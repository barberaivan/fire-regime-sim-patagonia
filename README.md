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
| `data_prep/` | preprocessing: flammability indices, FWI, landscape arrays |
| `spread/` | spread model fitting (ABC-SMC stage 1 + hierarchical fit) |
| `ignition_escape/` | ignition + escape model fitting |
| `fire_regime/` | integration: recalibration, the simulator function, runs, plots |
| `docs/` | deep architectural + computational documentation |
| `manuscript-spread/`, `manuscript-regime/` | LaTeX sources for the two papers |
| `data/` → store | heavy **inputs** (symlink; not in git) |
| `files/` → store | heavy **outputs** (symlink; not in git) |

Each code folder has its own short `README.md`; the full detail lives in **[`docs/`](docs/)**
(start with [`docs/architecture.md`](docs/architecture.md) for the module map and dependency
tree). Scripts assume the **repo root** as the working directory (open the `.Rproj`).

The **older version** of these models is documented in the PhD thesis (chapter 4 + supplementary):
<https://github.com/barberaivan/phd-thesis-fire-patagonia>. Several methods have changed since —
see `CLAUDE.md`.

---

## Getting started (first-time setup)

This repo holds **code only**. The heavy data — landscape rasters, FWI grids, fire
shapefiles, fitted models, simulation outputs — is **not** in git. It lives in a sibling
folder **`fire-regime-sim-patagonia-store`** (the "store"), synced via Insync/Google Drive,
and a small script links it into the repo.

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

### 3. Link the store into the repo

From the repo root, run `setup.sh` **once**, giving it the store path:

```bash
./setup.sh /full/path/to/fire-regime-sim-patagonia-store
```

That creates the `data/` and `files/` symlinks and remembers the path (in a local,
gitignored `.local-paths`), so any later re-run is just `./setup.sh`.

Confirm it worked:

```bash
ls data    # heavy inputs
ls files   # heavy outputs
```

> **Heads-up:** because the data is outside git, **uncommitted code is backed up nowhere** —
> `git commit && git push` often. Work one machine at a time, and `git pull` before you start.
> Symlinks require Linux/macOS (or Windows with WSL / Developer Mode).

### Spread engine dependency

Scripts use the **`FireSpread`** R package, expected as a **sibling repo** at `../FireSpread`
(`~/dev/FireSpread`). Clone it next to this repo and `library(FireSpread)` / source its
wrappers as the scripts do.

---

## Status

**Skeleton** — structure and config are in place; canonical R/C++ code is being migrated
from the old PhD repo (`~/Insync/Fire spread modelling/fire_spread/`; migration blueprint in
its `INVENTORY.md`). See `CLAUDE.md` for conventions and the migration to-do.
