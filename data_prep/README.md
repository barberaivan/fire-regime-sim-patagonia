# data_prep/ — preprocessing → intermediate data

Turns raw inputs (`data/`) into the intermediate products the models consume. Outputs are
written back under `data/` (heavy, in the store).

> Full detail: [`../docs/data-prep.md`](../docs/data-prep.md).

Planned files (migrated from the old repo):

| File | Role |
|------|------|
| `flammability_indices.R` | Fits VFI/TFI models (Stan logistic regression); exports fitted index params |
| `fwi_standardize.R` | Detrends daily FWI to anomalies and aggregates by fortnight |
| `fwi_fortnight_matrix.R` | Builds the lagged FWI-anomaly matrix at ignition points for model fitting |
| `fwi_projections.R` | Processes CMIP6 projected FWI (2050/2090) with modern-period calibration |
| `landscapes_preparation.R` | Builds 6-layer landscape arrays (VFI, TFI, elev, wind dir/speed, FWI). **Refactor into a function** that builds any landscape (focal fire *or* PNNH), not a loop |
