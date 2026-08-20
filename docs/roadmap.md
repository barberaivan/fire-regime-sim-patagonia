# Roadmap — current state & next steps

**This is a living document — edit it in place.** Unlike `docs/migration.md` (an append-only
historical changelog of the PhD-repo migration, finished and mostly closed out), this file
answers one question when you come back after a gap: *what's the current state, and what's the
next thing to do?* Update the two sections below as work progresses; don't accumulate history
here — that's what git log and `docs/migration.md` are for.

**Last updated:** 2026-08-20

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

1. **~~Design the simulation experiment~~ — done (2026-08-20).** Written up in
   `docs/spread.md` → *Stage 3 — validation*; `manuscript-spread/validation-and-journal.md`
   updated to match. How the open questions resolved:

   - **Tile-border truncation** — gone, not managed. Each fire runs on its own
     `(2·steps+1)²` sublandscape, and the 8-neighbour automaton cannot leave that square in
     `steps` steps, so no fire is ever cut short. The cost is that the rule removes cells near
     tile borders, more of them the larger `steps` is; drawing `steps` *before* the ignition
     cell (and choosing the tile ∝ the cells that admit that margin) keeps the `steps`
     distribution exact. Rejecting and redrawing would have reintroduced the bias.
   - **Ignition sampling across four tiles** — uniform over tile ∩ study area ∩ burnable, tile
     chosen ∝ eligible area at the drawn margin. Supersedes an equal `nsim/4` split, which
     would over-sample tile 4 by ~50 %.
   - **PNNH → tiles** — done in both documents.
   - **Edge-pair extraction** — stays in R, `FireSpread` untouched. Measured 49 ms/fire.
     The 1:1 pairing was also replaced by a donor-centred conditional logit, which is
     materially better powered.
   - **Journal framing** — still open, still independent of the code.

2. **Implement and run it.** Written and pilot-tested (3 908 fires, 3 min 20 s on 14 cores):
   `R/spread_validation_functions.R`, `spread/validation_ignition_cells.R` (already run — its
   output is in `files/spread_validation/ignition_cells.rds`), `spread/validation_simulate.R`
   (`n_target = 50 000`, well under an hour). Cost is not a constraint: the earlier
   "hours at 1e5, overnight at 1e6" estimate was an order of magnitude pessimistic.

   Still to write: the **analysis and plotting** script consuming
   `files/spread_validation/simulated_fires.rds` — size-distribution Q-Q, shape metrics against
   all 238 mapped polygons, signature distributions conditioned on `log10(area)`, and the
   FWI-stratified version.

   Two findings from the pilot that shape the write-up:
   - Observed fires are elongated (median 2.2-2.6) and wind-aligned (49-70 % within 30° of the
     113/293° axis); simulated fires are rounder (1.5) and randomly oriented (~0.29). The
     clearest discrepancy found so far.
   - The macro size test is confounded by focal-fire selection: the five spread hyperparameters
     are informed only by the 57 fires with a landscape, whose median is 388 ha against 47.5 ha
     for the full record. Report it with the mechanism stated; analyses 2-4 condition on size
     and are unaffected.

3. **TODO #7 re-run** (see above) — do this whenever the SMC-fitted regime outputs are actually
   needed; not urgent otherwise. Note it would now also pick up a new PNNH wind field (see the
   drift item above) unless the old `.asc` files are recovered.
4. **TODO #9 decision** (see above) — resolve before sharing the store, not urgent otherwise.

Deliberately **not** done, per the current scope: a general "build a landscape for any ROI"
function. `build_landscape()` is general enough to take any raster stack with the right bands,
but nothing automates producing that stack for an arbitrary region — the GEE side still exports a
fixed band set for a fixed set of regions (focal fires, PNNH, the K tiles). That is the remaining
work if arbitrary ROIs are ever needed.
