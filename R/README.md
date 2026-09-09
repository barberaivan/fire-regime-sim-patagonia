# R/ — shared function libraries

Reusable functions with **no upstream script dependencies**, sourced by the pipeline
scripts in `data_prep/`, `spread/`, `ignition_escape/` and `fire_regime/`.

Planned files (migrated from the old repo):

| File | Role |
|------|------|
| `flammability_indices_functions.R` | VFI/TFI computation + NDVI detrending; loads fitted index params from `data/` |
| `landscape_functions.R` | Shared recipe for every landscape: vegetation crosswalk, WindNinja wrapper, `build_landscape()`, fire-wise elements. Holds the frozen `wind_sd` |
| `fortnight_functions.R` | 14-day fortnight indexing (`date2fort()`), origin fixed at 1996 for FWI compatibility |
| `mcmc_functions_smc.R` | Core MCMC utilities for the hierarchical spread model (SMC variant): the single-parameter Gibbs/MH updates and the `logit_scaled` family |
| `hierarchical_mcmc_functions.R` | The stage-2 sampler itself: `mcmc()`, `mcmc_parallel()`, `acceptance()`. Reads its data from the global environment, as the monolith it came from did |
| `hierarchical_fit_data.R` | Stage-2 constants, the 235-fire table, design matrices and priors, as `hierarchical_fit_setup()` / `hierarchical_fit_priors()`; plus `hierarchical_fit_dirs()` and `read_fit()`, which give every stage-2 script its `test_mode` |
| `spread_validation_functions.R` | Shape metrics and the donor-centred conditional-logit spatial signature, applied identically to observed and simulated fires |
| `focal_simulation_functions.R` | Turns posterior draws into simulator parameters for re-simulating a focal fire — fitted vs newly drawn random effects, and the `steps` scale trap. Shared by the Fig. 5 and Fig. 6 runs |
