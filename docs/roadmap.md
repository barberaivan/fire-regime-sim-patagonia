# Roadmap — open tasks

**This is a living document — edit it in place.** It holds **only what is still open**: open
items, the next things to do, and decisions that are still pending. It is *not* a record of what
was done — when a task here is finished, the procedure it involved goes into the corresponding
`docs/*.md` (see `CLAUDE.md` → *Roadmap discipline*) and the entry is deleted from here. History
lives in git log and, for the migration, in `docs/migration.md`.

**Last updated:** 2026-09-05 (evening: writing pass done)

Where finished work is written up:

| Finished | Written up in |
|---|---|
| Repo migration (T0–T12) | `docs/migration.md`, `docs/architecture.md` |
| Landscape preparation, study-area tiles, reduced landscapes, `wind_sd` / WindNinja drift | `docs/data-prep.md` |
| Spread validation — design, run order, results, Figs. 5–7 | `docs/spread.md` |
| Every paper figure's script, and Fig. 1's base layers moving into the store | `docs/spread.md` |
| The manuscript build (two documents, the two-column traps) and what prose is written | `docs/spread.md` → *The manuscript* |
| The four answered questions of 2026-09-02 (shape's 241, the dropped spatial signature, Fig. 1's legend placement, the software citations) | `docs/spread.md` |
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

## Spread paper: Iván's review pass

The writing pass of 2026-09-05 is done (Introduction, Discussion, Conclusion, abstract, keywords,
online summary written; Methods and Results cut; write-up in `docs/spread.md` → *The
manuscript*). What is left is Iván's reading, and the points below are the ones Claude resolved
alone and is least sure of. Delete each once settled.

- **Author block.** Affiliations, ORCIDs, co-authors and the author-contributions statement are
  all still template text. Iván fills this. The Data availability and AI-use statements are
  template text too.

- **Decisions taken without asking, to check:**
  - *"Low-data" wording.* Rendered as "where fire behaviour is poorly documented" and, in the
    Introduction, spelled out as what the record lacks: no rate of spread, no daily
    progression, ignition point for a minority, spread date uncertain to within weeks, sparse
    weather stations. Check that "uncertain to within weeks" is not overstated.
  - *Laneri et al. 2020 is cited as Denham et al. (2020)* because Crossref lists Denham as
    first author; the thesis `.bib` had Laneri first. Confirm against the paper itself.
  - *Bazin, Dawson and Beaumont (2010, Genetics)* was chosen as the precedent for hierarchical
    ABC in *What this study contributes*. Not in the thesis; verified against Crossref only.
  - *The engine admission* is worded as: the contagion automaton was "adopted from Morales et
    al. (2015) because it was cheap and required no rate of spread". Check the tone.
  - *The vegetation paragraph* of the Discussion attributes the persisting vegetation effect
    to fuel moisture, continuity and coarse fuel as heat sink (the thesis's argument, citing
    Zylstra et al. 2016) and adds Barberá et al. 2023 for the microclimate. Check the causal
    claim "spread through them appears to remain slower".
  - *Progression datasets* are said to "resolve only fires of tens of hectares or more" at
    375–500 m; that is from the notes' rough ~50 ha figure for FEDS, not from a source.
  - *τ = 2.82* is described in the supplementary as fixed "beforehand" from a fire-size model
    fitted "to the mapped record". Confirm which data that model used.
  - *Abstract* rounds the study area to 29 000 km². Keywords: ten, alphabetical.

- **Thesis material deliberately left for the regime paper** (Iván asked to be told):
  the previous simulator's 60 m / annual-step design and its ignition model; the argument
  that Morales et al. (2015) confounded vegetation with physical factors (patterns paper);
  the general fuel- vs. moisture-limitation framing (Krawchuk, Pausas); the sigmoid vs.
  exponential extrapolation lesson; management and lightning-trend implications. Two
  thesis-discussion items were transformed rather than dropped: "ICE del PNNH now maps daily
  advance" became the global-datasets paragraph (the local product could still be named), and
  "distance to roads as a predictor of κ" became "suppression as a latent variable"; say if
  the explicit road-distance suggestion should come back.

- **Cut candidates if anything must be added:** the Results paragraph on parameter
  correlations is already minimal (developed in Fig. S3); the next cuts would be the third
  Discussion paragraph's synthetic-landscape numbers, or the Data bullets' provenance details.
