#!/usr/bin/env bash
# reproduce_range.sh — end-to-end driver for one vertex range.
#
# Usage:
#   reproduce_range.sh VMIN VMAX OUT_DIR
#
# Composes:
#   1. generate_primes.sh VMIN VMAX OUT_DIR/primes
#   2. generate_objs.sh OUT_DIR/primes OUT_DIR/objs
#   3. run_prover.sh    OUT_DIR/objs OUT_DIR/prover
#   4. collect_failures.sh OUT_DIR/prover/parts OUT_DIR/failures.tsv
#
# Each stage's output is left in place for inspection.  Stage skip:
# if a stage's output already exists it is reused; force a re-run by
# deleting the stage dir.

set -eu

if [ $# -ne 3 ]; then
    echo "usage: $0 VMIN VMAX OUT_DIR" >&2
    exit 2
fi

VMIN="$1"; VMAX="$2"; OUT="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"

{
    echo "# reproduce_range manifest"
    echo "host=$(hostname)"
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "vmin=$VMIN"
    echo "vmax=$VMAX"
    echo "out_dir=$OUT"
    echo "pipeline_commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
} > "$OUT/manifest.txt"

if [ ! -f "$OUT/primes/manifest.txt" ]; then
    "$ROOT/scripts/generate_primes.sh" "$VMIN" "$VMAX" "$OUT/primes"
else
    echo "[reproduce_range] $OUT/primes exists; skipping primegen" >&2
fi

if [ ! -f "$OUT/objs/manifest.txt" ]; then
    "$ROOT/scripts/generate_objs.sh" "$OUT/primes" "$OUT/objs"
else
    echo "[reproduce_range] $OUT/objs exists; skipping OBJ generation" >&2
fi

if [ ! -f "$OUT/prover/summary.txt" ]; then
    "$ROOT/scripts/run_prover.sh" "$OUT/objs" "$OUT/prover"
else
    echo "[reproduce_range] $OUT/prover exists; skipping molasses" >&2
fi

"$ROOT/scripts/collect_failures.sh" "$OUT/prover/parts" "$OUT/failures.tsv"

echo "[reproduce_range] done: $OUT/failures.tsv"
