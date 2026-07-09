# Machine-local / external paths used across the pipeline, collected in one place so no
# script hardcodes an absolute path directly (old tech debt — see docs/migration.md #5).
# Scripts that need these do: source(file.path("R", "config.R"))
#
# `data`-relative paths below resolve once the store is linked (./setup.sh) — see README.md.

config <- list(
  # WindNinja CLI scratch directory (only needed to *regenerate* wind layers from scratch;
  # not required to read the already-prepared landscape .rds files). Machine-local — edit
  # this path per machine; not present on this machine as of the 2026-07 migration.
  windninja_dir = "/home/ivan/windninja_cli_fire_spread_files",

  # Vegetation-class equivalence table (WWF/Lara et al. 1999 map); sheet "Sheet2" has the
  # cnum1/class1/cnum2/class2 crosswalk every script reads.
  veg_equiv_xlsx = file.path("data", "vegetation_equivalences.xlsx"),

  # Same, for the ciefap source map; used only by data_prep/vegetation_ciefap_merge.R (sheet 1,
  # joined by Ley_N3 — a different sheet/key than veg_equiv_xlsx's Sheet2 join).
  veg_equiv_xlsx_ciefap = file.path("data", "vegetation_equivalences_ciefap.xlsx")
)
