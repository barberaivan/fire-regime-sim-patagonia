# Journal targeting — the fire spread paper

Why the spread paper is aimed at the *International Journal of Wildland Fire*, and what the
alternatives were. This file used to also carry the validation design; that has moved to
`docs/spread.md` → *Stage 3 — validation*, which documents what the code actually does.

## Decision framework

Framing determines the journal, not the other way around. Two options:

- **Applied framing**: "tool for informing fire management and long-term
  regime projection in northwestern Patagonia." Weakened by moving projections
  to a separate paper.
- **Fire-science framing**: "rigorous hierarchical spread-model fitting and
  pattern-based validation in a data-poor region." This is what the work
  actually is once the projections are gone.

Pick one before writing the abstract and intro.

## Ranked candidates

**1. International Journal of Wildland Fire (IJWF)** — top pick if the framing
is fire-science-forward. Q1 by SJR, CiteScore 5.7, open access since 2024.
Reviewers know Rothermel, Finney, FARSITE, Cell2Fire, Morales 2015 by heart —
no need to explain ABC for spread models or why a spatial CA matters. Recent
neighbor: "Evaluating a simulation-based wildfire burn probability map for the
conterminous US" (IJWF 2025). Word count: 5000 (excluding abstract, legends and
all that).

**2. Ecological Applications** — director's pick. Aim fits *if* the applied
framing carries. Their scope statement is strict on this: "Papers describing
new methods or techniques can be published only if they describe truly new and
significant advances in methodology that can be broadly applied to the
understanding or management of environmental problems." Without projections,
the management hook softens. Possible angles: modern-period burn probability
map for detection/investment prioritization, road/settlement distance as a
lever for control difficulty, lightning-vs-human contribution to burned area.

**3. Landscape Ecology** — solid middle option (IF ~4) if wanting a broader
landscape-ecology audience. Less fire-specific reviewer expertise than IJWF.

**4. Ecological Modelling** — floor (IF ~3.5). Morales 2015 went there and it
still works, but the venue has lost ground vs. peers. Use as fallback.

## To skip

- **Methods in Ecology and Evolution** — scope statement explicitly excludes
  application papers ("not the results of applying existing or new methods").
  Would require reframing around the validation framework itself as the
  contribution, which is a real rewrite. Not now.
- **Ecography** — audience is macroecology/biogeography; a 30 m CA fit by ABC
  is more granular than their typical paper.
- **Environmental Modelling & Software** — fit is off unless leading with the
  `FireSpread` package as the contribution, which we're not.

## Recommended path

Discuss with director whether the applied framing can genuinely carry the
paper without the projections. If yes → EA. If no → IJWF. My reading of the
work as it stands is that IJWF is the more natural home, but director knows
career context better.

Decide framing first, then submit. Do not straddle.