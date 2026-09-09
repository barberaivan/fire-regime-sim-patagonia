# The MCMC core of the hierarchical spread fit (stage 2): the sampler itself.
#
# Extracted verbatim from spread/hierarchical_fit.R (the 3000-line monolith) when
# that script was split into spread/hierarchical_fit_{inits,tune,run}.R; see
# docs/spread.md -> "Stage 2 - hierarchical fit".
#
#   mcmc()          one chain: Gibbs for the conjugate blocks, Metropolis-Hastings
#                   for the area ~ steps regression, the `steps` of the fires with
#                   no ignition point, and the upper bound `stepsU`.
#   mcmc_parallel() n_cores chains of mcmc(), one per core, bound along a 4th
#                   dimension.
#   acceptance()    per-parameter acceptance rate of the M-H blocks, the quantity
#                   hierarchical_fit_tune.R tunes the proposal sd against.
#
# THESE FUNCTIONS READ THEIR DATA FROM THE GLOBAL ENVIRONMENT. That is how the
# monolith was written and it is preserved here rather than turned into a long
# argument list: every one of `Ytry`, `steps_bounds`, `X_`, `tXX_`, `Xlong`,
# `tXXlong`, `ids1`, `ids2`, `area1`, `area2`, `area_all`, `areaL`, `stepsL`,
# `Umin`, `Umax`, `n_coef`, `par_names`, `par_names_all`, `fire_ids`,
# `fire_ids_nonspread`, `nfires_spread`, `nfires_nonspread`, `par_start`, `b0`,
# `S0`, `S0_inv`, `t0` and `d0` must be in the global environment before mcmc()
# is called. Calling scripts get them with
#
#   source(file.path("R", "hierarchical_fit_data.R"))
#   list2env(hierarchical_fit_setup(), globalenv())
#   list2env(hierarchical_fit_priors(par_start), globalenv())
#
# The single-parameter updates (update_lm, update_corr, update_truncnorm,
# update_ranef, update_steps, update_stepsU) and the logit_scaled family live in
# R/mcmc_functions_smc.R, which this file needs sourced first.

# MCMC: sampler for the joint posterior

# nsim: number of iterations to run.
# sd_jump: list containing the proposal sd for each parameter that is updated
#   through m-h, using either normal or truncated normal in the case of sigma.
#   These parameters are coefficients for area ~ steps regression, the steps
#   of fires for which spread was not simulated (unknown ignition point), and 
#   the upper limit for steps at the logit scale, between Umin and Umax
#   (lstepsU, l for logit).
# start: list with initial values.
# samples: list with the output of a previous mcmc run, used to get starting
#   values.
# jump_factor: in the case of missing(sd_jump), the proposal sigmas are computed
#   from the MLE distribution, but multiplying them by the jump_factor.
# sd_jump_out: return the used sd_jump list?

# returns a list with 3 arrays of samples: fixef, ranef and steps.
mcmc <- function(nsim = 50, thin = 1, sd_jump, start, samples, jump_factor = 4,
                 sd_jump_out = F, progress = F) {

  # #_____ TEST
  # nsim = 10; thin = 1; jump_factor = 4; sd_jump_out = F
  # #_____ End test

  #### Allocate memory to save samples,
  nsave <- floor(nsim / thin)
  # replace nsim to avoid computing iterations that won't be save
  nsim <- nsave * thin

  # fixef:        [parname, partype (a, b, s2), nsave]
  # rho:          [parname, parname,            nsave] # correlation matrix for ranef
  # ranef:        [parname, fire_id,            nsave]
  # steps:        [1,       fire_id,            nsave]
  # stepsU:       [1,       1,                  nsave] 

  # fixef include the area ~ steps regression parameters.

  fixef_save <- array(NA, dim = c(n_coef + 1, 3, nsave),
                      dimnames = list(
                        par_names = par_names_all,
                        par_class = c("a", "b", "s2"),
                        iter = 1:nsave
                      ))

  rho_save <- array(NA, dim = c(n_coef, n_coef, nsave),
                    dimnames = list(
                      par_names = par_names,
                      par_names = par_names,
                      iter = 1:nsave
                    ))

  ranef_save <- array(NA, dim = c(n_coef, nfires_spread, nsave),
                      dimnames = list(
                        par_names = par_names,
                        fire_id = fire_ids,
                        iter = 1:nsave
                      ))

  steps_save <- array(NA, dim = c(nfires_nonspread, nsave),
                            dimnames = list(
                              fire_id = fire_ids_nonspread,
                              iter = 1:nsave
                            ))
  
  stepsU_save <- numeric(nsave)

  #### Define proposals sd (if missing)
  if(missing(sd_jump)) {

    tmp <- par_start$fixef["area", , ]
    tmp[3, ] <- sqrt(tmp[3, ]) # sd_jump for sigma, not sigma2
    area_jump <- apply(tmp, 1, sd) * jump_factor
    steps_jump <- apply(par_start$steps, 1, sd) * jump_factor
    stepsU_jump <- sd(logit_scaled(par_start$stepsU, Umin, Umax)) * jump_factor
    # notice jump sd for stepsU at logit scale                  
    
    if(sd_jump_out) {
      sd_jump <- list(area = area_jump,
                      steps = steps_jump,
                      stepsU = stepsU_jump)
    }

  } else {
    area_jump <- sd_jump$area
    steps_jump <- sd_jump$steps
    stepsU_jump <- sd_jump$stepsU # jump at logit scale
  }

  #### Define initial values (if missing)

  if(!missing(start)) {
    fixef <- start$fixef
    ranef <- start$ranef
    steps <- start$steps
    stepsU <- start$stepsU
  }

  # If there is no start, but there is a previous sample, set as start
  # the last value of the previous sample
  if(missing(start) & !missing(samples)) {
    nn <- dim(samples$fixef)[3]
    fixef <- samples$fixef[, , nn]
    ranef <- samples$ranef[, , nn]
    steps <- samples$steps[, nn]
    stepsU <- samples$stepsU[nn]
  }

  # if no start nor samples are provided, make random start from the MLEs
  if(missing(start) & missing(samples)) {
    is <- sample(1:length(par_start$stepsU), size = 1)
    fixef <- par_start$fixef[, , is]
    ranef <- par_start$ranef[, , is]
    steps <- par_start$steps[, is]
    stepsU <- par_start$stepsU[is]
  }

  #### Transient matrices to store expected value of random effects
  mu <- ranef
  mu[,] <- NA
  mu_steps <- steps
  mu_steps[] <- NA
  
  # MCMC loop -------------------------------------------------------------
  for(k in 1:nsim) {

    # Spread fixed effects ------------------------------------------------
    # (i.e., not area parameters)
    for(v in 1:n_coef) {

      if(v < n_coef) {
        y <- ranef[v, ]
        X <- X_
        tXX <- tXX_
      } else {
        # for steps, merge data for spread and non-spread fires, taking into
        # account that spread fires are in the constrained scale, but 
        # non-spread ones ("steps") are in the logit
        steps1_logit <- logit_scaled(ranef[v, ], stepsL, stepsU)
        y <- c(steps1_logit, steps)
        X <- Xlong
        tXX <- tXXlong
      }

      fixef[v, ] <- update_lm(
        y = y, X = X, tXX = tXX, s2 = fixef[v, "s2"],
        b0 = b0[, v], S0_inv = S0_inv, t0 = t0, d0 = d0
      )

      # update mu
      mu_temp <- X %*% fixef[v, 1:2]
      if(v < n_coef) {
        mu[v, ] <- mu_temp
      } else {
        mu[v, ] <- mu_temp[ids1]
        mu_steps <- mu_temp[ids2]
      }
    }

    # Area ~ steps parameters -------------------------------------------------
    # Get log(steps), considering that non-spread are in the logit, but the 
    # others, not.
    steps_invl <- invlogit_scaled(steps, stepsL, stepsU)
    steps_log <- log(c(ranef[n_coef, ], steps_invl))
    aa <- n_coef+1
    fixef[aa, ] <- update_truncnorm(
      y = area_all, x = steps_log, coef = fixef[aa, ], L = areaL,
      b0 = b0[, aa], S0 = S0, t0 = t0, d0 = d0,
      sd_jump = area_jump
    )

    # Correlation matrix -------------------------------------------------
    ranef_logit <- ranef
    ranef_logit[v, ] <- logit_scaled(ranef[v, ], stepsL, stepsU)
    error_mat <- t(ranef_logit - mu)
    rho <- update_corr(error_mat)
    sds <- sqrt(fixef[1:n_coef, 3])
    Sigma <- rho * outer(sds, sds)

    # Random effects (Lunn method) ---------------------------------------
    ranef <- update_ranef(
      Y = ranef, mu = mu, Sigma = Sigma, 
      Ytry = Ytry, steps_bounds = steps_bounds,
      stepsL = stepsL, stepsU = stepsU,
      area = area1, areaL = areaL, area_coef = fixef[n_coef+1, ],
      s = n_coef
    )

    # Random effects (steps) ---------------------------------------------
    steps <- update_steps(
      steps, mu_steps, s = sqrt(fixef[n_coef, 3]),
      stepsL = stepsL, stepsU = stepsU,
      area = area2, areaL, area_coef = fixef[n_coef+1, ], sd_jump = steps_jump
    )
    
    # Steps upper limit --------------------------------------------------
    stepsU_logit <- update_stepsU(
      stepsU_logit = logit_scaled(stepsU, Umin, Umax), 
      Umin = Umin, Umax = Umax, 
      steps1 = ranef[n_coef, ], mu_steps_logit1 = mu[n_coef, ], 
      s = sqrt(fixef[n_coef, 3]),
      steps_logit2 = steps, 
      area = area2, areaL = areaL, area_coef = fixef[n_coef+1, ], 
      sd_jump = stepsU_jump,
      stepsL = stepsL
    )
    stepsU <- invlogit_scaled(stepsU_logit, Umin, Umax)

    
    #### Save samples if thin iterations have passed
    if(k %% thin == 0) {
      if(progress) print(k)
      s <- k / thin
      fixef_save[, , s] <- fixef
      rho_save[, , s] <- rho
      ranef_save[, , s] <- ranef
      steps_save[, s] <- steps
      stepsU_save[s] <- stepsU
    }
  }

  #### Merge samples
  out <- list(
    fixef = fixef_save,
    rho = rho_save,
    ranef = ranef_save,
    steps = steps_save,
    stepsU = stepsU_save
  )

  if(sd_jump_out) out$sd_jump <- sd_jump

  return(out)
}

# function to run mcmc in parallel. n_cores is the number of cores and chains.
# the result is the same as for mcmc, but the arrays have a fourth dimension,
# the chain.
# Chains are initialized from pre-selected samples of a long mcmc run.
mcmc_parallel <- function(nsim = 50, thin = 1, n_cores = 8, sd_jump,
                          start_samples) {

  # ### TESTO
  # n_cores <- 8
  # iii <- sample(1:dim(run0_thin$fixef)[3], size = n_cores, replace = F)
  # nsim = 50; thin = 1; n_cores = 8; sd_jump = sd_jump_tune
  # start_samples <- list(
  #   fixef = run0_thin$fixef[, , iii],
  #   ranef = run0_thin$ranef[, , iii],
  #   steps = run0_thin$steps[, iii],
  #   stepsU = run0_thin$stepsU[iii]
  # )
  # ###
  registerDoMC(n_cores)

  # turn starting values into list
  start_list <- vector("list", n_cores)
  for(cc in 1:n_cores) {
    ll <- list(
      fixef = start_samples$fixef[, , cc],
      ranef = start_samples$ranef[, , cc],
      steps = start_samples$steps[, cc],
      stepsU = start_samples$stepsU[cc]
    )
    start_list[[cc]] <- ll
  }

  runs <- foreach(ss = start_list) %dopar% {
    mcmc(nsim = nsim, thin = thin, sd_jump = sd_jump, start = ss)
  }

  # extract lists
  fixef_l <- vector("list", n_cores)
  rho_l <- vector("list", n_cores)
  ranef_l <- vector("list", n_cores)
  steps_l <- vector("list", n_cores)
  stepsU_l <- vector("list", n_cores)

  for(cc in 1:n_cores) {
    fixef_l[[cc]] <- runs[[cc]]$fixef
    rho_l[[cc]] <- runs[[cc]]$rho
    ranef_l[[cc]] <- runs[[cc]]$ranef
    steps_l[[cc]] <- runs[[cc]]$steps
    stepsU_l[[cc]] <- runs[[cc]]$stepsU
  }

  # tidy runs
  fixef <- abind::abind(fixef_l, along = 4)
  rho <- abind::abind(rho_l, along = 4)
  ranef <- abind::abind(ranef_l, along = 4)
  steps <- abind::abind(steps_l, along = 3)
  stepsU <- do.call("cbind", stepsU_l)

  dimnames(fixef) <- c(dimnames(fixef_l[[1]]), list("chain" = as.character(1:n_cores)))
  dimnames(rho) <- c(dimnames(rho_l[[1]]), list("chain" = as.character(1:n_cores)))
  dimnames(ranef) <- c(dimnames(ranef_l[[1]]), list("chain" = as.character(1:n_cores)))
  dimnames(steps) <- c(dimnames(steps_l[[1]]), list("chain" = as.character(1:n_cores)))
  dimnames(stepsU) <- list("iter" = as.character(1:nrow(stepsU)),
                           "chain" = as.character(1:n_cores))

  out <- list(
    fixef = fixef,
    rho = rho,
    ranef = ranef,
    steps = steps,
    stepsU = stepsU
  )

  return(out)
}

# function to count succesive changes in a vector
count_changes <- function(x) sum(abs(diff(x)) > 1e-12)

# Compute the acceptance rate for the m-h updated parameters.
acceptance <- function(samples) {
  nn <- dim(samples$fixef)[3]
  nt <- nn - 1 # transitions
  parea <- apply(samples$fixef[n_coef+1, , , drop = F], 1:2, count_changes) / nt
  psteps <- unname(apply(samples$steps, 1, count_changes)) / nt
  pstepsU <- count_changes(samples$stepsU) / nt
  out <- list(area = parea, steps = psteps, stepsU = pstepsU)
  return(out)
}
