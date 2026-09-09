# Roadmap — open tasks

**This is a living document — edit it in place.** It holds **only what is still open**: open
items, the next things to do, and decisions that are still pending. It is *not* a record of what
was done — when a task here is finished, the procedure it involved goes into the corresponding
`docs/*.md` (see `CLAUDE.md` → *Roadmap discipline*) and the entry is deleted from here. History
lives in git log and, for the migration, in `docs/migration.md`.

**Last updated:** 2026-09-09 (the stage-2 hierarchical fit split out of its monolith; written up
in `docs/spread.md` → *Stage 2: the hierarchical fit, in four scripts*)

Where finished work is written up:

| Finished | Written up in |
|---|---|
| Repo migration (T0–T12) | `docs/migration.md`, `docs/architecture.md` |
| Landscape preparation, study-area tiles, reduced landscapes, `wind_sd` / WindNinja drift | `docs/data-prep.md` |
| Spread validation — design, run order, results, Figs. 5–7 and S6 (the κ-truncation re-run of 2026-09-07) | `docs/spread.md` |
| Every paper figure's script, and Fig. 1's base layers moving into the store | `docs/spread.md` |
| The manuscript build (two documents, the two-column traps) and what prose is written | `docs/spread.md` → *The manuscript* |
| The four answered questions of 2026-09-02 (shape's 241, the dropped spatial signature, Fig. 1's legend placement, the software citations) | `docs/spread.md` |
| Machine setup (WindNinja build, GEE asset paths) | `README.md` → *Getting started* |
| Splitting the non-public ignition data into its own store (migration TODO #9) | `docs/architecture.md` → *The two stores*, `README.md` → *The two data stores* |
| Splitting the stage-2 hierarchical fit out of its 3,040-line monolith (tech debt #2) | `docs/spread.md` → *Stage 2: the hierarchical fit, in four scripts* |

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

