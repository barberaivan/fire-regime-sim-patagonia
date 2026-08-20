# spread — spread model fitting (paper 1)

> **Status: scaffold.** High-level content is accurate (from the old repo's inventory); deep
> method/statistics detail (marked _TODO_) is written as the scripts are migrated and read.

The largest, most complex module. Fits the fire spread model in two stages, driving the external
`FireSpread` cellular-automaton engine (`../FireSpread`).

> **Note:** the parameter-**estimation method changed** from the thesis version (see the PhD
> thesis, chapter 4 + supplementary — link in `CLAUDE.md` / root `README.md`). The **evaluation**
> of the model is also going to change. Document the *current* method here; note deltas from the
> thesis where useful.

## Stage 1 — fire-wise posteriors — `stage1_smc.R`
- **Purpose:** sample a posterior of spread parameters per focal fire.
- **Method:** ABC-SMC (Del Moral et al. 2011) with a hard ABC kernel; DE-MCMC moves using
  `src/sample_triplets_weighted.cpp` (weighted triplets of burned area, shape similarity, steps).
  _TODO: summary statistics, distance, kernel schedule, particle count, tolerances._
- **Inputs:** `data/focal_fires/landscapes/*.rds`, flammability params.
- **Outputs:** `files/posterior_samples_stage1/*.rds`.

## Stage 2 — hierarchical fit — `hierarchical_fit.R`
- **Purpose:** fit a hierarchical Bayesian spread model across fires.
- **Method:** custom MCMC (Gibbs + Metropolis–Hastings) from `R/mcmc_functions_smc.R`; uses
  stage-1 samples as proposals. _TODO: hierarchy (random effects, inverse-Wishart), parameter
  transforms (scaled-logit-normal), priors, convergence diagnostics._
- **Inputs:** `files/posterior_samples_stage1/`, the lagged FWI matrix.
- **Outputs:** `files/hierarchical_model/*.rds` — **the fitted spread model (production constant).**

## Stage 3 — validation

Pattern-oriented validation: the simulator is judged on whether statistical patterns that
emerge from many simulated fires match those of the observed record, not on point prediction
of individual fires. The rationale for skipping classical train/test (57 fires, deliberate
underparameterization, hierarchical shrinkage as its own regularizer) lives in
`manuscript-spread/validation-and-journal.md` §1 and belongs in the discussion; this section
documents **what is run**.

Code: `R/spread_validation_functions.R` (shared metrics),
`spread/validation_ignition_cells.R` (run once), `spread/validation_simulate.R` (the run).

### The simulation experiment

Fires are simulated over the **four study-area tiles** (`docs/data-prep.md`), not PNNH — the
tiles cover 99.1 % of the Barberá et al. (2025) study area, which is the domain the observed
fire record is complete over. Per proposal:

| # | draw | from |
|---|------|------|
| 1 | FWI | resample with replacement from the **233** mapped fires' `fwi_fort_expquad`, standardized by `fwi_mean_sd_spread.rds`. The csv's 233 rows are the distinct fires; the model's 235 rows duplicate two split fires, so resample the csv. |
| 2 | posterior index | uniform over the 12 000 merged draws (`spread_model_samples.rds`) |
| 3 | parameters | a **new** fire from the population multivariate logit-normal `MVLN(μ(FWI, i), Σ(i))` — full hyperparameter *and* between-fire uncertainty, never a fitted fire's random effect |
| 4 | tile | probability ∝ `n_valid[k][steps]`, the eligible cells in tile *k* that admit a margin of `steps` |
| 5 | ignition cell | uniform among those cells |

Eligible cells are tile ∩ study area ∩ burnable, read from the **landscape arrays** (so cells
turned non-burnable by a missing predictor are excluded too): 26.6 M cells = 23 945 km², split
26.0 / 30.1 / 26.8 / 17.1 % across the tiles.

**Why that order.** The fire is simulated on the `(2·steps+1)²` sublandscape centred on the
ignition cell. `FireSpread` spreads to the 8 neighbours per step, so after `steps` steps the
burned set cannot leave that square — **no fire is ever cut short by a tile border**, which
disposes of the truncation problem the tiles introduced. But the rule removes cells near the
borders, and removes more of them the larger `steps` is (the study area spans each tile's full
height, so the N–S margin is zero). Fraction of eligible cells retained:

| steps | 50 | 200 | 359 | 716 | 1167 | 1766 |
|-------|----|-----|-----|-----|------|------|
| tile 1 | .978 | .911 | .839 | .707 | .479 | .130 |
| tile 2 | .981 | .929 | .871 | .716 | .372 | .002 |
| tile 3 | .983 | .932 | .875 | .740 | .436 | .072 |
| tile 4 | .986 | .925 | .823 | .590 | .318 | .020 |

Redrawing the ignition *and* the parameters until they fit would therefore reject large-`steps`
fires more often and silently shrink the simulated size distribution — reintroducing exactly
the bias the margin rule removes. Drawing `steps` first and then choosing the tile ∝ available
cells is equivalent to "uniform over every eligible cell in the whole study area that admits
margin `steps`", leaves the marginal distribution of `steps` untouched, and never fails
(`stepsU ≤ 2000` and tile 1 still has ~200 k eligible cells at `steps` = 2000). Tile choice
∝ area also supersedes an equal `nsim/4` split, which would over-sample tile 4 by ~50 %.

What this does *not* remove: conditional on a large `steps`, ignitions fall only in a central
sub-region of a tile. Negligible for the 88 % of fires with `steps ≤ 200`; a limitation for the
rare very large ones.

**The 10 ha threshold.** The mapping records nothing below 10 ha (observed minimum 10.1 ha), so
simulated fires below it have no observed counterpart and are discarded. About **56 % of
proposals** fall below it (half of those burn the single ignition cell), so the run proceeds in
passes until `n_target = 50 000` accepted fires is reached, oversampling by the running
acceptance rate. Discarded fires are not lost silently: their sizes are kept in `small_sizes`,
so the acceptance rate is itself reportable.

**No steps-intercept shift.** The −0.95 in `fire_regime/` is a recalibration of the *regime*
simulator; applying it here would make the validation circular.

### The analyses

**1. Regional size distribution (macro test).** Simulated vs observed `log10(area)`, Q-Q plus a
KS statistic. Read it with the caveat below — it is the weakest of the set.

**2. Shape metrics.** Area, perimeter, compactness, **elongation and orientation** (PCA on
burned-cell coordinates; orientation as a bearing mod 180, comparable to the fixed 293° wind, so
fires should run along the 113/293 axis), and convex-hull fill. These need no landscape, only a
rasterized polygon — so the observed reference is **all 238 mapped fires across every size
class**, not just the 57 focal ones. Sub-millisecond per fire. This is where the wind term is
actually tested (see below).

**3. Per-fire spatial signature.** For each fire, a **donor-centred conditional logit**: one
stratum per burned cell with at least one burnable unburned neighbour, members = that cell's
burnable neighbours, response = burned, predictors computed source→target exactly as
`spread_one_cell_prob()` does (`vfi`/`tfi` at the target, `slope = sin(atan(Δz/dist))` uphill
only, `wind = cos(angle_k − wdir_source)·wspeed_source`). This is literally the simulator's own
Bernoulli trial set; holding the donor fixed conditions out the fire, the weather and the donor
itself, and the shared intercept drops out. Fitted with `survival::clogit(method = "exact")` —
strata have up to 8 members and often several cases, where Breslow/Efron genuinely differ.
Donors subsampled to 1500 per fire. Compare the *distribution* of coefficients (and of
standardized partial effects `β·sd(x)`, comparable across predictors) between observed and
simulated, conditioning on `log10(area)`.

This replaces the 1:1 "one unburned edge cell + one random burned neighbour" pairing in
`validation-and-journal.md` §2.2, which was tested and is strictly weaker: on the 57 observed
fires it gives a near-zero, high-variance signature for `vfi` (median 0.06, 54 % > 0) where the
donor-centred version resolves it clearly (0.24, 84 % > 0).

Edge extraction stays **in R** — measured at 49 ms/fire mean over the 57 focal fires, 0.45 s for
the largest (300 k cells). There is no case for modifying `FireSpread`'s output contract.

**4. FWI-stratified version.** Repeat 2 and 3 within FWI quartiles — the model's most
distinctive structural claim is that spatial coefficients move with FWI. The second simulated
dataset with FWI drawn uniformly across the modeled range (for coverage where observed data is
sparse) is **deferred**, not part of the current run; revisit if the stratified test turns out
to be starved at high FWI.

### What each test can and cannot diagnose

**The wind term cannot be tested by any edge-based regression.** Around a fire's perimeter the
donor→receiver direction is the outward normal, so it is isotropic by construction, and the
already-burned neighbours of an edge donor are systematically the ones the fire arrived *from* —
i.e. upwind — which cancels the true effect. Both the 1:1 and the donor-centred schemes return a
flat, zero-centred `wind` coefficient on the observed fires (median 0.00, 51 % > 0). Wind is
tested through **orientation and elongation** instead, where the observed signal is strong. This
promotes the shape metrics from "cheap complement" to a primary analysis.

**The macro test is confounded by how the focal fires were chosen.** The five spread
hyperparameters are informed only by the 57 fires that have a landscape and an identified
ignition point, and those are a strongly size-biased subsample — median **388 ha** against
**47.5 ha** for the full 233-fire record, holding 74 % of all burned area. Only `steps` also
learns from the other 177, through the `log(area) ~ log(steps)` regression. So a fire drawn from
the population is a draw from the *focal-fire* population, and the simulated size distribution
sits high against the full record by construction. Two supporting checks:

- At the **observed** ignition points with new random effects (`metrics_table.rds`), the model
  slightly *under*-predicts the focal fires (median 258 ha vs 434 ha; PIT median 0.28).
- Uniform ignition makes fires *smaller*, not larger (median 258 → 154 ha).

So the over-prediction is in the parameter population, not in the ignition rule or the tiles.
Report the macro test against both references, state the mechanism, and note that it is the
same bias the regime paper's γ₀ = −0.95 recalibration absorbs. It does not affect analyses 2–4,
which condition on fire size.

Also flag once, per `validation-and-journal.md` §6.3: the simulator's edges lump "spread
refused" and "step budget exhausted", a lumped stand-in for suppression and weather-event end.
Per-cell stop-mechanism attribution is out of scope.

### Cost and parallelization

Measured, not estimated: clip + CA is **11 ms/fire** mean, worst case ~2.3 s and 492 MB at
`steps` = 1600; the slowest 1 % of fires take about half the total CPU. The 3 000-fire pilot took
**3 min 20 s** on 14 cores, so 50 000 accepted fires is well under an hour.

- **Tiles sequential, fires parallel.** One ~1 GB tile array in RAM at a time.
- **Fork, never PSOCK** (`parallel::mclapply`). Nothing writes to the landscape here — unlike
  `fire_regime/simulate.R`, there are no reburn dynamics — so the tile array is shared
  copy-on-write across all workers for free. A PSOCK cluster would serialize 1 GB per worker.
- **Everything random is drawn in the master**, so a worker is a pure function of its chunk.
  Each chunk carries its own `chunk_seed`; `simulate_fire` calls `R::rbinom` internally, so
  workers need independent streams, and seeding per chunk keeps results reproducible regardless
  of how chunks get scheduled.
- **Dynamic dispatch, small chunks** (200 fires, `mc.preschedule = FALSE`), ordered
  longest-`steps`-first. Static splitting is what fails: one unlucky worker would set the wall
  clock.
- **Reduce inside the worker.** 50 000 fires at the simulated mean size would be ~10⁹ burned
  cells; workers return one summary row per fire (size, shape, clogit coefficients, ignition
  location, drawn parameters) and no rasters.
- Two micro-optimizations that matter at the tail: subset the three simulator arguments straight
  out of the tile array (an intermediate `land[r1:r2, c1:c2, ]` cube doubles the copying), and
  hand vegetation over as `integer`, which is what the C++ signature wants.

### Pilot results (3 908 fires ≥ 10 ha, 2026-08-20)

Enough to confirm the statistics discriminate. The shape rows are size-matched, so the
focal-selection caveat above does not drive them:

| metric | observed | simulated |
|--------|----------|-----------|
| median area | 47.5 ha (233-fire record) | 154.5 ha |
| elongation, > 1000 ha | 2.59 | 1.46 |
| within 30° of the wind axis, > 1000 ha | 0.70 | 0.24 (0.33 = random) |
| compactness, 200–1000 ha | 0.045 | 0.236 |
| signature `slope` (β·sd, > 100 ha) | 0.20 | 0.19 |
| signature `vfi` (β·sd, > 100 ha) | 0.28 | 0.86 |
| signature `tfi` (β·sd, > 100 ha) | 1.72 | 0.19 |

Observed fires are elongated and wind-aligned at every size class; simulated fires are rounder
and randomly oriented. `slope` matches well, `vfi` is over-weighted and `tfi` under-weighted.

## Refactor targets
- Split inline data manipulation out of the fitting script into functions (tech debt #2).
- Vendor the `FireSpread` R spread wrappers instead of sourcing from `tests/testthat/` (#3).
