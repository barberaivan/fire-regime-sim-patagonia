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

## Regional vegetation raster (built in GEE, not in this repo — `docs/migration.md` TODO #8)
- **Purpose:** a single regional vegetation raster used as the `veg`/`GRID_CODE` source for every
  focal fire's raw GEE export and the PNNH landscape — built from the **ciefap** map (2016
  imagery), with pixels burned **before ~2014** patched with cover from the **Lara et al. 1999**
  map instead, since a post-2014 map can't show pre-fire vegetation where a fire predates it.
- **R-side prep** (one-time, upstream, not re-run by this repo): `vegetation reclassification.R`
  (`~/Insync/Mapa vegetación WWF - Lara et al. 1999/`) reclassifies the Lara polygons into 8
  classes; `exploring_layers.R` (`~/Insync/Mapa vegetación ciefap/`) merges ciefap's regional
  shapefiles and joins the `class1/class2` equivalence table (same table now at
  `data/vegetation_equivalences.xlsx` / `_ciefap.xlsx`). Both scripts upload their result to GEE.
- **GEE-side mosaic + patching** (separate repo, `~/dev/fire_spread-gee/` — see `CLAUDE.md`):
  the script `Vegetation type image - CIEFAP WWF merge` computes a per-pixel earliest-burn-year
  mask (`bef14` = burned before 2014), masks the ciefap image wherever `bef14` is true, then
  `mosaic()`s `[Lara, ciefap-masked]` — GEE's `mosaic()` falls through to the lower image
  wherever the top one is masked, so pre-2014-burned pixels get Lara's cover and everywhere else
  gets ciefap. Result is the GEE asset `projects/ivanbarbera-001/assets/vegetation_ciefap_wwf3`
  (also referenced as `users/IvanBarbera/Fire_spread/vegetation_ciefap_wwf` /
  `.../vegetation_ciefap_wwf_imported`), consumed directly by the `Landscapes export` and PNNH
  export GEE scripts — this is the actual source of the `veg` band in every raw GEE `.tif`
  already in `data/focal_fires/raw_gee/` and the PNNH rasters in `data/pnnh_images/`.
- **Not migrated into this repo**, per the `mapbiomas-arg-fire`/`-gee` precedent: GEE JS stays in
  its own repo; the R reclassification scripts are one-time upstream inputs, not part of any
  recurring pipeline here, and remain in their original Insync folders.
