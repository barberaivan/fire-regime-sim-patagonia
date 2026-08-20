# R/ — shared function libraries

Reusable functions with **no upstream script dependencies**, sourced by the pipeline
scripts in `data_prep/`, `spread/`, `ignition_escape/` and `fire_regime/`.

Planned files (migrated from the old repo):

| File | Role |
|------|------|
| `flammability_indices_functions.R` | VFI/TFI computation + NDVI detrending; loads fitted index params from `data/` |
| `landscape_functions.R` | Shared recipe for every landscape: vegetation crosswalk, WindNinja wrapper, `build_landscape()`, fire-wise elements. Holds the frozen `wind_sd` |
| `fortnight_functions.R` | 14-day fortnight indexing (`date2fort()`), origin fixed at 1996 for FWI compatibility |
| `mcmc_functions_smc.R` | Core MCMC utilities for the hierarchical spread model (SMC variant) |
| `spread_validation_functions.R` | Shape metrics and the donor-centred conditional-logit spatial signature, applied identically to observed and simulated fires |
