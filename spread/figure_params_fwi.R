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
#              spread/hierarchical_predictions.R and its output is read from disk.
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
# TWO VERSIONS are written, to be chosen between:
#
#   fig3_params_fwi     the 57 fires with a known ignition point only.
#   fig3_params_fwi_v2  the same, plus in the kappa panel the 178 fires
#                       WITHOUT an ignition point, whose only fitted parameter
#                       is kappa itself (they enter the fit through the
#                       area ~ steps regression, not through simulation, so no
#                       beta is estimated for them). Different colour and
#                       shape, same plasma scale, legend at the bottom.
#
# Input:  files/hierarchical_model/mu_samples_prediction.rds  (the band)
#         files/hierarchical_model/spread_model_samples.rds   (the points, and
#                                                              the slope probs)
#         both written by the stage-2 scripts (hierarchical_predictions.R and
#         hierarchical_fit_run.R respectively).
# Runs in about a minute, nearly all of it the HDI/quantile summaries over
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

# The FWI axis of the band. `hierarchical_predictions.R` builds it as an evenly spaced
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


# The fires without an ignition point ------------------------------------

# Their only fitted parameter is kappa, and it is stored differently from the
# focal fires': `draws$steps` is on the SCALED-LOGIT scale, bounded below by
# `stepsL` and above by `draws$stepsU`, which is itself estimated and so
# changes from draw to draw. Back-transform draw by draw before summarising,
# exactly as spread/exploratory_steps_area.R does.
stepsL <- bounds$L["steps"]

steps_nonfocal <- draws$steps
for (j in 1:npost) {
  steps_nonfocal[, j] <- invlogit_scaled2(draws$steps[, j], L = stepsL,
                                          U = draws$stepsU[j])
}

nonfocal_summ <- apply(steps_nonfocal, 1, summarise_post)
names(dimnames(nonfocal_summ)) <- c("type", "fire_id")

fwi_nonfocal <- fwi_to_original(focal_fwi_z(dimnames(draws$steps)[[1]]))

nonfocal_df <- as.data.frame.table(nonfocal_summ, responseName = "par_value") |>
  pivot_wider(names_from = "type", values_from = "par_value") |>
  mutate(par_name = factor("steps", levels = par_names),
         fwi = fwi_nonfocal[as.character(fire_id)])

cat("fires with a known ignition point:", ncol(draws$ranef), "\n")
cat("fires without one:", nrow(draws$steps), "\n")

# Figure ------------------------------------------------------------------

# Three shades of plasma: the darkest for the population band and every point
# outline, the middle one for the fires with a known ignition point, the
# lightest for those without, so all three read as one scale.
vir1 <- viridis(1, option = "C")
vir2 <- viridis(1, begin = 0.5, option = "C")
vir3 <- viridis(1, begin = 0.82, option = "C")

# Panel labels in the manuscript's notation (see `par_labels()` for why they
# are literal Unicode rather than plotmath).
lab_levels <- par_labels(par_names)
add_lab <- function(d) {
  d$par_lab <- factor(lab_levels[match(as.character(d$par_name), par_names)],
                      levels = lab_levels)
  d
}
mu_df <- add_lab(mu_df)
ranef_df <- add_lab(ranef_df)
nonfocal_df <- add_lab(nonfocal_df)
probs_data <- add_lab(probs_data)

ig_levels <- c("known", "unknown")
ig_labels <- c(known = "Ignition point known",
               unknown = "Ignition point unknown")

#' The figure, with or without the fires that have no ignition point
#'
#' @param extra_df the non-focal kappa estimates, or NULL for the version that
#'   leaves them out. When given, the point aesthetics are mapped instead of
#'   fixed, which is what raises the legend at the bottom.
#' @param probs the label data, whose y position depends on which points are
#'   drawn in each panel.
params_figure <- function(probs, extra_df = NULL) {
  p <- ggplot(mu_df, aes(fwi, mean, ymin = eti_lower_95, ymax = eti_upper_95)) +
    geom_ribbon(color = NA, alpha = 0.4, fill = vir1) +
    geom_line(color = vir1)

  if (is.null(extra_df)) {
    p <- p +
      geom_linerange(data = ranef_df, alpha = 0.5, color = vir2) +
      geom_point(data = ranef_df, alpha = 0.7, shape = 21, stroke = 0.35,
                 color = vir1, fill = vir2)
  } else {
    # The fires without an ignition point go underneath, fainter and smaller:
    # there are three times as many of them, and the 57 the rest of the figure
    # is about have to stay readable through them. Their layers carry the
    # shape/fill mapping the legend is built from; the known-ignition ones in
    # this panel carry it too, so both keys appear.
    steps_known <- mutate(ranef_df[ranef_df$par_name == "steps", ],
                          ig = factor("known", levels = ig_levels))
    steps_unknown <- mutate(extra_df,
                            ig = factor("unknown", levels = ig_levels))
    p <- p +
      geom_linerange(data = steps_unknown, alpha = 0.35, color = vir3) +
      geom_point(data = steps_unknown, aes(shape = ig, fill = ig), alpha = 0.8,
                 size = 1.2, stroke = 0.3, color = vir1) +

      geom_linerange(data = steps_known, alpha = 0.5, color = vir2) +
      geom_point(data = steps_known, aes(shape = ig, fill = ig), alpha = 0.7,
                 stroke = 0.35, color = vir1) +

      # Every other panel keeps the fixed aesthetics of version 1.
      geom_linerange(data = ranef_df[ranef_df$par_name != "steps", ],
                     alpha = 0.5, color = vir2) +
      geom_point(data = ranef_df[ranef_df$par_name != "steps", ], alpha = 0.7,
                 shape = 21, stroke = 0.35, color = vir1, fill = vir2) +

      # `breaks` and named `labels` are given explicitly: with the layers in
      # this order the two keys otherwise come out labelled the wrong way round.
      scale_fill_manual(values = c(known = vir2, unknown = vir3),
                        breaks = ig_levels, labels = ig_labels, name = NULL) +
      scale_shape_manual(values = c(known = 21, unknown = 24),
                         breaks = ig_levels, labels = ig_labels, name = NULL) +
      guides(fill = guide_legend(override.aes = list(alpha = 1, size = 2)))
  }

  p +
    geom_text(aes(x, y, label = prob), data = probs, inherit.aes = FALSE,
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
          axis.line = element_line(linewidth = 0.3),
          legend.position = "bottom",
          legend.margin = margin(t = -2, unit = "mm"),
          legend.text = element_text(size = 9))
}

fig3 <- params_figure(probs_data)
save_fig(fig3, "fig3_params_fwi", width = 17, height = 10)

# Version 2, with the fires that have no ignition point in the kappa panel.
# The 178 extra intervals stretch that panel's y range, so its label has to be
# placed again over the range that is actually drawn.
probs_data_v2 <- probs_data
k <- which(probs_data_v2$par_name == "steps")
lo <- min(c(ranef_df$eti_lower_95[ranef_df$par_name == "steps"],
            nonfocal_df$eti_lower_95))
hi <- max(c(ranef_df$eti_upper_95[ranef_df$par_name == "steps"],
            nonfocal_df$eti_upper_95))
probs_data_v2$y[k] <- lo + prob_y_frac * (hi - lo)

fig3_v2 <- params_figure(probs_data_v2, extra_df = nonfocal_df)
save_fig(fig3_v2, "fig3_params_fwi_v2", width = 17, height = 10.8)
