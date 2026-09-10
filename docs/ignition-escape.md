# ignition_escape — ignition & escape models (paper 2)

> **Status: scaffold.** High-level content is accurate (from the old repo's inventory); deep
> method/statistics detail (marked _TODO_) is written as the scripts are migrated and read.

The two simpler sub-models, fitted together. Canonical version is the old repo's `_FWIZ` variant.

> **Note:** in the regime paper, **a few functions in the spatial ignition model will change**
> from the thesis version (see the PhD thesis, chapter 4 + supplementary — link in `CLAUDE.md` /
> root `README.md`). Document the *current* formulation here.

## Fit — `fit.R`
- **Ignition model:** probability/rate of fire ignition per unit area per unit time.
  - **Method:** negative binomial. _TODO: spatial structure, covariates (flammability, FWI),
    offset/exposure, link._
- **Escape model:** probability a fire escapes to become a large fire, defined as exceeding a
  size threshold of **0.09 ha (one pixel)** — see the script's "Escape model (> 0.09 ha)" section.
  - **Method:** binary logistic regression (`escape_model.stan`, `bernoulli_logit`). Confirmed
    canonical with the user (2026-07-09) — this is what `escape_model_samples.rds` is fit from.
    _TODO: covariates beyond FWI/vfi/tfi/distance-to-roads-humans, full spec._
- **Fitted via:** Stan. Sources `R/flammability_indices_functions.R` + `R/fortnight_functions.R`.
- **Inputs:** FWI data, the PNNH boundary, the flammability-index parameters, and the
  **non-public** ignition record in `data_private/ignition/` (Bari's PNNH fire reports,
  Kitzberger's lightning database, the merged point set with its Earth Engine covariates, and
  the population-point sample). That folder lives in a separate, never-shared store; see
  `architecture.md` → *The two stores*. This is the only fitting script that needs it.
- **Outputs:** `files/ignition/ignition_model_samples.rds`, `escape_model_samples.rds`
  — **production constants** consumed by `fire_regime/`.

## The ordinal escape variant: `escape_ordinal_exploratory.R`

Escape can also be asked as a size-class question rather than a yes/no one, and that version is
kept in `escape_ordinal_exploratory.R` (model file `escape_model_ordinal.stan`, fitted output
`files/ignition/escape_model_samples_ordinal.rds`). It is **exploratory: nothing in
`fire_regime/` reads it**, and it is not one of the paper's fitted models.

- **Response:** the fire's size class, cutpoints at **0.09, 10 and 100 ha** (K = 4 classes),
  instead of the binary > 0.09 ha indicator.
- **Method:** cumulative logit, with `ordered[K-1]` cutpoints and a `categorical` likelihood over
  the implied class probabilities. The linear predictor is the *same* as the binary model's:
  FWI through the Gaussian lag-weighting kernel, `vfi`, `tfi`, `drz`, `dhz`, with the cutpoints
  carrying what the binary model puts in its single intercept.
- **Why it is kept:** the 10 ha cutpoint. The spread simulator was estimated on fires above that
  size, so an escape definition anchored at 10 ha can be read off this fit without refitting.
- **How it runs:** it is a *continuation* of `fit.R`, not a standalone script. Run `fit.R` down
  to the end of its "Prepare data for escape model" section, then run this one in the same
  session; it takes `ig2`, `fwi_points`, `nlags` and `mean_ci` from there (the script stops with
  a message if they are absent). Sampling is a few minutes on 8 cores, but the fit is already in
  the store, so the `sampling()` call is commented and the `readRDS()` is the active line, the
  same convention `fit.R` uses.
- **Its `ordinal_predict()`** is the counterpart of `fit.R`'s `logistic_predict()`: same
  prediction grids, but it returns one class probability curve per size class instead of a
  single escape-probability curve.
- **It also writes** `data_private/ignition/ignition_size_data.csv` (`ig2` plus its size class),
  the file `fire_regime/simulate.R` reads to compare the simulated fire size distribution
  against the observed one. That `write.csv()` is commented like the other exports: re-run it
  only if the ignition record or the cutpoints change. This is why the size-class definition
  lives here rather than in `fit.R`, even though the regime side depends on its output.

The escape question was once also posed as a **continuous** fire-size regression (log-area,
`skew_normal`, left-censored at one pixel). That formulation is gone: it is not in the repo, has
no fitted output anywhere, and nothing reads it.

# Modifications to the spatial ignition models

**Status: planned, not implemented.** This section records the changes decided for the regime
paper's version of the spatial ignition model, and why. It replaces the thesis formulation
described in chapter 4 (eq. `igspat`). Nothing here has been coded or fitted yet.

## The two symptoms

In the thesis simulator (chapter 4, Fig. *Probabilidad de ignición, escape, propagación y quema
en el PNNH*), the annual burn-probability map is dominated by two features that are artefacts of
the spatial ignition model rather than results:

1. **Human ignition mass collapses onto road filaments.** The distance-to-roads effect is
   `exp(c * d)` with `c` large and negative, so relative ignition probability falls from its
   maximum to near zero within about 1 km. Any pixel adjacent to any road takes almost all the
   mass, and predicted ignitions end up tracking road *density* rather than observed fire. The
   area around Bariloche gets many predicted ignitions for the amount of road it has, while
   comparatively little burns there.
2. **Lightning ignition mass piles into the low-elevation south.** The Valle del Manso, south of
   PNNH, is wide and low (~400 m). Its high `tfi` gives it high relative ignition probability,
   high escape probability and high spread probability at once, and the three compound
   multiplicatively, so it absorbs most of the simulated burned area.

Three structural facts make this worse than it looks:

- The spatial model is a **softmax over the landscape** with the total number of ignitions per
  fortnight fixed by the temporal model. Over-prediction anywhere is not a local error: it
  mechanically *steals* ignitions from the rest of the park.
- There is **no intercept, and none is identifiable**, because under `exp()` an additive constant
  in `eta` cancels exactly in `theta_point / (theta_point + theta_land)`.
- The **fitting extent is PNNH + 500 m** (`fit.R`, `kitz_in` / `bari_in`), while the
  **simulation extent is PNNH + 10 km**. The Manso is outside the fitting extent entirely, so no
  amount of information in the data can speak to it.

The `tfi` effect itself is not assumed wrong. Its sign is constrained but zero was reachable in
all three sub-models and none of them went there, and the spread model estimated a large effect
over a wide `tfi` range across 235 fires, so elevation (temperature) is plausibly a real driver.
The Manso may simply be a local outlier. The changes below are motivated by **conservatism in
extrapolation**, not by a belief that the effect is spurious. The one asymmetry worth keeping in
mind is that the *ignition* `tfi` effect is partly confounded with detection and reporting (low
elevation is also accessible, and the record is of reported fires), while the spread effect,
estimated conditional on a fire existing, is not. That is why the softening below is applied to
ignition and not to spread.

## 1. A coarse Gaussian-process spatial field, in both cause models

### What it is for

The covariates cannot express spatial patterns that matter for fire but are not measured: human
activity concentrated in particular areas, the actual lightning climatology, and suppression
capacity that varies with access. Elsewhere in the landscape "near a road" implies fire; around
Bariloche it does not. Lacking data to model those mechanisms, a spatial random effect is the
honest way to let the model say so.

### The competition problem, and the defence

The standard risk is spatial confounding: a smooth field absorbs the effect of any covariate that
varies at a *comparable scale*. The defence is explicit scale separation, and it only works if
the scale is **fixed rather than estimated**, because a free range will shrink until it absorbs
the covariates.

| Term | Scale of variation |
|------|--------------------|
| distance to roads / settlements | ~0.5 to 2 km |
| `vfi` (NDVI-driven) | ~1 km |
| `tfi` (elevation, northing) | ~2 to 5 km |
| **the field** | **20 to 30 km, fixed** |

A factor of roughly 20 of separation. The field can say "the east is three times quieter than the
covariates imply"; it cannot redraw a road.

### Basis

Use an mgcv `gp` smooth, built once in R and passed to Stan as data:

```r
sm <- smoothCon(s(x, y, bs = "gp", m = c(3, rho)),   # Matérn kappa = 1.5, range rho
                data = fit_coords,
                absorb.cons     = TRUE,
                diagonal.penalty = TRUE)[[1]]
B <- PredictMat(sm, newdata)
```

Why `gp` rather than `tp` or `te(bs = "cr")`:

- **Extrapolation.** A `gp` basis decays to its null space (the constant) away from the knots. In
  a softmax an additive constant cancels exactly, so outside the data the field contributes
  *nothing* and prediction falls back to the covariates. That is the neutral behaviour wanted.
  `tp` has a linear null space and grows linearly outside the data hull; `cr` extrapolates
  linearly past its outermost knot. Neither goes flat.
- **Isotropy.** `s(x, y, bs = "gp")` and `bs = "tp"` are isotropic; `te(x, y, bs = "cr")` is not,
  it has a separate scale per margin.
- **Scale control.** In `gp` the range sits inside the correlation function, so it bounds the
  shape of the field directly. With `cr` or `tp`, `k` is a *ceiling* on flexibility and mgcv's
  smoothing parameter λ decides the actual smoothness. (In a Stan fit, where the prior replaces
  λ, a small-`k` basis does control the scale, so this argument is weaker than the other two.)
- **Simulability**, see below.

`k`: knots spaced at roughly one range over PNNH + 10 km (~150 × 100 km) gives about 6 × 4 ≈ 24,
minus knots falling entirely over non-burnable ground. So **25 to 40 columns**, not 100. Kernels
at this range overlap heavily and the field cannot resolve anything finer than `rho` regardless.

**Never rebuild the basis independently at prediction time.** Keep the `sm` object and generate
landscape values with `PredictMat(sm, ...)`, so the knots and the absorbed constraint match the
fit. Verify once by round-tripping `PredictMat` on the fitting coordinates against the design
matrix `smoothCon` returned.

### Diagonal penalty and the hierarchy

`diagonal.penalty = TRUE` reparameterises so that `S = diag(1, ..., 1, 0, ..., 0)`, the trailing
zeros being the penalty null space. Null-space coefficients are unpenalised, get no `sigma`, and
cannot be simulated from, so the null-space dimension decides whether the plan works:

- `tp` in 2D has `null.space.dim = 3` (constant, x, y). Absorbing the constraint kills the
  constant and leaves **two unpenalised linear directions with no prior**, which are exactly the
  directions that extrapolate unboundedly.
- `gp` has a null space of just the constant, which `absorb.cons = TRUE` removes. `S` comes back
  as the **exact identity**, every coefficient is penalised, and the prior is fully iid.

So the model is:

```
beta_c ~ Normal(0, sigma_c)      iid,  c in {human, lightning}
field_c(s) = B(s) %*% beta_c
```

Verify rather than trust: check `sm$null.space.dim == 1` and that `sm$S[[1]]` is the identity
after the call.

**Separate `beta` per cause, same `rho`, same prior on `sigma`.** Separate fields because the two
causes have genuinely different spatial structure; the same prior because the hierarchy then
does the right thing automatically: lightning has far fewer points, so its field shrinks harder
towards zero. That is the point of making it hierarchical rather than fixing the amplitude.

Identifiability is free here. `absorb.cons` removes the constant, and under the softmax an
additive constant cancels exactly, so any centring convention gives the same fit.

### Setting the prior on `sigma`

`sigma` is **not** the marginal SD of the field. The implied marginal SD at a location is
`sigma * sqrt(rowSums(B^2))`, so a number chosen on the `sigma` scale is uninterpretable. Since
`sigma` is the single parameter controlling how much spatial structure the model may invent, and
the whole defence against covariate competition rests on it, it has to be put on a scale that
can be defended.

**Normalise the basis so that `sigma` is the field's marginal SD by construction:**

```r
B <- B / sqrt(mean(rowSums(B^2)))   # over the background-cell sample
```

After this, `sigma` is directly the SD of the field on the log-intensity scale, and a prior like
`sigma ~ Normal(0, 0.5) T[0, ]` says: the field typically moves relative ignition intensity by
about `exp(±0.5)`, with `exp(±1)` in the tails, i.e. a factor of two to three, not a factor of
fifty. Sanity-check by simulating a handful of fields at `sigma = 1` and looking at the spread
before fixing the prior.

Report a sensitivity over two or three values of the prior SD. The field's amplitude is a
modelling choice made for extrapolation safety, and should be presented as one.

### Whether the field is warranted at all

Before committing, map **observed versus expected ignition counts per 10 to 20 km tile** under
the current fit. Expected counts come from the existing background-cell machinery, so this needs
no refit. It answers three things at once: whether there is coarse-scale structure the covariates
miss, what amplitude and range it has (which informs `rho` and the prior on `sigma`), and whether
the Bariloche mismatch is an ignition problem at all or an escape/suppression one. It is also a
figure the paper wants.

### In the simulator

The field must **not** become 25 to 40 extra layers of the 30 m landscape array. `pnnh_vals`
currently carries four columns over the buffered raster (order 1.5e7 cells, ~0.5 GB); adding the
basis at that resolution would take it past 10 GB. Two properties collapse it:

1. **Per posterior draw the field is one number per location, not `k`.** `f = B %*% beta`, and
   `beta` is fixed for the whole iteration (`simulate.R`, `iss <- sample(1:ipost, 1)`). So the
   matmul goes once per iteration, above the fortnight loop.
2. **The field is smooth at 20 to 30 km, so it does not belong at 30 m.** Evaluate `B` on a
   coarse grid once at setup, 1 km or 2 km. At 1 km over ~150 × 100 km that is ~15,000 × 40,
   about 5 MB. Per iteration it is one matvec (microseconds). Per candidate cell it is an
   integer division of row/col to get the coarse index and one lookup, with no interpolation,
   since the field varies by a fraction of a percent across 1 km at that range.

The field never needs to reach C++. The ignition location sampling is pure R
(`simulate.R`, the `iprob_h` / `iprob_l` blocks) and never enters `FireSpread`.

### Simulating new fields

Two distinct options, which answer different questions. Both should be available; the default
matters.

| Option | Draw | Says |
|---|---|---|
| **(a) posterior field** | `beta` from the posterior, alongside every other parameter | the quiet zones are where we estimated them, with uncertainty |
| **(b) new field** | `beta ~ Normal(0, sigma_draw)` with `sigma_draw` from the posterior of `sigma` | spatial anomalies of this magnitude exist, but we do not claim to know where |

- For **maps**, use (a). Averaging over (b) averages the anomaly away, so the burn-probability
  map collapses back to the covariate-only prediction with wider bands, which is a map that says
  nothing.
- For **landscape-total burned area and its uncertainty**, (b) is the more honest of the two. Note
  it is not mean-preserving: a random field that lands mass on flammable ground burns more than
  one that lands it on wet ground, so (b) shifts the mean as well as widening the interval.
- It is **period-dependent**. The field encodes suppression capacity near Bariloche and the
  lightning climatology in the Manso, which are physically anchored, not exchangeable.
  Randomising them asserts the suppression could be anywhere. Reasonable for 2090, dubious for
  2040, and wrong for the modern run, where it would break the calibration against the observed
  burn probability of chapter 3.

So: **(a) is the default and is used for anything compared against observation; (b) is a flag,
used deliberately for the far-horizon projections, with the reason stated.**

### What the field does not fix

The field is at its prior mean (zero) outside the fitting extent. The Manso is in the 10 km
simulation buffer, outside PNNH + 500 m, so **the field will not touch it**. The field is the fix
for Bariloche; the Manso needs section 2 (and even that only partly, see below).

## 2. Softening the `tfi` effect for lightning ignitions

Replace the linear term `c_tfi * tfi` with a soft-clipped one:

```
log theta = log_inv_logit(a + b * tfi) + c_vfi * vfi
```

equivalently `theta = inv_logit(a + b * tfi) * exp(c_vfi * vfi)`. The two terms are **additive on
the log scale**, so `vfi` is completely unconstrained and moves `theta` as freely as it does now.
The `inv_logit` ceiling of 1 is not a constraint on anything: the softmax sees only ratios, so
the overall scale cancels. What is capped is the ratio the `tfi` term alone can contribute,
`1 / inv_logit(a + b * tfi_min)`, which is the intent.

### The shape

- `a + b*tfi << 0` (high elevation, low `tfi`): `log_inv_logit -> a + b*tfi`, linear, i.e. the
  current model.
- `a + b*tfi >> 0` (low elevation, high `tfi`, the extrapolation direction): flattens to a
  constant.

Saturation in the dangerous direction, decay in the safe one. The unbounded-below tail is
harmless: at very high elevation `theta -> 0`, which is both true and safe, and those cells are
mostly `altoandino` and non-burnable anyway.

### The trap, and how to set `a`

Adding the nonlinearity **makes an intercept identifiable**, because `log_inv_logit` is not
shift-invariant the way a linear term is. And `a -> -Inf` gives back `a + b*tfi`, recovering the
current unbounded model exactly, with `exp(a)` cancelling in the softmax. Left free, the
likelihood will go there and the change becomes a no-op. **The prior on `a` is the entire content
of this modification.**

Parameterise by the location of the bend, not by `a`:

```
tfi_50 = -a / b        # the tfi at which the term reaches half its ceiling
a = -b * tfi_50
```

and prior `tfi_50` **at or slightly above `max(tfi)` in the fitting data**. Then the curve is
essentially the current exponential everywhere there is data, and bends as it leaves it. The
methods sentence is one line: the saturation point was placed at the upper limit of the observed
range.

The bend is not sharp: at `tfi = tfi_50` the slope is already `b / 2`, so putting it exactly at
the data maximum does change the fit in the upper part of the observed range. That may be an
improvement, but it is a choice, so **run it with `tfi_50` at the maximum and a little beyond**
and compare.

Keep `b` positivity-constrained the way `c_fi_raw` already is. In the linear region `b` plays the
role of the old `c_tfi`.

### Coverage

This softens *lightning ignition* only. Escape and spread carry the same unbounded `tfi` from
`tfi_calc()` and still compound multiplicatively, so the Manso band will be reduced, not removed.
That is accepted: see the note on conservatism above, and section 6, which removes the
ignition-side contribution to the Manso by a different route.

## 3. Optional: saturating the human distance effects (not needed)

The same treatment can be applied to the distance terms, replacing `c * d` with a bounded kernel:

```
eta = c_vfi*vfi + c_tfi*tfi + c_r*exp(-d_r/r_r) + c_h*exp(-d_h/r_h)
```

Each distance term is then bounded in `[0, c]` with a fitted influence range, `eta` is bounded
above where the near-delta kernel is, and `exp()` is kept, so the intercept stays unidentifiable
and never has to be priored. A whole-linear-predictor logistic would do the same job but couples
everything: once cells sit on the plateau the vegetation and topography effects get compressed
there too, so covariates start interacting through the saturation instead of combining additively
in log space.

**Not planned.** The distance effects are not the problem. In the human model the missing piece is
the spatial field (section 1), and the strong selection for near-road cells is real: fires
genuinely are close to roads and roads genuinely are rare in the landscape. Recorded here in case
the field turns out not to be enough.

## 4. Larger background sample

`theta_land` is `sum(exp(eta))` over a fixed sample of `nland = 10000` landscape cells, an
unweighted Monte Carlo estimate of the landscape integral. With the near-delta road kernel, that
sum is dominated by the handful of sampled cells nearest a road. `E[log(S_hat)] <= log(S_true)` by
Jensen, and the underestimate is worst for the parameter values that make the integrand most
heavy-tailed, which are the steepest road effects. So the road effect is plausibly biased upward,
independently of the fact that the selection itself is real.

**Increase `nland`, do not stratify.** Stratifying towards near-road cells would only be correct
with inclusion-probability weights, `sum(w_j * exp(eta_j))`, which the current code does not have;
unweighted stratification would inflate the near-road share of the denominator and shrink
`c_dist_r`, suppressing a real signal.

More samples is cheap: `X_pop_fi` is `ny x nland x nfi`, so `nland = 1e5` over 24 years is ~38 MB
and a 4.8 Mflop matvec per leapfrog step.

To settle the magnitude rather than argue it: fix the parameters at the current posterior mean,
draw several independent background samples at 1e4, 1e5 and 1e6, and compare the spread of
`log(theta_land)` at each size against the log-likelihood differences that separate plausible
`c_dist_r` values. Note the saturating forms of sections 2 and 3 help here too, since a bounded
integrand has far lighter tails and the Jensen bias largely goes away.

## 5. Stan reimplementation, in log space

The current `ignition_model.stan` computes `theta_land` and `theta_point` on the natural scale and
forms the likelihood as `log(pp / (pp + theta_land))`, which is overflow-prone with large `eta`.
Since the linear predictor is being restructured anyway, move the whole location likelihood to log
space:

```stan
// per cause c
vector[nland] log_eta_pop = log_inv_logit(a[c] + b[c] * tfi_pop)
                            + c_vfi[c] * vfi_pop[y]
                            + B_pop * beta[c];
real log_theta_land = log_sum_exp(log_eta_pop);
// ...
target += log_eta_point[i] - log_sum_exp(log_eta_point[i], log_theta_land);
```

Points to carry into the rewrite:

- `theta_land` stops being a single matrix-vector product, because `tfi` and `vfi` now go through
  different functions. `X_pop_fi[y]` has to be split into separate `tfi_pop` and `vfi_pop[y]`
  vectors.
- Use Stan's `log_inv_logit` rather than `log(inv_logit(...))`.
- `log_sum_exp` for the denominator, and the two-argument form for the normalisation of each
  point, replacing `log(pp / (pp + theta_land))`.
- The basis `B` enters as plain data (`matrix[nland, k] B_pop`, `matrix[npoint, k] B_ig`). At
  `nland = 1e5` and `k = 40` that is ~32 MB of Stan data, which is fine.
- The temporal (negative binomial) part of the model is unchanged.

## 6. Splitting the ignition rate between the buffer and the park

### Why this is not cosmetic

Ignitions are simulated over PNNH + 10 km so that fires can enter the park from outside, but
**every metric is computed on PNNH land only** (burn probability, proportion of burnable area
burned). The buffer is never measured, and it is also the part of the landscape with no ignition
data at all.

That combination distorts the calibration, not just the map. The simulator is recalibrated by
lowering the steps-regression intercept (`steps_int_shift`, the thesis' `gamma_0,6 - 0.95`) until
the simulated PNNH burn probability matches the observed one from chapter 3. If the Manso absorbs
a large share of the simulated burned area, that constant has to be pushed up to bring PNNH back
to a reasonable value, which means **the model compensates for misallocated ignitions by making
every fire in the park spread more**. The bias is not confined to the area nobody looks at: it
leaks into the spread recalibration for the whole park, and it forces the Manso itself to an
implausible total burn probability along the way.

The root cause is that the spatial model is a **single softmax over the whole simulated
landscape**. A data-free region with high extrapolated `eta` does not merely get too many
ignitions of its own: it competes for a fixed pool and takes them away from the park.

### The change: allocate by burnable area, then normalise within each region

Each fortnight, split the fortnight's ignitions between the two regions **in proportion to their
burnable area**, and then run the spatial model **separately inside each**:

| Area | Share of the fortnight's ignitions | Location within the region |
|------|------------------------------------|----------------------------|
| **Inside PNNH** | `A_pnnh_burnable / A_total_burnable` | modelled: `exp(eta)` softmax **normalised over PNNH burnable cells** |
| **Buffer (10 km ring)** | `A_buffer_burnable / A_total_burnable` | modelled: `exp(eta)` softmax **normalised over buffer burnable cells** |

This is the **preferred strategy**. The competition that the softmax creates is *contained*
within each region instead of running across the whole landscape. The Manso can still drag most
of the buffer's ignitions, which is fine and may well be right, but it can no longer reach into
the park's allocation. And unlike the flat variant below, the covariate information in the buffer
is kept: roads, vegetation and topography south and east of the park still place the ignitions
they are given.

Both regions use the same per-burnable-km2 rate, so the mean intensity per burnable cell matches
on the two sides of the line by construction, and the inward flux of fires across the park
boundary stays about right, which is the whole reason the buffer exists.

This composes cleanly with section 1: the field is at its prior mean outside the fitting extent
anyway, so it only ever acts inside PNNH, which is exactly where it has data. Per-region
normalisation preserves the scale cancellation, so the field's additive constant still drops out
within each region independently.

### Variant: flat in the buffer

The more conservative version locates the buffer's share **uniformly over its burnable cells**,
discarding `eta` outside the park entirely, on the grounds that there is no data there. Recorded
as the fallback if the modelled buffer still concentrates too hard. It throws away real
information (roads south of PNNH are still roads, and the distance relationship plausibly
transfers), and it produces a *larger* boundary artefact, see below. If it is ever used, a middle
position worth considering is to keep the model for **human** ignitions in the buffer and go flat
only for **lightning**, where the elevation extrapolation is the actual problem.

### Drawing the two counts

Prefer **binomial thinning of a single negative-binomial draw** (draw `N_total` for the whole
buffered area, then `N_buffer ~ Binomial(N_total, A_buffer_burnable / A_total_burnable)`) over two
independent negative-binomial draws. Thinning a negative binomial leaves negative-binomial
marginals, so nothing is lost, and it keeps the two areas coupled through the shared draw. Two
independent draws would make them independent, which is wrong: the overdispersion is a weather
and regional phenomenon, so a fortnight that is busy inside the park is busy outside it too.

### The containment ceiling, which is worth measuring first

The most the Manso can now take is the **buffer's entire allocation**, i.e. its burnable-area
share. That ceiling is not obviously tight: a 10 km ring around a park of 7161.577 km2 with a long
perimeter is a substantial area in its own right. **Compute
`A_buffer_burnable / A_total_burnable` before assuming the containment solves the problem.** If
it comes out large, the lever is the buffer width, which is set by how far fires actually travel
and not by anything intrinsic to 10 km; a narrower ring would tighten the containment and still
serve its purpose.

### What it does and does not fix

It removes the **cross-region** competition, which was the dominant channel: the softmax was
actively concentrating the whole landscape's ignitions on the Manso. Within the buffer, and in
escape and spread everywhere, low elevation is still favoured, so the Manso will still burn more
than average. That residual is accepted (see the conservatism note above); what is removed is the
part where a data-free area competes for the park's ignitions and wins.

### The artefact to watch for

Per-region normalisation puts a step in intensity at the park line: two otherwise identical cells
straddling the boundary differ by the ratio of the two regions' mean `exp(eta)`. Since the buffer
contains the low-elevation Manso and the eastern steppe, its mean is the higher one, so buffer
cells are scaled *down* relative to what a global softmax would give them, which is the intended
effect.

Note this step is a **constant factor**, and it is smaller than the flat variant's, whose step is
`mean_pnnh(exp(eta)) / exp(eta_i)` and therefore varies cell by cell and is generally larger. Two
checks once it runs:

- **In the maps.** Any figure that draws the buffer (the thesis burn-probability panels show its
  contour) would show the step. Simplest mitigation is to mask the buffer in published maps,
  which is nearly the status quo already, since it is excluded from every metric.
- **Inside the park, near the boundary.** Plot simulated burn probability against distance to the
  PNNH boundary and look for a discontinuity in the first few km inside. If one appears, feather
  the transition over a few km rather than abandoning the split, but that adds a tuning knob and
  is probably not worth it unless the step is visible.

### In `simulate.R`

`cells_pnnh_dyn` is currently sampled as one pool (`candidate_cells <- sample(cells_pnnh_dyn,
size = nss * 2)`) and weighted by one `iprob`. The change is local: split the cell index into an
inner and a buffer pool once at setup, draw `nss` candidates from each per fortnight, and run the
existing weighting separately per pool with its own count. The importance-sampling approximation
stays valid region by region. Cost is roughly double the current ignition-placement work, which
is negligible against spread.

## Not planned: clipping `tfi`

Clipping `tfi` to its maximum observed value at prediction time would erase the Manso band
outright, costs one line, needs no refit, and would apply to ignition, escape and spread at once
(it lives in `tfi_calc()` in `R/flammability_indices_functions.R`, so it reaches the frozen
paper-1 spread fit too). It is recorded here as a **last resort only**. It is not desired: the
`tfi` effect is plausibly real, its compounding across the three sub-models may be realistic, and
a hard clip substitutes an arbitrary threshold for a modelled response.

## The escape model needs none of this

`escape_model.stan` is left as it is. Its covariate effects are small, so it neither produces the
runaway extrapolation that motivates sections 2 and 3, nor concentrates probability the way the
softmax-normalised ignition model does (escape is a per-point Bernoulli, not a competition
between cells, so an over-predicted region cannot steal probability from anywhere else). Adding a
spatial field there would spend degrees of freedom on a model that is not misbehaving.
