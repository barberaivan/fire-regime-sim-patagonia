# Fire perimeter datasets for training and calibrating spread models

Notes for the discussion section of the spread-model paper. The point to make is that the data landscape has shifted substantially in recent years: several open, remotely-sensed fire-progression datasets now exist that would allow calibration and validation of spread models at scales and resolutions unavailable when the thesis data were compiled. These can be used alone at coarse resolution, or combined with per-event fine-resolution mapping from free optical sensors, or ideally supplemented with commercial high-resolution imagery. Each source occupies a distinct point in the resolution–coverage tradeoff, so the choice depends on the modeling scale.

## Sub-daily perimeter time series from active-fire detections

**FEDS — Fire Event Data Suite (Chen et al. 2022, *Scientific Data*).** Object-based tracking system that clusters VIIRS active-fire detections (375 m, ~12 h revisit) into individual fire events and delineates half-daily perimeters and active fire fronts using an alpha-shape algorithm. Each perimeter carries an explicit overpass timestamp. The authors explicitly propose the dataset as suitable *"for calibration and evaluation of fire spread models, estimation of near-real-time wildfire emissions, and as means for prescribing initial conditions in fire forecast models."* Originally released for California 2012–2020; the methodology is global and code is open (Python).

- Strengths: sub-daily temporal resolution, explicit timestamps, active-front geometry (not just perimeter), designed for spread-model use.
- Limitations: only detects fires large enough to trigger VIIRS active-fire pixels (roughly > ~50 ha depending on intensity); 375 m spatial resolution is coarse relative to fine-scale spread processes; misses periods of dense cloud cover.

Reference: Chen, Y., Hantson, S., Andela, N., Coffield, S. R., Graff, C. A., Morton, D. C., Ott, L. E., Foufoula-Georgiou, E., Smyth, P., Goulden, M. L., & Randerson, J. T. (2022). California wildfire spread derived using VIIRS satellite observations and an object-based tracking system. *Scientific Data*, 9, 249.

## Daily perimeter time series from burned-area products

**GlobFire (Artés et al. 2019, *Scientific Data*).** Global dataset of individual fire events with final perimeters *and* daily burned-area polygons, built from MODIS MCD64A1 burned-area product (500 m, monthly aggregation with per-pixel date-of-burning). Coverage 2001–present, subsequently extended. The authors provide daily burnt areas explicitly *"for those users who want to study the cases by their daily evolution."* Available through EFFIS / GWIS Joint Research Centre.

- Strengths: global coverage, long time series, individual fire events pre-identified with start/end dates, both final and daily polygons.
- Limitations: 500 m spatial resolution; the "daily" attribution is the MODIS date-of-detection of the burn-scar reflectance change, not a satellite-overpass polygon, so effective time-of-day is diffuse (often lagged by hours to days under smoke or cloud); depends on MCD64A1 algorithmic choices tuned for global use.

Reference: Artés, T., Oom, D., de Rigo, D., Durrant, T. H., Maianti, P., Libertà, G., & San-Miguel-Ayanz, J. (2019). A global wildfire dataset for the analysis of fire regimes and fire behaviour. *Scientific Data*, 6, 296.

**FIREDpy (Balch et al. 2020) and derivatives.** Similar concept — MCD64A1-based event chaining producing individual fires with perimeters and burn-date attributes — with more flexible parameterization than GlobFire. NRT extensions using optical+SAR fusion (Sentinel-2 + Sentinel-1) are under development at CU Boulder Earth Lab. Same fundamental resolution limits as GlobFire (500 m, MODIS-lag).

## Regional purpose-built spread databases

**PT-FireSprd (Benali, Sá, and colleagues).** Portuguese Large Wildfire Spread database, an open dataset of observed wildfire behaviour for large Portuguese wildfires built specifically to support fire behaviour research and management. Serves as a methodological model for what a regional wildfire-spread database with detailed observed behaviour looks like — worth citing as an example of what could be built for other regions.

## Finer-resolution per-event perimeter mapping

For each event identified via the coarse-resolution products above, high-resolution perimeters can be reconstructed from free optical imagery.

**Sentinel-2 (10 m, ~5-day revisit, free, Copernicus Open Access Hub).** Burn perimeters computed from dNBR (difference of pre- and post-fire Normalized Burn Ratio). Used operationally by EFFIS for European fires down to ~1 ha. Combined revisit with Landsat 8+9 gives ~2–3-day effective clear-sky cadence at mid-latitudes.

**Landsat 8/9 (30 m, 16-day revisit each, free).** Native at typical spread-model grid resolution. Complements Sentinel-2 by extending back in time (Landsat archives to 1984, Sentinel-2 to 2015–2017 depending on region).

**Sentinel-1 SAR (10 m, ~6-day revisit, free).** Sees through smoke and cloud via backscatter change detection. The critical gap-filler when smoke or persistent cloud (common during major fire episodes) prevents optical burn detection. Optical+SAR fusion pipelines (e.g. the NRT FIREDpy line of work) are the current frontier.

## Commercial high-resolution option

**Planet (PlanetScope 3–5 m daily, SkySat submeter tasking).** Daily coverage at commercial resolution. Would provide near-daily perimeters at finer resolution than the model grid for most spread-model applications. Free for tropical forest monitoring via Planet–NICFI but Patagonia and most mid-latitude fire regions require commercial licensing. Cited in the Cerrado operational fire-spread system (FISC-Cerrado, Pinto et al. 2023, *Scientific Reports*) as ancillary imagery.

## Suggested framing for the discussion

The natural argument for the discussion is a hierarchy of what's newly feasible:

1. At the coarsest level, GlobFire and FIREDpy already provide global daily perimeters that could be used *right now* to calibrate spread models against many more fires than have historically been available, at the cost of accepting 500 m resolution and diffuse daily timing.

2. FEDS raises the temporal resolution to sub-daily and provides explicit timestamps, at the cost of missing small fires — a good match for spread models targeting the large fires that dominate ecological and socioeconomic impact.

3. Both of these can be refined per-event with dNBR from Sentinel-2 and Landsat 8/9 to yield fine-resolution perimeters at specific overpass times, combined with Sentinel-1 SAR to fill smoke and cloud gaps — a workflow that requires per-fire processing but stays within free and open data.

4. Ideally, this free-data hierarchy is supplemented by commercial Planet imagery for near-daily fine-resolution perimeters, particularly for research on the intra-daily dynamics of individual events.

The overall point: fire-progression data are no longer the binding constraint they were when the thesis was designed. Calibration and validation of spread models at scales and cadences appropriate for both operational fire management and landscape-scale fire regime modeling are now feasible with existing open datasets, and would be enhanced by combination with free per-event optical/SAR mapping or commercial high-resolution imagery.

## References for the bibliography

- Artés, T., Oom, D., de Rigo, D., Durrant, T. H., Maianti, P., Libertà, G., & San-Miguel-Ayanz, J. (2019). A global wildfire dataset for the analysis of fire regimes and fire behaviour. *Scientific Data*, 6, 296.
- Balch, J. K., St. Denis, L. A., Mahood, A. L., Mietkiewicz, N. P., Williams, T. M., McGlinchy, J., & Cook, M. C. (2020). FIRED (Fire Events Delineation): An open, flexible algorithm and database of US fire events derived from the MODIS burned area product (2001–2019). *Remote Sensing*, 12(21), 3498.
- Chen, Y., Hantson, S., Andela, N., Coffield, S. R., Graff, C. A., Morton, D. C., Ott, L. E., Foufoula-Georgiou, E., Smyth, P., Goulden, M. L., & Randerson, J. T. (2022). California wildfire spread derived using VIIRS satellite observations and an object-based tracking system. *Scientific Data*, 9, 249.
- Pinto, M. M., Trigo, R. M., Trigo, I. F., & DaCamara, C. C. (2023). A near real-time web-system for predicting fire spread across the Cerrado biome. *Scientific Reports*, 13, 5142.

Author, year, and journal are verified from the search results in this conversation. For Balch et al. 2020 (FIREDpy) the specific citation was not retrieved from the web in this chat and should be double-checked before use in the paper; the reference given is the standard citation for the original FIREDpy paper.
