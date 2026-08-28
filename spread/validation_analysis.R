# Spread model validation — the analysis and its figures.
#
# Brings the two sides together: 64,836 simulated fires from
# spread/validation_simulate.R and 241 observed ones from
# spread/validation_observed.R. Everything here is pattern comparison, never
# point prediction (docs/spread.md -> "Stage 3 — validation").
#
# Four analyses, in the order the design lists them:
#   1. the regional size distribution, as a Q-Q in log10(area);
#   2. shape metrics conditioned on size — elongation both ways, compactness,
#      hull fill, and orientation relative to the fixed 293-degree wind;
#   3. the per-fire spatial signature (`b_vfi`, `b_tfi`) conditioned on size;
#   4. the same metrics conditioned on FWI, plus an FWI-quartile table.
#
# Plot style, as designed: simulated fires as a 2-D density (hex bins — raw
# points do not work at 6e4, let alone the 1e6 the design anticipated),
# observed fires as points, and a GAM smoother on each. Conditioning on size or
# FWI is what defends the comparison against any residual mismatch in the
# marginals.
#
# Runs in well under a minute; writes into files/spread_validation/figures/.

library(ggplot2)
library(hexbin)     # geom_hex's binning backend; ggplot2 only suggests it
library(patchwork)
library(viridis)
theme_set(theme_bw())
source(file.path("R", "spread_validation_functions.R"))

# Settings ----------------------------------------------------------------

out_dir <- file.path("files", "spread_validation")
fig_dir <- file.path(out_dir, "figures")
wind_bearing <- 293 * pi / 180   # the fixed direction every landscape carries
size_breaks <- c(0, 100, 1000, Inf)
size_labels <- c("< 100 ha", "100-1000 ha", "> 1000 ha")

dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# Data --------------------------------------------------------------------

simr <- readRDS(file.path(out_dir, "simulated_fires.rds"))
sim <- simr$fires
obs_sig <- readRDS(file.path(out_dir, "observed_signature.rds"))
obs_shp <- readRDS(file.path(out_dir, "observed_shape.rds"))
stopifnot(identical(obs_sig$fire_id, obs_shp$fire_id))

fwi_scale <- readRDS(file.path("files", "hierarchical_model",
                               "fwi_mean_sd_spread.rds"))

# The simulated fires were measured against their own terrain-steered wind
# (`elong_wind`); the observed ones cannot be, so both sides also get
# elongation along the fixed 293 degrees. For the simulated side that is
# recovered post hoc from the covariance entries, which is exactly why
# validation_simulate.R saved them.
sim$elong_fixed <- mapply(elongation_along, sim$cov_ee, sim$cov_nn, sim$cov_en,
                          MoreArgs = list(bearing = wind_bearing))

# Angular distance to the 113/293 axis, in degrees (0 = perfectly wind-aligned,
# 90 = perpendicular). `orientation` is a bearing mod 180, so the axis is 113.
axis_dev <- function(ori) pmin(abs(ori - 113), 180 - abs(ori - 113))
sim$axis_dev <- axis_dev(sim$orientation)
obs_shp$axis_dev <- axis_dev(obs_shp$orientation)

both <- function(metric, sim_v, obs_v) {
  rbind(
    data.frame(set = "Simulated", metric = metric,
               log_area = log10(sim$area_ha), fwi_z = sim$fwi_z, value = sim_v),
    data.frame(set = "Observed", metric = metric,
               log_area = log10(obs_shp$area_ha),
               fwi_z = (obs_sig$fwi - fwi_scale$fwi_mean) / fwi_scale$fwi_sd,
               value = obs_v)
  )
}

d <- rbind(
  both("Elongation", sim$elongation, obs_shp$elongation),
  both("Elongation along 293°", sim$elong_fixed, obs_shp$elong_fixed),
  both("Compactness", sim$compactness, obs_shp$compactness),
  both("Convex-hull fill", sim$hull_fill, obs_shp$hull_fill),
  both("Deviation from wind axis (°)", sim$axis_dev, obs_shp$axis_dev),
  both("b_vfi", sim$b_vfi, obs_sig$b_vfi),
  both("b_tfi", sim$b_tfi, obs_sig$b_tfi)
)
d$set <- factor(d$set, levels = c("Simulated", "Observed"))
d <- d[is.finite(d$value), ]

shape_metrics <- c("Elongation", "Elongation along 293°", "Compactness",
                   "Convex-hull fill", "Deviation from wind axis (°)")
sig_metrics <- c("b_vfi", "b_tfi")


# Panel builder -----------------------------------------------------------

# `b_vfi`/`b_tfi` have very heavy tails on both sides — the simulated ones run
# to +-250 — so those two panels are trimmed to the pooled 1-99 % range. The
# trim is applied to the binning and the smoothers as well as to the axis, not
# just to what is drawn: hex bins spanning the untrimmed range are so tall that
# the visible ones are single slabs, and a GAM mean over a +-250 tail is not a
# curve anyone should read. Everything outside stays in the tables, which are
# medians and therefore unaffected.
ylims <- function(metric) {
  v <- d$value[d$metric == metric]
  if (metric %in% sig_metrics) unname(quantile(v, c(0.01, 0.99))) else range(v)
}

metric_panel <- function(metric, xvar, xlab, show_legend = FALSE) {
  dd <- d[d$metric == metric, ]
  dd$x <- dd[[xvar]]
  dd <- dd[is.finite(dd$x), ]
  yl <- ylims(metric)
  dd <- dd[dd$value >= yl[1] & dd$value <= yl[2], ]
  ds <- dd[dd$set == "Simulated", ]
  do <- dd[dd$set == "Observed", ]

  ggplot(mapping = aes(x, value)) +
    geom_hex(data = ds, bins = 55, aes(fill = after_stat(count))) +
    scale_fill_viridis(option = "G", trans = "log10", direction = -1,
                       name = "Simulated\nfires", guide = if (show_legend)
                         guide_colourbar() else "none") +
    geom_point(data = do, colour = "#c1272d", size = 0.55, alpha = 0.65) +
    geom_smooth(data = ds, method = "gam", formula = y ~ s(x, bs = "cs"),
                colour = "black", linewidth = 0.6, se = FALSE) +
    geom_smooth(data = do, method = "gam", formula = y ~ s(x, bs = "cs"),
                colour = "#c1272d", linewidth = 0.6, se = FALSE) +
    coord_cartesian(ylim = yl) +
    labs(x = xlab, y = metric) +
    theme(panel.grid = element_blank(),
          axis.title = element_text(size = 9),
          axis.text = element_text(size = 8),
          legend.title = element_text(size = 8),
          legend.text = element_text(size = 7))
}

assemble <- function(metrics, xvar, xlab, file, width, height) {
  ps <- lapply(seq_along(metrics), function(i)
    metric_panel(metrics[i], xvar, xlab, show_legend = i == 1))
  fig <- wrap_plots(ps, ncol = 2) + plot_layout(guides = "collect") &
    theme(legend.position = "right")
  ggsave(file.path(fig_dir, file), plot = fig, width = width, height = height,
         units = "cm", dpi = 350, bg = "white")
  cat("wrote", file.path(fig_dir, file), "\n")
}


# 1. Size distribution ----------------------------------------------------

lo <- log10(obs_shp$area_ha)
ls <- log10(sim$area_ha)
pp <- ppoints(length(lo))
qq <- data.frame(obs = quantile(lo, pp, type = 8),
                 sim = quantile(ls, pp, type = 8))

ks <- suppressWarnings(stats::ks.test(ls, lo))

p_qq <- ggplot(qq, aes(sim, obs)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey60", linewidth = 0.4) +
  geom_point(size = 0.9, colour = "#c1272d") +
  labs(x = expression(paste("Simulated ", log[10], " area (ha)")),
       y = expression(paste("Observed ", log[10], " area (ha)"))) +
  theme(panel.grid = element_blank())

p_dens <- ggplot(mapping = aes(log_area, after_stat(density))) +
  geom_histogram(data = data.frame(log_area = ls), bins = 60,
                 fill = "grey70", colour = NA) +
  # Default (nrd0) bandwidth: the SJ selector over 241 fires resolves bumps
  # that are sampling noise at this n.
  geom_density(data = data.frame(log_area = lo), colour = "#c1272d",
               linewidth = 0.7) +
  labs(x = expression(paste(log[10], " area (ha)")), y = "Density") +
  theme(panel.grid = element_blank())

ggsave(file.path(fig_dir, "size_distribution.png"),
       plot = p_dens + p_qq, width = 18, height = 8, units = "cm",
       dpi = 350, bg = "white")
cat("wrote", file.path(fig_dir, "size_distribution.png"), "\n")


# 2-4. The conditioned panels ---------------------------------------------

assemble(shape_metrics, "log_area", expression(paste(log[10], " area (ha)")),
         "shape_by_size.png", 20, 22)
assemble(sig_metrics, "log_area", expression(paste(log[10], " area (ha)")),
         "signature_by_size.png", 20, 9)
assemble(c(shape_metrics, sig_metrics), "fwi_z", "FWI anomaly (standardized)",
         "metrics_by_fwi.png", 20, 30)


# Report ------------------------------------------------------------------

sim$size_class <- cut(sim$area_ha, size_breaks, labels = size_labels)
obs_shp$size_class <- cut(obs_shp$area_ha, size_breaks, labels = size_labels)
obs_sig$size_class <- obs_shp$size_class

cat("\n== 1. size distribution ==\n")
cat("observed n =", length(lo), "| simulated n =", length(ls), "\n")
cat("KS D =", round(ks$statistic, 3), "(p =", format.pval(ks$p.value), ")\n")
print(round(rbind(observed = quantile(obs_shp$area_ha, c(.05, .25, .5, .75, .95, 1)),
                  simulated = quantile(sim$area_ha, c(.05, .25, .5, .75, .95, 1))), 1))
cat("Read with the truncation in mind: the simulated set is conditioned on",
    ">= 10 ha,\nand the observed record is what the mapping caught over",
    "1999-2022, not a sample\nof the same generative process.\n")

by_class <- function(x, g, f = median) round(tapply(x, g, f, na.rm = TRUE), 3)

cat("\n== 2. shape, by size class ==\n")
shape_tab <- rbind(
  obs_elongation = by_class(obs_shp$elongation, obs_shp$size_class),
  sim_elongation = by_class(sim$elongation, sim$size_class),
  obs_elong_293 = by_class(obs_shp$elong_fixed, obs_shp$size_class),
  sim_elong_293 = by_class(sim$elong_fixed, sim$size_class),
  sim_elong_wind = by_class(sim$elong_wind, sim$size_class),
  obs_compactness = by_class(obs_shp$compactness, obs_shp$size_class),
  sim_compactness = by_class(sim$compactness, sim$size_class),
  obs_hull_fill = by_class(obs_shp$hull_fill, obs_shp$size_class),
  sim_hull_fill = by_class(sim$hull_fill, sim$size_class),
  obs_frac_aligned = by_class(obs_shp$axis_dev <= 30, obs_shp$size_class, mean),
  sim_frac_aligned = by_class(sim$axis_dev <= 30, sim$size_class, mean)
)
print(shape_tab)
cat("(frac_aligned: within 30 deg of the 113/293 axis; 0.333 under a uniform",
    "orientation)\n")

cat("\n== 3. signature, by size class ==\n")
sig_tab <- rbind(
  obs_b_vfi = by_class(obs_sig$b_vfi, obs_sig$size_class),
  sim_b_vfi = by_class(sim$b_vfi, sim$size_class),
  obs_b_tfi = by_class(obs_sig$b_tfi, obs_sig$size_class),
  sim_b_tfi = by_class(sim$b_tfi, sim$size_class),
  obs_frac_vfi_pos = by_class(obs_sig$b_vfi > 0, obs_sig$size_class, mean),
  sim_frac_vfi_pos = by_class(sim$b_vfi > 0, sim$size_class, mean),
  obs_frac_tfi_pos = by_class(obs_sig$b_tfi > 0, obs_sig$size_class, mean),
  sim_frac_tfi_pos = by_class(sim$b_tfi > 0, sim$size_class, mean)
)
print(sig_tab)

cat("\n== 4. FWI quartiles ==\n")
# Quartiles of the observed FWI, applied to both sides so the bins are the same.
obs_z <- (obs_sig$fwi - fwi_scale$fwi_mean) / fwi_scale$fwi_sd
qbr <- quantile(obs_z, c(0, .25, .5, .75, 1), na.rm = TRUE)
qlab <- c("Q1 (low)", "Q2", "Q3", "Q4 (high)")
obs_q <- cut(obs_z, qbr, labels = qlab, include.lowest = TRUE)
sim_q <- cut(sim$fwi_z, qbr, labels = qlab, include.lowest = TRUE)
fwi_tab <- rbind(
  n_obs = tapply(rep(1, length(obs_q)), obs_q, sum),
  obs_elongation = by_class(obs_shp$elongation, obs_q),
  sim_elongation = by_class(sim$elongation, sim_q),
  obs_b_vfi = by_class(obs_sig$b_vfi, obs_q),
  sim_b_vfi = by_class(sim$b_vfi, sim_q),
  obs_b_tfi = by_class(obs_sig$b_tfi, obs_q),
  sim_b_tfi = by_class(sim$b_tfi, sim_q),
  obs_median_ha = by_class(obs_shp$area_ha, obs_q),
  sim_median_ha = by_class(sim$area_ha, sim_q)
)
print(fwi_tab)
cat("Simulated fires outside the observed FWI range:",
    sum(is.na(sim_q)), "of", nrow(sim), "\n")

saveRDS(list(ks = ks, shape = shape_tab, signature = sig_tab, fwi = fwi_tab,
             size_quantiles = list(
               observed = quantile(obs_shp$area_ha, c(.05, .25, .5, .75, .95, 1)),
               simulated = quantile(sim$area_ha, c(.05, .25, .5, .75, .95, 1)))),
        file.path(out_dir, "validation_summary.rds"))
cat("\nsaved", file.path(out_dir, "validation_summary.rds"), "\n")
