# Constants, data and priors of the hierarchical spread fit (stage 2).
#
# This is the "inline data manipulation" half of the old spread/hierarchical_fit.R
# monolith, turned into functions so each of the stage-2 scripts
# (spread/hierarchical_fit_{inits,tune,run}.R, spread/hierarchical_predictions.R,
# spread/exploratory_steps_area.R) can set itself up in three lines instead of
# re-running everything above it in one long file.
#
# Usage, in every stage-2 script:
#
#   source(file.path("R", "hierarchical_fit_data.R"))
#   list2env(hierarchical_fit_setup(), globalenv())
#
# The objects go into the GLOBAL environment on purpose: mcmc() and friends
# (R/hierarchical_mcmc_functions.R) read them as globals, exactly as they did in
# the monolith. Nothing about the numbers changes.
#
# Needs the tidyverse and terra loaded, and R/flammability_indices_functions.R
# sourced (for `fi_params`, `vfi_calc`, `tfi_calc`).

#' Where stage 2 reads from and writes to
#'
#' @param test_mode TRUE sends every write to files/hierarchical_model/test/, so
#'   a smoke run cannot overwrite the real fit. Reads still fall back to the
#'   canonical folder for anything the test has not produced itself.
#' @return list with `in_dir` and `out_dir`.
hierarchical_fit_dirs <- function(test_mode = FALSE) {
  in_dir <- file.path("files", "hierarchical_model")
  out_dir <- if (test_mode) file.path(in_dir, "test") else in_dir
  if (test_mode) dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  list(in_dir = in_dir, out_dir = out_dir)
}

#' Read a stage-2 artifact, preferring the run's own output folder
#'
#' In a normal run `in_dir` and `out_dir` are the same folder and this is just
#' readRDS(). In a test run it picks up whatever the test itself wrote and falls
#' back to the canonical artifact for the rest.
read_fit <- function(file, dirs) {
  p <- file.path(dirs$out_dir, file)
  if (!file.exists(p)) p <- file.path(dirs$in_dir, file)
  readRDS(p)
}

#' Constants and prepared data for the hierarchical fit
#'
#' Everything the sampler and the prediction scripts need: the parameter names
#' and their [L, U] support, the stage-1 posterior samples (`Ytry`), the 235
#' fires' FWI and area, the design matrices, and the `steps` bounds.
#'
#' The 235 rows are 57 fires with a mapped ignition point (subscript 1, spread
#' simulated) plus 178 without one (subscript 2, entering only through the
#' area ~ steps regression). Two fires of the record were split in two, so the
#' FWI csv's 233 rows become 235 here.
#'
#' @param out_dir if given, the FWI standardization used by the fit is written
#'   there as fwi_mean_sd_spread.rds (the paper figures read it back through
#'   `fwi_scale()`). NULL writes nothing, which is what a read-only script wants.
#' @return a named list; assign it into the global environment with `list2env()`.
hierarchical_fit_setup <- function(out_dir = NULL) {

  # Climatic data ------------------------------------------------------------

  # fwi_data <- read.csv(file.path("data", "climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ.csv"))
  fwi_data <- read.csv(file.path("data", "climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ2.csv"))

  # Fire polygons (to get area) ---------------------------------------------

  ff <- vect("data/patagonian_fires_spread.shp")
  ff$area_ha <- expanse(ff) / 1e4 # turn m2 to ha

  # Constants ---------------------------------------------------------------

  # constants for fire spread simulation
  upper_limit <- 1
  n_veg <- 5
  veg_names <- c("wet", "subalpine", "dry", "shrubland", "grassland")
  veg_levels <- c("Wet forest", "Subalpine forest", "Dry forest", "Shrubland", "Grassland")

  n_terrain <- 2
  terrain_names <- c("slope", "wind")
  terrain_variables <- c("elevation", "wdir", "wspeed")
  n_nd <- n_fi <- 2        # flammability indices
  nd_variables <- c("vfi", "tfi")

  par_names <- c("intercept", nd_variables, terrain_names, "steps")
  n_coef <- length(par_names)

  par_names_all <- c(par_names, "area")

  n_par <- length(par_names_all)
  n_pt <- 3 # b0, b1, s2

  # flammability indices parameters
  fi_params <- readRDS(file.path(
    "data", "flammability_indices", "flammability_indices.rds"
  ))

  slope_sd <- fi_params$slope_term_sd # 0.1891275

  # support for parameters
  ext_alpha <- 50
  ext_beta <- 30

  stepsL <- 2

  params_lower <- c(-ext_alpha, rep(0, n_coef-2), stepsL)
  params_upper <- c(ext_alpha, rep(ext_beta, n_coef-2), NA)
  names(params_lower) <- names(params_upper) <- par_names
  params_upper["slope"] <- ext_beta / slope_sd

  support <- rbind(params_lower, params_upper)
  colnames(support) <- names(params_lower) <- names(params_upper) <- par_names

  # synonims
  Lpar <- params_lower
  Upar <- params_upper

  support_width <- apply(support, 2, diff)

  # summary of predictors that make the flammability indices
  data_summ <- readRDS(file.path(
    "data", "flammability_indices", "ndvi_elevation_summary.rds"
  ))


  # to simulate fires and check model
  lands_dir <- file.path("data", "focal_fires", "landscapes")
  nmet <- n_veg + 2 # size by veg, size total, overlap
  met_names <- c("overlap", "size",
                 "wet", "subalpine", "dry", "shrubland", "grassland")

  # Load and prepare data ---------------------------------------------------

  # data with steps bounds
  size_data <- readRDS(file.path(
    "data", "focal_fires", "fire_size_data.rds"
  ))
  rownames(size_data) <- size_data$fire_id

  # dir to load files
  target_dir <- file.path("files", "posterior_samples_stage1")
  Ytry <- readRDS(file.path(target_dir, "samples_all_fires.rds"))
  Ytry <- aperm(Ytry, c(2, 3, 1))
  N1 <- dim(Ytry)[3] # number of samples from stage 1

  # Get steps into constrained scale (not log).
  # They where saved in log because a previous model used a log-link model
  # for steps. Now, the mcmc samples at the logit scale of a common space
  # (2, stepsU), with stepsU estimated. Because the prior from stage1 
  # has to be subtracted in the step 2 of the Lunn method, it's easier
  # to sample them in the constrained (simulator) scale. 
  Ytry[n_coef, , ] <- exp(Ytry[n_coef, , ])

  # limits for stepsU
  Umin <- ceiling(max(Ytry["steps", , ])) + 0.00120
  Umax <- 2000 # = 60000 m / 30 m

  # fire names
  fire_ids <- dimnames(Ytry)[[2]]

  # merge with FWI data
  # two fires were split, but they have the same FWI.
  fires_data_0 <- fwi_data[!(fwi_data$fire_id %in% c("2011_19", "2015_47")), ]
  fires_data_1 <- fwi_data[fwi_data$fire_id %in% c("2011_19", "2015_47"), ]
  fires_data_2 <- fires_data_1[c(1, 1, 2, 2), ]

  fires_data_2$fire_id[fires_data_2$fire_id == "2011_19"] <-
    fire_ids[grep("2011_19", fire_ids)]

  fires_data_2$fire_id[fires_data_2$fire_id == "2015_47"] <-
    fire_ids[grep("2015_47", fire_ids)]

  # bring area of separated fires
  for(i in 1:nrow(fires_data_2)) {
    fires_data_2$area_ha[i] <- ff$area_ha[ff$fire_id == fires_data_2$fire_id[i]]
  }

  # put together all fires
  fires_data <- rbind(fires_data_0, fires_data_2)
  rownames(fires_data) <- NULL

  # add log area and scaled fwi
  fires_data$area_ha_log <- log(fires_data$area_ha)

  fwi_mean <- mean(fires_data$fwi_fort_expquad) # more than zero
  fwi_sd <- sd(fires_data$fwi_fort_expquad)     # less than 1

  # export fwi scale (only when a run asks for it: the paper figures read this
  # back through fwi_scale(), so it must not be rewritten by every read-only
  # script that calls setup)
  fwi_spread_mean_sd <- list(fwi_mean = fwi_mean,
                             fwi_sd = fwi_sd)
  if (!is.null(out_dir)) {
    saveRDS(fwi_spread_mean_sd, file.path(out_dir, "fwi_mean_sd_spread.rds"))
  }

  fires_data$fwi <- (fires_data$fwi_fort_expquad - fwi_mean) / fwi_sd
  rownames(fires_data) <- fires_data$fire_id

  fires_data_spread <- fires_data[fires_data$fire_id %in% fire_ids, ]
  fires_data_spread <- fires_data_spread[fire_ids, ]

  fires_data_nonspread <- fires_data[!(fires_data$fire_id %in% fire_ids), ]

  fire_ids_nonspread <- fires_data_nonspread$fire_id
  nfires_nonspread <- length(fire_ids_nonspread)
  nfires_spread <- length(fire_ids)

  # lower bound for fire area (10 ha)
  areaL <- log(10-1e-6)

  # N of random effects
  J1 <- nfires_spread
  J2 <- nfires_nonspread
  J <- J1 + J2
  ids1 <- 1:J1
  ids2 <- (J1+1):J

  # variables for both subsets of fires
  fwi1 <- fires_data_spread$fwi
  fwi2 <- fires_data_nonspread$fwi
  fwi_all <- c(fwi1, fwi2)

  area1 <- fires_data_spread$area_ha_log
  area2 <- fires_data_nonspread$area_ha_log
  area_all <- c(area1, area2)

  # design matrices
  X_ <- cbind(rep(1, J1), fwi1)
  tXX_ <- t(X_) %*% X_

  Xsteps <- cbind(rep(1, J2), fwi2)
  Xlong <- rbind(X_, Xsteps)
  tXXlong <- t(Xlong) %*% Xlong

  # order size data based on fire_ids, to get steps_bounds
  size_data <- size_data[fire_ids, ]
  steps_bounds <- cbind(rep(5, J1), size_data$steps_upper)
  rownames(steps_bounds) <- fire_ids

  setup <- as.list(environment())
  setup$out_dir <- NULL
  setup
}

#' Priors for the hyperparameters
#'
#' Needs `par_start` (files/hierarchical_model/par_start.rds, written by
#' spread/hierarchical_fit_inits.R): two of the prior means are centred on it.
#' `n_coef` and `par_names_all` come from hierarchical_fit_setup().
#'
#' @return list with `b0`, `S0`, `S0_inv`, `t0`, `d0`, to be `list2env()`-ed.
hierarchical_fit_priors <- function(par_start,
                                    n_coef = get("n_coef", globalenv()),
                                    par_names_all = get("par_names_all", globalenv())) {

  # priors for intercepts and slopes. b0 has the means, S0 has the vcov (diagonal).
  b0 <- matrix(0, 2, n_coef + 1)
  colnames(b0) <- par_names_all
  rownames(b0) <- c("a", "b")
  b0["a", "steps"] <- mean(par_start$fixef["steps", "a", ])
  b0["a", "area"] <- mean(par_start$fixef["area", "a", ])

  # The prior sd for regression coefficients is the same for all parameters
  # (sd = 10)
  S0 <- diag(rep(10 ^ 2, 2)) # used for truncnorm regression (area), updated with MH
  S0_inv <- solve(S0)        # used for gibbs updates

  # s2 for all parameters has inv-gamma prior, for conjugacy.
  # invgamma::dinvgamma(x, t0, d0)
  t0 <- 1; d0 <- 1 / 1000

  list(b0 = b0, S0 = S0, S0_inv = S0_inv, t0 = t0, d0 = d0)
}
