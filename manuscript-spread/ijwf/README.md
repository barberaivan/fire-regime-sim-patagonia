# manuscript-spread/ijwf/

Paper 1 — the fire spread model — formatted for the **International Journal of Wildland Fire**
(CSIRO Publishing), **Research Article**.

The rules this folder implements are extracted, with sources, in
[`guidelines/IWJF_guidelines.md`](guidelines/IWJF_guidelines.md).
The `.tex` header repeats the ones you have to keep honouring while writing.

## Files

| File | What it is |
|------|------------|
| `spread-paper.tex` | **the manuscript** — the only file you normally edit |
| `references.bib` | the bibliography database |
| `ijwf.bst` | **our** BibTeX style: CSIRO's `samplebib.bst` patched to match the published Harvard examples (see below). CSIRO requires a modified `.bst` to be submitted with the sources — it is committed here |
| `international-journal-of-wildland-fire.csl` | the official CSL style, for Zotero and for the Word export (the `.bst` only works inside LaTeX) |
| `CSIRO_LaTeX_Template.cls` | CSIRO's class file, unmodified |
| `Logos/` | assets the class needs |
| `Makefile` | build targets |
| the `.aux`/`.bbl`/`.log`/`.pdf` next to the `.tex` | everything the compile generates — all gitignored |

The pristine CSIRO template (class, `samplebib.bst`, Word template, author guide) is in
`guidelines/CSIRO_LaTeX_Author_Template.zip`.

## Building

Everything works with the TeX Live already on this machine — no extra packages.

**Everything is compiled in place, next to the `.tex`** — no `-outdir`, no `build/`. That is
deliberate: the editor's build (LaTeX Workshop, `latex-workshop.latex.outDir` = `%DIR%`) and
`make` then share one `.aux`/`.bbl` instead of each keeping its own, which is what used to make
citations render as `?` depending on which one had run last. All of it is gitignored.

```bash
cd manuscript-spread/ijwf
make            # -> spread-paper.pdf   (latexmk + bibtex)
make words      # the 6000-word budget and the 200-word abstract
make docx       # -> spread-paper.docx  (for collaborators who edit)
make watch      # rebuild on every save
make clean      # latexmk -C: back to the sources
```

### Editing in Positron

**LaTeX Workshop** (`James-Yu.latex-workshop`, on Open VSX) builds on save, straight into this
folder. The settings it needs are already in the Positron user settings:

```jsonc
"latex-workshop.latex.outDir": "%DIR%",   // compile in place, same files as make
"latex-workshop.latex.autoBuild.run": "onSave",
"latex-workshop.view.pdf.viewer": "tab",
```

The alternative, with zero extension setup, is `make watch` in a split terminal and a PDF
viewer open on `spread-paper.pdf`.

**Reading the errors.** Do not try to copy them out of the terminal — the whole run is written
to `spread-paper.log` in this folder, and that is the file to open (or to hand to Claude). The
useful lines are the ones starting with `!`; `grep -n '^!' spread-paper.log` finds them.

### The framedbox segfault

If a build dies with **no error message at all** — the log stops mid-sentence, `latexmk` reports
`pdflatex ... gave return code 139`, and a `spread-paper.synctex(busy)` is left behind — that is
pdflatex **segfaulting**, not an error in your text.

The cause is the compulsory author-statements box at the end of the paper. The class builds
`framedbox` as an `mdframed` inside a full-width `strip`; when the box has to be split across a
page, mdframed's split loop crashes pdftex. It shows up on the *first* pass of a clean build,
because the still-unresolved `\ref`/`\cite` placeholders shift the page breaks onto the bad
one — so passes 2 and 3 then succeed and the crash looks intermittent. `\mdfsetup{nobreak=true}`
before `\begin{framedbox}` in the `.tex` keeps the box whole and is what fixes it. Keep that line.

### Word count

IJWF counts **Introduction → Conclusion only** — title, abstract, references, figure captions
and tables do not count. Everything outside that span sits inside `%TC:ignore` blocks in the
`.tex`, so what `make words` prints under *main text + headings* is the number that has to stay
under 6000.

## The reference style

`ijwf.bst` is `samplebib.bst` (CSIRO's own, which their author guide admits is "similar to
sample style but not exactly the same") patched to reproduce the examples in
`guidelines/Harvard-refs-styly-examples.pdf`:

- authors as `Povh LF, Willers N, Fleming PA` — no comma between surname and initials, no stops
  in initials, no "and"/"&" before the last author
- `(2023) Title.` — no full stop after the year
- volume not bold: `Wildland Fire 33, WF24031`
- `doi:...` appended automatically from a `doi` field; otherwise `Available at \url{...}` from `url`
- books as `` `Title', 2nd edn. (Publisher: City, Country) ``
- chapters as ``In `Booktitle'. (Eds G Cary, D Lindenmayer, S Dovers) pp. 15--25. (Publisher: City)``
- theses as `Title. PhD Thesis, University, Place.`
- article titles keep the capitalisation you typed — brace anything that must stay capitalised

Verified against every worked example in the CSIRO PDF. Two things it cannot do for you:

1. **Multiple citations in one `\citep{a,b}` are printed in the order you write them** — the
   class loads natbib without `sort`, and IJWF wants them chronological. Order the keys yourself.
2. Datasets/preprints via `@misc` need the `[Dataset]` / `[Preprint]` tag inside the `title`
   field to land in the right place.
3. **A DOI containing an underscore has to be escaped in the `.bib`** (`10.1007/0-387-21710-X\_9`)
   — the style writes the `doi` field into the `.bbl` as plain text, so a bare `_` is a
   "Missing $ inserted" fatal error.

If you prefer to keep the library in Zotero, use the `.csl` file instead and check the output
against the same PDF.

## Word version for collaborators

`make docx` runs the `.tex` through pandoc with the CSL style. The body, headings, abstract,
keywords, tables, equations and the formatted reference list all survive. The CSIRO-specific
macros (`\author[A]`, `\affil`, `\corau`, `framedbox`, `onlinesummarytext`) mean nothing to
pandoc and are dropped, so the title block and the author statements have to be pasted back in
if the collaborator needs to see them. That is fine for an editing pass; the submission always
goes out of LaTeX.

Coming back the other way: ask for the edited `.docx`, then
`quarto pandoc edited.docx -t markdown` to read the changes, or open it and transcribe. Do not
round-trip the Word file back into the `.tex` — the LaTeX source stays the single source of truth.

## The supplementary

`supplementary.tex` is its own document — IJWF numbers supplementary items separately
(Fig. S1, Eqn S1) and wants them submitted as separate file(s). It uses the plain
`article` class, not the CSIRO one (which exists to lay out an *article*: title block,
running heads, two columns, author statements), but shares `references.bib` and `ijwf.bst`
with the paper, so a key cited in both prints identically.

```bash
make supp       # -> supplementary.pdf
make            # both PDFs
```

Its content is a translation of the thesis's chapter 4 appendix, renotated to the
manuscript's symbols (see `docs/spread.md` → *Notation in the manuscript deliberately
differs from the thesis*). Cross-references into the paper are written by hand
("Eqn~2 of the main text"): the two documents do not share an `.aux`, so `\ref` cannot
reach across.
