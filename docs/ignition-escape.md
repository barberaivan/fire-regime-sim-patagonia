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
- **Inputs:** ignition/size data (`data/ignition/…`), ignition-point shapefiles, FWI data,
  the external (non-public) `data/ignition_data/` — Bari/Kitzberger PNNH ignition + population
  point samples.
- **Outputs:** `files/ignition/ignition_model_samples.rds`, `escape_model_samples.rds`
  — **production constants** consumed by `fire_regime/`.

## Abandoned/superseded model variants — not part of the canonical pipeline

Two earlier formulations exist in this folder but are **not used** by the canonical fit above.
Confirmed with the user (2026-07-09); flagged here rather than removed, since the user is
prioritizing spread-side work next and doesn't want to touch ignition-escape right now.

- **`escape_model_ordinal.stan`** — an earlier **ordinal** (K size-class) formulation of escape
  (`ordered` cutpoints + `categorical` likelihood), superseded by the binary model above. Its
  fitted output, `escape_model_samples_ordinal.rds`, still sits in `files/ignition/` (copied
  wholesale during migration) but nothing reads it. **Can be deleted** whenever this area is
  revisited — no other decision needed.
- **`size_model.stan`** + the **"Fire size model" section in `fit.R`** — a continuous fire-size
  regression (log-area, `skew_normal` likelihood, left-censored below one-pixel-size), from
  before the escape question was simplified to binary. **Never finished**: the script's
  `sizemod` is used (for `summary()`/diagnostic plots) but never assigned — its `sampling()` call
  is commented out, and unlike `igmod`/`escmod`, no fitted `.rds` exists anywhere to load
  instead. This section **cannot run from a fresh session as-is**. It is **unrelated** to
  `spread/hierarchical_fit.R`'s own `stansteps` (a steps~area regression used to initialize the
  spread model's stage-2 MCMC) — no code cross-reference between the two, and the ignition-escape
  work came chronologically *after* the spread model was fit, so it could not have informed it.
  When revisited: either fit `sizemod` properly and cache it, or remove the section.
