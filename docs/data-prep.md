# data_prep — preprocessing

> **Status: scaffold.** High-level content below is accurate (from the old repo's inventory);
> the deep method detail (marked _TODO_) is written as each script is migrated and read closely.

Turns raw inputs (`data/`) into the intermediate products the models consume; outputs go back
under `data/` (heavy, in the store).

## Flammability indices — `flammability_indices.R`
- **Purpose:** fit vegetation (VFI) and topographic (TFI) flammability indices; detrend NDVI.
- **Method:** Stan logistic regression. _TODO: response, predictors, priors, link, standardization._
- **Inputs:** raw NDVI rasters, fire data (`data/`).
- **Outputs:** `data/flammability_indices/flammability_indices.rds`, `ndvi_detrender_model.rds`
  (loaded at source time by `R/flammability_indices_functions.R`).

## FWI standardization & fortnights — `fwi_standardize.R`
- **Purpose:** detrend daily FWI to temporal anomalies; aggregate to 14-day fortnights.
- **Method:** _TODO: detrending model, fortnight indexing (`R/fortnight_functions.R`, origin 1996)._
- **Inputs → Outputs:** daily FWI tifs (`data/`) → standardized fortnight FWI rasters.

## Lagged FWI matrix — `fwi_fortnight_matrix.R`
- **Purpose:** build the lagged FWI-anomaly matrix at ignition points for model fitting; also the
  exp-quad temporal aggregation scale. _TODO: lag structure, interpolation, lengthscale._

## FWI projections — `fwi_projections.R`
- **Purpose:** process CMIP6 projected FWI (2050/2090) using modern-period calibration.
  _TODO: models, bias handling, calibration window._

## Landscape arrays — `landscapes_preparation.R`
- **Purpose:** build 6-layer landscape arrays (VFI, TFI, elevation, wind direction, wind speed,
  FWI) for each focal fire **and** for PNNH (regime simulation).
- **Refactor (tech debt #1):** make this a **function** that builds any landscape, not a loop.
- **Depends on:** `../FireSpread` wrappers, `R/flammability_indices_functions.R`, WindNinja outputs
  (_tech debt #5: hardcoded WindNinja path → config_).
- **Outputs:** `data/focal_fires/landscapes/*.rds`.
