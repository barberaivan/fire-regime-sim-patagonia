# Roadmap — open tasks

**This is a living document — edit it in place.** It holds **only what is still open**: open
items, the next things to do, and decisions that are still pending. It is *not* a record of what
was done — when a task here is finished, the procedure it involved goes into the corresponding
`docs/*.md` (see `CLAUDE.md` → *Roadmap discipline*) and the entry is deleted from here. History
lives in git log and, for the migration, in `docs/migration.md`.

**Last updated:** 2026-09-01

Where finished work is written up:

| Finished | Written up in |
|---|---|
| Repo migration (T0–T12) | `docs/migration.md`, `docs/architecture.md` |
| Landscape preparation, study-area tiles, reduced landscapes, `wind_sd` / WindNinja drift | `docs/data-prep.md` |
| Spread validation — design, run order, results, Figs. 5–7 | `docs/spread.md` |
| Machine setup (WindNinja build, GEE asset paths) | `README.md` → *Getting started* |

---

## Open items carried from the migration

Full detail in `docs/migration.md`'s TODO register.

- **TODO #6** — the ignition-escape "fire size" model can't run from a fresh session (dangling
  `sizemod`); confirmed abandoned/exploratory, and not touched per the explicit instruction not
  to work on ignition-escape right now.
- **TODO #7** — `fire_regime/simulate.R` / `probability_maps.R` read the canonical SMC-fitted
  spread model now, but have not been re-run against it; existing regime-simulation and
  probability-map outputs are **stale** until they are. Multi-day job (~2.5 days last time) —
  launch in `tmux`, with a small `nsim` smoke test first. It would also pick up a new PNNH wind
  field (`docs/data-prep.md` → *`wind_sd` is frozen*) unless the old `.asc` files are recovered.
- **TODO #9** — the Bari-Kitzberger non-public data still sits inside the shareable store;
  deliberately left as an open decision (physically re-separate vs. restrict the Drive
  subfolder's permissions). Decide **before** sharing the store with anyone.

## Next steps

### 1. The spread manuscript — the active job

All the computation the paper needs is done (validation, Figs. 5–7). What is left is prose and
the remaining figures.

- **Results and Discussion** — write them against `docs/spread.md` → *Results of the validation*
  and *Why the model cannot make an elongated fire*.
- **The Validation subsection of Methods is still written as designed, not as completed** — it
  was drafted before the runs finished. Move it to the past tense.
- **Figures 1–4** — plan in `manuscript-spread/ijwf/designing.txt`. The `.tex` still carries
  `[Claude, make and add the study area figure]`.
- Figs. 5, 6 and 7 are **done** (2026-09-01) — the Fig. 5 redecoration, the Fig. 6 redesign
  (shape metrics added, `drop_unavailable` with the < 30-cell rule) and the Fig. 7 merge and
  hectare axes. Written up in `docs/spread.md` → *Burn-probability maps* and *The paper's
  validation figures*; the Fig. 6 numbers quoted there are new, since the old ones predated the
  panel-label fix. What is left on them is prose:
  - the Fig. 6 caption and Results text have to be written from the new table, and the two shape
    panels are new material for the Results — compactness under simulated random effects puts
    96 % of observed fires outside the model's median, which is the headline result in
    calibration form;
  - the Fig. 5 caption should quote the per-panel mean overlaps now printed in the panels.

Target journal *International Journal of Wildland Fire*, Research Article; rules and sources in
`manuscript-spread/ijwf/guidelines/IWJF_guidelines.md`; build with `make` in
`manuscript-spread/ijwf/` (`make words` checks the 6000/200-word budgets). The paper says
**235 = 57 + 178** fires throughout (`docs/spread.md` → *How many fires?*).

