# Shared machinery for re-simulating the 57 FOCAL fires from the fitted
# hierarchical model (spread/simulate_focal_metrics.R, the model-fit metrics;
# spread/figure_burn_probability.R, paper Fig. 5).
#
# Both scripts ask the same question — "simulate this fire again, from its own
# ignition point, either with its own fitted random effect or with a fresh one
# drawn from the population" — and both used to carry their own copy of the
# chain that turns posterior draws into simulator parameters. That chain has a
# trap in it (below), so it lives here once.
#
# The originals are in spread/hierarchical_fit.R, section "Assessing model fit"
# (~L2526-2620). Do not re-derive the MVLN -> invlogit_scaled chain from
# scratch; if the fit ever changes, change it there and here together.
#
#   THE TRAP: in `draws$ranef`, row `steps` is stored on the NATURAL scale
#   while the other rows are on the logit scale. Fitted random effects are
#   therefore back-transformed on rows 1:(n_coef - 1) only. Simulated ones come
#   out of `rmvn()` entirely on the logit scale, so all n_coef rows are
#   transformed there — each with that draw's own upper bound for `steps`,
#   `draws$stepsU`.
#
# The cheapest check that a caller wired this up correctly is to compare the
# mean simulated sizes it gets against `metrics_table.rds`'s size quotients:
# they agree to a few per cent (the draws differ, the distribution does not).

#' Parameter bounds of the fitted spread model
#'
#' The [L, U] box the model's parameters are logit-scaled inside. `steps` has
#' no fixed upper bound — it is per posterior draw (`draws$stepsU`) — so `U`
#' carries NA there and every caller must fill it in.
#'
#' @param fi_params the flammability-index parameter list, for `slope_term_sd`.
#' @return list with `L`, `U` (named, in `par_names` order) and `par_names`.
focal_par_bounds <- function(fi_params, ext_alpha = 50, ext_beta = 30,
                             stepsL = 2) {
  par_names <- c("intercept", "vfi", "tfi", "slope", "wind", "steps")
  n_coef <- length(par_names)
  L <- c(-ext_alpha, rep(0, n_coef - 2), stepsL)
  U <- c(ext_alpha, rep(ext_beta, n_coef - 2), NA)
  names(L) <- names(U) <- par_names
  U["slope"] <- ext_beta / fi_params$slope_term_sd
  list(L = L, U = U, par_names = par_names, n_coef = n_coef)
}


#' Inverse-logit, scaled between L and U, column-wise when `x` is a matrix
invlogit_scaled2 <- function(x, L, U) {
  if (is.matrix(x)) {
    return(sapply(1:ncol(x), function(i) stats::plogis(x[, i]) * (U[i] - L[i]) + L[i]))
  }
  stats::plogis(x) * (U - L) + L
}


#' Fitted random effects for one fire, on the simulator's scale
#'
#' @param draws `spread_model_samples.rds`.
#' @param fire_id one of `dimnames(draws$ranef)[[2]]`.
#' @param ids posterior indices, one per simulated fire.
#' @param bounds the list `focal_par_bounds()` returns.
#' @return `length(ids)` x `n_coef` matrix, columns named as `par_names`.
ranef_fitted <- function(draws, fire_id, ids, bounds) {
  n_coef <- bounds$n_coef
  r <- draws$ranef[, fire_id, ids]                       # n_coef x nsim
  out <- t(r)
  out[, 1:(n_coef - 1)] <- invlogit_scaled2(t(r[1:(n_coef - 1), ]),
                                            bounds$L, bounds$U)
  colnames(out) <- bounds$par_names
  out
}


#' New random effects for one fire, drawn from the population distribution
#'
#' One draw of the hyperparameters per simulated fire, so both hyperparameter
#' and between-fire uncertainty are carried — never a fitted fire's own random
#' effect. This is the honest out-of-sample question, and the one the regime
#' simulator actually asks.
#'
#' @param fwi_z the fire's standardized FWI (the covariate the population mean
#'   is a function of).
#' @inheritParams ranef_fitted
ranef_simulated <- function(draws, fire_id, ids, bounds, fwi_z) {
  n_coef <- bounds$n_coef
  X <- cbind(1, fwi_z)
  out <- matrix(NA_real_, length(ids), n_coef,
                dimnames = list(NULL, bounds$par_names))
  U <- bounds$U
  for (k in seq_along(ids)) {
    jj <- ids[k]
    mu <- X %*% t(draws$fixef[1:n_coef, c("a", "b"), jj])
    sds <- sqrt(draws$fixef[1:n_coef, "s2", jj])
    V <- diag(sds) %*% draws$rho[, , jj] %*% diag(sds)
    U["steps"] <- draws$stepsU[jj]
    out[k, ] <- invlogit_scaled2(matrix(mgcv::rmvn(1, mu, V), nrow = 1),
                                 bounds$L, U)
  }
  out
}


#' Each focal fire's standardized FWI, as the fit scaled it
#'
#' Same source and same scaling as `spread/hierarchical_fit.R`. The two fires
#' that were split after the climatic table was built (`2011_19` ->
#' `2011_19E`/`W`, `2015_47` -> `2015_47N`/`S`) are not in the csv under their
#' split names; the fit gave both halves the parent's FWI, and so does this —
#' by stripping a trailing letter suffix, but only for ids that do not match
#' directly (`1999_25j` and `1999_2140469994_r` are in the csv as they are).
focal_fwi_z <- function(fire_ids,
                        fwi_file = file.path(
                          "data",
                          "climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ2.csv"),
                        scale_file = file.path("files", "hierarchical_model",
                                               "fwi_mean_sd_spread.rds")) {
  sc <- readRDS(scale_file)
  d <- utils::read.csv(fwi_file)
  k <- match(fire_ids, d$fire_id)
  split_id <- sub("[A-Za-z]+$", "", fire_ids)
  k[is.na(k)] <- match(split_id[is.na(k)], d$fire_id)
  z <- (d$fwi_fort_expquad[k] - sc$fwi_mean) / sc$fwi_sd
  stats::setNames(z, fire_ids)
}
