# fire_regime — integration & simulation (paper 2)

> **Status: scaffold.** High-level content is accurate (from the old repo's inventory); deep
> method detail (marked _TODO_) is written as the scripts are migrated and read.

Integrates ignition, escape and spread into the full fire regime simulator and runs the
scientific simulations/projections.

**Design intent (keep production-extractable):**
- **Recalibration is separate from simulation** — `recalibrate.R` recalibrates some spread
  parameters for the PNNH landscape; it is *not* embedded in the simulation loop.
- **The simulator is a standalone function** — `simulator.R` exposes the regime simulator as an
  importable function so the production side can extract it without the surrounding analysis code.

## `recalibrate.R`
- **Purpose:** recalibrate spread parameters for PNNH. _TODO: what is recalibrated, against what
  target, method._

## `simulator.R`
- **Purpose:** the regime simulator **as a function**: draws ignitions, applies escape, spreads
  fires via `FireSpread` over the PNNH landscape across fortnights/years.
  _TODO: time step, state, inputs (fitted params, landscape, FWI series), outputs, stochasticity._
- **Inputs:** `files/hierarchical_model/`, `files/ignition/`, `data/pnnh_images/…`, FWI fortnight
  rasters; sources `../FireSpread` + `R/flammability_indices_functions.R` + `R/fortnight_functions.R`.

## `simulate.R`
- **Purpose:** run many simulations for scientific analysis (incl. projections under CMIP6 FWI);
  writes to `files/fire_regime_simulation/`.

## `probability_maps.R`, `plots.R`
- Static fire-probability maps from single-model runs; visualization utilities. Export final
  figures into `manuscript-regime/figures/`.
