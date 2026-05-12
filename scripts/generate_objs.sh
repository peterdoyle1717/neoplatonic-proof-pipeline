#!/usr/bin/env bash
# generate_objs.sh — official LM-sparse Euclidean OBJ generation.
#
# Usage: generate_objs.sh PRIMES_DIR OUT_OBJ_DIR
#
# Reads CLERS strings from PRIMES_DIR/v<V>.txt files, splits them into
# NEO_WORKERS chunks, runs the euclid_lm binary in OBJ-emitting mode
# (`--objs-out-root`) on each chunk in parallel.  Output OBJ tree:
#   OUT_OBJ_DIR/objs/v<V>/<CLERS>.obj
# Provenance:
#   OUT_OBJ_DIR/manifest.txt
#   OUT_OBJ_DIR/commands.txt
#   OUT_OBJ_DIR/run.stderr     (GNU time)
#
# Env knobs:
#   EUCLID_LM_BIN          path to the euclid_oneshot binary (REQUIRED until
#                          euclid_lm extraction lands; see ARCHITECTURE.md).
#   NEO_WORKERS            parallel worker count, default 96 on doob, 4 elsewhere.
#   NEO_NICE               nice -n level, default 19.
#   OPENBLAS_NUM_THREADS   default 1 (propagated to workers).

set -eu

if [ $# -ne 2 ]; then
    echo "usage: $0 PRIMES_DIR OUT_OBJ_DIR" >&2
    exit 2
fi

PRIMES_DIR="$1"; OUT_OBJ_DIR="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

EUCLID_LM_BIN="${EUCLID_LM_BIN:-}"
if [ -z "$EUCLID_LM_BIN" ]; then
    cand="$ROOT/submodules/euclid_lm/bin/euclid_oneshot"
    if [ -x "$cand" ]; then
        EUCLID_LM_BIN="$cand"
    else
        echo "[generate_objs] EUCLID_LM_BIN not set and submodules/euclid_lm not built." >&2
        echo "[generate_objs] See docs/ARCHITECTURE.md (COMPONENT NOT YET CLEAN: euclid_lm)." >&2
        exit 2
    fi
fi
[ -x "$EUCLID_LM_BIN" ] || { echo "[generate_objs] not executable: $EUCLID_LM_BIN" >&2; exit 2; }

mkdir -p "$OUT_OBJ_DIR/objs" "$OUT_OBJ_DIR/chunks"

# Concatenate CLERS strings as `clers\n` from PRIMES_DIR/v*.txt.
# (euclid_oneshot --input-list expects bare CLERS lines.)
ALL_CLERS="$OUT_OBJ_DIR/all_clers.txt"
: > "$ALL_CLERS"
for f in "$PRIMES_DIR"/v*.txt; do
    [ -f "$f" ] || continue
    cat "$f" >> "$ALL_CLERS"
done
n=$(wc -l < "$ALL_CLERS")
if [ "$n" -eq 0 ]; then
    echo "[generate_objs] no CLERS in $PRIMES_DIR" >&2
    exit 2
fi

WORKERS="${NEO_WORKERS:-4}"
NICE="${NEO_NICE:-19}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"

# Split into N chunks for one process per chunk (NOT per CLERS).
# Use GNU split's -n l/N when available; otherwise compute chunk size
# from line count for portability (BSD split on macOS lacks -n).
W=$WORKERS
if [ "$W" -gt "$n" ]; then W=$n; fi
ABS_CLERS="$(cd "$(dirname "$ALL_CLERS")" && pwd)/$(basename "$ALL_CLERS")"
if split --version >/dev/null 2>&1; then
    ( cd "$OUT_OBJ_DIR/chunks" && split -n "l/$W" -d -a 3 "$ABS_CLERS" chunk_ )
else
    per=$(( (n + W - 1) / W ))
    ( cd "$OUT_OBJ_DIR/chunks" && split -l "$per" -d -a 3 "$ABS_CLERS" chunk_ )
fi

{
    echo "host=$(hostname)"
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "primes_dir=$PRIMES_DIR"
    echo "out_obj_dir=$OUT_OBJ_DIR"
    echo "euclid_lm_bin=$EUCLID_LM_BIN"
    echo "euclid_lm_md5=$(md5sum "$EUCLID_LM_BIN" 2>/dev/null | awk '{print $1}' || echo unknown)"
    echo "n_cases=$n"
    echo "workers=$WORKERS"
    echo "nice=$NICE"
    echo "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS"
    echo "pipeline_commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
} > "$OUT_OBJ_DIR/manifest.txt"

CMD_TEMPLATE='%s --input-list {} --out-dir %s --objs-out-root %s/objs'
printf "$CMD_TEMPLATE\n" "$EUCLID_LM_BIN" "$OUT_OBJ_DIR" "$OUT_OBJ_DIR" > "$OUT_OBJ_DIR/commands.txt"

# Run.  Prefer GNU parallel + /usr/bin/time -v (doob); fall back to serial
# loop when those aren't present (laptop smoke).
if command -v parallel >/dev/null 2>&1; then
    if /usr/bin/time -v true >/dev/null 2>&1; then
        /usr/bin/time -v -o "$OUT_OBJ_DIR/run.stderr" \
            parallel --nice "$NICE" -j "$WORKERS" --env OPENBLAS_NUM_THREADS --will-cite \
                "$EUCLID_LM_BIN" --input-list {} \
                    --out-dir "$OUT_OBJ_DIR" \
                    --objs-out-root "$OUT_OBJ_DIR/objs" \
                ::: "$OUT_OBJ_DIR"/chunks/chunk_*
    else
        parallel --nice "$NICE" -j "$WORKERS" --env OPENBLAS_NUM_THREADS --will-cite \
            "$EUCLID_LM_BIN" --input-list {} \
                --out-dir "$OUT_OBJ_DIR" \
                --objs-out-root "$OUT_OBJ_DIR/objs" \
            ::: "$OUT_OBJ_DIR"/chunks/chunk_* \
            2> "$OUT_OBJ_DIR/run.stderr"
    fi
else
    echo "[generate_objs] GNU parallel not found; running chunks serially (laptop smoke fallback)" >&2
    : > "$OUT_OBJ_DIR/run.stderr"
    for c in "$OUT_OBJ_DIR"/chunks/chunk_*; do
        "$EUCLID_LM_BIN" --input-list "$c" \
            --out-dir "$OUT_OBJ_DIR" \
            --objs-out-root "$OUT_OBJ_DIR/objs" 2>> "$OUT_OBJ_DIR/run.stderr"
    done
fi

n_obj=$(find "$OUT_OBJ_DIR/objs" -type f -name '*.obj' | wc -l)
echo "n_obj=$n_obj" >> "$OUT_OBJ_DIR/manifest.txt"
echo "[generate_objs] wrote $n_obj OBJs to $OUT_OBJ_DIR/objs" >&2

if [ "$n_obj" -ne "$n" ]; then
    echo "[generate_objs] WARN: expected $n OBJs, got $n_obj" >&2
fi
