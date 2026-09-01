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

### Burn-probability maps — `figure_burn_probability.R` (paper Fig. 5)

Per-cell burn probability from **2000** simulations under the **fitted** random effect and 2000
under a **newly simulated** one, on the same landscape and the same ignition point, for four
focal fires — 8 panels. Written to `manuscript-spread/figures/fig5_burn_probability.{png,pdf}`,
with the per-cell counts kept in `files/hierarchical_model/burn_probability_maps.rds` so the
figure can be retuned without re-simulating (`do_simulate <- FALSE`). About 4 minutes on 8
cores, nearly all of it `2015_50`.

The random effects come from `R/focal_simulation_functions.R`, shared with
`spread/simulate_focal_metrics.R` — including the `steps`-scale trap, documented there. What is
special here is only that a per-cell burn **count** is accumulated instead of a row of metrics,
chunked so each worker returns one integer matrix rather than one mask per simulation (42 MB
against 42 GB for `2015_50`). Each simulation's overlap with the observed fire comes back too,
for the panel labels.

The four fires and the criteria behind them are in `manuscript-spread/ijwf/designing.txt` →
Fig. 5: a monotone gradient of posterior-median overlap (0.84 / 0.64 / 0.35 / 0.27 against a
57-fire median of 0.535), three orders of magnitude in size, and the strongest under- and
overestimate in the set. Caption numbers: median fitted-ranef overlap over the 57 focal fires
0.535, median size quotient 1.04, 36 of 57 fires overestimated.

**What each panel carries, and why it is only there.** The two columns *are* the two
random-effect modes, so the titles "(A) fitted" / "(B) simulated" appear only in the top row.
The fire id and its size label the left column, as the row title. The scale bar is on the left
panel only, because the two panels of a fire share an extent. The right panels carry the
coordinates, as a lat/long graticule over the EPSG:5343 rasters — `label_axes = "-NE-"` puts the
parallels on the far right, where they cannot be read as belonging to the left panel, and the
meridian breaks are set by hand (`pretty(n = 2)`) because the default graticule puts six
"71.5x°W" labels on a panel one kilometre wide. Every panel is labelled with its **mean overlap**
with the observed fire, in a white box: **0.832 / 0.637 / 0.349 / 0.235** under fitted random
effects and **0.226 / 0.041 / 0.128 / 0.071** under simulated ones, in the panel order of the
figure. Those are means over the 2000 simulations; the 0.84 / 0.64 / 0.35 / 0.27 gradient the
fires were selected on is a median of posterior medians, which is why the smallest fire's number
differs a little.

Aesthetics follow the burn-probability maps made for the thesis defence
(`fire regime simulations/plots_defensa*.R` in the old PhD repo): a burnable / non-burnable base
layer, the probability surface over it through `ggnewscale`, the observed perimeter as a haloed
outline and the ignition point as a white dot. One feature of the panels is worth knowing before
it is mistaken for a bug: the square, blocky outer boundary of the burned region is the `steps`
budget, not a landscape edge — the automaton reaches 8 neighbours per step, so after `steps`
steps the burned set is contained in a square of that half-width around the ignition cell.

## Stage 3 — validation

Pattern-oriented validation: the simulator is judged on whether statistical patterns that
emerge from many simulated fires match those of the observed record, not on point prediction
of individual fires.

Code: `R/spread_validation_functions.R` (shared metrics),
`spread/validation_ignition_cells.R` (run once), `spread/validation_simulate.R` (the simulated
side), `spread/validation_observed.R` (the observed side — the same metrics over all 241 mapped
fires, saved to `files/spread_validation/observed_signature.rds` and `observed_shape.rds`), and
`spread/validation_analysis.R` (the comparison — figures into
`files/spread_validation/figures/`, numbers into `validation_summary.rds`). Results below under
*Results of the validation*.

### How it is run — order, commands and cost

Everything below was run over 2026-08-21…31. In order, with what each step needs and what it
leaves on disk:

| # | step | script | needs | writes | cost |
|---|------|--------|-------|--------|------|
| 0 | landscapes | `data_prep/landscapes_simulation.R` (tiles) and `data_prep/landscapes_preparation.R` (`do_signature` stage → the 184 reduced landscapes) | the GEE exports downloaded into `data/simulation_landscapes/raw_gee/` and `data/signature_landscapes/raw_gee/` | the tile and reduced-landscape `.rds` | WindNinja hours for the tiles; seconds for the 184 |
| 1 | eligible ignition cells | `spread/validation_ignition_cells.R` | the four tiles | `files/spread_validation/ignition_cells.rds` | run once |
| 2 | simulated side | `spread/validation_simulate.R` | 1 + `spread_model_samples.rds` + the FWI csv | `simulated_fires.rds` (12.8 MB, 64,836 fires) | **15 min on 14 cores** |
| 3 | observed side | `spread/validation_observed.R` | the 57 focal + 184 reduced landscapes | `observed_signature.rds`, `observed_shape.rds` (241 rows each) | 1.4 min |
| 4 | comparison | `spread/validation_analysis.R` | 2 + 3 | four figures in `files/spread_validation/figures/`, every number in `validation_summary.rds` | < 1 min |
| 5 | focal re-simulation | `spread/simulate_focal_metrics.R` | the hierarchical fit + the 57 focal landscapes | `files/hierarchical_model/focal_metrics.rds` | ~30 min on 14 cores |
| 6 | paper figures | `spread/figure_burn_probability.R` (Fig. 5), `spread/figure_dharma_metrics.R` (Fig. 6, needs 5), `spread/figure_validation_metrics.R` (Fig. 7, needs 4) | as noted | `manuscript-spread/figures/` | 4 min / seconds / seconds |

Shared metrics live in `R/spread_validation_functions.R`; steps 2–4 read nothing from each other
except through those `.rds` files, so any one of them can be re-run alone.

Step 2 is the only long one and is best launched detached:

```bash
tmux new-session -d -s spread_sim -c ~/dev/fire-regime-sim-patagonia \
  "stdbuf -oL -eL Rscript spread/validation_simulate.R 2>&1 | tee files/spread_validation/run.log; exec bash"
```

It accepted 64,836 fires ≥ 10 ha out of 148,649 proposals (43.6 %), so the single pass overshot
`n_target = 50 000` and no second pass was needed; the 83,813 rejected proposals keep their sizes
in `small_sizes`. Only 14 of the accepted fires (0.02 %) have an NA signature, where
`donor_strata()` found nothing to fit; fires split 13,987 / 18,348 / 19,941 / 12,560 across
tiles 1–4.

Step 4's figures and `validation_summary.rds` are analysis output and stay in `files/`; the
paper's validation figures are Figs. 6 and 7 (step 6), decided with Iván on 2026-08-31 —
see *The paper's validation figures* below.

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
rasterized polygon — so the observed reference is **all 241 mapped fires across every size
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

Terrain steering is real and worth knowing when reading either elongation: over the 64,836
simulated fires, `wdir` averaged over a fire's burned cells has a 5–95 % range of **277–311°**
around the 293° the tiles were driven with, though the per-fire fields are highly coherent
(median `rbar` 0.99). Measuring against each fire's own mean wind rather than the fixed 293°
changes the answer very little (see the results table below), which is itself informative.

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
**Observed values, computed and saved 2026-08-28** by `spread/validation_observed.R` into
`files/spread_validation/observed_signature.rds` (one row per fire; `observed_shape.rds` is its
shape twin). All **241** fires were fitted and all 241 converged — `donor_strata()` never
returned NULL, the smallest fire in the record still yielding 60 usable strata. Coefficients on
the original predictor scale, size classes by burned-cell area:

| | n | median | IQR | frac > 0 | < 100 ha | 100–1000 ha | > 1000 ha |
|---|---|---|---|---|---|---|---|
| `vfi`, all 241 | 241 | 1.121 | [−0.01, 3.46] | 0.74 | 2.09 | 0.44 | 0.84 |
| `tfi`, all 241 | 241 | 0.698 | [−3.78, 4.37] | 0.56 | 0.66 | 0.47 | 1.21 |
| `vfi`, 57 focal | 57 | 0.882 | [0.28, 1.84] | 0.84 | 1.12 | 0.79 | 0.94 |
| `tfi`, 57 focal | 57 | 0.624 | [−2.94, 2.99] | 0.53 | −0.21 | −0.65 | 1.13 |

(146 / 59 / 36 fires in the three size classes.)

**These supersede the numbers this file used to carry** (`vfi` 0.578, 86 % > 0; `tfi` 1.881,
65 % > 0), which came from an exploratory session whose output was never saved. `vfi` reproduces
in the ballpark — median 0.88 against 0.578, 84 % against 86 % positive — but `tfi` does not:
the measured median is 0.62, not 1.881, and only 53 % of focal fires are positive. The old
per-size-class figures are not reproduced at all. The saved run is the reference from here on;
it is stable under the donor subsampling (re-running with a different seed moves the focal `vfi`
median 0.882 → 0.828 and leaves `tfi` at 0.624).

`tfi` does strengthen with fire size, which is the pattern the size-conditioned comparison was
designed around, but `vfi` does not: it is *largest* among fires under 100 ha, where a hundred-odd
small fires with few strata give wide, noisy per-fire estimates (IQR [−0.26, 4.07] over the 184
non-focal fires against [0.28, 1.84] over the 57 focal ones). The comparison must condition on
`log10(area)` either way — but read the small-fire end as noise-dominated rather than as a
stronger signal.

Note these are *edge-local summary statistics*, not estimates of the model's β (the fitted
per-fire values are an order of magnitude larger: `vfi` median 11.9, `tfi` 4.5). What matters is
whether observed and simulated distributions of the statistic agree.

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
- **R — done (2026-08-28).** The `do_signature` loop at the end of
  `data_prep/landscapes_preparation.R` builds the three-layer arrays from those 184 exports into
  `data/signature_landscapes/landscapes/<fire_id>.rds` (25 MB in total, seconds to run). No
  WindNinja, no ignition point, no `steps`; the burn mask comes from the export's `burned` band
  and is stored 0-indexed as `burned_ids`, exactly as the focal landscapes store it, and
  `vfi`/`tfi` come from `build_landscape()` called with **`wind = NULL`** — a path added for this
  purpose, which emits the reduced `land_names_reduced` = `veg`/`vfi`/`tfi` layer set and skips
  the wind projection and the elevation layer. The year each fire's NDVI is detrended to is read
  from `patagonian_fires_spread.shp`'s `year` property minus one — the same property the GEE
  export picked `b_<year - 1>` with, and identical to the July–June `fire_year` for all 57 focal
  fires. One fire, `2014_1010415027`, trips the 2 % NA-mask warning at 3.3 %.

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

### Results of the validation (2026-08-28)

Both sides are on disk and compared by `spread/validation_analysis.R`, which writes four
figures into `files/spread_validation/figures/` and the numbers below into
`validation_summary.rds`. 64,836 simulated fires against 241 observed ones.

**1. Size distribution — the simulator runs large, uniformly.** KS *D* = 0.187
(*p* = 1.1e-7), and the Q-Q sits below the 1:1 line over the whole range rather than
departing in one tail:

| quantile | 5 % | 25 % | 50 % | 75 % | 95 % | max |
|---|---|---|---|---|---|---|
| observed (ha) | 15.8 | 27 | 58 | 321 | 3,249 | 28,616 |
| simulated (ha) | 12.8 | 36 | 151 | 904 | 10,143 | 454,278 |

Read it with the caveat the design already flags: the simulated set is conditioned on ≥ 10 ha
and the observed record is what the mapping caught over 1999–2022, not a draw from the same
generative process. It is the weakest test of the set, and the offset is roughly a factor of
2–3 in the middle of the distribution.

**2. Shape — the headline result, confirmed at every size.** Medians by size class:

| | < 100 ha | 100–1000 ha | > 1000 ha |
|---|---|---|---|
| `elongation` observed | **2.07** | **1.96** | **2.57** |
| `elongation` simulated | 1.56 | 1.47 | 1.47 |
| `elong_293` observed | 1.23 | 1.13 | 1.58 |
| `elong_293` simulated | 1.00 | 0.97 | 0.93 |
| `elong_wind` simulated | 0.99 | 0.98 | 0.94 |
| compactness observed / simulated | 0.24 / 0.33 | 0.10 / 0.26 | 0.03 / 0.09 |
| hull fill observed / simulated | 0.73 / 0.85 | 0.68 / 0.88 | 0.60 / 0.85 |
| frac. within 30° of 113/293 observed | 0.48 | 0.46 | **0.72** |
| frac. within 30° of 113/293 simulated | 0.30 | 0.27 | 0.26 |

Conditioning on size does not rescue it: simulated fires are rounder, fuller-hulled and more
compact than observed ones in every class, and their orientation is *below* the 0.333 a uniform
orientation would give while the observed alignment rises to 0.72 among fires over 1000 ha.
Measured along the fixed 293°, the simulated fires are not elongated at all (0.93–1.00), and
measured along their own terrain-steered wind they are the same. See *Why the model cannot make
an elongated fire*.

**3. Spatial signature — `vfi` broadly agrees, `tfi` has the wrong sign at small sizes.**

| | < 100 ha | 100–1000 ha | > 1000 ha |
|---|---|---|---|
| `b_vfi` observed / simulated | 2.09 / 1.39 | 0.44 / 1.42 | 0.84 / 1.74 |
| frac > 0 observed / simulated | 0.72 / 0.79 | 0.66 / 0.83 | 0.94 / 0.92 |
| `b_tfi` observed / simulated | 0.66 / **−2.45** | 0.47 / −0.57 | 1.21 / −0.18 |
| frac > 0 observed / simulated | 0.56 / 0.38 | 0.54 / 0.46 | 0.64 / 0.48 |

The `vfi` distributions overlap heavily — the simulated median is inside the observed IQR in all
three classes, and the fraction positive matches within a few points. The *trend* with size does
not match (observed falls then rises, simulated rises monotonically), but the small-fire end of
the observed side is noise-dominated, so little weight should be put on that.

`tfi` is the real disagreement: simulated fires give a **negative** edge-local topographic
signature at small sizes, where observed fires give a positive one, and the simulated fraction
positive is below a half in every class against 0.54–0.64 observed. This is a genuine structural
mismatch and not the size-conditioning artefact the pilot's unconditioned comparison suggested.

**4. FWI.** Both sides get bigger with FWI, and by a similar factor — observed median area
39.6 → 277.7 ha across quartiles of the observed FWI, simulated 53.9 → 397.9 ha (the offset from
test 1 carried along). Simulated `elongation` rises weakly with FWI (1.43 → 1.53) where observed
is flat (1.93 → 2.12, no trend), and simulated `b_vfi` *falls* with FWI (1.78 → 1.30) where
observed is noisy. Every simulated fire falls inside the observed FWI range, because FWI is
resampled from the 233 mapped fires — which is also why the FWI panels are visibly striped:
`fwi_z` takes only 233 distinct values.

### The paper's validation figures — Figs. 6 and 7

Decided with Iván on 2026-08-31 (his answers in `manuscript-spread/ijwf/designing.txt`): the four
figures `validation_analysis.R` writes stay as analysis output in `files/`, and the paper carries
two figures instead. **`vfi`/`tfi` are dropped from the paper**, and of the shape metrics only
compactness and the deviation from the wind axis survive — elongation and convex-hull fill are
largely redundant with compactness, and elongation along the fixed 293° adds nothing.

**Fig. 6 — `spread/simulate_focal_metrics.R` → `spread/figure_dharma_metrics.R` →
`fig6_dharma_metrics.{png,pdf}`.** DHARMa uniform Q-Q of eight metrics, for the **57 focal fires
only**, under fitted and under simulated random effects. Eight panels in a 3 × 3 grid, filled by
row — all vegetation / wet / subalpine, dry / shrubland / grassland, compactness / wind-axis
deviation — with the legend in the ninth cell (`legend.position = "inside"`; `facet_wrap` cannot
put a guide in an empty panel any other way).

Why focal fires only, for the paper's text: burned area per vegetation class is comparable
between observed and simulated only from the *same* ignition point, because what is available to
burn around that point dominates the answer — and the shape metrics are asked the same per-fire
way, so they need the ignition point too. The 184 fires without a mapped ignition point carry the
record-wide size/shape validation instead (Fig. 7).

**The simulations behind it are their own script.** `metrics_table.rds`, written by the
*Assessing model fit* block of `hierarchical_fit.R`, stores only size and size by vegetation
class — shape needs each simulated fire's burned cells, which it never kept. So
`spread/simulate_focal_metrics.R` re-runs the whole thing, 57 fires × 2000 × 2 modes, and reduces
each simulated fire to overlap, size, size by vegetation class, compactness, orientation and the
wind-axis deviation, into `files/hierarchical_model/focal_metrics.rds`. 25 minutes on 14 cores,
`2015_50` alone 4.7 of them. Every panel of the figure then comes from one simulation set.

Three checks the script prints, all of which passed on the 2026-09-01 run:

- the observed sizes it measures are **identical** to `size_obs.rds` — which also proves the two
  share a fire order, worth knowing because `size_obs` has no row names and everything downstream
  indexes it positionally;
- the medians over fires reproduce the old table — overlap 0.527 against 0.526, size quotient
  1.086 against 1.088 (fitted) and 1.510 against 1.505 (simulated). The draws differ, the
  distributions do not;
- 7.2 % of simulated fires burn fewer than 3 cells and so have no principal axis (33 % in the
  worst fire). Those draws are **resampled from the same fire's valid ones**, which keeps the
  matrix rectangular for `createDHARMa` and makes the two shape panels ask the conditional
  question they should: *given the model produced a fire at all*, is the observed shape typical?

**The wind axis is per fire**, not the fixed 293° of the record-wide validation: these 57 fires
each have their own wind direction, so the deviation is measured against the circular mean of
`wdir` over the **observed** fire's burned cells — one fixed axis per fire, scoring the observed
fire and all 4000 of its simulations alike.

**`drop_unavailable` is now `TRUE`, and the rule is `< 30` available cells, not `== 0`.** A
vegetation class with a handful of pixels in the landscape is a structural zero in all but name:
observed 0, nearly every simulation 0, and a residual that is pure tie randomization. At 30 cells
(2.7 ha) this drops 8 fires from the wet-forest panel, 11 from subalpine, 8 from dry, 2 from
grassland and none from shrubland.

**Results — and these supersede the numbers this file used to carry.** The old ones (fitted mean
0.28 overall, grassland worst at 0.29 / *D* = 0.43, dry forest best at 0.54 / *D* = 0.19) were
written before the panel-label shift of 2026-08-31 was fixed and were never updated: they are
this table's values displaced by one vegetation class. Recomputed, and confirmed against the old
`metrics_table.rds` (which gives 0.374 for the same quantity, against this run's 0.373):

| panel | *n* | mean residual, fitted | KS *D* | mean residual, simulated | KS *D* |
|---|---|---|---|---|---|
| All vegetation types | 57 | 0.373 | 0.252 | 0.686 | 0.341 |
| Wet forest | 49 | 0.446 | 0.285 | 0.649 | 0.305 |
| Subalpine forest | 46 | 0.534 | 0.221 | 0.709 | 0.386 |
| Dry forest | 49 | 0.485 | 0.263 | 0.652 | 0.275 |
| Shrubland | 57 | 0.291 | 0.420 | 0.649 | 0.275 |
| Grassland | 55 | 0.231 | 0.523 | 0.596 | 0.215 |
| Compactness | 57 | 0.429 | 0.348 | 0.163 | 0.518 |
| Deviation from wind axis | 57 | 0.325 | 0.428 | 0.245 | 0.465 |

Every panel rejects uniformity at *p* < 0.05 in both modes. Read in words:

- **Size** behaves as the thesis version did. Under **fitted** random effects the observed areas
  sit low in their own predictive distributions (0.373 overall, 65 % of fires below the simulated
  median) — the model burns too much — while **simulated** ones overshoot the other way (0.686,
  only 19 % below). **Grassland** is the worst class under fitted parameters (0.231, *D* = 0.523)
  and **subalpine forest** the best (0.534, *D* = 0.221).
- **Shape** puts the headline result in the calibration frame. Compactness: under simulated
  random effects the mean residual is **0.163** and **96 %** of observed fires are less compact
  than the model's median simulation — the same "simulated fires are too round" finding as Fig. 7,
  now per fire and from the fire's own ignition point. Wind-axis deviation: 0.245, with 90 % of
  observed fires better aligned with their own wind than the median simulation. Under fitted
  random effects both are much closer to calibration (0.429 and 0.325), which is the expected
  gap between a fit diagnostic and an out-of-sample one — but even there the fires are
  systematically less compact and better aligned than the model makes them.

**Fig. 7 — `spread/figure_validation_metrics.R` → `fig7_validation.{png,pdf}`.** One figure in
two parts, stacked by patchwork with the letters written by `ggtitle()` on each part's first
panel (heights 1 : 2.6). Part A is the size density + Q-Q. Part B is a 3 × 2 grid:
one metric per row (size, compactness, deviation from the wind axis), conditioned on FWI in the
left column and on fire size in the right. The size row has no size-vs-size panel, so the
top-right cell holds the two shared legends — line colour (Simulated / Observed) and the
`N° of simulated fires` colourbar. **Every size axis in the figure is drawn on a log10 scale and
labelled in hectares** — ticks read 10 / 100 / 1,000, never 1 / 2 / 3. Part A gets there by
plotting raw areas under `area_scale()` and putting its Q-Q quantiles back with `10^`, so the
plot is unchanged and only its ticks are; Part A also has to repeat `metric_panel()`'s type sizes
by hand (`part_theme()`), or it comes out in theme_bw's larger default and the two halves stop
looking like one figure. Axis titles appear once per column (bottom) and once per row (left),
since every column shares an x scale and every row a y scale.

The vertical striping in the FWI panels is deliberate: `fwi_z` is resampled from only 233 distinct
observed values, and jittering would hide a real property of the simulated set.

### The paper's model figures — Figs. 1-4 and S1-S5

Written 2026-09-01. Every figure the spread paper carries now has **its own script in
`spread/`**, each of which reads what the fit already wrote to `files/hierarchical_model/` and
draws; none of them re-fits anything, and none needs `hierarchical_fit.R` to have been run in the
session. Before this, Figs. 2-4 and S1-S5 existed only as plotting blocks buried in
`hierarchical_fit.R`, a 3000-line script that has to run top to bottom before any of them will
evaluate — so a caption change meant a refit.

| Paper | Script | Output stem | Reads |
|---|---|---|---|
| Fig. 1 | `figure_study_area.R` | `fig1_study_area` | shapefiles + external base layers |
| Fig. 2 | `figure_spread_curves.R` | `fig2_spread_curves` | `curves_df_prediction.rds` |
| Fig. 3 | `figure_params_fwi.R` | `fig3_params_fwi` | `mu_samples_prediction.rds`, `spread_model_samples.rds` |
| Fig. 4 | `figure_vegetation_effect.R` | `fig4_vegetation_effect` | `spreadprob_veg_comparison_array.rds` |
| Fig. 5 | `figure_burn_probability.R` | `fig5_burn_probability` | `burn_probability_maps.rds` |
| Fig. 6 | `figure_dharma_metrics.R` | `fig6_dharma_metrics` | `focal_metrics.rds` |
| Fig. 7 | `figure_validation_metrics.R` | `fig7_validation` | `files/spread_validation/` |
| Fig. S1 | `figure_flammability_indices.R` | `figS1_flammability_indices` | `data/flammability_indices/` |
| Fig. S2 | `figure_spread_curves.R` | `figS2_spread_curves_raw` | `curves_df_prediction_raw_x.rds` |
| Fig. S3 | `figure_parameter_correlations.R` | `figS3_parameter_correlations` | `spread_model_samples.rds` |
| Figs. S4, S5 | `figure_focal_fit.R` | `figS4_overlap`, `figS5_size_quotient` | `focal_metrics.rds` |

All of them write `.png` and `.pdf` into `manuscript-spread/figures/`, and all but Fig. 1 and
Fig. S3 run in seconds. Fig. S3 re-simulates 235 fires per posterior draw for each of the 15
parameter pairs (about 100 s) and caches the result to
`files/hierarchical_model/parameter_correlations.rds`; `do_compute <- FALSE` then redraws it for
free, the same two-stage pattern as Fig. 5.

The shared pieces are in **`R/spread_figure_functions.R`**: `summarise_post()` (the fit's own
posterior summary, renamed so it does not mask `dplyr::summarise`), `nice_theme()`,
`spread_fwi_all()`, the FWI back-transform, `par_labels()` and `save_fig()`. It sources
`R/focal_simulation_functions.R` for the parameter bounds and `invlogit_scaled2()`.

**Three conventions the paper figures follow, and the traps behind them.**

1. **Parameter names are the manuscript's**, never the code's: β₀ (intercept), β₁ (VFI),
   β₂ (TFI), β₃ (slope), β₄ (wind), κ (steps). `par_labels()` is the only place that mapping is
   written. They are **literal Unicode subscripts, not plotmath**, because plotmath silently
   drops the space between an expression and the string after it when the text is rotated —
   which is what a left-placed facet strip does, so `beta[0]~"(intercept)"` renders with the
   subscript sitting on the bracket. The price is that the PDF has to go through `cairo_pdf`;
   `save_fig()` does that.

2. **FWI is always shown on its original anomaly scale**, never the fit's standardized one. The
   two are easy to confuse and differ by a lot: FWI was already a pixel-level standardized
   anomaly before the fit standardized it *again* across the 235 fires, so a model-internal 0 is
   an anomaly of **+0.86**. The three levels of Figs. 2 and S2 are stored as
   -1.614 / 0 / 1.672 and printed as **-0.60 / 0.86 / 2.38**.

3. **`draws$ranef` mixes scales.** Row `steps` is stored on the natural scale, the other five on
   the logit scale; only rows `1:(n_coef - 1)` are back-transformed. Documented at length in
   `R/focal_simulation_functions.R` and repeated wherever it bites (Fig. 3's points, Fig. S3's
   simulation).

A fourth trap, found while writing Fig. S3: **`invlogit_scaled2()` reads a matrix as one column
per (L, U) pair.** Handing it a fires × draws slice with scalar bounds silently takes `U[2]`,
which is `NA` for a scalar `U`, and every correlation comes back `NA`. Use a plain
`plogis(x) * (U - L) + L` for whole slices.

**Figure 3 sanity check.** The per-parameter P(FWI slope > 0) printed by `figure_params_fwi.R`
reproduces the thesis-era figure exactly — 73.73 / 22.83 / 55.33 / 34.42 / 92 / 100 % for
intercept, VFI, TFI, slope, wind, steps. That is the cheapest confirmation that `fwi_all` and the
back-transform chain were rebuilt correctly from the saved posterior rather than re-derived
wrongly. Only `steps` is decisive: fire weather acts on how far a fire runs, not on how it
spreads locally.

**Two rendering defects of the thesis version of Fig. S3 are fixed**, and nothing else about it
is changed: the inner panels carried white-on-white strip text that rendered as ghost labels
floating above each row, and the bottom axis ran -1 to 1 with zero panel spacing, so neighbouring
panels printed "1.0" and "-1.0" on top of each other (the extreme breaks are dropped).

**Figs. S4 and S5 read `focal_metrics.rds`, not `metrics_table.rds`.** Both files hold overlap
and simulated size for the 57 focal fires, but `metrics_table.rds` is the superseded
`hierarchical_fit.R` run; `focal_metrics.rds` is what Fig. 6 uses, so the three focal-fire
figures now describe the same 2000 × 2 simulations. Results from it: median overlap **0.527**
under fitted random effects against **0.108** under simulated ones, and a median size quotient of
1.09 (55 of 57 fires within a factor of two) against 1.51 (28 of 57).

#### Fig. 1 — the study area map

`spread/figure_study_area.R` is an R remake of the QGIS figure the Fire Ecology paper used
(`~/Insync/patagonian_fires paper/study area map/mapa area de estudio 6.qgz` →
`01) study area 6.jpeg`, Feb 2025). Three panels over one extent — (A) the fire record, (B)
elevation, (C) vegetation — plus a South America locator inset.

Everything about the design was read out of the `.qgz` (it is a zip; `unzip` it and the `.qgs`
inside is XML) rather than reinvented:

- **CRS `EPSG:5343`** (POSGAR 2007 / Argentina 1) and the layout's own map extent,
  `ext(1476449.12, 1622527.39, 5071498.51, 5690988.16)`. Note `lat_0 = -90`, so northings are
  measured from the south pole and run 5.07-5.69 × 10⁶ m here.
- **Colours**: study-area outline `#470094`, fires `#E72A09`, lakes `#1DCCE3` over panels A and
  C but `#CAEEFC` over the elevation panel, Chile `grey83`. The vegetation ramp is inferno
  sampled at 8 levels (`#000000`, `#6b186e`, `#a82e5f`, `#dd513a`, `#f98c0a`, `#f6d645`,
  `#fcffa4`, `#fcffa4`); the last two classes share a colour and one legend entry. The elevation
  ramp is viridis over 200-3200 m.
- **The grey is Chile and the white is Argentina**; the international border needs no line of its
  own, it is where the two meet. The **thick dashed grey lines crossing the panels are the
  provincial boundaries** (Neuquén / Río Negro / Chubut), which is what panel C's three labels
  refer to. Take them from the bicontinental project's IGN `Provincias.shp` — the FAO GAUL file
  sitting in the same folder is missing six Argentine provinces, Río Negro and Chubut among them.
- Panel C draws **`vegetation_valdivian_img.tif`**, the 8-class version, not the
  `_dryforest2` one; the `.qgs` has four raster renderers and only the one on the
  `vegetation_valdivian_img copy` layer carries the inferno palette the printed figure shows.

**What this version adds** is the only intended change: panel A colours the **57 fires with a
mapped ignition point** (`#2166AC`) apart from the rest of the record. The split comes from
`data/focal_fires/landscapes/*.rds`, matched against `data/patagonian_fires_spread.shp`.

**Base layers live outside the store.** The elevation mosaic (240 MB), the vegetation raster, the
lakes and the country/province shapefiles are still in the Insync folders the QGIS project used,
reached through two new `R/config.R` entries, `study_area_map_dir` and `vegetation_lara_dir`.
Nothing else in the pipeline reads them. Runtime is about 90 s, nearly all of it those two
rasters; `maxcell_plot` caps what is actually rendered at 3 × 10⁶ cells, since the elevation
mosaic is 121 million cells at 30 m and each panel is 3.5 cm wide.

Departures from the QGIS original, and the open questions on it, are listed in `docs/roadmap.md`.

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

Against that ceiling, **61 % of the 241 mapped fires are more elongated than the model can be
(1.9), rising to 78 % among fires over 1000 ha**; the observed distribution runs 1.31 / 2.12 /
3.78 at the 10th / 50th / 90th percentiles, with a maximum of 7.55 (measured 2026-08-28 from
`observed_shape.rds`; the earlier 63 % / 79 % / 1.33 / 2.20 / 3.80 / 8.0 were the same statistic
over an unsaved 238-fire run).

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
