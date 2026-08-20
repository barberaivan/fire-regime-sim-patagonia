# Roadmap — current state & next steps

**This is a living document — edit it in place.** Unlike `docs/migration.md` (an append-only
historical changelog of the PhD-repo migration, finished and mostly closed out), this file
answers one question when you come back after a gap: *what's the current state, and what's the
next thing to do?* Update the two sections below as work progresses; don't accumulate history
here — that's what git log and `docs/migration.md` are for.

**Last updated:** 2026-08-19

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
- **Study-area tiles are defined in GEE but not yet exported.** `Landscapes export for
  simulation (study area tiles)` (in `~/dev/fire_spread-gee/`) cuts the Barberá et al. 2025
  study area into K = 4 latitudinal rectangles ~150 km tall, each fitted inside the region
  where the NDVI and vegetation assets have data. They do **not** overlap (2026-08-20: the
  10 km buffer and its ~20 km overlap are gone, and so is the R twin `study_area_tiles()`) —
  a fire that reaches a tile's border is cut short by it, which the simulation has to handle.
  R reads the rectangles back from the exports and records them in
  `data/simulation_landscapes/study_area_tiles.shp`. The script has **not been run** — see
  next steps.
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

## Next steps (roughly in priority order, per the user's own plan)

1. **Run the GEE tile export.** Open `Landscapes export for simulation (study area tiles)` in
   the Code Editor and start the 4 tasks (~500 MB each, `veg`/`ndvi`/`elevation`/`slope`/`aspect`
   at 30 m, EPSG:5343). Check the printed tile sizes first; the script has `K` at the top if they
   need to be smaller. Two things to confirm on opening it: the `study_area` asset path (taken
   from the older `Landscapes export`, `users/IvanBarbera/patagonian_fires/study_area`, while the
   other assets use the newer `projects/ivanbarbera-001/assets/` form), and that
   `NDVI_mean_ts` has a `b_2022` band. Download the results into
   `data/simulation_landscapes/raw_gee/`.
2. **Build the tile landscapes.** `data_prep/landscapes_simulation.R` with
   `do_tiles_windninja <- TRUE` for the first pass — 4 WindNinja runs at 120 m mesh, then the
   landscapes themselves (~1.0-1.2 GB each; build and save one at a time, the script already
   does). Nothing else needs re-running: `do_pnnh` stays `FALSE`.
3. **Implement the spread-paper validation** — the analyses, sampling scheme, and metrics
   described in `manuscript-spread/validation-and-journal.md` (regional size distribution,
   per-fire spatial signature via edge-pair conditional logistic regression, FWI-stratified
   version, shape metrics). The tiles from steps 1-2 are the landscape it simulates over; note
   that document assumes PNNH, which the tiles now supersede for the regional size-distribution
   test.
4. **TODO #7 re-run** (see above) — do this whenever the SMC-fitted regime outputs are actually
   needed; not urgent otherwise. Note it would now also pick up a new PNNH wind field (see the
   drift item above) unless the old `.asc` files are recovered.
5. **TODO #9 decision** (see above) — resolve before sharing the store, not urgent otherwise.

Deliberately **not** done, per the current scope: a general "build a landscape for any ROI"
function. `build_landscape()` is general enough to take any raster stack with the right bands,
but nothing automates producing that stack for an arbitrary region — the GEE side still exports a
fixed band set for a fixed set of regions (focal fires, PNNH, the K tiles). That is the remaining
work if arbitrary ROIs are ever needed.
