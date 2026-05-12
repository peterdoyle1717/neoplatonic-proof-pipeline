# neoplatonic-proof-pipeline

This repo reproduces the neoplatonic existence computation for a requested
vertex range. It pins the exact components used to:

1. generate the prime CLERS/net list,
2. generate official Euclidean OBJs using the LM-sparse solver,
3. run the rigorous `euclid_prover` (the "molasses" run),
4. collect the raw failure list.

The verified reference run is `v=4..50`. See
[`data/expected/v4_50/`](data/expected/v4_50/).

## Scope — included

- `submodules/clers`        — CLERS parser / canonicalizer (pinned)
- `submodules/primegen`     — prime-net generator (pinned)
- `submodules/euclid_lm`    — LM-sparse Euclidean solver + in-process realizer (pinned)
- `submodules/euclid_prover` — rigorous interval-arithmetic prover (pinned)

## Scope — intentionally excluded

- `ideal/`            — separate research repo for ideal hyperbolic
                        realization / bracket proofs. Not on the
                        reproducibility path.
- `homotopy_stage/`   — alternative Euclidean route (puffup_c). Not used
                        for the v=4..50 reference run.
- experimental oneshot float prover    (nonrigorous discovery/triage)
- `euclid_approver/` and fusion work   (atom catalog, not yet usable)
- atlas generation, MMA preprover, undented standalone publication target

## Top-level layout

```
README.md
docs/
  ARCHITECTURE.md       pipeline contract and excluded routes
  REPRODUCE.md          how to run for an arbitrary v range
  DOOB_RUN_NOTES.md     v=4..50 run provenance (paths, counts, hashes)
scripts/
  build_all.sh          build pinned submodule binaries
  generate_primes.sh    primegen + clers → primes.tsv
  generate_objs.sh      primes.tsv → official LM-sparse OBJs
  run_prover.sh         OBJ dir → rigorous prover verdicts
  collect_failures.sh   verdict TSV → failures.tsv (REJECT only)
  reproduce_range.sh    one-shot driver: vmin vmax outdir
data/expected/
  v4_50/                committed audit + 532-row failure list
runs/                   per-run output (gitignored)
submodules/
  clers/                pinned
  primegen/             pinned
  euclid_lm/            pinned (LM-sparse solver, extracted 2026-05-11)
  euclid_prover/        pinned
```

## How to reproduce

Pick a vertex range and an output dir, then:

```sh
scripts/build_all.sh
scripts/reproduce_range.sh 4 50 runs/v4_50
```

On doob the same driver applies, but you should run inside `nohup` and
the script will use `nice -n 19` and 96 workers automatically (see
`REPRODUCE.md`).

The reference v=4..50 run produced 8,239,684 OBJs, 8,239,684 rigorous
verdicts, 8,239,152 ACCEPT, 532 REJECT.  Reproducing should match the
REJECT CLERS set in `data/expected/v4_50/molasses_official_lm_failures.tsv`.

## Status

All four submodules pinned and building.  End-to-end smoke on macOS
(serial fallback when GNU parallel is absent) reproduces the v=4..50
reference verdict on v8 CCCACACCAABE (rigorous REJECT, same
failure_reason as the doob row).  Doob full-range runs are unchanged
from the reference recipe — see `docs/REPRODUCE.md`.

Remaining provenance items for Zenodo readiness are tracked in
`docs/DOOB_RUN_NOTES.md` (prover source-identity check).

## License

MIT for orchestration code in this repo. Each submodule keeps its own
license.
