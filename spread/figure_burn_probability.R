# Figure 5 — burn-probability maps for four focal fires.
#
# Per fire: `nsim` simulations under the FITTED random effect and `nsim` under
# a NEWLY SIMULATED one, always on the same landscape and the same ignition
# point, always from the full posterior with one draw per simulated fire (never
# the posterior mean, never a thinned subset). Burn probability per cell is the
# fraction of simulations that burned it; the observed perimeter is drawn over
# it. Eight panels, 4 fires x 2 random-effect modes.
#
# The simulation block is lifted from spread/hierarchical_fit.R (the "Assessing
# model fit" section, which builds `ranef_fit` / `ranef_sim` and loops over
# fires) — the only change is that a per-cell burn count is accumulated instead
# of reducing each simulation to a `metrics_table` row. Do not re-derive the
# MVLN -> invlogit_scaled chain from scratch.
#
#   THE TRAP: `draws$ranef` row 6 (`steps`) is stored on the NATURAL scale
#   while rows 1-5 are on the logit scale, so the fitted random effects must be
#   back-transformed on rows 1:(n_coef - 1) only. The simulated ones come out
#   of `rmvn()` entirely on the logit scale, so all six rows are transformed
#   there, with `Upar["steps"]` set per draw from `draws$stepsU`.
#
# The four fires and why they were chosen: manuscript-spread/ijwf/designing.txt
# -> Fig. 5. They give a monotone gradient of posterior-median overlap
# (0.84 / 0.64 / 0.35 / 0.27 against a 57-fire median of 0.535), three orders
# of magnitude in size, and the strongest under- and overestimate in the set.
#
# Two stages, toggled below: the run (a few minutes on 8 cores) writes a
# wrapped-raster .rds, and the plot reads that back, so the figure can be
# retuned without re-simulating.

library(FireSpread)
library(terra)
library(parallel)
library(ggplot2)
library(tidyterra)
library(viridis)
library(patchwork)
theme_set(theme_bw())

source(file.path("R", "config.R"))

# Settings ----------------------------------------------------------------

do_simulate <- TRUE
do_plot <- TRUE

nsim <- 1000        # per fire and per random-effect mode
cores <- 8
seed <- 20260828

# In the order the panels tell the story: the model nails a fire, holds up on
# the largest one in the record, then fails in both directions on a mid-sized
# and a small one.
fire_ids <- c("1999_25j", "2015_50", "2004_23", "2002_34")

lands_dir <- file.path("data", "focal_fires", "landscapes")
gee_dir <- file.path("data", "focal_fires", "raw_gee")
maps_file <- file.path("files", "hierarchical_model", "burn_probability_maps.rds")
fig_dir <- file.path("manuscript-spread", "figures")

# Model constants, as in spread/hierarchical_fit.R -------------------------

n_veg <- 5
nd_variables <- c("vfi", "tfi")
terrain_variables <- c("elevation", "wdir", "wspeed")
par_names <- c("intercept", "vfi", "tfi", "slope", "wind", "steps")
n_coef <- length(par_names)
upper_limit <- 1

ext_alpha <- 50; ext_beta <- 30; stepsL <- 2
fi_params <- readRDS(file.path("data", "flammability_indices",
                               "flammability_indices.rds"))
Lpar <- c(-ext_alpha, rep(0, n_coef - 2), stepsL)
Upar <- c(ext_alpha, rep(ext_beta, n_coef - 2), NA)
names(Lpar) <- names(Upar) <- par_names
Upar["slope"] <- ext_beta / fi_params$slope_term_sd

# Inverse-logit scaled between L and U, column-wise when x is a matrix.
invlogit_scaled2 <- function(x, L, U) {
  if (is.matrix(x)) {
    return(sapply(1:ncol(x), function(i) plogis(x[, i]) * (U[i] - L[i]) + L[i]))
  }
  plogis(x) * (U - L) + L
}


# Stage 1 — simulate ------------------------------------------------------

if (do_simulate) {

set.seed(seed)

draws <- readRDS(file.path("files", "hierarchical_model",
                           "spread_model_samples.rds"))
npost <- dim(draws$fixef)[3]
stopifnot(all(fire_ids %in% dimnames(draws$ranef)[[2]]))

# Each fire's standardized FWI, the covariate the population mean is a function
# of. Same source and same scaling as the fit.
fwi_scale <- readRDS(file.path("files", "hierarchical_model",
                               "fwi_mean_sd_spread.rds"))
fwi_data <- read.csv(file.path(
  "data", "climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ2.csv"))
stopifnot(all(fire_ids %in% fwi_data$fire_id))   # none of the four is a split fire
fwi_z <- (fwi_data$fwi_fort_expquad[match(fire_ids, fwi_data$fire_id)] -
            fwi_scale$fwi_mean) / fwi_scale$fwi_sd
names(fwi_z) <- fire_ids

#' Fitted random effects for one fire, on the simulator's scale
#'
#' Rows 1:(n_coef - 1) are stored on the logit scale and are back-transformed;
#' row `steps` is already natural and is left alone. Returns nsim x n_coef.
ranef_fitted <- function(fire_id, ids) {
  r <- draws$ranef[, fire_id, ids]                       # n_coef x nsim
  out <- t(r)
  out[, 1:(n_coef - 1)] <- invlogit_scaled2(t(r[1:(n_coef - 1), ]),
                                            Lpar, Upar)
  colnames(out) <- par_names
  out
}

#' New random effects for one fire, drawn from the population distribution
#'
#' One draw of the hyperparameters per simulated fire, so both hyperparameter
#' and between-fire uncertainty are carried. Everything comes out of `rmvn()`
#' on the logit scale, `steps` included, so all n_coef rows are transformed —
#' with that draw's own upper bound for `steps`.
ranef_simulated <- function(fire_id, ids) {
  X <- cbind(1, fwi_z[fire_id])
  out <- matrix(NA_real_, length(ids), n_coef,
                dimnames = list(NULL, par_names))
  Upar_ <- Upar
  for (k in seq_along(ids)) {
    jj <- ids[k]
    mu <- X %*% t(draws$fixef[1:n_coef, c("a", "b"), jj])
    sds <- sqrt(draws$fixef[1:n_coef, "s2", jj])
    V <- diag(sds) %*% draws$rho[, , jj] %*% diag(sds)
    Upar_["steps"] <- draws$stepsU[jj]
    out[k, ] <- invlogit_scaled2(matrix(mgcv::rmvn(1, mu, V), nrow = 1),
                                 Lpar, Upar_)
  }
  out
}

#' Per-cell burn counts over a matrix of parameter vectors (one row per fire)
#'
#' Chunked so each worker accumulates its own integer count matrix rather than
#' returning one burn mask per simulation — for the 2917 x 3577 landscape of
#' 2015_50 that is the difference between 42 MB and 42 GB of return traffic.
burn_counts <- function(pars, veg, nd, terrain, ig) {
  grp <- split(seq_len(nrow(pars)),
               cut(seq_len(nrow(pars)), cores, labels = FALSE))
  res <- mclapply(grp, function(g) {
    acc <- matrix(0L, nrow(veg), ncol(veg))
    for (i in g) {
      p <- pars[i, ]
      acc <- acc + simulate_fire(
        layer_vegetation = veg,
        layer_nd = nd,
        layer_terrain = terrain,
        coef_intercepts = rep(p["intercept"], n_veg),
        coef_nd = p[nd_variables],
        coef_terrain = p[c("slope", "wind")],
        ignition_cells = ig,        # already 0-indexed on disk
        upper_limit = upper_limit,
        steps = p["steps"]
      )
    }
    acc
  }, mc.cores = cores)
  bad <- vapply(res, inherits, logical(1), "try-error")
  if (any(bad)) stop(sum(bad), " chunks failed")
  Reduce(`+`, res)
}

maps <- vector("list", length(fire_ids))
names(maps) <- fire_ids

for (f in fire_ids) {
  cat("\n==", f, "\n")
  l <- readRDS(file.path(lands_dir, paste0(f, ".rds")))
  land <- l$landscape

  veg <- matrix(as.integer(land[, , "veg"]), dim(land)[1], dim(land)[2])
  nd <- land[, , nd_variables]
  terrain <- land[, , terrain_variables]

  ids <- sample.int(npost, nsim, replace = FALSE)   # shared by the two modes
  t0 <- Sys.time()
  cnt_fit <- burn_counts(ranef_fitted(f, ids), veg, nd, terrain, l$ig_rowcol)
  cnt_sim <- burn_counts(ranef_simulated(f, ids), veg, nd, terrain, l$ig_rowcol)
  cat("  ", nsim, "x2 simulations in",
      round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")

  obs <- l$burned_layer

  ## Crop to what is actually drawn: the union of the observed fire and every
  ## cell either mode ever burned, padded. The focal landscapes are the big
  ## export rectangles, so a 20 ha fire is a speck in one of them.
  hit <- (obs > 0) | (cnt_fit > 0) | (cnt_sim > 0)
  rr <- range(which(apply(hit, 1, any)))
  cc <- range(which(apply(hit, 2, any)))
  pad <- max(5, round(0.06 * max(diff(rr), diff(cc))))
  r1 <- max(rr[1] - pad, 1); r2 <- min(rr[2] + pad, nrow(veg))
  c1 <- max(cc[1] - pad, 1); c2 <- min(cc[2] + pad, ncol(veg))

  template <- rast(file.path(gee_dir, paste0("fire_data_raw_", f, ".tif")))[[1]]
  stopifnot(nrow(template) == nrow(veg), ncol(template) == ncol(veg))
  half <- res(template)[1] / 2
  template <- crop(template, ext(xFromCol(template, c1) - half,
                                 xFromCol(template, c2) + half,
                                 yFromRow(template, r2) - half,
                                 yFromRow(template, r1) + half))

  sub <- function(m) m[r1:r2, c1:c2]
  as_r <- function(m) rast_from_mat(m, template)

  prob_fit <- as_r(sub(cnt_fit) / nsim); names(prob_fit) <- "p"
  prob_sim <- as_r(sub(cnt_sim) / nsim); names(prob_sim) <- "p"

  # Background: burnable vs not, the layer every map in this project draws under
  burnable <- as_r(ifelse(sub(veg) == 99, 2L, 1L))
  levels(burnable) <- data.frame(value = 1:2,
                                 class = c("Burnable", "Non-burnable"))
  names(burnable) <- "class"

  obs_r <- as_r(sub(obs))
  obs_r[obs_r == 0] <- NA
  obs_poly <- as.polygons(obs_r, dissolve = TRUE, na.rm = TRUE)

  ig <- l$ig_rowcol + 1L   # undo the 0-indexing for terra
  ig_pt <- vect(cbind(xFromCol(template, ig[2, ] - c1 + 1L),
                      yFromRow(template, ig[1, ] - r1 + 1L)),
                type = "points", crs = crs(template))

  maps[[f]] <- list(
    fire_id = f,
    prob_fit = wrap(prob_fit), prob_sim = wrap(prob_sim),
    burnable = wrap(burnable), obs_poly = wrap(obs_poly), ig_pt = wrap(ig_pt),
    obs_cells = sum(obs > 0),
    mean_size_fit = sum(cnt_fit) / nsim,
    mean_size_sim = sum(cnt_sim) / nsim,
    nsim = nsim
  )

  cat("   observed", maps[[f]]$obs_cells, "cells | mean simulated:",
      round(maps[[f]]$mean_size_fit), "(fitted) /",
      round(maps[[f]]$mean_size_sim), "(simulated ranef)\n")

  rm(l, land, veg, nd, terrain, cnt_fit, cnt_sim); gc()
}

saveRDS(maps, maps_file)
cat("\nsaved", maps_file, "\n")

}


# Stage 2 — the figure ----------------------------------------------------

if (do_plot) {

maps <- readRDS(maps_file)
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# Aesthetics follow the burn-probability maps made for the thesis defence
# (`fire regime simulations/plots_defensa*.R` in the old repo): a two-class
# burnable/non-burnable base layer, the probability surface over it through
# ggnewscale, the fire outlined, and the ignition point as a white dot.
bg_colors <- c("Burnable" = "grey86", "Non-burnable" = "grey55")
obs_color <- "black"
prob_option <- "A"        # magma
prob_begin <- 0.08
prob_end <- 0.98

map_theme <- function() {
  theme(
    panel.border = element_rect(color = "grey30", fill = NA, linewidth = 0.3),
    panel.grid = element_blank(),
    axis.line = element_blank(),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    axis.title.x = element_blank(),
    axis.title.y = element_text(size = 8, lineheight = 1.05,
                                margin = margin(r = 1, unit = "mm")),
    plot.title = element_text(size = 8, hjust = 0,
                              margin = margin(b = 1, unit = "mm")),
    plot.margin = margin(1, 1, 1, 1, unit = "mm"),
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8)
  )
}

#' One panel. `ylab` is used as the row label, so it is only passed for the
#' left-hand (fitted) panel of each fire.
panel <- function(m, mode, title, ylab = NULL) {
  prob <- unwrap(if (mode == "fit") m$prob_fit else m$prob_sim)
  prob[prob == 0] <- NA          # unburned cells show the base layer instead
  obs <- unwrap(m$obs_poly)

  ggplot() +
    geom_spatraster(data = unwrap(m$burnable), maxcell = 5e6,
                    show.legend = FALSE) +
    scale_fill_manual(values = bg_colors, na.value = "transparent",
                      na.translate = FALSE, name = NULL) +
    ggnewscale::new_scale_fill() +

    geom_spatraster(data = prob, maxcell = 5e6) +
    scale_fill_viridis(option = prob_option, begin = prob_begin,
                       end = prob_end, limits = c(0, 1),
                       na.value = "transparent",
                       name = "Burn\nprobability") +

    # The observed perimeter, haloed so it reads over both ends of the magma
    # ramp — a plain black line vanishes on the unburned-but-reachable cells.
    geom_spatvector(data = obs, fill = NA, color = "white", linewidth = 0.55) +
    geom_spatvector(data = obs, fill = NA, color = obs_color, linewidth = 0.22) +
    geom_spatvector(data = unwrap(m$ig_pt), fill = "white", color = "black",
                    shape = 21, size = 1.4, stroke = 0.5) +

    ggspatial::annotation_scale(
      location = "br", height = unit(1.2, "mm"), width_hint = 0.28,
      bar_cols = c("grey20", "white"), text_col = "grey20",
      text_cex = 0.55, line_width = 0.3, pad_x = unit(1, "mm"),
      pad_y = unit(1, "mm")) +

    scale_x_continuous(expand = c(0, 0)) +
    scale_y_continuous(expand = c(0, 0)) +
    coord_sf(expand = FALSE) +
    map_theme() +
    labs(title = title, y = ylab)
}

panels <- list()
letters_ <- LETTERS[1:(2 * length(maps))]
k <- 0
for (f in names(maps)) {
  m <- maps[[f]]
  ha <- m$obs_cells * 0.09
  dig <- if (ha < 100) 1 else 0
  lab <- sprintf("%s - %s ha", f,
                 formatC(ha, format = "f", big.mark = ",", digits = dig))
  for (mode in c("fit", "sim")) {
    k <- k + 1
    panels[[k]] <- panel(
      m, mode,
      sprintf("(%s) %s random effect", letters_[k],
              if (mode == "fit") "fitted" else "simulated"),
      ylab = if (mode == "fit") sub(" - ", "\n", lab, fixed = TRUE) else NULL)
  }
}

fig <- wrap_plots(panels, ncol = 2, byrow = TRUE) +
  plot_layout(guides = "collect") &
  theme(legend.position = "right")

ggsave(file.path(fig_dir, "fig5_burn_probability.png"), plot = fig,
       width = 15, height = 24, units = "cm", dpi = 400, bg = "white")
ggsave(file.path(fig_dir, "fig5_burn_probability.pdf"), plot = fig,
       width = 15, height = 24, units = "cm", bg = "white")

cat("wrote", file.path(fig_dir, "fig5_burn_probability.png"), "and .pdf\n")

}
