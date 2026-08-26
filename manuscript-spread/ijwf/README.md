# manuscript-spread/ijwf/

Paper 1 — the fire spread model — formatted for the **International Journal of Wildland Fire**
(CSIRO Publishing), **Research Article**.

The rules this folder implements are extracted, with sources, in
[`../IJWF_guidelines/IWJF_guidelines.md`](../IJWF_guidelines/IWJF_guidelines.md).
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
| `build/` | everything the compile generates — gitignored |

The pristine CSIRO template (class, `samplebib.bst`, Word template, author guide) is in
`../IJWF_guidelines/CSIRO_LaTeX_Author_Template.zip`.

## Building

Everything works with the TeX Live already on this machine — no extra packages.

```bash
cd manuscript-spread/ijwf
make            # -> build/spread-paper.pdf   (latexmk + bibtex)
make words      # the 6000-word budget and the 200-word abstract
make docx       # -> build/spread-paper.docx  (for collaborators who edit)
make watch      # rebuild on every save
make clean
```

### Editing in Positron

Positron has no LaTeX extension installed. Two options:

- **Terminal**: keep `make watch` running in a split terminal and a PDF viewer open on
  `build/spread-paper.pdf`. Zero setup, works today.
- **LaTeX Workshop** (`James-Yu.latex-workshop`, on Open VSX so Positron can install it) if you
  want build-on-save, SyncTeX click-through and inline errors. Point its recipe at `latexmk`.

### Word count

IJWF counts **Introduction → Conclusion only** — title, abstract, references, figure captions
and tables do not count. Everything outside that span sits inside `%TC:ignore` blocks in the
`.tex`, so what `make words` prints under *main text + headings* is the number that has to stay
under 6000.

## The reference style

`ijwf.bst` is `samplebib.bst` (CSIRO's own, which their author guide admits is "similar to
sample style but not exactly the same") patched to reproduce the examples in
`../IJWF_guidelines/Harvard-refs-styly-examples.pdf`:

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
