# spread/ — spread model fitting

Fits the fire spread model in two stages, then validates it against emergent patterns of the
observed fire record. This is the largest, most complex module and the subject of paper 1.
Uses the external `FireSpread` engine (`../FireSpread`).

> Full detail: [`../docs/spread.md`](../docs/spread.md). Every paper figure has its own
> script here; none of them re-fits anything, and the pieces they share are in
> `R/spread_figure_functions.R`.

Planned files (migrated from the old repo):

| File | Role |
|------|------|
| `stage1_smc.R` | Stage 1 — fire-wise posterior sampling via ABC-SMC (compiles `src/sample_triplets_weighted.cpp`); writes to `files/` |
| `hierarchical_fit.R` | Stage 2 — hierarchical Bayesian fit via custom MCMC (Gibbs + MH), using stage-1 samples as proposals |
| `validation_ignition_cells.R` | Stage 3, run once — eligible ignition cells per study-area tile, and how many survive eroding the tile by each `steps` margin |
| `validation_simulate.R` | Stage 3 — simulates fires over the tiles from the full posterior and reduces each to a summary row (size, shape, spatial signature) |
| `validation_observed.R` | Stage 3 — the observed side: the same shape and signature metrics over all 241 mapped fires, into `files/spread_validation/observed_{signature,shape}.rds` |
| `validation_analysis.R` | Stage 3 — the comparison: size Q-Q, shape and signature conditioned on size and on FWI; figures into `files/spread_validation/figures/`, numbers into `validation_summary.rds` |
| `figure_study_area.R` | Paper Fig. 1 — the study-area map, three panels plus a locator inset; the 57 fires with a mapped ignition point in their own colour. Reads base layers from outside the store (`R/config.R`) |
| `figure_spread_curves.R` | Paper Figs. 2 and S2 — fitted spread probability against the model predictors, and against the raw variables behind them |
| `figure_params_fwi.R` | Paper Fig. 3 — the six spread parameters as a function of FWI, population band over the 57 fitted random effects |
| `figure_vegetation_effect.R` | Paper Fig. 4 — how much vegetation type still separates spread probability as fire weather worsens |
| `figure_flammability_indices.R` | Paper Fig. S1 — VFI and TFI as functions of NDVI, elevation and northing |
| `figure_parameter_correlations.R` | Paper Fig. S3 — posterior correlation between every pair of parameters, marginal and conditional to FWI (caches to `files/hierarchical_model/parameter_correlations.rds`) |
| `figure_focal_fit.R` | Paper Figs. S4 and S5 — per-fire overlap and per-fire simulated/observed size, both random-effect modes |
| `figure_burn_probability.R` | Paper Fig. 5 — burn-probability maps for four focal fires, fitted vs simulated random effects, into `manuscript-spread/figures/` |
| `simulate_focal_metrics.R` | Re-simulates the 57 focal fires (2000 x 2 random-effect modes) and reduces each simulated fire to size, size by vegetation class and shape — the input to Fig. 6. Supersedes the `metrics_table.rds` block of `hierarchical_fit.R` |
| `figure_dharma_metrics.R` | Paper Fig. 6 — DHARMa Q-Q of burned area (overall and by vegetation class), compactness and wind-axis deviation, 57 focal fires, fitted vs simulated random effects |
| `figure_validation_metrics.R` | Paper Fig. 7 — one figure in two parts: the size distribution (A) and size / compactness / wind-axis deviation conditioned on FWI and on size (B) |
