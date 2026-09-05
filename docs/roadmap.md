# Roadmap — open tasks

**This is a living document — edit it in place.** It holds **only what is still open**: open
items, the next things to do, and decisions that are still pending. It is *not* a record of what
was done — when a task here is finished, the procedure it involved goes into the corresponding
`docs/*.md` (see `CLAUDE.md` → *Roadmap discipline*) and the entry is deleted from here. History
lives in git log and, for the migration, in `docs/migration.md`.

**Last updated:** 2026-09-05

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

## Next steps 2026-09-05

### General comments

We can use 6000 words (not including table and fig captions). Methods and results must be
cut significantly. Dedicate ~1500 words for each big section: 
intro, methods, results, and discussion.
The idea to cut methods:
  tell the main ideal with little formal details; these go to supp.
To cut resutls: 
  choose the main results. Second ones may be mentioned very briefly and developed in
  supp. Follow the thesis here. For example, the corr between parameters may be 
  only mentioned briefly in the main, and developed in supp.

In these notes my english is quite poor, with expressions like "low-data" that 
refer to data not very good to inform spread: we don't have ROS recorded,
nor daily advance, nor exact date. Find a way to express it correctly. 

Resolve all alone and write in this document what made you doubt so Iván 
reviews with more attention.

### Write Introduction and Discussion

Below I describe what the Intro and Disc should have. This is probably
mentioned in the thesis. When writing the draf of this sections, 
Claude must read the thesis and identify which parts apply to this paper
vs which ones are purely for the fire-regime simulation paper 
(not spread-specific). If some aspects are mentioned in the thesis 
but not here, include them and tell this to Iván.
It is likely that the widest-scope fundamentation of why fire modelling
corresponds to both this paper and the fire-regime one. So do not be affraid
of copying ideas from the thesis chapter 4. 
When we write the fire-regime paper we can easily paraphrase the text
if it becomes redundant.

read the md files at 
manuscript-spread/notes (except journal_choose, not useful now) to 
take references and nurture the intro and disc.

Introduction must have:

- Importance of fire simulation modelling to understand future
  trajectories of the system and counterfactuals based on 
  management and climatic scenarios.
- A very brief survey of kind of fire spread models: 
  very detailed and data-parameter hungry ones vs. simpler ones
  aimed at reproducing fire-regime properties.
- Importance of simulation models for patagonia, the Morales 2015
  experience, data-limitation.
- Our proposal of developing a small-parameters, small-data requirement
  and computationally cheap model. We say in intro that our simpler
  approach is an easy way to get a low-parameter, limited-data model
  running. However, in the discussion we will admit that better
  spread engines are compatible with cheap, low-parameter, low-data 
  settings. But we cannot say bluntly in a paper "well, we did this
  because we did not know so much about the good fire models nor about
  how to program them (I know now), so we went with what we knew". 
  So the introduction is honest with what we thought at the beggining,
  and the discussion is honest with what we know now.
  
Discussion main messages:

- Our model recovered general properties of fire behaviour, both 
  recognized everywhere and from our system:
  spread dominated by wind and slope, with other variables taking smaller
  effects. negative correlation among wind and slope parameters is very
  reallistic, point it out, and also mention this in the results. 
- Bad properties of our model: the spread engine has a bad geometry;
  We should say elegantly that in the attempt to make a simple, cheap 
  model we simplified parts of the spread process that had a terrible 
  effect on the performance. 
  An alternative should be to use the same spread geometric engine as 
  the standard models (e.g., MTT flammap, cell2fire), but replace the 
  parameter-data-hungry fuel-flammability functions with our empirical
  approach, like ROS = f(VFI, TFI, FWI). That would be a nice merge.
- Our approach of simplifiying the spread process as one-time may not be 
  bad, and with better data, that one-time spread could be one day, not
  15. Now, with more large fires and a database of dayly advance
  (I saw one sometime ago, one that reconstructs daily fire polygons
  from virs or modis) a model could be fit. Anyway, that systematic
  data bases lack small fires, so our strategy of complementing data
  sources to fit some parameters should still be use. 
  For example, the main spread functions are fitted from large fires 
  with data, but with a small number of parameters may be tuned from 
  a larger set. 
- The hierarchical structure could still serve to simulate variability,
  even if a better model explains more variability. For example, 
  suppression data may be available for a few fires, and we could have it
  as a latent variable that controls initial spread, explaining
  the occurrence of small or large fires. Then we could simulate it.
- We could also treat weather and ignition point of small fires with 
  uncertain/unavailable data as parameters to estimate, assigning
  informative priors. Both start day and ignition point could be 
  estimated, and satellite data could provide bounds for those parameters.

The discussion (and conclusion) must be very explicit about what we aportamos
here:
  - simplifications on the model that are useful when data is limited,
  - parameters fitted from different data types (size-matching, and ignition
    point known),
  - hierarchical structure,
  - ABC for likelihood-free setting, and its adaptation for the hierarchical 
    structure.

All these are very valuable aportes for fire-spread simulators aimed at simulating
fire regimes in low-data settings, and they are not made invalid for having 
used an inferior spread engine.

In both sections, you must write citing papers. Not terribly extensively,
we have little space, but do not forget the most relevant ones.
Follow the thesis style and citation density, and take the refs from the 
md files above, and also from the thesis.


### Write: 

- Conclusion,
- Abstract, with its subsections.

### Reduce

Materials and Methods and Results. (moving parts or large details to the supp.)

- **Author block.** Affiliations, ORCIDs, co-authors and the author-contributions
  statement are all still template text. Iván fills this.
