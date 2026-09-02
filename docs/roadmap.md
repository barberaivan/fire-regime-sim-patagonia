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
| Every paper figure's script, and Fig. 1's base layers moving into the store | `docs/spread.md` |
| The manuscript build (two documents, the two-column traps) and what prose is written | `docs/spread.md` → *The manuscript* |
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

---

## Target journal

*International Journal of Wildland Fire*, Research Article; rules and sources in
`manuscript-spread/ijwf/guidelines/IWJF_guidelines.md`; build with `make` in
`manuscript-spread/ijwf/` (`make words` checks the 6000/200-word budgets). The paper says
**235 = 57 + 178** fires throughout (`docs/spread.md` → *How many fires?*).

---

## Next step: finishing the paper

Methods, Results, the supplementary and a partial Discussion are written (see
`docs/spread.md` → *The manuscript*). What is left:

- **Introduction.** Still `Bla bla`.

- **Conclusion**, then the **abstract** (200 words, the six structured labels), the
  **keywords** (eight or more) and the **online summary** (50–80 words, three sentences).

- **Finish the Discussion.** The comment block at the top of the section names the three
  missing pieces: what the fitted model says about spread in this region; the two-stage
  ABC fit as a method, against the thesis-era estimation; and what it all means for the
  regime simulator of paper 2.

- **The cutting pass.** `make words` is at **~5690 of 6000** with the Introduction and the
  Conclusion still stubs, so the Methods have to lose several hundred words. The obvious
  candidates are the neighbourhood matrices $G$ and $A$, the long justification of the
  hierarchical structure, and the tile-margin argument in the validation subsection —
  all of which could move to the supplementary, which has no budget.

- **Author block.** Affiliations, ORCIDs, co-authors and the author-contributions
  statement are all still template text.

### Questions for Iván (decide/review)

1. **Fig. 7's FWI axis is on the fit's standardized scale** (`-1.6 … 1.9`) while Figs. 2–4
   are on the anomaly scale (`-0.60 … 2.38`). One figure disagrees with three. Convert
   Fig. 7 in `spread/figure_validation_metrics.R`, or leave it and let the caption carry
   the difference? The caption currently says so explicitly.
2. **The shape reference set is 241 mapped perimeters**, not the 235 = 57 + 178 the paper
   says everywhere else — shape needs no weather and no ignition point, so it can use the
   six fires the fit cannot. The Methods now state 241 and say why. Accept, or re-run the
   shape analysis on the 235 for one number throughout?
3. **The spatial signature is out of the paper**, following the 2026-08-31 decision to drop
   `vfi`/`tfi` from the figures: no figure carried it, so its Methods paragraph went too.
   That loses a real negative result (the simulated `tfi` edge signature has the wrong sign
   at small sizes). Leave it out, or bring it back as a supplementary figure?
4. **Fig. 1 still builds both variants.** Only `stacked` is in the paper. Drop `below` from
   `variants` in `spread/figure_study_area.R` and let the file name lose its suffix?
5. **The `R` bibliography entry says 2022** while the Methods say R 4.5.3. Same for any
   other package whose `note` field has drifted from the installed version.
