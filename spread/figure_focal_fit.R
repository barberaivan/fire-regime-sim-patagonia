# Figures S4 and S5 — how well the model reproduces each of the 57 focal fires,
# fire by fire. Fig. 6 asks the same question as a calibration test over the 57
# together; these two put the individual fires back on the page.
#
#   Fig. S4 (figS4_overlap)  spatial overlap with the observed fire — the
#           fraction of the union of the two footprints that both share. One
#           point per fire, its posterior mean under a SIMULATED random effect
#           on x against the mean under its own FITTED one on y, with 95 % HDIs
#           both ways. Everything sits above the 1:1 line by construction (a
#           fire's own fitted parameters must do at least as well as a fresh
#           draw); how far above is the price of predicting out of sample, and
#           the y values are the overlaps quoted for Fig. 5.
#
#   Fig. S5 (figS5_size_quotient)  simulated / observed burned area, per fire,
#           with fires ordered by observed size. 1 is perfect. Two panels for
#           the two random-effect modes, on free y scales — the simulated-ranef
#           quotients run orders of magnitude higher, which is the whole point.
#           The pattern to read is the trend along x: the model overshoots the
#           small fires and holds on the large ones.
#
# Input:  files/hierarchical_model/focal_metrics.rds, written by
#         spread/simulate_focal_metrics.R — 2000 simulations per fire per mode,
#         from the full posterior, one draw per simulated fire. The same file
#         Fig. 6 reads, so the three figures are the same simulations.
#         (The older metrics_table.rds of spread/hierarchical_fit.R holds the
#         same quantities from a superseded run; do not mix them.)
# Runs in seconds.

library(ggplot2)
library(viridis)
theme_set(theme_bw())

source(file.path("R", "spread_figure_functions.R"))

# Settings ----------------------------------------------------------------

fit_dir <- file.path("files", "hierarchical_model")

mode_levels <- c("Fitted random effects", "Simulated random effects")

# Data --------------------------------------------------------------------

fm <- readRDS(file.path(fit_dir, "focal_metrics.rds"))
sim <- fm$sim               # iter x metric x fire
obs <- fm$obs               # fire x metric
fire_ids <- dimnames(sim)[[3]]
J1 <- length(fire_ids)
ids_fit <- grep("^fit_", dimnames(sim)$iter)
ids_sim <- grep("^sim_", dimnames(sim)$iter)
stopifnot(length(ids_fit) == fm$nsim, length(ids_sim) == fm$nsim)

#' Per-fire posterior summary of one metric under one mode
#'
#' @return data.frame with one row per fire, in `fire_ids` order.
per_fire <- function(metric, ids, transform = identity) {
  m <- transform(sim[ids, metric, , drop = FALSE][, 1, ])   # nsim x fire
  out <- as.data.frame(t(apply(m, 2, summarise_post)))
  out$fire_id <- fire_ids
  out
}


# Figure S4 — overlap -----------------------------------------------------

ov_fit <- per_fire("overlap", ids_fit)
ov_sim <- per_fire("overlap", ids_sim)

cols <- c("mean", "hdi_lower_95", "hdi_upper_95")
ov <- data.frame(
  fire_id = fire_ids,
  setNames(ov_fit[, cols], paste0(c("mean", "lower", "upper"), "_fit")),
  setNames(ov_sim[, cols], paste0(c("mean", "lower", "upper"), "_sim"))
)

figS4 <- ggplot(ov) +
  geom_linerange(aes(x = mean_sim, y = mean_fit,
                     ymin = lower_fit, ymax = upper_fit), alpha = 0.3) +
  geom_linerange(aes(y = mean_fit, xmin = lower_sim, xmax = upper_sim),
                 orientation = "y", alpha = 0.3) +
  geom_point(aes(mean_sim, mean_fit), size = 2, shape = 21) +
  scale_y_continuous(limits = c(0, 0.9), expand = c(0.005, 0.005)) +
  scale_x_continuous(limits = c(0, 0.8), expand = c(0.01, 0.01)) +
  coord_fixed() +
  ylab("Overlap from fitted random effects") +
  xlab("Overlap from simulated random effects") +
  nice_theme()

save_fig(figS4, "figS4_overlap", width = 9, height = 12)


# Figure S5 — size quotients ----------------------------------------------

# The quotient is formed per simulation and then summarised, not as a ratio of
# summaries: the distribution of simulated/observed is what the panel shows,
# and its mean is not the mean simulated size over the observed one.
size_obs <- obs[, "size"]
stopifnot(all(size_obs > 0))

quot <- function(ids) {
  q <- t(sim[ids, "size", , drop = FALSE][, 1, ]) / size_obs   # fire x nsim
  out <- as.data.frame(t(apply(q, 1, summarise_post)))
  out$fire_id <- fire_ids
  out$size_obs <- size_obs
  out
}

qsumm <- rbind(cbind(quot(ids_fit), ranef = mode_levels[1]),
               cbind(quot(ids_sim), ranef = mode_levels[2]))
qsumm$ranef <- factor(qsumm$ranef, levels = mode_levels)
qsumm$fire_id <- factor(qsumm$fire_id,
                        levels = fire_ids[order(size_obs)])

figS5 <- ggplot(qsumm, aes(fire_id, mean,
                           ymin = hdi_lower_95, ymax = hdi_upper_95)) +
  geom_hline(yintercept = 1, color = viridis(1, begin = 0.7)) +
  geom_linerange(alpha = 0.5) +
  geom_point(size = 2, alpha = 0.7) +
  facet_wrap(vars(ranef), nrow = 2, scales = "free_y",
             axes = "all", axis.labels = "margins",
             strip.position = "right") +
  scale_y_continuous(expand = c(0.01, 0.01)) +
  ylab("Simulated / observed fire size") +
  xlab("Fire ID (increasing size)") +
  nice_theme() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5,
                                   size = 7),
        panel.spacing.y = unit(6, "mm"))

save_fig(figS5, "figS5_size_quotient", width = 15, height = 16)


# Report ------------------------------------------------------------------

cat(sprintf("\noverlap over %d focal fires\n", J1))
cat(sprintf("  fitted    median %.3f  (range %.3f-%.3f)\n",
            median(ov$mean_fit), min(ov$mean_fit), max(ov$mean_fit)))
cat(sprintf("  simulated median %.3f  (range %.3f-%.3f)\n",
            median(ov$mean_sim), min(ov$mean_sim), max(ov$mean_sim)))

cat("\nsize quotient (simulated / observed), posterior means\n")
for (m in mode_levels) {
  x <- qsumm$mean[qsumm$ranef == m]
  cat(sprintf("  %-26s median %6.2f   %2d of %d fires within [0.5, 2]\n",
              m, median(x), sum(x >= 0.5 & x <= 2), J1))
}
