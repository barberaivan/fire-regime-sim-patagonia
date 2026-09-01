# Figure 6 — DHARMa quantile residuals for the 57 focal fires: burned area
# overall and by vegetation class, plus the two shape metrics the paper keeps.
#
# What is being asked, panel by panel: for each fire, is the OBSERVED value a
# plausible draw from the `nsim` values the model simulates for that same fire,
# from that same ignition point? DHARMa turns that into a scaled residual — the
# empirical quantile of the observation inside its own simulated predictive
# distribution, randomized across ties for the count metrics — which is uniform
# under a well-calibrated model. Sorting the 57 of them and plotting against
# `ppoints(57)` gives one uniform Q-Q per panel: on the 1:1 line = calibrated,
# below it = the model simulates too much, above it = too little.
#
# Two random-effect modes in every panel:
#   fitted    — each fire's own posterior random effect. A fit diagnostic (the
#               fire's data informed the parameters).
#   simulated — a fresh draw from the population distribution at that fire's
#               FWI. The honest out-of-sample question, and the one the regime
#               simulator actually asks.
#
# The eight panels, in the 3 x 3 layout, filled by row (the ninth cell holds
# the legend):
#   all vegetation | wet forest | subalpine forest
#   dry forest     | shrubland  | grassland
#   compactness    | wind-axis deviation | [legend]
#
# Only the 57 FOCAL fires appear here, for both halves. Burned area per
# vegetation class is comparable between observed and simulated only from the
# same ignition point, because what is available to burn around that point
# dominates the answer — and the shape metrics are asked the same way, per
# fire, so they need the ignition point too. The 184 fires without one carry
# the record-wide size/shape validation instead (Fig. 7).
#
# Input:  files/hierarchical_model/focal_metrics.rds, written by
#         spread/simulate_focal_metrics.R — which is where the simulation
#         protocol, and the per-fire wind axis the deviation is measured
#         against, are documented.
# Runs in seconds.

library(ggplot2)
library(DHARMa)
library(viridis)
theme_set(theme_bw())

# Settings ----------------------------------------------------------------

set.seed(20260901)          # createDHARMa randomizes ties

# A vegetation class with almost nothing to burn is a structural zero: the
# observed area is 0, nearly every simulation is 0, and the residual is little
# more than tie randomization. Fires with fewer than `min_available` cells of a
# class are dropped from that class's panel — a handful of pixels carries no
# more information than none at all. `veg_available` is saved for exactly this.
drop_unavailable <- TRUE
min_available <- 30         # cells, i.e. 2.7 ha

fig_dir <- file.path("manuscript-spread", "figures")
fit_dir <- file.path("files", "hierarchical_model")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# Panels, in the order they are drawn. `integer` picks DHARMa's tie
# randomization, which the count metrics need and the two continuous ones
# must not have.
panels <- data.frame(
  metric = c("size", "size_wet", "size_subalpine", "size_dry",
             "size_shrubland", "size_grassland", "compactness", "axis_dev"),
  label = c("All vegetation types", "Wet forest", "Subalpine forest",
            "Dry forest", "Shrubland", "Grassland",
            "Compactness", "Deviation from wind axis"),
  veg = c(NA, "wet", "subalpine", "dry", "shrubland", "grassland", NA, NA),
  integer = c(rep(TRUE, 6), FALSE, FALSE)
)

# Data --------------------------------------------------------------------

fm <- readRDS(file.path(fit_dir, "focal_metrics.rds"))
sim <- fm$sim               # iter x metric x fire
obs <- fm$obs               # fire x metric
J <- dim(sim)[3]
nsim <- fm$nsim
ids_fit <- grep("^fit_", dimnames(sim)$iter)
ids_sim <- grep("^sim_", dimnames(sim)$iter)
stopifnot(J == nrow(obs), length(ids_fit) == nsim, length(ids_sim) == nsim,
          all(panels$metric %in% dimnames(sim)$metric))

# Residuals ---------------------------------------------------------------

#' Simulated values for one metric and one mode, as a fires x nsim matrix
#'
#' A simulated fire of fewer than three cells has no principal axis, so
#' `axis_dev` is NA there by construction. Those draws are resampled from the
#' fire's valid ones rather than dropped, which keeps the matrix rectangular
#' for DHARMa and makes the panel ask the conditional question it should ask:
#' GIVEN the model produced a fire at all, is the observed shape typical of it?
#' The fraction affected is reported at the end.
sim_matrix <- function(metric, ids, keep) {
  m <- t(sim[ids, metric, keep, drop = FALSE][, 1, ])
  bad <- rowSums(is.na(m))
  for (i in which(bad > 0)) {
    ok <- m[i, !is.na(m[i, ])]
    if (length(ok) == 0) stop("fire ", rownames(m)[i], " has no valid ", metric)
    m[i, is.na(m[i, ])] <- sample(ok, bad[i], replace = TRUE)
  }
  m
}

#' Which fires enter a panel
panel_fires <- function(veg) {
  if (is.na(veg) || !drop_unavailable) return(seq_len(J))
  which(fm$veg_available[, veg] >= min_available)
}

res_table <- do.call("rbind", lapply(seq_len(nrow(panels)), function(k) {
  pk <- panels[k, ]
  keep <- panel_fires(pk$veg)

  one_mode <- function(ids, mode) {
    d <- createDHARMa(simulatedResponse = sim_matrix(pk$metric, ids, keep),
                      observedResponse = obs[keep, pk$metric],
                      integerResponse = pk$integer)
    r <- sort(d$scaledResiduals)
    data.frame(panel = pk$label, ranef = mode, n = length(r),
               q_obs = r, q_exp = ppoints(length(r)))
  }

  rbind(one_mode(ids_fit, "Fitted parameters"),
        one_mode(ids_sim, "Simulated parameters"))
}))

res_table$panel <- factor(res_table$panel, levels = panels$label)
res_table$ranef <- factor(res_table$ranef,
                          levels = c("Fitted parameters", "Simulated parameters"))

# Figure ------------------------------------------------------------------

# Aesthetics as in the thesis version: filled circles, viridis over the first
# half of the ramp, dark strips with white text. Eight panels in a 3 x 3 grid
# leave the bottom-right cell empty, and the legend goes in it.
bgcol <- "#1a1a1a"

p <- ggplot(res_table, aes(q_exp, q_obs, color = ranef, fill = ranef)) +
  geom_abline(intercept = 0, slope = 1, linewidth = 0.5, linetype = "dashed") +
  geom_point(shape = 21, size = 1.5, stroke = 0.4) +
  scale_color_viridis(discrete = TRUE, option = "D", end = 0.5) +
  scale_fill_viridis(discrete = TRUE, option = "D", end = 0.5, alpha = 0.4) +
  scale_x_continuous(breaks = c(0, 0.25, 0.5, 0.75, 1)) +
  scale_y_continuous(breaks = c(0, 0.25, 0.5, 0.75, 1)) +
  facet_wrap(vars(panel), ncol = 3, axes = "all",
             axis.labels = "margins") +
  coord_fixed() +
  labs(x = "Expected quantiles", y = "Observed quantiles") +
  theme(panel.border = element_blank(),
        panel.grid = element_blank(),
        axis.line = element_line(linewidth = 0.3),
        axis.text = element_text(size = 8),
        axis.title = element_text(size = 10),
        legend.position = "inside",
        legend.position.inside = c(0.83, 0.15),
        legend.title = element_blank(),
        legend.text = element_text(size = 9,
                                   margin = margin(l = -1, unit = "mm")),
        legend.key.spacing.y = unit(1, "mm"),
        panel.spacing.y = unit(4, "mm"),
        panel.spacing.x = unit(4, "mm"),
        strip.background = element_rect(color = bgcol, fill = bgcol),
        strip.text = element_text(color = "white", size = 9))

for (ext in c("png", "pdf")) {
  f <- file.path(fig_dir, paste0("fig6_dharma_metrics.", ext))
  ggsave(f, plot = p, width = 17, height = 17, units = "cm",
         dpi = 350, bg = "white")
  cat("wrote", f, "\n")
}

# Report ------------------------------------------------------------------

# The caption numbers: how far each panel is from calibration. KS against
# uniform on the residuals themselves, and the fraction of fires whose observed
# value sits below the simulated median (0.5 under calibration; for the size
# panels, < 0.5 means the model burns too much).
cat("\n== calibration, by panel ==\n")
tab <- do.call("rbind", lapply(split(res_table,
                                     list(res_table$panel, res_table$ranef)),
                               function(x) {
  ks <- suppressWarnings(ks.test(x$q_obs, "punif"))
  data.frame(panel = as.character(x$panel[1]), ranef = as.character(x$ranef[1]),
             n = nrow(x), mean_res = mean(x$q_obs),
             frac_below_median = mean(x$q_obs < 0.5),
             ks_D = unname(ks$statistic), ks_p = ks$p.value)
}))
rownames(tab) <- NULL
tab <- tab[order(tab$ranef, match(tab$panel, panels$label)), ]
# One row per panel per mode, printed narrow enough not to wrap in a terminal.
cat(sprintf("%-26s %-10s %3s %8s %8s %6s %9s\n",
            "panel", "ranef", "n", "mean_res", "frac<med", "KS_D", "KS_p"))
for (i in seq_len(nrow(tab))) {
  cat(sprintf("%-26s %-10s %3d %8.3f %8.3f %6.3f %9.1e\n",
              tab$panel[i], if (tab$ranef[i] == "Fitted parameters") "fitted" else "simulated",
              tab$n[i], tab$mean_res[i], tab$frac_below_median[i],
              tab$ks_D[i], tab$ks_p[i]))
}

cat("\ndrop_unavailable =", drop_unavailable, "| min_available =",
    min_available, "cells\n")
for (k in which(!is.na(panels$veg))) {
  n_out <- J - length(panel_fires(panels$veg[k]))
  cat(sprintf("  %-18s %2d fires dropped\n", panels$label[k], n_out))
}

na_ori <- mean(is.na(sim[, "orientation", ]))
worst <- max(apply(is.na(sim[, "orientation", ]), 2, mean))
cat(sprintf("simulations with no principal axis (< 3 cells): %.2f %% overall, %.1f %% in the worst fire\n",
            100 * na_ori, 100 * worst))
