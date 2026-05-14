#!/usr/bin/env bash
# reproduce_range.sh VMIN VMAX OUT_DIR
#
# End-to-end:
#   1. primegen        -> CLERS lists per v
#   2. clers decode    -> netcodes
#   3. euclid pipeline -> topology check, solver, OBJ topology check, prover
#   4. failures        -> v <TAB> clers <TAB> verdict <TAB> message
#   5. compare to data/expected/v4_50/ if the range is covered.
#
# Env knobs (forwarded as-is to euclid/run_parallel_template.sh):
#   JOBS, SHARDS, NICE, BLAS_THREADS

set -eu

if [ $# -ne 3 ]; then
    echo "usage: $0 VMIN VMAX OUT_DIR" >&2
    exit 2
fi

VMIN=$1
VMAX=$2
OUT=$3
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLERS="$ROOT/submodules/clers/bin/clers"

mkdir -p "$OUT"

{
    echo "host=$(hostname)"
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "vmin=$VMIN"
    echo "vmax=$VMAX"
    echo "pipeline_commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
} > "$OUT/manifest.txt"

# Step 1: primes.
[ -d "$OUT/primes" ] || "$ROOT/scripts/generate_primes.sh" "$VMIN" "$VMAX" "$OUT/primes"

# Step 2: decode CLERS to netcodes (single bulk call).
if [ ! -f "$OUT/netcodes.txt" ]; then
    cat "$OUT/primes"/v*.txt 2>/dev/null \
        | "$CLERS" decode \
        > "$OUT/netcodes.txt"
fi

# Step 3: euclid pipeline. The runner expects the three binaries in its
# cwd, so cd into euclid/ first. OUTROOT is absolute so output still lands
# under $OUT.
make -C "$ROOT/euclid" all >&2
ABS_NETCODES="$(cd "$(dirname "$OUT/netcodes.txt")" && pwd)/$(basename "$OUT/netcodes.txt")"
ABS_OUTROOT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")/euclid"
(
    cd "$ROOT/euclid"
    JOBS=${JOBS:-4} SHARDS=${SHARDS:-} NICE=${NICE:-0} \
        BLAS_THREADS=${BLAS_THREADS:-1} BUILD=0 \
        OUTROOT="$ABS_OUTROOT" \
        ./run_parallel_template.sh "$ABS_NETCODES"
)

# Step 4: collect failures.
"$ROOT/scripts/collect_failures.sh" "$OUT/euclid" "$CLERS" > "$OUT/failures.tsv"

# Step 5: compare to expected if the range overlaps.
EXPECTED="$ROOT/data/expected/v4_50/molasses_official_lm_failures.tsv"
COMPARE="$OUT/compare.txt"
if [ "$VMIN" = 4 ] && [ "$VMAX" -le 50 ] && [ -f "$EXPECTED" ]; then
    EXP_KEYS="$OUT/_expected_keys.tsv"
    GOT_KEYS="$OUT/_got_keys.tsv"
    awk -F'\t' -v vmax="$VMAX" \
        '$1 ~ /^[0-9]+$/ && $1+0 <= vmax {print $1"\t"$2}' \
        "$EXPECTED" | sort > "$EXP_KEYS"
    awk -F'\t' '{print $1"\t"$2}' "$OUT/failures.tsv" | sort > "$GOT_KEYS"
    only_exp=$(comm -23 "$EXP_KEYS" "$GOT_KEYS" | wc -l | tr -d ' ')
    only_got=$(comm -13 "$EXP_KEYS" "$GOT_KEYS" | wc -l | tr -d ' ')
    common=$(comm  -12 "$EXP_KEYS" "$GOT_KEYS" | wc -l | tr -d ' ')
    n_exp=$(wc -l < "$EXP_KEYS" | tr -d ' ')
    n_got=$(wc -l < "$GOT_KEYS" | tr -d ' ')
    {
        echo "compare_range=v4..v$VMAX"
        echo "expected_failures=$n_exp"
        echo "produced_failures=$n_got"
        echo "common=$common"
        echo "only_in_expected=$only_exp"
        echo "only_in_produced=$only_got"
        echo "expected_path=$EXPECTED"
        echo "produced_path=$OUT/failures.tsv"
        if [ "$only_exp" = 0 ] && [ "$only_got" = 0 ]; then
            echo "compare=PASS"
        else
            echo "compare=FAIL"
        fi
    } > "$COMPARE"
    cat "$COMPARE"
fi

echo "[reproduce_range] done: $OUT/failures.tsv"
