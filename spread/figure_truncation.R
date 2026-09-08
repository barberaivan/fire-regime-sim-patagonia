# Figure S6 — how a simulated fire stops, and what it does to its shape.
#
# A fire in the regional experiment (spread/validation_simulate.R) ends in one
# of two ways: propagation failed at every cell on its edge, or the step budget
# kappa ran out while it was still burning. `steps_used == steps` separates
# them exactly, with no threshold to choose. Because FireSpread reaches the 8
# neighbours per step, a fire in the second group is confined to the square of
# half-width kappa around its ignition cell, and since a fire runs furthest
# downwind that square clips its long axis first: what is left is rounder, and
# its leading principal axis turns across the wind.
#
# Two panels, both over the simulated fires split by that flag, with the
# observed record on top:
#   (A) the distribution of the deviation from the 113/293 wind axis, with the
#       45-degree random-orientation reference marked. The capped fires pile up
#       ABOVE 45 degrees (an active across-wind bias); the free-running ones sit
#       where the observed fires do.
#   (B) compactness against burned area, in the style of Fig. 7B: observed
#       fires as points, one GAM smoother per group.
#
# Input:  files/spread_validation/simulated_fires.rds (spread/validation_simulate.R)
#         files/spread_validation/observed_shape.rds  (spread/validation_observed.R)
# Output: manuscript-spread/figures/figS6_truncation.{png,pdf}
# No re-simulation; runs in seconds.

library(ggplot2)
library(patchwork)
library(viridis)
library(scales)
theme_set(theme_bw())
source(file.path("R", "spread_figure_functions.R"))   # save_fig()

# Settings ----------------------------------------------------------------

val_dir <- file.path("files", "spread_validation")

obs_col <- "#c1272d"                              # as in Figs. 6 and 7
grp_cols <- viridis_pal(option = "D", end = 0.5)(2)   # the two simulated groups

lab_obs <- "Observed"
lab_free <- "Simulated, stopped on its own"
lab_capped <- "Simulated, stopped by κ"
grp_levels <- c(lab_obs, lab_free, lab_capped)
grp_pal <- setNames(c(obs_col, grp_cols[1], grp_cols[2]), grp_levels)

lab_size <- "Burned area (ha)"
lab_compact <- "Compactness"
lab_dev <- "Deviation from wind axis (°)"

# Data --------------------------------------------------------------------

sim <- readRDS(file.path(val_dir, "simulated_fires.rds"))$fires
obs_shp <- readRDS(file.path(val_dir, "observed_shape.rds"))

# Angular distance to the 113/293 axis, in degrees (0 = wind-aligned,
# 90 = perpendicular). `orientation` is a bearing mod 180, so the axis is 113.
axis_dev <- function(ori) pmin(abs(ori - 113), 180 - abs(ori - 113))

# The exact stopping criterion; see the header.
sim$group <- ifelse(sim$steps_used == sim$steps_int, lab_capped, lab_free)

d <- rbind(
  data.frame(group = lab_obs, area_ha = obs_shp$area_ha,
             compactness = obs_shp$compactness,
             axis_dev = axis_dev(obs_shp$orientation)),
  data.frame(group = sim$group, area_ha = sim$area_ha,
             compactness = sim$compactness,
             axis_dev = axis_dev(sim$orientation))
)
d$group <- factor(d$group, levels = grp_levels)
d <- d[is.finite(d$area_ha) & is.finite(d$compactness) &
       is.finite(d$axis_dev), ]

panel_theme <- function() {
  theme(panel.grid = element_blank(),
        plot.title = element_text(size = 10),
        axis.title = element_text(size = 9),
        axis.text = element_text(size = 8),
        legend.title = element_blank(),
        legend.text = element_text(size = 8),
        legend.key = element_blank(),
        legend.key.size = unit(4, "mm"),
        plot.margin = margin(1.5, 1.5, 1.5, 1.5, unit = "mm"))
}


# (A) orientation ---------------------------------------------------------

# Densities, not histograms: the three groups differ by two orders of magnitude
# in n, so counts cannot share an axis. `bounds` keeps the kernel inside the
# 0-90 range the metric lives on, which otherwise leaks mass past both ends.
p_a <- ggplot(d, aes(axis_dev, after_stat(density), colour = group,
                     fill = group)) +
  geom_vline(xintercept = 45, colour = "grey55", linewidth = 0.4,
             linetype = "dashed") +
  annotate("text", x = 45, y = Inf, label = "random orientation",
           hjust = -0.06, vjust = 1.6, size = 2.6, colour = "grey40") +
  geom_density(linewidth = 0.6, alpha = 0.18, bounds = c(0, 90)) +
  scale_colour_manual(values = grp_pal, drop = FALSE) +
  scale_fill_manual(values = grp_pal, drop = FALSE) +
  scale_x_continuous(breaks = seq(0, 90, 15), limits = c(0, 90)) +
  labs(x = lab_dev, y = "Density") +
  ggtitle("(A)") +
  panel_theme() +
  theme(legend.position = "inside",
        legend.position.inside = c(0.02, 0.98),
        legend.justification = c(0, 1),
        legend.background = element_blank(),
        legend.margin = margin(0, 0, 0, 0, unit = "mm"))


# (B) compactness against size --------------------------------------------

area_breaks <- 10^(1:6)

p_b <- ggplot(d, aes(area_ha, compactness, colour = group)) +
  geom_point(data = d[d$group == lab_obs, ], size = 0.55, alpha = 0.65) +
  geom_smooth(method = "gam", formula = y ~ s(x, bs = "cs"), se = FALSE,
              linewidth = 0.7) +
  scale_colour_manual(values = grp_pal, drop = FALSE, guide = "none") +
  scale_x_log10(breaks = area_breaks, labels = label_comma(accuracy = 1),
                minor_breaks = rep(1:9, 6) * 10^rep(0:5, each = 9)) +
  # compactness is bounded below by 0; the GAM extrapolates past it at the
  # largest sizes, and a curve drawn below zero would be an artefact of the
  # smoother, not of the fires.
  coord_cartesian(ylim = c(0, NA)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(x = lab_size, y = lab_compact) +
  ggtitle("(B)") +
  panel_theme()


# Write -------------------------------------------------------------------

save_fig(p_a + p_b, "figS6_truncation", width = 17, height = 8)
