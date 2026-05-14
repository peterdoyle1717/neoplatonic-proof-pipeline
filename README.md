# neoplatonic-proof-pipeline

Reproduce the neoplatonic existence computation for a vertex range
v=VMIN..VMAX. Four stages:

1. **prime CLERS list**     — `submodules/primegen` (recurrence: grow + base seeds)
2. **decode CLERS → netcode** — `submodules/clers`
3. **solve + realize + prove** — `euclid/` (three single-file C programs)
4. **collect failures**     — `v <TAB> clers <TAB> verdict <TAB> message`

The verified reference run is `v=4..50` (8,239,684 cases). The
canonical failure list is in [`data/expected/v4_50/`](data/expected/v4_50/).

## Layout

```
README.md
docs/
  ARCHITECTURE.md   pipeline contract
  REPRODUCE.md      how to run an arbitrary range
scripts/
  build_all.sh      builds clers, primegen, and euclid/
  generate_primes.sh   primegen → CLERS lists per v
  collect_failures.sh  euclid manifests → failures.tsv (CLERS-keyed)
  reproduce_range.sh   one-shot driver: VMIN VMAX OUT_DIR
data/expected/v4_50/   committed reference failure list
euclid/
  euclid_clean.c    LM-with-dent-gate solver + realizer
  euclid_prover.c   certified interval-arithmetic prover
  euclid_check.c    combinatorial topology checker
  Makefile          builds all three
  run_parallel_template.sh   batch driver with JOBS/SHARDS/NICE/BLAS_THREADS knobs
  README.md         usage
submodules/
  clers/            CLERS encoder/decoder (pinned)
  primegen/         prime-net generator (pinned)
runs/               per-run output (gitignored)
```

## Reproduce

```sh
scripts/build_all.sh
scripts/reproduce_range.sh 4 50 runs/v4_50
```

`reproduce_range.sh` runs each phase in turn, leaves intermediate
output under `OUT_DIR/`, and finally writes `OUT_DIR/failures.tsv`. If
the requested range overlaps the committed `v4_50` reference, it also
writes `OUT_DIR/compare.txt` with `compare=PASS|FAIL` based on a
CLERS-level set match.

Env knobs (all optional, forwarded to the euclid runner):

```
JOBS           parallel worker count           (default 4)
SHARDS         shard count                      (default 4*JOBS)
NICE           nice level; 0 disables           (default 0)
BLAS_THREADS   per-process BLAS cap             (default 1)
```

No host-specific defaults. For a parallel run on a workstation, set
`JOBS=<n_cores> NICE=19` at invocation. For a laptop smoke test, the
defaults suffice.

## License

MIT.
