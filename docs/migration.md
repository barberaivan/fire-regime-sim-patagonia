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
- [x] **T5** — `data_prep/` FWI scripts (`fwi_standardize.R`, `fwi_fortnight_matrix.R` + its
      `fwi_fortnight_matrix_expquad.stan`, `fwi_projections.R`). Path edits: `source(weather/
      fortnight_functions.R)` → `R/fortnight_functions.R` (all 3); external
      `patagonian_fires.shp` absolute path → `data/patagonian_fires/patagonian_fires.shp`;
      `stan_model()` path updated (`fwi_fortnight_matrix.R`).
      - **Surfaced a systemic gap**: T2 only copied the **folders** listed in Reference B —
        it never inventoried `data/`'s many **loose top-level files** (shapefiles + CSVs sitting
        directly in `data/`, not in a subfolder). `fwi_fortnight_matrix.R` needed several of
        these. Rather than patch just this task's own needs, grepped **all remaining canonical
        scripts (T6–T10)** at once for loose-file references, so this gap doesn't get
        rediscovered piecemeal later.
      - Copied for T5 itself: `ignition_points_checked.*`, `ignition_points_checked_with_date.*`
        (its own `writeVector()` is commented out — like TODO #4, it only exists because a
        prior run produced it once; needed as-is), `ignition_points_checked_with_date-fort-
        matrix-fwiz.*`, `ignition_points_checked_with_date-fort-fwiz2.*`,
        `climatic_data_by_fire_fwi-fortnight-{matrix_FWIZ,cumulative_FWIZ,cumulative_FWIZ2}.csv`.
        No filename changes — per the no-file-rename decision, only folder names are cleaned up.
      - Also copied two small items **for T6** (`climatic_data_by_fire_fwi-fortnight-
        cumulative.csv` bare, `climatic_data_by_fire_FWI-wind_corrected.csv`) and one **for T8**
        (`patagonian_fires_spread.*`) — cheap to grab now since already located by the same grep;
        avoids re-deriving this list later. `landscapes_ig-known_non-steppe.rds` (also read by
        `landscapes_preparation.R`) does **not** exist yet anywhere — it's a self-produced cache
        file (written and read by that same script), not a pre-existing input; left for T6.
      - Confirmed `data/fwi_daily_1998-2022/` was already copied **wholesale** in T2 (before
        selective copying started), so `fwi_standardize.R`'s outputs
        (`fwi_daily_..._standardized.tif`, `fwi_fortnights_..._standardized.tif`) were already
        in the store — verified by exact byte-size match against the source folder, no re-copy
        needed.
      - **Verified:** parse() OK for all 3; grep audit clean (no `/home/`, no leftover
        `weather/fortnight_functions.R` source); actually loaded every data dependency through
        the store symlink with `terra` (`apn_limites` 55 features, `patagonian_fires` 238,
        `fwi_fortnights` raster 676 layers — all load); separately compiled
        `fwi_fortnight_matrix_expquad.stan` at its new path — succeeds. Full script runs are
        long-running (fortnight aggregation, ~150-model-member projection loop) and were not
        executed end-to-end — only the data-loading and stan-compile surface was verified,
        consistent with the plan's verification bar.
- [x] **T6** — `data_prep/landscapes_preparation.R`. The biggest script so far. Path edits:
      `gee_dir` → `data/focal_fires/raw_gee`; `"flammability indices"` → `"flammability_indices"`
      (2 sites); `"focal fires data"` → `"focal_fires"` (the landscapes-output write); veg xlsx
      → `config$veg_equiv_xlsx` (+ TODO #2 comment); PNNH elevation absolute path → repo-relative
      `file.path("data","pnnh_images",...)`; `windninja_dir` assignment → `config$windninja_dir`
      (single source of truth, tech debt #5) — this alone doesn't cover it, though: the
      **`system()`/`unlink()` calls had the absolute WindNinja path baked directly into the
      shell-command string**, not routed through the `windninja_dir` variable — 3 separate
      sites (2 active, 1 commented) rewritten to build the path from `windninja_dir` via
      `file.path()`/`paste0()` instead. Added the required
      `# TODO(refactor): loop → function` marker at the landscape-building loop (deferred, item
      #5). Left one already-commented dead-code line (`"focal fires data", "wind ninja
      files", ...`) untouched — inactive, not part of Reference C's scope.
      - **Flagged, not fixed** (behavior-preserving): line 99's `mval <- mean(r)` looks like a
        pre-existing inconsistency — `r` is a SpatRaster, not the numeric vector `v` extracted
        just above it, whereas the equivalent PNNH-section code later in the same script
        correctly uses `mean(v, na.rm = T)`. Possibly a latent bug in the original script; not
        altered since this migration makes no logic changes.
      - Confirmed the `raw_gee` file count is **57**, not "58" as I'd noted from memory earlier
        in this conversation — verified against the old repo directly (also 57, byte-identical
        filenames); my earlier count was off by one (a `find` without `-type f` had included
        the directory itself). No copy gap — T2's copy was already complete.
      - **Verified:** parse() OK; grep audit clean except the one intentionally-untouched dead
        comment; actually sourced both `source()` lines (`R_spread_functions.R` — confirmed
        `land_cube` available; `flammability_indices_functions.R`); loaded the first of the 57
        raw GEE tifs with `terra` (7 named layers); confirmed every other data dependency
        resolves through the store symlink (`file.exists()` — the loose CSVs/shapefile, the
        flammability rds, the PNNH buffered raster + wind ascii grids, both pre-computed PNNH
        landscape outputs, the focal-fire `landscapes/` output dir). Confirmed both blockers
        fire exactly where expected: `config$windninja_dir` doesn't exist (TODO #3) and
        `config$veg_equiv_xlsx` doesn't exist (TODO #2) — the script cannot run past vegetation-
        transform/WindNinja setup until those are resolved, consistent with T4's finding.
- [x] **T7** — `src/sample_triplets_weighted.cpp` (no edits — no filesystem paths inside) +
      `spread/stage1_smc.R`. Path edits: `sourceCpp()` → `src/sample_triplets_weighted.cpp`;
      `data_dir` → `data/focal_fires/landscapes`; `target_dir` → `files/posterior_samples_stage1`
      (3 assignment sites + the loop's partial/full-save/cleanup paths); `"flammability
      indices"` → `"flammability_indices"`; `"focal fires data"` → `"focal_fires"` for
      `fire_size_data.{rds,csv}` (both active reads **and** their paired commented
      compute/cache lines — unlike T6's abandoned dead-code line, these are a live
      compute-once-cache-forever pattern, so leaving the commented half stale would silently
      break a future re-run of the cache-computing block).
      - **Found and resolved a real naming collision** (see TODO #5, new): the script's tail
        end compares its SMC output against `files/posterior_samples_stage1/` (bare name) —
        but in the *old* repo that bare name belonged to a **different, legacy** folder: the
        output of `sampling_fire_wise_posteriors_IMPORTANCE.R`, explicitly marked "not used" in
        `INVENTORY.md` §6. This migration's rename map assigns that same bare name to the
        **SMC** folder instead (dropping the `_smc` suffix, Reference B). Mechanically renaming
        `target_dir_imp` the same way would have made the script silently **compare the SMC
        output against itself** — a real correctness bug, not just a cosmetic one. Confirmed
        via `INVENTORY.md` that the importance-sampling script is legacy/unused, so its data was
        correctly never migrated. Resolution: **commented out both comparison blocks** (~30
        lines) with an explanatory header, rather than inventing a new name for non-canonical,
        non-migrated data or leaving a silently-wrong active reference.
      - **Verified, going beyond parse-checking**: actually compiled
        `sample_triplets_weighted.cpp` at its new path *and ran it* on a real weight vector
        (correct 4×3 output); sourced the FireSpread helper (`land_cube` available);
        `library(FireSpread)` loads with `simulate_fire_compare`/`overlap_spatial` (the
        package functions this script's similarity functions call) both present; every data
        dependency resolves through the store symlink — `landscapes/` (57 files, matching the
        57 focal fires), `fire_size_data.rds`, `flammability_indices.rds`, and
        `posterior_samples_stage1/` (58 files: 57 per-fire `full_samples_history_*.rds` + the
        merged `samples_all_fires.rds` — exactly matching T3's copy). The multi-day SMC
        sampling loop itself was not run end-to-end.
- [x] **T8** — `spread/hierarchical_fit.R`. The ~3000-line monolith. Given the size, skipped a
      full sequential read: did a targeted grep sweep for every path-bearing pattern first
      (including a **string-literal** sweep for the renamed tokens, since `file.path()` calls
      broken across lines hide from a single-line grep — this caught 2 extra
      `"flammability indices"` and 1 extra `"hierarchical_model_FWIZ_SMC"` occurrence my first
      pass missed), read small context windows only at edit sites, and spot-read the two sections
      flagged as risky by the sweep. Edits: `source()`s → `R/mcmc_functions_smc.R` +
      `R/flammability_indices_functions.R`; `"hierarchical_model_FWIZ_SMC"` → `"hierarchical_model"`
      (28 occurrences, single `replace_all`); `"posterior_samples_stage1_smc"` →
      `"posterior_samples_stage1"`; `"flammability indices"` → `"flammability_indices"`;
      `"focal fires data"` → `"focal_fires"`; added the `TODO(migration #1)` marker at the
      FireSpread source line (same pattern as T6/T7).
      - **Checked for a repeat of T7's naming collision** (bare `hierarchical_model` vs.
        `_FWIZ_SMC`) since the very first directory scan (early in this conversation) showed a
        **third** sibling folder, `files/hierarchical_model/` (bare, no suffix) — distinct from
        both `_FWIZ` and `_FWIZ_SMC`. Found two bare-name references at `spreadprobs`
        (`spreadprob_veg_comparison_array.rds`) — but unlike T7, this is **benign**: the array is
        computed fresh by *this same script* and immediately reloaded (a self-contained
        write-then-reread, not a reference to another script's legacy output), and since our
        rename collapses `hierarchical_model_FWIZ_SMC` → `hierarchical_model` anyway, the bare
        name was already coincidentally correct — **no edit needed** for those two lines.
        Confirmed the old bare folder is genuinely messy (many `_FI`/`_thin`/`2`-suffixed
        exploratory artifacts from both this script and the legacy, non-canonical
        `hierarchical model fitting_FWIZ2.R`), but only `spreadprob_veg_comparison_array.rds` is
        actually referenced by the canonical script — copied just that one file (9.8M) into the
        store's `files/hierarchical_model/`, not the rest of the messy folder.
      - Also confirmed `fwi_mean_sd_spread.rds` (TODO #4) is **only** referenced here via the
        already-known dead commented write (line 660) — this script never reads it back, so TODO
        #4's open question is unaffected by this task.
      - **Verified:** parse() OK on the full 3043-line file; grep audit clean; actually sourced
        both `R/` dependencies (`update_ranef` confirmed defined); **all 22** distinct data
        paths this script touches resolve through the store symlinks (`file.exists()` — landscapes,
        fire_size_data, flammability indices + summary, both FWI cumulative CSVs,
        `patagonian_fires_spread.shp`, `apn_limites.shp`, stage-1 posterior samples, the PNNH
        landscape, `landscape_flammability`'s CSV, and all 13 canonical `hierarchical_model/`
        artifacts including the 10 `draws_batch_*.rds` — exact count match). The MCMC/Stan
        fitting itself (originally a multi-day run) was not executed end-to-end.
- [x] **T9** — `ignition_escape/fit.R` (+ its `ignition_model.stan`, `escape_model.stan`,
      `size_model.stan` — all 3 `stan_model()` calls are commented in the canonical script,
      models are loaded from pre-fit `.rds`, but copied the `.stan` sources for reference). Path
      edits: `source()`s → `R/flammability_indices_functions.R` + `R/fortnight_functions.R`; veg
      xlsx → `config$veg_equiv_xlsx` (+ TODO #2); `"flammability indices"` →
      `"flammability_indices"`; `"ignition_FWIZ"` → `"ignition"`; the 3 stan-path comments
      updated to `ignition_escape/*.stan` for consistency.
      - **New external dependency found and resolved**: `igdata_dir <- file.path("..",
        "ignition_data")` — a directory *outside* the repo entirely (sibling to old
        `fire_spread/`), with an explicit comment "Ignition data is not in the fire_spread repo,
        it's not public". Two of its 4 referenced files
        (`Total_focos_NH_nov89-mar21.xlsx`, `base_ampliado_kitzberger_rayos.xlsx`) turned out to
        be **byte-identical duplicates** (confirmed via `md5sum`) of files already in
        `data/ignition/` (copied in T2) — the external folder even had a file literally named
        `..._duplicado?.xlsx` confirming the user's own suspicion. Rather than restructure the
        script's 4 reads individually, kept `igdata_dir` as a single variable pointing at a new
        `data/ignition_data/` store folder holding all 4 needed files (2 xlsx + 2 shapefiles with
        sidecars) — simplest edit (one line), at the cost of ~1.6M of harmless duplication
        (acceptable — not space-limited). Preserved the "not public" intent via an updated
        comment: data now lives in the gitignored store, still never in git.
      - **Found a second pre-existing dangling-variable bug** (distinct from T8's, not
        introduced by migration): the "Fire size model" section uses `sizemod` at 3 sites, but
        its only assignment is commented out and — unlike `igmod`/`escmod`, which both have a
        `readRDS()` fallback right after their commented `sampling()` call — **no fitted-size-
        model `.rds` exists anywhere in the old repo** to load instead (the `ignition/` store
        folder's 6 files are all ignition/escape variants, no size model). This section would
        error in the *old* repo too if run fresh; flagged with an inline `TODO(migration)`
        comment rather than invented a fix.
      - **Verified:** parse() OK; grep audit clean; both `R/` dependencies actually source;
        `config$veg_equiv_xlsx` confirmed missing as expected (TODO #2); all 15 data/code
        dependencies resolve through the store/repo — and beyond `file.exists()`, actually
        **loaded** the two new shapefiles (285 and 23,986 features), the xlsx (284×35), and the
        fitted `ignition_model_samples.rds` (a real `stanfit` object) to confirm they're not just
        present but readable.
- [x] **T10** — `fire_regime/` (`simulate.R` 1583 lines, `probability_maps.R` 321 lines,
      `plots.R` 950 lines). Same grep-sweep-first approach as T8/T9 given the combined size.
      Path edits (all 3, where present): `source()`s → `R/flammability_indices_functions.R` +
      `R/fortnight_functions.R` (+ `R/config.R` newly added to `plots.R`, which had no `source()`
      calls before); veg xlsx → `config$veg_equiv_xlsx` (TODO #2); `"ignition_FWIZ"` →
      `"ignition"`; `"fire_regime_simulation_FWIZ"` → `"fire_regime_simulation"` — **each script
      also hardcoded this literal again at several sites instead of reusing its own
      `export_dir`/`source_dir` variable** (4 extra sites in `simulate.R`, several in `plots.R`),
      caught by grepping the literal token repo-wide rather than trusting one `replace_all` per
      variable definition. External `patagonian_fires.shp` / `ignition_points_pnnh_bari-
      kitzberger.shp` absolute paths (in `plots.R`) → repo-relative.
      - **Important, not-cosmetic finding (new TODO #7):** `simulate.R` and `probability_maps.R`
        both read the fitted spread model from `hierarchical_model_FWIZ` — the **legacy,
        pre-SMC** folder — not the canonical `hierarchical_model_FWIZ_SMC` that
        `spread/hierarchical_fit.R` (T8) actually produces. Confirmed via `md5sum`/size that the
        two `spread_model_samples.rds` are genuinely different files (48.5M legacy vs. 37.7M
        SMC), not a naming accident. Per the behavior-preserving rule, did **not** silently
        repoint this at the SMC output: copied the legacy file into a distinctly-named
        `files/hierarchical_model_legacy_preSMC/` and left both scripts reading from there, with
        a prominent inline `TODO(migration #7)` comment. This is very likely exactly the
        "evaluation" update the user mentioned at the start of this conversation is still
        pending (spread estimation method already changed to SMC; evaluation hasn't caught up)
        — a deliberate decision for the user, not something to change silently during migration.
      - **New external-file addition**: `plots.R` actively reads
        `ignition_points_pnnh_bari-kitzberger.shp` (no `_data` suffix — a different file than the
        one T9 copied) from the same external, non-public `ignition_data` directory. Added it to
        the store's existing `data/ignition_data/` folder alongside T9's files.
      - Left one inert commented-out comparison snippet untouched (`firesmap` in `simulate.R`,
        not a live cache pattern) — same precedent as T6's abandoned WindNinja comment.
      - **Verified:** parse() OK on all 3; grep audit clean; both `R/` dependencies source in
        all 3; **16** distinct data/store paths resolve — including confirming, by size, that
        `hierarchical_model/spread_model_samples.rds` and
        `hierarchical_model_legacy_preSMC/spread_model_samples.rds` really are different files —
        and actually loading the legacy spread model object and the new shapefile (288 features).
- [x] **T11** — Global audit (repo-wide grep + sourcing smoke tests) + close out.
      A repo-wide (not per-task) grep swept up **three real, previously-missed bugs** that
      per-task audits had not caught because they weren't `data`/`files` paths:
      - `ignition_escape/fit.R` had **8 `ggsave()`/figure-path sites** (14 raw substring
        occurrences) still writing to the old `"ignition-escape_FWIZ/figures/..."` — a folder
        that doesn't exist in the new repo at all. Fixed → `"ignition_escape/figures/..."`.
      - `spread/hierarchical_fit.R` had **21 occurrences** writing to
        `"spread/figures_FWIZ2_SMC/..."` — same issue. Fixed → `"spread/figures/..."`.
      - `fire_regime/probability_maps.R` had one **bare-string** (not `file.path()`-split)
        occurrence, `"files/ignition_FWIZ/ignition_prob_relative_raw.rds"`, that a
        quoted-token grep (`"ignition_FWIZ"` as its own argument) doesn't match when the token
        is embedded inside a larger single string. Fixed → `"files/ignition/..."`.
      - Created `spread/figures/` and `ignition_escape/figures/` (with `.gitkeep`) so these
        `ggsave()` calls have somewhere to write, and gitignored their contents (regenerable
        diagnostic output, unlike the curated, committed `manuscript-*/figures/`).
      - **Lesson for future migration-style work:** per-task grepping for the exact rename
        tokens is necessary but not sufficient — a final repo-wide sweep for the *raw substrings*
        (not just quoted-argument patterns) catches sites a script-local review misses,
        especially figure/output paths that don't fit the `data`/`files` mental model.
      - Everything else the repo-wide sweep flagged was an accepted exception: `R/config.R`'s
        one intentional machine-local WindNinja path; loose data **filenames** correctly left
        unrenamed (`*_FWIZ.csv`/`*_FWIZ2.csv`/`*_FWIZ.tiff` — individual files, not folders, per
        the no-file-rename decision); a few harmless historical comments; and the two
        deliberately-inert dead-code snippets (T6's WindNinja comment, T10's `firesmap`).
      - **Final global verification, all pass:**
        1. Repo-wide `/home/|_FWIZ|focal fires data` grep → only the accepted exceptions above.
        2. `tests.*testthat` → exactly one occurrence in each of the 4 scripts that need it
           (`stage1_smc.R`, `landscapes_preparation.R`, `hierarchical_fit.R`, `simulate.R`).
        3. `source("R/config.R"); source("R/fortnight_functions.R");
           source("R/flammability_indices_functions.R")` → no error.
        4. `Rcpp::sourceCpp("src/sample_triplets_weighted.cpp")` → compiles, function callable.
        5. **All 15 R files in the repo** `parse()` cleanly in one sweep (re-checked the 3 files
           touched during this final pass).
      - Updated the "Status" sections in `README.md`, `CLAUDE.md`, and `docs/architecture.md`
        from "skeleton stage" to "migration complete", surfacing TODO #7 and #2 as the two
        things to resolve before running the full pipeline.
      - Did **not** merge `migrate` → `main` as part of this task — see final summary for why.
      (Later merged into `main` in a follow-up turn, per user request.)
- [x] **T12** — Vegetation-source R scripts + raw polygon data (2026-07-09, post-migration
      follow-up). TODO #8's original write-up treated the R-side reclassification scripts as
      "one-time upstream, not migrated" — the user pushed back: the whole vegetation-data story
      should be clean and reproducible in this repo, coupled with its GEE-side counterpart. Went
      back and read the **other 3 R scripts** in the Lara folder that hadn't been read yet
      (`subseting lakes.R`, `vegetation reclassification.R`,
      `vegetation reclassification_dry forests separados.R`, `rasterize vegetation polygons.R`)
      to properly separate canonical from exploratory, rather than migrating everything.
      - **Found a genuine canonical/exploratory split**, confirmed two independent ways: (1) a
        repo-wide grep across both `fire_spread-gee` and this repo found their outputs
        (`vegetation_valdivian_img*`, `*reclassified*`, `*dryforest2*`, `Kitz22`) referenced
        **nowhere downstream** — only `vegetation_valdivian_raw` (the *raw*, non-reclassified
        merge) is actually used by the GEE mosaic script; (2) the 2 canonical scripts use only
        `terra` (still maintained), while the 4 excluded ones use `library(rgeos); library(rgdal)`
        — **not installed on this machine** (both packages were retired from CRAN in 2023) — so
        the excluded scripts couldn't even run here as-is. The GEE mosaic does its own
        `GRID_CODE`→`cnum1` remap directly (matching the Lara xlsx's `Sheet3`), independent of
        the excluded scripts' string-based class labels.
      - **Migrated the 2 canonical scripts**: `merging all shapefiles in one.R` →
        `data_prep/vegetation_lara_merge.R` (merges `norte/centro/sur` regional pieces →
        `vegetation_map_lara1999.shp`, the GEE `vegetation_valdivian_raw` asset's source);
        `exploring_layers.R` → `data_prep/vegetation_ciefap_merge.R` (merges ciefap's NQN/RN/CH
        2013 provincial shapefiles, joins the equivalence table by `Ley_N3` →
        `ciefap_2016_NQN-RN-CH_reclass.shp`, the GEE `vegetation_ciefap_2016_NQN-RN-CH_reclass`
        asset's source). Added `config$veg_equiv_xlsx_ciefap` (sheet 1, keyed by `Ley_N3` — a
        different sheet/join than `veg_equiv_xlsx`'s `Sheet2`). Added `overwrite = TRUE` to both
        `writeVector()` calls since their outputs now pre-exist in the store (needed for
        reproducible re-runs; the originals lacked this and would error on re-run).
      - **Copied the canonical inputs + outputs into the store**: `data/vegetation_lara/`
        (`norte/centro/sur.*` + `vegetation_map_lara1999.*`, 207M) and `data/vegetation_ciefap/`
        (`NQN_2013/`, `RN_2013/`, `CH_2013/` — only the 2013 vintage the script reads, not 2017
        or the untouched SC/TF `.rar` archives — + `ciefap_2016_NQN-RN-CH_reclass.*`, 2.1G).
      - **Left the 4 excluded scripts in their original Insync location** (not migrated) —
        `subseting lakes.R`, both `vegetation reclassification*.R` variants, and
        `rasterize vegetation polygons.R` — confirmed exploratory/superseded, unreferenced
        downstream, and reliant on retired packages.
      - **Verified beyond parse-checking**: actually **ran both scripts end-to-end** (not just
        checked they parse) — `vegetation_lara_merge.R` merged 15,523 polygons and reprojected
        to WGS84; `vegetation_ciefap_merge.R` merged 157,145 polygons across the 3 provinces,
        produced a 142-row area-by-class summary (matching the equivalence table's `Sheet1` row
        count), and confirmed all 11 expected vegetation categories present in the joined
        `class1` column.
      - Updated `CLAUDE.md`'s GEE section, `docs/data-prep.md`, and this entry to reflect the
        full, now-reproducible chain: Lara/ciefap raw data → R merge/reclass (this repo) → GEE
        mosaic + pre-2014 patching (`fire_spread-gee`) → per-fire/PNNH raw exports (already in
        this repo's store).

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
| `weather/FWI model cumulative expquad_simpler.stan` | `data_prep/fwi_fortnight_matrix_expquad.stan` |
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

1. **FireSpread helper export — RESOLVED (2026-07-09).** Moved `land_cube()`, `rast_from_mat()`,
   and the shared constants (`distances`, `angles`, `moves`, `elev`, `wdir`, `wspeed`, `b_slope`,
   `b_wind`) from `FireSpread/tests/testthat/R_spread_functions.R` into a new
   `FireSpread/R/spread_helpers.R`, using `terra::`-qualified calls so the functions work via
   `library(FireSpread)` alone (no separate `library(terra)` needed). Auto-exported by the
   package's existing `exportPattern("^[[:alpha:]]+")` — **did not** run `devtools::document()`,
   since `NAMESPACE` is hand-maintained (no roxygen header) and regenerating it risked wiping the
   existing `useDynLib`/`importFrom(Rcpp, evalCpp)` lines; roxygen-style doc comments were added
   to the new file for readability but are not processed into `man/`. Bumped `DESCRIPTION` to
   1.4, reinstalled via `R CMD INSTALL .`, verified `land_cube`/`rast_from_mat` load and run
   correctly via `library(FireSpread)`. Dropped the `source(file.path("..", "FireSpread",
   "tests", "testthat", "R_spread_functions.R"))` line from all 4 scripts that used it
   (`landscapes_preparation.R`, `stage1_smc.R`, `hierarchical_fit.R`, `simulate.R`) — added
   `library(FireSpread)` to `landscapes_preparation.R`, which didn't already have it; the other
   3 already did. `tests/testthat/R_spread_functions.R` was left untouched (still defines its
   own copy for the package's own tests, plus the R reference reimplementations
   `simulate_fire_r()`/`spread_one_cell_r()`, which stay test-only — the pipeline never calls
   them, confirmed by grep) — the small duplication between it and the new package file is
   harmless (test-local definitions simply shadow the package version during tests).
   Verified: all 4 scripts still parse; `library(FireSpread)` alone provides both functions in
   each script's actual import context.
2. **Vegetation-equivalences `.xlsx` — RESOLVED (2026-07-09).** The original WWF/Lara file
   (`Mapa vegetación WWF - Lara et al. 1999/clases de vegetacion y equivalencias.xlsx`) was
   never actually lost — it wasn't synced to this machine's Insync, but the user found it in
   Google Drive, downloaded it, and it's now at `data/vegetation_equivalences.xlsx` in the
   store (`config$veg_equiv_xlsx`). Verified: 3 sheets — `Sheet2` (the one every script reads)
   has exactly the schema all 6 consuming scripts expect (`cnum1, class1, cnum2, class2`, 11
   rows, the same 6 category names used throughout the codebase); `Sheet1` is a richer
   `GRID_CODE`→class legend crosswalk with the author's own provenance notes (not read by any
   script); `Sheet3` is an alternate wide `GRID_CODE`→`cnum1` lookup (also unread). All 6
   consuming scripts (`landscapes_preparation.R`, `ignition_escape/fit.R`,
   `data_prep/flammability_indices.R`, `fire_regime/simulate.R`, `probability_maps.R`, `plots.R`)
   re-verified: parse OK, and the exact `readxl::read_excel(config$veg_equiv_xlsx, sheet =
   "Sheet2")` call confirmed to load correctly (11×4, matching values).
   - **The "ciefap" file is a separate, legitimate input, not a substitute** — the user
     confirmed both the Lara and ciefap equivalence tables were used, for two *different* source
     vegetation maps. A repo-wide grep found **zero** references to "ciefap" anywhere in this
     repo's code, so it's not consumed by anything migrated here — most likely used in the
     separate GEE JS repo (`mapbiomas`-style upstream raw-layer prep; see `CLAUDE.md`'s "GEE Code
     Editor scripts" section for precedent, though this specific case predates that convention).
     Kept for provenance at `data/vegetation_equivalences_ciefap.xlsx`; not wired into
     `config$`, since nothing here reads it. If a future upstream step needs it, add a second
     `config$` entry then.
3. **WindNinja dir** — machine-local scratch dir, absent on this machine; only needed to
   *regenerate* wind layers (already baked into the prepared landscape `.rds` files, so not a
   blocker for most of the pipeline). All uses now derive from `config$windninja_dir`
   (`R/config.R`), including the 3 `system()`/`unlink()` shell-command strings in
   `landscapes_preparation.R` that used to hardcode the absolute path directly (fixed in T6).
   **Install feasibility checked (2026-07-09):** not available via `apt` or `snap`; checked the
   official GitHub releases (`firelab/windninja`) via the API — the latest release (3.12.2) has
   **zero attached binary assets**, so there's no prebuilt Linux package at all. Installing would
   mean building from source (GDAL/NetCDF/Boost/Qt dependency chain) — a genuinely heavy,
   multi-hour, failure-prone undertaking not appropriate to attempt without the user's explicit
   go-ahead, especially since it isn't currently blocking anything. Only matters if new focal
   fires are added or the PNNH landscape needs rebuilding from scratch — not needed yet.
4. **`fwi_mean_sd_spread.rds` — RESOLVED (2026-07-09).** The canonical `hierarchical_fit.R`'s
   `saveRDS()` for this file was commented out (so it only existed via a legacy non-SMC run's
   copy — see T3). Traced what actually produces the two numbers: `fwi_mean`/`fwi_sd` are just
   `mean()`/`sd()` of each fire's FWI value, computed from the climate CSV + fire-ID labels
   *before* any MCMC/Stan fitting — not derived from posterior draws at all, so they cannot
   differ between the legacy and SMC fits. Verified this empirically: independently recomputed
   both numbers from `data/climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ2.csv` +
   `files/posterior_samples_stage1/samples_all_fires.rds` (for fire-ID labels) and got values
   **byte-identical** to the legacy copy already in the store (`fwi_mean = 0.8636725`,
   `fwi_sd = 0.9051262`). So the existing file's *value* was already correct — the only real gap
   was provenance (the canonical script couldn't reproduce its own output). Uncommented the
   `saveRDS()` in `hierarchical_fit.R` so a future full re-run regenerates it correctly; did not
   rewrite the existing (already-correct) file in the store.
5. **`posterior_samples_stage1` name collision — resolved during T7.** In the old repo, the
   bare `files/posterior_samples_stage1/` belonged to the **legacy** importance-sampling stage-1
   output (`sampling_fire_wise_posteriors_IMPORTANCE.R`, "not used" per this doc's history and
   the old `INVENTORY.md` §6) — a *different* folder from `posterior_samples_stage1_smc/`
   (canonical). This migration's clean-rename drops the `_smc` suffix, so the canonical SMC
   folder now also has the bare name — colliding with the legacy folder's old identity. Since
   the legacy data was correctly never migrated (non-canonical), `stage1_smc.R`'s tail-end
   comparison against it (comparing SMC vs. importance-sampling overlap) was **commented out**
   rather than silently pointed at the SMC folder itself (which would have made it compare the
   SMC output against itself — a real bug, not just stale code). Re-derive from the archived old
   repo if that comparison is ever needed again.
6. **`ignition_escape/fit.R`'s "Fire size model" section can't run from a fresh session** —
   `sizemod` (used at 3 sites) has no active assignment (its `sampling()` call is commented) and
   no fitted `.rds` exists anywhere to load instead, unlike the ignition/escape models in the
   same script. Pre-existing in the old repo, not introduced by migration; looks like an
   abandoned/exploratory side-analysis, not a canonical output. Flagged in-code; needs either a
   real fit + `saveRDS`/`readRDS` pair, or removal, if this section is ever needed.
7. **`fire_regime/simulate.R` and `probability_maps.R` — repointed to the canonical SMC spread
   model; NOT yet re-validated.** Originally both read `spread_model_samples.rds` from
   `files/hierarchical_model_legacy_preSMC/` (the pre-SMC fit, kept during T10 to preserve exact
   old behavior — confirmed genuinely different from the SMC fit: 48.5M vs 37.7M, different
   dates, via `md5sum`/size). Per user decision (2026-07-09): the spread-parameter *estimation*
   method has already moved to SMC (post-PhD work); the regime *evaluation* scripts (these two)
   are the ones still pending an update, and that update may not happen for months — so the read
   was **repointed now** to `files/hierarchical_model/spread_model_samples.rds` (the canonical
   SMC fit), rather than left on the legacy file indefinitely.
   - **Verified safe to swap structurally**: the legacy and SMC `spread_model_samples.rds` have
     identical `names()` (`fixef, rho, ranef, steps, stepsU`), identical dimensions, and
     identical dimnames (parameter names) — only the posterior *values* differ. Downstream code
     that indexes into `smod$fixef`, `smod$ranef`, etc. is therefore unaffected structurally by
     the swap.
   - **NOT tested beyond this**: neither script has been re-run end-to-end against the new
     parameters — the regime simulation and probability-map outputs currently in the store were
     generated with the *old* (pre-SMC) parameters and have not been regenerated. Treat any
     existing `files/fire_regime_simulation/` or probability-map output as stale until these
     scripts are actually re-run.
   - **Cleanup deferred**: `files/hierarchical_model_legacy_preSMC/` should be deleted once the
     re-run/validation above is done and confirmed working — not before, in case a rollback is
     needed.
   - **Re-run scale, assessed 2026-07-09 (not launched):** the original `fire_regime_simulation/`
     output is 180 batch files spanning **2025-01-09 to 2025-01-12 (~2.5 days wall-clock)** —
     `simulate.R` runs `nsim <- 1000` fire-year simulations per scenario-period, in batches of
     100, via `foreach`/`registerDoMC`, across 9 scenario-periods (modern + 2040/2090 × 4 SSP
     scenarios). This is a multi-day job, not something to launch without deciding on core count
     and scope first — exactly the class of long-running script `CLAUDE.md`'s "Running long
     scripts" convention says belongs in `tmux`, started deliberately. Did not attempt a
     stripped-down smoke test (e.g. `nsim=2`) either: extracting a minimal runnable slice from
     the 1583-line script without reading it in full risks a false signal either way — a
     mistake in the extraction misread as "the SMC repoint is broken," or the reverse. **When
     ready:** manually try a small `nsim` (2–3) for one scenario first, in `tmux`, before
     committing to the full re-run.
8. **Regional vegetation raster — RESOLVED (2026-07-09).** Full process now understood, across
   two repos:
   - **R-side reclassification** (found earlier the same day): `vegetation reclassification.R`
     (`~/Insync/Mapa vegetación WWF - Lara et al. 1999/`) reclassifies the Lara et al. 1999
     polygons into 8 classes; `exploring_layers.R` (`~/Insync/Mapa vegetación ciefap/`) merges
     ciefap's regional shapefiles and joins the `class1/class2` table. Both end with "upload to
     GEE" — correctly predicted the mosaic step itself was GEE-side.
   - **GEE-side mosaic + pre-2014 patching** (found via the GEE Code Editor repo the user
     provided): cloned to `~/dev/fire_spread-gee/` (remote
     `https://earthengine.googlesource.com/users/Ivan_Barbera/fire_spread`; see `CLAUDE.md`'s new
     "GEE Code Editor scripts" section). The script `Vegetation type image - CIEFAP WWF merge`
     contains the exact logic:
     1. Builds `burn_year_earliest` from the fire-perimeter collection, derives `bef14` — a
        binary mask of pixels burned before 2014 (the year the ciefap imagery was taken).
     2. Recodes the raw Lara `GRID_CODE` image via an explicit `remap()` (the same `cnum1`
        mapping found in the Lara xlsx's `Sheet3`) and rasterizes the already-reclassified
        ciefap vector.
     3. **The patch**: `veg_im_ciefap.updateMask(bef14.eq(0))` masks ciefap OUT wherever
        burned before 2014; `ImageCollection([veg_im_wwf, veg_im_ciefap_ok]).mosaic()` stacks
        Lara as the base layer with ciefap on top — GEE's `mosaic()` falls through to the layer
        below wherever the top layer is masked, so pre-2014-burned pixels get Lara's cover
        instead of ciefap's. Exactly matches the user's memory.
     4. Final asset: `projects/ivanbarbera-001/assets/vegetation_ciefap_wwf3` (a GEE-hosted
        asset, not a local file — hence unfindable by filesystem search). Confirmed downstream:
        `Landscapes export`, `Landscapes export BalconGut with distance` (per-fire raw exports),
        and `Export data for ignition model and fire regime simulation (PNNH)` all reference
        this asset (under two equivalent names:
        `users/IvanBarbera/Fire_spread/vegetation_ciefap_wwf` and
        `projects/ivanbarbera-001/assets/vegetation_ciefap_wwf_imported`) as their vegetation
        source — this is exactly what produces the `veg`/`GRID_CODE` layer already baked into
        every focal fire's raw GEE export and the PNNH landscape rasters already in the store.
   - **Not migrated further** — per the `mapbiomas-arg-fire`/`mapbiomas-arg-fire-gee` precedent
     (`CLAUDE.md`), GEE JS code stays in its own separate repo, not copied into this one. The two
     R reclassification scripts remain in their original Insync folders (upstream, one-time
     inputs to GEE assets, not part of the recurring pipeline) — not migrated here either, since
     nothing in this repo re-runs them.
9. **Non-public Bari-Kitzberger data risks exposure via a future store share link — UNSOLVED,
   left as an open decision on purpose (user, 2026-07-09).** `data/ignition_data/`
   (`ignition_points_pnnh_bari-kitzberger*`, `population_points_pnnh_bari-kitzberger_data.*`,
   `Total_focos_NH_nov89-mar21.xlsx`, `base_ampliado_kitzberger_rayos.xlsx`) is explicitly
   non-public — the original script's own comment says so ("Ignition data is not in the
   fire_spread repo, it's not public"), which is why the *old* repo kept it physically outside
   the repo entirely, at a separate sibling path (`../ignition_data`), never bundled with
   anything shared.
   - **The problem this migration (re)introduced:** T9 copied that data *into*
     `fire-regime-sim-patagonia-store/data/ignition_data/` for convenience — but the store as a
     whole is exactly the kind of folder that gets a single shared Google Drive link handed to
     collaborators (see the `mapbiomas-arg-fire` precedent in `~/Insync/Claude/repo-store-
     structure.md` and this repo's own `README.md` "Getting started"). If the *whole store*
     is ever shared that way, this non-public data goes out with it.
   - **Not solved here on purpose** — this needs the user's own decision, not a unilateral
     restructuring. Two directions worth weighing when the user gets to it:
     1. **Physically separate it again**, mirroring the old repo's own solution: a second,
        never-shared location (e.g. a sibling `fire-regime-sim-patagonia-store-private/`),
        symlinked in by `setup.sh` via a second, optional argument — the most robust guarantee,
        since a share link simply can't reach a folder it was never given.
     2. **Restrict the subfolder's permissions within Google Drive** (Drive supports overriding
        a specific subfolder's sharing even when its parent is shared) — keeps everything in one
        physical place, but is easier to misconfigure or forget after future restructuring.
   - No files were moved and `setup.sh` was not changed — this is a documentation-only entry,
     deliberately left for the user to resolve.
10. **Refactors (post-verification, not part of this migration):**
   - `landscapes_preparation.R` loop → function (build any landscape, not a hard-coded loop).
   - Split `hierarchical_fit.R` monolith — algorithm core vs. inline data manipulation.
   - Extract `recalibrate.R` + `simulator.R` (standalone function) out of `fire_regime/simulate.R`.
   - Fill `docs/*.md` deep detail per module as each is refactored (docs strategy: fill during
     migration/refactor, not up front).
