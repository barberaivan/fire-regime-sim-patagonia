# Figure 3 — the six spread parameters as a function of fire weather.
#
# One panel per parameter, on the simulator's own (constrained) scale, against
# FWI on its original anomaly scale. Two things are drawn in each:
#
#   the band   the posterior of the POPULATION MEAN parameter at that FWI —
#              mean and 95 % ETI. "Mean" here is the average over random
#              effects, computed by simulating 200 of them per posterior draw
#              and averaging AFTER the logit-scaled back-transform; the
#              transform is nonlinear, so the mean parameter is not the
#              parameter of the mean. That loop is in
#              spread/hierarchical_fit.R and its output is read from disk.
#   the points the 57 fitted random effects — posterior mean and 95 % ETI per
#              fire, each at its own FWI. These are the data the band is fitted
#              through, and their scatter is the between-fire variance sigma_p.
#
# The percentage in each panel is P(beta_1 > 0) for that parameter: the
# posterior probability that FWI has a POSITIVE slope at the unconstrained
# scale. It is a probability, not a p-value — 50 % means the sign is
# undetermined. Only `steps` is decisive (100 %), which is the paper's point:
# fire weather acts mainly on how far a fire runs, not on how it spreads
# locally.
#
# Input:  files/hierarchical_model/mu_samples_prediction.rds  (the band)
#         files/hierarchical_model/spread_model_samples.rds   (the points, and
#                                                              the slope probs)
#         both written by spread/hierarchical_fit.R.
# Runs in about a minute — nearly all of it the HDI/quantile summaries over
# 150 x 6 x 12000 draws.

library(ggplot2)
library(tidyr)
library(dplyr)
library(viridis)
theme_set(theme_bw())

source(file.path("R", "focal_simulation_functions.R"))
source(file.path("R", "spread_figure_functions.R"))

# Settings ----------------------------------------------------------------

fit_dir <- file.path("files", "hierarchical_model")

# Where the P(slope > 0) label sits, in original FWI units and as a fraction of
# each panel's own y range. Set by hand: the panels have wildly different y
# scales (probabilities of order 1 next to `steps` in the hundreds).
prob_x <- 0.1
prob_y_frac <- 0.9

# Data --------------------------------------------------------------------

draws <- readRDS(file.path(fit_dir, "spread_model_samples.rds"))
mu_samples <- readRDS(file.path(fit_dir, "mu_samples_prediction.rds"))

fi_params <- readRDS(file.path("data", "flammability_indices",
                               "flammability_indices.rds"))
bounds <- focal_par_bounds(fi_params)
par_names <- bounds$par_names
n_coef <- bounds$n_coef

npost <- dim(draws$fixef)[3]
npred <- dim(mu_samples)[1]
stopifnot(dim(mu_samples)[2] == n_coef, dim(mu_samples)[3] == npost)

# The FWI axis of the band. `hierarchical_fit.R` built it as an evenly spaced
# sequence over the range of the 235 fires' standardized FWI, so it has to be
# rebuilt the same way — `mu_samples` carries the values but not the grid.
fwi_all <- spread_fwi_all(draws)
fwi_seq <- seq(min(fwi_all), max(fwi_all), length.out = npred)

# The band ----------------------------------------------------------------

mu_summ <- apply(mu_samples, 1:2, summarise_post)
dimnames(mu_summ) <- list(metric = dimnames(mu_summ)[[1]],
                          row = 1:npred, par_name = par_names)

mu_df <- as.data.frame.table(
    mu_summ[c("mean", "eti_lower_95", "eti_upper_95"), , ],
    responseName = "par_value") |>
  pivot_wider(names_from = "metric", values_from = "par_value") |>
  mutate(row = as.numeric(as.character(row)),
         fwi = fwi_to_original(fwi_seq[as.numeric(as.character(row))]))

# The points --------------------------------------------------------------

# THE TRAP, as in R/focal_simulation_functions.R: `draws$ranef` holds `steps`
# on the natural scale already and the other five on the logit scale, so only
# rows 1:(n_coef - 1) are back-transformed.
ranef_cons <- draws$ranef
for (i in 1:npost) {
  ranef_cons[1:(n_coef - 1), , i] <- t(invlogit_scaled2(
    t(draws$ranef[1:(n_coef - 1), , i]),
    L = bounds$L[1:(n_coef - 1)], U = bounds$U[1:(n_coef - 1)]))
}

ranef_summ <- apply(ranef_cons, 1:2, summarise_post)
names(dimnames(ranef_summ)) <- c("type", "par_name", "fire_id")

fwi_focal <- fwi_to_original(focal_fwi_z(dimnames(draws$ranef)[[2]]))

ranef_df <- as.data.frame.table(ranef_summ, responseName = "par_value") |>
  pivot_wider(names_from = "type", values_from = "par_value") |>
  mutate(par_name = factor(as.character(par_name), levels = par_names),
         fwi = fwi_focal[as.character(fire_id)])

# The slope probabilities -------------------------------------------------

b_probs <- apply(draws$fixef[1:n_coef, "b", ], 1,
                 function(x) mean(x > 0))

# One text per panel, placed near the top of that panel's own data range.
span <- ranef_df |>
  group_by(par_name) |>
  summarise(lo = min(eti_lower_95), hi = max(eti_upper_95), .groups = "drop")

probs_data <- data.frame(
  par_name = factor(par_names, levels = par_names),
  prob = paste(round(b_probs * 100, 2), "%"),
  x = prob_x,
  y = span$lo[match(par_names, as.character(span$par_name))] +
      prob_y_frac * (span$hi[match(par_names, as.character(span$par_name))] -
                     span$lo[match(par_names, as.character(span$par_name))])
)

cat("P(FWI slope > 0), by parameter:\n")
print(round(b_probs, 4))

# Figure ------------------------------------------------------------------

# Two shades of plasma: the darker one for the population band and the point
# outlines, the lighter one for the per-fire intervals and point fills, so the
# 57 fires read as a cloud and the band reads as the summary through it.
vir1 <- viridis(1, option = "C")
vir2 <- viridis(1, begin = 0.5, option = "C")

# Panel labels in the manuscript's notation (see `par_labels()` for why they
# are literal Unicode rather than plotmath).
lab_levels <- par_labels(par_names)
mu_df$par_lab <- factor(lab_levels[match(as.character(mu_df$par_name),
                                         par_names)], levels = lab_levels)
ranef_df$par_lab <- factor(lab_levels[match(as.character(ranef_df$par_name),
                                            par_names)], levels = lab_levels)
probs_data$par_lab <- factor(lab_levels[match(as.character(probs_data$par_name),
                                              par_names)], levels = lab_levels)

fig3 <- ggplot(mu_df, aes(fwi, mean, ymin = eti_lower_95, ymax = eti_upper_95)) +
  geom_ribbon(color = NA, alpha = 0.4, fill = vir1) +
  geom_line(color = vir1) +

  geom_linerange(data = ranef_df, alpha = 0.5, color = vir2) +
  geom_point(data = ranef_df, alpha = 0.7, shape = 21, stroke = 0.35,
             color = vir1, fill = vir2) +

  geom_text(aes(x, y, label = prob), data = probs_data, inherit.aes = FALSE,
            size = 7 / .pt) +

  facet_wrap(vars(par_lab), scales = "free_y", strip.position = "left",
             axes = "all") +

  xlab("Fire Weather Index anomaly") +
  scale_y_continuous(expand = c(0.05, 0.05)) +
  theme(strip.placement = "outside",
        strip.background = element_rect(color = "white", fill = "white"),
        strip.text = element_text(margin = margin(r = 0, l = 4, unit = "mm"),
                                  size = 11),
        panel.spacing.x = unit(0, "mm"),
        panel.spacing.y = unit(6, "mm"),
        panel.border = element_blank(),
        panel.grid = element_blank(),
        axis.title.y = element_blank(),
        axis.line = element_line(linewidth = 0.3))

save_fig(fig3, "fig3_params_fwi", width = 17, height = 10)
