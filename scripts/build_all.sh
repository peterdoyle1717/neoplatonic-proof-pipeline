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

if [ ! -d "$ROOT/submodules/euclid_lm" ]; then
    echo "[build_all] submodules/euclid_lm not present." >&2
    echo "[build_all] Run 'git submodule update --init --recursive' first." >&2
    exit 2
fi
build_one euclid_lm

echo "[build_all] done"
