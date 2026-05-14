# Euclid trusted-input batch package

This directory contains single-file batch-capable versions of the solver and prover, plus a separate input checker.

- `euclid_clean.c`: solver. One netcode in, OBJ out. Batch mode writes one OBJ per netcode.
- `euclid_prover.c`: prover. One OBJ filename in, report out. Batch mode writes one report per OBJ.
- `euclid_check.c`: separate validator for netcodes and OBJ files.

The solver and prover now assume their inputs are already wellformed, within the compiled capacity, and properly oriented sphere triangulations. Use `euclid_check` before a large run when that assumption needs to be enforced.

The uploaded originals are preserved as:

- `euclid_clean_original.c`
- `euclid_prover_original.c`
- `Makefile_original`

## Build

```sh
make clean
make all
```

On macOS the Makefile links the solver against Accelerate. On Linux it links against LAPACK/BLAS.

## One-off use

Check a netcode, solve it, check the OBJ, prove it:

```sh
./euclid_check --netcode '1,2,3;1,3,4;1,4,2;2,4,3'
./euclid_clean '1,2,3;1,3,4;1,4,2;2,4,3' > out.obj
./euclid_check --obj out.obj
./euclid_prover out.obj > out.report
```

## Batch solver

Input is one netcode per line:

```sh
./euclid_clean --batch --outdir run/solverout/shard_0000 \
  < run/shards/shard_0000 \
  > run/solvermanifest/shard_0000.tsv \
  2> run/solverlogs/shard_0000.err
```

Manifest format:

```text
index<TAB>ok<TAB>netcode<TAB>objpath<TAB>
index<TAB>fail<TAB>netcode<TAB><TAB>message
```

## Batch prover

Input is one OBJ filename per line:

```sh
./euclid_prover --batch --outdir run/proverout/shard_0000 \
  < run/provershards/shard_0000 \
  > run/provermanifest/shard_0000.tsv \
  2> run/proverlogs/shard_0000.err
```

Manifest format:

```text
index<TAB>accept<TAB>objpath<TAB>reportpath<TAB>
index<TAB>reject<TAB>objpath<TAB>reportpath<TAB>message
index<TAB>fail<TAB>objpath<TAB><TAB>message
```

Each batch item is written to a temporary file in the output directory and then renamed into place only after the file is complete.

## Separate checker

One-off:

```sh
./euclid_check --netcode NETCODE
./euclid_check --obj path/to/file.obj
```

Batch:

```sh
./euclid_check --netcodes < all.netcodes > netcheck.tsv
./euclid_check --objs < objfiles.txt > objcheck.tsv
```

Checker manifest format:

```text
index<TAB>ok<TAB>input<TAB>message
index<TAB>fail<TAB>input<TAB>message
```

The checker validates syntax, triangular faces, index ranges, paired opposite edge orientations, Euler characteristic 2, and single-cycle vertex links.

## Smoke tests

```sh
make smoke
make batch-smoke
```

## Parallel run template

A conservative driver script is included:

```sh
JOBS=80 SHARDS=800 ./run_parallel_template.sh all.netcodes
```

By default, the template runs `euclid_check` before the solver and again before the prover. To skip those validation passes after you trust the input set:

```sh
CHECK=0 JOBS=80 SHARDS=800 ./run_parallel_template.sh all.netcodes
```

The script uses GNU parallel if available. If `parallel` is not found, it runs shards sequentially for debugging.

The intended layout is:

```text
run/
  checkmanifest/
  shards/
  solverout/
  solverlogs/
  solvermanifest/
  objfiles.txt
  provershards/
  proverout/
  proverlogs/
  provermanifest/
```

The individual jobs do not write to one shared artifact directory. Each shard gets its own solver/prover output directory. Merge later from the manifests.
