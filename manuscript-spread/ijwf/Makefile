# Build the IJWF spread manuscript.
#   make          -> PDF (build/spread-paper.pdf)
#   make words    -> word count of Introduction..Conclusion (the 6000-word budget)
#   make docx     -> Word version for collaborators who want to edit
#   make watch    -> rebuild the PDF on every save
#   make clean    -> remove build/

MAIN    := spread-paper
OUT     := build
PANDOC  := $(shell command -v pandoc 2>/dev/null || echo "quarto pandoc")

.PHONY: all pdf words docx watch clean

all: pdf

pdf: $(OUT)/$(MAIN).pdf

$(OUT)/$(MAIN).pdf: $(MAIN).tex references.bib
	latexmk -pdf -bibtex -interaction=nonstopmode -halt-on-error -outdir=$(OUT) $(MAIN).tex
	@echo "--> $(OUT)/$(MAIN).pdf"

# IJWF counts Introduction..Conclusion only: title, abstract, references, figure
# captions and tables are excluded. Those parts sit inside %TC:ignore blocks in
# the .tex, so texcount's "Words in text + headers" IS the number that must be <= 6000.
words:
		@texcount -inc -relaxed -total $(MAIN).tex | \
		awk '/Words in text/{t=$$4} /Words in headers/{h=$$4} \
		     /Words outside text/{c=$$6} \
		     END{printf "\n  main text + headings : %d  (limit 6000)\n", t+h; \
		          printf "  captions (excluded)  : %d\n", c; \
		          if (t+h > 6000) printf "  OVER BY %d WORDS\n", t+h-6000; else printf "  %d words to spare\n", 6000-(t+h)}'
		@echo "  abstract (limit 200) :" $$(sed -n '/\\begin{abstract}/,/\\end{abstract}/p' $(MAIN).tex | detex 2>/dev/null | wc -w)

# Word version. Reference formatting comes from the official CSL style, since the
# .bst only works inside LaTeX. The CSIRO class macros (\affil, \corau, framedbox,
# onlinesummarytext ...) are not known to pandoc and are dropped — this output is
# for a collaborator's editing pass, not for submission.
docx: $(MAIN).tex references.bib
	@$(PANDOC) $(MAIN).tex --from=latex --citeproc \
		--bibliography=references.bib \
		--csl=international-journal-of-wildland-fire.csl \
		--number-sections=false \
		-o $(OUT)/$(MAIN).docx
	@echo "--> $(OUT)/$(MAIN).docx"

watch:
	latexmk -pdf -bibtex -pvc -interaction=nonstopmode -outdir=$(OUT) $(MAIN).tex

clean:
	rm -rf $(OUT)
