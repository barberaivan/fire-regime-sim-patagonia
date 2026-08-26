# IJWF — author requirements (extracted)

Compiled 2026-08-26 from the sources below. **Sources are cited per section**; when in doubt
go back to the source, the pages change.

| Key | Source |
|-----|--------|
| **[GEN]** | CSIRO Publishing general author instructions — <https://connectsci.au/wf/pages/author-instructions> |
| **[WF]** | *International Journal of Wildland Fire* journal-specific instructions — <https://connectsci.au/wf/pages/wf-authors> |
| **[HARV]** | `Harvard-refs-styly-examples.pdf` (local) = <https://connectsci.au/DocumentLibrary/Harvard-refs.pdf> |
| **[CHK]** | `Manuscript-Checklists.pdf` (local) |
| **[TMPL]** | `CSIRO_LaTeX_Author_Template.zip` + `CSIRO_LaTeX_Author_Guide.pdf` (local) |

Local companions in this folder: the two PDFs above, the LaTeX template zip, and the author
guide PDF. The initialised manuscript lives in **`../ijwf/`**.

---

## 1. Article type and word limit  [WF]

| Type | Limit |
|------|-------|
| **Research Article** ← *our target* | **6000 words** |
| Research Note | 3000 words; 3–5 tables/figures max |
| Review | 9000 words |
| Perspective | 1000–4000 words (usually commissioned) |
| Comment | 2000 words (on papers from the past 12 months) |
| Response | 1000 words |
| Book Review | ~1000 words |

> "Maximum of 6000 words, including text from the introduction to the conclusion (excludes
> title, abstract, references, figure captions and tables)" [WF]

So the 6000 words are **Introduction → Conclusion only**. Not counted: title, abstract,
references, figure captions, tables. (Acknowledgements / author statements are outside the
Introduction–Conclusion span too.)

Research Articles may have "a sufficient number of figures and tables to present the research
effectively" — no fixed cap. [WF]

## 2. Abstract  [WF]

- **≤ 200 words** — "Abstracts of Research Articles and Research Notes should not exceed 200 words".
- **Structured**, with these labelled sections, in this order:
  **Background; Aims; Methods; Key results; Conclusions; Implications.**
- Should state rationale, aims/objectives, methods, findings, impact. **No citations, equations,
  lists, tables or figures.** Include the paper's keywords in it. Abbreviations defined in the
  abstract must be defined **again** at first use in the body. [GEN]

## 3. Keywords  [GEN] [CHK]

- **Eight or more** — "I have provided eight or more keywords" [CHK]; "Minimum eight keywords
  recommended" [GEN].
- Put keywords in the title where possible, and in the abstract. [GEN]

## 4. Plain language / online summary  [GEN]

Not listed as compulsory for IJWF on [WF], but the general instructions and the LaTeX template
provide it (`onlinesummarytext` environment):

- **50–80 words**, three sentences, for interested non-experts, no jargon:
  (1) engage the reader / why the area matters, (2) the problem + the main discovery,
  (3) the bigger picture (implications/impact). Optional image (with permission + photographer
  credit).

## 5. Structure of the manuscript  [GEN]

> "title page and author information, abstract, keywords, body text (e.g. Introduction,
> Materials and methods, Results, Discussion, tables, figure captions, figures), author
> statements, references, supplementary material."

## 6. Compulsory author statements  [TMPL] [WF] [CHK]

At the end of the manuscript (LaTeX template's `framedbox`):

| Statement | Compulsory? |
|-----------|-------------|
| **Data availability** | **yes** |
| **Conflicts of interest** | **yes** — if none: "The authors declare that they have no conflicts of interest." |
| **Declaration of funding** | **yes** — grant numbers where available; if none: "This research did not receive any specific funding." |
| Acknowledgements | no |
| Author contributions | no |
| **Declaration of use of AI** | if AI was used |
| Ethics statement | if human/animal subjects (also needed in Methods) |
| Author biographies | some paper types only |

## 7. Authors, affiliations, ORCID  [GEN] [CHK]

- Full first + last names of every author; affiliation = department, institution, city, state,
  country; uppercase superscript letters link authors to affiliations.
- Corresponding author marked with `*` and an email address.
- **ORCID required for the submitting author**, recommended for all — and co-authors must
  **link their ORCID to their ScholarOne account before acceptance**; it cannot be added later.
- AI tools cannot be listed as authors. [GEN]

## 8. Formatting  [GEN] [WF] [TMPL]

- **Format-free submission is accepted**: "You can submit without worrying about formatting to
  the journal's specific requirements, present your manuscript in the format you choose, with
  references in the style you prefer." Journal style "is mostly applied by the production team
  after acceptance." [WF] — *but* word limits, the structured abstract, line numbers and the
  author statements are still enforced at submission [CHK].
- **Line numbers: required, continuous** [GEN] [CHK] → LaTeX class option `linenum`.
- **SI units**; non-SI values in parentheses. Either solidus (mL/day) or negative exponent
  (mL day⁻¹) — be consistent. Avoid double solidus. [GEN] [TMPL]
- Define abbreviations at first use, separately in abstract and body. [GEN]
- Equations must be editable (real LaTeX, not images); cite as "Eqn 1". [GEN]
- Footnotes: avoid in body text. [GEN]
- **Australian English spelling** throughout. [TMPL] Inclusive language required. [GEN]
- Headings: up to 5 levels (`\section` … `\subparagraph`). IJWF does **not** number headings. [TMPL]

## 9. Species names  [WF] [GEN]

> "Please list the scientific name and authority with the common name of species at the first
> occurrence and then use either name consistently" [WF]

Italicise full scientific names at first appearance; abbreviate the genus thereafter. [GEN]

## 10. Figures and tables  [GEN] [CHK] [TMPL]

- Numbered sequentially in order of first citation in the text; every figure/table must be
  cited (`Fig. 1`, `Table 1`).
- Captions must let the item **stand alone**; define any abbreviation not already defined.
- **Tables must be editable** (LaTeX/Word/Excel) — never images. Avoid excessive column
  subdivision and coloured shading; explain bold/italics in a table footnote.
- Figures: high resolution, legible, colour encouraged; **supplied as separate files at best
  quality for the revised manuscript**, with the captions kept in the manuscript.
- Permission + credit needed for any reused/third-party image.

## 11. References — Harvard  [WF] [HARV]

**In-text**
- Author + year: `(Smith 2024)`.
- Several together: **chronological**, semicolon-separated `(Bloggs 2017; Doe 2024)`; same year →
  alphabetical.
- Two authors joined by "and"; three or more → "*et al.*" after the first author.
- Direct quote → include page: `(Smith et al. 2024, p. 6)`.

**Reference list**
- Alphabetical by first author surname, then chronological.
- **Full titles; journal names NOT abbreviated.**
- All author names where possible; **minimum three then "et al."**; never ellipses.
- Same author + year → italic letter suffixes (2023*a*, 2023*b*).
- Minimum fields: author surnames + initials, year, title of work, publication title, volume,
  page range, publisher (books/reports), URL/DOI where available. **Include DOIs.**
- In press: **include**. Datasets and preprints: **include** (`[Dataset]`, `[Preprint]`).
- **Not** in the reference list, cite parenthetically in the text instead: unpublished reports,
  personal communications, submitted/under-review manuscripts, continuously-updated generic web
  pages, Government Acts (write Acts out in full at first mention).
- Non-English references: `[In Chinese with English title and abstract]` at the end.
- URLs: give maximum context + access date; no links to executable files. [GEN]

**Examples** — see `Harvard-refs-styly-examples.pdf`; the important shapes:

```
Journal (page range)  Povh LF, Willers N, Fleming PA (2023) Set free: an evaluation of two
                      break-away mechanisms for tracking collars. Wildlife Research 50,
                      782–291. doi:10.1071/WR21176
Journal (article ID)  Franz SC, Colavito MM, Edgeley CM (2024) From flexibility to feasibility:
                      … International Journal of Wildland Fire 33, WF24031. doi:10.1071/WF24031
Book                  Lezak MD (1983) 'Neuropsychological assessment', 2nd edn. (Oxford
                      University Press: New York, NY, USA)
Chapter               Gill AM, Bradstock R (2003) Fire regimes and biodiversity: a set of
                      postulates. In 'Australia burning: …'. (Eds G Cary, D Lindenmayer,
                      S Dovers) pp. 15–25. (CSIRO Publishing: Melbourne, Vic, Australia)
Thesis                Purcell BV (2010) Order in the pack: … PhD Thesis, University of Western
                      Sydney, NSW, Australia.
Dataset               Fiddes S, Pepler A, Saunders K, Hope P (2020) Southern Australia's climate
                      regions. (Version 1.0.0) [Dataset] Zenodo. doi:10.5281/zenodo.4265471
Web                   Stroke Foundation (2023) Clinical Guidelines for Stroke Management.
                      Available at https://… [accessed 13 November 2023]
```

Note: no comma between surname and initials, no periods in initials, year in parentheses, no
italics on the title, **volume then comma then pages**, `doi:` prefix (not a URL).

**Style files**
- LaTeX/BibTeX: `../ijwf/samplebib.bst` (`\bibliographystyle{samplebib}`), shipped with the CSIRO
  template. The author guide notes it "will produce the bibliography which is similar to sample
  style but not exactly the same"; if we tweak it, **the modified `.bst` must be submitted with
  the source files**. [TMPL]
- Zotero / pandoc (CSL): `../ijwf/international-journal-of-wildland-fire.csl`, the official CSL
  style — <https://www.zotero.org/styles/international-journal-of-wildland-fire>.
- EndNote styles: <http://www.endnote.com/support/enstyles.asp> [GEN]

## 12. Supplementary material  [GEN] [TMPL]

- Separate file(s), submitted with the manuscript; published as supplied.
- Numbered separately from the main text: `Table S1`, `Fig. S1`; cited in the text as
  "Table S1, available as Supplementary material".
- Appendices should go here where possible.
- The **model/statistical detail belongs here**, per this repo's convention (`docs/` carries the
  computational detail).

## 13. Statistics  [GEN]

> "Statistical analyses must include sufficient detail with package citations and version
> numbers … Assumptions underlying statistical methods must be clearly stated."

## 14. Submission  [WF] [GEN] [CHK]

- Platform: **ScholarOne** — <https://mc.manuscriptcentral.com/csiro-wf>.
- **Cover letter** justifying suitability + confirming not published / not under consideration
  elsewhere. [GEN]
- **At least three suggested reviewers**, excluding "current or recent collaborators, members of
  your own research institution/group or other people who could be viewed as not impartial". [WF]
- Review is **single-anonymised** → no need to anonymise the manuscript. [WF]
- Include a link to any preprint of the work. [CHK]
- Proofs: respond within **2 business days**. [GEN]
- APCs / open access / Read-and-Publish waivers:
  <https://connectsci.au/wf/pages/publishing-charges-and-waivers>.

## 15. Submission checklist  [CHK]

Before starting: fits scope · not under consideration elsewhere · read general + journal
instructions · read publishing policies · checked APC-free OA eligibility.

Ready to submit: cover letter · **≥8 keywords** · author names/affiliations correct · emails for
all authors · corresponding author identified · **conflicts + funding + data availability** ·
ethics · all references cited and listed · **word count and formatting met** · **line numbers** ·
high-resolution labelled figures with captions · preprint link.

After review: clean version + tracked version · 8 keywords · author order matches ScholarOne ·
co-author ORCIDs linked · funding matches ScholarOne · **abstract within limit and format** ·
short summary + image if required · high-res figures as separate files · editable tables and
equations · figures/tables cited · reference list matches citations · author statements ·
permissions · supplementary files separate · acknowledged people have consented.
