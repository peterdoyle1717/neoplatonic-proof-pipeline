#!/usr/bin/env bash
# build_all.sh -- build clers, primegen, and the euclid binaries.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

make -C "$ROOT/submodules/clers"
make -C "$ROOT/submodules/primegen" tools
make -C "$ROOT/euclid"
echo "[build_all] done"
