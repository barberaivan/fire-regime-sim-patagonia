# Roadmap — current state & next steps

**This is a living document — edit it in place.** Unlike `docs/migration.md` (an append-only
historical changelog of the PhD-repo migration, finished and mostly closed out), this file
answers one question when you come back after a gap: *what's the current state, and what's the
next thing to do?* Update the two sections below as work progresses; don't accumulate history
here — that's what git log and `docs/migration.md` are for.

**Last updated:** 2026-07-09

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

1. **`landscapes_preparation.R` refactor** — loop → function(s), so any landscape (focal fire,
   PNNH, or a future arbitrary ROI) can be built without a hard-coded loop. Full analysis of the
   three current duplicate blocks and a proposed function shape is in `docs/migration.md`
   → Refactors (item 10) → "`landscapes_preparation.R` refactor — handoff notes". Not started.
2. **Implement the spread-paper validation** — the analyses, sampling scheme, and metrics
   described in `manuscript-spread/validation-and-journal.md` (regional size distribution,
   per-fire spatial signature via edge-pair conditional logistic regression, FWI-stratified
   version, shape metrics). This is what follows the landscape refactor: validation needs
   large-N fire simulations over the PNNH landscape, which the refactor makes easier to drive.
   Not started.
3. **GEE-side generalization** — export landscape variables for any ROI, not just the fixed
   focal-fire set + PNNH. Needs planning; likely a prerequisite (or companion) to item 1's "any
   landscape" goal, since the R script currently assumes GEE has already exported a fixed band
   set for a fixed set of ROIs. See `CLAUDE.md` → "GEE Code Editor scripts".
4. **Simulate fire across the whole `patagonian_fires` study area** — the actual motivation for
   installing WindNinja: generate new wind fields beyond the cached focal-fire/PNNH landscapes.
   Depends on items 1 and 3 to build landscapes for arbitrary locations.
5. **TODO #7 re-run** (see above) — do this whenever the SMC-fitted regime outputs are actually
   needed; not urgent otherwise.
6. **TODO #9 decision** (see above) — resolve before sharing the store, not urgent otherwise.
