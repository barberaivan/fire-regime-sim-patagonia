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

## Regional vegetation raster — the full chain (R here + GEE in a separate repo)

A single regional vegetation raster is used as the `veg`/`GRID_CODE` source for every focal
fire's raw GEE export and the PNNH landscape — built from the **ciefap** map (2016 imagery),
with pixels burned **before ~2014** patched with cover from the **Lara et al. 1999** map instead
(a post-2014 map can't show pre-fire vegetation where a fire predates it). The chain:

```
Lara norte/centro/sur.shp  ──┐                      ciefap NQN/RN/CH_2013 provincial .shp ──┐
                              ├─ R (this repo)                                              ├─ R (this repo)
                              ▼                                                             ▼
              vegetation_map_lara1999.shp                          ciefap_2016_NQN-RN-CH_reclass.shp
                              │                                                             │
                              └──────────────┬──────────────────────────────────────────────┘
                                              ▼  upload to GEE as assets
                         GEE: "Vegetation type image - CIEFAP WWF merge"  (~/dev/fire_spread-gee/)
                          — pre-2014-burned mask (bef14) + mosaic([Lara, ciefap masked by bef14])
                                              ▼
                    GEE asset vegetation_ciefap_wwf3  →  consumed by "Landscapes export" /
                                                          PNNH export GEE scripts
                                              ▼
                data/focal_fires/raw_gee/*.tif  and  data/pnnh_images/*.tif  (already in this repo)
```

### Lara merge — `vegetation_lara_merge.R`
- **Purpose:** merge the 3 regional Lara et al. 1999 vegetation polygon pieces into one raw
  (non-reclassified) layer, reprojected to WGS84 for GEE upload.
- **Inputs:** `data/vegetation_lara/{norte,centro,sur}.shp`.
- **Outputs:** `data/vegetation_lara/vegetation_map_lara1999.shp` (157,145→15,523-feature merge;
  this is the source of the GEE asset `vegetation_valdivian_raw`) and a `Kitz22`/`FireSpread`
  classification-comparison CSV (side output, not consumed downstream).
- **Note:** the GEE mosaic script does its own `GRID_CODE`→`cnum1` remap directly from this raw
  merge (matching `data/vegetation_equivalences.xlsx`'s `Sheet3`) — this script does *not* do
  any string-based reclassification itself (that was a separate, superseded branch — see below).
- **Verified:** actually run end-to-end (not just parsed) — merges 15,523 polygons.

### ciefap merge — `vegetation_ciefap_merge.R`
- **Purpose:** merge ciefap's 3 provincial (Neuquén/Río Negro/Chubut, **2013 vintage** — the
  2017 vintage and the untouched Santa Cruz/Tierra del Fuego `.rar` archives aren't used) shape-
  files, and join the vegetation-class equivalence table by `Ley_N3` to attach
  `class1/cnum1/class2/cnum2`.
- **Inputs:** `data/vegetation_ciefap/{NQN_2013,RN_2013,CH_2013}/cob_2013_N3_aok_*.shp`,
  `config$veg_equiv_xlsx_ciefap` (`R/config.R`; **sheet 1**, keyed by `Ley_N3` — a different
  sheet/join than `veg_equiv_xlsx`'s `Sheet2`).
- **Outputs:** `data/vegetation_ciefap/ciefap_2016_NQN-RN-CH_reclass.shp` (this is the source of
  the GEE asset `vegetation_ciefap_2016_NQN-RN-CH_reclass`) and an area-by-`Ley_N1/N2/N3` summary
  CSV (side output).
- **Verified:** actually run end-to-end — merges 157,145 polygons across the 3 provinces,
  produces a 142-row area summary (matches the equivalence table's first sheet row count), and
  all 11 expected `class1` categories are present after the join.

### GEE-side mosaic + pre-2014 patching (separate repo — see `CLAUDE.md`)
`~/dev/fire_spread-gee/` (remote `https://earthengine.googlesource.com/users/Ivan_Barbera/
fire_spread`), script `Vegetation type image - CIEFAP WWF merge`: computes a per-pixel earliest-
burn-year mask (`bef14` = burned before 2014, the year the ciefap imagery was taken), masks the
ciefap image wherever `bef14` is true, then `mosaic()`s `[Lara, ciefap-masked]` — GEE's
`mosaic()` falls through to the lower image wherever the top one is masked, so pre-2014-burned
pixels get Lara's cover and everywhere else gets ciefap. Result: the GEE asset
`projects/ivanbarbera-001/assets/vegetation_ciefap_wwf3` (also referenced as
`users/IvanBarbera/Fire_spread/vegetation_ciefap_wwf` / `.../vegetation_ciefap_wwf_imported`),
consumed directly by the `Landscapes export` and PNNH export GEE scripts. **Not migrated into
this repo**, per the `mapbiomas-arg-fire`/`-gee` precedent — GEE JS stays in its own repo.

### Excluded — exploratory/superseded, not migrated
Left in their original Insync folders (`~/Insync/Mapa vegetación WWF - Lara et al. 1999/`):
`subseting lakes.R`, `vegetation reclassification.R`, `vegetation reclassification_dry forests
separados.R`, `rasterize vegetation polygons.R`. Confirmed exploratory: their outputs
(`vegetation_valdivian_img*`, `*reclassified*`, `*dryforest2*`, `Kitz22`-labeled results) are
referenced **nowhere** downstream (neither in this repo nor `fire_spread-gee`), and they depend
on `rgeos`/`rgdal` — retired from CRAN in 2023, not installed here, so they couldn't run as-is
regardless. See `docs/migration.md` TODO #8 / T12 for the full investigation.
