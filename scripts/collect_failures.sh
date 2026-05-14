#!/bin/sh
# collect_failures.sh EUCLID_OUTDIR CLERS_BIN > failures.tsv
#
# Joins solver and prover manifests by OBJ path, filters to non-accept
# verdicts, and emits one tab-separated row per failure in the form
#
#   v <TAB> clers <TAB> verdict <TAB> message
#
# `clers` is the canonical CLERS name for the failed netcode, obtained
# by piping all failed netcodes through `<clers_bin> name`. `v` is the
# vertex count, read off the netcode by taking the max vertex id.

set -eu

EUCLID=${1:?"usage: $0 EUCLID_OUTDIR CLERS_BIN"}
CLERS=${2:?"usage: $0 EUCLID_OUTDIR CLERS_BIN"}

SOLVER=$EUCLID/solvermanifest/all.tsv
PROVER=$EUCLID/provermanifest/all.tsv
[ -f "$SOLVER" ] || { echo "missing $SOLVER" >&2; exit 1; }
[ -f "$PROVER" ] || { echo "missing $PROVER" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Solver row:  idx ok netcode objpath msg     -> key on column 4
# Prover row:  idx verdict objpath reportpath msg -> key on column 3
sort -t"$(printf '\t')" -k4 "$SOLVER" > "$TMP/solver.sorted"
sort -t"$(printf '\t')" -k3 "$PROVER" > "$TMP/prover.sorted"

join -t"$(printf '\t')" -1 4 -2 3 \
    -o 0,1.1,1.2,1.3,1.5,2.1,2.2,2.4,2.5 \
    "$TMP/solver.sorted" "$TMP/prover.sorted" > "$TMP/joined.tsv"

# Filter non-accept; netcode=$4, verdict=$7, prover-msg=$9.
awk -F"$(printf '\t')" '$7 != "accept" { print $4 "\t" $7 "\t" $9 }' \
    "$TMP/joined.tsv" > "$TMP/failed.tsv"

# Canonical CLERS name from each failed netcode (single bulk subprocess).
cut -f1 "$TMP/failed.tsv" | "$CLERS" name > "$TMP/failed.clers"

# v = max vertex id in each netcode.
awk -F"$(printf '\t')" '{
    n = split($1, parts, /[,;]/)
    vmax = 0
    for (i = 1; i <= n; i++) if (parts[i] + 0 > vmax) vmax = parts[i] + 0
    print vmax
}' "$TMP/failed.tsv" > "$TMP/failed.v"

paste "$TMP/failed.v" "$TMP/failed.clers" "$TMP/failed.tsv" \
    | awk -F"$(printf '\t')" '{ print $1 "\t" $2 "\t" $4 "\t" $5 }' \
    | sort -k1,1n -k2,2
