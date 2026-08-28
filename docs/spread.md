# spread — spread model fitting (paper 1)

> **Status: scaffold.** High-level content is accurate (from the old repo's inventory); deep
> method/statistics detail (marked _TODO_) is written as the scripts are migrated and read.

The largest, most complex module. Fits the fire spread model in two stages, driving the external
`FireSpread` cellular-automaton engine (`../FireSpread`).

> **Note:** the parameter-**estimation method changed** from the thesis version (see the PhD
> thesis, chapter 4 + supplementary — link in `CLAUDE.md` / root `README.md`). The **evaluation**
> of the model is also going to change. Document the *current* method here; note deltas from the
> thesis where useful.

> **Notation in the manuscript deliberately differs from the thesis.** Beyond translating the
> Spanish (IIV → VFI, IIT → TFI, quincena → fortnight, pasos → steps, solapamiento → overlap,
> orientación norte → northness, and the five vegetation classes), two symbol clashes the thesis
> tolerated are fixed in `manuscript-spread/ijwf/spread-paper.tex`:
>
> - the flammability-index coefficients are `a_v`, `b_v`, `c_v`, not `α_v`, `β_v`, `ω_v` — the
>   old names collided with the spread coefficients `β`;
> - aspect is `Φ`, not `L` — the old name collided with the vector of lower bounds **L**.
>
> The thesis's "previa redundante" is called a **placeholder prior** in the manuscript, and it is
> no longer redundant: stage 1 now uses a plain uniform prior over [**L**, **U**]. Do not
> "correct" the manuscript back to thesis notation.

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
of individual fires.

Code: `R/spread_validation_functions.R` (shared metrics),
`spread/validation_ignition_cells.R` (run once), `spread/validation_simulate.R` (the run).

### Why not classical train/test

The argument belongs in the paper's discussion, in 2–3 paragraphs, citing Parisien et al. 2020
(burn-probability models are evaluated against emergent regime properties, not point
predictions) and the pattern-oriented-modelling literature (Grimm, Hartig).

- **57 fires** is already small for a 6-parameter hierarchical model with sign-constrained
  priors, a multivariate logit-normal on the transformed parameters, and an auxiliary
  `log(area) ~ log(steps)` regression that depends on the fitted `κ_f`. Holding out 20 % would
  degrade both the hyperparameter estimates and the auxiliary regression that corrects the size
  bias using the fires with unknown ignition point.
- The size distribution is **heavy-tailed and peaked** (high peak at small fires, thin long
  tail). Estimating it from ~50 fires is not a stable target for a held-out test.
- The model is **deliberately underparameterized** for the process: sigmoid functional forms,
  sign restrictions, fixed `τ`, restricted parameter ranges. Overfitting is not the failure mode
  cross-validation is designed to catch.
- The hierarchical structure is its own regularizer: per-fire `β_f` are shrunk toward the
  population posterior, so a held-out fire's "test" coefficients would mostly reflect the
  population mean plus noise.
- The aim is **regime-level pattern reproduction**, not point prediction of individual fires.

Framing: *we evaluate the simulator's ability to reproduce statistical patterns that emerge
from real fires.*

What is deliberately **not** done: per-cell stop-mechanism attribution (whether an edge cell is
unburned because propagation refused or because `κ` ran out). The distinction is real but adds
interpretive complexity the paper does not need — one sentence in the discussion and move on.

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

Two elongations, not one. `elongation` is **direction-free** — the ratio of the principal axes,
however the fire happens to point — and is the only one both sides of the comparison can supply,
because the 184 observed fires without an ignition point were exported with no wind layer.
`elong_wind` is elongation **along the wind axis**: spread along it over spread across it, so
below 1 means the fire stretched *across* the wind, and it can never exceed `elongation`. It is
computed for the simulated fires only.

The axis it is measured against is the **circular mean of `wdir` over the cells the fire burned**,
not the fixed 293° the tiles were driven with: WindNinja steers the field by terrain, and in the
smoke test the per-fire mean ranged over 261–335°. The sublandscape's circular mean is recorded
too (`wdir_land_deg`) — fixed before the fire runs, so free of any feedback from its shape — with
the mean resultant length `rbar` of each, which says whether the field was coherent enough for a
mean direction to mean anything. `fire_shape()` also returns the burned cells' covariance entries
(`cov_ee`/`cov_nn`/`cov_en`), from which `elongation_along()` recovers elongation against *any*
reference axis after the fact — including the fixed 293° needed to treat the simulated fires
exactly as the observed ones must be treated — without re-running the simulation.

**3. Per-fire spatial signature.** For each fire, a **donor-centred conditional logit**: one
stratum per burned cell with at least one burnable unburned neighbour, members = that cell's
burnable neighbours, response = burned. This is literally the simulator's own Bernoulli trial
set; holding the donor fixed conditions out the fire, the weather and the donor itself, and the
shared intercept drops out. Fitted with `survival::clogit(method = "exact")` — strata have up to
8 members and often several cases, where Breslow/Efron genuinely differ. Donors subsampled to
1500 per fire.

**Predictors: `vfi` and `tfi` only, both in one multiple regression.** The slope and wind terms
of `spread_one_cell_prob()` are *directional* — they depend on which cell the fire actually
arrived from — and for an observed fire the burn order is unknown, so the donor is a guess at
the arrival direction, not a measurement. Including them would compare something computable for
simulated fires against something not computable for observed ones. Their omission costs
nothing: an edge contrast has no power for them anyway (see below). Multiple rather than
univariate, because `vfi` and `tfi` are correlated through vegetation and topography and the
univariate coefficients would each absorb part of the other's effect.

Coefficients are reported **on the original predictor scale**. `edge_clogit()` standardizes
per fire for numerical conditioning and divides the estimates back by the scale; centring
cancels in a conditional likelihood, so only the scale has to be undone.

Because the predictors no longer depend on the donor, **the landscape needs only `veg`, `vfi`
and `tfi`** — no elevation layer, no wind field, no WindNinja. That is what makes it feasible
to run the signature on **all 241 mapped fire polygons**, not just the 57 with a known ignition
point, which removes the size-bias of the focal subsample from this analysis. See *Reduced
landscapes* below.

This replaces an earlier 1:1 "one unburned edge cell + one random burned neighbour" pairing,
which was tested and is strictly weaker: on the 57 observed
fires it leaves the `vfi` signature at noise where the donor-centred version resolves it.
Observed values (57 focal fires, original scale, all converged):

| | median | IQR | frac > 0 | < 100 ha | 100–1000 ha | > 1000 ha |
|---|---|---|---|---|---|---|
| `vfi` | 0.578 | [0.20, 1.18] | 0.86 | 0.06 | 0.78 | 0.59 |
| `tfi` | 1.881 | [−1.01, 4.05] | 0.65 | 0.15 | 1.55 | 2.53 |

Both strengthen with fire size, so the comparison must condition on `log10(area)`. Note these
are *edge-local summary statistics*, not estimates of the model's β (the fitted per-fire values
are an order of magnitude larger: `vfi` median 11.9, `tfi` 4.5). What matters is whether
observed and simulated distributions of the statistic agree.

Edge extraction stays **in R** — measured at 49 ms/fire mean over the 57 focal fires, 0.45 s for
the largest (300 k cells). There is no case for modifying `FireSpread`'s output contract.

### Reduced landscapes for the fires without an ignition point

The signature needs `veg`, `vfi`, `tfi` and the rasterized burn polygon for every mapped fire.
`vfi` needs vegetation + NDVI; `tfi` needs elevation + slope + aspect — so the **GEE band set is
unchanged**, only the fire selection is. What is skipped on the R side is WindNinja, which is
what made the fire-wise landscapes slow.

The observed set is assembled from **two sources**, because the 57 focal fires already have
everything the signature needs — `data/focal_fires/landscapes/*.rds` carry `veg`, `vfi`, `tfi`
and the burned layer in the same arrays used for fitting. Only the remaining fires are exported.

- **The 57 focal fires** — read straight off disk. Nothing to re-export.
- **The 184 fires with unknown ignition point** — two interchangeable drivers in
  `~/dev/fire_spread-gee/`: the Code Editor script `"Landscapes export for signature validation
  (fires without ignition point)"` and its Python twin
  `python/export_signature_landscapes.py`. **Prefer the Python one for the whole batch** — the
  Code Editor's "run all tasks" plug-in gives up partway (it submitted 129 of 184 before the
  browser died; nothing was wrong with the exports, all 129 succeeded), while the Python driver
  submits from outside the browser, derives the fire list at run time so it cannot drift, and
  skips fires whose task already exists so it is re-runnable. Exports each fire's own
  bounding box + 150 m rather than the pre-computed landscape rectangle — the analysis is
  edge-local, so that is all it needs. Same bands, same `EPSG:5343`; Drive folder
  `raw data from GEE signature`, file prefix `fire_signature_raw_`. Deliberately a **separate
  script** from `"Landscapes export"`, so the provenance of the 57 fitting landscapes stays
  reproducible.
- **R — still to write.** A second loop in `data_prep/landscapes_preparation.R` building the
  three-layer arrays from those 184 exports. No WindNinja, no ignition point, no `steps`; the
  burned layer comes from the export's `burned` band, and `vfi`/`tfi` reuse `build_landscape()`
  unchanged.

The script excludes the 57 by an explicit `fire_id` list taken from the landscape **filenames**,
not from `ig_points`: `ig_points.distinct("Name")` has only 53 entries, because some fires were
split in two after the ignition points were drawn, so it does not reproduce the set. 241 − 57 =
**184**.

> **Homogeneity trap.** Splitting the observed set across two vintages could have made it
> inconsistent in two ways. One is real and must be honoured; the other was checked and is not a
> problem.
>
> 1. **Vegetation crosswalk — real.** The focal landscapes used urban → wet forest
>    (`veg_crosswalk("forest")`, the fitting convention), *not* the non-burnable convention used
>    for the simulation tiles. The 184 must use `"forest"`.
> 2. **GEE asset vintage — checked, no problem.** The focal fires were exported from the legacy
>    `users/IvanBarbera/Fire_spread/{vegetation_ciefap_wwf, NDVI_mean_ts}`, the 184 from the
>    migrated `projects/ivanbarbera-001/assets/{vegetation_ciefap_wwf_imported,
>    NDVI_mean_ts_1998-2022}`. Compared directly on 2026-08-21 over a test fire at 30 m:
>    `max|old − new| = 0` for both vegetation and NDVI. The migrated rasters are pixel-identical
>    and the band order is unchanged, so the two vintages are interchangeable.
>
> The new NDVI asset does name its bands `b_<year>`, and selection is by name — positional
> indexing happens to give the same answer here (index 16 is `b_2014` in both), but relying on
> that is needless risk.
>
> `patagonian_fires_spread` keeps its legacy path, verified still resolving with its 241
> features. `projects/ivanbarbera-001/assets/patagonian_fires` has only 238, missing
> `1999_1546963766`, `2003_1215845321` and `2014_-1075171770`.

**4. FWI-stratified version.** Repeat 2 and 3 within FWI quartiles — the model's most
distinctive structural claim is that spatial coefficients move with FWI. The second simulated
dataset with FWI drawn uniformly across the modeled range (for coverage where observed data is
sparse) is **deferred**, not part of the current run; revisit if the stratified test turns out
to be starved at high FWI.

### What each test can and cannot diagnose

**No edge-based regression can test the wind or slope terms.** Two reasons, and they compound.
First, both terms are *directional*: they are functions of which cell the fire arrived from, and
for an observed fire the burn order is unknown, so there is nothing to measure. Second, even
granting a donor, the contrast has no power — around a perimeter the donor→receiver direction is
the outward normal, hence isotropic by construction, and an edge donor's already-burned
neighbours are systematically the ones the fire arrived *from*, i.e. upwind, which cancels the
true effect. Measured on the 57 observed fires, both the 1:1 and the donor-centred schemes
return a flat, zero-centred `wind` coefficient (median 0.00, 51 % > 0). Wind and slope are
tested through **fire shape** instead, where the observed signal is strong. This promotes the
shape metrics from "cheap complement" to a primary analysis.

### The elongation gap, and why it is not a bug

The pilot showed simulated fires far rounder and less wind-aligned than observed ones. Since
FireSpread is known to be able to produce strongly elongated fires, this was investigated as a
suspected coding error before being accepted as a result. **It is not a bug.** What was checked,
in order:

1. **Wind layers.** `wspeed` (divided by the frozen `wind_sd = 1.464333`) has median 2.575 in
   tile 3 and 2.547–2.645 across focal-fire landscapes; `wdir` is in radians, median 5.114 rad
   = 293° in the tiles and 277–323° across focal fires. Tiles and fitting landscapes are on the
   same scale. (Masked cells carry −9999 in the non-`veg` layers; they are `veg == 99` so the
   automaton never reads them, and `donor_strata()` excludes them.)
2. **The MVLN → parameter chain.** Drawing from the population and applying
   `invlogit_scaled` reproduces the fitted per-fire random effects closely — intercept, `vfi`,
   `tfi`, `slope` and `wind` quantiles all line up (e.g. `wind` median 3.58 simulated against
   4.90 fitted). No logit-scale or bounds error. Note `draws$ranef` row 6 (`steps`) is stored on
   the **natural** scale while rows 1–5 are on the logit scale — a trap worth remembering.
3. **The engine's wind term, in isolation.** On a synthetic flat landscape (`vfi = tfi = 0`,
   constant elevation, uniform wind) the burned centroid travels toward `(wdir − 180) mod 360`
   for every direction tested, to within 1.4°:

   | wdir (from) | 0 | 45 | 90 | 135 | 180 | 225 | 270 | 293 | 315 |
   |---|---|---|---|---|---|---|---|---|---|
   | expected travel | 180 | 225 | 270 | 315 | 0 | 45 | 90 | 113 | 135 |
   | observed travel | 180.4 | 225.1 | 270.6 | 314.8 | 1.0 | 45.6 | 90.0 | 111.6 | 135.0 |

   The convention is right too: `nb_angle[k]` is the compass bearing of the direction the fire
   comes *from*, so `cos(angle_k − wdir)` peaks when the fire moves downwind.
4. **Fitted parameters on their own landscapes.** Simulating each focal fire with its own fitted
   random effect at its own ignition point (159 runs over 53 fires) reproduces **size** well —
   median 512 ha simulated against 434 ha observed — but not shape: elongation 1.58 against
   2.42, wind-aligned fraction 0.33 (i.e. random) against 0.49.

So the gap survives with the right parameters, on the right landscapes, at the right ignition
points. It is a property of the fitted model, not of the tiles, the ignition
rule or the code. Consistent with this, the stage-1/2 fit achieves a median spatial overlap of
0.53 — location and footprint are matched, anisotropy is not, and the overlap statistic is not
sensitive to it.

#### Why the model cannot make an elongated fire

**The automaton's spread *rate* is isotropic; only its spread *probability* is directional.**
The front advances at most one cell per step in each of the eight directions, and the wind term
`cos(angle_k − wdir) · wspeed · b_wind` changes *whether* a neighbour ignites, never *how fast*
the front moves. So the downwind front can never outrun the flanks — which is exactly what makes
a real fire a cigar.

Once the wind term is strong enough to matter it drives downwind `p → 1` and upwind `p → 0`.
Downwind *and lateral* cells then both burn essentially every step, so the burned set is the
downwind half of the Chebyshev ball of radius `steps` — a half-lobe whose principal-axis
elongation is fixed by geometry:

- half-disc: `sqrt((R²/4) / (R²/4 − (4R/3π)²))` = **1.892**
- half-square (the Chebyshev reachable set): **2.0**

Measured on a flat synthetic landscape (`vfi = tfi = 0`, uniform wind), sweeping the no-wind
spread probability `p0` against `b_wind`, elongation never escapes that bound:

| `p0` \ `b_wind` | 0 | 1 | 2 | 4 | 8 |
|---|---|---|---|---|---|
| 0.05 | – | 1.58 | 1.51 | 1.66 | 1.84 |
| 0.20 | 2.14 | 1.39 | 1.62 | 1.79 | 1.84 |
| 0.50 | 1.01 | 1.60 | 1.84 | 1.83 | 1.84 |
| 0.90 | 1.00 | 1.05 | 1.31 | 1.92 | 1.85 |

Note the columns: **raising `b_wind` does not raise elongation.** Past `b_wind ≈ 4` every row
collapses onto 1.83–1.85 regardless of the base flammability — the wind term has saturated and
the shape is pure geometry.

The one regime that does produce cigars is marginal propagation, where `p` is low enough that
the *effective* front speed differs between downwind and lateral. With `upper_limit = 0.5`,
`p0 = 0.05`, `b_wind = 2` the simulator reaches elongation **4.99** — but the fire is 931 cells,
84 ha. **The model can be elongated or large, not both.**

And the fitted fires sit firmly in the saturated regime: the fitted `wind` coefficient has median
4.90, so the downwind-to-upwind logit swing `2 · b_wind · wspeed` has median 25, and **82 % of
fires exceed a swing of 6** — more than enough to pin `p` at 0 and 1.

Against that ceiling, **63 % of the 238 mapped fires are more elongated than the model can be
(1.9), rising to 79 % among fires over 1000 ha**; the observed distribution runs 1.33 / 2.20 /
3.80 at the 10th / 50th / 90th percentiles, with a maximum of 8.0.

This is the paper's main negative result, and it is a structural statement rather than a
tuning failure: no value of the fitted parameters can fix it. Reproducing fire shape would need
a term the model does not have — either a front that advances more than one cell per step
downwind (rate anisotropy), or a spread probability capped well below 1 combined with a much
larger `steps` budget, so that the front speed itself becomes directional. Worth one paragraph
in the discussion as a concrete direction, not a fix attempted here.

A secondary contributor worth naming: the wind field is spatially uniform in direction and
near-constant in magnitude (WindNinja at 4 m/s), in both fitting and simulation, so the fitted
coefficient has no way to express the day-to-day gustiness that drives real head-fire runs.

**This is also the likely explanation for the size mismatch**, and it supersedes the
focal-selection story written here earlier, which was wrong. The `steps` distribution is fine:
all 235 fires inform it, and the population draws reproduce the fitted values closely —

| | 5 % | 25 % | 50 % | 75 % | 95 % | mean |
|---|---|---|---|---|---|---|
| fitted `steps`, all 235 | 8 | 18 | 31 | 92 | 349 | 89 |
| simulated `steps` (MVLN) | 5 | 15 | 40 | 103 | 368 | 92 |

Given a correct `steps` budget, a fire that spreads as a round blob burns more area than one
that spreads as an elongated cigar with the same reach. So the roundness and the inflated size
distribution are one finding, not two, and the arrow points from shape to size. Anything that
recovers realistic anisotropy would be expected to pull the size distribution down with it.

Worth stating in the paper as the main negative result, with the caveat that the fixed,
spatially uniform wind field (one direction, near-constant magnitude, WindNinja at 4 m/s) is a
plausible contributor: real fire-day winds are stronger and gustier than the field the model was
both fitted and simulated under, so the fitted `wind` coefficient has no way to express the
day-to-day variation that produces real elongation.

Also flag once: the simulator's edges lump "spread refused" and "step budget exhausted", a
lumped stand-in for suppression and weather-event end. Per-cell stop-mechanism attribution is
out of scope.

### Plot style

For each metric, one panel with:

- x = `log10(fire_size)`, or FWI (both worth showing; size is the primary axis because the
  metrics depend strongly on it through sample size).
- Simulated dataset as a 2-D density (`geom_density_2d_filled` or hex bins — raw points do not
  work at 1e6).
- Observed fires as points.
- GAM smoothers (`geom_smooth`) for each dataset.

Facet by metric (each coefficient, each shape metric). One figure for the size-conditional
plots, one for the FWI-conditional ones. Conditioning on size or FWI defends against any
residual mismatch in the marginals; FWI is pixel-level standardized (temporal variation only),
so there are no spatial FWI complications.

### How many fires? The four counts, reconciled

Four different totals for "the mapped record" appear across the code, and they are all correct
for what they count — checked 2026-08-28, no bug:

| count | what it is |
|---|---|
| **241** | features in `data/patagonian_fires_spread.shp` |
| **238** | features in `data/patagonian_fires/patagonian_fires.shp` — the base mapped record |
| **235** | rows in the hierarchical fit (`J1 = 57` + `J2 = 178`) |
| **233** | distinct fires in `data/climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ2.csv` |

`_spread` = base record **+2** (`2011_19` split into `2011_19E`/`W`, `2015_47` into
`2015_47N`/`S`) **+1** (`2003_1215845321`, present only in `_spread`) = 241. Two fires also
carry a different year label between the two files (`1546963766` is 1999 in `_spread`, 2000 in
the base; `-1075171770` is 2014 vs 2016) — same fires, so they do not change any count.

Of the 241, **six have no FWI record** (`1999_1319185782`, `1999_1689435445`,
`1999_1780556035`, `2003_1215845321`, `2005_17`, `2012_23`), leaving 235 fires the model can
use; collapsing the two splits gives the csv's 233 distinct fires.

**For the paper, always say 235 = 57 + 178.** The one place that does not match is the shape
analysis, which was run over the 238 polygons of the base shapefile — it needs no weather and
no ignition point, so it can use fires the fit cannot. Either re-run it on the 235 for a single
number throughout, or keep 238 and say in the text that the shape reference set is every mapped
polygon rather than only the fires the model was fitted to. The manuscript currently takes the
second route and gives no count there.

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
| signature `vfi` (> 100 ha) | see table above | to be recomputed |
| signature `tfi` (> 100 ha) | see table above | to be recomputed |

Observed fires are elongated and wind-aligned at every size class; simulated fires are rounder
and randomly oriented — the headline result. The signature rows predate the switch to a
`vfi`/`tfi`-only multiple regression on the original scale and to the full ~235-fire observed
reference; they must be recomputed once the reduced landscapes exist. Under the earlier
four-predictor standardized version, `slope` matched well, `vfi` was over-weighted and `tfi`
under-weighted.

## Refactor targets
- Split inline data manipulation out of the fitting script into functions (tech debt #2).
- Vendor the `FireSpread` R spread wrappers instead of sourcing from `tests/testthat/` (#3).
