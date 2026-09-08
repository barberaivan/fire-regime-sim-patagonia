#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# One-time setup: record this machine's store paths and link the heavy DATA STORES.
#
# This repo holds CODE only. The heavy data lives in TWO sibling folders synced
# via Insync/Google Drive:
#
#   fire-regime-sim-patagonia-store          PUBLIC  — landscape rasters, FWI
#                                            grids, fire perimeters, fitted
#                                            models, posterior samples,
#                                            simulation outputs. This is the
#                                            folder shared as a Drive link with
#                                            collaborators and reviewers.
#                                            Linked in as data/ and files/.
#
#   fire-regime-sim-patagonia-store-private  NON-PUBLIC — the PNNH ignition
#                                            record (Bari) and the lightning
#                                            ignition database (Kitzberger),
#                                            plus everything derived from them.
#                                            Provided for this research only and
#                                            NEVER shared. Linked in as
#                                            data_private/.
#
# Keeping them physically apart is the whole guarantee: a share link cannot
# reach a folder it was never given. Do not merge them back.
#
# Each store's absolute path is machine-specific, so both are saved to a
# gitignored file (.local-paths) and the committed docs stay path-free.
#
# Pure-R project: no Python/interpreter handling — an RStudio/Positron R session
# is all that's needed to run the code.
#
# USAGE
#   ./setup.sh /path/to/store [/path/to/store-private]   # first run
#   ./setup.sh                                            # later — reuses saved values
#
# The private store is OPTIONAL. Without it everything runs except
# ignition_escape/fit.R and the two blocks of fire_regime/ that read the
# observed ignition record (see README.md → "The two data stores").
#
# See README.md ("Getting started") for where to get the stores.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"                        # always operate from the repo root

# 1. Resolve the store paths: load anything saved before (gitignored), then let
#    command-line arguments override them.
[ -f .local-paths ] && source .local-paths
[ "$#" -ge 1 ] && STORE_ROOT="$1"
[ "$#" -ge 2 ] && STORE_PRIVATE_ROOT="$2"

if [ -z "${STORE_ROOT:-}" ]; then
  echo "Usage: ./setup.sh /path/to/fire-regime-sim-patagonia-store [/path/to/fire-regime-sim-patagonia-store-private]"
  echo "(the stores are the heavy-data folders from Insync or Google Drive — see README.md)"
  exit 1
fi

# 2. Make sure the stores actually exist (the #1 mistake is a wrong path).
if [ ! -d "$STORE_ROOT" ]; then
  echo "ERROR: store folder not found: $STORE_ROOT"
  echo "Download/sync it first (see README.md), then pass the correct path."
  exit 1
fi
if [ -n "${STORE_PRIVATE_ROOT:-}" ] && [ ! -d "$STORE_PRIVATE_ROOT" ]; then
  echo "ERROR: private store folder not found: $STORE_PRIVATE_ROOT"
  exit 1
fi

# 3. Persist for next time. Your shell can `source .local-paths` to get both.
{
  echo "STORE_ROOT=$STORE_ROOT"
  [ -n "${STORE_PRIVATE_ROOT:-}" ] && echo "STORE_PRIVATE_ROOT=$STORE_PRIVATE_ROOT"
} > .local-paths

# 4. Create one symlink per heavy folder. Both stores mirror the repo's paths
#    exactly (STORE/<rel> <-> <rel>), so this is a mechanical loop: adding a new
#    heavy folder later = adding one line to the right list.
link_one() {                                # link_one <repo path> <store root>
  local rel="$1" target="$2/$1"
  if [ -e "$rel" ] && [ ! -L "$rel" ]; then
    echo "ERROR: $rel exists and is not a symlink — refusing to overwrite"; exit 1
  fi
  [ -d "$target" ] || echo "  note: $rel is empty in the store — creating it"
  mkdir -p "$target"
  ln -sfn "$target" "$rel"
  echo "linked  $rel  ->  $target"
}

PUBLIC_LINKS=(
  data     # heavy inputs: landscape rasters, FWI grids, fire perimeters
  files    # heavy outputs: fitted models, posterior samples, simulation runs
)
PRIVATE_LINKS=(
  data_private   # non-public ignition record (Bari + Kitzberger) and derivatives
)

for rel in "${PUBLIC_LINKS[@]}"; do
  link_one "$rel" "$STORE_ROOT"
done

if [ -n "${STORE_PRIVATE_ROOT:-}" ]; then
  for rel in "${PRIVATE_LINKS[@]}"; do
    link_one "$rel" "$STORE_PRIVATE_ROOT"
  done
else
  echo
  echo "note: no private store given — data_private/ was not linked."
  echo "      Everything runs except ignition_escape/fit.R and the two blocks of"
  echo "      fire_regime/ that read the observed ignition record. To add it later:"
  echo "        ./setup.sh \"\$STORE_ROOT\" /path/to/fire-regime-sim-patagonia-store-private"
fi

echo
echo "Setup complete — heavy data is linked for this machine."
