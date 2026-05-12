#!/usr/bin/env bash
# build_all.sh — build pinned submodule binaries.
#
# Builds each component listed in submodules/.  euclid_lm is currently a
# TODO (see docs/ARCHITECTURE.md); this script reports the gap and exits
# non-zero unless EUCLID_LM_BIN is preset to an already-built binary.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

build_one() {
    local sub="$1"
    if [ ! -d "$ROOT/submodules/$sub" ]; then
        echo "[build_all] submodule missing: $sub" >&2
        return 1
    fi
    echo "[build_all] $sub"
    $MAKE -C "$ROOT/submodules/$sub"
}

MAKE="${MAKE:-make}"

build_one clers
build_one primegen
build_one euclid_prover

if [ -d "$ROOT/submodules/euclid_lm" ]; then
    build_one euclid_lm
else
    if [ -z "${EUCLID_LM_BIN:-}" ]; then
        echo "[build_all] submodules/euclid_lm not present and EUCLID_LM_BIN not set." >&2
        echo "[build_all] See docs/ARCHITECTURE.md (COMPONENT NOT YET CLEAN: euclid_lm)." >&2
        echo "[build_all] Workaround for now: point EUCLID_LM_BIN at the in-tree" >&2
        echo "[build_all] orchestrator copy:" >&2
        echo "    EUCLID_LM_BIN=~/Dropbox/neo/orchestrator/tools/euclid_oneshot/bin/euclid_oneshot" >&2
        exit 2
    fi
    echo "[build_all] using pre-built EUCLID_LM_BIN=$EUCLID_LM_BIN"
    [ -x "$EUCLID_LM_BIN" ] || { echo "[build_all] not executable: $EUCLID_LM_BIN" >&2; exit 2; }
fi

echo "[build_all] done"
