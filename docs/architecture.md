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
| `data_private/` → private store | — | non-public ignition record (symlink; gitignored) — see *The two stores* below |
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
`landscapes_preparation.R`, `landscapes_simulation.R`.

**Layer 2b — model fitting** (`spread/`, `ignition_escape/`, write to `files/`):
`spread/stage1_smc.R` → `spread/hierarchical_fit.R`; `ignition_escape/fit.R`.

**Layer 3 — integration** (`fire_regime/`): `recalibrate.R`, `simulator.R`, `simulate.R`,
`probability_maps.R`, `plots.R`.

### Function-library sourcing (who sources what)

```
R/flammability_indices_functions.R
    ↑ sourced by: R/landscape_functions.R, data_prep/landscapes_{preparation,simulation}.R,
                  spread/hierarchical_fit.R, ignition_escape/fit.R,
                  fire_regime/{simulate,probability_maps,plots}.R
    (loads data/flammability_indices/*.rds at source time)

R/landscape_functions.R
    ↑ sourced by: data_prep/landscapes_preparation.R, data_prep/landscapes_simulation.R
    (needs R/config.R + R/flammability_indices_functions.R sourced first; holds the
     frozen wind_sd and the canonical land_names)

R/fortnight_functions.R
    ↑ sourced by: data_prep/fwi_standardize.R, data_prep/fwi_fortnight_matrix.R,
                  data_prep/fwi_projections.R, ignition_escape/fit.R, fire_regime/simulate.R

R/mcmc_functions_smc.R
    ↑ sourced by: spread/hierarchical_fit.R

R/spread_validation_functions.R
    ↑ sourced by: spread/validation_{simulate,observed,analysis}.R,
                  spread/simulate_focal_metrics.R, spread/figure_validation_metrics.R

R/focal_simulation_functions.R
    ↑ sourced by: spread/simulate_focal_metrics.R, spread/figure_burn_probability.R
    (posterior draws -> simulator parameters for one focal fire; the `steps`
     natural-vs-logit scale trap lives here)

../FireSpread  (library + R spread wrappers)
    ↑ used by: data_prep/landscapes_{preparation,simulation}.R, spread/stage1_smc.R,
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
    ├─ data_prep/landscapes_simulation.R     → data/simulation_landscapes/landscapes/*.rds (one per tile)
    │                                          data/pnnh_images/pnnh_spread_landscape*.rds
    │
    ├─ ignition_escape/fit.R                 → files/ignition/{ignition,escape}_model_samples.rds
    │    (reads data_private/ignition/ — the non-public record, separate store)
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

## The two stores

Heavy data lives in **two** sibling folders outside git, both mirroring the repo's relative
paths and both linked in by `./setup.sh`:

| Store | Mirrors | Holds | Shareable? |
|-------|---------|-------|------------|
| `fire-regime-sim-patagonia-store` | `data/`, `files/` | everything else | **yes** |
| `fire-regime-sim-patagonia-store-private` | `data_private/` | `ignition/` — the non-public ignition record | **no, never** |

The shareable store is published as a read-only Drive link, and it is the link the spread
paper's data availability statement points at:
<https://drive.google.com/drive/folders/1oqhWG3qKghszEEHhP24v30GrbHm2jwme>
(verified 2026-09-08: folder `fire-regime-sim-patagonia-store`, "anyone with the link" as
**reader**, owner-only write). The private store has no link and must never get one.

### Why the split exists

The PNNH fire-report record (Marcelo Bari, APN) and the lightning-ignition database (Thomas
Kitzberger) were provided for this research only. The main store is what gets handed out as a
single Google Drive link (the papers' data availability statements point at it), so anything
inside it is effectively published. Physical separation is the guarantee: a share link cannot
reach a folder it was never given. The alternative considered and rejected was restricting the
subfolder's permissions inside Drive, which is one misconfiguration away from failing.

### What is in the private store

`data_private/ignition/` holds, in one folder (the two duplicated folders it replaced were
merged, and identical copies of both source spreadsheets dropped):

- `Total_focos_NH_nov89-mar21.xlsx`, `base_ampliado_kitzberger_rayos.xlsx` — the two sources;
- `ignition_points_pnnh_bari-kitzberger.*` — the two merged and de-duplicated (n = 288), as
  uploaded to Earth Engine, and `..._data.*` — the same points back with covariates (n = 285);
- `population_points_pnnh_bari-kitzberger_data.*` — background pixels with the same covariates
  (n = 23,986). No ignition record in it, so not sensitive in itself; kept here because it is
  useless without the ignition points and because a whole-folder rule cannot be misapplied;
- `ignition_size_data.csv` — the merged record with covariates, escape flag and size class
  (n = 284), read by `fire_regime/simulate.R`. Legacy: no script in this repo writes it (it
  came from the thesis repo's abandoned size model), so it cannot currently be regenerated;
- one kml with a single ignition point located from news reports.

### What deliberately stays public

The fitted ignition and escape posteriors (`files/ignition/*.rds`) and
`data/pnnh_images/pnnh_data_summary.rds`: parameters, prediction surfaces and covariate
means/sds, verified to contain no individual record. The spread paper's ignition points
(`data/ignition_points_checked*`, the 57 focal fires) are a different dataset and are public.

### Working with it

Only three places read the private store: `ignition_escape/fit.R` (`igdata_dir`),
`fire_regime/simulate.R` (the observed-size comparison) and `fire_regime/plots.R` (the
ignition-point map). Everything else, the whole spread pipeline included, runs from the
shareable store alone, so `./setup.sh` takes the private path as an **optional** second
argument and simply skips the `data_private/` link when it is absent.

**When adding a file that contains individual ignition records, write it under
`data_private/`.** Nothing derived from that record belongs in `data/` or `files/`.

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
   not a hard-coded loop — **done**: the three near-duplicate blocks became
   `build_landscape()` + friends in `R/landscape_functions.R`, driven by
   `data_prep/landscapes_preparation.R` (fire-wise) and `data_prep/landscapes_simulation.R`
   (study-area tiles + PNNH). Verified to reproduce the saved landscapes bit-for-bit — see
   `docs/data-prep.md`.
2. Split the monolithic hierarchical-fit script — algorithm core stays in `R/`, inline data
   manipulation becomes functions.
3. Don't source `R_spread_functions.R` from `FireSpread/tests/testthat/` — **done**: `land_cube`/
   `rast_from_mat` now live in `FireSpread/R/spread_helpers.R`, exported by the package
   (`docs/migration.md` TODO #1).
4. Make the working-directory assumption explicit (repo root via the `.Rproj`).
5. Replace the hardcoded WindNinja absolute path with a config value — **done**: centralized in
   `R/config.R`. WindNinja itself is now built from source and installed on this machine too
   (`docs/migration.md` TODO #3 has the full build log, including a config-format fix this
   surfaced in `landscapes_preparation.R`).
6. One canonical version per script; drop the suffix sprawl — **done** during migration.
