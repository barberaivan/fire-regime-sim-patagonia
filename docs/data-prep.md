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

## Landscape arrays — `landscapes_preparation.R` + `landscapes_simulation.R`

A landscape is a 3-D array `[row, col, layer]` with **six layers, in this order**:

| Layer | Content |
|---|---|
| `veg` | `{0: wet forest, 1: subalpine, 2: dry forest, 3: shrubland, 4: grassland, 99: non-burnable}` |
| `vfi` | vegetation flammability index, standardized |
| `tfi` | topographic flammability index, standardized |
| `elevation` | m a.s.l., **raw** — the slope term is scaled through its coefficient (`fi_params$slope_term_sd`), not through the layer |
| `wdir` | wind direction, radians, the direction the wind comes **from** |
| `wspeed` | wind speed / `wind_sd` |

Those layer names are indexed by name downstream (`terrain_variables <- c("elevation", "wdir",
"wspeed")` in `spread/` and `fire_regime/`), so they are part of the file format — do not rename
them. FWI is **not** a landscape layer despite the old script header saying so: it is a
fire-level covariate carried in the fires table read by `spread/hierarchical_fit.R`.

Cells with any missing predictor are marked `veg = 99` and their layers filled with `-9999`; the
engine skips non-burnable neighbours before reading any layer, so the fill value never enters a
calculation.

### The two kinds of landscape

Both scripts drive the same recipe, `R/landscape_functions.R`. They differ only in what the
paper needs them for:

| | `landscapes_preparation.R` | `landscapes_simulation.R` |
|---|---|---|
| Purpose | **fit** the spread model | **simulate** new fires (size distribution) |
| Extent | one landscape per focal fire (57) | 4 study-area tiles + PNNH |
| Fire-wise data | ignition point, observed burned area, per-fire wind direction | none — ignitions and FWI are drawn by the simulator |
| Urban class | → wet forest, so its burn probability tracks NDVI | → **non-burnable** (a 600-km region contains Bariloche, Esquel, El Bolsón) |
| NDVI | previous summer's, detrended to its 2022 equivalent | tiles: 2022 as-is (already that scale); PNNH: 2021 as-is |
| WindNinja mesh | 90 m | 120 m (region-sized DEMs do not fit 90 m in RAM) |
| Wind direction | per fire, from the climatic table | fixed 293° |
| Output | `data/focal_fires/landscapes/<fire_id>.rds` (list: array + fire-wise elements) | `data/simulation_landscapes/landscapes/study_area_tile_<k>.rds` (list: array + geometry); `data/pnnh_images/pnnh_spread_landscape*.rds` (bare array — that is what `fire_regime/simulate.R` reads) |

Both scripts have stage flags at the top (`do_windninja`, `do_tiles`, `do_pnnh`, …) so the slow
WindNinja pass is not re-run by accident.

### Study-area tiles

The study area of Barberá et al. 2025 is ~600 km of latitude — too much for one export or one
WindNinja run. It is cut into `K` latitudinal pieces of equal latitudinal length, each exported
as a rectangle. **The tiling lives entirely in GEE**, in `Landscapes export for simulation
(study area tiles)` (`~/dev/fire_spread-gee/`), because it depends on the assets' footprints,
which only GEE knows. Two constraints shape the rectangles:

- **They do not overlap.** Consecutive tiles meet at a shared edge that falls on the 30 m export
  grid, so no pixel belongs to two tiles. The cost is that a fire reaching a tile's border is cut
  short by it — a property of the tiling, not of the landscape, and something the simulation has
  to deal with (before 2026-08-20 the tiles were instead buffered by 10 km and overlapped by
  ~20 km, so that edge fires had room to spread).
- **They stay inside the data.** `ndvi` and `veg` come from finite assets whose footprints do not
  cover the study area's bounding box, and whose edges are not axis-aligned in EPSG:5343 — a
  rectangle fitted to the study area alone carries a wedge of NA along its border. Each tile is
  therefore cropped to where both assets have data at *every* latitude it spans, measured by
  probing the assets themselves. Interior NA (lakes, rock, unclassified vegetation) is untouched
  by this and expected: `build_landscape()` turns any cell with a missing predictor into a
  non-burnable one. The GEE console prints each tile's data fraction, so the two cases stay
  distinguishable.

At `K = 4` the tiles are ~150 km tall and as wide as the study area is at those latitudes, each
at or below the size of the PNNH landscape that already works downstream; raise `K` if one stops
fitting in memory. As arrays they are ~1 GB each, so load one at a time.

The export writes `veg`, `ndvi`, `elevation`, `slope`, `aspect` per tile. Drop the downloaded
files in `data/simulation_landscapes/raw_gee/` under the names GEE gave them — the R side globs
`study_area_tile_<k>_*.tif` and `vrt()`s them if an export came back split. Nothing is uploaded
to GEE: the rectangles are derived there from the `study_area` asset.

`study_area_tiles.shp` (written to `data/simulation_landscapes/`) is the R-side record of the
tiles, read back from the exported rasters' own extents, so it coincides with them exactly. It is
not an input to GEE. `landscapes_simulation.R` also prints how much of the study area the tiles
cover, which cropping to the assets can leave below 100%.

### What a tile `.rds` contains

A list, not a bare array (unlike the PNNH files, which stay bare because `fire_regime/simulate.R`
reads them that way):

| Field | Content |
|---|---|
| `landscape` | the `[row, col, layer]` array, layers as in the table above |
| `tile`, `n_tiles` | which tile this is, out of how many |
| `template` | single-layer SpatRaster giving the tile's extent/resolution/CRS — **`terra::wrap()`ped**, so call `unwrap()` before use. Pair it with `rast_from_mat()` to put a simulated fire back on the ground, or to turn cell indices into coordinates |
| `counts_veg_available` | burnable cells per vegetation type (1:5), for sampling ignitions and for burn-probability denominators |
| `na_prop` | proportion of cells forced non-burnable by a missing predictor |

One fixed wind direction over 600 km is defensible: the circular mean of the mapped fires'
directions is 289–291° in every tile (290° overall; 293° over the 57 focal fires, which is the
value the PNNH wind field was built with and what the tiles use).

### `wind_sd` is frozen

Wind speed is standardized by `wind_sd = 1.464333`, the SD pooled over the 57 focal-fire
WindNinja runs. It is the scale the spread model was **fitted** under, so it lives as a constant
in `R/landscape_functions.R` and every landscape — focal fire, PNNH, tile — divides by that same
number. Recomputing it from a different set of landscapes would silently rescale the fitted wind
coefficient. `landscapes_preparation.R` re-derives it after a WindNinja pass and warns on drift.

> ⚠️ **The WindNinja outputs in `data/pnnh_images/` no longer match the saved PNNH landscapes.**
> The `*_ang.asc`/`*_vel.asc` files were regenerated on 2026-07-09 19:39 by the WindNinja built
> from source on this machine, while `pnnh_spread_landscape*.rds` date from 15:04 (copied from
> the old store). The two wind fields agree statistically (circular mean 293.9 vs 293.7; median
> speed 3.77 vs 3.74 m/s) but differ per cell by up to ~1.9 rad in complex terrain. The focal
> fires' WindNinja scratch dir is empty, so rebuilding *those* landscapes also means a new wind
> field. Consequence: rebuilding PNNH or the focal fires now would change results slightly
> — `do_pnnh` therefore defaults to `FALSE`. The simulation tiles are new and unaffected.

- **Verified:** `build_landscape()` + `fire_elements()` reproduce the saved landscapes
  bit-for-bit. On PNNH and on three focal fires (`1999_25j`, `2015_47N`, `2014_1`) the `veg`,
  `vfi`, `tfi` and `elevation` layers are zero-diff over all burnable cells, and `ig_rowcol`,
  `burned_ids`, `burned_layer` and `counts_veg*` are `identical()`. `vfi`/`tfi` on *non-burnable*
  cells changed from `-9999` to `0` (never read by the engine). Wind is the only real difference,
  for the reason boxed above.
- **Depends on:** `../FireSpread` (`land_cube`), `R/flammability_indices_functions.R`,
  `R/landscape_functions.R`, `WindNinja_cli` on `PATH`, `config$windninja_dir`.

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
