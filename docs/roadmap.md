# Roadmap: open tasks

**This is a living document, edited in place.** It holds **only what is still open**: open
items, the next things to do, and decisions that are still pending. It is *not* a record of what
was done: when a task here is finished, the procedure it involved goes into the corresponding
`docs/*.md` (see `CLAUDE.md` → *Roadmap discipline*) and the entry is deleted from here. History
lives in git log and, for the migration, in `docs/migration.md`.

**Last updated:** 2026-09-09 (the fire-regime season simulator's C++ redesign discussed and
written up in `docs/fire-regime.md`; four decisions taken, three still open)

Where finished work is written up:

| Finished | Written up in |
|---|---|
| Repo migration (T0–T12) | `docs/migration.md`, `docs/architecture.md` |
| Landscape preparation, study-area tiles, reduced landscapes, `wind_sd` / WindNinja drift | `docs/data-prep.md` |
| Spread validation: design, run order, results, Figs. 5–7 and S6 (the κ-truncation re-run of 2026-09-07) | `docs/spread.md` |
| Every paper figure's script, and Fig. 1's base layers moving into the store | `docs/spread.md` |
| The manuscript build (two documents, the two-column traps) and what prose is written | `docs/spread.md` → *The manuscript* |
| The four answered questions of 2026-09-02 (shape's 241, the dropped spatial signature, Fig. 1's legend placement, the software citations) | `docs/spread.md` |
| Machine setup (WindNinja build, GEE asset paths) | `README.md` → *Getting started* |
| Splitting the non-public ignition data into its own store (migration TODO #9) | `docs/architecture.md` → *The two stores*, `README.md` → *The two data stores* |
| Splitting the stage-2 hierarchical fit out of its 3,040-line monolith (tech debt #2) | `docs/spread.md` → *Stage 2: the hierarchical fit, in four scripts* |
| The ignition-escape folder's structure: canonical `fit.R` vs. the exploratory ordinal escape variant (migration TODO #6) | `docs/ignition-escape.md`, `ignition_escape/README.md` |

---

## Open items carried from the migration

Full detail in `docs/migration.md`'s TODO register.

- **TODO #7.** `fire_regime/simulate.R` / `probability_maps.R` read the canonical SMC-fitted
  spread model now, but have not been re-run against it; existing regime-simulation and
  probability-map outputs are **stale** until they are. Multi-day job (~2.5 days last time),
  launch in `tmux`, with a small `nsim` smoke test first. It would also pick up a new PNNH wind
  field (`docs/data-prep.md` → *`wind_sd` is frozen*) unless the old `.asc` files are recovered.
  **Before launching it** (whether or not the C++ redesign has happened), see the checklist below:
  at 3 workers instead of 14 this run costs days that a few cheap fixes give back.

### Before the next `simulate.R` re-run

Short, and all of it is independent of the C++ redesign.

1. **Fix `epost`.** `simulate.R:962` reads `epost <- nrow(imod)`; it should be `nrow(emod)`.
   Currently inert (both are 8000, measured 2026-09-09), so no past result is wrong, but a re-run
   is exactly when a refitted posterior would change one of them and make it bite.
2. **Decide whether the posterior hoist lands first.** It is decided in principle
   (`docs/fire-regime.md` → *Decisions taken*, DECIDED 3): one posterior draw per fire-year
   iteration instead of a fresh draw every fortnight. It **changes results** (the between-replicate
   variance grows, correctly). A ~2.5-day re-run done before the hoist produces outputs that the
   hoist then supersedes, so it is worth doing the hoist first and re-checking `steps_int_shift`
   on a small `nsim`.
3. **Take the other cheap fixes while there**: the per-fire `xyFromCell`/`cellFromXY` round trip
   collapses to `spread_row = ignition_row + 186`, the `rbind`/`c()` accumulators grow
   quadratically, and `rm()` on the stanfits after `as.matrix()` saves ~46 MB per worker. Detail
   in `docs/fire-regime.md` → *Order of work* steps 1 to 3.

## The season simulator moves into C++

Designed, not implemented, and **paused mid-discussion**. The whole discussion (diagnosis, the
six findings from reading `simulate.R` and the `FireSpread` engine, four decisions taken, three
decisions still open, and the order of work) lives in **`docs/fire-regime.md` → *Rebuilding the
season simulator in C++***. Start there; the next session's first job is the three open
decisions (Move A vs Move B, a separate `FireRegimeSim` package or not, header-only vs
registered C-callable).

