# spread — spread model fitting (paper 1)

> **Status: scaffold.** High-level content is accurate (from the old repo's inventory); deep
> method/statistics detail (marked _TODO_) is written as the scripts are migrated and read.

The largest, most complex module. Fits the fire spread model in two stages, driving the external
`FireSpread` cellular-automaton engine (`../FireSpread`).

> **Note:** the parameter-**estimation method changed** from the thesis version (see the PhD
> thesis, chapter 4 + supplementary — link in `CLAUDE.md` / root `README.md`). The **evaluation**
> of the model is also going to change. Document the *current* method here; note deltas from the
> thesis where useful.

## Stage 1 — fire-wise posteriors — `stage1_smc.R`
- **Purpose:** sample a posterior of spread parameters per focal fire.
- **Method:** ABC-SMC (Del Moral et al. 2011) with a hard ABC kernel; DE-MCMC moves using
  `src/sample_triplets_weighted.cpp` (weighted triplets of burned area, shape similarity, steps).
  _TODO: summary statistics, distance, kernel schedule, particle count, tolerances._
- **Inputs:** `data/focal_fires/landscapes/*.rds`, flammability params.
- **Outputs:** `files/posterior_samples_stage1/*.rds`.

## Stage 2 — hierarchical fit — `hierarchical_fit.R`
- **Purpose:** fit a hierarchical Bayesian spread model across fires.
- **Method:** custom MCMC (Gibbs + Metropolis–Hastings) from `R/mcmc_functions_smc.R`; uses
  stage-1 samples as proposals. _TODO: hierarchy (random effects, inverse-Wishart), parameter
  transforms (scaled-logit-normal), priors, convergence diagnostics._
- **Inputs:** `files/posterior_samples_stage1/`, the lagged FWI matrix.
- **Outputs:** `files/hierarchical_model/*.rds` — **the fitted spread model (production constant).**

## Refactor targets
- Split inline data manipulation out of the fitting script into functions (tech debt #2).
- Vendor the `FireSpread` R spread wrappers instead of sourcing from `tests/testthat/` (#3).
