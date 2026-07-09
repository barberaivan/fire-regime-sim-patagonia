# Validation strategy and journal planning — fire spread paper

This document synthesizes the validation design and journal targeting decisions
for the fire spread paper (spun off from Chapter 4 of the thesis, keeping only
the spread model + fitting; ignition/escape/projections go to a separate paper).

---

## 1. Why not classical train/test validation

Justify this explicitly in 2–3 paragraphs early in the discussion. Cite Parisien
et al. 2020 (burn probability models are evaluated against emergent regime
properties, not point predictions) and pattern-oriented modelling literature
(Grimm, Hartig).

Key points:

- **57 fires** is already small for a 6-parameter hierarchical model with
  sign-constrained priors, a Multivariate Logit-Normal on the transformed
  parameters, and an auxiliary `log(area) ~ log(steps)` regression that depends
  on the fitted `κ_f` values. Holding out 20% would degrade both the
  hyperparameter estimates and the auxiliary regression that corrects
  size bias using the 178 fires with unknown ignition point.
- The size distribution has a **heavy-tailed, peaked shape** (high peak at small
  fires, thin long tail). Estimating it from ~50 fires is not a stable target
  for a held-out test.
- The model is **deliberately underparameterized** for the process: sigmoid
  functional forms, sign restrictions, fixed `τ`, restricted parameter ranges.
  Overfitting is not the failure mode classical CV is designed to catch.
- The hierarchical structure provides its own regularization: per-fire `β_f`
  are shrunk toward the population-level posterior. A held-out fire's "test"
  coefficients would mostly reflect the population mean plus noise.
- Aim of the model is **regime-level pattern reproduction**, not point
  prediction of individual fires. This is stated already in the chapter and
  aligns with the burn-probability-model literature.

Frame the validation as: *we evaluate the simulator's ability to reproduce
statistical patterns that emerge from real fires.*

---

## 2. Validation analyses to run

Three analyses, in order of increasing informativeness. Keep it at this level —
we are **not** going to dig into per-cell stop-mechanism attribution (whether an
edge cell is unburned because propagation refused vs. because `κ` ran out).
That distinction is real but adds interpretive complexity we do not need for
this paper. Mention it as a limitation in one sentence and move on.

### 2.1 Regional size distribution (macro test)

Simulate a large number of fires (`N ≈ 1e5–1e6`) over the PNNH landscape with:

- Random ignition points sampled uniformly (or from a simple spatial rule
  matching observed ignition density if easy — not critical).
- FWI sampled from the empirical KDE of the observed 250-fire dataset.
- Posterior-mean hyperparameters (or thinned posterior draws if wanting to
  propagate uncertainty).

Compare simulated vs. observed size distribution:

- Q-Q plot in `log10(area)`.
- Discrepancy metric: KS statistic or median size-ratio per size class.

This is the direct analog of Morales 2015's regional test. It **is not "too
easy"**: it detected shape mismatches in Morales 2015 (under-representation of
small fires, over-representation of very large fires). The `γ_{0,6}` calibration
of −0.95 in the chapter fixes the *mean* burn proportion, not the *shape* of the
distribution. If the shape is off, that's a real finding.

### 2.2 Per-fire spatial signature (main test)

For each simulated fire and each observed fire, extract a coefficient vector
that summarizes how spatial predictors relate to burning at the fire's edges,
then compare the *distribution* of these vectors across fires.

#### Sampling scheme: edge pairs

Work in raster space. For each fire (simulated or the rasterized observed
polygons):

1. Identify **unburned edge cells**: unburned cells with at least one burned
   neighbor. Use a 3×3 focal sum on the burned mask.
2. For each unburned edge cell, pick **one** random burned neighbor. That's a
   pair (unburned edge cell, adjacent burned cell = "donor").
3. Look up predictors at both members of each pair. Use the same donor→receiver
   convention as the spread model itself (slope and wind computed
   directionally from donor to receiver). This matches the model's own
   structure and works identically for simulated and observed fires.

Rasterize observed polygons at the simulator's 30 m resolution (they were built
from Landsat, so this is exact). Compute pairs once for observed fires.

Implementation note: **do edge detection in the C++ simulator** and return pair
indices alongside the burn raster. Edge detection during a step is essentially
what the simulator already does. One extra output array, near-free per fire.
For 1e5–1e6 fires this cuts pair extraction from hours to minutes.

#### Regression

For each fire, fit a **conditional (matched-pair) logistic regression** with
`survival::clogit`, one stratum per pair. Response: burned status. Predictors:
IIV, IIT, slope (donor→receiver), wind term (donor→receiver). Match the model's
own predictor set — this keeps interpretation clean.

Conditional logistic conditions out fire-level confounders (FWI, day-of-fire,
suppression) via the stratum, which is exactly the property we want. The
intercept disappears — we only compare *contrasts* between paired cells. That's
fine and even preferable for this purpose.

**One random burned neighbor per unburned edge cell** (rather than all
neighbors) keeps the observed and simulated procedures cleanly matched and
avoids within-pair correlation issues.

#### Multivariate vs. univariate

Multivariate as the main analysis (~few hundred pairs per fire, 4 predictors
with sign-restricted priors — fine). Univariate versions as supplement.
Consider reporting standardized partial effects at means alongside raw `β`s;
partial effects are more stable across fires under collinearity.

### 2.3 FWI-stratified version (strongest test)

Split observed and simulated fires into FWI tertiles or quartiles and repeat
the per-fire regression within each stratum. Compare coefficient distributions
by stratum.

This tests the model's most distinctive structural claim — that spatial
coefficients change with FWI (slope effect down, wind effect up as FWI rises).
This is what distinguishes our hierarchical model from Morales 2015's flat one.

Run **two simulated datasets** for this:

- FWI drawn from the empirical KDE (matches observed marginal distribution;
  used for the size and marginal signature tests).
- FWI drawn uniformly across the modeled FWI range (used for the stratified
  test, so high-FWI strata have coverage where observed data is sparse; tests
  whether the simulator extrapolates sensibly).

---

## 3. Visualization plan

For each metric, one panel with:

- x = `log10(fire_size)`, or FWI (both worth showing; size is the primary
  axis because the metrics depend strongly on it via sample size).
- Simulated dataset shown as 2D density (`geom_density_2d_filled` or hex bins
  — raw points don't work at 1e6).
- Observed fires as points.
- Smoothed conditional means for each dataset (`geom_smooth`, GAM).

Facet by metric (each coefficient, each shape metric). Consider one figure for
size-conditional plots, one for FWI-conditional plots.

Sampling FWI for simulations from the empirical KDE makes marginal plots
look clean. Conditioning on size or FWI defends against any residual
mismatch. FWI is pixel-level standardized (only temporal variation), so no
spatial FWI complications.

---

## 4. Shape metrics (cheap complement)

All computable from burned-cell coordinates in raster space. **Do not
vectorize** — vectorization is 50–100× slower and tells us nothing more.

- **Area**: count × cell area.
- **Perimeter**: `terra::boundaries` or cell-count. Biased but consistent across
  observed and simulated → fine for comparison.
- **Compactness**: 4π·area / perimeter².
- **Elongation & orientation**: PCA on `(x, y)` coordinates of burned cells.
  Eigenvalue ratio = elongation. Leading eigenvector angle vs. wind direction =
  wind alignment. This is the highest-priority shape metric — probes
  wind-vs-slope-dominated spread directly. Sub-millisecond per fire.
- **Convex hull fill ratio**: hull from edge coordinates with `grDevices::chull`.

Plot each metric the same way: metric ~ log(size), simulated density + observed
points + smoothers.

---

## 5. Cost estimate

- Simulation: dominant. 1e5 fires: hours. 1e6 fires: overnight. Simulator is
  already C++/Rcpp (`FireSpread` package).
- Edge pair extraction: free if done inside C++, ~5–50 ms/fire in R otherwise.
- Shape metrics: sub-millisecond per fire.
- Per-fire regressions: milliseconds each. 1e6 fires → hours in R with
  `survival::clogit`.
- Plotting: minutes.

If posterior uncertainty on hyperparameters is desired, thin to ~50 posterior
draws × ~500 simulated fires per draw. Otherwise use posterior-mean
hyperparameters — for pattern comparison of this kind, that's sufficient.

---

## 6. Framing paragraphs to write

Three key sections to nail:

1. **Methods intro to validation** (~1 paragraph). Standard train/test doesn't
   apply. Explain why: data scarcity, aim of the simulator, deliberate
   underparameterization, hierarchical shrinkage as regularization. Cite
   Parisien 2020, pattern-oriented modelling.
2. **Methods for the three analyses** — clear, procedural, matching observed
   and simulated protocols. State the donor→receiver convention. State the
   sampling rule for pairs. State that conditional logistic conditions out
   fire-level effects.
3. **Discussion of what each test can and can't diagnose**. In particular,
   flag briefly (one paragraph) that the simulator's edges are a mix of
   "spread refused" and "step budget exhausted" and that this is a lumped
   representation of real-world stopping mechanisms including suppression and
   weather-event end. Do not go further than that — the sensitivity checks
   and per-cell mechanism decomposition are out of scope for this paper.

---

## 7. Journal targeting

### Decision framework

Framing determines the journal, not the other way around. Two options:

- **Applied framing**: "tool for informing fire management and long-term
  regime projection in northwestern Patagonia." Weakened by moving projections
  to a separate paper.
- **Fire-science framing**: "rigorous hierarchical spread-model fitting and
  pattern-based validation in a data-poor region." This is what the work
  actually is once the projections are gone.

Pick one before writing the abstract and intro.

### Ranked candidates

**1. International Journal of Wildland Fire (IJWF)** — top pick if the framing
is fire-science-forward. Q1 by SJR, CiteScore 5.7, open access since 2024.
Reviewers know Rothermel, Finney, FARSITE, Cell2Fire, Morales 2015 by heart —
no need to explain ABC for spread models or why a spatial CA matters. Recent
neighbor: "Evaluating a simulation-based wildfire burn probability map for the
conterminous US" (IJWF 2025).

**2. Ecological Applications** — director's pick. Aim fits *if* the applied
framing carries. Their scope statement is strict on this: "Papers describing
new methods or techniques can be published only if they describe truly new and
significant advances in methodology that can be broadly applied to the
understanding or management of environmental problems." Without projections,
the management hook softens. Possible angles: modern-period burn probability
map for detection/investment prioritization, road/settlement distance as a
lever for control difficulty, lightning-vs-human contribution to burned area.

**3. Landscape Ecology** — solid middle option (IF ~4) if wanting a broader
landscape-ecology audience. Less fire-specific reviewer expertise than IJWF.

**4. Ecological Modelling** — floor (IF ~3.5). Morales 2015 went there and it
still works, but the venue has lost ground vs. peers. Use as fallback.

### To skip

- **Methods in Ecology and Evolution** — scope statement explicitly excludes
  application papers ("not the results of applying existing or new methods").
  Would require reframing around the validation framework itself as the
  contribution, which is a real rewrite. Not now.
- **Ecography** — audience is macroecology/biogeography; a 30 m CA fit by ABC
  is more granular than their typical paper.
- **Environmental Modelling & Software** — fit is off unless leading with the
  `FireSpread` package as the contribution, which we're not.

### Recommended path

Discuss with director whether the applied framing can genuinely carry the
paper without the projections. If yes → EA. If no → IJWF. My reading of the
work as it stands is that IJWF is the more natural home, but director knows
career context better.

Decide framing first, then submit. Do not straddle.
