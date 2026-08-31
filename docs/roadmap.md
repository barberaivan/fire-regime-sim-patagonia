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
- **The spread model's validation is complete** (2026-08-28) — design, both sides, the analysis
  and its figures. Design in `docs/spread.md` → *Stage 3 — validation*, results in the same file
  under *Results of the validation*; `manuscript-spread/journal_choose.md` updated to match.
  Code: `R/spread_validation_functions.R`, `spread/validation_ignition_cells.R` (output in
  `files/spread_validation/ignition_cells.rds`), `spread/validation_simulate.R` (64,836
  simulated fires), `spread/validation_observed.R` (241 observed fires),
  `spread/validation_analysis.R` (the comparison — four figures and
  `validation_summary.rds`). Paper Fig. 5 is done too, by
  `spread/figure_burn_probability.R`.

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

**Where the spread paper's validation stands (2026-08-28).** Design, both sides of the
comparison, the analysis and Fig. 5 are all **done**. Results are written up in `docs/spread.md`
→ *Results of the validation*; the remaining work is manuscript prose and the other figures.

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
                          [D] analysis + figures ─── DONE ✅
```

Fig. 5 (step E below) is done too, so the whole validation block is closed. What remains for
the paper is writing the Results and Discussion around it, and Figs. 1–4 and 6–7.

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

### D. Analysis and figures — **DONE 2026-08-28**

`spread/validation_analysis.R` compares the 64,836 simulated fires with the 241 observed ones —
size-distribution Q-Q, shape by size class, signature conditioned on `log10(area)`, and the
FWI-stratified version. Under a minute. Four figures into `files/spread_validation/figures/`
(`size_distribution`, `shape_by_size`, `signature_by_size`, `metrics_by_fwi`), every number into
`files/spread_validation/validation_summary.rds`. Plot style as designed: simulated as hex-binned
2-D density, observed as points, GAM smoothers on both. Full tables in `docs/spread.md` →
*Results of the validation*.

What it found, in one line each:

- **Size** — the simulator runs large by a factor of 2–3 through the middle of the distribution
  (median 151 vs 58 ha), uniformly rather than in one tail; KS *D* = 0.187. Weakest test of the
  set, and the truncation/record caveats apply.
- **Shape** — the headline result holds *at every size class*. Observed elongation 2.07 / 1.96 /
  2.57 against simulated 1.56 / 1.47 / 1.47; observed wind alignment 0.48 / 0.46 / 0.72 against
  simulated 0.30 / 0.27 / 0.26, the last of which is below the 0.333 of a uniform orientation.
- **Signature, `vfi`** — broadly agrees. The simulated median sits inside the observed IQR in all
  three size classes and the fraction positive matches within a few points. The gap the pilot
  implied was mostly the missing size conditioning.
- **Signature, `tfi`** — the real disagreement. Simulated fires give a *negative* edge-local
  topographic signature at small sizes (−2.45) where observed give a positive one (+0.66), and
  fewer than half of simulated fires are positive in any class.
- **FWI** — both sides grow with FWI by a similar factor (observed median 39.6 → 277.7 ha across
  quartiles, simulated 53.9 → 397.9). Simulated elongation rises weakly with FWI, observed is
  flat. The FWI panels are visibly striped because `fwi_z` is resampled from only 233 distinct
  observed values.

Decided with Iván on 2026-08-31 (his answers in `manuscript-spread/ijwf/designing.txt`): these
four stay as analysis output, and the paper's validation figures are the two built in **F**
below. `vfi`/`tfi` are dropped from the paper, and of the shape metrics only compactness and the
deviation from the wind axis survive — elongation and convex-hull fill are largely redundant
with compactness, and elongation along the fixed 293° adds nothing.

### E. Figure 5 — burn-probability maps for four fires — **DONE 2026-08-28**

`spread/figure_burn_probability.R` → `manuscript-spread/figures/fig5_burn_probability.{png,pdf}`.
Per fire, 1000 simulations under fitted random effects and 1000 under simulated ones, same
landscape and same ignition point, one posterior draw per simulated fire, full posterior. Eight
panels, 4 fires × 2 modes: burn probability per cell over a burnable/non-burnable base layer,
the observed perimeter haloed over it, the ignition point as a white dot, a scale bar per panel
(the four fires span 20 ha to 28,616 ha, so no shared scale would work). About **2 minutes on 8
cores**, nearly all of it `2015_50`.

The per-cell counts are kept in `files/hierarchical_model/burn_probability_maps.rds` (cropped to
what is drawn, rasters `wrap()`ped), so the figure can be restyled with `do_simulate <- FALSE`
without re-simulating.

The simulation block was copied from `spread/hierarchical_fit.R` ~L2526–2620, not re-derived, and
the natural-vs-logit `steps` trap was respected. The check that it was copied right: mean
simulated sizes give size quotients 1.03 / 1.11 / 0.53 / 2.39, against the `metrics_table`
values 1.04 / 1.11 / 0.53 / 2.49.

One thing to know before reading the panels: the square, blocky outer edge of the burned region
is the `steps` budget, not a landscape border — 8 neighbours per step means the burned set stays
inside a square of half-width `steps` around the ignition cell.

**Caption numbers, already computed:** median fitted-ranef overlap over the 57 focal fires is
0.535, median size quotient 1.04, and 36 of 57 fires are overestimated.

### F. Figures 6–7 — the validation figures — **DONE 2026-08-31**

Two scripts, both fast, both writing into `manuscript-spread/figures/`.

**Fig. 6 — `spread/figure_dharma_size.R` → `fig6_dharma_size_veg.{png,pdf}`.** DHARMa uniform
Q-Q of burned area, overall and per vegetation class, for the **57 focal fires only**, under
fitted and under simulated random effects. Reproduces `dharma_size_fit_sim.png` from the old PhD
repo (the *"Dharma for size"* block of `spread/hierarchical model fitting_FWIZ2_SMC.R`) against
this repo's canonical fit; reads only `metrics_table.rds`, `size_obs.rds` and
`veg_available.rds`, and runs in seconds.

Why focal fires only, for the paper's text: burned area per vegetation class is comparable
between observed and simulated only from the *same* ignition point, because what is available to
burn around that point dominates the answer. The 184 fires without a mapped ignition point
therefore carry the shape/size validation instead, never this one.

What it shows, in the same direction as the thesis version: **fitted** random effects put the
observed areas low in their own predictive distributions (mean scaled residual 0.28 overall,
0.75 of fires below the simulated median) — the model burns too much — while **simulated**
random effects push it the other way (mean 0.62, only 0.32 below the median). Grassland is the
worst class under fitted parameters (mean 0.29, KS *D* = 0.43), dry forest the best (0.54,
*D* = 0.19). Every class rejects uniformity at *p* < 0.05, in both modes; the script prints the
full table.

One open switch, `drop_unavailable` at the top of the script, defaults to `FALSE` — the faithful
reproduction. Fires where a vegetation class is entirely absent from the landscape (5 wet, 10
subalpine, 5 dry) are structural zeros whose residual is pure tie randomization; setting it to
`TRUE` drops them per panel. This is what `veg_available` was saved for and never used for.

**Fig. 7 — `spread/figure_validation_metrics.R` → `fig7a_size_distribution.{png,pdf}` and
`fig7b_metrics_conditioned.{png,pdf}`.** Part A is the size density + Q-Q, unchanged from D.
Part B is a 3 × 2 grid: one metric per row (size, compactness, deviation from the wind axis),
conditioned on FWI in the left column and on fire size in the right. The size row has no
size-vs-size panel, so the top-right cell holds the two shared legends — the line colour
(Simulated / Observed) and the `N° of simulated fires` colourbar. Sizes are drawn on a log10
scale but labelled in hectares. Axis titles appear once per column (bottom) and once per row
(left), since every column shares an x scale and every row a y scale.

The vertical striping in the FWI panels is left in on purpose: `fwi_z` is resampled from only 233
distinct observed values, and jittering would hide a real property of the simulated set.

Left as it is, and worth a glance before submission: Part A still labels its axes in log10 units
while Part B labels sizes in hectares.

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

The Validation subsection is still written **as designed, not as completed** — it was drafted
before B–E ran. It now needs updating to the past tense and a Results section written against
`docs/spread.md` → *Results of the validation*.

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
