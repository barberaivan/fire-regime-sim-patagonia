# manuscript-spread/

LaTeX sources for **paper 1 — the fire spread model** (fitting procedure + validation).

```
manuscript-spread/
├── ijwf/               # the manuscript, formatted for the target journal  ← write here
│   └── guidelines/     # the journal's rules, extracted + the original CSIRO template/PDFs
├── figures/            # publication-ready figures (committed)
└── journal_choose.md   # why IJWF: the ranked journal candidates and the framing
```

**Target journal: *International Journal of Wildland Fire*** (CSIRO Publishing), Research
Article — 6000 words, 200-word structured abstract, ≥8 keywords. The rules, with their sources,
are in [`ijwf/guidelines/IWJF_guidelines.md`](ijwf/guidelines/IWJF_guidelines.md); how to build
the thing is in [`ijwf/README.md`](ijwf/README.md).

The folder is named for the journal, not for the format: if the paper is ever retargeted, that
means a new sibling folder with a different class file, and the guidelines/figures stay put.
The reasoning behind that choice is in [`journal_choose.md`](journal_choose.md); the validation
design it used to share a file with now lives in `docs/spread.md` → *Stage 3 — validation*.

Conventions (see the root `README.md` / `~/Insync/Claude/repo-store-structure.md`):

- **Sources in git:** `.tex`, `.bib`, `.cls`/`.sty`/`.bst` are text and are committed here.
- **Final figures in git:** put publication-ready figures in `figures/` and commit them, so
  the manuscript stays **self-contained and compilable by anyone who clones the repo** without
  syncing the heavy store. `ijwf/spread-paper.tex` sets `\graphicspath{{figures/}{../figures/}}`,
  so `\includegraphics{fig_name}` finds them.
- **Heavy/intermediate plots stay in the store** (`files/…`); a plotting script exports the
  chosen final figures into this `figures/` folder.
- **If a final figure is genuinely huge**, symlink `figures/` (or one file) into the store —
  LaTeX reads through a symlink transparently; the only requirement is that whoever compiles
  has run `./setup.sh` so the symlink resolves.
- **Build artifacts are gitignored** — `latexmk` compiles in place, next to the `.tex` in
  `ijwf/`, so that `make` and the editor's build-on-save share one `.aux`/`.bbl`.
