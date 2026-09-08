# fire-regime-sim-patagonia

Fire regime spatially explicit simulator for NW Patagonia, Argentina. Integrated ignition,
escape and spread models based on cellular automata, with parameters fitted to data.

The spread engine is the C++/Rcpp package [`FireSpread`](https://github.com/barberaivan/FireSpread);
this repo fits the models to data and integrates them into the regime simulator.

---

## Repository structure

| Folder | Role |
|--------|------|
| `R/` | shared function libraries (sourced by the pipeline scripts) |
| `src/` | in-repo C++ (Rcpp) |
| `data_prep/` | preprocessing: flammability indices, FWI, landscape arrays, vegetation-source merge |
| `spread/` | spread model fitting (ABC-SMC stage 1 + hierarchical fit) |
| `ignition_escape/` | ignition + escape model fitting |
| `fire_regime/` | integration: recalibration, the simulator function, runs, plots |
| `docs/` | deep architectural + computational documentation |
| `manuscript-spread/`, `manuscript-regime/` | LaTeX sources for the two papers |
| `data/` → store | heavy **inputs** (symlink; not in git) |
| `files/` → store | heavy **outputs** (symlink; not in git) |
| `data_private/` → private store | the **non-public** ignition record (symlink; not in git) |

Each code folder has its own short `README.md`; the full detail lives in **[`docs/`](docs/)**
(start with [`docs/architecture.md`](docs/architecture.md) for the module map and dependency
tree). Scripts assume the **repo root** as the working directory (open the `.Rproj`).

The **older version** of these models is documented in the PhD thesis, Barberá (2025), chapter 4
(`tex/secciones/04_modelos.tex`) + its appendix (`09_append_modelos.tex`):
<https://github.com/barberaivan/phd-thesis-fire-patagonia> (local clone
`~/dev/phd-thesis-fire-patagonia`). Several methods have changed since — see `CLAUDE.md` →
*Prior work — PhD thesis* for the chapter-by-chapter map and what is no longer current.

---

## Getting started (first-time setup)

This repo holds **code only**. The heavy data — landscape rasters, FWI grids, fire
shapefiles, fitted models, simulation outputs — is **not** in git. It lives in sibling
folders (the "stores"), synced via Insync/Google Drive, and a small script links them into
the repo. There are **two**: the shareable **`fire-regime-sim-patagonia-store`** and the
never-shared **`fire-regime-sim-patagonia-store-private`** (see *The two data stores* below).

> **Why?** Code belongs in git (which versions and backs it up); large binaries do not.
> Keeping them apart avoids a bloated git history and the sync conflicts that arise when a
> cloud-sync tool and git fight over the same files. See
> `~/Insync/Claude/repo-store-structure.md` for the full strategy.

### 1. Get the code

```bash
git clone git@github.com:barberaivan/fire-regime-sim-patagonia.git
cd fire-regime-sim-patagonia
```

### 2. Get the data store

Sync/download the **`fire-regime-sim-patagonia-store`** folder (Insync or a shared Google
Drive link) and note where it landed. It mirrors the repo's heavy paths (`data/`, `files/`).

If you also have access to the non-public ignition record, sync
**`fire-regime-sim-patagonia-store-private`** too (it mirrors `data_private/`). It is
optional: without it everything runs except `ignition_escape/fit.R` and two blocks of
`fire_regime/`.

### 3. Link the stores into the repo

From the repo root, run `setup.sh` **once**, giving it the store path (and the private one
if you have it, as a second argument):

```bash
./setup.sh /full/path/to/fire-regime-sim-patagonia-store \
           /full/path/to/fire-regime-sim-patagonia-store-private   # optional
```

That creates the `data/`, `files/` and `data_private/` symlinks and remembers the paths (in
a local, gitignored `.local-paths`), so any later re-run is just `./setup.sh`.

Confirm it worked:

```bash
ls data           # heavy inputs
ls files          # heavy outputs
ls data_private   # non-public ignition record (only if you have the private store)
```

> **Heads-up:** because the data is outside git, **uncommitted code is backed up nowhere** —
> `git commit && git push` often. Work one machine at a time, and `git pull` before you start.
> Symlinks require Linux/macOS (or Windows with WSL / Developer Mode).

### Spread engine dependency

Scripts use the **`FireSpread`** R package, expected as a **sibling repo** at `../FireSpread`
(`~/dev/FireSpread`). Clone it next to this repo and `library(FireSpread)` / source its
wrappers as the scripts do.

### WindNinja (optional — only to regenerate wind layers)

Already-prepared landscapes (`data/focal_fires/landscapes/`, `data/pnnh_images/`) embed their
wind layers, so most work doesn't need this. It's only required to generate *new* wind fields
(e.g. simulating fire outside the already-cached locations). No prebuilt Linux package exists;
build from source and put `WindNinja_cli` on `PATH`. See `docs/migration.md` TODO #3 for the
full build recipe (flags, dependency gotchas, the release tag to use) and set
`config$windninja_dir` in `R/config.R` to a scratch directory on your machine.

**Already done on Iván's machine:** built from source and installed at
`~/.local/bin/WindNinja_cli` (on `PATH`), source tree at `~/.local/src/windninja`. Two gotchas
that cost time the first time and will cost it again on a new machine:

- the CMake flag is `NINJA_QTGUI`, **not** `NINJA_GUI`;
- `momentum_flag` is incompatible with a NINJAFOAM-off build — leave it out;
- never point a test run at a real elevation file in the store (WindNinja writes its outputs
  beside the input).

### Google Earth Engine assets

The GEE scripts (`~/dev/fire_spread-gee/`, see `CLAUDE.md`) read the assets from the cloud
project **`projects/ivanbarbera-001/assets/`**; the legacy `users/IvanBarbera/Fire_spread/`
paths still resolve and are still what the 57 focal-fire landscapes were exported from. The
migrated NDVI and vegetation rasters were verified pixel-identical to the legacy ones at 30 m
with unchanged band order, so the two vintages are interchangeable — with one exception:
`projects/ivanbarbera-001/assets/patagonian_fires` has only 238 features, so the fire polygons
are still read from the legacy `patagonian_fires_spread` (241 features). Detail in
`docs/spread.md` → *Reduced landscapes*.

---

## The two data stores

The heavy data is split across two sibling folders, and the split is what makes the main store
safe to hand out as a single Drive link:

| Store | Linked in as | Holds | Shareable? |
|-------|--------------|-------|------------|
| `fire-regime-sim-patagonia-store` | `data/`, `files/` | landscape rasters, FWI grids and projections, fire perimeters, flammability indices, every fitted model and posterior sample, simulation outputs | **yes** — this is the link that goes in the papers' data availability statements |
| `fire-regime-sim-patagonia-store-private` | `data_private/` | `ignition/` — the PNNH fire-report record (Marcelo Bari, APN), the lightning-ignition database (Thomas Kitzberger), and everything derived from them: the merged point set, its Earth Engine covariate export, the population-point sample, `ignition_size_data.csv` | **no, never** |

The shareable store is published read-only at
<https://drive.google.com/drive/folders/1oqhWG3qKghszEEHhP24v30GrbHm2jwme>,
which is the link in the spread paper's data availability statement.

Both sources were provided for this research only and are not ours to redistribute, which is why
they sit in a folder a share link cannot reach rather than in a restricted subfolder of the main
store. **Do not move them back into the main store**, and do not add derived files that contain
individual ignition records to `data/` or `files/`.

What is *not* private: the fitted ignition and escape posteriors (`files/ignition/*.rds`) and the
PNNH covariate summaries stay in the shareable store. They are parameters and prediction surfaces,
checked to carry no individual record. The spread paper's own ignition points
(`data/ignition_points_checked*`, the 57 focal fires) are unrelated to the Bari-Kitzberger record
and are public.

Only `ignition_escape/fit.R` and two blocks of `fire_regime/` (the observed-size comparison in
`simulate.R`, the ignition-point map in `plots.R`) read the private store; everything else,
including the whole spread pipeline, runs from the shareable store alone.

## Status

**Migration complete (T0–T11)** — all canonical R/C++ code and heavy data have been copied from
the old PhD repo (`~/Insync/Fire spread modelling/fire_spread/`) into this repo and its store,
with paths updated and verified (parsing, sourcing, and data-loading, not full end-to-end runs).
The old repo's originals are untouched and kept until the new repo is confirmed working.

A few items need attention before trusting the full pipeline's output — see `docs/migration.md`'s
TODO register, especially:
- `fire_regime/` now reads the **canonical SMC-fitted** spread model (repointed from the legacy
  pre-SMC fit), but neither `simulate.R` nor `probability_maps.R` has been **re-run/validated**
  against it yet — treat existing regime-simulation/probability-map outputs as stale until they
  are (TODO #7);
- the ignition-escape "fire size" model and the ordinal-class escape model are abandoned/
  superseded exploratory work, not part of the canonical pipeline (see `ignition_escape/README.md`).

See `CLAUDE.md` for conventions and `docs/architecture.md` for the full migration/tech-debt list.
**Picking this back up after a break? See `docs/roadmap.md`** — it lists what is still open. What
is already done is written up in the `docs/*.md` for the module it belongs to.
