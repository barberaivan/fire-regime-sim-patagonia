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

---

## Target journal

*International Journal of Wildland Fire*, Research Article; rules and sources in
`manuscript-spread/ijwf/guidelines/IWJF_guidelines.md`; build with `make` in
`manuscript-spread/ijwf/` (`make words` checks the 6000/200-word budgets). The paper says
**235 = 57 + 178** fires throughout (`docs/spread.md` → *How many fires?*).

---

## Next step: writing paper sections

Do all this without asking details to Iván. If in doubt, decide and write
the question here so he can decide/review tomorrow.

All the computation and every figure are done. What is left is prose writing
(plus captions). The manuscript-spread/designing.txt describes the results 
and supplementary sections, by simply describing the figures. 
Use that to have a layout. Whenever it's intended to 
be the same as in the thesis, you can inspire from what I did there, adapting
figures, numbers, but almost the same structure.
The methods are far too long. Do not make shorter now, but try not to extend so
much; in the end we will have to cut text. Inspire from the thesis in length
(considering the length of the spread-only parts, not regime-simulation).

- Edit the validation section of methods, based on what was done (check code and docs/). 
  It was drafted before the runs finished. Move it to the past tense too.
  Include the study area figure in methods too, and write its caption.
  Commit and push.

- Write Results, including all figures, its captions, and tables if required.
  Consider the notes in `docs/spread.md` → *Results of the validation*
  and *Why the model cannot make an elongated fire*.
  Commit and push.
  
- Write a small draft of the discussion, not a full draft, just a draft of some 
  paragraphs including what is mentioned about validation in docs/spread.md 
  (*Why the model cannot make an elongated fire*).

- Write the supplementary information, including all its figures and captions. 
  As this is just like in the thesis, this can be simply a translation of it.
  Commit and push.

[Notes on figures]

- **Fig. 1, which legend layout.** Now we go for the stacked version, but keep both. 

- **Figs. 2 and S2 now label the FWI legend in anomaly units** (-0.60 / 0.86 / 2.38) instead of
  the fit's standardized values (-1.614 / 0 / 1.672), so Figs. 2, 3 and 4 share one FWI scale.
  Take this into account when writing the caption or results.

[A tidy-up task]

- **Fig. 1's base layers are outside the store.** We need to copy them to the store, 
  putting them in the folders you think are appropriate. Do it and adapt the code
  accordingly (maybe a study_area_figure_layers folder in data/?). In that case, put 
  there also the vegetation_merged layer, deleting its own folder afterwards.
  
  The elevation mosaic (240 MB), the lakes and
  the country/province shapefiles are still in `~/Insync/patagonian_fires paper/study area map/`
  and `~/Insync/Mapa vegetación WWF - Lara et al. 1999/`, reached through two new `R/config.R`
  entries. Decide whether to copy that folder into the store (the figure then rebuilds on any
  machine) or leave it machine-local. The vegetation raster is no longer among them: panel C now
  reads `data/vegetation_merged/vegetation_merged_120m.tif`, which *is* in the store.

  Commit and push when done.