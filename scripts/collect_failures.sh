#!/usr/bin/env bash
# collect_failures.sh — assemble a single failures.tsv from prover output.
#
# Usage:
#   collect_failures.sh PARTS_DIR OUT_FAILURES_TSV
#
# Reads PARTS_DIR/*.tsv (the per-chunk prover output produced by
# run_prover.sh), keeps rows with status != ACCEPT, and writes them to
# OUT_FAILURES_TSV with a header.  Schema:
#
#   v   clers   obj_path   molasses_status   failure_reason
#   stdout_path   stderr_path

set -eu

if [ $# -ne 2 ]; then
    echo "usage: $0 PARTS_DIR OUT_FAILURES_TSV" >&2
    exit 2
fi

PARTS_DIR="$1"; OUT="$2"
[ -d "$PARTS_DIR" ] || { echo "[collect_failures] no parts dir: $PARTS_DIR" >&2; exit 2; }

OUT_DIR=$(dirname "$OUT")
mkdir -p "$OUT_DIR"

{
    printf '# molasses failure list (rigorous prover output)\n'
    printf '# generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# source: %s\n' "$PARTS_DIR"
    printf 'v\tclers\tobj_path\tmolasses_status\tfailure_reason\tstdout_path\tstderr_path\n'
    awk -F'\t' -v OFS='\t' '$4 != "ACCEPT" { print $1, $2, $3, $4, $8, $6, $7 }' "$PARTS_DIR"/*.tsv
} > "$OUT"

n=$(awk -F'\t' '!/^#/ && NR>1' "$OUT" | wc -l)
echo "[collect_failures] wrote $n failure rows to $OUT" >&2
