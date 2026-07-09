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

  # Vegetation-class equivalence table (WWF/Lara et al. 1999 map). RESOLVED (migration #2,
  # 2026-07-09): found via Google Drive (not locally synced) and placed in the store. Schema
  # verified against every script that reads it (sheet "Sheet2": cnum1, class1, cnum2, class2).
  # A separate "ciefap" equivalence table (for a different source vegetation map) is also kept
  # in the store as data/vegetation_equivalences_ciefap.xlsx for provenance — it is NOT read by
  # any script in this repo (confirmed via repo-wide grep); it was used elsewhere (likely the
  # separate GEE JS repo, see CLAUDE.md) to prepare the raw vegetation layers upstream of here.
  veg_equiv_xlsx = file.path("data", "vegetation_equivalences.xlsx")
)
