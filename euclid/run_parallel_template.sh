#!/bin/sh
# run_parallel_template.sh -- shard, solve, prove, manifest.
#
# Usage:
#   ./run_parallel_template.sh INPUT_NETCODES
#
# Env knobs (all optional, all numeric or 0/1):
#   JOBS           parallel worker count (default 4).
#   SHARDS         number of shards to split input into (default 4*JOBS).
#   NICE           nice level for parallel workers; 0 disables (default 0).
#   BLAS_THREADS   per-process BLAS thread cap (default 1; set 0 to leave alone).
#   CHECK          1 = run combinatorial topology check before/after solving (default 1).
#   SOLVE          1 = run solver phase (default 1).
#   PROVE          1 = run prover phase (default 1).
#   BUILD          1 = run "make all" before starting (default 1).
#   OUTROOT        output directory root (default ./run).
#
# No host-specific assumptions. Set NICE and BLAS_THREADS to whatever your
# environment wants; defaults are conservative.

set -u

INPUT=${1:-}
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
    echo "usage: $0 INPUT_NETCODES_FILE" >&2
    exit 2
fi

JOBS=${JOBS:-4}
SHARDS=${SHARDS:-}
NICE=${NICE:-0}
BLAS_THREADS=${BLAS_THREADS:-1}
CHECK=${CHECK:-1}
SOLVE=${SOLVE:-1}
PROVE=${PROVE:-1}
BUILD=${BUILD:-1}
OUTROOT=${OUTROOT:-./run}

[ -z "$SHARDS" ] && SHARDS=$(( JOBS * 4 ))
[ "$SHARDS" -ge 1 ] 2>/dev/null || { echo "SHARDS must be >= 1" >&2; exit 2; }

# Cap per-process BLAS threads so JOBS-way parallel doesn't oversubscribe.
if [ "$BLAS_THREADS" != 0 ]; then
    export OPENBLAS_NUM_THREADS=$BLAS_THREADS
    export OMP_NUM_THREADS=$BLAS_THREADS
    export MKL_NUM_THREADS=$BLAS_THREADS
    export VECLIB_MAXIMUM_THREADS=$BLAS_THREADS
fi

NICE_PREFIX=""
[ "$NICE" != 0 ] && NICE_PREFIX="nice -n $NICE"

if [ "$BUILD" = 1 ]; then
    make all || exit 1
fi

[ -x ./euclid_clean ]  || { echo "missing ./euclid_clean";  exit 1; }
[ -x ./euclid_prover ] || { echo "missing ./euclid_prover"; exit 1; }
[ "$CHECK" = 0 ] || [ -x ./euclid_check ] || { echo "missing ./euclid_check"; exit 1; }

rm -rf "$OUTROOT"
mkdir -p \
    "$OUTROOT/shards" \
    "$OUTROOT/solverout" \
    "$OUTROOT/solverlogs" \
    "$OUTROOT/solvermanifest" \
    "$OUTROOT/provershards" \
    "$OUTROOT/proverout" \
    "$OUTROOT/proverlogs" \
    "$OUTROOT/provermanifest" \
    "$OUTROOT/checkmanifest"

INPUT_NETCODES=$INPUT
if [ "$CHECK" = 1 ]; then
    ./euclid_check --netcodes < "$INPUT" > "$OUTROOT/checkmanifest/netcodes.tsv" || true
    awk -F '\t' '$2 == "ok" { print $3 }' "$OUTROOT/checkmanifest/netcodes.tsv" \
        > "$OUTROOT/checked.netcodes"
    INPUT_NETCODES=$OUTROOT/checked.netcodes
fi

# Round-robin split. Awk keeps shard files open (no close-per-line, which
# would truncate on each reopen). For SHARDS up to ~256 this is fine; for
# larger SHARDS you may hit awk's open-file ceiling -- use GNU `split -n r/N`
# if so.
awk -v n="$SHARDS" -v root="$OUTROOT/shards" '
    NF { print > sprintf("%s/shard_%06d", root, (NR - 1) % n) }
' "$INPUT_NETCODES"

run_stage() {
    bin=$1 shard_dir=$2 out_dir=$3 manifest_dir=$4 log_dir=$5
    if command -v parallel >/dev/null 2>&1; then
        find "$shard_dir" -type f | sort | parallel -j "$JOBS" --will-cite '
            shard={}
            base=$(basename "$shard")
            mkdir -p "'$out_dir'/$base"
            '"$NICE_PREFIX"' '"$bin"' --batch --outdir "'$out_dir'/$base" \
                < "$shard" \
                > "'$manifest_dir'/$base.tsv" \
                2> "'$log_dir'/$base.err"
        '
    else
        for shard in "$shard_dir"/*; do
            [ -f "$shard" ] || continue
            base=$(basename "$shard")
            mkdir -p "$out_dir/$base"
            $NICE_PREFIX "$bin" --batch --outdir "$out_dir/$base" \
                < "$shard" \
                > "$manifest_dir/$base.tsv" \
                2> "$log_dir/$base.err" || true
        done
    fi
}

if [ "$SOLVE" = 1 ]; then
    run_stage ./euclid_clean \
        "$OUTROOT/shards" "$OUTROOT/solverout" \
        "$OUTROOT/solvermanifest" "$OUTROOT/solverlogs"
    cat "$OUTROOT/solvermanifest"/shard_*.tsv > "$OUTROOT/solvermanifest/all.tsv" 2>/dev/null || true
    awk -F '\t' '$2 == "ok" { print $4 }' "$OUTROOT/solvermanifest/all.tsv" > "$OUTROOT/objfiles.txt"
fi

INPUT_OBJS=$OUTROOT/objfiles.txt
if [ "$PROVE" = 1 ] && [ "$CHECK" = 1 ] && [ -f "$OUTROOT/objfiles.txt" ]; then
    ./euclid_check --objs < "$OUTROOT/objfiles.txt" > "$OUTROOT/checkmanifest/objs.tsv" || true
    awk -F '\t' '$2 == "ok" { print $3 }' "$OUTROOT/checkmanifest/objs.tsv" \
        > "$OUTROOT/checked.objfiles"
    INPUT_OBJS=$OUTROOT/checked.objfiles
fi

if [ "$PROVE" = 1 ] && [ -f "$INPUT_OBJS" ]; then
    awk -v n="$SHARDS" -v root="$OUTROOT/provershards" '
        NF { print > sprintf("%s/shard_%06d", root, (NR - 1) % n) }
    ' "$INPUT_OBJS"
    run_stage ./euclid_prover \
        "$OUTROOT/provershards" "$OUTROOT/proverout" \
        "$OUTROOT/provermanifest" "$OUTROOT/proverlogs"
    cat "$OUTROOT/provermanifest"/shard_*.tsv > "$OUTROOT/provermanifest/all.tsv" 2>/dev/null || true
fi

echo "JOBS=$JOBS  SHARDS=$SHARDS  NICE=$NICE  BLAS_THREADS=$BLAS_THREADS  CHECK=$CHECK  SOLVE=$SOLVE  PROVE=$PROVE"
echo "OUTROOT=$OUTROOT"
[ -f "$OUTROOT/checkmanifest/netcodes.tsv" ] && echo "  netcode check: $OUTROOT/checkmanifest/netcodes.tsv"
[ -f "$OUTROOT/solvermanifest/all.tsv" ]     && echo "  solver:        $OUTROOT/solvermanifest/all.tsv"
[ -f "$OUTROOT/objfiles.txt" ]               && echo "  OBJ list:      $OUTROOT/objfiles.txt"
[ -f "$OUTROOT/checkmanifest/objs.tsv" ]     && echo "  OBJ check:     $OUTROOT/checkmanifest/objs.tsv"
[ -f "$OUTROOT/provermanifest/all.tsv" ]     && echo "  prover:        $OUTROOT/provermanifest/all.tsv"
