# Stage 2, step 3 of 4. THE FIT: the parallel MCMC and the tidied posterior.
#
# n_cores chains, run in nb batches so a crash costs one batch and not the whole
# thing (each batch restarts from the last iteration of the previous one), then
# the batches are merged into the single object every downstream script reads.
#
#   reads   files/hierarchical_model/par_start.rds, run0.rds, sd_jump_tune.rds
#   writes  files/hierarchical_model/draws_batch_01..10.rds
#           files/hierarchical_model/spread_model_samples.rds  <- THE FITTED MODEL
#           files/hierarchical_model/fwi_mean_sd_spread.rds
#   cost    about 15 h for the canonical run (8 cores x 150 saved x 1000 thin
#           x 10 batches = 12,000 draws); launch it detached, e.g.
#             tmux new-session -d -s spread_fit -c ~/dev/fire-regime-sim-patagonia \
#               "Rscript spread/hierarchical_fit_run.R 2>&1 | tee files/hierarchical_model/run.log"
#
# It prints the ESS and R-hat range of every parameter block at the end; the
# canonical run gave ESS > 10,000 and R-hat < 1.002 everywhere.
#
# Run from the repo root. Next: spread/hierarchical_predictions.R.

library(tidyverse)
library(terra)
library(abind)
library(posterior)
library(foreach)
library(doMC)
library(truncnorm)

source(file.path("R", "flammability_indices_functions.R"))
source(file.path("R", "mcmc_functions_smc.R"))
source(file.path("R", "hierarchical_fit_data.R"))
source(file.path("R", "hierarchical_mcmc_functions.R"))

# Settings ---------------------------------------------------------------

# Smoke test: a few iterations on one core, everything written to
# files/hierarchical_model/test/ so the real fit cannot be overwritten. Set it
# from outside with
#   Rscript -e 'test_mode <- TRUE; source("spread/hierarchical_fit_run.R")'
if (!exists("test_mode")) test_mode <- FALSE
dirs <- hierarchical_fit_dirs(test_mode)

list2env(hierarchical_fit_setup(out_dir = dirs$out_dir), globalenv())
par_start <- read_fit("par_start.rds", dirs)
list2env(hierarchical_fit_priors(par_start), globalenv())

# Run MCMC in parallel ----------------------------------------------------

run0 <- read_fit("run0.rds", dirs)
sd_jump_tune <- read_fit("sd_jump_tune.rds", dirs)

n_cores <- 8 # takes the same time as with more cores
nsave <- 150
thin <- 1000
nb <- 10     # it takes long, run in batches

# Smoke test: two chains (not one: n_cores == number of chains, and a single
# chain would drop the array dimension the batch loop indexes), 10 saved draws,
# two batches. Seconds instead of ~15 h.
if (test_mode) { n_cores <- 2; nsave <- 10; thin <- 1; nb <- 2 }

# Prepare init samples
eend <- dim(run0$fixef)[3]
bbegin <- floor(eend * 0.7)
iii <- sample(bbegin:eend, size = n_cores, replace = F)
start_samples8 <- list(
  fixef = run0$fixef[, , iii],
  ranef = run0$ranef[, , iii],
  steps = run0$steps[, iii],
  stepsU = run0$stepsU[iii]
)

Sys.time()
for(batch in 1:nb) {
  print(batch)

  if(batch == 1) {
    init_samples <- start_samples8
  } else {
    # load previous batch
    nump <- stringr::str_pad(batch-1, 2, side = "left", pad = "0")
    fname_prev <- paste("draws_batch_", nump, ".rds", sep = "")
    draws_prev <- readRDS(file.path(dirs$out_dir, fname_prev))
    # get last iters
    last <- dim(draws_prev$fixef)[3]
    init_samples <- list(
      fixef = draws_prev$fixef[, , last, ],
      ranef = draws_prev$ranef[, , last, ],
      steps = draws_prev$steps[, last, ],
      stepsU = draws_prev$stepsU[last, ]
    )
  }

  draws <- mcmc_parallel(nsim = nsave * thin, thin = thin, n_cores = n_cores,
                         start_samples = init_samples, sd_jump = sd_jump_tune)
  num <- stringr::str_pad(batch, 2, side = "left", pad = "0")
  fname <- paste("draws_batch_", num, ".rds", sep = "")
  saveRDS(draws, file.path(dirs$out_dir, fname))
}
Sys.time()
# start: 2026-01-31 16:27:17 -03
# end:   2026-02-01 07:12:01 -03

# Tidy samples ------------------------------------------------------------

batch_files <- list.files(dirs$out_dir, pattern = "^draws_batch_[0-9]+\\.rds$")
stopifnot(length(batch_files) == nb)

# assign growing iter_id to samples from consecutive batches
dlist <- lapply(1:length(batch_files), function(i) {
  x <- readRDS(file.path(dirs$out_dir, batch_files[i]))
  # assign NOT growing chain_id
  iter_names <- as.character((1:nsave) + (i-1) * nsave)
  print(i)
  nitems <- length(x)
  for(j in 1:nitems) {
    pos <- grep("iter", names(dimnames(x[[j]])))
    names(dimnames(x[[j]]))[pos] <- "iteration"
    dimnames(x[[j]])[[pos]] <- iter_names
  }
  return(x)
})


# Merge batches in a list with arrays (draws), which will be exported.
# In addition, create draws_arrays to summarize with posterior package.
partypes <- c("fixef", "rho", "ranef", "steps", "stepsU")
nitems <- length(partypes)
draws <- vector("list", nitems)
names(draws) <- partypes
dimpar <- c(2, 2, 2, 1, 0)
# dimension of a single posterior sample for each parameter type
draws_arrays <- vector("list", nitems)
names(draws_arrays) <- partypes
# Chains and total iterations, derived from the batches just read. The monolith
# hardcoded these as 8 and 1500; when they do not match the run's settings the
# reshape below recycles silently instead of failing, so they are derived and
# checked here.
nc <- n_cores
ni <- nsave * nb
npost <- nc * ni
stopifnot(dim(dlist[[1]]$fixef)[3] == nsave,
          dim(dlist[[1]]$fixef)[4] == nc)

for(p in 1:nitems) {
  # p = 5
  
  draws_temp <- abind(lapply(dlist, function(x) x[[p]]),
                      along = dimpar[p] + 1) # along iter dimension

  if(dimpar[p] > 1) {
    nvar <- prod(dim(draws_temp)[1:dimpar[p]]) # number of (collapsed) parameters
    drarr <- array(draws_temp, c(nvar, ni, nc))
    # this collapses the first two dimensions, which in most cases have parameters
    # in matrix form

    # # check ordering:
    # draws_temp[, , 2, 1, drop = F] # third col, first row
    # drarr[1:nvar, 2, 1, drop = F] # element 6 * 2 + 1

    # set name to collapsed variable
    vardf <- expand.grid(
      v1 = dimnames(draws_temp)[[1]],
      v2 = dimnames(draws_temp)[[2]]
    )

    dimnames(drarr) <- list(
      variable = paste(vardf$v1, vardf$v2, sep = "__"),
      iteration = dimnames(draws_temp)[["iteration"]],
      chain = dimnames(draws_temp)[["chain"]]
    )
  } else {
    if(dimpar[p] == 1) { # steps
      drarr <- draws_temp
      names(dimnames(drarr)) <- c("variable", "iteration", "chain")
    } 
    if(dimpar[p] == 0) { # stepsU
      arr <- array(NA, dim = c(1, ni, nc),
                   dimnames = list(
                     "variable" = "stepsU",
                     "iteration" = 1:ni,
                     "chain" = 1:nc
                   ))
      arr[1, , ] <- draws_temp
      draws_arrays[[p]] <- as_draws_array(aperm(arr, c(2,3,1)))
      
      # collapse iterations and chains, in a single "iterations" dimension
      draws[[p]] <- as.vector(arr)
    }
  }

  # remove redundant parameters
  if(partypes[p] == "rho") {
    rows_keep <- which(lower.tri(matrix(1:n_coef^2, n_coef, n_coef)))
    drarr <- drarr[rows_keep, , ]
  }
  
  # tidy parameters with more than one variable
  if(dimpar[p] > 0) {
    draws_arrays[[p]] <- aperm(drarr, c(2, 3, 1)) # get iteration, chain, variable.
  
    # collapse iterations and chains, in a single "iterations" dimension
    par_dims <- 1:dimpar[p]
    iter_dims <- (1:2) + max(par_dims)
  
    # permute to collapse (dims to collapse must be the first ones)
    perm <- c(iter_dims, par_dims)
    draws2 <- aperm(draws_temp, perm)
    draws3 <- array(draws2, c(ni*nc, dim(draws_temp)[par_dims]))
    new_par_dims <- par_dims + 1
    draws4 <- aperm(draws3, c(new_par_dims, 1))
  
    par_dn <- dimnames(draws_temp)[par_dims]
    dn <- c(par_dn, list(1:(ni*nc)))
    names(dn) <- c(rep("variable", dimpar[p]), "iteration")
    dimnames(draws4) <- dn
  
    draws[[p]] <- draws4
  }
}

saveRDS(draws, file.path(dirs$out_dir, "spread_model_samples.rds"))

# summaries
summaries <- lapply(draws_arrays, function(x) summarise_draws(x))

for(i in 1:nitems) {
  print(partypes[i])
  mm <- apply(summaries[[i]][, c("ess_tail", "ess_bulk", "rhat")],
              2, range, na.rm = T)
  print(mm)
}

# [1] "fixef"
# ess_tail ess_bulk     rhat
# [1,] 11115.42 11177.68 0.999823
# [2,] 12291.79 12288.82 1.000919
# [1] "rho"
# ess_tail ess_bulk      rhat
# [1,] 11323.78 11618.20 0.9998963
# [2,] 12085.65 12327.41 1.0005965
# [1] "ranef"
# ess_tail ess_bulk      rhat
# [1,] 10512.09 10635.39 0.9995837
# [2,] 12379.66 12654.28 1.0010891
# [1] "steps"
# ess_tail ess_bulk      rhat
# [1,] 10496.33 10477.40 0.9997057
# [2,] 12434.69 12538.19 1.0010788
# [1] "stepsU"
# ess_tail ess_bulk      rhat
# [1,] 11433.24 11749.44 0.9999798
# [2,] 11433.24 11749.44 0.9999798
