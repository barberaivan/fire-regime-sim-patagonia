# Figure S3 — how the six spread parameters correlate ACROSS FIRES.
#
# The hierarchical model gives each fire its own parameter vector, drawn from a
# multivariate normal on the unconstrained scale with correlation matrix `rho`.
# `rho` itself is not what a reader wants to see: it is a correlation on the
# logit scale, between quantities with different bounds, and the transform to
# the simulator's scale is nonlinear. So each panel here is the posterior of
# the correlation coefficient BETWEEN THE TWO PARAMETERS AS THE SIMULATOR SEES
# THEM — computed by simulating a full set of 235 fires from each posterior
# draw, back-transforming, and correlating.
#
# Two densities per panel, and the difference between them is the point:
#   Marginal to FWI     fires drawn at their own FWI, so a correlation can come
#                       either from `rho` or from two parameters both
#                       responding to fire weather.
#   Conditional to FWI  every fire drawn at FWI = 0, which removes the shared
#                       weather driver and leaves only `rho`.
# Where the two coincide, FWI explains none of the association. The one place
# they separate clearly is steps-intercept and steps-VFI, which is the
# signature of fire weather acting through `steps` (Fig. 3).
#
# Input:  files/hierarchical_model/spread_model_samples.rds
# Cost:   the simulation is a few minutes; it is cached to
#         files/hierarchical_model/parameter_correlations.rds, so set
#         `do_compute <- FALSE` to retune the figure without redoing it.
#
# TWO DEFECTS OF THE THESIS VERSION ARE FIXED HERE, and nothing else about it
# is changed: (1) the inner panels used to carry white-on-white strip text,
# which rendered as ghost labels floating above each row; (2) the bottom axis
# ran -1 to 1 with zero panel spacing, so neighbouring panels printed "1.0"
# and "-1.0" on top of each other. The extreme breaks are dropped.

library(ggplot2)
library(viridis)
library(mgcv)      # rmvn
theme_set(theme_bw())

source(file.path("R", "focal_simulation_functions.R"))
source(file.path("R", "spread_figure_functions.R"))

# Settings ----------------------------------------------------------------

do_compute <- TRUE
do_plot <- TRUE

seed <- 20260901

fit_dir <- file.path("files", "hierarchical_model")
corr_file <- file.path(fit_dir, "parameter_correlations.rds")

# Model constants ---------------------------------------------------------

fi_params <- readRDS(file.path("data", "flammability_indices",
                               "flammability_indices.rds"))
bounds <- focal_par_bounds(fi_params)
par_names <- bounds$par_names
n_coef <- bounds$n_coef


# Stage 1 — the correlation posteriors ------------------------------------

if (do_compute) {

set.seed(seed)

draws <- readRDS(file.path(fit_dir, "spread_model_samples.rds"))
npost <- dim(draws$fixef)[3]

# The 235 fires the model was fitted to, and their design matrix.
fwi_all <- spread_fwi_all(draws)
J <- length(fwi_all)
Xlong <- cbind(1, fwi_all)
cat(J, "fires,", npost, "posterior draws\n")

combs <- as.data.frame(t(combn(par_names, 2)))
combs$num1 <- match(combs$V1, par_names)
combs$num2 <- match(combs$V2, par_names)

dcorr_list <- vector("list", nrow(combs))

for (i in seq_len(nrow(combs))) {
  v1 <- combs$V1[i]; v2 <- combs$V2[i]
  vv <- c(v1, v2)
  vv_num <- c(combs$num1[i], combs$num2[i])
  cat(sprintf("  %2d/%d  %s ~ %s\n", i, nrow(combs), v1, v2))

  # The 2 x 2 covariance of this pair, per posterior draw.
  s2_1 <- draws$fixef[v1, "s2", ]
  s2_2 <- draws$fixef[v2, "s2", ]
  covv <- sqrt(s2_1) * sqrt(s2_2) * draws$rho[v1, v2, ]

  V <- array(NA_real_, dim = c(2, 2, npost))
  V[1, 1, ] <- s2_1
  V[2, 2, ] <- s2_2
  V[1, 2, ] <- V[2, 1, ] <- covv

  # Population means at each fire's own FWI, on the unconstrained scale.
  mu1 <- Xlong %*% draws$fixef[v1, c("a", "b"), ]
  mu2 <- Xlong %*% draws$fixef[v2, c("a", "b"), ]
  mus <- aperm(abind::abind(mu1, mu2, along = 3), c(1, 3, 2))

  # Marginal: fires at their own FWI. Conditional: every fire at FWI = 0, so
  # only the between-fire covariance is left.
  zeroes <- matrix(0, J, 2)
  sims_marg <- sapply(1:npost, function(j) rmvn(J, mus[, , j], V[, , j]),
                      simplify = "array")
  sims_cond <- sapply(1:npost, function(j) rmvn(J, zeroes, V[, , j]),
                      simplify = "array")

  # To the simulator's scale. One bound pair per parameter, applied to a whole
  # J x npost slice at once — NOT `invlogit_scaled2()`, which reads a matrix as
  # one column per (L, U) pair and would silently take U[2] = NA here. `steps`
  # is the exception: its upper bound is estimated, so it is one draw at a time.
  scale_slice <- function(x, L, U) plogis(x) * (U - L) + L

  for (p in 1:2) {
    if (vv[p] != "steps") {
      L <- bounds$L[vv_num[p]]; U <- bounds$U[vv_num[p]]
      sims_marg[, p, ] <- scale_slice(sims_marg[, p, ], L, U)
      sims_cond[, p, ] <- scale_slice(sims_cond[, p, ], L, U)
    } else {
      for (j in 1:npost) {
        sims_marg[, p, j] <- scale_slice(sims_marg[, p, j],
                                         bounds$L["steps"], draws$stepsU[j])
        sims_cond[, p, j] <- scale_slice(sims_cond[, p, j],
                                         bounds$L["steps"], draws$stepsU[j])
      }
    }
  }

  corr_marg <- apply(sims_marg, 3, function(x) cor(x)[1, 2])
  corr_cond <- apply(sims_cond, 3, function(x) cor(x)[1, 2])

  # `adjust = 1.5`: 12000 draws over [-1, 1] resolve wiggles the default
  # bandwidth keeps and that are sampling noise here.
  dmarg <- density(corr_marg, from = -1, to = 1, n = 2^10, adjust = 1.5)
  dcond <- density(corr_cond, from = -1, to = 1, n = 2^10, adjust = 1.5)

  dcorr_list[[i]] <- data.frame(
    dens = c(dmarg$y, dcond$y),
    x = c(dmarg$x, dcond$x),
    type = factor(rep(c("Marginal to FWI", "Conditional to FWI"),
                      each = length(dmarg$y)),
                  levels = c("Marginal to FWI", "Conditional to FWI")),
    V1 = v1, V2 = v2,
    mean_marg = mean(corr_marg), mean_cond = mean(corr_cond)
  )
}

saveRDS(list(combs = combs, dcorr = dcorr_list, par_names = par_names),
        corr_file)
cat("saved", corr_file, "\n")

}


# Stage 2 — the figure ----------------------------------------------------

if (do_plot) {

cc <- readRDS(corr_file)
combs <- cc$combs
dcorr_list <- cc$dcorr

# A lower-triangular 5 x 5 grid of panels: columns are the first five
# parameters, rows the last five, so panel (row, col) is the pair
# (col_labs[col], row_labs[row]) and the upper triangle is empty. Filled by
# column, which is the order `combn()` produced the 15 pairs in.
lay <- matrix(c(1, 2, 3, 4, 5,
                NA, 6, 7, 8, 9,
                NA, NA, 10, 11, 12,
                NA, NA, NA, 13, 14,
                NA, NA, NA, NA, 15), ncol = 5)

col_labs <- par_labels(par_names[-n_coef])
row_labs <- par_labels(par_names[-1])

lwd_y <- 0.4
lwd_x <- 0.1

plist <- vector("list", 5)
for (p in 1:5) plist[[p]] <- vector("list", 5)

for (col in 1:5) {
  for (row in 1:5) {
    ii <- lay[row, col]

    if (is.na(ii)) {
      # An empty cell of the upper triangle. In the top row it still has to
      # carry the column strip, or the header would be missing there.
      d <- data.frame(V2 = row_labs[row], V1 = col_labs[col])
      plotcito <- ggplot(d) + geom_blank() +
        theme(panel.border = element_blank())

      if (row == 1) {
        plotcito <- plotcito +
          facet_grid(V2 ~ V1, switch = "y") +
          theme(strip.background = element_rect(color = strip_bgcol,
                                                fill = strip_bgcol),
                strip.text = element_text(color = "white", size = 11),
                strip.background.y = element_blank(),
                strip.text.y = element_blank())
      }

    } else {
      d <- dcorr_list[[ii]]
      d$V1 <- col_labs[col]
      d$V2 <- row_labs[row]

      plotcito <- ggplot(d) +
        geom_vline(xintercept = 0, linetype = "dotted", linewidth = 0.55) +
        geom_ribbon(aes(x = x, ymin = 0, ymax = dens, fill = type),
                    color = NA, alpha = 0.4) +
        geom_line(aes(x = x, y = dens, color = type), linewidth = 0.5) +
        scale_color_viridis(option = "C", discrete = TRUE, end = 0.5) +
        scale_fill_viridis(option = "C", discrete = TRUE, end = 0.5) +
        scale_y_continuous(expand = c(0, 0)) +
        # Breaks stop at +/- 0.5: with zero panel spacing, a "1.0" and the next
        # panel's "-1.0" print on top of each other.
        scale_x_continuous(expand = c(0, 0), limits = c(-1, 1),
                           breaks = c(-0.5, 0, 0.5)) +
        expand_limits(y = max(d$dens) * 1.05) +
        facet_grid(V2 ~ V1, switch = "y") +
        theme(legend.title = element_blank(),
              legend.position = "none",
              panel.grid = element_blank(),
              panel.spacing.x = unit(0, "line"),
              panel.border = element_blank(),
              axis.ticks.y = element_blank(),
              axis.text.y = element_blank(),
              axis.title = element_blank(),
              axis.line.x = element_line(linewidth = lwd_x),
              axis.line.y = element_line(linewidth = lwd_y),
              strip.background = element_rect(color = strip_bgcol,
                                              fill = strip_bgcol),
              strip.text = element_text(color = "white", size = 11),
              strip.placement = "inside")

      # Each label is said once: column names only along the top, row names
      # only down the left, x ticks only along the bottom.
      if (row > 1) {
        plotcito <- plotcito +
          theme(strip.background.x = element_blank(),
                strip.text.x = element_blank())
      }
      if (col > 1) {
        plotcito <- plotcito +
          theme(strip.background.y = element_blank(),
                strip.text.y = element_blank())
      }
      if (row < 5) {
        plotcito <- plotcito +
          theme(axis.ticks.x = element_blank(),
                axis.text.x = element_blank())
      }
      if (ii == 12) {   # the middle panel of the bottom row
        plotcito <- plotcito +
          theme(legend.position = "bottom", axis.title.x = element_text()) +
          xlab("Correlation coefficient")
      }
    }

    plist[[col]][[row]] <- plotcito
  }
}

# `egg::ggarrange` rather than patchwork: it aligns the panels of a ragged
# grid by their plot regions, which is what keeps the lower triangle square.
figS3 <- egg::ggarrange(plots = do.call("c", plist), byrow = FALSE)

save_fig(figS3, "figS3_parameter_correlations", width = 22, height = 20)

# Report ------------------------------------------------------------------

# The pairs that actually correlate, and the ones FWI explains: the caption
# needs both lists.
tab <- do.call("rbind", lapply(seq_along(dcorr_list), function(i) {
  d <- dcorr_list[[i]]
  data.frame(pair = paste(combs$V1[i], combs$V2[i], sep = " ~ "),
             marginal = d$mean_marg[1], conditional = d$mean_cond[1])
}))
tab$fwi_share <- tab$marginal - tab$conditional
tab <- tab[order(-abs(tab$marginal)), ]

cat("\nposterior mean correlation, on the simulator's scale\n")
cat(sprintf("%-22s %9s %11s %9s\n", "pair", "marginal", "conditional",
            "difference"))
for (i in seq_len(nrow(tab))) {
  cat(sprintf("%-22s %9.3f %11.3f %9.3f\n", tab$pair[i], tab$marginal[i],
              tab$conditional[i], tab$fwi_share[i]))
}

}
