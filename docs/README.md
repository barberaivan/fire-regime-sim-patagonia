# docs/

Deep documentation for the repo — the **architectural and computational detail** that the
concise papers and their supplementary material draw on. This is the two-tier system:

- **Short per-folder `README.md`** (in `R/`, `spread/`, …) = orientation: what's in the folder,
  planned files. Read first.
- **`docs/*.md`** (here) = the full detail: methods, statistics, inputs/outputs, gotchas.
- **`CLAUDE.md` and the root `README.md`** stay small and just point here.

| Doc | Covers |
|-----|--------|
| [`architecture.md`](architecture.md) | **Start here.** Module map, the **dependency tree**, end-to-end data flow, canonical pipeline, migration status & tech debt |
| [`data-prep.md`](data-prep.md) | Flammability indices (VFI/TFI), FWI standardization/fortnights/projections, landscape arrays |
| [`spread.md`](spread.md) | Spread model — ABC-SMC stage 1 (fire-wise posteriors) + hierarchical fit (paper 1) |
| [`ignition-escape.md`](ignition-escape.md) | Ignition (neg. binomial) + escape (logistic) models (paper 2) |
| [`fire-regime.md`](fire-regime.md) | Integration, spread recalibration, the simulator function, projections (paper 2) |

> **Relationship to the papers:** the two papers are concise (for ecologists); their
> supplementary carry full model/statistical detail; **this `docs/` tree carries the
> architectural + computational detail** (how the code is organised and run). Keep them in sync
> but not duplicated — supplementary = *what the model is*, docs = *how the repo computes it*.
