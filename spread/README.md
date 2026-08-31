# spread/ — spread model fitting

Fits the fire spread model in two stages, then validates it against emergent patterns of the
observed fire record. This is the largest, most complex module and the subject of paper 1.
Uses the external `FireSpread` engine (`../FireSpread`).

> Full detail: [`../docs/spread.md`](../docs/spread.md).

Planned files (migrated from the old repo):

| File | Role |
|------|------|
| `stage1_smc.R` | Stage 1 — fire-wise posterior sampling via ABC-SMC (compiles `src/sample_triplets_weighted.cpp`); writes to `files/` |
| `hierarchical_fit.R` | Stage 2 — hierarchical Bayesian fit via custom MCMC (Gibbs + MH), using stage-1 samples as proposals |
| `validation_ignition_cells.R` | Stage 3, run once — eligible ignition cells per study-area tile, and how many survive eroding the tile by each `steps` margin |
| `validation_simulate.R` | Stage 3 — simulates fires over the tiles from the full posterior and reduces each to a summary row (size, shape, spatial signature) |
| `validation_observed.R` | Stage 3 — the observed side: the same shape and signature metrics over all 241 mapped fires, into `files/spread_validation/observed_{signature,shape}.rds` |
| `validation_analysis.R` | Stage 3 — the comparison: size Q-Q, shape and signature conditioned on size and on FWI; figures into `files/spread_validation/figures/`, numbers into `validation_summary.rds` |
| `figure_burn_probability.R` | Paper Fig. 5 — burn-probability maps for four focal fires, fitted vs simulated random effects, into `manuscript-spread/figures/` |
| `figure_dharma_size.R` | Paper Fig. 6 — DHARMa Q-Q of burned area overall and by vegetation class, 57 focal fires, fitted vs simulated random effects |
| `figure_validation_metrics.R` | Paper Fig. 7 — the size distribution (A) and size / compactness / wind-axis deviation conditioned on FWI and on size (B) |
