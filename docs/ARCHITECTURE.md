# Architecture

The pipeline is a four-stage chain:

```
primegen           submodules/primegen
   v -> CLERS list per v
   |
clers decode       submodules/clers
   CLERS line -> netcode (face list "a,b,c;...")
   |
euclid pipeline    euclid/
   (a) euclid_check --netcodes  combinatorial topology gate
   (b) euclid_clean --batch     LM-with-dent-gate solve + realize -> OBJ
   (c) euclid_check --objs      OBJ topology gate
   (d) euclid_prover --batch    rigorous interval-arithmetic verdict
   |
collect_failures   scripts/collect_failures.sh
   joins solver+prover manifests by OBJ path,
   emits v <TAB> clers <TAB> verdict <TAB> message
```

## Contract per stage

**primegen**: per-v CLERS lists at `OUT/primes/v{V}.txt`. Empty file
allowed (v=5 has no primes).

**clers decode**: stdin one CLERS per line, stdout one netcode per
line. Bulk decode in a single process.

**euclid_clean**: input netcode, output OBJ with vertex coordinates in
`%.17f` fixed-point (no scientific notation). LM iterates with
adaptive damping and a dent gate that rejects any trial step where
some vertex's flower sum of bends is negative. Realize is BFS from
face 0 in the standard gauge `V[b0]=(0,0,0.5), V[b1]=(0,0,-0.5),
V[b2]=(sqrt(3)/2,0,0)`.

**euclid_check**: combinatorial sanity. Triangulated sphere, Euler
characteristic 2, single-cycle oriented link at every vertex, no
duplicate directed edges. Pre-filters bad CLERS before the solver and
bad OBJs before the prover.

**euclid_prover**: three certificates, each via interval arithmetic
with `nextafter`-based directed rounding (do NOT compile with
`-ffast-math`):

  * EXISTENCE  -- `rho_upper < sigma_lower^2 / (16 sqrt E)`.
  * EMBEDDING  -- `sqrt(V) * motion_upper < collision_lower`.
  * UNDENTED   -- `sin(T/2) > 0` at every vertex link.

ACCEPT iff all three pass.

## Batch contract

Both solver and prover support a `--batch --outdir DIR` mode that
reads one item per line from stdin and emits one manifest row per
input line on stdout:

```
solver:   index  ok|fail              netcode  objpath        message
prover:   index  accept|reject|fail   objpath  reportpath     message
```

Per-item output files use temp-then-rename for atomic writes. File
names are `n{index:08d}_{fnv64hash:016x}.{obj,report}`; the manifest
is the canonical CLERS-↔-output mapping.

## Sharding

`euclid/run_parallel_template.sh` shards stdin round-robin across
SHARDS files and runs them under GNU parallel (`-j JOBS`). Falls back
to a serial loop if `parallel` is not on PATH.

`BLAS_THREADS=1` is exported by default so the solver's LAPACK calls
don't oversubscribe under parallel.

## What's not in this repo

Anything not on the reproducibility path. No homotopy/ideal solvers,
no MMA experiments, no atlas, no approver/catalog work. Those live in
separate repos.
