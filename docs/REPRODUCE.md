# Reproducing a vertex range

## Prerequisites

- C compiler, GNU make, GNU parallel.
- SuperLU, BLAS (OpenBLAS recommended), LAPACK headers + libs.
  - macOS: `brew install superlu` for SuperLU; BLAS/LAPACK via Accelerate.
  - Debian/Ubuntu: `apt install libsuperlu-dev libopenblas-dev liblapack-dev`.
- `euclid_lm` is a tracked submodule; `make -C submodules/euclid_lm`
  builds `submodules/euclid_lm/bin/euclid_oneshot` (the wholesale
  binary; the submodule's repo name is `euclid_lm`).

## Quick path

```sh
git clone --recursive <this-repo>
cd neoplatonic-proof-pipeline
scripts/build_all.sh
scripts/reproduce_range.sh VMIN VMAX OUTDIR
```

Example for v=4..10 smoke:

```sh
scripts/reproduce_range.sh 4 10 runs/v4_10
```

Example for full v=4..50 reference:

```sh
NEO_WORKERS=96 NEO_NICE=19 scripts/reproduce_range.sh 4 50 runs/v4_50
```

## Stage-by-stage

```
scripts/generate_primes.sh VMIN VMAX OUT_PRIMES_DIR
scripts/generate_objs.sh    OUT_PRIMES_DIR OUT_OBJ_DIR
scripts/run_prover.sh       OUT_OBJ_DIR OUT_PROVER_DIR
scripts/collect_failures.sh OUT_PROVER_DIR/parts OUT_FAILURES_TSV
```

Each script:

- exits non-zero on first error,
- writes `commands.txt` and a provenance manifest beside its output,
- uses `nice -n "${NEO_NICE:-19}"` on doob-style parallel runs,
- uses `OPENBLAS_NUM_THREADS=1` per worker,
- never spawns one OS process per CLERS for large generation.

## Environment knobs

| Variable               | Default | Meaning |
|------------------------|---------|---------|
| `NEO_WORKERS`          | 96 on doob, `nproc/2` on laptops | parallel worker count |
| `NEO_NICE`             | 19 on doob, unset on laptop | `nice -n` level |
| `OPENBLAS_NUM_THREADS` | 1       | BLAS thread oversubscription guard |
| `EUCLID_LM_BIN`        | `submodules/euclid_lm/bin/euclid_oneshot` | path to the wholesale euclid_lm binary |
| `EUCLID_PROVER_BIN`    | `submodules/euclid_prover/src/euclid_prover` | path to the rigorous prover |

## doob notes

- VPN must be active.
- Use `doob.dartmouth.edu`, not the `doob` alias.
- Place the runs under `/tmp/<run>` or `~/neo/data/<run>` per the standing
  rule that production runs save output on doob, not the laptop.
- The molasses stage runs many hours on v=4..50 (≈ 38h wall on 96 cores at
  `nice 19`).  Run inside `nohup`.

## Comparing your reproduction to the v=4..50 reference

After your run completes, the failure CLERS sets should match:

```sh
diff \
  <(awk -F'\t' 'NR>6{print $1"\t"$2}' runs/v4_50/failures.tsv | sort) \
  <(awk -F'\t' 'NR>6{print $1"\t"$2}' data/expected/v4_50/molasses_official_lm_failures.tsv | sort)
```

Exact-match on `v` and `CLERS` columns is the success criterion.  The
`obj_path` column will differ because it embeds run-specific dirs; that
column is informational, not part of the comparison.
