# Stage 2, step 1 of 4. STARTING VALUES for the hierarchical spread fit.
#
# Fits the auxiliary logit-normal `steps ~ FWI` + `area ~ steps` model in Stan
# over all 235 fires, and turns the stage-1 ABC-SMC samples into a cloud of MLE
# point estimates that the MCMC starts from.
#
#   reads   files/posterior_samples_stage1/samples_all_fires.rds (through
#           hierarchical_fit_setup()), spread/steps_model_logitnorm.stan
#   writes  files/hierarchical_model/steps_model_stan_samples.rds
#           files/hierarchical_model/par_start.rds
#           files/hierarchical_model/fwi_mean_sd_spread.rds
#   cost    a few minutes for the Stan fit, a few minutes for the MLE loop
#
# BOTH heavy steps are OFF by default (`do_sample`, `do_estimate`), because the
# artifacts are on disk and every downstream script only reads them. Turn one on
# to regenerate it. This is the same do_*/read-back pattern the paper-figure
# scripts use.
#
# Run from the repo root. Next: spread/hierarchical_fit_tune.R.

library(tidyverse)
library(viridis)
library(terra)
library(rstan)
library(logitnorm)
library(bayesplot)
library(truncnorm)
theme_set(theme_bw())

source(file.path("R", "flammability_indices_functions.R"))
source(file.path("R", "hierarchical_fit_data.R"))

# Settings ---------------------------------------------------------------

# Smoke test: a few iterations on one core, everything written to
# files/hierarchical_model/test/ so the real fit cannot be overwritten. Set it
# from outside with
#   Rscript -e 'test_mode <- TRUE; source("spread/hierarchical_fit_inits.R")'
if (!exists("test_mode")) test_mode <- FALSE
dirs <- hierarchical_fit_dirs(test_mode)

do_sample <- FALSE    # re-run the Stan steps model?
do_estimate <- FALSE  # re-compute the MLE starting values?

list2env(hierarchical_fit_setup(out_dir = dirs$out_dir), globalenv())

# Get FWIZ range in the study period ------------------------------------

pnnh <- vect(file.path("data", "protected_areas", "apn_limites.shp"))
pnnh <- pnnh[pnnh$nombre == "Nahuel Huapi", ]
pnnh <- project(pnnh, "EPSG:5343")

# FWI
fwi_fort <- rast(file.path("data", "fwi_daily_1998-2022", "24km",
                           "fwi_fortnights_19970701_20230630_standardized.tif"))
fwi_fort <- project(fwi_fort, "EPSG:5343")
fwi_fort <- crop(fwi_fort, pnnh, snap = "out")
fwiz_range_ori <- range(values(fwi_fort))

fwiz_range <- (fwiz_range_ori - fwi_mean) / fwi_sd
fwiz_range 
# -1.786781  3.401912 // 52 km
# -1.963114  3.671563 // 24 km

# Steps model with Stan (starting values) ---------------------------------

# Ytry contains contrained steps samples, at simulator scale
steps_fitted1 <- as.numeric(apply(Ytry["steps", , ], 1, mean))

sdata1 <- list(
  N1 = J1, N2 = J2, 
  
  steps1 = steps_fitted1,
  fwi1 = fwi1,
  fwi2 = fwi2,
  
  area1 = area1,
  area2 = area2,
  areaL = areaL, # lower area at log scale
  
  L = 2, # forces to simulate spread outside the ignition
  Umax = Umax, # 2000 = 60000 / 30, # 60 km max
  Umin = Umin,
  
  prior_steps_int_mn = 0,
  prior_steps_int_sd = 100,
  prior_steps_b_sd = 10,
  prior_steps_sigma_sd = 2,
  
  prior_area_int_mn = mean(c(area1, area2)),
  prior_area_int_sd = sd(c(area1, area2)),
  prior_area_b_sd = 3,
  prior_area_sigma_sd = sd(c(area1, area2)) * 2
)
L <- sdata1$L

if (do_sample) {
  smodel <- stan_model("spread/steps_model_logitnorm.stan")
  stansteps <- sampling(
    smodel, sdata1, seed = 234669, refresh = 100,
    cores = if (test_mode) 1 else 4,
    chains = if (test_mode) 1 else 4,
    iter = if (test_mode) 20 else 4000,
    warmup = if (test_mode) 10 else 1000
  )
  saveRDS(stansteps, file.path(dirs$out_dir, "steps_model_stan_samples.rds"))
}
stansteps <- read_fit("steps_model_stan_samples.rds", dirs)

# mcmc_dens(stansteps, pars = c("steps_int", "steps_b", "U"),
#           facet_args = list(nrow = 2))
# mcmc_pairs(stansteps, pars = c("steps_int", "steps_b", "U", "steps_sigma"))

# Plot steps curves
spar <- as.matrix(stansteps, pars = c("steps_int", "steps_b", "U", "steps_sigma"))
ni <- 500
ids <- sample(1:nrow(spar), ni, F)
nr <- 200

fwiseq <- seq(min(fwi_all), 10, length.out = nr)
mumat_logit <- matrix(NA, nr, ni)
mumat <- matrix(NA, nr, ni)
ylims <- matrix(NA, nr, 2)

# Compute mean
L <- stepsL
for(i in 1:ni) {
  it = ids[i]
  mumat_logit[, i] <- spar[it, "steps_int"] + spar[it, "steps_b"] * fwiseq
  for(j in 1:nr) {
    mumat[j, i] <-
      momentsLogitnorm(mumat_logit[j, i], spar[it, "steps_sigma"])["mean"] *
      (spar[it, "U"] - L) + L
  }
}
# limits of predictive distribution
for(r in 1:nr) {
  # r = 1
  yl <- rnorm(ni * 4, mumat_logit[r, ], spar[ids, "steps_sigma"])
  yy <- plogis(yl) * (spar[ids, "U"] - L) + L
  ylims[r, ] <- quantile(yy, probs = c(0.025, 0.975), method = 8)
}
# df to plot
pred1 <- data.frame(
  fwi = fwiseq,
  mu = rowMeans(mumat),
  mu_lower = apply(mumat, 1, quantile, probs = 0.025, method = 8),
  mu_upper = apply(mumat, 1, quantile, probs = 0.975, method = 8),
  y_lower = ylims[, 1],
  y_upper = ylims[, 2]
)
# "data" to plot
datadf1 <- data.frame(
  steps = c(
    steps_fitted1,
    as.matrix(stansteps, "steps2") |> colMeans()
  ),
  fwi = fwi_all,
  type = rep(c("ABC-area-fit", "only-area-fit"), c(J1, J2))
)
# plot
p1 <- ggplot(pred1, aes(fwi, mu, ymin = mu_lower, ymax = mu_upper)) +
  geom_ribbon(mapping = aes(fwi, mu, ymin = y_lower, ymax = y_upper),
              alpha = 0.15) +
  geom_ribbon(alpha = 0.3) +
  geom_line() +
  geom_point(data = datadf1, mapping = aes(x = fwi, y = steps, color = type),
             inherit.aes = F, shape = 21, size = 2, stroke = 0.65) +
  scale_color_viridis(discrete = T, end = 0.5) +
  geom_vline(xintercept = max(fwiz_range),
             color = viridis(1, option = "C", begin = 0.5)) +
  scale_y_continuous(limits = c(0, 2000), expand = c(0.001, 00.01)) +
  theme(panel.grid.minor = element_blank()) +
  ylab("Steps") +
  xlab("FWI anomaly")
p1

# ggsave("spread/figures/step_model_stan_logitnorm.png",
#        width = 15, height = 12, units = "cm", plot = p1)

# check area ~ steps:
datadf1$steps_log <- log(datadf1$steps)
datadf1$area_log <- area_all
plot(area_log ~ steps_log, datadf1)
mm <- lm(area_log ~ steps_log, data = datadf1)
abline(coef(mm), col = 2, lwd = 2)

# Starting values from MLE estimates --------------------------------------

# using samples from the first-step abc, get a point estimate of all parameters.
par_start <- vector("list", 4)
names(par_start) <- c("fixef", "ranef", "steps", "stepsU")
nsim <- N1 / 2
set.seed(123)
ii <- sample(1:N1, size = nsim, replace = F) # choose random effects
iistan <- sample(1:nrow(spar), size = nsim, replace = F) # choose stan samples

# get parameters from Stan for the steps-area model
spar_area <- as.matrix(stansteps, c("area_int", "area_b", "area_sigma"))
spar_steps2 <- as.matrix(stansteps, c("steps_logit2"))

par_start[["fixef"]] <- array(NA, dim = c(n_coef + 1, 3, nsim),
                    dimnames = list(
                      par_names = c(par_names, "area"),
                      par_class = c("a", "b", "s2"),
                      iter = 1:nsim
                    ))

par_start[["ranef"]] <- Ytry[, , 1:nsim]
par_start[["ranef"]][, , ] <- NA

mm <- matrix(NA, J2, nsim)
rownames(mm) <- fire_ids_nonspread
par_start[["steps"]] <- mm

par_start[["stepsU"]] <- numeric(nsim)

# Compute estimates
if (do_estimate) {
  for(i in 1:nsim) {
    print(i)

    ranef_ <- Ytry[, , ii[i]]
    par_start[["ranef"]][, , i] <- ranef_

    # simple parameters (before steps)
    for(v in 1:(n_coef-1)) {
      parvals <- ranef_[v, ]
      mod <- lm(parvals ~ fwi1)
      par_start[["fixef"]][v, , i] <- c(coef(mod), sigma(mod) ^ 2)
    }

    # parameters for steps ~ fwi and area ~ steps regression taken from Stan model
    temp1 <- spar[iistan[i], c("steps_int", "steps_b", "steps_sigma")]
    temp1["steps_sigma"] <- temp1["steps_sigma"] ^ 2
    par_start[["fixef"]]["steps", , i] <- temp1

    temp2 <- spar_area[iistan[i], c("area_int", "area_b", "area_sigma")]
    temp2["area_sigma"] <- temp2["area_sigma"] ^ 2
    par_start[["fixef"]]["area", , i] <- temp2

    # steps for non-spread fires
    par_start[["steps"]][, i] <- spar_steps2[iistan[i], ]

    # Upper steps parameter
    par_start[["stepsU"]][i] <- spar[iistan[i], "U"]
  }
  saveRDS(par_start, file.path(dirs$out_dir, "par_start.rds"))
}
par_start <- read_fit("par_start.rds", dirs)
