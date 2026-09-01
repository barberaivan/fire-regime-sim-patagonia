# Figures 2 and S2 — the fitted spread probability as a function of what drives
# it, at three levels of fire weather.
#
#   Fig. 2  (fig2_spread_curves)      the four MODEL predictors: VFI, TFI,
#           slope and wind speed. One panel each, the other three held at their
#           mean, i.e. the marginal shape of the spread kernel.
#   Fig. S2 (figS2_spread_curves_raw) the same curves against the RAW variables
#           the indices are built from: NDVI within each vegetation type,
#           elevation, and northing. This is the one a reader who wants to know
#           "how flammable is a wet forest at NDVI 0.8?" can actually use;
#           Fig. S1 gives the raw-to-index mapping it rests on.
#
# Every curve is the posterior mean OVER random effects, not the curve of the
# mean parameter vector: for each posterior draw, 200 random effects are drawn
# from that draw's population distribution, a curve computed for each, and the
# 200 averaged — so the ribbon is the 95 % ETI of that average across the
# posterior. The averaging is nonlinear (plogis of a random linear predictor),
# which is why it cannot be shortcut. That loop lives in
# spread/hierarchical_fit.R and its result is on disk; this script only draws.
#
# Input:  files/hierarchical_model/curves_df_prediction.rds        (Fig. 2)
#         files/hierarchical_model/curves_df_prediction_raw_x.rds  (Fig. S2)
#         both written by spread/hierarchical_fit.R.
# Runs in seconds.
#
# THE FWI LEVELS. The three curves are the 2.5th percentile, the model-internal
# zero and the 97.5th percentile of the 235 fires' standardized FWI. They are
# STORED as those standardized values (-1.614 / 0 / 1.672) and RELABELLED here
# to the anomaly scale the paper reports (-0.60 / 0.86 / 2.38) — see
# R/spread_figure_functions.R. Do not read the stored level names as anomalies.

library(ggplot2)
library(viridis)
theme_set(theme_bw())

source(file.path("R", "focal_simulation_functions.R"))
source(file.path("R", "spread_figure_functions.R"))

# Settings ----------------------------------------------------------------

fit_dir <- file.path("files", "hierarchical_model")

fwi_name <- "FWI\nanomaly"

# Data --------------------------------------------------------------------

curves <- readRDS(file.path(fit_dir, "curves_df_prediction.rds"))
curves_raw <- readRDS(file.path(fit_dir, "curves_df_prediction_raw_x.rds"))

# The stored level names are standardized FWI; the printed ones are anomalies.
stopifnot(identical(levels(curves$fwi_level), levels(curves_raw$fwi_level)))
fwi_z_levels <- as.numeric(levels(curves$fwi_level))
fwi_labels <- sprintf("%.2f", fwi_to_original(fwi_z_levels))
cat("FWI levels: standardized", paste(fwi_z_levels, collapse = " / "),
    "-> anomaly", paste(fwi_labels, collapse = " / "), "\n")

# Shared aesthetics -------------------------------------------------------

fwi_colour <- function() {
  list(
    scale_color_viridis(option = "A", end = 0.8, discrete = TRUE,
                        name = fwi_name, labels = fwi_labels),
    scale_fill_viridis(option = "A", end = 0.8, discrete = TRUE,
                       name = fwi_name, labels = fwi_labels)
  )
}

curve_layers <- function() {
  list(geom_ribbon(color = NA, alpha = 0.4), geom_line())
}


# Figure 2 — the model predictors -----------------------------------------

# Strips below the panels, standing in for the x titles: the four predictors
# are on four different units, so a single shared x title would be a lie.
fig2 <- ggplot(curves, aes(varying_val, mean,
                           ymin = eti_lower_95, ymax = eti_upper_95,
                           color = fwi_level, fill = fwi_level)) +
  curve_layers() +
  fwi_colour() +

  facet_wrap(vars(varying_var2), scales = "free_x", strip.position = "bottom",
             axes = "all", axis.labels = "margins") +

  ylab("Spread probability") +
  theme(strip.placement = "outside",
        strip.background = element_rect(color = "white", fill = "white"),
        strip.text = element_text(margin = margin(r = 0, l = 0, unit = "mm"),
                                  size = 11),
        panel.spacing.x = unit(0, "mm"),
        panel.spacing.y = unit(6, "mm"),
        panel.border = element_blank(),
        panel.grid = element_blank(),
        axis.title.x = element_blank(),
        axis.line = element_line(linewidth = 0.3),
        legend.position = "right")

save_fig(fig2, "fig2_spread_curves", width = 14, height = 12)


# Figure S2 — the raw variables -------------------------------------------

# Two blocks with different facetting: NDVI has to be split by vegetation type
# (the VFI curve is a different parabola in each), elevation and northing do
# not. They are drawn separately and stacked, with one shared y title, because
# a single facet_wrap cannot mix the two strip styles.

raw <- curves_raw
raw$varying_var2 <- as.character(raw$varying_var)
raw$varying_var2[raw$varying_var == "elevation"] <- "Elevation (m a.s.l.)"
raw$varying_var2[raw$varying_var == "northing"] <- "Northing"

curves_veg <- ggplot(raw[raw$varying_var == "ndvi", ],
                     aes(varying_val, mean,
                         ymin = eti_lower_95, ymax = eti_upper_95,
                         color = fwi_level, fill = fwi_level)) +
  curve_layers() +
  fwi_colour() +

  facet_wrap(vars(vegetation), scales = "fixed", strip.position = "top",
             axes = "all", axis.labels = "margins", nrow = 3) +

  scale_y_continuous(breaks = seq(0, 1, 0.25), limits = c(0, 1),
                     expand = c(0.005, 0.005)) +
  scale_x_continuous(breaks = seq(0, 1, 0.25), limits = c(0, 1)) +

  xlab("NDVI") +
  theme(strip.placement = "outside",
        strip.background = element_rect(color = strip_bgcol,
                                        fill = strip_bgcol),
        strip.text = element_text(size = 10, color = "white"),
        panel.spacing.x = unit(3, "mm"),
        panel.spacing.y = unit(6, "mm"),
        panel.border = element_blank(),
        panel.grid = element_blank(),
        axis.line = element_line(linewidth = 0.3),
        axis.title.y = element_blank(),
        # The sixth cell of the 3 x 2 grid is empty; the legend goes in it.
        legend.position = "inside",
        legend.position.inside = c(0.78, 0.13))

curves_topo <- ggplot(raw[raw$varying_var != "ndvi", ],
                      aes(varying_val, mean,
                          ymin = eti_lower_95, ymax = eti_upper_95,
                          color = fwi_level, fill = fwi_level)) +
  curve_layers() +
  fwi_colour() +

  facet_wrap(vars(varying_var2), scales = "free_x", strip.position = "bottom",
             axes = "all", axis.labels = "margins", nrow = 1) +

  scale_y_continuous(breaks = seq(0, 1, 0.25), limits = c(0, 1),
                     expand = c(0.005, 0.005)) +
  theme(strip.placement = "outside",
        strip.background = element_rect(color = "white", fill = "white"),
        strip.text = element_text(margin = margin(r = 0, l = 0, unit = "mm"),
                                  size = 11),
        panel.spacing.x = unit(3, "mm"),
        panel.spacing.y = unit(6, "mm"),
        panel.border = element_blank(),
        panel.grid = element_blank(),
        axis.title.x = element_blank(),
        axis.title.y = element_blank(),
        axis.line = element_line(linewidth = 0.3),
        legend.position = "none")

# `deeptime::ggarrange2` rather than patchwork: it is what takes a `left` grob
# as one y title spanning both blocks, which is the whole reason the two are
# drawn without their own.
ylabb <- grid::textGrob("Spread probability",
                        gp = grid::gpar(fontsize = 11, fontface = "plain"),
                        rot = 90)

figS2 <- deeptime::ggarrange2(
  curves_veg + theme(plot.margin = margin(b = 5, unit = "mm")),
  curves_topo,
  left = ylabb,
  nrow = 2, heights = c(3.9, 1)
)

save_fig(figS2, "figS2_spread_curves_raw", width = 14, height = 18)
