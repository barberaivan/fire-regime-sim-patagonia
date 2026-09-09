# EXPLORATORY (not a paper figure): `steps` against FWI, and fire size against
# `steps`, for all 235 fires, split by whether the ignition point is known.
#
# This is the one plotting block of the old spread/hierarchical_fit.R monolith
# that was kept when the rest were deleted (every paper figure has its own
# script in spread/ now). It is worth keeping because it is the only place the
# two halves of the fit are drawn side by side: the 57 fires whose spread was
# actually simulated in stage 1 ("Known" ignition location) and the 178 that
# enter the model only through the area ~ steps regression ("Unknown"). Their
# `steps` posteriors are not estimated the same way, and this is where that
# shows.
#
#   reads   files/hierarchical_model/spread_model_samples.rds
#           files/hierarchical_model/mu_samples_prediction.rds
#   writes  spread/figures/steps_fwi_area.{png,pdf}
#   cost    seconds
#
# THE SCALE TRAP: draws$ranef["steps", , ] is on the natural scale, while
# draws$steps (the 178) is on the logit scale between stepsL and that draw's own
# stepsU. The first block below is what puts them on one scale; do not skip it.
#
# Run from the repo root.

library(tidyverse)
library(viridis)
library(terra)
library(deeptime)     # ggarrange2
library(ggh4x)        # facet_nested_wrap
library(truncnorm)
theme_set(theme_bw())

source(file.path("R", "flammability_indices_functions.R"))
source(file.path("R", "mcmc_functions_smc.R"))       # invlogit_scaled
source(file.path("R", "spread_figure_functions.R"))  # summarise_post
source(file.path("R", "hierarchical_fit_data.R"))

dirs <- hierarchical_fit_dirs(FALSE)
list2env(hierarchical_fit_setup(), globalenv())

draws <- readRDS(file.path(dirs$in_dir, "spread_model_samples.rds"))
npost <- ncol(draws$steps)

vir1 <- viridis(1, option = "C")
vir2 <- viridis(1, begin = 0.5, option = "C")

# The population-level steps ~ FWI curve ----------------------------------

# mu_samples is what spread/hierarchical_predictions.R wrote; npred and the FWI
# sequence have to be rebuilt exactly as that script defined them, or the join
# below silently misaligns.
npred <- 150
fwi_seq <- seq(min(fwi_all), max(fwi_all), length.out = npred)
fwi_seq_ori <- (fwi_seq * fwi_sd) + fwi_mean

mu_samples <- readRDS(file.path(dirs$in_dir, "mu_samples_prediction.rds"))
stopifnot(dim(mu_samples)[1] == npred)

# summarize posterior and longanize.
mu_summ <- apply(mu_samples, 1:2, summarise_post)
dimnames(mu_summ) <- list(
  metric = dimnames(mu_summ)[[1]],
  row = 1:npred,
  par_name = par_names
)
mu_summ_sub <- mu_summ[c("mean", "eti_lower_95", "eti_upper_95"), , ]
mu_df1 <- as.data.frame.table(mu_summ_sub, responseName = "par_value")
mu_df <- pivot_wider(mu_df1, names_from = "metric", values_from = "par_value")
mu_df$row <- as.numeric(as.character(mu_df$row))

# merge with fwi data
df_fwi <- data.frame(row = 1:npred, fwi_z = fwi_seq,
                     fwi = fwi_seq_ori)
mu_df <- left_join(mu_df, df_fwi, by = "row")

# Steps-FWI-Area predictions (all fires) -----------------------------------

# unconstrain the non-spread steps
steps2_draws <- draws$steps
for(j in 1:npost) {
  steps2_draws[, j] <- invlogit_scaled(draws$steps[, j], stepsL, draws$stepsU[j])
} 

# merge all steps
steps_all_draws <- rbind(
  draws$ranef[n_coef, , ],
  steps2_draws
)

steps_summ <- apply(steps_all_draws, 1, summarise_post) |> t() |> as.data.frame()
steps_summ$fwi <- fwi_all
steps_summ$fwi_ori <- fwi_all * fwi_sd + fwi_mean
steps_summ$area_log <- area_all
steps_summ$ig_location <- c(rep("Known", J1),
                            rep("Unknown", J2))

## Use mu_samples
pred_fwi <- mu_df[mu_df$par_name == "steps", ]
pred_fwi$fwi_ori <- fwi_seq_ori
# add title wierdly
pred_fwi$ig <- "Ignition location"
steps_summ$ig <- "Ignition location"

fig_steps <-
ggplot(steps_summ, aes(fwi_ori, mean, ymin = eti_lower_95, ymax = eti_upper_95)) +

  # geom_smooth(aes(fwi_ori, mean), inherit.aes = F,
  #             method = "lm", se = F, linetype = "dashed", color = vir1,
  #             linewidth = 0.35) +

  geom_ribbon(data = pred_fwi,
              mapping = aes(fwi_ori, mean, ymin = eti_lower_95, ymax = eti_upper_95),
              inherit.aes = F, color = NA, alpha = 0.4, fill = vir1) +
  geom_line(data = pred_fwi, color = vir1,
            mapping = aes(fwi_ori, mean),
            inherit.aes = F) +
  geom_linerange(alpha = 0.5, color = vir2) +
  geom_point(alpha = 0.7, shape = 21, color = vir1, fill = vir2, stroke = 0.35) +

  ggh4x::facet_nested_wrap(vars(ig, ig_location),
                           axes = "all", remove_labels = "all") +

  ylab("Steps") +
  xlab("Fire Weather Index anomaly") +

  scale_y_continuous(expand = c(0.001, 0.001), limits = c(0, 1150),
                     breaks = seq(0, 1000, by = 250)) +

  theme(strip.background = element_rect(color = "white", fill = "white"),
        strip.text = element_text(size = 11),
        panel.spacing.x = unit(4, "mm"),
        panel.border = element_blank(),
        panel.grid = element_blank(),
        legend.position = "none",
        axis.line = element_line(linewidth = 0.3))
fig_steps

# area ~ steps

# summarize steps at log scale
steps_log_summ <- apply(log(steps_all_draws), 1, summarise_post) |> t() |> as.data.frame()
steps_log_summ$fwi <- fwi_all
steps_log_summ$fwi_ori <- fwi_all * fwi_sd + fwi_mean
steps_log_summ$area_log <- area_all
steps_log_summ$ig_location <- c(rep("Known", J1),
                                rep("Unknown", J2))

npred <- 150
pred_area <- data.frame(steps = seq(min(steps_log_summ$eti_lower_95),
                                    max(steps_log_summ$eti_upper_95),
                                    length.out = npred))
predmat <- matrix(NA, npred, npost)
for(i in 1:npred) {
  predmat[i, ] <-
    as.vector(draws$fixef["area", "a", ]) +
    as.vector(draws$fixef["area", "b", ]) * pred_area$steps[i]

}

# predmat contains the normal mean, but as the area is truncated-normal,
# the true mean is another.
ss <- as.vector(draws$fixef["area", "s2", ]) |> sqrt()
predmat_mu <- predmat
# # Truncated-normal mean:
# for(i in 1:npost) {
#   predmat_mu[, i] <- etruncnorm(a = areaL, mean = predmat[, i], sd = ss[i])
# }

pred_area$mu <- rowMeans(predmat_mu)
pred_area$mu_lower <- apply(predmat_mu, 1, quantile, prob = 0.025)
pred_area$mu_upper <- apply(predmat_mu, 1, quantile, prob = 0.975)

fig_area <-
ggplot() +
  geom_hline(yintercept = log(10), linetype = "dashed", color = "gray") +

  geom_ribbon(data = pred_area,
              mapping = aes(steps, mu, ymin = mu_lower, ymax = mu_upper),
              inherit.aes = F, color = NA, alpha = 0.4, fill = vir1) +
  geom_line(data = pred_area, color = vir1,
            mapping = aes(steps, mu),
            inherit.aes = F) +

  geom_linerange(data = steps_log_summ, orientation = "y",
                 mapping = aes(x = mean, y = area_log, 
                               xmin = eti_lower_95, xmax = eti_upper_95,
                               color = ig_location),
                 alpha = 0.5, color = vir2) +
  geom_point(data = steps_log_summ,
             mapping = aes(mean, area_log),
             alpha = 0.7, shape = 21, color = vir1, fill = vir2) +

  scale_color_viridis(discrete = TRUE, end = 0.6) +

  facet_wrap(vars(ig_location), axes = "all", axis.labels = "margins") +

  xlab("Steps (log)") +
  ylab("Fire size (log ha)") +

  scale_y_continuous(expand = c(0.05, 0.05)) +

  theme(strip.background = element_blank(),
        strip.text = element_blank(),
        panel.spacing.x = unit(4, "mm"),
        panel.border = element_blank(),
        panel.grid = element_blank(),
        legend.position = "none",
        axis.line = element_line(linewidth = 0.3))
fig_area

fig_steps_area <- ggarrange2(
  fig_steps + theme(plot.margin = margin(b = 7, unit = "mm")),
  fig_area,
  nrow = 2
)
ggsave(
  "spread/figures/steps_fwi_area.png",
  plot = fig_steps_area, width = 17, height = 15, units = "cm"
)
ggsave(
  "spread/figures/steps_fwi_area.pdf",
  plot = fig_steps_area, width = 17, height = 15, units = "cm"
)
