# fire_regime: integration & simulation (paper 2)

> **Status: scaffold.** High-level content is accurate (from the old repo's inventory); deep
> method detail (marked _TODO_) is written as the scripts are migrated and read.

Integrates ignition, escape and spread into the full fire regime simulator and runs the
scientific simulations/projections.

**Design intent (keep production-extractable):**
- **Recalibration is separate from simulation**: `recalibrate.R` recalibrates some spread
  parameters for the PNNH landscape; it is *not* embedded in the simulation loop.
- **The simulator is a standalone function**: `simulator.R` exposes the regime simulator as an
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
- **Inputs:** besides the fitted models and landscapes, it reads
  `data_private/ignition/ignition_size_data.csv`, the observed ignition record, used only to
  compare the simulated fire-size distribution with the observed one. It comes from the
  never-shared private store (`architecture.md` → *The two stores*), so this comparison block
  is the one part of the script that will not run without it. `plots.R` likewise reads the
  ignition points from there for its PNNH map.

## `probability_maps.R`, `plots.R`
- Static fire-probability maps from single-model runs; visualization utilities. Export final
  figures into `manuscript-regime/figures/`.

## `spread_probability_map.R` — the spread panel under the SMC posterior (2026-09-09)

Recomputes **only** the spread panel (panel D of the thesis figure
`burn_prob_models_modern`) under the canonical SMC fit and under the legacy pre-SMC fit, so the
two are directly comparable. Written to answer a specific question: the south of PNNH burns
much more than the rest in the annual burn-probability map (panel E), and it was unclear whether
that comes from ignition (low elevation raising the lightning-ignition probability) or from
spread. Run it from the repo root, no arguments, **~20 min** (2 posteriors x 12000 draws x 1.1 M
burnable pixels x 2 variants).

It also recomputes the **escape** layer, not because that fit changed but because of the
`prob_esc` bug below; the two ignition layers are read from the old tiff unchanged.

Workflow: reads `data/pnnh_images/pnnh_data_120m_buff_10000.tif`, recodes vegetation, computes
VFI/TFI, then for each posterior draw takes the fixed effects at FWI = mean (`fixef[, "a", ]`),
draws one fire-level parameter vector from `MVN(mu, V)` built from `s2` and `rho`, maps it to
the constrained support, and averages `plogis()` over draws. Writes
`files/fire_regime_simulation/spread_prob_map_120m.tif` (4 layers) and two figures into
`fire_regime/figures/` (gitignored, like `spread/figures/`).

Two variants per posterior, because the original code and the thesis caption disagree:
- **static** — slope and wind terms set to zero. This is what the code behind the thesis figure
  actually computed, so it is the drop-in remake of panel D.
- **directional** — the most favourable direction (straight upslope, 14.4 km/h wind blowing
  along the spread). This is what the caption describes ("se fijó la velocidad del viento en
  14.4 km/h"), and it is where the slope and wind coefficients show up. **The caption is wrong
  about the published panel**; fix it if that figure is reused in the regime paper.

Results:
- The map **barely changed**. Overall mean spread probability inside PNNH: 15.7 % legacy ->
  12.8 % SMC (static); 76.9 % -> 76.9 % (directional). The spatial pattern is essentially
  identical; the SMC-legacy difference is a nearly uniform -3 pp offset with no structure
  (see `spread_prob_smc_vs_legacy.png`, panel C).
- The south is **not** a spread hotspot. Mean static spread probability by latitudinal band
  inside the park runs 19.9 % (southernmost tenth) down to 9.4 % (northernmost), a gentle
  gradient of the same shape under both fits; the directional variant is flat (83.7 % south
  vs 77.0 % north). Nothing in this that looks like the sharp, order-of-magnitude southern
  hotspot in panel E.
- So the southern burn-probability hotspot is **not explained by the spread model**, and
  repointing to the SMC posterior does not change that. The remaining candidates are ignition
  (elevation -> TFI -> lightning) and escape, plus the compounding of many simulated fires.

### The `prob_esc` bug (found and fixed 2026-09-09)

The escape loop in `probability_maps.R` read `prob_esc <- plogis(...)` where every other loop in
the script accumulates (`x <- x + ... * weight`). It therefore kept only the **last** posterior
draw. Consequences:

- `data/pnnh_images/pnnh_data_120m_buff_10000_ig-esc-spread-prob_FWIZ.tiff`'s `escprob` layer,
  and with it **panel C of the thesis figure** `burn_prob_models_modern`, is one draw from the
  escape posterior rather than its mean. That tiff is stale until `probability_maps.R` is
  re-run in full.
- The error is smaller than it sounds, because the escape posterior is tight: mean inside PNNH
  31.2 % (one draw) vs 31.9 % (posterior mean), correlation 0.957, 95 % of pixels within
  +-9 pp. The map reads the same; individual pixels move.
- Nothing else consumed that layer. The simulator (`simulate.R`) evaluates escape per ignition
  from the posterior directly and never reads the tiff, so simulation output is unaffected.

Fixed in `probability_maps.R`, with the corrected escape layer recomputed by
`spread_probability_map.R` (layer `escprob` of `spread_prob_map_120m.tif`) so the remade
five-panel figure has a correct panel C without waiting on a full re-run.

---

# Rebuilding the season simulator in C++ (design discussion, 2026-09-09)

> **Status: designed, nothing implemented. Paused mid-discussion; resume at *Open decisions*.**
> This replaces the design note of 2026-08-27, which proposed an R-level mask redesign and left
> the C++ question open. The session of 2026-09-09 read `simulate.R` end to end, read the
> `FireSpread` engine source, and measured the objects involved. Several assumptions in the old
> note turned out to be wrong or incomplete; the corrected diagnosis is below. Iván took four
> decisions (marked **DECIDED**); three remain open and are listed at the end.

## The problem, stated precisely

`simulate.R` stalls at **2 to 3 workers on a 32 GB machine**, while the spread-validation path in
`spread/validation_simulate.R` runs comfortably on 14. The difference is not the model, it is
**mutable landscape state**.

The validation path is memory-clean by construction (`docs/spread.md` → *Cost and
parallelization*): one tile in RAM at a time, forked workers, nothing written to the landscape,
so the array stays shared copy-on-write across all workers for free.

The season simulator cannot use that trick as written, because it carries a mutable landscape:

```r
pnnh_land_dyn <- pnnh_land                                 # simulate.R:277, per season
...
pnnh_land_dyn <- vegetation_update(pnnh_land_dyn, burned)  # simulate.R:464, per fire
```

Under `registerDoMC` (fork), the first write in each worker dirties the pages and the OS
materialises a private copy of the whole landscape array per worker. `pnnh_land` is
6482 x 3712 = **24,061,184 cells x 6 layers x 8 bytes = 1.15 GB**, so three workers is the
ceiling. Three further costs sit on top:

1. `vegetation_update()` (simulate.R:210 to 225) allocates the veg layer twice more per call,
   `as.vector(land[, , "veg"])` then `matrix(veg_vec, ncol = ncol(land))`, before assigning back
   into the 3-D array, which is itself a full-array copy.
2. The candidate-cell filter (simulate.R:477 to 481) rebuilds a `bitmask` of length
   `max(cells_pnnh_dyn, cells_burned)` on every fire, a landscape-sized allocation per fire, to
   do a set difference.
3. Both accumulators grow quadratically: `size_fwi_table <- rbind(size_fwi_table, mmat)` and
   `burned_ids_list <- c(burned_ids_list, list(burned))` copy the whole accumulator each fire.

The ceiling is structural, not a hardware shortfall. More RAM would buy more workers without
fixing any of this.

## What reading the code and the engine actually showed

Six findings, all verified, that change the shape of the fix.

### 1. `const&` buys nothing across the R/C++ boundary

The old note assumed the clip existed only to avoid handing the engine a big array. Inside C++,
`const T&` is a pointer and copies nothing. **Across the R boundary it is not.** Rcpp generates
(`FireSpread/src/RcppExports.cpp:140-142`):

```cpp
Rcpp::traits::input_parameter< const IntegerMatrix& >::type layer_vegetation(layer_vegetationSEXP);
Rcpp::traits::input_parameter< const arma::fcube& >::type layer_nd(layer_ndSEXP);
Rcpp::traits::input_parameter< const arma::fcube& >::type layer_terrain(layer_terrainSEXP);
```

Each *constructs a new object* from the SEXP and binds the reference to that temporary. R has no
`float` and no `int8`, so `pnnh_land` is `double`; converting to `arma::fcube` (float) is a
value-by-value conversion and must allocate. The rule: **R to C++ is zero copy only when the
storage type matches exactly** (REALSXP into `NumericMatrix`, INTSXP into `IntegerMatrix`), or
when aliasing deliberately with `arma::mat(REAL(x), nr, nc, /*copy_aux_mem=*/false, true)`. Since
the engine wants float and R only has double, zero copy is structurally impossible while the
master holds the landscape as an R array. No signature change fixes it.

So each fire currently pays: the `land[rr, cc, ]` subcube copy in `clip_landscape()`; three more
double copies for `[, , "veg"]`, `[, , nd_variables]`, `[, , terrain_variables]`; and three Rcpp
conversions to int, float, float. Roughly 3x the clip, allocated and freed per fire.
`docs/spread.md` already flags the second of these for the validation path; the third is
unavoidable in the current architecture.

### 2. The clip's real reason is the engine's per-call scratch

`simulate_fire_internal` allocates, per call, sized by whatever landscape it is handed
(`spread_functions.cpp:262, 292`):

```cpp
IntegerMatrix burned_ids(2, n_cell);
IntegerMatrix burned_bin(n_row, n_col);
```

At full PNNH that is 192 MB + 96 MB = **289 MB allocated and zero-filled for every fire**, most
of it never touched. Handing the engine the whole landscape would be catastrophic even with zero
copying of the landscape itself. **The clip is unnecessary if and only if the scratch stops being
sized by the landscape**, which means allocating it once per worker and reusing it.

### 3. Dropping the clip is behaviourally neutral

`clip_landscape()` clips to plus or minus `steps` around the ignition, and with `steps` steps the
maximum Chebyshev reach from the ignition is `steps - 1` (the ignition itself is step 1). The clip
boundary is unreachable by construction, and at the landscape edge the clip truncates exactly as
the full landscape does. Removing the clip is therefore not a modelling change, and the rewrite
stays checkable against current output.

### 4. The two PNNH grids are perfectly aligned

```
ignition grid  data/pnnh_images/pnnh_data_30m_buff_10000_std.tif    6090 x 3344, 30 m
spread grid    data/pnnh_images/pnnh_data_spread_buffered_30m.tif   6482 x 3712, 30 m
same CRS; x offset 0 cells, y offset 186 cells
```

So the `xyFromCell` / `cellFromXY` round trip done **per fire** (simulate.R:475-478, and
simulate.R:388-390 for the ignition points) is nothing but

```
spread_row = ignition_row + 186
spread_col = ignition_col
```

That whole block collapses to an integer add. Worth fixing whatever else happens.

### 5. The regime side needs 11% of the spread fit

`files/hierarchical_model/spread_model_samples.rds`, in RAM:

| component | dim | size | used by the regime simulator? |
|---|---|---|---|
| `fixef` | 7 x 3 x 12000 | 2.66 MB | rows `1:n_coef` (= 1:6) only; row 7 is the `area` regression |
| `rho` | 6 x 6 x 12000 | 4.03 MB | yes |
| `ranef` | 6 x 57 x 12000 | 32.05 MB | **no** (the 57 fitted focal fires' random effects) |
| `steps` | 178 x 12000 | 17.04 MB | **no** (the 178 fitted fires' steps draws) |
| `stepsU` | 12000 | 0.09 MB | yes |
| | | **55.90 MB** | live set: **6.4 MB** |

Grepped repo-wide: `ranef`, `steps` and `fixef["area", , ]` are read **only** inside `spread/` and
its `R/` helpers (`simulate_focal_metrics.R`, `figure_params_fwi.R`, `figure_burn_probability.R`,
`exploratory_steps_area.R`, `focal_simulation_functions.R`, `spread_figure_functions.R`, the MCMC
machinery). Nothing in `fire_regime/` touches them: `simulate.R:413-420` and `:604-606` and
`probability_maps.R:299-303` use `fixef[1:n_coef, , ]`, `rho` and `stepsU` and nothing else. The
split falls exactly along the paper boundary: `ranef` / `steps` / `area` are paper-1 quantities.

The ignition and escape sides are the same story in miniature:

| object | in RAM | what the simulator uses |
|---|---|---|
| `igmod` stanfit | 5.9 MB | `imod`, 8000 x 24, **1.47 MB** |
| `escmod` stanfit | 40.5 MB | `emod`, 8000 x 7, **0.43 MB** |

The stanfits stay in the global environment after extraction and are forked into every worker.
They are deeply nested lists of many small SEXPs, which is the case where R's GC mark phase does
dirty pages across a fork. `rm()` after `as.matrix()` is free.

### 6. A latent index bug, currently inert

```r
ipost <- nrow(imod)   # simulate.R:961
epost <- nrow(imod)   # simulate.R:962   <- should be nrow(emod)
spost <- dim(smod$fixef)[3]
```

Measured: `nrow(imod)` = `nrow(emod)` = 8000, so **this has not corrupted any result**. It is a
coincidence, not a correctness argument: the moment either model is refitted with a different
number of draws, `sample(1:epost, 1)` either indexes past the end of the escape posterior
(yielding `NA` coefficients) or silently ignores part of it. Note also that `spost` = 12000 while
`ipost` = `epost` = 8000, which matters for the stratification below.

**Fix the line before any re-run**, redesign or not: it is one character, and a re-run is the
moment the posteriors most plausibly change underneath it.

## Decisions taken

**DECIDED 1. The season loop moves into C++ now.** Not the R-level mask redesign the old note
proposed as step 1. That work would be thrown away (in C++ the burn state is written from
scratch), and, more importantly, the current R implementation is worth much more as an
**untouched reference oracle** for validating the rewrite than as a thing to optimise. Refactor it
and the baseline is gone.

**DECIDED 2. Multi-year simulation is consciously out of scope.** Fuel recovery, vegetation
dynamics, time-since-fire and carbon coupling are future work and are deliberately not designed
here. The target stays what it is today: independent fire-year iterations. See *Left for later*
below for the one thing that must be remembered when that changes.

**DECIDED 3. One posterior draw per iteration.** Currently `simulate_fire_season` draws a fresh
posterior index on *every fortnight*:

```r
iss <- sample(1:ipost, 1)   # simulate.R:296, ignition
ess <- sample(1:epost, 1)   # simulate.R:375, escape
sss <- sample(1:spost, 1)   # simulate.R:411, spread
```

so one simulated season is a mixture over 26 independent draws per sub-model rather than a draw
from one coherent parameter set. The consequence is that **parameter uncertainty is averaged away
within a replicate**: the between-replicate spread reported is the variance of an average of 26
draws, not the variance of one draw, and for a projections paper whose headline is uncertainty in
future burned area that understates it silently.

The new construction: **one draw per sub-model per fire-year iteration, held fixed for the whole
season; fire-level random effects redrawn per fire from the hierarchical distribution implied by
that draw's hyperparameters.** The second half is already correct within a fortnight (`sss` gives
`fixef` and `rho`, then `mgcv::rmvn` draws a fresh coefficient vector per fire); the change is
hoisting the three `sample()` calls out of the fortnight loop.

Three consequences to carry:

- **It changes results.** Mean burned area should move little; the variance across replicates will
  increase, correctly. The `steps_int_shift` calibration was tuned under the old scheme against a
  marginal size distribution, so it is probably robust, but it must be re-checked, not assumed.
- **Stratify rather than resample.** Assign replicate *i* a thinned posterior index rather than
  `sample(1:spost, 1)`: same cost, covers the posterior exactly, less Monte Carlo noise. Because
  `ipost` = `epost` = 8000 and `spost` = 12000, the three must be thinned to a common draw count
  so that "replicate *i* uses draw *i*" is coherent across the three sub-models. Doing that also
  makes the `ipost`/`epost`/`spost` bookkeeping, and its bug class, disappear.
- **The same logic applies to the climate models.** `simulations <- sample(1:nclimsim, nsim, T,
  prob = modmem$weight)` picks a GCM ensemble member per replicate-year. That is fine for
  independent fire-years, but the moment runs become multi-year, one member must be held for the
  whole trajectory or the temporal autocorrelation that drives clustered fire years is destroyed.

**DECIDED 4. This document is where the redesign lives.** Other docs point here rather than
restating it.

## The design

### The seam

> **C++ owns the landscape and the season loop. R owns all raster I/O, all model objects,
> parameter drawing, scenario orchestration and analysis.**

The C++ entry point takes: a handle to the static landscape loaded once per session; one
already-drawn parameter set for this iteration; the FWI series as a small array; the precomputed
grid offsets. It returns summary tables and a handful of small rasters. This is exactly the
"simulator as a standalone, production-extractable function" that `fire_regime/README.md` asks
for, and it is more extractable than the current 1587-line script, not less.

What must **not** move into C++: anything touching `terra`, any Stan or `brms` object, and all
analysis and plotting. In particular
`terra::extract(fwi_local, points, method = "bilinear")` inside the fortnight loop does not get
reimplemented; FWI is a 24 km raster, so over PNNH it is a few hundred cells by about 36
fortnights, a few hundred KB. Hand C++ a small float array plus the geotransform and do the
bilinear interpolation inline in about 15 lines. `terra` then never enters the loop.

### The landscape behind an `XPtr`

`Rcpp::XPtr<T>` is an R external pointer (`EXTPTRSXP`): an ordinary R object whose payload is a
raw C++ pointer plus an optional finalizer.

```cpp
// [[Rcpp::export]]
SEXP landscape_load(std::string path) {
  Landscape* L = new Landscape(path);       // reads the file, allocates float / uint8
  return Rcpp::XPtr<Landscape>(L, true);    // true = delete when R collects the handle
}
```

Four properties matter here:

1. R never copies it: it is not an R vector, so copy-on-modify does not apply.
2. R's GC marks the handle's header, not the 500 MB behind it.
3. **Allocated before the fork, it is genuinely shared.** All workers inherit the same physical
   pages, and since nothing writes to the static part, copy-on-write never fires. The whole
   redesign hangs on this property.
4. It can hold types R cannot express: `float`, `uint8_t`, `int16_t`, interleaved structs.

The footgun, and it is real: **an `XPtr` does not survive serialization or a session restart.**
`saveRDS()` writes a handle whose pointer is meaningless on reload, and dereferencing it segfaults
R with no error message. Two cheap mitigations: never save it (rebuild from the `.tif` at session
start, one read), and store a magic tag inside the struct that C++ checks before use, so a stale
handle raises an R error instead of crashing. It also does not work across a PSOCK cluster, only
fork, which is consistent with the plan.

### Scratch allocated once, and one array for burn state

The engine's per-call `burned_bin` and `burned_ids` become per-worker buffers allocated once for
the whole run:

- **Burn state**: one `uint8` array of `ncell` (24 MB), with `0` = unburned, `1` = burned earlier
  this season, `2` = burned by the current fire. The burnable test is `!= 0`; after each fire,
  walk that fire's own cell list turning `2` into `1`. Clearing is O(fire size), not O(ncell), and
  the within-season reburn ban and the per-fire visited-set are the same array. The `veg == 99`
  sentinel and `vegetation_update()` both disappear, and `veg` stays in the shared static block.
- **Burned ids**: a `std::vector<int32_t>` with reserved capacity, reused across fires, growing
  only to the largest fire seen.
- **Candidate filter**: `keep <- !burn_state[cells]`, a lookup into an array that already exists,
  replacing the per-fire landscape-sized `bitmask` allocation.

### Memory budget

| | now | after |
|---|---|---|
| static landscape | 1.15 GB copied per worker | ~500 to 580 MB shared once (float + uint8) |
| dynamic per worker | the full 1.15 GB array | 24 MB (one `uint8` burn-state array) |
| per-fire allocation | ~3x the clip, plus 289 MB of engine scratch if unclipped | none |
| parameters per worker | whole posteriors forked (56 + 5.9 + 40.5 MB of objects) | one slice: 6x3 + 6x6 + 1 = 55 doubles, 440 bytes |

At 24 MB of mutable state per worker, the worker count stops being set by RAM.

### Parallelism and reproducibility

Keep `mclapply` / fork at the R level and keep the C++ **single-threaded**, using R's own RNG via
`RNGScope`. Two payoffs: no thread-safety questions about the R API, and, critically for
validating the rewrite, **if C++ uses R's RNG and draws in the same order the results are
bit-identical to the current implementation.** That turns a distributional comparison into an
exact test. A faster per-worker PRNG can be swapped in later if profiling asks for it.

The one place this needs care is `sample(x, size, replace = FALSE, prob = ...)` for the ignition
locations, which uses R's `ProbSampleNoReplace`. Reproducing it exactly is about 20 lines and is
required for bit-identity.

### The lean parameter file

Build, once, a small `spread_sim_params.rds` (or one file for all three sub-models) holding only
what the simulator generates from: `fixef[1:6, , ]`, `rho`, `stepsU`, the sliced `imod` and
`emod`, the FWI standardisation constants (`fwi_mean_spread`, `fwi_sd_spread`, `ls_fwi_spread`)
and the parameter support. About 8 MB before thinning, and it carries no trace of which fires
were fitted. `spread/` keeps reading the full fit object; nothing breaks (verified by the
repo-wide grep in finding 5). This is what the production side ships alongside the two packages,
and what the C++ constructor receives.

### Memory layout: AoS or SoA

Two terms, because both appear here and they are opposites:

- **SoA, struct of arrays**: one array per variable, `elev[i]`, `wdir[i]`. This is what R does now
  and what `arma::fcube` does (each slice is a layer). Variable-contiguous.
- **AoS, array of structs**: one array whose elements hold all variables of one cell,
  `cells[i].elev`. Cell-contiguous.

The unit of memory transfer is a **64-byte cache line**: reading one `float` from RAM physically
fetches 64 bytes, so performance is largely "how many of the bytes dragged in are actually used".
On the current machine (Ryzen 7 2700X): L1d 32 KB per core, **L2 512 KB per core**, L3 2 x 8 MB
(one pool per 4-core complex, so with 8 workers each core effectively has ~2 MB, not 16), 8
physical cores with SMT, 31 GB RAM.

The landscape wants **AoS**, because the kernel reads all of a cell's variables together
(`layer_terrain.tube(r, c)` gathers three values of one cell). Under SoA those three sit
`n_cell * 4` bytes apart, megabytes in a big clip, so evaluating one neighbour drags in 5 x 64
bytes to use 20. Under AoS one 64-byte line holds three whole cells
(`struct Cell { float vfi, tfi, elev, wdir, wspeed; uint8_t veg; }`, 24 B padded, 577 MB for the
landscape; SoA would be 505 MB).

Honest estimate: **1.5x to 3x on the kernel, not the 5x the cache-line arithmetic suggests.**
Fires revisit cells (each is evaluated by up to 8 burning neighbours) and a fire front's working
set mostly fits in 512 KB of L2, so after first touch both layouts are cheap. The gain is
concentrated on first touch and on large fires. This is why the layout is a *measured* second
step, not a commitment (see *Open decisions*).

The output accumulators are the opposite case and want **SoA**: one preallocated vector per
column, which is what an R data.frame is anyway. That also kills the quadratic `rbind` growth.

### Outputs stay tiny

Reduce inside the worker. `burned_ids_list` should probably not be returned at all at regime
scale: it is the same 10^9-cell mistake `docs/spread.md` flags for the validation path. Fire-level
records should be summary rows appended to preallocated vectors, and burn-probability maps should
be accumulated into one counter raster inside the worker rather than reconstructed afterwards from
per-fire cell lists (which is what `map_burnprob()` does now, and why `burnprob()` blew the C
stack, simulate.R:665).

## Open decisions

Three, and the next session should start here.

### A. Move A now, Move B deferred?

The redesign requires a new entry point in any case, because the current exported API is
incompatible with a C++ season loop for three independent reasons: per-call landscape-sized
scratch (finding 2), an `arma::fcube` landscape built from R SEXPs (finding 1), and an R
allocation on return, so the boundary is crossed per fire rather than per season.

- **Move A (required, additive):** a `Landscape` type, an allocation-free kernel taking
  `const Landscape&` plus caller-owned scratch, and the season driver on top.
  **`simulate_fire_compare`, `simulate_fire_compare_veg`, `simulate_fire_animate` and
  `simulate_fire_internal` are not touched**: the spread paper's validation path, the ABC-SMC
  fitting and `R/focal_simulation_functions.R` depend on those signatures and are mid-paper. Share
  `spread_one_cell_prob` between old and new rather than duplicating the probability logic.
- **Move B (optional):** switch the kernel's landscape from `arma::fcube` (SoA) to AoS.

Recommendation: **do A now, defer B until measured.** The certain win is A (removing 289 MB of
scratch per fire, ~3x clip copying, and the double-to-float conversion); B is probable but
unmeasured. The one thing to commit to now, because it makes B nearly free later, is that **the
new kernel takes a `const Landscape&` of our own type, not three `arma::fcube`s.** Then the
interleaving question is an internal change to one struct's accessors, A/B-testable in an
afternoon with no API churn. Keeping arma cubes in the new signature would make B a rewrite.

### B. Where does the new code live?

Iván Renison's argument for putting the simulator in an Rcpp package (compiler flags, no
recompilation) is correct, and there is a concrete trap here:

```
~/dev/FireSpread/src/Makevars   ->   PKG_CXXFLAGS = -ffast-math -march=native
~/.R/Makevars                   ->   does not exist
R CMD config CXXFLAGS           ->   -g -O2 ... -fstack-protector-strong -D_FORTIFY_SOURCE=3
```

A package's `src/Makevars` applies **only when that package is built**. `sourceCpp()` never sees
it; it uses R's Makeconf plus `~/.R/Makevars`, which does not exist here. So
`src/sample_triplets_weighted.cpp` compiles today at plain `-O2` with stack protector and fortify
on, no `-march=native`, no `-ffast-math`, while FireSpread compiles with both. The kernel calls
`expf`, `cosf`, `sinf`, `atanf` **per neighbour evaluation**, so `-ffast-math` is a large part of
why FireSpread is as fast as it is. Putting the season driver in this repo's `src/` and pulling
the kernel in as an inline header would **recompile the kernel into the driver's translation unit
under the driver's weaker flags, silently**: same source, same behaviour, quietly slower, with
nothing in the output to say so. That rules out `src/` + `sourceCpp()`.

Three options:

| | what it is | cost |
|---|---|---|
| **(a)** driver in this repo's `src/`, via `sourceCpp()` | simplest to start | loses FireSpread's flags silently; recompiles every session; ruled out by the above |
| **(b)** everything into FireSpread | one package, gets the flags | FireSpread stops being about fire spread and acquires ignition rates, escape, FWI, fortnights, while paper 1 cites it as the spread engine |
| **(c)** new sibling package `FireRegimeSim`, `LinkingTo: FireSpread` | FireSpread unchanged and still the paper-1 citable engine; `FireRegimeSim` is the paper-2 artifact and the production hand-off (install two packages plus the ~8 MB parameter file, no analysis repo needed); one implementation of the spread probability; `LinkingTo: FireSpread (>= x)` catches breaking header changes at install | one more sibling repo to keep in sync, and a small `inst/include/` restructure of FireSpread |

Recommendation: **(c)**, as a new `~/dev/FireRegimeSim` mirroring how `../FireSpread` sits beside
this repo. Explicitly **not** absorbing or forking the engine: duplicating the spread kernel is how
the two papers end up describing simulators that have quietly diverged.

### C. Within (c), header-only or registered C-callable?

- **Header-only** (kernel `inline` in `inst/include/FireSpread/`): simplest, but it inlines into
  the driver's translation unit and so takes the driver's flags. Matching them means putting
  `-ffast-math` in `FireRegimeSim/src/Makevars` too, and that is the uncomfortable part:
  `-ffast-math` implies `-ffinite-math-only`, so NaN checks can be optimised away. The ignition
  code has real NaNs (`iprob_h[is.na(iprob_h)] <- 0`, simulate.R:328). Moving that check into C++
  under `-ffast-math` is a silent-wrong-answer bug, not a slow one. If this route is taken,
  missingness must be handled with an explicit sentinel or mask, never NaN semantics.
- **Registered C-callable** (`R_RegisterCCallable` in FireSpread, `R_GetCCallable` in
  `FireRegimeSim`; the shared header then declares only the POD `Landscape` type and the
  signature): the kernel is compiled **once, inside FireSpread, always with
  `-ffast-math -march=native`**, and the driver compiles with `-march=native` only. The indirect
  call happens once per fire, not per cell, so its cost is unmeasurable, and a change to
  FireSpread's kernel internals no longer forces a `FireRegimeSim` rebuild. About 15 lines of
  boilerplate. Struct-layout compatibility needs a version field checked at runtime.

Recommendation: **C-callable.** It removes the flag-divergence trap permanently and keeps
`-ffast-math` off the statistical code, where it is genuinely dangerous.

Separately, note that `-march=native` makes the `.so` non-portable. Fine for these machines, but
a portable build target is needed if the production side ever ships binaries.

## Order of work, once the decisions above are taken

1. **Cheap fixes that are correct under any architecture, and do not disturb the reference
   behaviour of the spread path**: `epost`; the `xyFromCell` / `cellFromXY` round trip to `+186`;
   the quadratic accumulators; `rm()` the stanfits after extraction.
2. **Build the lean parameter file**, with the three posteriors thinned to a common draw count.
3. **Hoist the posterior draw to the iteration** (DECIDED 3) in the current R code, and re-run a
   small `nsim` to see how much the between-replicate variance moves and whether
   `steps_int_shift` needs re-tuning.
4. **Freeze the current R implementation as the reference oracle** at that point. Record a fixed
   seed and a small `nsim`, and keep its output.
5. **Move A** in the chosen package layout, using R's RNG in the same draw order, validated for
   bit-identity against (4).
6. **Measure**: peak RSS and wall clock at 2, 8 and 14 workers, before and after.
7. **Move B** only if (6) says the kernel, not the memory traffic, is the remaining cost.

Steps 1 to 3 are worth doing **before** the TODO #7 re-run, since that re-run is a multi-day job
and this is the difference between 3 workers and all of them.

## Left for later (deliberately not designed here)

Multi-year simulation, with fuel recovery and vegetation dynamics, is future work (DECIDED 2).
One thing must be remembered when it arrives, because it is expensive to discover late:

> **`vfi` becomes dynamic the moment vegetation does.**
> `vfi_calc(vegetation, ndvi)` (`R/flammability_indices_functions.R:43`) is a function of the
> vegetation class and NDVI, while `tfi_calc(elevation, aspect, slope)` (:71) is purely static.
> So a landscape that only ever set `veg` to the non-burnable sentinel, as today, can treat `vfi`
> as static; a landscape where vegetation actually changes class cannot.
>
> The clean answer is **not to store `vfi` at all**: store `veg` (`uint8`, dynamic) and `ndvi`
> (static, quantisable to `uint8`) and compute `vfi` in the kernel through a 5 x 256 lookup
> table. One table read per cell, post-fire vegetation change propagates into flammability
> automatically, and one dynamic float layer disappears. Deciding this before writing multi-year
> state is the point; it is the thing that is expensive to change later.

Also for that day: years stop being a parallel dimension (`simulate.R:538` runs
`foreach(yy = years)`, valid only because years are independent draws with no carry-over), the
replicate becomes the only parallel dimension, and time-since-fire replaces the boolean burn state
so that the within-season reburn ban and between-year fuel recovery become the same mechanism.
