#!/usr/bin/env bash
# generate_primes.sh — emit a CLERS list for v in [VMIN, VMAX].
#
# Usage: generate_primes.sh VMIN VMAX OUT_DIR
#
# Drives primegen's `make all VMAX=...` to populate
#   submodules/primegen/data/prime/{v}.txt.gz
# then decompresses the requested range into
#   OUT_DIR/v<V>.txt          (one CLERS per line, plain text)
#   OUT_DIR/all.tsv           (TSV: v<TAB>clers, concatenated)
# plus provenance:
#   OUT_DIR/manifest.txt
#   OUT_DIR/commands.txt
#
# Env knobs (forwarded to primegen):
#   PRIMEGEN_JOBS   (default 80 on doob, 4 on laptop)
#   PRIMEGEN_NICE   (default 19)

set -eu

if [ $# -ne 3 ]; then
    echo "usage: $0 VMIN VMAX OUT_DIR" >&2
    exit 2
fi

VMIN="$1"; VMAX="$2"; OUT_DIR="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIMEGEN_DIR="$ROOT/submodules/primegen"

[ -d "$PRIMEGEN_DIR" ] || { echo "primegen submodule missing at $PRIMEGEN_DIR" >&2; exit 2; }

mkdir -p "$OUT_DIR"

JOBS="${PRIMEGEN_JOBS:-4}"
NICE="${PRIMEGEN_NICE:-19}"

{
    echo "host=$(hostname)"
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "vmin=$VMIN"
    echo "vmax=$VMAX"
    echo "primegen_commit=$(git -C "$PRIMEGEN_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "pipeline_commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "primegen_jobs=$JOBS"
    echo "primegen_nice=$NICE"
} > "$OUT_DIR/manifest.txt"

echo "make -C $PRIMEGEN_DIR all VMAX=$VMAX JOBS=$JOBS NICE=$NICE" > "$OUT_DIR/commands.txt"

# Build tools and generate primes through VMAX in the primegen submodule.
make -C "$PRIMEGEN_DIR" tools >&2
make -C "$PRIMEGEN_DIR" all VMAX="$VMAX" JOBS="$JOBS" NICE="$NICE" >&2

: > "$OUT_DIR/all.tsv"
for v in $(seq "$VMIN" "$VMAX"); do
    gz="$PRIMEGEN_DIR/data/prime/${v}.txt.gz"
    out="$OUT_DIR/v${v}.txt"
    if [ ! -f "$gz" ]; then
        # primegen treats v=5 as empty / absent; tolerate.
        : > "$out"
        continue
    fi
    gunzip -c "$gz" > "$out"
    awk -v v="$v" '{print v "\t" $0}' "$out" >> "$OUT_DIR/all.tsv"
done

n=$(wc -l < "$OUT_DIR/all.tsv")
echo "n_cases=$n" >> "$OUT_DIR/manifest.txt"
echo "[generate_primes] wrote $n CLERS rows to $OUT_DIR/all.tsv" >&2
