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

# Acceptance comparison: if the range is exactly 4..50, compare the produced
# failure set against the committed reference at data/expected/v4_50/.
# The comparison is on (v, clers) pairs only; obj_path and stdout_path differ
# between runs by design.
EXPECTED="$ROOT/data/expected/v4_50/molasses_official_lm_failures.tsv"
COMPARE_LOG="$OUT/compare.txt"
if [ "$VMIN" = "4" ] && [ "$VMAX" = "50" ] && [ -f "$EXPECTED" ]; then
    EXP_CLERS="$OUT/_expected_clers.txt"
    GOT_CLERS="$OUT/_produced_clers.txt"
    awk -F'\t' '!/^#/ && NR>1 {print $1"\t"$2}' "$EXPECTED"      | sort > "$EXP_CLERS"
    awk -F'\t' '!/^#/ && NR>1 {print $1"\t"$2}' "$OUT/failures.tsv" | sort > "$GOT_CLERS"
    n_exp=$(wc -l < "$EXP_CLERS"  | tr -d ' ')
    n_got=$(wc -l < "$GOT_CLERS"  | tr -d ' ')
    n_only_exp=$(comm -23 "$EXP_CLERS" "$GOT_CLERS" | wc -l | tr -d ' ')
    n_only_got=$(comm -13 "$EXP_CLERS" "$GOT_CLERS" | wc -l | tr -d ' ')
    n_common=$(comm  -12 "$EXP_CLERS" "$GOT_CLERS" | wc -l | tr -d ' ')
    {
        echo "expected_failures=$n_exp"
        echo "produced_failures=$n_got"
        echo "common=$n_common"
        echo "only_in_expected=$n_only_exp"
        echo "only_in_produced=$n_only_got"
        echo "expected_path=$EXPECTED"
        echo "produced_path=$OUT/failures.tsv"
    } > "$COMPARE_LOG"
    if [ "$n_only_exp" -eq 0 ] && [ "$n_only_got" -eq 0 ]; then
        echo "compare=PASS" >> "$COMPARE_LOG"
        echo "[reproduce_range] COMPARE PASS  $n_got produced == $n_exp expected" >&2
    else
        echo "compare=FAIL" >> "$COMPARE_LOG"
        echo "[reproduce_range] COMPARE FAIL" >&2
        echo "  produced=$n_got expected=$n_exp common=$n_common" >&2
        echo "  only_in_expected=$n_only_exp  only_in_produced=$n_only_got" >&2
        echo "  expected: $EXPECTED" >&2
        echo "  produced: $OUT/failures.tsv" >&2
        echo "  full diff: $COMPARE_LOG and $EXP_CLERS vs $GOT_CLERS" >&2
    fi
    # surface comparison in the run's summary if one exists
    if [ -f "$OUT/prover/summary.txt" ]; then
        cat "$COMPARE_LOG" >> "$OUT/prover/summary.txt"
    fi
else
    echo "[reproduce_range] range $VMIN..$VMAX != 4..50 or no expected file; skipping comparison" >&2
fi

echo "[reproduce_range] done: $OUT/failures.tsv"
