# Roadmap — current state & next steps

**This is a living document — edit it in place.** Unlike `docs/migration.md` (an append-only
historical changelog of the PhD-repo migration, finished and mostly closed out), this file
answers one question when you come back after a gap: *what's the current state, and what's the
next thing to do?* Update the two sections below as work progresses; don't accumulate history
here — that's what git log and `docs/migration.md` are for.

**Last updated:** 2026-08-21

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
- **The spread model's validation is designed, implemented and half-run** (2026-08-21). Design
  in `docs/spread.md` → *Stage 3 — validation*; `manuscript-spread/validation-and-journal.md`
  updated to match. Code: `R/spread_validation_functions.R`,
  `spread/validation_ignition_cells.R` (run — output in
  `files/spread_validation/ignition_cells.rds`), `spread/validation_simulate.R` (smoke-tested,
  not yet run at full size).

  - **All 185 GEE export tasks succeeded** — the 184 fires with unknown ignition point, plus the
    `2015_41` focal smoke test. In Drive folder `raw data from GEE signature`, prefix
    `fire_signature_raw_`, **not downloaded yet**. Two interchangeable drivers live in
    `~/dev/fire_spread-gee/`: the Code Editor script and `python/export_signature_landscapes.py`.
    Use the Python one for batches — the Code Editor's "run all tasks" plug-in gave up after 129
    of 184 (all 129 succeeded, so it was a transport failure, not a code one) and the Python
    driver is re-runnable, skipping fires whose task already exists.
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

**Where the spread paper's validation stands (2026-08-21).** The design is settled and written
up (`docs/spread.md` → *Stage 3 — validation*). Both sides of the comparison are code-complete
and smoke-tested; what is left is one download, one short script, one long run, and the analysis.

```
   simulated side                     observed side
   ──────────────                     ─────────────
   [A] full 50k run  ─── ready        57 focal fires ─── already on disk
       (unblocked, ~1-1.5 h)          184 others ─── exported ✅, NOT downloaded
                                            │
                                            ▼
                                      [B] R loop → landscapes
                                            │
                                            ▼
                                      [C] observed signature (241 fires)
                    └────────────┬──────────┘
                                 ▼
                          [D] analysis + figures
```

### A. Run the full simulation — **LAUNCHED 2026-08-21, ~1–1.5 h**

Running in tmux session `spread_sim`, logging to `files/spread_validation/run.log`:

```bash
cd ~/dev/fire-regime-sim-patagonia
tmux new-session -d -s spread_sim -c ~/dev/fire-regime-sim-patagonia \
  "stdbuf -oL -eL Rscript spread/validation_simulate.R 2>&1 | tee files/spread_validation/run.log; exec bash"
```

Smoke-tested twice: on 2026-08-21 after the switch to the `vfi`/`tfi`-only signature, and again
after the wind-elongation columns were added (300 requested → 370 fires from 892 proposals,
41.5 % acceptance, no NAs in the new columns). `n_target = 50 000` therefore needs ~120 000
proposals.

Writes `files/spread_validation/simulated_fires.rds` — one summary row per fire (size, shape
metrics, `b_vfi`/`b_tfi`, ignition location, drawn parameters) plus `small_sizes` for the
sub-10-ha fires. Nothing else depends on it, so start it and do B meanwhile.

**The shape columns carry both elongations** (see `docs/spread.md` → *The analyses* §2):
direction-free `elongation`, which is all the observed side can supply, and `elong_wind` along
each fire's own terrain-steered mean wind. The covariance entries `cov_ee`/`cov_nn`/`cov_en` are
saved too, so `elongation_along()` can measure against any other axis — notably the fixed 293° —
without re-running. Already visible in the smoke test: median `elong_wind` **0.97**, i.e. the
simulated fires are, if anything, very slightly stretched *across* the wind rather than along it.

### B. Build the 184 reduced landscapes — blocked on the download

**All 185 export tasks SUCCEEDED** (the 184 targets plus the `2015_41` focal smoke test), in
Drive folder `raw data from GEE signature`, files named `fire_signature_raw_<fire_id>.tif`.
They are **not downloaded yet** — that folder is not in Insync's selective sync. Either add it,
or download and unzip into:

```
data/signature_landscapes/raw_gee/      <- the 184 .tif (new)
data/signature_landscapes/landscapes/   <- the 184 .rds this step writes
```

mirroring `data/focal_fires/` and `data/simulation_landscapes/`. Then write a second loop in
`data_prep/landscapes_preparation.R` that, per fire: reads the tif, computes `vfi` from
`veg` + detrended `ndvi_prev`, `tfi` from `elevation`/`slope`/`aspect`, and saves a list with the
three layers plus the rasterized `burned` band. Reuses `build_landscape()`; **no WindNinja, no
ignition point, no `steps`**.

> Two things this loop must get right, or the observed set is inconsistent:
> - **`veg_crosswalk("forest")`** — urban → wet forest, the convention the 57 focal landscapes
>   used. *Not* the `"nonburnable"` one the simulation tiles use.
> - **NDVI detrending** — the focal landscapes detrend the previous summer's NDVI to its 2022
>   equivalent, which is why the export carries both `ndvi_prev` and `ndvi_22`. Do the same.
>
> The asset-vintage worry is closed: the migrated NDVI and vegetation rasters were compared
> against the legacy ones at 30 m and are pixel-identical (`max|old − new| = 0`), band order
> unchanged.

### C. Observed signature for all 241 fires — blocked on B

Run `donor_strata()` + `edge_clogit()` (`R/spread_validation_functions.R`) over the 57 focal
landscapes *and* the 184 new ones, and `fire_shape()` over all 238 mapped polygons. Already
proven on the 57: all converged, `vfi` median 0.578 (86 % > 0), `tfi` 1.881 (65 % > 0), both
strengthening with fire size.

### D. Analysis and figures — blocked on A and C

The only piece with no code yet. Consumes `simulated_fires.rds` and the observed tables:
size-distribution Q-Q in `log10(area)`, shape metrics against all 238 polygons by size class,
signature distributions conditioned on `log10(area)`, and the FWI-stratified version. Plot style
in `manuscript-spread/validation-and-journal.md` §3 — simulated as 2-D density, observed as
points, GAM smoothers on both.

**The headline result is already visible in the pilot and will not change:** observed fires are
elongated (median 2.2–2.6) and wind-aligned (49–70 % within 30° of the 113/293° axis), simulated
fires are rounder (~1.5) and randomly oriented (~0.29). It is structural — the automaton's
spread *rate* is isotropic, so the head fire cannot outrun the flanks, capping elongation at the
half-lobe bound of 1.89–2.0 regardless of the wind coefficient. Full argument and the evidence
that it is not a bug in `docs/spread.md` → *Why the model cannot make an elongated fire*.

### Then

4. **TODO #7 re-run** (see above) — do this whenever the SMC-fitted regime outputs are actually
   needed; not urgent otherwise. Note it would now also pick up a new PNNH wind field (see the
   drift item above) unless the old `.asc` files are recovered.
5. **TODO #9 decision** (see above) — resolve before sharing the store, not urgent otherwise.

Deliberately **not** done, per the current scope: a general "build a landscape for any ROI"
function. `build_landscape()` is general enough to take any raster stack with the right bands,
but nothing automates producing that stack for an arbitrary region — the GEE side still exports a
fixed band set for a fixed set of regions (focal fires, PNNH, the K tiles). That is the remaining
work if arbitrary ROIs are ever needed.
