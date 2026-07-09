# fire_regime/ — integration & simulation

Integrates the ignition, escape and spread models into the full fire regime simulator, and
runs the scientific simulations/projections (paper 2).

> Full detail: [`../docs/fire-regime.md`](../docs/fire-regime.md).

Design intent (keep these separate so the production side can extract cleanly):

- **Recalibration is separate from simulation.** The regime run recalibrates some spread
  parameters for PNNH; that step lives in its own script, not inside the simulation loop.
- **The simulator is a standalone function.** Write the simulator as an importable function
  so production can extract it without the surrounding analysis code.

Planned files (migrated / refactored from the old repo):

| File | Role |
|------|------|
| `recalibrate.R` | Recalibrates spread parameters for the PNNH landscape (separate from the runs) |
| `simulator.R` | The fire regime simulator **as a function** (imports fitted params; production-extractable) |
| `simulate.R` | Runs many simulations for scientific analysis; writes to `files/` |
| `probability_maps.R` | Static fire-probability maps from single-model runs |
| `plots.R` | Visualization utilities for regime results |
