# Stage 2, step 4 of 4. PREDICTIONS from the fitted hierarchical spread model.
#
# Four heavy loops that turn the 12,000 posterior draws into the four prediction
# artifacts the paper figures read. None of them re-fits anything; each averages
# the spread model over 200 freshly drawn random effects per posterior draw, so
# what comes out is the POPULATION-level curve, not one fire's.
#
#   reads   files/hierarchical_model/spread_model_samples.rds
#   writes  files/hierarchical_model/
#             mu_samples_prediction.rds            -> Fig. 3  (figure_params_fwi.R)
#             curves_df_prediction.rds             -> Fig. 2  (figure_spread_curves.R)
#             curves_df_prediction_raw_x.rds       -> Fig. S2 (figure_spread_curves.R)
#             spreadprob_veg_comparison_array.rds  -> Fig. 4  (figure_vegetation_effect.R)
#   cost    minutes each; the vegetation block is the slow one (it loops over
#           posterior draw x 21 FWI values x 5 vegetation types)
#
# Each block has its own do_* switch, so any one artifact can be regenerated
# alone. They share nothing but `draws` and the setup constants.
#
# FWI IS ON THE FIT'S STANDARDIZED SCALE here, as it is in the saved artifacts;
# the figure scripts put it back on the anomaly scale with fwi_to_original().
# See docs/spread.md -> "The paper's model figures".
#
# Run from the repo root. Needs spread/hierarchical_fit_run.R to have run.

library(tidyverse)
library(viridis)
library(terra)
library(FireSpread)   # rast_from_mat, for the PNNH landscape of the veg block
library(truncnorm)
theme_set(theme_bw())

source(file.path("R", "flammability_indices_functions.R"))
source(file.path("R", "mcmc_functions_smc.R"))       # invlogit_scaled
source(file.path("R", "focal_simulation_functions.R")) # invlogit_scaled2
source(file.path("R", "spread_figure_functions.R"))    # summarise_post
source(file.path("R", "hierarchical_fit_data.R"))

# Settings ---------------------------------------------------------------

# Smoke test: three posterior draws instead of 12,000, everything written to
# files/hierarchical_model/test/. Set it from outside with
#   Rscript -e 'test_mode <- TRUE; source("spread/hierarchical_predictions.R")'
if (!exists("test_mode")) test_mode <- FALSE
dirs <- hierarchical_fit_dirs(test_mode)

do_mu_samples <- TRUE   # Fig. 3:  parameters as a function of FWI
do_curves <- TRUE       # Fig. 2:  spread probability against its predictors
do_curves_raw <- TRUE   # Fig. S2: the same against the raw variables
do_veg_effect <- TRUE   # Fig. 4:  vegetation separation as FWI worsens

list2env(hierarchical_fit_setup(), globalenv())

# Load tidy samples -------------------------------------------------------

draws <- read_fit("spread_model_samples.rds", dirs)
npost <- ncol(draws$steps)

if (test_mode) {
  keep <- 1:3
  draws$fixef <- draws$fixef[, , keep, drop = FALSE]
  draws$rho <- draws$rho[, , keep, drop = FALSE]
  draws$ranef <- draws$ranef[, , keep, drop = FALSE]
  draws$steps <- draws$steps[, keep, drop = FALSE]
  draws$stepsU <- draws$stepsU[keep]
  npost <- length(keep)
}

if (do_mu_samples) {

  # Spread parameters as function of FWI ------------------------------------

  # a panel for each parameter, at the constrained scale, as a function of FWI
  # at its original scale. Use the FWI within the simulated fires?

  nr <- 200 # number of random effects to simulate in order to compute mean
  npred <- 150

  fwi_seq <- seq(min(fwi_all), max(fwi_all), length.out = npred)
  X <- cbind(rep(1, npred), fwi_seq)
  fwi_seq_ori <- (fwi_seq * fwi_sd) + fwi_mean

  ranef_raw <- matrix(rnorm(nr * n_coef), ncol = n_coef)

  # random effects array, placeholders
  ranef_tmp <- array(NA, dim = c(npred, n_coef, nr))
  ranef_cons <- array(NA, dim = c(npred, n_coef, nr))

  # array with posterior samples for the predicted average across raneffs
  mu_samples <- array(NA, dim = c(npred, n_coef, npost))

  # Loop to compute means
  for(i in 1:npost) {
    if(i %% 100 == 0) print(i)

    # mu at unconstrained scale
    mumat <- X %*% t(draws$fixef[1:n_coef, c("a", "b"), i])

    # Compute choleski factor of vcov matrix for random effects
    sds <- draws$fixef[1:n_coef, "s2", i] |> sqrt()
    rho <- draws$rho[, , i]
    V <- diag(sds) %*% rho %*% diag(sds)
    Vchol_U <- chol(V)

    # unconstrained centred random effects
    ranef_centred <- ranef_raw %*% Vchol_U

    # unconstrained random effects
    for(j in 1:nr) {
      ranef_tmp[, , j] <- t(t(mumat) + ranef_centred[j, ])
    }

    # constrain fixed-bounds parameters
    for(v in 1:(n_coef-1)) {
      # v = 1
      ranef_cons[, v, ] <- invlogit_scaled(ranef_tmp[, v, ], 
                                           Lpar[v], Upar[v])
    }
    # constrain steps
    ranef_cons[, n_coef, ] <- invlogit_scaled(ranef_tmp[, n_coef, ], 
                                         stepsL, draws$stepsU[i])
  
    # average raneffs
    mu_samples[, , i] <- apply(ranef_cons, 1:2, mean)
  }

  saveRDS(mu_samples, file.path(dirs$out_dir, "mu_samples_prediction.rds"))
}


if (do_curves) {

  # Spread probability curves ---------------------------------------------

  # Four panels, with spread prob as a function of vfi, tfi, slope and wind.
  # In all cases, the remaining predictors are fixed at zero (makes sense?),
  # so the FWI affects only the focal slope and the intercept.
  # From every posterior sample, 3 curves (3 FWI values) could be drawn, which are
  # the average across 200 random-effect curves each.

  # start by making a design matrix from the (expand-gridded) prediction
  # data.frame. Here, use regional data to define the range for predictors.

  # output: array curves_samples[npred, 3, npost]
  # For every posterior sample (i),
  # 01 - get simulated spread parameters for the three FWI values.
  #      array[3, n_coef, 200]
  # 02 - compute the array of spread-prob linear predictors, with dimension
  #      [npred, 3, 200]. then, apply plogis().
  # 03 - average curves across random effects obtaining the average curve as
  #      curve_mean[npred, 3]
  # 04 - store curves_samples[, , i] <- curve_mean

  # Load landscapes to find the 95 % percentile of wind speed.
  # Then, bear in mind that in landscapes wind speed was divided by the sd (1.41).
  # In the case of slope, it was not scaled.

  wind_sd <- 1.464333 # from landscapes_preparation.R
  wind_high_kmh <- 90 ## check later
  wind_high_mps <- wind_high_kmh / 3.6
  wind_high_z <- wind_high_mps / wind_sd

  vfi_low <- fi_params$vfi_z_hdi["vfi_lower"]
  vfi_high <- fi_params$vfi_z_hdi["vfi_upper"]

  tfi_low <- fi_params$tfi_z_hdi["tfi_lower"]
  tfi_high <- fi_params$tfi_z_hdi["tfi_upper"]

  nseq <- 400

  pdspread <- rbind(
    # vfi ___________
    expand.grid(
      vfi = seq(vfi_low, vfi_high, length.out = nseq),
      tfi = 0,
      slope_ang = 0,
      wind_kmh = 0,
      varying_var = "vfi"
    ),
    # tfi ___________
    expand.grid(
      vfi = 0,
      tfi = seq(tfi_low, tfi_high, length.out = nseq),
      slope_ang = 0,
      wind_kmh = 0,
      varying_var = "tfi"
    ),
    # slope ___________
    expand.grid(
      vfi = 0,
      tfi = 0,
      slope_ang = seq(-45, 45, length.out = nseq),
      wind_kmh = 0,
      varying_var = "slope"
    ),
    # wind ___________
    expand.grid(
      vfi = 0,
      tfi = 0,
      slope_ang = 0,
      wind_kmh = seq(-90, 90, length.out = nseq),
      varying_var = "wind"
    )
  )

  # scale predictors in the way the fire simulator needs them
  names_spread <- c("vfi", "tfi", "slope", "wind")
  names_plot <- colnames(pdspread)[1:4]

  pdspread$wind <- pdspread$wind_kmh / 3.6 / wind_sd
  pdspread$slope <- sin(pdspread$slope_ang * pi / 180)
  # turn into zero the slope values below zero
  pdspread$slope[pdspread$slope < 0] <- 0

  # move those values to varying_val
  pdspread$varying_val <- NA
  for(v in 1:4) {
    rows <- pdspread$varying_var == names_spread[v]
    colname <- names_plot[v]
    pdspread$varying_val[rows] <- pdspread[rows, colname]
  }

  # to match later:
  npred <- nrow(pdspread)
  pdspread$row <- 1:npred

  # design matrix
  Xspread <- model.matrix(~ vfi + tfi + slope + wind, data = pdspread)

  # prediction data for FWI:

  # fwi already standardized:
  fwi_ref <- quantile(fwi_all, prob = c(0.025, 0.5, 0.975), method = 8)
  fwi_ref[2] <- 0
  fwi_ref_text <- as.character(round(fwi_ref, 3))

  # FWI is standardized with respect to fires data; but it was originally 
  # standardized at the pixel level, taking much smaller values.
  # Get it at the original scale, to show in plots:
  fwi_original <- fwi_ref * fwi_sd + fwi_mean
  round(fwi_original, 3)
  # These are the actual values used:
  # 2.5%    mean  97.5% 
  # -0.597  0.864  2.377

  Xfwi <- cbind(rep(1, 3), fwi_ref)
  npred_mu <- length(fwi_ref)

  # Array to store samples of curves
  curves_samples <- array(
    NA, dim = c(npred, npred_mu, npost),
    dimnames = list(
      row = 1:npred,
      fwi_level = fwi_ref_text,
      iter = 1:npost
    )
  )

  # Compute curves

  nr <- 200 # number of random effects to simulate in order to compute mean
  ranef_raw <- matrix(rnorm(nr * (n_coef-1)), ncol = n_coef-1)
  # random effects array, placeholders
  ranef_tmp <- array(NA, dim = c(npred_mu, n_coef-1, nr))
  ranef_cons <- array(NA, dim = c(npred_mu, n_coef-1, nr))

  fitted_prob <- array(NA, dim = c(npred, npred_mu, nr))

  for(i in 1:npost) {
    if(i %% 100 == 0) print(i)

    # mu at unconstrained scale
    mumat <- Xfwi %*% t(draws$fixef[1:(n_coef-1), 1:2, i])

    # Compute choleski factor of vcov matrix for random effects
    sds <- draws$fixef[1:(n_coef-1), "s2", i] |> sqrt()
    rho <- draws$rho[1:(n_coef-1), 1:(n_coef-1), i]
    V <- diag(sds) %*% rho %*% diag(sds)
    Vchol_U <- chol(V)
  
    # unconstrained centred random effects
    ranef_centred <- ranef_raw %*% Vchol_U

    # unconstrained random effects
    for(j in 1:nr) {
      ranef_tmp[, , j] <- t(t(mumat) + ranef_centred[j, ])
    }

    # constrain 
    for(v in 1:(n_coef-1)) {
      # v = 1
      ranef_cons[, v, ] <- invlogit_scaled(
        ranef_tmp[, v, ], Lpar[v], Upar[v]
      )
    }
    ranef_cons3 <- aperm(ranef_cons, c(2, 1, 3))

    # Compute spread probability curves for all raneffs and FWI values
    for(j in 1:nr) {
      fitted_prob[, , j] <- plogis(Xspread %*% ranef_cons3[, , j])
    }

    # average curves across raneffs
    curves_samples[, , i] <- apply(fitted_prob, 1:2, mean)
  }

  # summarize posterior and longanize.
  curves_summ <- apply(curves_samples, 1:2, summarise_post)
  names(dimnames(curves_summ))[1] <- "metric"

  curves_summ_sub <- curves_summ[c("mean", "eti_lower_95", "eti_upper_95"), , ]
  curves_df1 <- as.data.frame.table(curves_summ_sub, responseName = "probfit")
  curves_df <- pivot_wider(curves_df1, names_from = "metric", values_from = "probfit")
  curves_df$row <- as.numeric(as.character(curves_df$row))
  curves_df$fwi_level <- factor(curves_df$fwi_level, levels = fwi_ref_text)

  # merge with predictions data
  curves_df <- left_join(curves_df,
                         pdspread[, c("row", "varying_val", "varying_var")],
                         by = "row")

  curves_df$varying_var2 <- factor(as.character(curves_df$varying_var),
                                   levels = c("vfi", "tfi", "slope", "wind"),
                                   labels = c("VFI", "TFI", "Slope (°)",
                                              "Wind speed (km/h)"))


  saveRDS(curves_df, file.path(dirs$out_dir, "curves_df_prediction.rds"))
}


if (do_curves_raw) {

  # Spread probability curves (raw variables) -------------------------------

  # First, plot the relationship between raw variables and flammability indices.
  # Then, plot spraed probability as a function of raw variables
  # (ndvi * veg, elevation, slope-weighted northing)

  veg_levels <- data_summ$ndvi$vegetation
  nveg <- length(veg_levels)

  nseq <- 300

  pd_veg <- do.call("rbind", lapply(1:nveg, function(v) {
    expand.grid(
      ndvi = seq(data_summ$ndvi$hdi_lower_95[v],
                 data_summ$ndvi$hdi_upper_95[v],
                 length.out = nseq),
      vegnum = v,
      vegetation = veg_levels[v],
      elevation = 0,
      northing = 0,
      varying_var = "ndvi"
    )
  }))

  pd_topo <- rbind(
    expand.grid(
      ndvi = 0,
      vegnum = 1,
      vegetation = veg_levels[1],
      elevation = seq(data_summ$elevation["hdi_lower_95"],
                      data_summ$elevation["hdi_upper_95"],
                      length.out = nseq),
      northing = 0,
      varying_var = "elevation"
    ),
    expand.grid(
      ndvi = 0,
      vegnum = 1,
      vegetation = veg_levels[1],
      elevation = data_summ$elevation["mean"],
      northing = seq(-1, 1, length.out = nseq),
      varying_var = "northing"
    )
  )

  pdspread_fi <- rbind(pd_veg, pd_topo)

  names_spread <- c("ndvi", "elevation", "northing")
  # move values to varying_val
  pdspread_fi$varying_val <- NA
  for(v in 1:3) {
    rows <- pdspread_fi$varying_var == names_spread[v]
    colname <- names_spread[v]
    pdspread_fi$varying_val[rows] <- pdspread_fi[rows, colname]
  }

  # Compute flammability indices
  pdspread_fi$vfi <- vfi_calc(pdspread_fi$vegnum, pdspread_fi$ndvi)

  # TFI
  pdspread_fi$tfi <-
    fi_params$b_elev_ori * pdspread_fi$elevation +
    fi_params$b_north_ori * pdspread_fi$northing
  pdspread_fi$tfi <- (pdspread_fi$tfi - fi_params$tfi_mean) / fi_params$tfi_sd


  ## Compute spread probability curves.

  # make zero the non-varying index
  pdspread_fi$vfi[pdspread_fi$varying_var != "ndvi"] <- 0
  pdspread_fi$tfi[pdspread_fi$varying_var == "ndvi"] <- 0

  # to match later:
  npred <- nrow(pdspread_fi)
  pdspread_fi$row <- 1:npred

  # design matrix
  Xspread_fi <- model.matrix(~ vfi + tfi, data = pdspread_fi)

  # prediction data for FWI:
  # fwi already standardized:
  fwi_ref <- quantile(fwi_all, prob = c(0.025, 0.5, 0.975), method = 8)
  fwi_ref[2] <- 0
  fwi_ref_text <- as.character(round(fwi_ref, 3))

  Xfwi <- cbind(rep(1, 3), fwi_ref)
  npred_mu <- length(fwi_ref)

  # Array to store samples of curves
  curves_samples <- array(
    NA, dim = c(npred, npred_mu, npost),
    dimnames = list(
      row = 1:npred,
      fwi_level = fwi_ref_text,
      iter = 1:npost
    )
  )

  # Compute curves

  nr <- 200 # number of random effects to simulate in order to compute mean
  n_coef_fi <- 3
  ranef_raw <- matrix(rnorm(nr * n_coef_fi), ncol = 3) # only simulates the used parameters
  # random effects array, placeholders
  ranef_tmp <- array(NA, dim = c(npred_mu, n_coef_fi, nr))
  ranef_cons <- array(NA, dim = c(npred_mu, n_coef_fi, nr))

  fitted_prob <- array(NA, dim = c(npred, npred_mu, nr))

  for(i in 1:npost) {
    if(i %% 100 == 0) print(i)

    # mu at unconstrained scale
    mumat <- Xfwi %*% t(draws$fixef[1:3, 1:2, i])
  
    # Compute choleski factor of vcov matrix for random effects
    sds <- draws$fixef[1:n_coef_fi, "s2", i] |> sqrt()
    rho <- draws$rho[1:n_coef_fi, 1:n_coef_fi, i]
    V <- diag(sds) %*% rho %*% diag(sds)
    Vchol_U <- chol(V)
  
    # unconstrained centred random effects
    ranef_centred <- ranef_raw %*% Vchol_U
  
    # unconstrained random effects
    for(j in 1:nr) {
      ranef_tmp[, , j] <- t(t(mumat) + ranef_centred[j, ])
    }
  
    # constrain 
    for(v in 1:n_coef_fi) {
      # v = 1
      ranef_cons[, v, ] <- invlogit_scaled(
        ranef_tmp[, v, ], Lpar[v], Upar[v]
      )
    }

    ranef_cons3 <- aperm(ranef_cons, c(2, 1, 3))

    # Compute spread probability curves for all raneffs and FWI values
    for(j in 1:nr) {
      fitted_prob[, , j] <- plogis(Xspread_fi %*% ranef_cons3[, , j])
    }

    # average curves across raneffs
    curves_samples[, , i] <- apply(fitted_prob, 1:2, mean)
  }

  # summarize posterior and longanize.
  curves_summ <- apply(curves_samples, 1:2, summarise_post)
  names(dimnames(curves_summ))[1] <- "metric"

  curves_summ_sub <- curves_summ[c("mean", "eti_lower_95", "eti_upper_95"), , ]
  curves_df1 <- as.data.frame.table(curves_summ_sub, responseName = "probfit")
  curves_df <- pivot_wider(curves_df1, names_from = "metric", values_from = "probfit")
  curves_df$row <- as.numeric(as.character(curves_df$row))
  curves_df$fwi_level <- factor(curves_df$fwi_level, levels = fwi_ref_text)

  # merge with predictions data
  curves_df <- left_join(curves_df,
                         pdspread_fi[, c("row", "vegetation", "varying_val", "varying_var")],
                         by = "row")


  saveRDS(curves_df, file.path(dirs$out_dir, "curves_df_prediction_raw_x.rds"))
}


if (do_veg_effect) {

  # veg_levels as the factor the flammability functions index by (the monolith
  # picked this up from the block above; set it here so this block runs alone)
  veg_levels <- data_summ$ndvi$vegetation

  # Vegetation effect on spread prob as a function of FWI --------------------

  # Recipe for the analysis.

  # Get fixed TFI (elevation = elev_fixed; northing = 0).
  # Sample slope and windspeed in the PNNH, N = 500.

  # Using slope values from the sample, elevation fixed and northing fixed, 
  # estimate the NDVI for all points by veg type. 
  # Compute the NDVI.

  # Duplicate the sample to make slope = 0 (downhill). Hence, this will represent
  # an average between downhill and uphill effects. 

  # For each veg type, 

  # Compute TFI at elevation = elev_fixed, northing = 0

  # For a sequence of FWI, do the following:
  #   For each posterior sample

  (fwiqs <- quantile(fwi_all, prob = seq(0.025, 0.975, length.out = 20),
                     method = 8))
  fwiseq <- sort(c(0, median(fwi_all), fwiqs))
  plot(fwiseq)

  # Get slope and windspeed at the PNNH
  pnnh_land_rast <- rast(file.path("data", "pnnh_images",
                                   "pnnh_data_spread_buffered_30m.tif"))
  # Nahuel Huapi National Park (strict)
  pnnh <- vect(file.path("data", "protected_areas", "apn_limites.shp"))
  pnnh <- pnnh[pnnh$nombre == "Nahuel Huapi", ]
  pnnh <- project(pnnh, "EPSG:5343")

  pnnh_sample <- spatSample(pnnh_land_rast, size = 2000, method = "regular", 
                            as.points = T, values = T)
  keep1 <- relate(pnnh_sample, pnnh, "intersects")
  pnnh_sample1 <- pnnh_sample[keep1, ]
  pnnh_sample2 <- pnnh_sample1[pnnh_sample1$veg < 7, ] # keep only burnable and focal vegs
  set.seed(2345)
  pnnh_sample3 <- pnnh_sample2[sample(1:nrow(pnnh_sample2), size = 500, replace = F), ]

  # get coordinates to get rowcol and then, windspeed
  sampled_crds <- crds(pnnh_sample3)
  sampled_cells <- cellFromXY(pnnh_land_rast, sampled_crds)
  # sampled_rowcols <- rowColFromCell(pnnh_rast_full, sampled_cells)

  # get spread landscape for PNNH
  pnnh_land <- readRDS(file.path("data", "pnnh_images",
                                 "pnnh_spread_landscape_urban-nonburnable.rds"))
  wind_rast <- rast_from_mat(pnnh_land[, , "wspeed"], pnnh_land_rast$ndvi)

  # Extract wind and slope
  sw_vals <- cbind(values(pnnh_land_rast$slope), values(wind_rast))[sampled_cells, ]
  colnames(sw_vals) <- c("slope", "wspeed")

  # Compute slope term from angle
  sw_terms <- sw_vals 
  sw_terms[, "slope"] <- sin(sw_vals[, "slope"] * pi / 180)
  sw_terms_t <- t(sw_terms)
  # plot(sw_terms[, "slope"] ~ sw_vals[, "slope"]) # OK

  # duplicate sw_terms, with zero slope
  sw_dup <- sw_terms
  sw_dup[, "slope"] <- 0

  sw_data <- rbind(sw_terms, sw_dup) # wind is already standardized
  sw_data_t <- t(sw_data)

  Xfwi <- cbind(rep(1, length(fwiseq)), fwiseq)

  # Get VFI for each vegetation type

  nd <- expand.grid(elevation = 900, northing = 0,
                    slope = sw_vals[, "slope"],
                    vegfac2 = factor(veg_levels, levels = veg_levels))

  ndvi_model <- readRDS(file.path("files", "landscape_flammability", 
                                  "ndvi_model_01.rds"))
  nd$ndvi01 <- predict(ndvi_model, nd, "response") |> as.numeric()
  nd$ndvi <- nd$ndvi01 * 2 - 1 # scale to [-1, 1] 
  nd$vfi <- vfi_calc(nd$vegfac2, nd$ndvi)


  vfimat <- matrix(nd$vfi, 500, 5) |> t() # veg types in rows
  tfi_fixed <- tfi_calc(900, 90, 0)

  ## Array to fill
  spreadprobs <- array(
    NA, dim = c(length(fwiseq), n_veg, npost),
    dimnames = list(
      "fwi" = fwiseq,
      "vegetation" = factor(veg_levels, levels = veg_levels),
      "iteration" = 1:npost
    )
  )

  nr <- 200 # random effects draws
  ranef_raw <- matrix(rnorm(nr * 5), nr, 5)
  nc <- 5 # spread coefficients
  nf <- length(fwiseq)

  # matrices to fill in the loop
  ranef_unc <- matrix(NA, nr, 5)
  colnames(ranef_unc) <- par_names[1:5]
  ranef <- ranef_unc

  ## WARNING: heavy loop
  for(i in 1:npost) {
    print(i)
  
    # mu at unconstrained scale
    mumat <- Xfwi %*% t(draws$fixef[1:(n_coef-1), 1:2, i])
  
    # Compute choleski factor of vcov matrix for random effects
    sds <- draws$fixef[1:(n_coef-1), "s2", i] |> sqrt()
    rho <- draws$rho[1:(n_coef-1), 1:(n_coef-1), i]
    V <- diag(sds) %*% rho %*% diag(sds)
    Vchol_U <- chol(V)
  
    # unconstrained centred random effects
    ranef_centred <- ranef_raw %*% Vchol_U
  
    # Loop over fwi values (rows in mumat)
    for(f in 1:nf) {
      # unconstrained random effects
      ranef_unc[] <- ranef_centred + outer(rep(1, nr), mumat[f, ])
    
      # constrained random effects 
      ranef[] <- invlogit_scaled2(ranef_unc, params_lower[1:nc], params_upper[1:nc])
    
      # Compute terms of the linear predictor
      tfi_term <- ranef[, "tfi"] * tfi_fixed
      wind_term <- ranef[, "wind"] %*% sw_terms_t["wspeed", , drop = F]
      slope_term <- ranef[, "slope"] %*% sw_terms_t["slope", , drop = F]
    
      lp_downhill <- ranef[, "intercept"] + tfi_term + wind_term # no slope
      lp_uphill <- lp_downhill + slope_term
    
      # Loop over vegetation types
      for(v in 1:n_veg) {
        vfi_local <- ranef[, "vfi"] %*% vfimat[v, , drop = F]
      
        prob_downhill <- mean(plogis(vfi_local + lp_downhill))
        prob_uphill <- mean(plogis(vfi_local + lp_uphill))
      
        spreadprobs[f, v, i] <- mean(c(prob_downhill, prob_uphill))
      }
    
    }
  }

  saveRDS(spreadprobs, file.path(dirs$out_dir, "spreadprob_veg_comparison_array.rds"))
}
