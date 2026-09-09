# Spread probability map over PNNH, recomputed with the canonical SMC posterior.
#
# Why this script exists
# ----------------------
# Panel D of the thesis figure "burn_prob_models_modern" (probabilidad de propagacion)
# was computed with the legacy, pre-SMC hierarchical fit. The question it is being used
# to answer now is why the south of the park burns so much in panel E: is that driven by
# ignition (low elevation raising the lightning-ignition probability and dragging
# ignitions south) or by spread? To tell, panel D has to be recomputed with the
# canonical SMC-fitted posterior (docs/migration.md #7).
#
# This script recomputes the spread panel under BOTH posteriors, so the two are directly
# comparable. The escape panel is recomputed too, not because its fit changed (it did not)
# but because the loop in probability_maps.R assigned instead of accumulating until
# 2026-09-09, so the escape layer of the existing tiff is a single posterior draw rather
# than the posterior mean. The two ignition layers are unaffected and are read from that
# tiff for the drop-in remake of the full figure.
#
# What is computed
# ----------------
# For every pixel, the spread probability towards it, marginalising over the fire-level
# random effects. For each posterior draw i a single fire-level parameter vector is drawn
# from MVN(mu_i, V_i) on the unconstrained scale and mapped to the constrained support;
# probabilities are then averaged over draws. FWI is held at its mean on the spread scale
# (z = 0), as in the original script.
#
# Two variants per posterior:
#   * "static"      -- slope and wind terms set to zero. This is exactly what the original
#                      script computed, i.e. the drop-in remake of panel D. (The thesis
#                      caption says wind was fixed at 14.4 km/h, but the code that produced
#                      the figure did not include the wind term at all; see the loop below.)
#   * "directional" -- the most favourable direction: fire arriving straight upslope
#                      (sin of the terrain slope) with a 14.4 km/h wind blowing along the
#                      spread direction. This is the variant the caption describes, and it
#                      is where the slope/wind coefficients, the ones that moved most
#                      between the two fits, actually show up.
#
# Inputs : data/pnnh_images/pnnh_data_120m_buff_10000.tif
#          files/hierarchical_model/spread_model_samples.rds            (canonical, SMC)
#          files/hierarchical_model_legacy_preSMC/spread_model_samples.rds
#          files/ignition/escape_model_samples.rds
#          data/pnnh_images/pnnh_data_120m_buff_10000_ig-esc-spread-prob_FWIZ.tiff
#            (only for the two ignition layers of the full-figure remake)
# Outputs: files/fire_regime_simulation/spread_prob_map_120m.tif
#            (4 spread layers + the recomputed escprob)
#          fire_regime/figures/spread_prob_smc_vs_legacy.png/.pdf
#          fire_regime/figures/burn_prob_models_modern_smc.png/.pdf
#
# Runtime: ~30 min (2 posteriors x 12000 draws x ~1.1 M pixels x 2 variants, plus 8000
# escape draws).
# Run from the repo root:  Rscript fire_regime/spread_probability_map.R

library(terra)
library(rstan)
library(ggplot2)
library(tidyterra)
library(ggspatial)
library(viridis)
library(patchwork)

source(file.path("R", "config.R"))
source(file.path("R", "flammability_indices_functions.R"))

theme_set(theme_minimal())   # maps: white panel background, as in fire_regime/plots.R

set.seed(2026)

t_start <- Sys.time()
msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "|", ..., "\n")

dir.create(file.path("fire_regime", "figures"), showWarnings = FALSE)

# Figure size settings ----------------------------------------------------

a4h <- 29.7
a4w <- 21.0
margins <- 2.5
fig_width_max <- a4w - margins * 2
fig_height_max <- a4h - margins * 2

map_theme <- function() {
  theme(
    panel.border = element_blank(),
    panel.grid = element_blank(),
    axis.line = element_blank(),

    axis.text = element_text(size = 7),
    axis.title = element_blank(),

    plot.title = element_text(size = 9),
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8),

    strip.text = element_text(size = 9),
    strip.background = element_rect(fill = "white", color = "white")
  )
}

# Inverse-logit scaled between L and U, column-wise for a matrix. Copied from
# fire_regime/probability_maps.R so this script stands alone.
invlogit_scaled2 <- function(x, L, U) {
  if(is.matrix(x)) {
    out <- sapply(1:ncol(x), function(i) {
      plogis(x[, i]) * (U[i] - L[i]) + L[i]
    })
    return(out)
  } else {
    return(plogis(x) * (U - L) + L)
  }
}

# Constants for spread ----------------------------------------------------
# (identical to fire_regime/probability_maps.R; the parameter support must match the
#  one the sampler used, or the constrained draws are wrong)

n_veg <- 5
n_terrain <- 2
terrain_names <- c("slope", "wind")
nd_variables <- c("vfi", "tfi")

par_names <- c("intercept", nd_variables, terrain_names, "steps")
n_coef <- length(par_names)

ext_alpha <- 50
ext_beta <- 30

slope_sd <- fi_params$slope_term_sd

params_lower <- c(-ext_alpha, rep(0, n_coef - 2), 2)
params_upper <- c(ext_alpha, rep(ext_beta, n_coef - 2), 2000)
names(params_lower) <- names(params_upper) <- par_names
params_upper["slope"] <- ext_beta / slope_sd

support <- rbind(params_lower, params_upper)
colnames(support) <- names(params_lower) <- names(params_upper) <- par_names

stopifnot(all(support[2, ] > support[1, ]))

# Wind held at 14.4 km/h, standardised the way the landscapes are (divided by the
# regional sd, not centred; see data_prep landscape preparation).
wind_sd <- 1.464333
wind_mps <- 4.0            # 14.4 km/h
wind_spread <- wind_mps / wind_sd

# Data -------------------------------------------------------------------

msg("reading PNNH raster")

pnnh <- vect(file.path("data", "protected_areas", "apn_limites.shp"))
pnnh <- pnnh[pnnh$nombre == "Nahuel Huapi", ]
pnnh <- project(pnnh, "EPSG:5343")

pnnh_buff <- vect(file.path("data", "protected_areas", "pnnh_buff_10000.shp"))

pnnh_rast <- rast(file.path("data", "pnnh_images",
                            "pnnh_data_120m_buff_10000.tif"))

# Vegetation recoding (11 focal classes -> the 5 model classes; urban is taken as wet
# forest so its burn probability still responds to NDVI, as in probability_maps.R).
dveg <- readxl::read_excel(config$veg_equiv_xlsx, sheet = "Sheet2")
dveg$cnum2[dveg$class1 == "Urban"] <- 1
dveg$class2[dveg$class1 == "Urban"] <- "Wet forest"
dveg$veg_focal <- dveg$cnum1
dveg$veg_num <- dveg$cnum2

pnnh_df <- as.data.frame(values(pnnh_rast))
names(pnnh_df)[names(pnnh_df) == "veg"] <- "veg_focal"
pnnh_df <- dplyr::left_join(pnnh_df, dveg[, c("veg_focal", "veg_num")],
                            by = "veg_focal")

pnnh_rast$vegetation <- pnnh_df$veg_num
pnnh_rast$vfi <- vfi_calc(values(pnnh_rast$vegetation),
                          values(pnnh_rast$ndvi))
pnnh_rast$tfi <- tfi_calc(values(pnnh_rast$elevation),
                          values(pnnh_rast$aspect),
                          values(pnnh_rast$slope))
pnnh_rast$slope_spread <- sin(pnnh_rast$slope * pi / 180)

# distances to roads and human settlements, standardised as the escape model expects
pnnh_data_summary <- readRDS(file.path("data", "pnnh_images",
                                       "pnnh_data_summary.rds"))
pnnh_rast$drz <- (pnnh_rast$dist_roads / 1000 - pnnh_data_summary$dr_mean) /
  pnnh_data_summary$dr_sd
pnnh_rast$dhz <- (pnnh_rast$dist_humans / 1000 - pnnh_data_summary$dh_mean) /
  pnnh_data_summary$dh_sd

vfi <- values(pnnh_rast$vfi)[, 1]
tfi <- values(pnnh_rast$tfi)[, 1]
slope_term <- values(pnnh_rast$slope_spread)[, 1]
drz <- values(pnnh_rast$drz)[, 1]
dhz <- values(pnnh_rast$dhz)[, 1]

ok <- !is.na(vfi) & !is.na(tfi) & !is.na(slope_term)
msg("burnable pixels:", sum(ok), "of", length(ok))

vfi_ok <- vfi[ok]
tfi_ok <- tfi[ok]
slope_ok <- slope_term[ok]

# the escape model needs the two distances as well
ok_esc <- ok & !is.na(drz) & !is.na(dhz)
msg("pixels with distances too (escape):", sum(ok_esc))

# Spread probability ------------------------------------------------------

# Averages the spread probability over the posterior, marginalising the fire-level
# random effects (one draw of the random effects per posterior draw, as in the
# original script). Returns the two variants described in the header.
spread_prob_map <- function(smod, label) {

  npost <- dim(smod$fixef)[3]
  weight <- 1 / npost

  # sanity checks on the file's structure before spending an hour on it
  stopifnot(dimnames(smod$fixef)[[1]][1:n_coef] == par_names)
  stopifnot(dim(smod$rho)[1] == n_coef, dim(smod$rho)[3] == npost)

  p_static <- numeric(length(vfi_ok))
  p_dir <- numeric(length(vfi_ok))

  msg(label, ": ", npost, " posterior draws")

  for(i in 1:npost) {
    if(i %% 500 == 0) msg(label, ": draw", i, "/", npost)

    # mean of the fire-level effects at the unconstrained scale, at FWI = mean
    # (the "a" column; "b" is the FWI slope, so it drops out at z = 0)
    mu <- smod$fixef[1:n_coef, "a", i]

    sds <- sqrt(smod$fixef[1:n_coef, "s2", i])
    V <- diag(sds) %*% smod$rho[, , i] %*% diag(sds)

    ranef_unc <- matrix(mgcv::rmvn(1, mu, V), nrow = 1)
    colnames(ranef_unc) <- par_names
    ranef <- invlogit_scaled2(ranef_unc, support[1, ], support[2, ])

    lp <- ranef["intercept"] + vfi_ok * ranef["vfi"] + tfi_ok * ranef["tfi"]
    p_static <- p_static + plogis(lp) * weight

    # most favourable direction: straight upslope, wind blowing along the spread
    lp_dir <- lp + slope_ok * ranef["slope"] + wind_spread * ranef["wind"]
    p_dir <- p_dir + plogis(lp_dir) * weight
  }

  list(static = p_static, directional = p_dir)
}

# Escape probability ------------------------------------------------------

# Recomputed here only so panel C of the five-panel remake is a posterior mean. The
# escape layer of the existing tiff was written by the assignment bug in
# probability_maps.R (fixed 2026-09-09), so it is a single posterior draw. The escape
# fit itself did not change; this is the same logistic regression, accumulated properly.
escape_prob_map <- function() {
  escmod <- readRDS(file.path("files", "ignition", "escape_model_samples.rds"))

  esc_betas <- as.matrix(escmod, pars = c("b_vfi", "b_tfi",
                                          "b_drz", "b_dhz")) |> t()
  esc_intercept <- as.matrix(escmod, pars = "a") |> as.numeric()
  # no fwi effect included

  Xesc <- cbind(vfi[ok_esc], tfi[ok_esc], drz[ok_esc], dhz[ok_esc])

  npost <- ncol(esc_betas)
  weight <- 1 / npost
  stopifnot(nrow(esc_betas) == ncol(Xesc), length(esc_intercept) == npost)

  msg("escape: ", npost, " posterior draws")

  p <- numeric(nrow(Xesc))
  for(k in 1:npost) {
    if(k %% 500 == 0) msg("escape: draw", k, "/", npost)
    p <- p + plogis(esc_intercept[k] + Xesc %*% esc_betas[, k])[, 1] * weight
  }
  p
}

smod_smc <- readRDS(file.path("files", "hierarchical_model",
                              "spread_model_samples.rds"))
smod_leg <- readRDS(file.path("files", "hierarchical_model_legacy_preSMC",
                              "spread_model_samples.rds"))

res_smc <- spread_prob_map(smod_smc, "SMC")
res_leg <- spread_prob_map(smod_leg, "legacy")

rm(smod_smc, smod_leg); gc()

res_esc <- escape_prob_map()

# Assemble the output raster ----------------------------------------------

mk_layer <- function(x, nm, mask = ok) {
  full <- rep(NA_real_, length(mask))
  full[mask] <- x
  r <- rast(pnnh_rast[[1]])
  values(r) <- full
  names(r) <- nm
  r
}

out <- c(
  mk_layer(res_smc$static, "spreadprob_smc"),
  mk_layer(res_leg$static, "spreadprob_legacy"),
  mk_layer(res_smc$directional, "spreadprob_smc_dir"),
  mk_layer(res_leg$directional, "spreadprob_legacy_dir"),
  mk_layer(res_esc, "escprob", mask = ok_esc)
)

writeRaster(out, file.path("files", "fire_regime_simulation",
                           "spread_prob_map_120m.tif"), overwrite = TRUE)
msg("wrote files/fire_regime_simulation/spread_prob_map_120m.tif")

# Numbers worth printing: is the south really hotter under the new fit? -----

# Latitudinal profile inside the park, in 10 bands from south to north.
inside <- mask(out[[1:4]], pnnh)
yy <- yFromCell(inside, 1:ncell(inside))
band <- cut(yy, breaks = 10, labels = FALSE)   # 1 = southernmost, 10 = northernmost
prof <- do.call(rbind, lapply(names(inside), function(nm) {
  v <- values(inside[[nm]])[, 1] * 100
  data.frame(layer = nm,
             band = 1:10,
             mean = tapply(v, band, mean, na.rm = TRUE) |> as.numeric())
}))

cat("\n--- mean spread probability (%) by latitudinal band inside PNNH",
    "(band 1 = south, 10 = north) ---\n")
print(reshape(prof[, c("layer", "band", "mean")], idvar = "band",
              timevar = "layer", direction = "wide"), row.names = FALSE)

cat("\n--- overall means inside PNNH (%) ---\n")
print(round(sapply(names(inside),
                   function(nm) mean(values(inside[[nm]])[, 1], na.rm = TRUE) * 100), 2))

# Figures -----------------------------------------------------------------

bp_vir <- "F"
bp_begin <- 1
bp_end <- 0.1
maxcell <- 100000
park_contour <- "black"
park_lwd <- 0.2

# One map panel, styled like the thesis figure.
map_panel <- function(lyr, title, limits = NULL, option = bp_vir,
                      begin = bp_begin, end = bp_end, name = "%",
                      axes = FALSE) {
  p <- ggplot() +
    geom_spatraster(data = lyr, maxcell = maxcell)

  if(option == "diff") {
    p <- p + scale_fill_gradient2(low = "#2166ac", mid = "white",
                                  high = "#b2182b", midpoint = 0,
                                  na.value = "transparent", name = name,
                                  limits = limits)
  } else {
    p <- p + scale_fill_viridis(option = option, na.value = "transparent",
                                begin = begin, end = end, name = name,
                                limits = limits)
  }

  p <- p +
    geom_spatvector(data = pnnh, fill = NA, color = park_contour,
                    linewidth = park_lwd) +
    scale_x_continuous(breaks = seq(-72, -71, by = 0.5), expand = c(0, 0),
                       labels = function(x) sprintf("%.1f°", x)) +
    scale_y_continuous(breaks = seq(-41.5, -40.5, by = 0.5), expand = c(0, 0),
                       labels = function(x) sprintf("%.1f°", x)) +
    coord_sf() +
    map_theme() +
    theme(panel.grid = element_blank(),
          legend.key.width = unit(2, "mm")) +
    labs(title = title)

  if(!axes) {
    p <- p + theme(axis.text = element_blank(), axis.ticks = element_blank())
  } else {
    p <- p + theme(axis.ticks = element_line(linewidth = 0.1, color = "gray20"))
  }
  p
}

pct <- out * 100

# ---- comparison figure: legacy vs SMC, static and directional, plus differences
lim_static <- range(values(pct[[c("spreadprob_smc", "spreadprob_legacy")]]),
                    na.rm = TRUE)
lim_dir <- range(values(pct[[c("spreadprob_smc_dir", "spreadprob_legacy_dir")]]),
                 na.rm = TRUE)

d_static <- pct[["spreadprob_smc"]] - pct[["spreadprob_legacy"]]
d_dir <- pct[["spreadprob_smc_dir"]] - pct[["spreadprob_legacy_dir"]]
lim_d_static <- c(-1, 1) * max(abs(values(d_static)), na.rm = TRUE)
lim_d_dir <- c(-1, 1) * max(abs(values(d_dir)), na.rm = TRUE)

cmp <-
  map_panel(pct[["spreadprob_legacy"]], "A. Static, legacy (pre-SMC) fit",
            limits = lim_static, axes = TRUE) +
  map_panel(pct[["spreadprob_smc"]], "B. Static, SMC fit", limits = lim_static) +
  map_panel(d_static, "C. Static, SMC - legacy",
            limits = lim_d_static, option = "diff", name = "pp") +
  map_panel(pct[["spreadprob_legacy_dir"]],
            "D. Upslope + 14.4 km/h wind,\nlegacy fit",
            limits = lim_dir, axes = TRUE) +
  map_panel(pct[["spreadprob_smc_dir"]],
            "E. Upslope + 14.4 km/h wind,\nSMC fit", limits = lim_dir) +
  map_panel(d_dir, "F. Directional, SMC - legacy",
            limits = lim_d_dir, option = "diff", name = "pp") +
  plot_layout(ncol = 3, byrow = TRUE) &
  theme(plot.margin = margin(1, 1, 1, 1, unit = "mm"),
        legend.key.height = unit(9, "mm"),
        legend.margin = margin(0, 0, 0, 0, unit = "mm"))

ggsave(file.path("fire_regime", "figures", "spread_prob_smc_vs_legacy.png"),
       plot = cmp, width = fig_width_max, height = 14.5, units = "cm", bg = "white")
ggsave(file.path("fire_regime", "figures", "spread_prob_smc_vs_legacy.pdf"),
       plot = cmp, width = fig_width_max, height = 14.5, units = "cm")
msg("wrote fire_regime/figures/spread_prob_smc_vs_legacy.png")

# ---- drop-in remake of the full five-panel figure, with panel D from the SMC fit
old_tiff <- file.path("data", "pnnh_images",
                      "pnnh_data_120m_buff_10000_ig-esc-spread-prob_FWIZ.tiff")
burn_map <- file.path("files", "fire_regime_simulation", "burn_prob_map-modern.tif")

if(file.exists(old_tiff) && file.exists(burn_map)) {
  old <- rast(old_tiff)
  ig <- old[[c("igprob_h", "igprob_l")]] * 100
  bp_modern_lyr <- rast(burn_map) * 100

  titles <- c("A. Probabilidad relativa de\nignición por humanos",
              "B. Probabilidad relativa de\nignición por rayos",
              "C. Probabilidad de escape\n(recalculada)",
              "D. Probabilidad de\npropagación (SMC)")

  ll <- list(
    map_panel(ig[[1]], titles[1]),
    map_panel(ig[[2]], titles[2]),
    map_panel(pct[["escprob"]], titles[3]),
    map_panel(pct[["spreadprob_smc"]], titles[4])
  )

  bp_modern <- map_panel(bp_modern_lyr, "E. Probabilidad de quema\nanual (1999-2022)",
                         axes = TRUE) +
    geom_spatvector(data = pnnh_buff, fill = NA, color = "gray20",
                    linewidth = park_lwd, alpha = 0.6) +
    ggspatial::annotation_scale(
      location = "tr", height = unit(0.7, "mm"),
      bar_cols = c("grey60", "white"), text_col = "black",
      text_cex = 0.5, line_width = 0.2
    ) +
    annotation_north_arrow(
      location = "tl", which_north = "true",
      style = north_arrow_orienteering(
        line_width = 0.2, line_col = "black",
        fill = c("grey60", "white"), text_col = "transparent",
        text_face = NULL, text_size = 0, text_angle = 0
      ),
      width = unit(3, "mm"), height = unit(3, "mm"))

  bp1 <- ll[[1]] + ll[[2]] + ll[[3]] + ll[[4]] + bp_modern +
    plot_layout(ncol = 2, byrow = TRUE)

  ggsave(file.path("fire_regime", "figures", "burn_prob_models_modern_smc.png"),
         plot = bp1, width = fig_width_max * 0.7, height = fig_height_max - 3,
         units = "cm", bg = "white")
  ggsave(file.path("fire_regime", "figures", "burn_prob_models_modern_smc.pdf"),
         plot = bp1, width = fig_width_max * 0.7, height = fig_height_max - 3,
         units = "cm")
  msg("wrote fire_regime/figures/burn_prob_models_modern_smc.png")
} else {
  msg("SKIPPED the five-panel remake: missing", old_tiff, "or", burn_map)
}

msg("done in", round(difftime(Sys.time(), t_start, units = "mins"), 1), "min")
