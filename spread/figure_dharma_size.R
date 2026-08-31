# Figure 6 — DHARMa quantile residuals of burned area, overall and by
# vegetation class, for the 57 focal fires.
#
# Reproduces `dharma_size_fit_sim.png` from the old PhD repo (the "Dharma for
# size" block of `spread/hierarchical model fitting_FWIZ2_SMC.R`), against this
# repo's canonical fit.
#
# What is being asked: for each fire, is the OBSERVED burned area a plausible
# draw from the 2000 areas the model simulates for that same fire, from that
# same ignition point? DHARMa turns that into a scaled residual — the empirical
# quantile of the observation inside its own simulated predictive distribution,
# randomized across ties because area in cells is a count — which is uniform
# under a well-calibrated model. Sorting them and plotting against `ppoints(J)`
# gives one uniform Q-Q per class: on the 1:1 line = calibrated, below it = the
# model simulates too much area, above it = too little.
#
# Two random-effect modes, both already in `metrics_table.rds`:
#   fitted    — each fire's own posterior random effect. This is a fit
#               diagnostic (the fire's data informed the parameters).
#   simulated — a fresh draw from the population distribution at that fire's
#               FWI. This is the honest out-of-sample question, and the one the
#               regime simulator actually asks.
#
# Only the 57 FOCAL fires appear here. Burned area per vegetation class is only
# comparable between observed and simulated when both start from the same
# ignition point, and what is available to burn around that point dominates the
# answer — so the 184 fires without a mapped ignition point cannot enter this
# figure (they carry the shape/size validation instead; see
# spread/validation_analysis.R).
#
# Inputs (all written by spread/hierarchical_fit.R):
#   files/hierarchical_model/metrics_table.rds   4000 x 7 x 57
#   files/hierarchical_model/size_obs.rds        57 x 6 (total + 5 veg classes)
#   files/hierarchical_model/veg_available.rds   57 x 5 (cells of each class)
# Runs in seconds.

library(ggplot2)
library(DHARMa)
library(viridis)
theme_set(theme_bw())

# Settings ----------------------------------------------------------------

set.seed(20260831)          # createDHARMa randomizes ties

# Fires where a vegetation class is entirely ABSENT from the landscape are a
# structural zero: observed 0, every simulation 0, and the residual is pure tie
# randomization carrying no information about the model. Dropping them is
# defensible and is why hierarchical_fit.R saves `veg_available` at all — but
# the thesis figure kept all 57 fires in every panel, so the faithful
# reproduction is the default. Fires affected: 5 wet, 10 subalpine, 5 dry,
# 0 shrubland, 0 grassland.
drop_unavailable <- FALSE

veg_levels <- c("Wet forest", "Subalpine forest", "Dry forest",
                "Shrubland", "Grassland")
class_levels <- c(veg_levels, "All vegetation types")

fig_dir <- file.path("manuscript-spread", "figures")
fit_dir <- file.path("files", "hierarchical_model")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# Data --------------------------------------------------------------------

metrics_table <- readRDS(file.path(fit_dir, "metrics_table.rds"))
size_obs <- readRDS(file.path(fit_dir, "size_obs.rds"))
veg_available <- readRDS(file.path(fit_dir, "veg_available.rds"))

J <- dim(metrics_table)[3]
iter <- dimnames(metrics_table)$iter
ids_fit <- grep("^fit_", iter)
ids_sim <- grep("^sim_", iter)
stopifnot(length(ids_fit) == length(ids_sim),
          nrow(size_obs) == J, nrow(veg_available) == J,
          ncol(size_obs) == length(veg_levels) + 1)

# Drop `overlap`; what is left is size and the five per-class sizes, in the
# same column order as `size_obs`.
size_metrics <- dimnames(metrics_table)$metric[-1]
stopifnot(length(size_metrics) == ncol(size_obs))

# fire x nsim, per metric
sim_by_metric <- function(m, ids) t(metrics_table[ids, m + 1L, ])

# Availability mask per column of `size_obs`: the total column is always
# available, the five class columns only where the class exists at all.
available <- cbind(rep(TRUE, J), veg_available > 0)

# Residuals ---------------------------------------------------------------

unif_q <- function(n) ppoints(n)

res_table <- do.call("rbind", lapply(seq_along(size_metrics), function(m) {
  keep <- if (drop_unavailable) which(available[, m]) else seq_len(J)

  one_mode <- function(ids, label) {
    d <- createDHARMa(simulatedResponse = sim_by_metric(m, ids)[keep, ],
                      observedResponse = size_obs[keep, m],
                      integerResponse = TRUE)
    r <- sort(d$scaledResiduals)
    data.frame(veg_class = class_levels[m], ranef = label,
               q_obs = r, q_exp = unif_q(length(r)))
  }

  rbind(one_mode(ids_fit, "Fitted parameters"),
        one_mode(ids_sim, "Simulated parameters"))
}))

res_table$veg_class <- factor(res_table$veg_class, levels = class_levels)
res_table$ranef <- factor(res_table$ranef,
                          levels = c("Fitted parameters", "Simulated parameters"))

# Figure ------------------------------------------------------------------

# Aesthetics as in the thesis version: filled circles, viridis over the first
# half of the ramp, dark strips with white text.
bgcol <- "#1a1a1a"

p <- ggplot(res_table, aes(q_exp, q_obs, color = ranef, fill = ranef)) +
  geom_abline(intercept = 0, slope = 1, linewidth = 0.5, linetype = "dashed") +
  geom_point(shape = 21, size = 1.8, stroke = 0.4) +
  scale_color_viridis(discrete = TRUE, option = "D", end = 0.5) +
  scale_fill_viridis(discrete = TRUE, option = "D", end = 0.5, alpha = 0.4) +
  scale_x_continuous(breaks = c(0, 0.25, 0.5, 0.75, 1)) +
  scale_y_continuous(breaks = c(0, 0.25, 0.5, 0.75, 1)) +
  facet_wrap(vars(veg_class), nrow = 2, axes = "all",
             axis.labels = "margins") +
  coord_fixed() +
  labs(x = "Expected quantiles", y = "Observed quantiles") +
  theme(panel.border = element_blank(),
        panel.grid = element_blank(),
        axis.line = element_line(linewidth = 0.3),
        axis.text = element_text(size = 8),
        axis.title = element_text(size = 10),
        legend.position = "bottom",
        legend.title = element_blank(),
        legend.text = element_text(size = 9,
                                   margin = margin(l = -1, unit = "mm")),
        panel.spacing.y = unit(5, "mm"),
        panel.spacing.x = unit(5, "mm"),
        strip.background = element_rect(color = bgcol, fill = bgcol),
        strip.text = element_text(color = "white", size = 10))

for (ext in c("png", "pdf")) {
  f <- file.path(fig_dir, paste0("fig6_dharma_size_veg.", ext))
  ggsave(f, plot = p, width = 15, height = 13, units = "cm",
         dpi = 350, bg = "white")
  cat("wrote", f, "\n")
}

# Report ------------------------------------------------------------------

# The caption numbers: how far each class is from calibration. KS against
# uniform on the residuals themselves, and the fraction of fires whose observed
# area sits below the simulated median (0.5 under calibration; < 0.5 means the
# model burns too much).
cat("\n== calibration of burned area, by class ==\n")
tab <- do.call("rbind", lapply(split(res_table,
                                     list(res_table$veg_class, res_table$ranef)),
  function(x) {
    if (!nrow(x)) return(NULL)
    data.frame(class = as.character(x$veg_class[1]),
               ranef = as.character(x$ranef[1]),
               n = nrow(x),
               mean_resid = round(mean(x$q_obs), 3),
               frac_below_median = round(mean(x$q_obs < 0.5), 3),
               ks_D = round(suppressWarnings(
                 ks.test(x$q_obs, "punif"))$statistic, 3),
               ks_p = signif(suppressWarnings(
                 ks.test(x$q_obs, "punif"))$p.value, 3))
  }))
rownames(tab) <- NULL
print(tab[order(match(tab$class, class_levels), tab$ranef), ])
cat("\nmean_resid 0.5 and frac_below_median 0.5 = calibrated;",
    "< 0.5 = the model simulates too much area.\n")
cat("drop_unavailable =", drop_unavailable, "\n")
