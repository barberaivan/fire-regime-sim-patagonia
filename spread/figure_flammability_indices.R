# Figure S1 — what the two flammability indices are made of.
#
# VFI and TFI are not fitted here: they are FIXED functions of NDVI, vegetation
# type, elevation and northing, estimated beforehand by the regional logistic
# regression of data_prep/ and stored in
# data/flammability_indices/flammability_indices.rds. The spread model then
# treats them as two ordinary covariates. This figure is the reference that
# says what a VFI of 0.5 corresponds to on the ground, and it is what Fig. S2
# (spread probability against the raw variables) rests on.
#
#   top     VFI against NDVI, one curve per vegetation type. Each is the
#           downward parabola a_v + b_v (NDVI - c_v)^2, standardized — so
#           flammability peaks at an intermediate NDVI (enough fuel, dry
#           enough) and the peak is sharp in the wet types and broad in the
#           dry ones. Each curve is drawn only over the 95 % HDI of NDVI
#           ACTUALLY OBSERVED in that vegetation type, which is why they cover
#           different x ranges: extrapolating a grassland parabola to NDVI 0.95
#           would be inventing a landscape that does not exist.
#   bottom  TFI against elevation and against northing. TFI is linear in both,
#           so these two panels are the whole index; elevation spans its own
#           95 % HDI and northing its full [-1, 1].
#
# Input:  data/flammability_indices/flammability_indices.rds  (the parameters)
#         data/flammability_indices/ndvi_elevation_summary.rds (the ranges)
# Runs in seconds.

library(ggplot2)
library(viridis)
theme_set(theme_bw())

source(file.path("R", "spread_figure_functions.R"))

# Settings ----------------------------------------------------------------

nseq <- 300      # points per curve

# Data --------------------------------------------------------------------

# `vfi_calc()` and `tfi_calc()` read a global `fi_params`, so it has to exist
# before the file is sourced.
fi_params <- readRDS(file.path("data", "flammability_indices",
                               "flammability_indices.rds"))
source(file.path("R", "flammability_indices_functions.R"))

data_summ <- readRDS(file.path("data", "flammability_indices",
                               "ndvi_elevation_summary.rds"))
stopifnot(identical(as.character(data_summ$ndvi$vegetation), veg_levels))

# VFI: one NDVI sequence per vegetation type, over that type's own 95 % HDI.
vfi_df <- do.call("rbind", lapply(seq_along(veg_levels), function(v) {
  data.frame(
    ndvi = seq(data_summ$ndvi$hdi_lower_95[v], data_summ$ndvi$hdi_upper_95[v],
               length.out = nseq),
    vegnum = v,
    vegetation = veg_levels[v]
  )
}))
vfi_df$vegetation <- factor(vfi_df$vegetation, levels = veg_levels)
vfi_df$vfi <- vfi_calc(vfi_df$vegnum, vfi_df$ndvi)

# TFI: linear in elevation and in northing, and standardized the same way.
tfi_std <- function(elevation, northing) {
  raw <- fi_params$b_elev_ori * elevation + fi_params$b_north_ori * northing
  (raw - fi_params$tfi_mean) / fi_params$tfi_sd
}

elev_df <- data.frame(
  elevation = seq(data_summ$elevation["hdi_lower_95"],
                  data_summ$elevation["hdi_upper_95"], length.out = nseq),
  northing = 0
)
elev_df$tfi <- tfi_std(elev_df$elevation, elev_df$northing)

north_df <- data.frame(
  elevation = unname(data_summ$elevation["mean"]),
  northing = seq(-1, 1, length.out = nseq)
)
north_df$tfi <- tfi_std(north_df$elevation, north_df$northing)

# Figure ------------------------------------------------------------------

panel_theme <- function() {
  theme(panel.border = element_blank(),
        panel.grid = element_blank(),
        axis.line = element_line(linewidth = 0.3))
}

vfi_plot <- ggplot(vfi_df) +
  geom_line(aes(ndvi, vfi, color = vegetation), linewidth = 0.6) +
  scale_color_viridis(discrete = TRUE, begin = 0, end = 0.9, option = "D",
                      name = "Vegetation\ntype") +
  ylab("Vegetation\nFlammability Index (VFI)") +
  xlab("NDVI") +
  scale_y_continuous(breaks = seq(-1, 1, 1), limits = c(-2, 1)) +
  scale_x_continuous(breaks = seq(0, 1, 0.25), limits = c(0, 1)) +
  panel_theme() +
  theme(legend.position = "right")

tfi_elev <- ggplot(elev_df) +
  geom_line(aes(elevation, tfi), linewidth = 0.6) +
  ylab("Topographic\nFlammability Index (TFI)") +
  xlab("Elevation (m a.s.l.)") +
  scale_y_continuous(breaks = seq(-2, 2, 1), limits = c(-2, 2)) +
  panel_theme()

tfi_north <- ggplot(north_df) +
  geom_line(aes(northing, tfi), linewidth = 0.6) +
  xlab("Northness") +
  scale_y_continuous(breaks = seq(-2, 2, 1), limits = c(-2, 2)) +
  panel_theme() +
  theme(axis.title.y = element_blank())

# The 2 x 2 grid holds three panels; the vegetation legend is pulled out of the
# VFI panel and put in the free cell, so the VFI panel keeps the same width as
# the TFI one below it.
veg_legend <- ggpubr::as_ggplot(ggpubr::get_legend(vfi_plot))

figS1 <- deeptime::ggarrange2(
  vfi_plot + theme(legend.position = "none"),
  veg_legend, tfi_elev, tfi_north,
  nrow = 2
)

save_fig(figS1, "figS1_flammability_indices", width = 14, height = 12)

# Report ------------------------------------------------------------------

# The peak of each vegetation type's parabola and the VFI there — the numbers
# the caption quotes.
cat("\nVFI peak by vegetation type (within the observed NDVI range)\n")
for (v in veg_levels) {
  x <- vfi_df[vfi_df$vegetation == v, ]
  k <- which.max(x$vfi)
  cat(sprintf("  %-18s NDVI %.3f -> VFI %+.2f   (range %.2f-%.2f)\n",
              v, x$ndvi[k], x$vfi[k], min(x$ndvi), max(x$ndvi)))
}
cat(sprintf("\nTFI: %+.2f at %.0f m to %+.2f at %.0f m (northing 0)\n",
            elev_df$tfi[1], elev_df$elevation[1],
            elev_df$tfi[nseq], elev_df$elevation[nseq]))
cat(sprintf("TFI: %+.2f to %+.2f across northing -1 to 1 (elevation %.0f m)\n",
            north_df$tfi[1], north_df$tfi[nseq], north_df$elevation[1]))
