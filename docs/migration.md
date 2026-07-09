# Migration checklist — fire_spread → fire-regime-sim-patagonia

Living tracker for migrating canonical code + data from the old PhD monorepo
(`~/Insync/Fire spread modelling/fire_spread/`) into this repo. Work happens in small,
independently committable tasks (T0…T11) so a session can pick up one task, verify it, commit,
and stop — cheap to resume later. Tick a task's checkbox in the list below when its commit lands.

**Principles:**
- **Copy, never move.** Originals in `fire_spread/` stay untouched until everything verifies.
  Applies to the store too (heavy data is copied in, renamed as needed).
- **Behavior-preserving now, refactor later.** No logic changes in this pass — no
  loop→function, no splitting big scripts. Those are deferred (see TODO register).
- **Clean-rename folder names now** (drop spaces + `_FWIZ*/_SMC` suffixes). Individual data
  *filenames* stay as-is this pass (many near-duplicates exist; deferred).
- **FireSpread helpers stay sourced from `../FireSpread/tests/testthat/` for now** — exporting
  them properly from the package is TODO #1 below, done as its own small task.

Verification tooling: `/usr/bin/Rscript` — `parse()` for syntax, `file.exists()` for data,
light `source()` only for dependency-free libs.

---

## Task checklist

- [x] **T0** — This file + `R/config.R` (machine-local/external paths in one place).
- [x] **T1** — `R/` libraries: `fortnight_functions.R`, `mcmc_functions_smc.R`,
      `flammability_indices_functions.R` + its 2 `.rds` into `data/flammability_indices/`.
      Confirmed `mcmc_functions_smc.R` is self-contained — despite the header comment ("inherits
      from mcmc_functions.R"), it has no `source()` call and defines every function itself
      (`update_lm`, `update_corr`, `update_truncnorm`, `update_ranef`, `update_steps`,
      `update_stepsU`, the `logit_scaled*` family). `R/mcmc_functions.R` was **not** copied.
      All three files verified by actually `source()`-ing them (not just `parse()`), including
      `flammability_indices_functions.R` reading its `.rds` through the store symlink.
- [x] **T2** — Store inputs copy (`data/` folders, Reference B). 9.8G copied. Went beyond a
      blind `cp -r`: grep-verified which files are actually read by canonical scripts before
      copying, and excluded what wasn't (see below) — cheaper to decide now than to migrate and
      later wonder why a 4GB folder is unused.
      - `focal_fires/` (renamed from `focal fires data/`): `fire_size_data.{rds,csv}`,
        `raw_gee/` (renamed from `raw data from GEE/`, 58 files), `landscapes/`. **Excluded:**
        `defensa_tesis_extra/` (13M, thesis-defense presentation tifs, unreferenced),
        `gam_terms_to_include.{csv,xls}` and `fwi_values_ig-known.rds` (unreferenced by any
        canonical script).
      - `pnnh_images/`: copied only the 14 files actually referenced by canonical scripts
        (grep-verified across `landscapes_preparation.R`, `hierarchical_fit`, `simulate.R`,
        `probability_maps.R`, `plots.R`) — 3.3G. **Excluded** unreferenced multi-resolution/
        exploratory variants: `pnnh_data_300m.tif(.aux.xml)`, `_60m.tif`, bare `_30m.tif` and
        `_30m_std.tif` (only the `_buff_10000` variants are read), `_spread_buffered_120m.tif.tif`,
        `visualizing_images_scale.qgz`, and the WindNinja `_cld.asc/.prj` (only `_ang`/`_vel` are
        read for PNNH) — saved ~1.3G.
      - `protected_areas/`, `ignition/`, `fwi_daily_1998-2022/`: copied wholesale (small, all
        confirmed canonical).
      - `fwi_projections/`: copied wholesale **except** the three `_OLD`/`__old` superseded
        folders (`fwi_fortnights_standardized_modern_compare_OLD`,
        `fwi_fortnights_standardized_OLD`,
        `Quilcaille_Batibeniz_2023_database-nw_patagonia_clipped__old`) — saved ~1.9G, kept 4.7G
        incl. the 4.3G Quilcaille/Batibeniz CMIP6 database (confirmed read by
        `fwi_projections.R`'s `proj_dir`).
      - External `patagonian_fires.shp` (+ sidecars) copied from
        `~/Insync/patagonian_fires/patagonian_fires/` into `data/patagonian_fires/`.
      - Verified: full store tree listed, plus `file.exists()` spot-checks through the repo's
        `data` symlink for one representative path per folder — all `TRUE`.
- [x] **T3** — Store outputs copy (`files/` folders, Reference B). ~5.0G copied.
      - `hierarchical_model/` (from `hierarchical_model_FWIZ_SMC/`, 267M, 21 files, no `dump/`) —
        copied wholesale, **plus** `fwi_mean_sd_spread.rds` brought in from the **legacy**
        `hierarchical_model_FWIZ/` (non-SMC) folder. Reason: the canonical SMC fit script
        (`hierarchical model fitting_FWIZ2_SMC.R` line 660) has the `saveRDS()` for this file
        **commented out**, so it's never produced by the canonical pipeline — yet
        `fire_regime_simulations_FWIZ.R` (line 830) reads it. This is real pre-existing tech
        debt, not something introduced by the migration; see TODO #4 below — flagged rather
        than silently fixed, per the behavior-preserving-now principle. The rest of
        `hierarchical_model_FWIZ/` (its other 20 files + its `dump/` subfolder, which differs
        from its parent — a stale backup) was **not** copied: it's the legacy non-SMC fit,
        superseded by the SMC output.
      - `posterior_samples_stage1/` (from `posterior_samples_stage1_smc/`, 294M) — copied
        wholesale; clean, no `_exploration`/`-BACKUP` variants mixed in.
      - `ignition/` (from `ignition_FWIZ/`, 138M) — copied wholesale, including some
        alternative-spec model variants (`*_ordinal`, `*_time-only1/2`, `*_relative_raw`)
        alongside the two canonically-read files (`ignition_model_samples.rds`,
        `escape_model_samples.rds`); none are `_OLD`/`dump`-labeled so kept for provenance.
      - `fire_regime_simulation/` (from `fire_regime_simulation_FWIZ/`, 4.2G, 220 files) —
        copied wholesale; clean, no `_OLD`/`-EXPONENTIAL`/`_OLD_BUG` variants mixed in (those
        sibling folders exist in the old repo but were correctly excluded, per Reference B).
      - `landscape_flammability/` (72M, same name) — copied wholesale; not produced by any
        script in the canonical migration set (a leaf input, like the fixed CSVs in `data/`).
      - Verified: sizes match source folders; store `files/` tree listed; spot-checked
        `file.exists()` through the repo's `files` symlink.
- [x] **T4** — `data_prep/flammability_indices.R` (+ its `flammability_indices.stan` model,
      copied alongside since it's code, not store data). Path edits: `"flammability indices"`
      → `"flammability_indices"` (5 data read/write sites); `stan_model(...)` path updated to
      `data_prep/flammability_indices.stan`; external veg xlsx read replaced with
      `config$veg_equiv_xlsx` + a `# TODO(migration #2)` comment (added `source(R/config.R)`).
      Surfaced two more store gaps while reading the script, both filled: the input
      `ndvi_regional_points.shp` (+ sidecars, not yet copied in T2) and two of the script's own
      legitimate outputs already computed in the old repo — `flammability_indices_samples.rds`
      (21.9M Stan fit) and `ndvi_elevation_summary.rds` — carried over so the ~24-min Stan fit
      doesn't need re-running. Other files in that old data folder
      (`ndvi_effects_samples.rds`, `ndvi_ts_detrend.*`, `ndvi_images-by-summer.csv`,
      `ndvi_optim_and_proportion.rds`) are unreferenced by this script and were left out.
      **Verified:** `parse()` OK; grep audit clean (no leftover `"flammability indices"`/`/home/`);
      actually ran the script up through both store-backed reads
      (`ndvi_detrender_model.rds`, `ndvi_regional_points.shp`, both load through the symlink);
      confirmed `config$veg_equiv_xlsx` correctly resolves to **missing** (TODO #2, expected,
      not a new bug); separately compiled `flammability_indices.stan` at its new path with
      `stan_model()` — succeeds (only a pre-existing, harmless "incomplete final line" warning
      from the stan file itself). Full end-to-end run is blocked on TODO #2 (the xlsx).
- [ ] **T5** — `data_prep/` FWI scripts (`fwi_standardize.R`, `fwi_fortnight_matrix.R`,
      `fwi_projections.R`).
- [ ] **T6** — `data_prep/landscapes_preparation.R`.
- [ ] **T7** — `src/sample_triplets_weighted.cpp` + `spread/stage1_smc.R`.
- [ ] **T8** — `spread/hierarchical_fit.R`.
- [ ] **T9** — `ignition_escape/fit.R`.
- [ ] **T10** — `fire_regime/` (`simulate.R`, `probability_maps.R`, `plots.R`).
- [ ] **T11** — Global audit (repo-wide grep + sourcing smoke tests) + close out.

---

## Reference A — code file map (old → new)

| Old (in `fire_spread/`) | New (in repo) |
|---|---|
| `flammability indices/flammability_indices_functions.R` | `R/flammability_indices_functions.R` |
| `weather/fortnight_functions.R` | `R/fortnight_functions.R` |
| ~~`spread/mcmc_functions.R`~~ | *(not migrated — `mcmc_functions_SMC.R` is self-contained; confirmed in T1)* |
| `spread/mcmc_functions_SMC.R` | `R/mcmc_functions_smc.R` |
| `spread/sample_triplets_weighted.cpp` | `src/sample_triplets_weighted.cpp` |
| `flammability indices/flammability_indices.R` | `data_prep/flammability_indices.R` |
| `flammability indices/flammability_indices.stan` | `data_prep/flammability_indices.stan` |
| `weather/FWI standardize and aggregate by fortnight.R` | `data_prep/fwi_standardize.R` |
| `weather/FWI fortnight matrix for spread and lengthscale estimation.R` | `data_prep/fwi_fortnight_matrix.R` |
| `weather/FWI projections/standardize and aggregate projections by fortnight (2050 and 2090).R` | `data_prep/fwi_projections.R` |
| `spread/landscapes_preparation.R` | `data_prep/landscapes_preparation.R` |
| `spread/sampling_fire_wise_posteriors_(stage1)_SMC.R` | `spread/stage1_smc.R` |
| `spread/hierarchical model fitting_FWIZ2_SMC.R` | `spread/hierarchical_fit.R` |
| `ignition-escape_FWIZ/ignition-escape_analyses.R` | `ignition_escape/fit.R` |
| `fire regime simulations/fire_regime_simulations_FWIZ.R` | `fire_regime/simulate.R` |
| `fire regime simulations/fire_probability_maps_single-models_FWIZ.R` | `fire_regime/probability_maps.R` |
| `fire regime simulations/plots.R` | `fire_regime/plots.R` |

## Reference B — store folder rename map (copy canonical only)

Copy into `~/Insync/fire-regime-sim-patagonia-store/…`. Only the **canonical** folder is
copied (ignore `_OLD`, other suffix variants, and already-superseded legacy dirs).

| Old relative | New relative in store |
|---|---|
| `data/focal fires data/` | `data/focal_fires/` |
| `data/focal fires data/raw data from GEE/` | `data/focal_fires/raw_gee/` |
| `data/flammability indices/` | `data/flammability_indices/` |
| `data/pnnh_images/`, `data/protected_areas/`, `data/ignition/`, `data/fwi_projections/`, `data/fwi_daily_1998-2022/` | same (already clean) |
| `files/hierarchical_model_FWIZ_SMC/` | `files/hierarchical_model/` |
| `files/posterior_samples_stage1_smc/` | `files/posterior_samples_stage1/` |
| `files/ignition_FWIZ/` | `files/ignition/` |
| `files/fire_regime_simulation_FWIZ/` | `files/fire_regime_simulation/` |
| `files/landscape_flammability/` | same |
| *(external)* `~/Insync/patagonian_fires/patagonian_fires/patagonian_fires.*` | `data/patagonian_fires/` |
| *(external, MISSING)* vegetation-equivalences `.xlsx` | `data/vegetation_equivalences.xlsx` — **TODO #2** |

## Reference C — path-edit rules (apply to every migrated script)

Robust string replacements; verify with grep after each file.

- **Source redirects:**
  `file.path("spread","mcmc_functions_SMC.R")` → `file.path("R","mcmc_functions_smc.R")`;
  `file.path("flammability indices","flammability_indices_functions.R")` → `file.path("R","flammability_indices_functions.R")`;
  `file.path("weather","fortnight_functions.R")` → `file.path("R","fortnight_functions.R")`;
  `sourceCpp(file.path("spread","sample_triplets_weighted.cpp"))` → `…file.path("src",…)`.
- **FireSpread source line:** keep
  `source(file.path("..","FireSpread","tests","testthat","R_spread_functions.R"))` **unchanged**;
  add a comment `# TODO(firespread-export): drop once rast_from_mat/land_cube exported — see docs/migration.md #1`.
- **Data folder tokens:** `"focal fires data"`→`"focal_fires"`; `"raw data from GEE"`→`"raw_gee"`;
  `"flammability indices"` (in *data* paths only) → `"flammability_indices"`;
  `"hierarchical_model_FWIZ_SMC"`→`"hierarchical_model"`; `"hierarchical_model_FWIZ"`→`"hierarchical_model"`
  ⚠️ *(simulate.R reads `_FWIZ`, fit writes `_FWIZ_SMC`; both collapse to `hierarchical_model` —
  confirm simulate.R should use the SMC fit; see TODO #4)*;
  `"posterior_samples_stage1_smc"`→`"posterior_samples_stage1"`; `"ignition_FWIZ"`→`"ignition"`;
  `"fire_regime_simulation_FWIZ"`→`"fire_regime_simulation"`.
- **Hardcoded absolute paths → `R/config.R` or store-relative:**
  WindNinja dir `/home/ivan/windninja_cli_fire_spread_files` → `config$windninja_dir`;
  veg xlsx `/home/ivan/Insync/…/clases de vegetacion y equivalencias.xlsx` → `config$veg_equiv_xlsx`;
  PNNH elev absolute path → `file.path("data","pnnh_images","pnnh_data_spread_elevation_30m.tif")`;
  external patagonian_fires absolute → `file.path("data","patagonian_fires","patagonian_fires.shp")`.

---

## Global verification (end state — T11)

1. `grep -rnE '/home/|_FWIZ|focal fires data' <repo> --include=*.R` → only allowed TODO comments.
2. `grep -rn 'tests.*testthat' <repo> --include=*.R` → only the one FireSpread `source()` line per script.
3. `Rscript -e 'source("R/config.R"); source("R/fortnight_functions.R"); source("R/flammability_indices_functions.R")'` → no error.
4. `Rscript -e 'Rcpp::sourceCpp("src/sample_triplets_weighted.cpp")'` → compiles.
5. Every migrated script `parse()`s; every `file.path("data"/"files", …)` read target resolves
   via the symlinks (`file.exists()` spot-checks).
6. A cheap end-to-end smoke run when convenient — deferred, not required to close the migration.

Originals in `fire_spread/` remain untouched throughout; deletion happens only after the user
confirms the new repo runs.

---

## Deferred TODO register

1. **FireSpread helper export** — move `rast_from_mat()`, `land_cube()` + constants from
   `FireSpread/tests/testthat/R_spread_functions.R` into `FireSpread/R/` (auto-exported by the
   package's `exportPattern("^[[:alpha:]]+")`), `document()` + rebuild; then drop the
   `source(…)` line from the 4 scripts that use it and rely on `library(FireSpread)`. The R
   reference reimplementations in that file (`simulate_fire_r()`, `spread_one_cell_r()`) stay
   test-only — the pipeline never calls them (confirmed by grep).
2. **Vegetation-equivalences `.xlsx` missing** — original WWF/Lara file
   (`Mapa vegetación WWF - Lara et al. 1999/clases de vegetacion y equivalencias.xlsx`) is gone
   from disk; only a different *ciefap* variant exists
   (`Mapa vegetación ciefap/clases de vegetacion y equivalencias_ciefap.xlsx`). User to
   locate/confirm the correct file → copy to `data/vegetation_equivalences.xlsx`. Until then,
   the 4 scripts that read it (`landscapes_preparation.R`, `ignition_escape/fit.R`,
   `data_prep/flammability_indices.R`, `fire_regime/simulate.R`) can't run past that line.
3. **WindNinja dir** — machine-local scratch dir, absent on this machine; only needed to
   *regenerate* wind layers (already baked into the prepared landscape `.rds` files, so not a
   blocker for most of the pipeline).
4. **`fwi_mean_sd_spread.rds` isn't actually produced by the canonical fit** — resolved during
   T3: the `saveRDS()` for it in the canonical `hierarchical model fitting_FWIZ2_SMC.R` (line
   660) is **commented out**, so the file only exists because a legacy non-SMC run
   (`hierarchical model fitting_FWIZ.R`) produced it. `fire_regime/simulate.R` needs it (reads
   it from `hierarchical_model_FWIZ` in the old repo). For the migration, the file was copied
   from the legacy folder into the new `files/hierarchical_model/` alongside the canonical SMC
   outputs (data-only carry-over, no code change). **Real open question for T8/T10:** should
   `hierarchical_fit.R` uncomment that write and regenerate this artifact from the SMC fit
   (statistically more correct — it'd reflect the actual model being used), or is reusing the
   legacy artifact fine because it's just an FWI standardization constant, independent of which
   fit produced it? Needs a decision when those scripts are migrated, not before.
5. **Refactors (post-verification, not part of this migration):**
   - `landscapes_preparation.R` loop → function (build any landscape, not a hard-coded loop).
   - Split `hierarchical_fit.R` monolith — algorithm core vs. inline data manipulation.
   - Extract `recalibrate.R` + `simulator.R` (standalone function) out of `fire_regime/simulate.R`.
   - Fill `docs/*.md` deep detail per module as each is refactored (docs strategy: fill during
     migration/refactor, not up front).
