# Machine-local / external paths used across the pipeline, collected in one place so no
# script hardcodes an absolute path directly (old tech debt — see docs/migration.md #5).
# Scripts that need these do: source(file.path("R", "config.R"))
#
# `data`-relative paths below resolve once the store is linked (./setup.sh) — see README.md.

config <- list(
  # WindNinja CLI scratch directory (only needed to *regenerate* wind layers from scratch;
  # not required to read the already-prepared landscape .rds files). Machine-local — edit
  # this path per machine. `WindNinja_cli` itself must be on PATH (built from source and
  # installed at ~/.local/bin on this machine — see docs/migration.md TODO #3 for the build).
  windninja_dir = "/home/ivan/windninja_cli_fire_spread_files",

  # Vegetation-class equivalence table (WWF/Lara et al. 1999 map); sheet "Sheet2" has the
  # cnum1/class1/cnum2/class2 crosswalk every script reads.
  veg_equiv_xlsx = file.path("data", "vegetation_equivalences.xlsx"),

  # Same, for the ciefap source map; used only by data_prep/vegetation_ciefap_merge.R (sheet 1,
  # joined by Ley_N3 — a different sheet/key than veg_equiv_xlsx's Sheet2 join).
  veg_equiv_xlsx_ciefap = file.path("data", "vegetation_equivalences_ciefap.xlsx"),

  # Base layers for the study-area map (paper Fig. 1, spread/figure_study_area.R):
  # the elevation mosaic, the country/province polygons and the Argentine
  # bicontinental shapefiles. These came from the QGIS project the thesis-era
  # figure was drawn in ("mapa area de estudio 6.qgz") and still live in the
  # Insync folder it used, NOT in the repo's store — nothing else in the
  # pipeline reads them, and the elevation raster alone is 240 MB. Machine-local:
  # edit per machine, or copy the folder into the store and repoint here.
  study_area_map_dir = "/home/ivan/Insync/patagonian_fires paper/study area map",

  # The WWF / Lara et al. (1999) vegetation folder, for the same figure: the
  # regional vegetation raster it colours panel C with and the lakes polygons.
  # Also machine-local, and also outside the store.
  vegetation_lara_dir = "/home/ivan/Insync/Mapa vegetación WWF - Lara et al. 1999"
)
