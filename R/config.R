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

  # Vegetation-class equivalence table. TODO(migration #2): the original WWF/Lara file is
  # missing from disk; a different "ciefap" variant exists but has not been confirmed as
  # equivalent. Once resolved, the file should live at data/vegetation_equivalences.xlsx
  # (store-relative, so this path needs no further machine-specific editing).
  veg_equiv_xlsx = file.path("data", "vegetation_equivalences.xlsx")
)
