# manuscript-regime/

LaTeX sources for **paper 2 — the fire regime simulator + projections** (also develops the
ignition & escape models; cites the spread paper).

Conventions (see the root `README.md` / `~/Insync/Claude/repo-store-structure.md`):

- **Sources in git:** `.tex`, `.bib`, `.cls`/`.sty` are text and are committed here.
- **Final figures in git:** put publication-ready figures in `figures/` and commit them, so
  the manuscript stays **self-contained and compilable by anyone who clones the repo** without
  syncing the heavy store. Reference them repo-relative, e.g. `\graphicspath{{figures/}}` then
  `\includegraphics{fig_name}`.
- **Heavy/intermediate plots stay in the store** (`files/…`); a plotting script exports the
  chosen final figures into this `figures/` folder.
- **If a final figure is genuinely huge**, symlink `figures/` (or one file) into the store —
  LaTeX reads through a symlink transparently; the only requirement is that whoever compiles
  has run `./setup.sh` so the symlink resolves.
- **Build artifacts are gitignored** (`*.aux *.log *.bbl …`) — see root `.gitignore`.
