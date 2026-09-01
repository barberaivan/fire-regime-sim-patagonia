# Figure 4 — how much vegetation type still matters as fire weather worsens.
#
# The question the paper asks with this figure: does severe fire weather
# override the vegetation, or does the vegetation keep its grip? The answer is
# in the two panels together.
#
#   (A) the SPREAD of the five vegetation types' spread probabilities at each
#       FWI — mean absolute deviation across the five, in percentage points. A
#       falling line means the types converge, i.e. weather is overriding
#       vegetation.
#   (B) the five curves themselves, so the reader can see that they converge by
#       every type rising, not by the flammable ones stalling.
#
# Both are computed on a realistic landscape rather than at fixed covariate
# values: 500 cells sampled inside Nahuel Huapi National Park supply the joint
# distribution of slope and wind speed, each cell counted twice (its own slope
# and slope = 0) so uphill and downhill spread weigh equally, elevation and
# northing held at 900 m and 0. NDVI is each vegetation type's own predicted
# value there. For every posterior draw and every FWI, 200 random effects are
# drawn from that draw's population distribution, the spread probability is
# averaged over cells and over random effects, and that average is what the
# summaries below describe. That loop is the heavy part and lives in
# spread/hierarchical_fit.R; its output is read from disk here.
#
# Input:  files/hierarchical_model/spreadprob_veg_comparison_array.rds
#         (fwi x vegetation x posterior draw), written by
#         spread/hierarchical_fit.R.
# Runs in seconds.
#
# The thesis version of this figure (Fig. 4.9) is in Spanish; this is the same
# figure with the paper's English labels and FWI on the anomaly scale it is
# already stored on.

library(ggplot2)
library(tidyr)
library(dplyr)
library(viridis)
library(patchwork)
theme_set(theme_bw())

source(file.path("R", "focal_simulation_functions.R"))
source(file.path("R", "spread_figure_functions.R"))

# Settings ----------------------------------------------------------------

fit_dir <- file.path("files", "hierarchical_model")

# Panel-letter positions, in data units. Set by hand against the two y limits.
lab_x <- -0.57
lab_y_a <- 0.117
lab_y_b <- 0.99

# Data --------------------------------------------------------------------

spreadprobs <- readRDS(file.path(fit_dir,
                                 "spreadprob_veg_comparison_array.rds"))
stopifnot(identical(dimnames(spreadprobs)[[2]], veg_levels))

fwi_z <- as.numeric(dimnames(spreadprobs)[[1]])
fwi_ori <- fwi_to_original(fwi_z)

# Panel A — the vegetation effect -----------------------------------------

# Mean absolute deviation across the five types, computed WITHIN each posterior
# draw (so the uncertainty band is the uncertainty of the effect, not the
# spread of five independently summarised curves).
mad2 <- function(x) mean(abs(x - mean(x)))

mad_draws <- apply(spreadprobs, c(1, 3), mad2)
mad_summ <- apply(mad_draws, 1, summarise_post) |> t() |> as.data.frame()
mad_summ$fwi <- fwi_ori

p_a <- ggplot(mad_summ, aes(x = fwi, y = mean,
                            ymin = hdi_lower_95, ymax = hdi_upper_95)) +
  geom_ribbon(color = NA, alpha = 0.2) +
  geom_line() +
  ylab("Vegetation effect (%)") +
  xlab("Fire Weather Index anomaly") +
  annotate("text", x = lab_x, y = lab_y_a, label = "A", size = 12 / .pt,
           fontface = "plain", hjust = 0, vjust = 1) +
  scale_y_continuous(expand = c(1e-5, 1e-5), limits = c(0, 0.12),
                     labels = function(x) x * 100) +
  nice_theme()

# Panel B — the five curves -----------------------------------------------

psumm <- apply(spreadprobs, 1:2, summarise_post)
names(dimnames(psumm))[1] <- "summary"

psumm_df <- as.data.frame.table(psumm, responseName = "prob") |>
  pivot_wider(names_from = "summary", values_from = "prob") |>
  mutate(fwi = fwi_to_original(as.numeric(as.character(fwi))),
         vegetation = factor(as.character(vegetation), levels = veg_levels))

p_b <- ggplot(psumm_df, aes(x = fwi, y = mean,
                            ymin = hdi_lower_95, ymax = hdi_upper_95,
                            color = vegetation, fill = vegetation)) +
  geom_ribbon(color = NA, alpha = 0.2) +
  geom_line() +
  scale_fill_viridis(discrete = TRUE, begin = 0, end = 0.9, option = "D",
                     name = NULL) +
  scale_color_viridis(discrete = TRUE, begin = 0, end = 0.9, option = "D",
                      name = NULL) +
  ylab("Spread probability (%)") +
  xlab("Fire Weather Index anomaly") +
  annotate("text", x = lab_x, y = lab_y_b, label = "B", size = 12 / .pt,
           fontface = "plain", hjust = 0, vjust = 1) +
  scale_y_continuous(expand = c(1e-5, 1e-5), limits = c(0.2, 1),
                     labels = function(x) x * 100) +
  nice_theme() +
  theme(legend.position = "right")

# The two panels share the x axis, so only B carries its title and ticks.
fig4 <- (p_a + theme(axis.text.x = element_blank(),
                     axis.title.x = element_blank())) + p_b +
  plot_layout(nrow = 2)

save_fig(fig4, "fig4_vegetation_effect", width = 13, height = 13)

# Report ------------------------------------------------------------------

# The two numbers the Results quote: the vegetation effect at the driest and
# the wettest end of the record.
ends <- mad_summ[c(1, nrow(mad_summ)), ]
cat(sprintf("\nvegetation effect (mean abs. deviation, percentage points)\n"))
cat(sprintf("  FWI anomaly %+.2f: %.1f  [%.1f, %.1f]\n",
            ends$fwi, 100 * ends$mean,
            100 * ends$hdi_lower_95, 100 * ends$hdi_upper_95))

cat("\nspread probability by vegetation type (%), at the two ends\n")
for (v in veg_levels) {
  x <- psumm_df[psumm_df$vegetation == v, ]
  x <- x[c(1, nrow(x)), ]
  cat(sprintf("  %-18s %5.1f -> %5.1f\n", v, 100 * x$mean[1], 100 * x$mean[2]))
}
