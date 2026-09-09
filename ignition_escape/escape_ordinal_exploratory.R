# Escape as an ordinal size class - exploratory ----------------------------
#
# NOT part of the canonical ignition-escape pipeline. The canonical escape model
# is the binary one (> 0.09 ha) in ignition_escape/fit.R, fitted with
# escape_model.stan; that is the model fire_regime/ reads. This script keeps the
# earlier, more flexible formulation alive: instead of escaped / not escaped, the
# response is the fire's size class, with cutpoints at 0.09, 10 and 100 ha
# (K = 4 classes), fitted as a cumulative-logit (ordered cutpoints, categorical
# likelihood) with the same linear predictor as the binary model: FWI with a
# Gaussian lag-weighting kernel, vfi, tfi, distance to roads, distance to
# human settlements.
#
# The 10 ha cutpoint is the interesting one: the spread simulator was estimated
# on fires above that size, so an escape definition anchored there can be read
# straight off this model without refitting.
#
# Continuation of fit.R, not a standalone script. Run ignition_escape/fit.R down
# to the end of its "Prepare data for escape model" section, then run this in the
# same session. It needs, from there:
#   ig2         ignition records ordered by id, with area / vfi / tfi / drz / dhz
#   fwi_points  n x nlags matrix of lagged FWI at each ignition
#   nlags       lag length used for FWI
#   mean_ci     posterior summary helper (defined in fit.R's "Functions")
#
# Inputs:  data_private/ignition/* (through fit.R), escape_model_ordinal.stan
# Outputs: files/ignition/escape_model_samples_ordinal.rds (the fit below;
#          already in the store, so the sampling() call is commented and the
#          readRDS() is the active line, as in fit.R)
#          data_private/ignition/ignition_size_data.csv (ig2 with its size class;
#          the file fire_regime/simulate.R reads to compare the simulated fire
#          size distribution against the observed one). Only re-export it if the
#          ignition record or the cutpoints change.
#
# Sampling takes a few minutes on 8 cores.

library(rstan)
library(bayesplot)

needed <- c("ig2", "fwi_points", "nlags", "mean_ci")
missing <- needed[!sapply(needed, exists)]
if(length(missing)) {
  stop("run ignition_escape/fit.R through its 'Prepare data for escape model' ",
       "section first; missing from this session: ",
       paste(missing, collapse = ", "))
}

# Size classes ------------------------------------------------------------

ig2$area_impute <- ig2$area
ig2$area_impute[is.na(ig2$area)] <- 0.045 # NA is less than 1 pix

area_cuts <- c(0.09, 10, 100, max(ig2$area, na.rm = TRUE) * 10)
K <- length(area_cuts)
class_names <- c("(0, 0.09]", "(0.09, 10]", "(10, 100]", "(100, ...)")

ig2$sizeclass <- sapply(area_cuts, function(cut) {
  as.numeric(ig2$area_impute > cut)
}) |> rowSums() + 1
table(ig2$sizeclass)

# ### Fire size class data, used by fire_regime/simulate.R to compare the
# ### simulated size distribution against the observed one. Stays in the private
# ### store: it is one row per ignition record.
# write.csv(ig2, file.path("data_private", "ignition", "ignition_size_data.csv"),
#           row.names = FALSE)

# Fit ---------------------------------------------------------------------

sdata_sizeclass <- list(
  n = nrow(ig2),
  nlag = nlags,
  K = max(ig2$sizeclass),

  y = ig2$sizeclass,

  fwi_mat = fwi_points,
  vfi = ig2$vfi,
  tfi = ig2$tfi,
  drz = ig2$drz,
  dhz = ig2$dhz,

  prior_a_sd = 3,
  prior_b_sd = 10,
  prior_ls_sd = nlags * 0.75
)

# smodel_sizeclass <- stan_model(file.path("ignition_escape",
#                                          "escape_model_ordinal.stan"))
# scmod <- sampling(
#   smodel_sizeclass, data = sdata_sizeclass, seed = 1596142, refresh = 200,
#   cores = 8, chains = 8, iter = 2000, warmup = 1000,
#   pars = c("a", "b_fwi", "b_vfi", "b_tfi", "b_drz", "b_dhz", "ls")
# )
# saveRDS(scmod, file.path("files", "ignition",
#                          "escape_model_samples_ordinal.rds"))

scmod <- readRDS(file.path("files", "ignition",
                           "escape_model_samples_ordinal.rds"))
sscmod <- summary(scmod)[[1]]
min(sscmod[, "n_eff"], na.rm = TRUE) # 2652.897
max(sscmod[, "Rhat"], na.rm = TRUE)  # 1.004428

pairs(scmod, pars = c("a", "b_fwi", "b_vfi", "b_tfi", "b_drz", "b_dhz", "ls"))

# glimpse at the posteriors
mcmc_dens(scmod, pars = c("a[1]", "a[2]", "a[3]",
                          "b_fwi", "b_vfi", "b_tfi",
                          "b_drz", "b_dhz", "ls"),
          facet_args = list(scales = "free", ncol = 3))

# Predictions -------------------------------------------------------------

ahat <- as.matrix(scmod, "a")
npost <- nrow(ahat)

# Class probabilities along one covariate, marginalising nothing: pdata is the
# prediction grid, xname the column varying in it, bname the matching slope in
# scmod. Returns pdata repeated K times, with the posterior mean and 95 % CI of
# each class probability, ready for a ggplot faceted by class_name. The
# counterpart of fit.R's logistic_predict(), which does the same for the binary
# model.
ordinal_predict <- function(pdata, xname, bname) {
  eta <- as.matrix(scmod, bname) %*% pdata[, xname]
  cmf <- array(NA, dim = c(nrow(pdata), K-1, npost))
  for(k in 1:(K-1)) cmf[, k, ] <- plogis(ahat[, k] - eta) |> t()
  pmf <- array(NA, dim = c(nrow(pdata), K, npost))
  pmf[, 1, ] <- cmf[, 1, ]
  pmf[, K, ] <- 1 - cmf[, K-1, ]
  for(k in 2:(K-1)) pmf[, k, ] <- cmf[, k, ] - cmf[, k-1, ]

  out <- do.call("rbind", lapply(1:K, function(k) {
    summ <- apply(pmf[, k, ], 1, mean_ci) |> t() |> as.data.frame()
    summ$class <- k
    summ$class_name <- factor(class_names[k], levels = class_names)
    return(cbind(pdata, summ))
  }))

  return(out)
}

# The prediction grids themselves (NDVI by vegetation type, vegetation,
# topography, distance to roads, distance to humans, FWI) are the ones built in
# fit.R's "Escape model predictions" section: build them there and pass them
# here, e.g.
#   prob_ndvi <- ordinal_predict(pd_ndvi, "vfi", "b_vfi")
# and facet by class_name instead of drawing a single escape-probability curve.
