#!/usr/bin/env bash
# run_prover.sh — rigorous "molasses" prover over an OBJ dir.
#
# Usage: run_prover.sh OBJ_DIR OUT_PROVER_DIR
#
# Enumerates OBJ_DIR/objs/v*/*.obj, splits the OBJ-path list into N chunks,
# launches one chunk worker per chunk in parallel.  Each chunk worker runs
# `euclid_prover` once per OBJ (the rigorous prover is per-OBJ only) and
# writes one TSV row per OBJ; ACCEPT cases get no log file; REJECT/ERROR
# cases save full prover output to OUT_PROVER_DIR/logs/.
#
# Output:
#   OUT_PROVER_DIR/parts/chunk_NNN.tsv     per-chunk verdict TSVs
#   OUT_PROVER_DIR/logs/                   per-REJECT prover output
#   OUT_PROVER_DIR/input_objs.txt          enumeration order
#   OUT_PROVER_DIR/manifest.txt
#   OUT_PROVER_DIR/commands.txt
#   OUT_PROVER_DIR/summary.txt             totals
#   OUT_PROVER_DIR/run.stderr              GNU time
#
# Env knobs:
#   EUCLID_PROVER_BIN  default submodules/euclid_prover/src/euclid_prover.
#   NEO_WORKERS        default 96 on doob, 4 elsewhere.
#   NEO_NICE           default 19.

set -eu

if [ $# -ne 2 ]; then
    echo "usage: $0 OBJ_DIR OUT_PROVER_DIR" >&2
    exit 2
fi

OBJ_DIR="$1"; OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PROVER="${EUCLID_PROVER_BIN:-$ROOT/submodules/euclid_prover/src/euclid_prover}"
[ -x "$PROVER" ] || { echo "[run_prover] prover not executable: $PROVER" >&2; exit 2; }

WORKERS="${NEO_WORKERS:-4}"
NICE="${NEO_NICE:-19}"

mkdir -p "$OUT/chunks" "$OUT/parts" "$OUT/logs"

# Enumerate OBJ paths.  Accept either OBJ_DIR=<root with objs/v*/*.obj>
# or OBJ_DIR=<dir containing OBJs at any depth>.
INPUT="$OUT/input_objs.txt"
if [ -d "$OBJ_DIR/objs" ]; then
    find "$OBJ_DIR/objs" -type f -name '*.obj'
else
    find "$OBJ_DIR" -type f -name '*.obj'
fi | sort > "$INPUT"
n=$(wc -l < "$INPUT")
[ "$n" -gt 0 ] || { echo "[run_prover] no OBJs under $OBJ_DIR" >&2; exit 2; }

{
    echo "host=$(hostname)"
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "obj_dir=$OBJ_DIR"
    echo "prover=$PROVER"
    echo "prover_md5=$(md5sum "$PROVER" 2>/dev/null | awk '{print $1}' || echo unknown)"
    echo "input_objs=$n"
    echo "workers=$WORKERS"
    echo "nice=$NICE"
    echo "pipeline_commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
} > "$OUT/manifest.txt"

( cd "$OUT/chunks" && split -n "l/$WORKERS" -d -a 3 "$INPUT" chunk_ )

WORKER="$ROOT/scripts/_molasses_chunk_worker.sh"
[ -x "$WORKER" ] || chmod +x "$WORKER"

echo "$WORKER {CHUNK} $OUT/parts $OUT/logs $PROVER" > "$OUT/commands.txt"

/usr/bin/time -v -o "$OUT/run.stderr" \
    parallel --nice "$NICE" -j "$WORKERS" --will-cite \
        "$WORKER {} $OUT/parts $OUT/logs $PROVER" \
        ::: "$OUT"/chunks/chunk_*

ACCEPT=$(awk -F'\t' '$4=="ACCEPT"' "$OUT"/parts/*.tsv 2>/dev/null | wc -l)
REJECT=$(awk -F'\t' '$4=="REJECT"' "$OUT"/parts/*.tsv 2>/dev/null | wc -l)
ERROR=$(awk -F'\t' '$4=="ERROR" || $4=="MISSING"' "$OUT"/parts/*.tsv 2>/dev/null | wc -l)
TOTAL=$(cat "$OUT"/parts/*.tsv 2>/dev/null | wc -l)

{
    echo "finished_iso=$(date -Is)"
    echo "input_count=$n"
    echo "total_rows=$TOTAL"
    echo "accept=$ACCEPT"
    echo "reject=$REJECT"
    echo "error_or_missing=$ERROR"
} > "$OUT/summary.txt"

echo "[run_prover] accept=$ACCEPT reject=$REJECT error=$ERROR total=$TOTAL" >&2
