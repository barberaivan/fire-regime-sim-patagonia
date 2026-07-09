# Architecture & pipeline

How the modules fit together, the **module dependency tree**, and the end-to-end data flow.
This is the deep companion to the short per-folder READMEs and to `CLAUDE.md` (an index only).

Paths below use the **new repo layout**. During migration they are being translated from the
old PhD repo (`~/Insync/Fire spread modelling/fire_spread/`, blueprint in its `INVENTORY.md`).

---

## The models

A spatially explicit simulator combining three fitted sub-models over a landscape:

| Sub-model | Question it answers | Fitted in | Paper |
|-----------|---------------------|-----------|-------|
| **Ignition** | fires started per unit area per unit time | `ignition_escape/` | regime (2) |
| **Escape** | P(a fire escapes to become a large fire) | `ignition_escape/` | regime (2) |
| **Spread** | pixel-level burn probability via a cellular automaton | `spread/` | spread (1) |

`fire_regime/` integrates all three into the regime simulator and runs projections. The spread
engine itself (the C++ cellular automaton) is the **external `FireSpread` package**
(`../FireSpread`, a sibling repo); this repo *fits* the models and *drives* the engine.

---

## Module map

| Path | Layer | Role |
|------|-------|------|
| `R/` | 1 | shared function libraries (no upstream script deps) |
| `src/` | 1 | in-repo C++ (Rcpp) |
| `data_prep/` | 2a | preprocessing → intermediate data |
| `spread/` | 2b | spread model fitting |
| `ignition_escape/` | 2b | ignition + escape model fitting |
| `fire_regime/` | 3 | integration, recalibration, simulator, runs, plots |
| `data/` → store | — | heavy inputs (symlink; gitignored) |
| `files/` → store | — | heavy outputs (symlink; gitignored) |
| `manuscript-spread/`, `manuscript-regime/` | — | LaTeX sources for the two papers |
| `docs/` | — | this documentation |

---

## Layered dependency tree

**Layer 1 — function libraries** (sourced by everything downstream):

- `R/flammability_indices_functions.R` — `ndvi_detrend()`, `vfi()`, `tfi()`; loads fitted index
  params from `data/` at source time.
- `R/fortnight_functions.R` — `date2fort()` + reference table (origin fixed at 1996 for FWI).
- `R/mcmc_functions_smc.R` — MCMC core for the hierarchical spread fit (SMC variant).
- `src/sample_triplets_weighted.cpp` — compiled via `Rcpp::sourceCpp()` by the spread stage-1 fit.
- **external:** `FireSpread` R wrappers (`../FireSpread`) — `library(FireSpread)` + the R spread
  helper functions. *Tech debt: the old repo sourced these from `FireSpread/tests/testthat/`; vendor
  them or use a proper exported function here.*

**Layer 2a — preprocessing** (`data_prep/`, write back to `data/`):
`flammability_indices.R`, `fwi_standardize.R`, `fwi_fortnight_matrix.R`, `fwi_projections.R`,
`landscapes_preparation.R`.

**Layer 2b — model fitting** (`spread/`, `ignition_escape/`, write to `files/`):
`spread/stage1_smc.R` → `spread/hierarchical_fit.R`; `ignition_escape/fit.R`.

**Layer 3 — integration** (`fire_regime/`): `recalibrate.R`, `simulator.R`, `simulate.R`,
`probability_maps.R`, `plots.R`.

### Function-library sourcing (who sources what)

```
R/flammability_indices_functions.R
    ↑ sourced by: data_prep/landscapes_preparation.R, spread/hierarchical_fit.R,
                  ignition_escape/fit.R, fire_regime/{simulate,probability_maps,plots}.R
    (loads data/flammability_indices/*.rds at source time)

R/fortnight_functions.R
    ↑ sourced by: data_prep/fwi_standardize.R, data_prep/fwi_fortnight_matrix.R,
                  data_prep/fwi_projections.R, ignition_escape/fit.R, fire_regime/simulate.R

R/mcmc_functions_smc.R
    ↑ sourced by: spread/hierarchical_fit.R

../FireSpread  (library + R spread wrappers)
    ↑ used by: data_prep/landscapes_preparation.R, spread/stage1_smc.R,
               spread/hierarchical_fit.R, fire_regime/{simulate,plots}.R

src/sample_triplets_weighted.cpp
    ↑ compiled (sourceCpp) by: spread/stage1_smc.R
```

---

## End-to-end pipeline (canonical)

```
Raw data (GEE exports, FWI tifs, fire shapefiles)  →  data/
    │
    ├─ data_prep/flammability_indices.R      → data/flammability_indices/*.rds
    ├─ data_prep/fwi_standardize.R           → data/…/fwi_fortnights_*_standardized.tif
    ├─ data_prep/landscapes_preparation.R    → data/focal_fires/landscapes/*.rds  (one per fire)
    │
    ├─ ignition_escape/fit.R                 → files/ignition/{ignition,escape}_model_samples.rds
    │
    ├─ spread/stage1_smc.R                   → files/posterior_samples_stage1/*.rds
    ├─ spread/hierarchical_fit.R             → files/hierarchical_model/*.rds   ← spread params (production constant)
    │
    └─ fire_regime/recalibrate.R + simulate.R (uses simulator.R)
                                             → files/fire_regime_simulation/*.rds
                                                    └─ probability_maps.R / plots.R → manuscript-*/figures/
```

Production constants (extracted for the platform): the fitted spread model
(`files/hierarchical_model/`), the ignition & escape samples (`files/ignition/`), and the
regime **simulator function** (`fire_regime/simulator.R`).

---

## Migration status & tech debt

**Migration complete (T0–T11)** — canonical code and heavy data have been copied from the old
repo into this one and the store, renamed to canonical names, and verified (parse, sourcing,
data-loading through the store symlinks — not full multi-day fits/simulations run end-to-end).
Originals in the old repo are kept until the new repo is confirmed working. Legacy
`_FWIZ/_FWIZ2/_SMC` variants and `dump/` were **not** carried over (old `INVENTORY.md` §6); git
holds the history instead. Full task-by-task log, every finding, and the complete TODO register
live in **`docs/migration.md`** — the most important open item before running the full
pipeline:

- **`fire_regime/simulate.R` and `probability_maps.R` now read the canonical SMC-fitted spread
  model** (repointed from the legacy pre-SMC fit, structurally verified compatible), but neither
  script has been re-run/validated against it — existing outputs are stale until they are
  (`docs/migration.md` TODO #7).

- **The ignition-escape "fire size" model and ordinal-class escape model are abandoned/
  superseded** — see `ignition_escape/README.md`; not touched, just flagged.

Tech-debt items deferred to *after* this migration (old `INVENTORY.md` §9; not addressed here
per the behavior-preserving-first approach):

1. `landscapes_preparation.R` → a **function** that builds any landscape (focal fire *or* PNNH),
   not a hard-coded loop.
2. Split the monolithic hierarchical-fit script — algorithm core stays in `R/`, inline data
   manipulation becomes functions.
3. Don't source `R_spread_functions.R` from `FireSpread/tests/testthat/` — **done**: `land_cube`/
   `rast_from_mat` now live in `FireSpread/R/spread_helpers.R`, exported by the package
   (`docs/migration.md` TODO #1).
4. Make the working-directory assumption explicit (repo root via the `.Rproj`).
5. Replace the hardcoded WindNinja absolute path with a config value — **done**: centralized in
   `R/config.R` (`docs/migration.md` TODO #3 covers the remaining machine-setup step).
6. One canonical version per script; drop the suffix sprawl — **done** during migration.
