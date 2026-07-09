# spread/ — spread model fitting

Fits the fire spread model in two stages. This is the largest, most complex module and the
subject of paper 1. Uses the external `FireSpread` engine (`../FireSpread`).

> Full detail: [`../docs/spread.md`](../docs/spread.md).

Planned files (migrated from the old repo):

| File | Role |
|------|------|
| `stage1_smc.R` | Stage 1 — fire-wise posterior sampling via ABC-SMC (compiles `src/sample_triplets_weighted.cpp`); writes to `files/` |
| `hierarchical_fit.R` | Stage 2 — hierarchical Bayesian fit via custom MCMC (Gibbs + MH), using stage-1 samples as proposals |
