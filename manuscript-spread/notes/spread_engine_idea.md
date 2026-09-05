# Spread Engine Improvement: From Cellular Automaton to Elliptical Wave Propagation

## Context and Purpose

This document synthesizes a technical conversation about improving the fire spread engine used in
Barbera's thesis (Chapter 4). It is intended as a reference for drafting a section of the thesis
paper discussing this limitation and a better alternative.

The existing model is a **simple cellular automaton (CA)** where fire spreads from burning cells to
their 8 neighbors via Bernoulli trials, with propagation probability depending on vegetation type,
topography (IIT, uphill direction), and wind (cosine of alignment between wind direction and
cell-to-cell direction, scaled by wind speed). The model was fitted using ABC (Approximate Bayesian
Computation) against observed fire polygons. Key reference: Morales et al. (2015); the model
itself is described in Chapter 4 (Ecuación \ref{eq:datamodel}). Cite key already in bib:
`morales_stochastic_2015`.

---

## The Core Limitation of the CA Approach

The CA approach has a fundamental geometric problem: it is **contagion-based, not
wave-propagation-based**. Fire spread in reality follows Huygens' principle — at any point on the
fire perimeter, an independent elliptical wavelet is emitted, and the new perimeter is the envelope
of all those wavelets (Van Wagner 1969; Richards 1990, 1995). The ellipse shape encodes the
directionality of spread driven by wind and slope in a geometrically consistent way.

A CA operating on an 8-neighbor grid approximates this poorly:
- Diagonal neighbors are reachable only via paths through cardinal neighbors, introducing
  directional biases.
- The fire shape depends on the topology of the grid, not on the physics of fire spread.
- There is no concept of **travel time**: the model is atemporal within each fortnightly step, and
  the maximum number of steps (κ) is a free parameter that controls fire size in a physically
  opaque way.
- Wind enters only as a direction cosine weighting the contagion probability, not as the
  determinant of an anisotropic spread ellipse.

This means that under strong directional winds — the dominant condition in major Patagonian fires —
the CA produces fire shapes that are biased by grid geometry rather than wind direction.

---

## The Proposed Alternative: Elliptical Wave Propagation with Empirical ROS

### Two mature implementations exist in the literature:

**1. Minimum Travel Time (MTT) — Finney (2002), as implemented in FlamMap (Finney 2006)**

MTT reformulates fire growth as a shortest-path problem on a grid of nodes (cell *corners*, not
centers). Fire behavior is precomputed for each cell (rate of spread, ellipse dimensions), and the
minimum cumulative travel time from one node to all others is found using Dijkstra's algorithm
operating on transects connecting nodes. The arrival time field is then converted to isochrones
(fire perimeter positions at given times).

Key properties:
- **Nodes are cell corners**, not centers. The land area is associated with cells; nodes are
  zero-dimensional points. A transect from node A to node B crosses through one or more cells, and
  the fire behavior of each cell is applied to the segment of the transect within that cell.
- **No perimeter bookkeeping**: unlike FARSITE/Prometheus (which use Huygens perimeter expansion),
  MTT requires no correction for crossing fire fronts or merging fires. Each node's arrival time is
  computed independently. This makes it naturally parallelizable.
- **Computationally efficient**: Finney (2002) reports MTT is 8–12× faster than FARSITE for
  complex landscapes, with the speed advantage growing with landscape size and number of parallel
  processors.
- **Designed for fixed weather**: MTT was designed for conditions constant in time (used in FlamMap
  for burn probability assessment). Finney (2002) notes explicitly that "minimum travel time
  techniques may be well suited to short-range assessments of fire growth, where weather conditions
  could be assumed constant (e.g., several hours)."
- **Can handle multiple simultaneous ignition sources**: Dijkstra simply initializes multiple nodes
  with t* = 0.

**2. Cell2Fire — Pais et al. (2021)**

Cell2Fire is a raster-based fire growth simulator that applies the elliptical spread model **at the
cell level**. Each burning cell generates an ellipse oriented in the head fire direction, and fire
spreads from the center of the burning cell to the centers of adjacent cells. Head (HROS), flank
(FROS), and back (BROS) rates of spread define the ellipse axes; the ellipse is computed using the
FBP system (or any ROS model). When fire from cell i reaches the center of adjacent cell j, a new
ellipse is generated at cell j.

Key properties:
- **Simpler implementation** than MTT: operates on cell centers (not corners), no graph search
  needed.
- **Designed for Monte Carlo burn probability**: thousands of runs from random ignitions. Highly
  parallelized in C++ with OpenMP.
- **CA-like structure but geometrically correct**: unlike an 8-neighbor Bernoulli CA, the ellipse
  correctly represents anisotropic spread. The fire shape depends on wind and slope, not grid
  topology.
- Cell2Fire explicitly notes that spotting is a planned future addition (Pais et al. 2021).

---

## The Ellipse: Mathematical Structure

Both approaches share the same underlying ellipse parameterization (Anderson 1983; Catchpole et al.
1982):

- **a** = flanking spread rate (semi-minor axis)
- **b + c** = forward (head) spread rate = R_head (maximum, in direction α)
- **b − c** = backing spread rate (minimum, opposite to α)
- **α** = direction of maximum spread (from wind + slope resultant)
- **c** = offset of ignition point from ellipse center (ignition point at rear focus)

The length-to-breadth ratio LB = b/a is an empirical function of effective wind speed alone
(Anderson 1983):

```
LB = 0.936·exp(0.2566·U_eff) + 0.461·exp(−0.1548·U_eff) − 0.397
```

where U_eff is the effective mid-flame wind speed (km/h). From LB and R_head, all three ellipse
parameters can be derived. LB → 1 (circle) with no wind; LB >> 1 (elongated) with strong wind.

The travel time along a transect at angle β relative to north, crossing a cell with ellipse
parameters (a, b, c, α), is computed via Equations 1–4 of Finney (2002) — essentially finding the
angle θ on the ellipse that corresponds to the transect direction and computing the speed normal to
the front.

---

## The Empirical ROS Function: Mimicking Rothermel's Structure Without Fuel Models

Rothermel (1972) — cite key `rothermel_mathematical_1972`, already in bib — has the functional
structure:

```
R = R_base · (1 + φ_wind + φ_slope)
```

where φ_wind and φ_slope are dimensionless multipliers, and the wind+slope resultant defines α and
U_eff. This structure can be preserved while replacing R_base with an empirical function of
observable variables:

```
R_head = R_base(veg_type, NDVI, FWI) · exp(k · U_eff)
α      = direction of (wind_vec + slope_equivalent_vec)
LB     = Anderson (1983) formula applied to U_eff
```

- **R_base** is calibrated empirically from observed fire spread data, as a function of vegetation
  type, NDVI (fuel state/load proxy), and FWI (atmospheric fire danger).
- **exp(k · U_eff)** is the wind response function. The exponential form is consistent with
  McArthur's empirical models and the Canadian FBP system, and fits fire spread data better than a
  power law at high winds. One free parameter k per vegetation class.
- **Slope enters as an equivalent wind**: Rothermel provides a formula to convert slope angle to an
  equivalent upslope wind speed, so wind and slope vectors can be added before computing U_eff and
  α.
- **LB from Anderson (1983)**: this formula is empirical and does not depend on fuel type, so it
  can be borrowed directly.

This structure preserves the geometric correctness of the ellipse while replacing the fuel-model
machinery with observable inputs available in Patagonia (satellite-derived NDVI, FWI from ERA5 or
SMN, vegetation maps, digital elevation models).

---

## Computational Efficiency: Fixed Weather as an Enabler

Both MTT and Cell2Fire are substantially more computationally efficient than dynamic simulators
such as FARSITE (Finney 1998) or Prometheus, which must track and correct an explicit fire
perimeter at every timestep — merging fronts, excising crossed segments, redistributing points
along the perimeter. These serial bookkeeping tasks are expensive and do not parallelize well
(Finney 2002). In contrast, MTT and Cell2Fire are efficient for two related reasons:

**1. Fire behavior is precomputed once.** Because weather is assumed constant during a run, ROS and
ellipse parameters for each cell are calculated in a preprocessing step and do not change. This
preprocessing is embarrassingly parallel and takes less than 2% of total compute time (Finney
2002). In dynamic simulators, fire behavior must be recalculated continuously as the perimeter
evolves and weather changes.

**2. No perimeter management is needed.** MTT's arrival-time field at nodes is computed
independently for each node — the algorithm is ignorant of neighboring nodes' states on the fire
front, which is precisely what Huygens' principle assumes (Finney 2002). Cell2Fire similarly
propagates from cell centers independently. Neither requires the serial correction steps that make
FARSITE and Prometheus hard to parallelize.

Finney (2002) reports MTT being 8–12× faster than FARSITE on complex landscapes using a single
processor, with the advantage growing further when parallelized. This makes these methods
particularly well suited to burn-probability modeling, where thousands of simulations are needed to
characterize the fire regime — as in the present work.

The key constraint is that this efficiency is contingent on the fixed-weather assumption. If
weather conditions change frequently during a simulation, travel-time calculations must be
interrupted and restarted, partially losing the advantage over perimeter-expansion methods (Finney
2002). For the fortnightly timestep used here, with weather assumed constant within each fire
event, this constraint is not a limitation — it is a natural match.

---

## Why the Existing CA Is Inferior — A Draft Paragraph for the Paper

> El modelo de propagación basado en autómata celular (Ecuación X) incorpora correctamente los
> efectos direccionales del viento y la pendiente como modificadores de la probabilidad de contagio,
> y resultó práctico dada la limitada información disponible para la calibración. Sin embargo,
> hereda las limitaciones geométricas propias de los autómatas celulares en grillas regulares: la
> topología de 8 vecinos introduce sesgos angulares en la forma del incendio simulado, y el modelo
> carece de un concepto explícito de tiempo de viaje del fuego, lo que hace que el número de
> iteraciones (κ) sea un parámetro de control del tamaño del incendio con escasa interpretación
> física. Alternativas geométricamente superiores existen y han sido implementadas en simuladores
> ampliamente utilizados: tanto los autómatas celulares elípticos (Pais et al. 2021) como los
> métodos de tiempo mínimo de viaje sobre grafos de nodos (Finney 2002) aplican el principio de
> Huygens en cada paso de la simulación, produciendo formas de incendio determinadas por las
> condiciones de viento y pendiente, no por la topología de la grilla. Cualquiera de estos motores
> de propagación podría combinarse con una función empírica de velocidad de propagación de
> estructura similar a la aquí utilizada, reemplazando los modelos de combustible con variables
> derivadas de imágenes satelitales e índices atmosféricos disponibles en la región.
> Adicionalmente, ambos métodos son notablemente más eficientes desde el punto de vista
> computacional que los simuladores dinámicos como FARSITE o Prometheus — en los cuales el
> seguimiento y corrección del perímetro en cada paso limita la paralelización —, siendo esta
> eficiencia una consecuencia directa de asumir condiciones meteorológicas constantes durante cada
> simulación (Finney 2002). Esta suposición es precisamente la que se adopta en el presente modelo,
> donde cada incendio transcurre dentro de una quincena con viento y condiciones atmosféricas fijas.

---

## Full References

References marked **[IN BIB]** have their cite key confirmed in `04_modelos.tex`. The others are
new and will need to be added to `references.bib`.

---

### Anderson, H.E. (1983)
**[NEW — needs bib entry]**
Suggested key: `anderson_predicting_1983`

Anderson, H.E. (1983). *Predicting wind-driven wildland fire size and shape*. USDA Forest Service
Research Paper INT-305. Intermountain Forest and Range Experiment Station, Ogden, UT.

---

### Catchpole, E.A., de Mestre, N.J., & Gill, A.M. (1982)
**[NEW — needs bib entry]**
Suggested key: `catchpole_intensity_1982`

Catchpole, E.A., de Mestre, N.J., & Gill, A.M. (1982). Intensity of fire at its perimeter.
*Australian Forestry Research*, 12(1), 47–54.

---

### Finney, M.A. (1998)
**[IN BIB]** Cite key: `finney1998farsite`

Finney, M.A. (1998). *FARSITE: Fire Area Simulator—model development and evaluation*. USDA Forest
Service Research Paper RMRS-RP-4. Rocky Mountain Research Station, Ogden, UT.

---

### Finney, M.A. (2002)
**[NEW — needs bib entry]**
Suggested key: `finney_fire_2002`

Finney, M.A. (2002). Fire growth using minimum travel time methods. *Canadian Journal of Forest
Research*, 32(8), 1420–1424. https://doi.org/10.1139/X02-068

**This is the core algorithmic reference for MTT — the primary citation for the proposed
alternative spread engine.**

---

### Finney, M.A. (2006)
**[IN BIB]** Cite key: `finney2006overview`

Finney, M.A. (2006). An overview of FlamMap fire modeling capabilities. In P.L. Andrews & B.W.
Butler (Eds.), *Fuels Management—How to Measure Success: Conference Proceedings, 28–30 March 2006,
Portland, OR*. Proceedings RMRS-P-41, pp. 213–220. Fort Collins, CO: U.S. Department of
Agriculture, Forest Service, Rocky Mountain Research Station.

---

### Morales, J.M., Mermoz, M., Gowda, J.H., & Kitzberger, T. (2015)
**[IN BIB]** Cite key: `morales_stochastic_2015`

Morales, J.M., Mermoz, M., Gowda, J.H., & Kitzberger, T. (2015). A stochastic fire spread model
for north Patagonia based on fire occurrence maps. *Ecological Modelling*, 300, 73–80.
https://doi.org/10.1016/j.ecolmodel.2015.01.005

---

### Pais, C., Carrasco, J., Martell, D.L., Weintraub, A., & Woodruff, D.L. (2021)
**[NEW — needs bib entry]**
Suggested key: `pais_cell2fire_2021`

Pais, C., Carrasco, J., Martell, D.L., Weintraub, A., & Woodruff, D.L. (2021). Cell2Fire: A
cell-based forest fire growth model to support strategic landscape management planning. *Frontiers
in Forests and Global Change*, 4, 692706. https://doi.org/10.3389/ffgc.2021.692706

---

### Richards, G.D. (1990)
**[NEW — needs bib entry]**
Suggested key: `richards_elliptical_1990`

Richards, G.D. (1990). An elliptical growth model of forest fire fronts and its numerical solution.
*International Journal of Numerical Methods in Engineering*, 30(6), 1163–1179.
https://doi.org/10.1002/nme.1620300606

---

### Richards, G.D. (1995)
**[NEW — needs bib entry]**
Suggested key: `richards_general_1995`

Richards, G.D. (1995). A general mathematical framework for modeling two-dimensional wildland fire
spread. *International Journal of Wildland Fire*, 5(2), 63–72.
https://doi.org/10.1071/WF9950063

---

### Rothermel, R.C. (1972)
**[IN BIB]** Cite key: `rothermel_mathematical_1972`

Rothermel, R.C. (1972). *A mathematical model for predicting fire spread in wildland fuels*. USDA
Forest Service Research Paper INT-115. Intermountain Forest and Range Experiment Station, Ogden,
UT.

---

### Van Wagner, C.E. (1969)
**[NEW — needs bib entry]**
Suggested key: `van_wagner_simple_1969`

Van Wagner, C.E. (1969). A simple fire growth model. *The Forestry Chronicle*, 45(2), 103–104.
https://doi.org/10.5558/tfc45103-2

---

## Summary: What Needs to Be Added to references.bib

Five new entries are needed:

| Suggested key | Reference |
|---|---|
| `finney_fire_2002` | Finney (2002) — MTT algorithm, *Can. J. For. Res.* |
| `pais_cell2fire_2021` | Pais et al. (2021) — Cell2Fire, *Front. For. Glob. Change* |
| `anderson_predicting_1983` | Anderson (1983) — ellipse LB formula, USDA Res. Paper INT-305 |
| `catchpole_intensity_1982` | Catchpole et al. (1982) — ellipse derivations, *Aust. For. Res.* |
| `richards_elliptical_1990` | Richards (1990) — Huygens fire fronts, *Int. J. Num. Meth. Eng.* |
| `richards_general_1995` | Richards (1995) — 2D fire spread framework, *Int. J. Wildland Fire* |
| `van_wagner_simple_1969` | Van Wagner (1969) — elliptical fire shape, *For. Chron.* |

The following are **already in the bib** and can be cited directly:
`finney1998farsite`, `finney2006overview`, `morales_stochastic_2015`,
`rothermel_mathematical_1972`

