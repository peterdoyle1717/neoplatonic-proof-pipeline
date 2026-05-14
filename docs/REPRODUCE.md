# Reproducing a run

```sh
git clone --recurse-submodules https://github.com/peterdoyle1717/neoplatonic-proof-pipeline.git
cd neoplatonic-proof-pipeline
./scripts/build_all.sh
./scripts/reproduce_range.sh 4 20 runs/v4_20
```

That's it. `reproduce_range.sh` runs four phases:

1. **primegen**     -> `runs/v4_20/primes/v{V}.txt` (CLERS per v).
2. **clers decode** -> `runs/v4_20/netcodes.txt`.
3. **euclid**       -> `runs/v4_20/euclid/{checkmanifest,solverout,solvermanifest,proverout,provermanifest,...}/`.
4. **collect**      -> `runs/v4_20/failures.tsv` (one row per non-accept verdict, CLERS-keyed).

If the requested range overlaps the committed reference v=4..50, it
also writes `runs/v4_20/compare.txt`:

```
compare_range=v4..v20
expected_failures=14
produced_failures=14
common=14
only_in_expected=0
only_in_produced=0
compare=PASS
```

## Tuning

```sh
JOBS=96 NICE=19 BLAS_THREADS=1 ./scripts/reproduce_range.sh 4 50 runs/v4_50
```

Reasonable defaults on a workstation. No host-specific code paths;
nothing wired in by default.

## Requirements

- C11 compiler, `make`, `awk`, `sort`, `join`, `paste`.
- LAPACK + BLAS (linker flags `-llapack -lblas`). On macOS the
  Makefile uses `-framework Accelerate` instead.
- `GNU parallel` (optional; the runner falls back to a serial loop).
- Disk space scales with v. v=4..50 produces about 40 GB of OBJs and
  another ~5 GB of prover reports. v=4..20 is < 100 MB.

## Re-running from intermediate state

`reproduce_range.sh` skips primegen and clers-decode if their output
already exists. To force a re-run, delete the corresponding directory
or file under `OUT_DIR` before invoking.

## Expected verdict counts

For the committed reference range:

```
v=4..50    8,239,684 cases    8,239,152 accept    532 reject
```

The 532-row reject list is at
`data/expected/v4_50/molasses_official_lm_failures.tsv`.
