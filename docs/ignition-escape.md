# ignition_escape — ignition & escape models (paper 2)

> **Status: scaffold.** High-level content is accurate (from the old repo's inventory); deep
> method/statistics detail (marked _TODO_) is written as the scripts are migrated and read.

The two simpler sub-models, fitted together. Canonical version is the old repo's `_FWIZ` variant.

> **Note:** in the regime paper, **a few functions in the spatial ignition model will change**
> from the thesis version (see the PhD thesis, chapter 4 + supplementary — link in `CLAUDE.md` /
> root `README.md`). Document the *current* formulation here.

## Fit — `fit.R`
- **Ignition model:** probability/rate of fire ignition per unit area per unit time.
  - **Method:** negative binomial. _TODO: spatial structure, covariates (flammability, FWI),
    offset/exposure, link._
- **Escape model:** probability a fire escapes to become a large fire.
  - **Method:** logistic regression. _TODO: covariates, threshold defining "escape"._
- **Fitted via:** Stan. Sources `R/flammability_indices_functions.R` + `R/fortnight_functions.R`.
- **Inputs:** ignition/size data (`data/ignition/…`), ignition-point shapefiles, FWI data.
- **Outputs:** `files/ignition/ignition_model_samples.rds`, `escape_model_samples.rds`
  — **production constants** consumed by `fire_regime/`.
