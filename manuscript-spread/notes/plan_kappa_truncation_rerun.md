# Plan: the κ truncation, the 200 k re-run, and a supplementary conditional analysis

Written 2026-09-07, after diagnosing why the spread paper's regional validation reports
simulated fires as rounder than observed and oriented **across** the wind. This file is the
brief for executing the fix. It is self-contained: read it, then work through the steps in
order.

Nothing here changes the model or the fit. It changes how many fires the regional validation
simulates, records one extra quantity per simulated fire, adds an analysis conditional on that
quantity for the supplementary, and updates the numbers the paper quotes.

---

## 1. The finding this is built on

The paper currently says (Results, *Validation: the regional simulation*, and
Table~\ref{tab:shape}) that simulated fires are rounder than observed at every size and that
their principal axis deviates 54, 58 and 60° from the wind axis, against 31, 32 and 20° for the
observed record and 45° under random orientation. A deviation **above** 45° is not noise around
random, it is an active across-wind bias, and that is what prompted the check.

What the data says, from `files/spread_validation/simulated_fires.rds` and
`files/hierarchical_model/focal_metrics.rds`:

1. **It is not the reference axis.** The metric scores both sides against the fixed 113/293°
   axis (`spread/validation_analysis.R`, `axis_dev`). Recomputing the simulated side against
   each fire's own terrain-steered wind (`wdir_burn_deg`, already saved) gives 54.1 / 55.9 /
   57.9° instead of 54.0 / 58.1 / 59.6°. Recomputing the observed side against each fire's own
   recorded event direction (`direction_use` in
   `data/climatic_data_by_fire_FWI-wind_corrected.csv`, available for 232 of the 241) gives
   29.5 / 33.6 / 21.0° instead of 31.3 / 32.1 / 19.5°. The regional wind is tight
   (`wdir_burn_deg` median 293.2, IQR 289-298, rbar 0.98), so the fixed axis is a fair
   reference on both sides.

2. **It is not the engine.** On the 57 focal fires, scored against each fire's own wind axis,
   the simulator aligns: observed median deviation 27.9°, simulated under **fitted** random
   effects 31.6° (48 % within 30°). Under **simulated** random effects it collapses to 56.9°
   (27 %), the same value as the regional experiment.

3. **It is the κ budget truncating the fire along the wind.** The automaton reaches 8
   neighbours per step, so after κ steps the burned set is confined to a square of half-width κ
   around the ignition cell. A fire runs furthest downwind, so the square clips its long axis
   first; once the along-wind extent is pinned and the flanks keep growing, the leading
   principal axis flips to across-wind. Splitting the 64,836 simulated fires by a proxy for
   truncation (`size_cells / (2κ+1)² > 0.2`) gives:

   | median | observed | simulated, free-running | simulated, κ-capped | simulated, all |
   |---|---|---|---|---|
   | compactness | 0.243 / 0.095 / 0.028 | 0.213 / 0.128 / 0.053 | 0.531 / 0.370 / 0.107 | 0.330 / 0.263 / 0.085 |
   | deviation from wind axis (°) | 31.3 / 32.1 / 19.5 | 37.4 / 31.8 / 29.6 | 67.0 / 67.0 / 68.6 | 54.0 / 58.1 / 59.6 |
   | fraction within 30° | 0.479 / 0.458 / 0.722 | 0.41 / 0.47 / 0.51 | 0.17 / 0.18 / 0.16 | 0.295 / 0.272 / 0.255 |
   | elongation | 2.06 / 1.96 / 2.57 | 1.73 / 1.70 / 1.65 | 1.33 / 1.35 / 1.40 | |

   (three values per cell: < 100 ha, 100-1000 ha, > 1000 ha). 60.1 % of the simulated fires are
   in the capped group: 47.1 % below 100 ha, 67.6 % in the middle class, 73.2 % above 1000 ha.

4. **Two independent confirmations of the mechanism.** Among free-running fires, a larger wind
   coefficient improves alignment (median deviation 43.9° at β₄ < 2 falling to 29.3° at β₄
   10-20). Among capped fires it makes alignment worse (55.9° rising to 77.2°), because a
   stronger wind makes the fire reach the square sooner along the very axis it is elongating
   on. And the orientation histogram of capped fires piles 50 % of its mass into 0-45°, i.e.
   around 23°, exactly perpendicular to the 113° wind axis, while free-running fires peak at
   105-150°, on the wind axis.

This does not overturn the discussion's existing claim that the automaton cannot make a
strongly elongated fire (the synthetic sweep, ceiling ≈ 1.92): free-running fires still reach
only 1.65-1.73 against the observed 1.96-2.57, and the largest observed fires are still far
better aligned (0.72 within 30°) than the simulator manages (0.51). It changes *how much* of
the reported shape mismatch is that structural ceiling and how much is the stopping rule.

---

## 2. What this does NOT touch

Do not re-run and do not edit:

- `spread/simulate_focal_metrics.R` and everything downstream of `focal_metrics.rds`: Fig. 5
  (`figure_burn_probability.R`), Fig. 6 (`figure_dharma_metrics.R`), Figs. S4/S5
  (`figure_focal_fit.R`), Table `tab:dharma`, and the Results subsection on re-simulating the
  mapped fires. Those come from the focal simulations, not from the regional experiment.
- The fit itself (`spread/hierarchical_fit.R`) and Figs. 2, 3, 4, S1, S2, S3.
- `spread/validation_observed.R` and `spread/validation_ignition_cells.R`. The observed side and
  the eligible ignition cells are unchanged, so `observed_signature.rds`, `observed_shape.rds`
  and `ignition_cells.rds` stay as they are.

---

## 3. Step 1: adapt `spread/validation_simulate.R`

Two changes.

**(a) A fixed proposal budget of 200,000, replacing the fires-wanted target.** The run is
currently driven by `n_target <- 50000` fires of at least 10 ha, with passes until the target
is met, which is why it ended on the odd pair 148,649 proposals / 64,836 fires. Iván's decision
is to state a round number of simulated fires instead. Expected yield at the observed
acceptance rate of 43.6 %: about 87,000 fires of at least 10 ha.

- Replace `n_target <- 50000` with `n_proposals <- 200000` in the settings block, and update the
  comment above it.
- Replace the `while (n_kept < n_target)` pass loop with a single pass over
  `prop <- draw_proposals(n_proposals)`, keeping the per-tile loop, the longest-first chunk
  ordering and the per-tile timing exactly as they are. The `accept` variable and its 1.1 safety
  factor go away; the acceptance rate becomes something the run reports at the end rather than
  something it steers by.
- In the saved `settings` list, replace `n_target = n_target` with
  `n_proposals = n_proposals`.
- Update the header comment: the script no longer proceeds in passes, and the sub-threshold
  fires are still kept in `small_sizes` so the acceptance rate stays reportable.

**(b) Record whether each fire was stopped by the κ budget.** The engine already returns it:
`simulate_fire_compare()` gives `steps_used` (see `~/dev/FireSpread/src/spread_functions.cpp`,
`List::create(Named("burned_layer"), Named("burned_ids"), Named("steps_used"))`). The C++ loop
is `while (burning_size > 0 && step < steps)` with `step` initialised to 1, so a fire that died
on its own has `steps_used < steps` and a fire still burning when the budget ran out has
`steps_used == steps`. That is the exact criterion, with no threshold to choose.

- In `simulate_one()`, add `steps_used = fire$steps_used` to the returned row (put it next to
  `shape`, before `wind`).
- Do not compute the capped flag here; derive it in the analysis as `steps_used == steps`, since
  `steps` is already a column of the saved table.
- Add a comment saying what the flag is for: fires stopped by the budget are confined to the
  square of half-width κ, which truncates them along their long axis and rotates their principal
  axis across the wind, and the supplementary conditions on it.

Everything else in the script stays: the same seed (`seed <- 20260820`), the same
`min_area_ha <- 10`, the same FWI resampling, the same tile and ignition-cell drawing.

---

## 4. Step 2: run it

From the repo root, detached, keeping the log (the paper quotes the acceptance rate and the run
is the only place it is printed):

```bash
nohup Rscript spread/validation_simulate.R > files/spread_validation/run_log.txt 2>&1 &
```

About 20-25 minutes on 14 cores (the previous 148,649 proposals took 15 minutes). It overwrites
`files/spread_validation/simulated_fires.rds`, which is in the store and not in git, so the old
file is gone once this finishes. That is intended: the paper will describe the new run.

Sanity checks on the new file before going on:

- `nrow(fires)` between 80,000 and 95,000, `n_proposals == 200000`.
- `mean(fires$steps_used == fires$steps)` is the capped share. Expect **at least** 0.60: the
  exact criterion also catches fires that used every step without reaching the square's edge,
  so it should sit somewhat above the 60.1 % the `sat > 0.2` proxy gave. If it comes out far
  below 0.5, something is wrong with the flag, stop and check.
- The median area, deviation and compactness by size class should be close to the old run's
  values quoted in section 1 above. Large departures mean something other than the sample size
  changed.

---

## 5. Step 3: adapt `spread/validation_analysis.R`

The main analysis stays over **all** simulated fires. The model does produce the capped fires,
so the headline comparison must keep them. Add the conditional analysis alongside.

- After the data are read, add `sim$capped <- sim$steps_used == sim$steps` with a comment
  giving the criterion and its meaning.
- In the `== 2. shape, by size class ==` report block, add the same shape rows computed
  separately for `capped` and for free-running fires, so the console report carries the numbers
  the supplementary table needs: compactness, deviation from the wind axis, fraction within 30°
  and elongation, by size class, for each group.
- Add the capped share overall and by size class to the report.
- Add these to `validation_summary.rds` as a new element (`truncation`), so the numbers are
  recoverable without re-running.
- Leave the main figures (`shape_by_size.png`, `signature_by_size.png`, `metrics_by_fwi.png`)
  as they are, over all fires.

Then run it (`Rscript spread/validation_analysis.R`, under a minute) and keep its console output
alongside the run log, since every number the paper quotes for this experiment comes from it.

---

## 6. Step 4: the new supplementary figure

A new script, `spread/figure_truncation.R`, writing `figS6_truncation.{png,pdf}` into
`manuscript-spread/figures/` through `save_fig()` from `R/spread_figure_functions.R`, in the
style of the other figure scripts (a header comment saying what it draws, what it reads and how
long it takes; no re-simulation).

Two panels are enough, and they are the two that show the mechanism rather than just the
outcome:

- **(A)** the distribution of the deviation from the wind axis, 0-90°, for the observed fires,
  the free-running simulated fires and the κ-capped ones, as three densities or as a histogram
  by group, with the 45° random-orientation reference marked.
- **(B)** compactness against burned area (log scale), observed fires as points, the two
  simulated groups as separate hex-bin densities or as separate GAM smoothers, in the style of
  Fig. 7B.

Use the existing palette conventions of the paper's figures. Check the supplementary's current
last figure number before fixing on S6.

---

## 7. Step 5: re-draw Fig. 7

`Rscript spread/figure_validation_metrics.R` (seconds). It reads the new
`simulated_fires.rds` automatically. Update the hard-coded "64,836" in its header comment.

---

## 8. Step 6: the numbers in `manuscript-spread/ijwf/spread-paper.tex`

Every number below comes from the regional experiment and changes with the re-run. Find them by
the quoted text, not by line number.

**Methods, *Validation*, the paragraph beginning "The second simulated many fires over the whole
study area":**

- "After running 148\,649 fires and discarding those below 10\,ha ... we obtained 64\,836
  simulated fires to compare against the 235 observed ones." The two simulation counts change.
  **Leave the 235 alone.** The code's observed reference here is the full 241 mapped fires, and
  saying 235 is a deliberate simplification of the narrative, so that one fire count runs
  through the whole paper (`docs/spread.md` → *How many fires? The four counts, reconciled*).
  Do not change it to 241 and do not raise it as a question.

**Results, *Validation: the regional simulation*:**

- "the 64\,836 simulated fires were larger than the mapped record" (the count).
- The Kolmogorov-Smirnov statistic and its P value ("$D = 0.187$ ($P = 1.1 \times 10^{-7}$)").
- The size quantiles: "median 151 against 58\,ha, 75th percentile 904 against 321\,ha, 95th
  percentile 10\,143 against 3249\,ha". Only the simulated side of each pair changes.
- The FWI-quartile medians: "the simulated median from 54 to 398\,ha".
- The whole shape paragraph: the six compactness values, the three simulated deviations, and the
  sentence about conditioning on FWI ("roughly 0.15 higher throughout", "near 35$^\circ$
  observed and 50$^\circ$ simulated").

**Table `tab:shape`:** the caption's "64\,836 simulated fires" and the three simulated rows
(compactness, deviation, fraction within 30°). The observed rows and the "Number of fires"
row do not change.

**Fig. 7 caption:** "The 64\,836 fires simulated over the whole study area".

**Discussion, *The model cannot make an elongated fire*:** "$\kappa$ drawn from the population
reproduces the fitted values closely (median 40 against 31 steps)" - the 40 is the median κ over
the simulated fires and changes. The elongation ceiling (1.92), the median wind coefficient
(4.9) and the "61 % / 78 % of the mapped fires are more elongated than the model can be" come
from the synthetic sweep and the observed record, and do **not** change.

**`manuscript-spread/ijwf/supplementary.tex`, *The regional simulation experiment*:** "One pass
of 148\,649 proposals left 64\,836 fires of at least 10\,ha (43.6\,\%)". Rewrite for the fixed
budget: 200,000 proposals, the new count, the new acceptance rate.

---

## 9. Step 7: the new supplementary subsection

Add it to `supplementary.tex` at the end of section *Validation*, after *Comparing simulated
with observed fires*. Suggested title: **How simulated fires stop, and what it does to their
shape**. It should carry, in the supplementary's voice:

- The mechanism: a simulated fire stops either because propagation failed at every edge cell or
  because the step budget κ ran out; the automaton reaches 8 neighbours per step, so a fire in
  the second group is confined to a square of half-width κ centred on its ignition cell. Because
  a fire runs furthest downwind, that square truncates it along its long axis first, and the
  leading principal axis of what is left turns across the wind.
- The criterion (`steps_used == κ`, exact, no threshold) and the share of fires it flags,
  overall and by size class.
- The table: compactness, deviation from the wind axis, fraction within 30° and elongation, by
  size class, for the observed fires and for each of the two simulated groups.
- The figure (S6), referenced from the text.
- The reading: conditional on stopping by failed propagation, the simulator's shapes are close
  to the observed ones; the mismatch reported in the main text is carried by the fires the step
  budget cut short. And the honest caveat: this conditions on an outcome of the simulation, and
  the observed record cannot be split the same way, so it is a diagnostic of where the mismatch
  comes from, not a claim that the model reproduces shape. The model does produce those capped
  fires.

Numbers go in only after the re-run. Do not copy the values from section 1 of this file into the
paper: those are from the old run and from the proxy criterion.

---

## 10. Step 8: the mention in the Discussion

The supplementary section is to be **mentioned only**, in the Discussion, in the "further
analysis shows ..." register, so that the reader takes away that we understand the simulator
better rather than that a new result is being reported. Iván's framing, to be written into
three or four sentences at the end of the subsection *The model cannot make an elongated fire*:

- Further analysis (Section~S<n> of the Supplementary material) shows that the shape mismatch is
  carried by the fires that the step budget cut short, and that fires allowed to stop on their
  own are close to the observed record in compactness and in wind alignment.
- So the automaton's geometry is perhaps not as bad as the headline comparison makes it look.
- What it needs is a regime of lower spread probability, where fires stop because propagation
  fails rather than because the budget runs out.
- But that regime is exactly the one in which fire size becomes hard to control, which is the
  same trade-off the marginal-propagation experiment already shows (elongation 5.0 at 84 ha):
  the model can be elongated or large, not both.

Keep it consistent with the paragraph above it, which already notes that κ is "a lumped stand-in
for everything that ends a fire in time".

---

## 11. Step 9: docs

- `docs/spread.md` → *Stage 3 - validation*: update the run-order table (200,000 proposals, the
  new fire count, the new timing), record the `steps_used` flag and what it is for, and add the
  truncation result under *Results of the validation*. Add `figure_truncation.R` /
  `figS6_truncation` to the per-figure table.
- `docs/roadmap.md`: while this plan is open, a one-line pointer to this file. Delete it when the
  work is done, per the roadmap discipline in `CLAUDE.md`.

---

## 12. Checks before committing

- `pdflatex` both documents from `manuscript-spread/ijwf/` (or `make`), no errors, and `make
  words` still within the 6000/200-word budgets.
- Every "64\,836" and "148\,649" is gone from the repo: `grep -rn "64\\\\,836\|148\\\\,649"
  manuscript-spread/ docs/ spread/`.
- The focal-fire numbers (0.53 / 0.11 overlap, 1.09 / 1.51 size ratio, 55 / 28 fires within a
  factor of two, Table `tab:dharma`) are untouched, since nothing they depend on was re-run.
- Conventions: no em dashes anywhere, Australian -ise spelling in the manuscript, and the
  figures written by `save_fig()` into `manuscript-spread/figures/` as both `.png` and `.pdf`.
