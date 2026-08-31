# Figure 7 — the pattern validation, in two parts.
#
# Both parts compare the 64,836 simulated fires from spread/validation_simulate.R
# against the 241 observed ones from spread/validation_observed.R. This is the
# validation that does NOT need a mapped ignition point, so it uses the whole
# record (57 focal + 184 reduced landscapes), unlike the burned-area-by-
# vegetation calibration of spread/figure_dharma_size.R.
#
#   Part A  the regional size distribution: a density over log10(area) and the
#           matching Q-Q. Marginal, not conditioned — and read with the
#           truncation in mind (simulated fires are conditioned on >= 10 ha,
#           and the observed record is what the mapping caught over 1999-2022,
#           not a draw from the same generative process).
#
#   Part B  three metrics, one per row, each conditioned on FWI (left) and on
#           fire size (right):
#             size        — the size/FWI relationship itself, so the right-hand
#                           cell is empty and holds the legends
#             compactness — 4*pi*area / perimeter^2; the shape metric that
#                           shows the clearest pattern and the easiest one to
#                           explain. Elongation and convex-hull fill are
#                           largely redundant with it, and elongation along the
#                           fixed 293 degrees adds nothing, so none of them is
#                           in the paper figure.
#             deviation from the wind axis — |orientation - 113| folded into
#                           0-90 degrees; 0 = perfectly wind-aligned.
#           Conditioning is what defends the comparison against any residual
#           mismatch in the marginals of Part A.
#
# Style, as designed and as in spread/validation_analysis.R: simulated fires as
# a log-scaled hex-bin density (raw points do not work at 6e4), observed fires
# as points, a GAM smoother on each side.
#
# Axis sizes are drawn on a log10 scale but labelled in hectares, never in
# log units. Axis TITLES appear only once per column (bottom) and once per row
# (left), since every column shares an x scale and every row a y scale.
#
# The hex bins are visibly striped in the FWI panels because FWI is resampled
# from only 233 distinct observed values. That is left alone: jittering would
# hide a real property of the simulated set.
#
# Runs in well under a minute.

library(ggplot2)
library(hexbin)     # geom_hex's binning backend; ggplot2 only suggests it
library(patchwork)
library(viridis)
library(scales)
theme_set(theme_bw())
source(file.path("R", "spread_validation_functions.R"))

# Settings ----------------------------------------------------------------

val_dir <- file.path("files", "spread_validation")
fig_dir <- file.path("manuscript-spread", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

obs_col <- "#c1272d"
sim_col <- "black"
n_bins <- 55

set_levels <- c("Simulated", "Observed")
set_cols <- setNames(c(sim_col, obs_col), set_levels)

lab_fwi <- "FWI anomaly (standardized)"
lab_size <- "Burned area (ha)"
lab_compact <- "Compactness"
lab_dev <- "Deviation from wind axis (°)"

# Data --------------------------------------------------------------------

sim <- readRDS(file.path(val_dir, "simulated_fires.rds"))$fires
obs_sig <- readRDS(file.path(val_dir, "observed_signature.rds"))
obs_shp <- readRDS(file.path(val_dir, "observed_shape.rds"))
stopifnot(identical(obs_sig$fire_id, obs_shp$fire_id))

fwi_scale <- readRDS(file.path("files", "hierarchical_model",
                               "fwi_mean_sd_spread.rds"))

# Angular distance to the 113/293 axis, in degrees (0 = perfectly wind-aligned,
# 90 = perpendicular). `orientation` is a bearing mod 180, so the axis is 113.
axis_dev <- function(ori) pmin(abs(ori - 113), 180 - abs(ori - 113))

d <- rbind(
  data.frame(set = "Simulated",
             area_ha = sim$area_ha,
             fwi_z = sim$fwi_z,
             compactness = sim$compactness,
             axis_dev = axis_dev(sim$orientation)),
  data.frame(set = "Observed",
             area_ha = obs_shp$area_ha,
             fwi_z = (obs_sig$fwi - fwi_scale$fwi_mean) / fwi_scale$fwi_sd,
             compactness = obs_shp$compactness,
             axis_dev = axis_dev(obs_shp$orientation))
)
d$set <- factor(d$set, levels = set_levels)

# Shared scales -----------------------------------------------------------

# One x range per column and one y range per row, so the panels line up and the
# titles can be dropped everywhere but the margins.
finite_range <- function(x) range(x[is.finite(x)])
xlim_fwi <- finite_range(d$fwi_z)
xlim_size <- finite_range(d$area_ha)

area_breaks <- 10^(1:6)
area_scale <- function(which_axis) {
  f <- if (which_axis == "x") scale_x_log10 else scale_y_log10
  f(breaks = area_breaks, labels = label_comma(accuracy = 1),
    minor_breaks = rep(1:9, 6) * 10^rep(0:5, each = 9))
}


# Panel builder -----------------------------------------------------------

#' One conditioned panel.
#'
#' @param yvar column of `d` on the y axis; "area_ha" switches y to log10.
#' @param xvar "fwi_z" or "area_ha"; the latter switches x to log10.
#' @param ylab,xlab NULL drops the title (used everywhere but the margins).
#' @param legend draw the two guides in this panel (collected by patchwork).
metric_panel <- function(yvar, xvar, ylab = NULL, xlab = NULL,
                         legend = FALSE) {
  dd <- d[is.finite(d[[yvar]]) & is.finite(d[[xvar]]), ]
  dd$x <- dd[[xvar]]
  dd$y <- dd[[yvar]]
  ds <- dd[dd$set == "Simulated", ]
  do <- dd[dd$set == "Observed", ]

  p <- ggplot(mapping = aes(x, y)) +
    geom_hex(data = ds, bins = n_bins, aes(fill = after_stat(count))) +
    scale_fill_viridis(
      option = "G", transform = "log10", direction = -1,
      name = "N° of simulated fires",
      guide = if (legend) guide_colourbar(
        title.position = "top", barwidth = unit(38, "mm"),
        barheight = unit(3.5, "mm"), direction = "horizontal") else "none") +
    geom_point(data = do, aes(colour = set), size = 0.55, alpha = 0.65) +
    geom_smooth(data = ds, aes(colour = set), method = "gam",
                formula = y ~ s(x, bs = "cs"), linewidth = 0.6, se = FALSE) +
    geom_smooth(data = do, aes(colour = set), method = "gam",
                formula = y ~ s(x, bs = "cs"), linewidth = 0.6, se = FALSE) +
    scale_colour_manual(
      values = set_cols, name = NULL, drop = FALSE,
      guide = if (legend) guide_legend(
        direction = "horizontal", order = 1,
        override.aes = list(linewidth = 1.1, size = 0, alpha = 1)) else "none") +
    labs(x = xlab, y = ylab)

  # x scale, shared down the column
  p <- p + if (xvar == "area_ha") area_scale("x") else scale_x_continuous()
  p <- p + coord_cartesian(
    xlim = if (xvar == "area_ha") xlim_size else xlim_fwi)

  if (yvar == "area_ha") p <- p + area_scale("y")

  p + theme(panel.grid = element_blank(),
            axis.title = element_text(size = 9),
            axis.text = element_text(size = 8),
            plot.margin = margin(1.5, 1.5, 1.5, 1.5, unit = "mm"))
}


# Part A — the size distribution ------------------------------------------

lo <- log10(obs_shp$area_ha)
ls <- log10(sim$area_ha)
pp <- ppoints(length(lo))
qq <- data.frame(obs = quantile(lo, pp, type = 8),
                 sim = quantile(ls, pp, type = 8))

p_dens <- ggplot(mapping = aes(log_area, after_stat(density))) +
  geom_histogram(data = data.frame(log_area = ls), bins = 60,
                 fill = "grey70", colour = NA) +
  # Default (nrd0) bandwidth: the SJ selector over 241 fires resolves bumps
  # that are sampling noise at this n.
  geom_density(data = data.frame(log_area = lo), colour = obs_col,
               linewidth = 0.7) +
  labs(x = expression(paste(log[10], " area (ha)")), y = "Density") +
  theme(panel.grid = element_blank())

p_qq <- ggplot(qq, aes(sim, obs)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey60", linewidth = 0.4) +
  geom_point(size = 0.9, colour = obs_col) +
  labs(x = expression(paste("Simulated ", log[10], " area (ha)")),
       y = expression(paste("Observed ", log[10], " area (ha)"))) +
  theme(panel.grid = element_blank())

fig_a <- p_dens + p_qq


# Part B — the conditioned metrics ----------------------------------------

# Row 1 has no size ~ size panel; the guides go in the gap it leaves.
p_size_fwi <- metric_panel("area_ha", "fwi_z", ylab = lab_size, legend = TRUE)
p_comp_fwi <- metric_panel("compactness", "fwi_z", ylab = lab_compact)
p_comp_size <- metric_panel("compactness", "area_ha")
p_dev_fwi <- metric_panel("axis_dev", "fwi_z", ylab = lab_dev, xlab = lab_fwi)
p_dev_size <- metric_panel("axis_dev", "area_ha", xlab = lab_size)

fig_b <- p_size_fwi + guide_area() +
  p_comp_fwi + p_comp_size +
  p_dev_fwi + p_dev_size +
  plot_layout(ncol = 2, guides = "collect") &
  theme(legend.box = "vertical",
        legend.box.just = "left",
        legend.justification = c(0, 0.5),
        legend.title = element_text(size = 9, hjust = 0),
        legend.text = element_text(size = 8),
        legend.key.spacing.x = unit(1.5, "mm"),
        legend.spacing.y = unit(2, "mm"),
        legend.margin = margin(0, 0, 0, 0, unit = "mm"))


# Write -------------------------------------------------------------------

save_both <- function(p, name, width, height) {
  for (ext in c("png", "pdf")) {
    f <- file.path(fig_dir, paste0(name, ".", ext))
    ggsave(f, plot = p, width = width, height = height, units = "cm",
           dpi = 350, bg = "white")
    cat("wrote", f, "\n")
  }
}

save_both(fig_a, "fig7a_size_distribution", 18, 8)
save_both(fig_b, "fig7b_metrics_conditioned", 17, 19)
