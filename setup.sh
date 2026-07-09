#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# One-time setup: record this machine's store path and link the heavy DATA STORE.
#
# This repo holds CODE only. The heavy data (landscape rasters, FWI grids, fire
# shapefiles, fitted models, posterior samples, simulation outputs) lives in a
# sibling folder "fire-regime-sim-patagonia-store" synced via Insync/Google Drive.
# This script symlinks that store's subfolders back into the repo at their
# mirrored paths (data/, files/). The store's absolute path is machine-specific,
# so it is saved to a gitignored file (.local-paths) and the committed docs stay
# path-free.
#
# Pure-R project: no Python/interpreter handling — an RStudio/Positron R session
# is all that's needed to run the code.
#
# USAGE
#   ./setup.sh /path/to/fire-regime-sim-patagonia-store   # first run
#   ./setup.sh                                             # later — reuses saved value
#
# See README.md ("Getting started") for where to get the store.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"                        # always operate from the repo root

# 1. Resolve the store path: load anything saved before (gitignored), then let a
#    command-line argument override it.
[ -f .local-paths ] && source .local-paths
[ "$#" -ge 1 ] && STORE_ROOT="$1"

if [ -z "${STORE_ROOT:-}" ]; then
  echo "Usage: ./setup.sh /path/to/fire-regime-sim-patagonia-store"
  echo "(the store is the heavy-data folder from Insync or Google Drive — see README.md)"
  exit 1
fi

# 2. Make sure the store actually exists (the #1 mistake is a wrong path).
if [ ! -d "$STORE_ROOT" ]; then
  echo "ERROR: store folder not found: $STORE_ROOT"
  echo "Download/sync it first (see README.md), then pass the correct path."
  exit 1
fi

# 3. Persist for next time. Your shell can `source .local-paths` to get $STORE_ROOT.
echo "STORE_ROOT=$STORE_ROOT" > .local-paths

# 4. Create one symlink per heavy folder. The store mirrors the repo's paths
#    exactly (STORE_ROOT/<rel> <-> <rel>), so this is a mechanical loop:
#    adding a new heavy folder later = adding one line here.
LINKS=(
  data     # heavy inputs: landscape rasters, FWI grids, fire shapefiles, ignition data
  files    # heavy outputs: fitted models, posterior samples, simulation runs
)
for rel in "${LINKS[@]}"; do
  target="$STORE_ROOT/$rel"
  if [ -e "$rel" ] && [ ! -L "$rel" ]; then
    echo "ERROR: $rel exists and is not a symlink — refusing to overwrite"; exit 1
  fi
  [ -d "$target" ] || echo "  note: $rel is empty in the store — creating it"
  mkdir -p "$target"
  ln -sfn "$target" "$rel"
  echo "linked  $rel  ->  $target"
done

echo
echo "Setup complete — heavy data is linked for this machine."
