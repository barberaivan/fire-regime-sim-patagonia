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

All the computation and every figure are done. What is left is prose.

- **Results and Discussion** — write them against `docs/spread.md` → *Results of the validation*
  and *Why the model cannot make an elongated fire*.
- **The Validation subsection of Methods is still written as designed, not as completed** — it
  was drafted before the runs finished. Move it to the past tense.
- **Captions, and the figures into the `.tex`.** Nothing in `spread-paper.tex` includes a figure
  yet, and it still carries `[Claude, make and add the study area figure]`.

**Figures are done.** All eleven — Figs. 1-7 and S1-S5 — are built, each by its own script in
`spread/`, and written to `manuscript-spread/figures/`. Procedure, colours, the traps and the
numbers are in `docs/spread.md` → *The paper's model figures* and *The paper's validation
figures*. What is left on them is prose: the captions, and the Results text for Figs. 2-4 and
6-7.

**For Iván — decisions on the figures I could not make for you**

- **Fig. 1, which legend layout.** Two versions are built, differing only in where the panel A
  and panel B keys sit: `fig1_study_area_stacked` (all three legends in the fourth column, under
  the inset — the maps stay full height) and `fig1_study_area_below` (A's key under A and B's
  under B, as the published QGIS figure has them — costs the maps about a fifth of their height).
  **Pick one**, then delete the other from `variants` at the foot of
  `spread/figure_study_area.R` and the file name loses its suffix.
- **Fig. 1, the fire palette** is now three points of one magma ramp, set at the top of the
  script: the study-area outline at `begin = 0.12` (near-black), a mapped fire at `0.45`
  (reddish-purple), a fire with a known ignition point at `0.72` (coral). Move the `begin`
  values if the two fire classes are not far enough apart in print. The lakes stay cyan — water
  should not read as a fourth level of the fire scale.
- **Fig. 1, which vegetation map panel C should show.** It draws the WWF / Lara et al. (1999)
  raster the published figure used. The spread model does *not* run on that map — it runs on the
  merged CIEFAP + Lara raster this repo builds (`docs/data-prep.md`). Showing the published one
  keeps continuity with the Fire Ecology paper; showing the merged one would show the landscape
  the model actually sees. Your call.
- **Fig. 1, three cosmetic departures from the QGIS original.** (i) The QGIS map items carry
  `mapRotation = -1.5°`; the R panels are north-up, so the tilt is gone. (ii) The fire layer is
  `patagonian_fires_spread.shp` (241 features) rather than the 238-feature base record, because
  only `_spread` carries the split ids the 57 focal fires are keyed on. (iii) `annotation_scale`
  prints only the bar's maximum ("60 km"), not the QGIS bar's 0 / 50 / 100 ticks, and the
  graticule reads "72°W / 40°S" rather than "-72°0′".
- **Fig. 1's base layers are outside the store.** The elevation mosaic (240 MB), the vegetation
  raster, the lakes and the country/province shapefiles are still in `~/Insync/patagonian_fires
  paper/study area map/` and `~/Insync/Mapa vegetación WWF - Lara et al. 1999/`, reached through
  two new `R/config.R` entries. Decide whether to copy that folder into the store (the figure
  then rebuilds on any machine) or leave it machine-local.
- **Figs. 2 and S2 now label the FWI legend in anomaly units** (-0.60 / 0.86 / 2.38) instead of
  the fit's standardized values (-1.614 / 0 / 1.672), so Figs. 2, 3 and 4 share one FWI scale.
  Check that is what you want before writing the captions.
- **Fig. S3 lost two rendering defects** that the thesis version had: ghost white-on-white strip
  labels above each row, and colliding "1.0" / "-1.0" tick labels between panels (its x breaks
  now stop at ±0.5). Nothing else about its design changed.

Target journal *International Journal of Wildland Fire*, Research Article; rules and sources in
`manuscript-spread/ijwf/guidelines/IWJF_guidelines.md`; build with `make` in
`manuscript-spread/ijwf/` (`make words` checks the 6000/200-word budgets). The paper says
**235 = 57 + 178** fires throughout (`docs/spread.md` → *How many fires?*).

