# data_prep/ — preprocessing → intermediate data

Turns raw inputs (`data/`) into the intermediate products the models consume. Outputs are
written back under `data/` (heavy, in the store).

> Full detail: [`../docs/data-prep.md`](../docs/data-prep.md).

| File | Role |
|------|------|
| `flammability_indices.R` | Fits VFI/TFI models (Stan logistic regression); exports fitted index params |
| `fwi_standardize.R` | Detrends daily FWI to anomalies and aggregates by fortnight |
| `fwi_fortnight_matrix.R` | Builds the lagged FWI-anomaly matrix at ignition points for model fitting |
| `fwi_projections.R` | Processes CMIP6 projected FWI (2050/2090) with modern-period calibration |
| `landscapes_preparation.R` | Builds 6-layer landscape arrays (VFI, TFI, elev, wind dir/speed, FWI). **Refactor into a function** that builds any landscape (focal fire *or* PNNH), not a loop |
| `vegetation_lara_merge.R` | Merges the raw Lara et al. 1999 vegetation polygons (source of the GEE `vegetation_valdivian_raw` asset) |
| `vegetation_ciefap_merge.R` | Merges + reclassifies the ciefap vegetation polygons (source of the GEE `vegetation_ciefap_2016_NQN-RN-CH_reclass` asset) |

The last two feed a GEE-side mosaic in a separate repo (`~/dev/fire_spread-gee/`) — see
"Regional vegetation raster" in `docs/data-prep.md` for the full cross-repo chain.
