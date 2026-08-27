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

---

# Computational redesign of the season simulator (design note, 2026-08-27)

> **Status: design note, nothing implemented.** Written while the regime re-run (TODO #7) is
> still pending, so this is the moment to decide whether to re-run `simulate.R` as it stands or
> restructure first. Read alongside `docs/spread.md` → *Cost and parallelization*, which
> documents the memory-clean pattern the validation path already uses.

## The problem, stated precisely

`simulate.R` stalls at **2–3 workers on a 32 GB machine**, while the spread-validation path in
`spread/validation_simulate.R` runs comfortably on 14. The difference is not the model, it is
**mutable landscape state**.

The validation path is memory-clean by construction (`docs/spread.md`): one tile in RAM at a
time, forked workers, *nothing written to the landscape*, so the array stays shared
copy-on-write across all workers for free.

The season simulator cannot use that trick as written, because it carries a mutable landscape:

```r
pnnh_land_dyn <- pnnh_land                                 # simulate.R:277, per season
...
pnnh_land_dyn <- vegetation_update(pnnh_land_dyn, burned)  # simulate.R:464, per fire
```

Under `registerDoMC` (fork), the first write in each worker dirties the pages and the OS
materialises **a private copy of the whole landscape array per worker**. Copy-on-write gives
nothing back. Three further costs sit on top:

1. `vegetation_update()` (simulate.R:210–225) allocates the veg layer **twice more** per call —
   `as.vector(land[, , "veg"])`, then `matrix(veg_vec, ncol = ncol(land))` — before assigning
   back into the 3-D array, which is itself a full-array copy.
2. The candidate-cell filter (simulate.R:477–481) rebuilds a `bitmask` of length
   `max(cells_pnnh_dyn, cells_burned)` **on every fire**, i.e. a landscape-sized allocation per
   fire, to do a set difference.
3. Both accumulators grow quadratically: `size_fwi_table <- rbind(size_fwi_table, mmat)` and
   `burned_ids_list <- c(burned_ids_list, list(burned))` copy the whole accumulator each fire.

So the ceiling is structural, not a hardware shortfall. More RAM would buy more workers without
fixing any of this.

## The key observation: the engine never sees the full landscape

`simulate_one_fire()` (simulate.R:142–176) clips before simulating:

```r
land_clipped <- clip_landscape(ig_rowcol[, 1], steps, land)
fire_sim <- simulate_fire_compare(
  layer_vegetation = land_clipped[, , "veg"],
  layer_nd         = land_clipped[, , nd_variables],
  layer_terrain    = land_clipped[, , terrain_variables], ...)
```

`clip_landscape()`'s own comment already says it exists "to simulate a fire using only the
necessary RAM". **The C++ engine only ever reads the clip.** Therefore the burned state only has
to be *correct inside the clip* — it never has to be written back into the full landscape at all.

That is the whole redesign.

## The redesign

**Keep the landscape read-only. Carry the dynamic state as a separate, small mask, and stamp it
into the clip.**

```r
# Season state: one landscape-shaped mask, allocated once, mutated in place.
burned_mask <- matrix(FALSE, land_rows, land_cols)   # or raw() / bit-packed

# In clip_landscape(): build the veg layer from the static array, then stamp.
rr <- row_lwr:row_upr; cc <- col_lwr:col_upr
veg <- land[rr, cc, "veg"]                # static array, never modified
veg[burned_mask[rr, cc]] <- 99L           # within-season reburn ban, applied locally

# After each fire, mutate the mask in place — no landscape copy.
burned_mask[cbind(burned[1, ], burned[2, ])] <- TRUE
```

Consequences:

- `pnnh_land` is **never written to**, so it stays genuinely shared copy-on-write across every
  forked worker. Per-worker mutable state drops from a full multi-layer `double` array to one
  `logical` (or `raw`) matrix — roughly `ncell × nlayers × 8` bytes down to `ncell × 1`.
- The per-fire candidate filter becomes `keep <- !burned_mask[cells_pnnh_dyn]` — a lookup into a
  mask that already exists, instead of a landscape-sized allocation per fire.
- Subset the **three engine arguments directly** out of the static array rather than
  materialising an intermediate `land[rr, cc, ]` cube — the same micro-optimisation
  `docs/spread.md` already records for the validation path, which doubles the copying if skipped.
- Preallocate `size_fwi_table` (or collect rows in a list and `rbindlist()` once) to kill the
  quadratic growth. `burned_ids_list` should probably not be returned at all at regime scale —
  see *Outputs* below.

Worth measuring before and after rather than trusting the argument: `gc()` peak, and wall-clock
at 2, 8 and 14 workers.

## Should the season loop move into C++?

Probably yes, and for reasons beyond speed:

- **One mutable landscape behind a pointer.** No R copy-on-modify semantics, no per-fire
  allocation, mutation genuinely in place.
- **Type control.** R stores essentially everything as 8-byte `double`. Vegetation is 8 classes
  — one byte. Time-since-fire is a small integer — two bytes. In C++ that is an 8× and 4×
  reduction on exactly the layers that have to be per-worker mutable. R cannot express this
  (`raw` is one byte but awkward, and there is no int8/int16 vector type). At 100-year
  simulations this stops being a micro-optimisation and becomes the deciding constraint.
- **One boundary crossing per season** instead of one per fire.

The natural seam: **the season (or the whole multi-year run) goes into C++; parameter drawing,
scenario orchestration and all the analysis stay in R.** That preserves the design intent in
`fire_regime/README.md` — the simulator as a standalone, production-extractable function — and
in fact strengthens it, since a C++ season function with an R wrapper is more extractable than a
1500-line R script.

What it costs: interactive debuggability, and the ease of swapping a sub-model. Both matter
during development and matter less once the structure settles. Do the R-level mask redesign
first — it is small, testable against the current output, and it is the same change either way.

## What changes when a simulation is 100 sequential seasons

This is the target design (fuel recovery, vegetation dynamics, eventual carbon coupling), and it
changes the parallel structure qualitatively.

**1. Years stop being a parallel dimension.** `simulate.R:538` currently runs
`foreach(yy = years)` — valid *only* because years are independent draws with no carry-over.
Once vegetation persists between seasons, year *t+1* depends on year *t* and the year loop is
strictly sequential. **The replicate (and scenario) becomes the only parallel dimension.** That
is fine — hundreds of replicates is what the science needs anyway — but it means each worker now
owns a landscape for the whole 100-year run, so per-worker memory is unavoidable rather than
incidental. Getting it small is the whole game.

**2. Split the landscape by mutability.** This is the central design decision:

| | Contents | Lifetime | Type |
|---|---|---|---|
| **Static** | elevation, slope, aspect, northing, distance-to-roads/houses — everything that never changes | allocated once, **shared read-only across all workers** | as-is |
| **Dynamic** | vegetation class, time-since-fire, fuel/biomass state | **one per replicate**, mutated every year | int8 / int16 / float32 |

Order-of-magnitude, for a 12 M-cell landscape: dynamic state as `int8` veg + `int16` TSF + two
`float32` fuel layers ≈ 130 MB per worker, so 16 workers ≈ 2 GB. The current design's full
`double` array is ~50× worse per worker. The static stack, however big, is paid for **once**.

**3. Replace the boolean burn flag with time-since-fire.** Within-season reburn ban and
between-year fuel recovery then become the same mechanism: `TSF == 0` means "already burned this
season, non-burnable"; flammability recovers as a function of TSF thereafter. The special case
disappears, and the `veg == 99` sentinel goes with it.

**4. Outputs stay tiny — keep them that way.** The plan (≈5 saved rasters per period, plus
annual scalar summaries: burned proportion, forest cover, later carbon stocks) means each
100-year replicate returns a few small rasters and a ~100-row table. **Reduce inside the
worker**; never accumulate per-fire burned-cell lists across 100 years — at regime scale that is
the same 10⁹-cell mistake `docs/spread.md` already flags for the validation path. Fire-level
records, if wanted, should be summary rows appended to a preallocated table.

## Order of work

1. Mask redesign at the R level; verify it reproduces current output exactly on a small `nsim`.
2. Measure: peak RSS and wall-clock at 2 / 8 / 14 workers, before and after.
3. Kill the quadratic accumulators.
4. Only then decide on the C++ season loop, informed by (2).
5. Design the dynamic-state struct (veg + TSF + fuel) before writing any multi-year code — it is
   the thing that is expensive to change later.

Steps 1–3 are worth doing **before** the TODO #7 re-run, since that re-run is a multi-day job
and this is the difference between 3 workers and all of them.
