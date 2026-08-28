# Roadmap — current state & next steps

**This is a living document — edit it in place.** Unlike `docs/migration.md` (an append-only
historical changelog of the PhD-repo migration, finished and mostly closed out), this file
answers one question when you come back after a gap: *what's the current state, and what's the
next thing to do?* Update the two sections below as work progresses; don't accumulate history
here — that's what git log and `docs/migration.md` are for.

**Last updated:** 2026-08-28

**Open to-dos live in `docs/migration.md`'s TODO register** (items #6, #7, #9 are still
unresolved — summarized under "Open items" below, full detail in that file).

---

## Current state

- The repo migration (T0–T12) is done; code and heavy data live here and in the store, not in
  the old PhD repo. See `docs/migration.md` for the full log.
- `FireSpread` now properly exports `land_cube()`/`rast_from_mat()` (no more sourcing from
  `tests/testthat/`).
- WindNinja is built from source and installed (`~/.local/bin/WindNinja_cli`, on `PATH`; source
  tree at `~/.local/src/windninja`) — see `docs/migration.md` TODO #3 for the build story and
  gotchas (`NINJA_QTGUI` not `NINJA_GUI`, `momentum_flag` incompatible with a NINJAFOAM-off
  build, never point a test run at a real elevation file in the store).
- The vegetation-source pipeline (Lara + ciefap merges, R-side + GEE-side mosaic) is fully
  traced and documented — `docs/migration.md` TODO #8, `CLAUDE.md`'s "GEE Code Editor scripts"
  section.
- **Landscape preparation is refactored and split by purpose** (2026-08-19). The three
  near-duplicate blocks became one shared recipe, `R/landscape_functions.R`, driven by two
  scripts: `data_prep/landscapes_preparation.R` (fire-wise landscapes, for fitting) and
  `data_prep/landscapes_simulation.R` (study-area tiles + PNNH, for simulating new fires).
  Verified to reproduce the saved landscapes bit-for-bit — see `docs/data-prep.md`.
- **The study-area tiles are exported and built** (2026-08-20). `Landscapes export for
  simulation (study area tiles)` (in `~/dev/fire_spread-gee/`) cut the Barberá et al. 2025
  study area into K = 4 latitudinal rectangles, each fitted inside the region where the NDVI
  and vegetation assets have data. They do **not** overlap (the 10 km buffer and its ~20 km
  overlap are gone, and so is the R twin `study_area_tiles()`) — a fire that reaches a tile's
  border is cut short by it, which the simulation still has to handle. The four exports are in
  `data/simulation_landscapes/raw_gee/`, and `data_prep/landscapes_simulation.R` has been run
  over them end to end: rectangles → `study_area_tiles.shp`, WindNinja wind fields →
  `data/simulation_landscapes/wind/`, landscapes → `data/simulation_landscapes/landscapes/
  study_area_tile_{1..4}.rds` (303-443 MB each on disk, ~0.7-1.0 GB in memory).

  | tile | size | Mpix | burnable | NA-masked |
  |------|------|------|----------|-----------|
  | 1 | 126 x 158 km | 22.2 | 90.5 % | 0.27 % |
  | 2 | 106 x 170 km | 20.1 | 81.6 % | 0.38 % |
  | 3 | 122 x 142 km | 19.2 | 77.1 % | 0.92 % |
  | 4 | 112 x 132 km | 16.4 | 84.5 % | 0.47 % |

  The tiles cover **99.1 %** of the study area, and the per-tile circular mean of the mapped
  fires' wind direction (291, 292, 288, 291) confirms the single fixed 293 degrees used for all
  four wind fields. No tile came close to the 2 % NA warning threshold.

  The tiles are deliberately **broader than the study area** — 70,158 km2 of tile against
  29,158 km2 of study area, so roughly 2-3x. Nothing is clipped or NA'd at the study-area
  boundary: the GEE script uses `study_area` only as a map layer for drawing the rectangles by
  eye, and the burnable fraction outside the study area matches the fraction inside (90.4 vs
  90.6 %, 82.3 vs 81.0 %, 76.5 vs 77.7 %, 86.1 vs 81.0 %). Fires can therefore spread past the
  study area; they are stopped only by a tile's own border. `landscapes_simulation.R`'s
  `terra::intersect()` line is a one-way coverage *check* (is any of the study area untiled?),
  not a crop.
- **The spread model's validation is designed, implemented, and both sides are run**
  (2026-08-28). Design in `docs/spread.md` → *Stage 3 — validation*;
  `manuscript-spread/journal_choose.md` updated to match. Code:
  `R/spread_validation_functions.R`, `spread/validation_ignition_cells.R` (run — output in
  `files/spread_validation/ignition_cells.rds`), `spread/validation_simulate.R` (run — 64,836
  simulated fires), `spread/validation_observed.R` (run — 241 observed fires). Only the analysis
  and figures (step D below) are left.

  - **All 185 GEE export tasks succeeded** — the 184 fires with unknown ignition point, plus the
    `2015_41` focal smoke test — and all 184 are downloaded and built into reduced landscapes
    (step B below). Two interchangeable drivers live in `~/dev/fire_spread-gee/`: the Code Editor
    script and `python/export_signature_landscapes.py`. Use the Python one for batches — the Code
    Editor's "run all tasks" plug-in gave up after 129 of 184 (all 129 succeeded, so it was a
    transport failure, not a code one) and the Python driver is re-runnable, skipping fires whose
    task already exists.
  - **The GEE assets migrated** to `projects/ivanbarbera-001/assets/` and the scripts follow the
    tiles script's paths. Verified live: the migrated NDVI and vegetation rasters are
    pixel-identical to the legacy ones at 30 m, band order unchanged, and the legacy
    `patagonian_fires_spread` still resolves with its 241 features (it has no cloud-project twin
    — `projects/.../patagonian_fires` has only 238).
  - **Headline finding, already solid from the pilot:** the simulator cannot reproduce fire
    shape. Observed fires are elongated and wind-aligned, simulated ones are round and randomly
    oriented, and this is structural rather than a tuning or coding failure — see
    `docs/spread.md` → *Why the model cannot make an elongated fire*.

- **WindNinja outputs have drifted from the saved landscapes.** The PNNH `.asc` files were
  regenerated on 2026-07-09 by the locally built WindNinja and no longer match
  `pnnh_spread_landscape*.rds`; the focal fires' scratch dir is empty entirely. Statistically the
  fields agree, per-cell they don't. Detail and consequences in `docs/data-prep.md`
  → "`wind_sd` is frozen".

### Open items carried from the migration (not yet resolved)

- **TODO #6** (`docs/migration.md`) — the ignition-escape "fire size" model can't run from a
  fresh session (dangling `sizemod`); confirmed abandoned/exploratory, not touched per explicit
  instruction not to work on ignition-escape right now.
- **TODO #7** — `fire_regime/simulate.R`/`probability_maps.R` read the canonical SMC-fitted
  spread model now, but haven't been re-run against it; existing regime-simulation/probability-map
  outputs are stale until they are. This is a multi-day job (~2.5 days last time) — launch in
  `tmux` with a small `nsim` smoke test first.
- **TODO #9** — Bari-Kitzberger non-public data currently sits inside the shareable store;
  deliberately left as an open decision (physically re-separate vs. restrict Drive subfolder
  permissions). Decide before sharing the store with anyone.

---

## Next steps

**Where the spread paper's validation stands (2026-08-28).** The design is settled and written
up (`docs/spread.md` → *Stage 3 — validation*), and **both sides of the comparison are computed
and on disk**. All that is left is D: the analysis and its figures.

```
   simulated side                     observed side
   ──────────────                     ─────────────
   [A] full run ─── DONE ✅           57 focal fires ─── already on disk
       64,836 fires, 15 min           184 others ─── exported + downloaded ✅
                                            │
                                            ▼
                                      [B] R loop → landscapes ─── DONE ✅
                                            │
                                            ▼
                                      [C] observed signature ─── DONE ✅
                                          241 fires, all converged
                    └────────────┬──────────┘
                                 ▼
                          [D] analysis + figures
```

### A. Run the full simulation — **DONE 2026-08-21**

`files/spread_validation/simulated_fires.rds` (12.8 MB) holds **64,836 fires ≥ 10 ha** from
148,649 proposals — 43.6 % acceptance, so the single pass overshot `n_target = 50 000` and no
second pass was needed. **15 minutes on 14 cores**, not the 1–1.5 h estimated. 83,813 proposals
fell below the 10 ha threshold (52.5 % of them burned one cell); their sizes are in `small_sizes`.
Log kept at `files/spread_validation/run.log`. To reproduce:

```bash
tmux new-session -d -s spread_sim -c ~/dev/fire-regime-sim-patagonia \
  "stdbuf -oL -eL Rscript spread/validation_simulate.R 2>&1 | tee files/spread_validation/run.log; exec bash"
```

Health of the output: every conditional logit that was fitted converged, and only **14 fires of
64,836** (0.02 %) have an NA signature, where `donor_strata()` found nothing to fit. Fires split
13,987 / 18,348 / 19,941 / 12,560 across tiles 1–4. Sizes run 12.8 ha at the 5th percentile to
454,279 ha at the maximum, median 151 ha.

**Both elongations are in the output** (see `docs/spread.md` → *The analyses* §2):
direction-free `elongation`, which is all the observed side can supply, and `elong_wind` along
each fire's own terrain-steered mean wind. The covariance entries `cov_ee`/`cov_nn`/`cov_en` are
saved too, so `elongation_along()` can measure against any other axis without re-running — the
fixed 293° column below was produced that way, post hoc.

| size class | n | median area | `elongation` | `elong_wind` | vs fixed 293° |
|---|---|---|---|---|---|
| 10–100 ha | 28,069 | 30 ha | 1.56 | 0.99 | 1.00 |
| 100–1000 ha | 21,313 | 287 ha | 1.47 | 0.98 | 0.97 |
| > 1000 ha | 15,454 | 3,258 ha | 1.47 | 0.94 | 0.93 |

**This sharpens the headline result.** The simulated fires are not merely rounder than observed
ones — along the wind they are not elongated *at all*: median `elong_wind` 0.976 overall, and it
*falls* as fires get bigger, so the largest ones are slightly stretched **across** the wind.
Orientation agrees: 27.8 % fall within 30° of the 113/293 axis, marginally *below* the 33.3 %
a uniformly random orientation would give. The wind term is not producing a head fire. Full
argument in `docs/spread.md` → *Why the model cannot make an elongated fire*.

Terrain steering is real and worth keeping in mind for D: `wdir` averaged over a fire's burned
cells has a 5–95 % range of **277–311°** around the 293° the tiles were driven with, though the
per-fire fields are highly coherent (median `rbar` 0.99).

One thing for D to check rather than assume: the simulated signature medians are `b_vfi`
1.39 / 1.42 / 1.74 by size class and `b_tfi` −2.45 / −0.57 / −0.18. Against the observed medians
C actually measured (`b_vfi` 2.09 / 0.44 / 0.84, `b_tfi` 0.66 / 0.47 / 1.21 over all 241), the
`vfi` gap is much smaller than the old unsaved pilot suggested, while `b_tfi` still has the
wrong sign for small and mid-sized fires. Do the size-conditioned comparison properly rather
than reading the gap off medians.

### B. Build the 184 reduced landscapes — **DONE 2026-08-28**

The exports, the download and the R loop are all done. `data/signature_landscapes/landscapes/`
holds **184 `.rds`**, 25 MB in total, written in seconds by the `do_signature` stage at the end
of `data_prep/landscapes_preparation.R`:

```
data/signature_landscapes/raw_gee/      <- the 184 .tif                   DONE
data/signature_landscapes/smoke_test/   <- fire_signature_raw_2015_41.tif, the focal
                                           smoke test; diff it against
                                           data/focal_fires/raw_gee/fire_data_raw_2015_41.tif
                                           if the vintages are ever doubted again. Not input.
data/signature_landscapes/landscapes/   <- the 184 .rds                   DONE
```

Each `.rds` is a list with `landscape` (a `veg`/`vfi`/`tfi` array), `burned_layer`,
`burned_ids` (0-indexed, as in `data/focal_fires/`), `counts_veg`, `counts_veg_available` and
`fire_id`.

How the two consistency requirements were met:

- **Crosswalk** — the loop reuses the `dveg <- veg_crosswalk("forest")` the focal loop builds
  (urban → wet forest), not the `"nonburnable"` convention of the simulation tiles.
- **NDVI detrending** — `ndvi_prev` is detrended to its 2022 equivalent with `ndvi_detrend()`,
  at `year - 1` where `year` is the fire's property in `patagonian_fires_spread.shp`. That is
  the same property the GEE export selected band `b_<year - 1>` with, and it equals the
  July–June `fire_year` the focal loop derives from the fire dates for all 57 focal fires.

One change was needed in the shared recipe: `build_landscape()` now accepts **`wind = NULL`**
and then emits the reduced layer set `land_names_reduced` = `veg`/`vfi`/`tfi` — no wind
projection, and no `elevation` layer either (it exists only for the engine's directional slope
term, and a cell with missing elevation already loses its `tfi`, so the NA mask is unchanged).
The full-landscape path is untouched.

Two smaller edits in the same script: the stage toggles now include `do_signature`, and the
exploratory veg-abundance tail is behind `do_veg_summary <- FALSE` so that an `Rscript` run of
the file does not re-read all 57 rasters and draw plots.

One fire, `2014_1010415027`, trips the 2 % NA-mask warning at 3.3 % — the only warning in the
run.

> A warning for anyone re-running the export: `--status` in that script collapses tasks by
> description and reports the best state per name, so a **re-submission of an already-finished
> batch looks like "185 SUCCEEDED" while 122 duplicates sit in the queue**. On 2026-08-28 a
> second full wave was launched by mistake and had to be cancelled by hand. Check
> `ee.data.listOperations()` for live states before resubmitting anything.

### C. Observed signature and shape — **DONE 2026-08-28**

`spread/validation_observed.R` runs `donor_strata()` + `edge_clogit()` and `fire_shape()` over
the 57 focal landscapes and the 184 reduced ones — **241 fires, 1.4 minutes** — and saves one
row per fire to `files/spread_validation/observed_signature.rds` and `observed_shape.rds`. Both
tables carry `fire_id`, `source` (focal / signature), `area_ha` and the fire's FWI
(`fwi_fort_expquad`, available for 233 of the 241; the 8 without it are fires the climatic table
never covered), so D's FWI-stratified test can read them directly.

**All 241 fires were fitted and all 241 converged.** `donor_strata()` never returned NULL — even
the smallest fire in the record yields 60 usable strata — so, unlike the simulated side's 14 NA
fires, the observed side has no missing signature at all.

**The rerun disagrees with the numbers that were quoted around the repo, and the rerun wins.**
`docs/spread.md` has been updated; the headline comparison:

| 57 focal fires | quoted | measured |
|---|---|---|
| `vfi` median | 0.578 | **0.882** |
| `vfi` frac > 0 | 0.86 | **0.84** |
| `tfi` median | 1.881 | **0.624** |
| `tfi` frac > 0 | 0.65 | **0.53** |

`vfi` reproduces in the ballpark; `tfi` does not — the measured median is a third of the quoted
one and barely half the fires are positive. The old per-size-class figures are not reproduced
either. The difference is not the donor subsampling: re-running with a different seed moves the
focal `vfi` median 0.882 → 0.828 and leaves `tfi` at 0.624 exactly.

Over all 241 fires: `vfi` median 1.121 (74 % > 0), `tfi` median 0.698 (56 % > 0), with the
per-size-class breakdown in `docs/spread.md`. `tfi` strengthens with fire size; `vfi` does not —
it is largest among fires under 100 ha, where the 146 small fires have few strata and wide,
noisy per-fire estimates. Read the small-fire end as noise-dominated, not as a stronger signal.

The **shape** side reproduces what was quoted: median `elongation` 2.12 over all 241 (2.47 over
the 57 focal), and 51 % of fires oriented within 30° of the 113/293° axis — against the
simulated 1.50 and 27.8 %. 61 % of the 241 are more elongated than the model's 1.9 ceiling,
rising to 78 % above 1000 ha. `observed_shape.rds` also carries `elong_fixed`, elongation along
the fixed 293°, which is the column directly comparable to the simulated `elong_wind`.

### D. Analysis and figures — **no code yet; both inputs are now on disk**

The only piece with no code yet. Consumes `simulated_fires.rds` (on disk since 2026-08-21) and
the observed tables `observed_signature.rds` / `observed_shape.rds` (since 2026-08-28):
size-distribution Q-Q in `log10(area)`, shape metrics against all 238 polygons by size class,
signature distributions conditioned on `log10(area)`, and the FWI-stratified version. Plot style
in `docs/spread.md` → *Plot style* — simulated as 2-D density, observed as points, GAM
smoothers on both.

**The headline result is already visible and will not change:** observed fires are elongated
(median 2.12 over all 241, 2.47 over the 57 focal) and wind-aligned (51 % within 30° of the
113/293° axis, 72 % above 1000 ha), simulated fires are rounder (median 1.50 over all 64,836)
and randomly oriented (27.8 % within 30°, against 33.3 % for uniform). The full run adds the sharper version: measured **along the wind**, the simulated
fires are not elongated at all — median `elong_wind` 0.976, falling to 0.94 above 1000 ha. It is
structural — the automaton's
spread *rate* is isotropic, so the head fire cannot outrun the flanks, capping elongation at the
half-lobe bound of 1.89–2.0 regardless of the wind coefficient. Full argument and the evidence
that it is not a bug in `docs/spread.md` → *Why the model cannot make an elongated fire*.

### E. Figure 5 — burn-probability maps for four fires — **no code yet**

The other results figure that needs a run, not just a plot. Independent of B/C/D: it uses the
focal landscapes and the fitted model, both already on disk, so it can be done in any order.

**The four fires are chosen** (criteria and full justification in
`manuscript-spread/ijwf/designing.txt` → Fig. 5). Summaries from the 2000 fitted-ranef sims in
`files/hierarchical_model/metrics_table.rds`; `q` = simulated / observed size:

| fire_id | obs ha | overlap med/mean | q med/mean | P(q>1) |
|---|---|---|---|---|
| `1999_25j` | 724.0 | 0.838 / 0.832 | 1.04 / 1.04 | 0.85 |
| `2015_50` | 28,567.3 | 0.636 / 0.637 | 1.11 / 1.11 | 1.00 |
| `2004_23` | 320.1 | 0.350 / 0.349 | 0.44 / 0.53 | 0.07 |
| `2002_34` | 19.9 | 0.266 / 0.237 | 2.67 / 2.49 | 0.95 |

They give a monotone overlap gradient (0.84 → 0.27, against a 57-fire median of 0.535), three
orders of magnitude in size, and the strongest under- and overestimate in the set.

**What to run.** Per fire, 1000 simulations under **fitted** random effects and 1000 under
**simulated** ones — same landscape, same ignition point, one posterior draw per simulated fire,
full posterior (never the mean, never a thinned subset). Then burn probability per cell = the
fraction of simulations that burned it, with the observed perimeter drawn over it. Eight panels,
4 fires × 2 random-effect modes.

**Do not write the simulation loop from scratch.** `spread/hierarchical_fit.R` ~L2526–2620
already does exactly this — it builds `ranef_fit` and `ranef_sim` from `draws`, loops over
fires, and simulates. The only change needed is to accumulate a per-cell burn count instead of
reducing each simulation to the `metrics_table` row. Copy that block rather than re-deriving the
MVLN → `invlogit_scaled` chain.

> **The trap in that chain:** `draws$ranef` row 6 (`steps`) is stored on the **natural** scale
> while rows 1–5 are on the logit scale. `docs/spread.md` → *The elongation gap* records it.

**Inputs:** `data/focal_fires/landscapes/<fire_id>.rds` (landscape, `ig_rowcol`, `burned_layer`),
`files/hierarchical_model/draws_batch_*.rds` or `spread_model_samples.rds`, and
`files/hierarchical_model/size_obs.rds`. **Output:** a figure into `manuscript-spread/figures/`.

**Aesthetics:** Iván has made maps like this before, for presentations and possibly for the
thesis or RAE — find that code and copy its look rather than inventing one.

**Caption numbers, already computed:** median fitted-ranef overlap over the 57 focal fires is
0.535, median size quotient 1.04, and 36 of 57 fires are overestimated.

### Then

**Manuscript (started 2026-08-26).** `manuscript-spread/ijwf/` is initialised for the target
journal — *International Journal of Wildland Fire*, Research Article. Rules extracted with their
sources in `manuscript-spread/ijwf/guidelines/IWJF_guidelines.md`; build with `make` in
`manuscript-spread/ijwf/` (`make words` checks the 6000/200-word budgets). Writing can start
before D is finished — Introduction, study area and methods do not depend on the validation
results.

**Materials and methods drafted (2026-08-28)** — study area, data, the spread model, the
two-stage estimation and the validation design, with `references.bib` populated. It runs
**3311 words of the 6000**, which is more than half the budget on one section; the obvious
trim is to move the hierarchical priors (Eqns 4–6) and the stage-2 detail to the
supplementary, where IJWF expects the statistical detail anyway. Every open question in it has
been resolved except one: the `.tex` still carries `[Claude, make and add the study area
figure]`. The paper says **235 = 57 + 178** fires throughout (the four counts are reconciled in
`docs/spread.md` → *How many fires?*), and the figure plan lives in
`manuscript-spread/ijwf/designing.txt`.

Still true of the Validation subsection: it is written **as designed, not as completed** — the
spatial signature has only been run on the 57 focal fires, and needs B and C. Do not submit it
in that state.

4. **TODO #7 re-run** (see above) — do this whenever the SMC-fitted regime outputs are actually
   needed; not urgent otherwise. Note it would now also pick up a new PNNH wind field (see the
   drift item above) unless the old `.asc` files are recovered.
5. **TODO #9 decision** (see above) — resolve before sharing the store, not urgent otherwise.

6. **Redesign the season simulator before the TODO #7 re-run** — design note in
   `docs/fire-regime.md` → *Computational redesign of the season simulator*. `simulate.R` stalls
   at 2–3 workers because it carries a mutable full landscape (`pnnh_land_dyn`) that forking
   copies per worker; the engine only ever reads the clip, so the burned state can be a small
   mask stamped into the clip instead, leaving `pnnh_land` read-only and shared. Also covers the
   quadratic accumulators, whether the season loop should move to C++, and what changes once a
   simulation is 100 sequential seasons with vegetation updating. Steps 1–3 of its *Order of
   work* are cheap and should precede the multi-day re-run.

Deliberately **not** done, per the current scope: a general "build a landscape for any ROI"
function. `build_landscape()` is general enough to take any raster stack with the right bands,
but nothing automates producing that stack for an arbitrary region — the GEE side still exports a
fixed band set for a fixed set of regions (focal fires, PNNH, the K tiles). That is the remaining
work if arbitrary ROIs are ever needed.
