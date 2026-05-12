#!/usr/bin/env bash
# _molasses_chunk_worker.sh — process one chunk of OBJ paths through the
# rigorous euclid_prover.  Emit one TSV row per OBJ.
#
# Usage:
#   _molasses_chunk_worker.sh CHUNK_FILE PARTS_DIR LOGS_DIR PROVER
#
# Per-OBJ: run the prover, parse "final:" verdict, parse a short summary
# of existence/embedding/undented lines.  ACCEPT rows write no log file.
# REJECT/ERROR rows save full combined stdout+stderr to LOGS_DIR/<chunk>_<stem>.log.
#
# Columns (TSV):
#   v  clers  obj_path  molasses_status  elapsed_seconds
#   stdout_path  stderr_path  certificate_or_failure_summary

set -u

CHUNK_FILE=${1:?chunk file required}
PARTS_DIR=${2:?parts dir required}
LOGS_DIR=${3:?logs dir required}
PROVER=${4:?prover path required}

mkdir -p "$PARTS_DIR" "$LOGS_DIR"

if [ ! -x "$PROVER" ]; then
    echo "_molasses_chunk_worker: prover not executable: $PROVER" >&2
    exit 2
fi

chunk_id=$(basename "$CHUNK_FILE")
TSV="$PARTS_DIR/$chunk_id.tsv"
: > "$TSV"

while IFS= read -r obj; do
    [ -z "$obj" ] && continue
    if [ ! -f "$obj" ]; then
        printf '?\t-\t%s\tMISSING\t0\t-\t-\tmissing obj\n' "$obj" >> "$TSV"
        continue
    fi

    stem=$(basename "$obj" .obj)
    v=$(echo "$obj" | sed -E 's|.*/v([0-9]+)/[^/]+\.obj$|\1|')
    clers="$stem"

    t0=$(date +%s.%N)
    combined=$("$PROVER" "$obj" 2>&1)
    t1=$(date +%s.%N)
    elapsed=$(awk -v t0="$t0" -v t1="$t1" 'BEGIN{printf "%.4f", t1-t0}')

    verdict=$(echo "$combined" | awk '/^final:/ {print $2; exit}')
    [ -z "$verdict" ] && verdict=ERROR

    summary=$(echo "$combined" | awk '
        /^final:/             {print}
        /^existence_test:/    {print}
        /^embedding_test_used:/ {print}
        /^undented_test:/     {print}
    ' | tr '\n' ';' | sed 's/;$//')

    if [ "$verdict" = "ACCEPT" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t-\t-\t%s\n' \
            "$v" "$clers" "$obj" "$verdict" "$elapsed" "$summary" >> "$TSV"
    else
        log="$LOGS_DIR/${chunk_id}_${stem}.log"
        printf '%s\n' "$combined" > "$log"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t%s\n' \
            "$v" "$clers" "$obj" "$verdict" "$elapsed" "$log" "$summary" >> "$TSV"
    fi
done < "$CHUNK_FILE"
