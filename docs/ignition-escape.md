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
- **Escape model:** probability a fire escapes to become a large fire, defined as exceeding a
  size threshold of **0.09 ha (one pixel)** — see the script's "Escape model (> 0.09 ha)" section.
  - **Method:** binary logistic regression (`escape_model.stan`, `bernoulli_logit`). Confirmed
    canonical with the user (2026-07-09) — this is what `escape_model_samples.rds` is fit from.
    _TODO: covariates beyond FWI/vfi/tfi/distance-to-roads-humans, full spec._
- **Fitted via:** Stan. Sources `R/flammability_indices_functions.R` + `R/fortnight_functions.R`.
- **Inputs:** FWI data, the PNNH boundary, the flammability-index parameters, and the
  **non-public** ignition record in `data_private/ignition/` (Bari's PNNH fire reports,
  Kitzberger's lightning database, the merged point set with its Earth Engine covariates, and
  the population-point sample). That folder lives in a separate, never-shared store; see
  `architecture.md` → *The two stores*. This is the only fitting script that needs it.
- **Outputs:** `files/ignition/ignition_model_samples.rds`, `escape_model_samples.rds`
  — **production constants** consumed by `fire_regime/`.

## The ordinal escape variant: `escape_ordinal_exploratory.R`

Escape can also be asked as a size-class question rather than a yes/no one, and that version is
kept in `escape_ordinal_exploratory.R` (model file `escape_model_ordinal.stan`, fitted output
`files/ignition/escape_model_samples_ordinal.rds`). It is **exploratory: nothing in
`fire_regime/` reads it**, and it is not one of the paper's fitted models.

- **Response:** the fire's size class, cutpoints at **0.09, 10 and 100 ha** (K = 4 classes),
  instead of the binary > 0.09 ha indicator.
- **Method:** cumulative logit, with `ordered[K-1]` cutpoints and a `categorical` likelihood over
  the implied class probabilities. The linear predictor is the *same* as the binary model's:
  FWI through the Gaussian lag-weighting kernel, `vfi`, `tfi`, `drz`, `dhz`, with the cutpoints
  carrying what the binary model puts in its single intercept.
- **Why it is kept:** the 10 ha cutpoint. The spread simulator was estimated on fires above that
  size, so an escape definition anchored at 10 ha can be read off this fit without refitting.
- **How it runs:** it is a *continuation* of `fit.R`, not a standalone script. Run `fit.R` down
  to the end of its "Prepare data for escape model" section, then run this one in the same
  session; it takes `ig2`, `fwi_points`, `nlags` and `mean_ci` from there (the script stops with
  a message if they are absent). Sampling is a few minutes on 8 cores, but the fit is already in
  the store, so the `sampling()` call is commented and the `readRDS()` is the active line, the
  same convention `fit.R` uses.
- **Its `ordinal_predict()`** is the counterpart of `fit.R`'s `logistic_predict()`: same
  prediction grids, but it returns one class probability curve per size class instead of a
  single escape-probability curve.
- **It also writes** `data_private/ignition/ignition_size_data.csv` (`ig2` plus its size class),
  the file `fire_regime/simulate.R` reads to compare the simulated fire size distribution
  against the observed one. That `write.csv()` is commented like the other exports: re-run it
  only if the ignition record or the cutpoints change. This is why the size-class definition
  lives here rather than in `fit.R`, even though the regime side depends on its output.

The escape question was once also posed as a **continuous** fire-size regression (log-area,
`skew_normal`, left-censored at one pixel). That formulation is gone: it is not in the repo, has
no fitted output anywhere, and nothing reads it.
