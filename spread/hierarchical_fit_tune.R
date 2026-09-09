# Stage 2, step 2 of 4. ADAPTATION: one long chain, then proposal-sd tuning.
#
# Runs a single 10,000-iteration chain to get dispersed starting points, then
# tunes the Metropolis-Hastings proposal sd of the three M-H blocks (the
# area ~ steps coefficients, the 178 `steps` of the fires with no ignition point,
# and `stepsU`) towards an acceptance rate of 0.44. The tuning is a small
# regression loop: run K short chains, fit sigma ~ acceptance, predict the sigma
# that gives 0.44, then invert the fit (acceptance ~ sigma, beta GAM) and solve.
#
#   reads   files/hierarchical_model/par_start.rds
#   writes  files/hierarchical_model/run0.rds, sd_jump_tune.rds
#   cost    about 285 s per 10,000 iterations on one core; the K = 20 tuning
#           chains of 1,000 iterations add roughly 10 minutes
#
# Run from the repo root. Next: spread/hierarchical_fit_run.R.

library(tidyverse)
library(terra)
library(mgcv)          # gam, to tune the proposals
library(truncnorm)

source(file.path("R", "flammability_indices_functions.R"))
source(file.path("R", "mcmc_functions_smc.R"))
source(file.path("R", "hierarchical_fit_data.R"))
source(file.path("R", "hierarchical_mcmc_functions.R"))

# Settings ---------------------------------------------------------------

# Smoke test: a few iterations on one core, everything written to
# files/hierarchical_model/test/ so the real fit cannot be overwritten. Set it
# from outside with
#   Rscript -e 'test_mode <- TRUE; source("spread/hierarchical_fit_tune.R")'
if (!exists("test_mode")) test_mode <- FALSE
dirs <- hierarchical_fit_dirs(test_mode)

list2env(hierarchical_fit_setup(), globalenv())
par_start <- read_fit("par_start.rds", dirs)
list2env(hierarchical_fit_priors(par_start), globalenv())

# MCMC adaptation ---------------------------------------------------------

# run a long chain to get good starting points
nsim <- 10000
ns <- 1000   # iterations per tuning chain
K <- 20      # tuning steps

# Smoke test: still enough iterations that an acceptance rate is neither 0 nor 1
# (the beta GAM below needs that), but ~2 minutes instead of ~20.
if (test_mode) { nsim <- 500; ns <- 200; K <- 12 }

# Diagnostic plots go to a file when this runs unattended, to the device when
# Ivan steps through it in RStudio.
if (!interactive()) pdf(file.path(dirs$out_dir, "tune_diagnostics.pdf"))

system.time(
  run0 <- mcmc(nsim = nsim, sd_jump_out = T)
)

# 285.632 s / 10000 iter
# 285.632 * 100 / 3600 # 7.93 h para correr 1e6 muestras.
# 7.93 * 1.5 # 11.895 h para 1.5 M
xiter <- 1:nsim

par(mfrow = c(2, 4))
for(v in 1:(n_coef+1)) {
  # v = 1
  yy <- range(c(run0$fixef[v, 1:2, ], sqrt(run0$fixef[v, "s2", ])))
  plot(run0$fixef[v, "a", ] ~ xiter, type = "l", ylim = yy,
       main = par_names_all[v])
  lines(run0$fixef[v, "b", ] ~ xiter, col = "red")
  lines(sqrt(run0$fixef[v, "s2", ]) ~ xiter, col = "green")
}
par(mfrow = c(1, 1))

yy <- range(run0$stepsU)
plot(run0$stepsU ~ xiter, type = "l", ylim = yy, main = "stepsU")

saveRDS(run0, file.path(dirs$out_dir, "run0.rds"))
run0 <- readRDS(file.path(dirs$out_dir, "run0.rds"))

# Initial proposal sigma:
tmp <- run0$fixef["area", , ]
tmp[3, ] <- sqrt(tmp[3, ]) # sd_jump for sigma, not sigma2
area_jump <- apply(tmp, 1, sd)

sd_jump1 <- list(
  area = sqrt(area_jump ^ 2 * 2),
  steps = sqrt(apply(run0$steps, 1, sd) ^ 2 * 2),
  stepsU = sqrt(sd(logit_scaled(run0$stepsU, Umin, Umax)) ^ 2 * 2)
)
# posterior sd after a long run, just for curiosity
burn <- floor(nsim * 0.1) # 1000 of the canonical 10000
sd_post <- list(
  area = apply(run0$fixef[7, , burn:nsim, drop = F], 1:2, sd),
  steps = apply(run0$steps[, burn:nsim], 1, sd),
  stepsU = sd(logit_scaled(run0$stepsU, Umin, Umax))
)

# first run, to get acceptance
run1 <- mcmc(nsim = ns, sd_jump = sd_jump1, samples = run0, sd_jump_out = T)
a1 <- acceptance(run1)

# acceptance trial steps (K set above)

# placeholders for acceptance and jump sigma
accept_track <- list(
  area = run1$fixef[n_coef+1, , 1:K],
  steps = run1$steps[, 1:K],
  stepsU = run1$stepsU[1:K]
)
accept_track$area[, ] <- NA
accept_track$steps[, ] <- NA
accept_track$stepsU[] <- NA

sigma_track <- accept_track

# fill sigma and accept in the first run
accept_track$area[, 1] <- a1$area
accept_track$steps[, 1] <- a1$steps
accept_track$stepsU[1] <- a1$stepsU

sigma_track$area[, 1] <- sd_jump1$area
sigma_track$steps[, 1] <- sd_jump1$steps
sigma_track$stepsU[1] <- sd_jump1$stepsU

# Fill 4 sigma values below and above the first, to fit the first regression
# using 5 data points
factors <- seq(0.1, 2, by = 0.2)
lf <- length(factors)
for(k in 2:(lf+1)) {
  print(k)
  sigma_track$area[, k] <- sd_jump1$area * factors[k-1]
  sigma_track$steps[, k] <- sd_jump1$steps * factors[k-1]
  sigma_track$stepsU[k] <- sd_jump1$stepsU * factors[k-1]

  # run MCMC
  sss <- list(area = sigma_track$area[, k],
              steps = sigma_track$steps[, k],
              stepsU = sigma_track$stepsU[k])
  run_k <- mcmc(ns, sd_jump = sss, samples = run0)

  # compute and store acceptance
  a_k <- acceptance(run_k)
  accept_track$area[, k] <- a_k$area
  accept_track$steps[, k] <- a_k$steps
  accept_track$stepsU[k] <- a_k$stepsU
}

# iterative fitting
for(k in (lf+2):K) {
  # k = 12
  print(k)
  # use previous runs to fit a regression of sigma ~ accept, and choose the
  # predicted sigma for accept = 0.44

  # area parameters
  for(j in 1:3) { # loop over (a, b, s2)
    # j = 1
    dd <- data.frame(
      aa = accept_track$area[j, 1:(k-1)],
      ss = sigma_track$area[j, 1:(k-1)]
    )

    # remove sigma too close to zero
    dd <- dd[dd$ss >= 1e-4, ]
    dd$lss = log(dd$ss)

    # fit regression
    if(k < 10) {
      mm <- lm(lss ~ aa + I(aa ^ 2), data = dd)
    } else {
      mm <- gam(lss ~ s(aa, k = 6), data = dd, method = "REML")
    }

    ss_pred <- predict(mm, newdata = data.frame(aa = 0.44),
                       se.fit = F) |> exp()
    sigma_track$area[j, k] <- ifelse(ss_pred < 1e-4, 1e-4, ss_pred)
  }

  # steps
  for(j in 1:J2) {
    # get previous data
    dd <- data.frame(
      aa = accept_track$steps[j, 1:(k-1)],
      ss = sigma_track$steps[j, 1:(k-1)]
    )

    # remove sigma too close to zero
    dd <- dd[dd$ss >= 1e-4, ]
    dd$lss = log(dd$ss)

    # fit regression
    if(k < 10) {
      mm <- lm(lss ~ aa + I(aa ^ 2), data = dd)
    } else {
      mm <- gam(lss ~ s(aa, k = 6), data = dd, method = "REML")
    }

    ss_pred <- predict(mm, newdata = data.frame(aa = 0.44),
                       se.fit = F) |> exp()
    sigma_track$steps[j, k] <- ifelse(ss_pred < 1e-4, 1e-4, ss_pred)
  }
  
  # stepsU

  # get previous data
  dd <- data.frame(
    aa = accept_track$stepsU[1:(k-1)],
    ss = log(sigma_track$stepsU[1:(k-1)])
  )
  
  # remove sigma too close to zero
  dd <- dd[dd$ss >= 1e-4, ]
  dd$lss = log(dd$ss)
  
  # fit regression
  if(k < 10) {
    mm <- lm(lss ~ aa + I(aa ^ 2), data = dd)
  } else {
    mm <- gam(lss ~ s(aa, k = 6), data = dd, method = "REML")
  }
  
  ss_pred <- predict(mm, newdata = data.frame(aa = 0.44),
                     se.fit = F) |> exp()
  sigma_track$stepsU[k] <- ifelse(ss_pred < 1e-4, 1e-4, ss_pred)
  
  # run MCMC
  sss <- list(area = sigma_track$area[, k],
              steps = sigma_track$steps[, k],
              stepsU = sigma_track$stepsU[k])
  run_k <- mcmc(ns, sd_jump = sss, samples = run0)

  # compute and store acceptance
  a_k <- acceptance(run_k)
  accept_track$area[, k] <- a_k$area
  accept_track$steps[, k] <- a_k$steps
  accept_track$stepsU[k] <- a_k$stepsU
}

# Fit reverse model (acceptance ~ sigma) and choose that value.
sd_jump_tune <- list(
  area = sigma_track$area[, K],  # place-holder
  steps = sigma_track$steps[, K],
  stepsU = sigma_track$stepsU[K]
)

# area parameters
for(j in 1:3) {
  # get data
  dd <- data.frame(
    aa = accept_track$area[j, 1:K],
    ss = sigma_track$area[j, 1:K]
  )

  # fit gam
  mm <- gam(aa ~ s(ss, k = 6), family = betar(),
            data = dd, method = "REML")

  fn <- function(ss) {
    apred <- predict(mm, newdata = data.frame(ss = ss), type = "response")
    return((apred - 0.44) ^ 2)
  }

  opt <- optim(sigma_track$area[j, K], fn, method = "Brent",
               lower = min(dd$ss), upper = max(dd$ss))

  sd_jump_tune$area[j] <- opt$par

  # Visualize
  tit <- paste("area", colnames(sd_jump1$area)[j], sep = "; ")
  ppp <- data.frame(ss = seq(min(dd$ss), max(dd$ss), length.out = 100))
  ppp$y <- predict(mm, ppp, type = "response")
  plot(aa ~ ss, data = dd, main = tit, xlab = "Sigma", ylab = "Acceptance")
  lines(y ~ ss, data = ppp)
  abline(v = opt$par, col = 2, lty = 2)
  abline(h = 0.44, col = 4, lty = 2)
}

# steps
for(j in 1:J2) {
  dd <- data.frame(
    aa = accept_track$steps[j, 1:K],
    ss = sigma_track$steps[j, 1:K]
  )

  # fit gam
  mm <- gam(aa ~ s(ss, k = 6), family = betar(),
            data = dd, method = "REML")

  fn <- function(ss) {
    apred <- predict(mm, newdata = data.frame(ss = ss), type = "response")
    return((apred - 0.44) ^ 2)
  }

  opt <- optim(sigma_track$steps[j, K], fn, method = "Brent",
               lower = min(dd$ss), upper = max(dd$ss))

  sd_jump_tune$steps[j] <- opt$par
}

# StepsU
dd <- data.frame(
  aa = accept_track$stepsU[1:K],
  ss = sigma_track$stepsU[1:K]
)

# fit gam
mm <- gam(aa ~ s(ss, k = 6), family = betar(),
          data = dd, method = "REML")

fn <- function(ss) {
  apred <- predict(mm, newdata = data.frame(ss = ss), type = "response")
  return((apred - 0.44) ^ 2)
}

opt <- optim(sigma_track$stepsU[K], fn, method = "Brent",
             lower = min(dd$ss), upper = max(dd$ss))

sd_jump_tune$stepsU <- opt$par


# compare posterior sd with tune sd
plot(sd_jump_tune$steps ~ sd_post$steps)
mm <- lm(sd_jump_tune$steps ~ sd_post$steps - 1)
abline(c(0, coef(mm))) # coef(mm) = 2.3

fftune <- as.vector(sd_jump_tune$area)
ffpost <- as.vector(sd_post$area)
plot(fftune ~ ffpost)
mm <- lm(fftune ~ ffpost - 1)
abline(c(0, coef(mm))) # coef(mm) = 0.28

sd_post$stepsU; sd_jump_tune$stepsU

saveRDS(sd_jump_tune, file.path(dirs$out_dir, "sd_jump_tune.rds"))

if (!interactive()) dev.off()
