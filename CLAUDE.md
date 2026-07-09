# CLAUDE.md

Operating rules for Claude Code (and any contributor) working in this repo.
Durable guidance only — keep this an index, not an encyclopedia.

## What this repo is

A spatially explicit **fire regime simulator** for north-western Patagonia (Nahuel
Huapi National Park and surroundings). Three fire sub-models — **ignition**, **escape**,
**spread** — are fitted to data and integrated into one regime simulator used for
scientific projections and, eventually, a production simulation platform.

- **Science side:** two papers — (1) the fire spread model (fitting + validation);
  (2) the fire regime simulator + projections (develops ignition & escape, cites the
  spread paper, runs many simulations).
- **Production side:** the spread engine (`FireSpread`, C++), the fitted parameters as
  input constants, and the whole regime simulator wrapped as an extractable function.

Language stack: **R** for all fitting/simulation/processing; **C++ via Rcpp** for the
spread engine and one in-repo `.cpp`. No Python.

## Repository structure

```
fire-regime-sim-patagonia/
├── R/                 # shared function libraries (no upstream script deps)
├── src/               # C++ (Rcpp) — sample_triplets_weighted.cpp
├── data_prep/         # preprocessing → intermediate data (flammability, FWI, landscapes)
├── spread/            # spread model fitting (ABC-SMC stage 1 + hierarchical fit)
├── ignition_escape/   # ignition + escape model fitting
├── fire_regime/       # integration: recalibration, the simulator function, runs, plots
├── docs/              # deep architectural + computational documentation (see below)
├── manuscript-spread/ # LaTeX sources — paper 1 (spread)
├── manuscript-regime/ # LaTeX sources — paper 2 (regime)
├── data/  → store     # heavy INPUTS  (symlink into the -store folder; gitignored)
└── files/ → store     # heavy OUTPUTS (symlink into the -store folder; gitignored)
```

Each code folder has a short `README.md` describing its role and planned files.

## Documentation — read the right file

Two tiers: the short per-folder `README.md` (orientation) and the deep `docs/*.md` (detail).
**CLAUDE.md and the root README stay small and point to `docs/`.**

| Doc | Covers |
|-----|--------|
| `docs/architecture.md` | **Start here.** Module map, the **dependency tree**, data flow, canonical pipeline, migration status & tech debt |
| `docs/data-prep.md` | flammability indices, FWI processing, landscape arrays |
| `docs/spread.md` | spread model — ABC-SMC stage 1 + hierarchical fit (paper 1) |
| `docs/ignition-escape.md` | ignition + escape models (paper 2) |
| `docs/fire-regime.md` | integration, recalibration, the simulator, projections (paper 2) |

`docs/` carries the architectural/computational detail; the papers' **supplementary** carry the
model/statistical detail. Keep them in sync, not duplicated.

## Prior work — PhD thesis

The **older version** of these models is described in the PhD thesis, **chapter 4 (`04_modelos`)
and its supplementary**: <https://github.com/barberaivan/phd-thesis-fire-patagonia>
(local clone `~/dev/phd-thesis-fire-patagonia`). Read it for background, but note what has
**changed since** and must not be assumed current:
- the **spread parameter estimation method** changed (thesis → this repo's ABC-SMC + hierarchical fit);
- the **spread model evaluation** is going to change;
- in the regime paper, **a few functions in the spatial ignition model will change**.

## Code + Store — heavy data lives outside git

This repo is **code only**. Heavy data (`data/`, `files/`) is not in git; it lives in a
sibling **`fire-regime-sim-patagonia-store`** folder synced via Insync/Google Drive and
is symlinked into the repo by **`./setup.sh`** (see `README.md` → *Getting started*, and
the strategy doc at `~/Insync/Claude/repo-store-structure.md`).

- Run `./setup.sh /path/to/fire-regime-sim-patagonia-store` once per machine; later runs
  are just `./setup.sh`. The store path is saved to gitignored `.local-paths`.
- Because data is outside git, **uncommitted code is backed up nowhere** — `git commit &&
  git push` often. Work one machine at a time; `git pull` before starting.
- Never commit the `data`/`files` symlinks or `.local-paths` (all gitignored).

## Conventions

- **Working directory is the repo root.** All `file.path("spread", …)` style paths are
  relative to it. Run scripts from the root (the `.Rproj` opens there).
- **External engine dependency:** the spread functions come from the **`FireSpread`** R
  package, a **sibling repo at `../FireSpread`** (`~/dev/FireSpread`, remote
  `barberaivan/FireSpread`). Scripts source its R wrappers and `library(FireSpread)`.
- Prefer functions over top-level scripts; keep MCMC/algorithm cores in `R/`, and keep the
  regime **simulator as a standalone function** so the production side can extract it.

## Status & migration

**Migration complete (T0–T11)** — canonical R/C++ code and heavy data have been copied from the
old PhD repo `~/Insync/Fire spread modelling/fire_spread/` (blueprint: that repo's
`INVENTORY.md`) into this repo/store, renamed to canonical names, and verified (parse, sourcing,
data-loading — not full multi-day fits/simulations end-to-end). Originals are kept until the new
repo is confirmed working, then can be deleted.

**Before trusting the full pipeline's output**, resolve the open items in `docs/migration.md`'s
TODO register — most importantly **#7**: `fire_regime/simulate.R` and `probability_maps.R` now
read the **canonical SMC-fitted** spread model (repointed 2026-07-09; structurally verified
compatible with the legacy fit), but neither script has been **re-run/validated** against it —
existing regime-simulation/probability-map outputs are stale until they are. Also see
`ignition_escape/README.md`: the "fire size" model and the ordinal-class escape model are
abandoned/superseded, not part of the canonical ignition-escape pipeline (binary
`escape_model.stan` is canonical). The full tech-debt and TODO list live in
**`docs/architecture.md` → Migration status & tech debt** and **`docs/migration.md`**.

**TODO #2 (vegetation-equivalences `.xlsx`) is resolved** — found via Google Drive, placed at
`data/vegetation_equivalences.xlsx`. A separate "ciefap" equivalence table (for a different
source vegetation map, used elsewhere — not by anything in this repo) is kept alongside it at
`data/vegetation_equivalences_ciefap.xlsx` for provenance.
