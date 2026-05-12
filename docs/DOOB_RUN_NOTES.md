# Reference run: v=4..50, 2026-05-09 to 2026-05-10 on doob

This is the recorded provenance of the run whose failure list is committed at
`data/expected/v4_50/molasses_official_lm_failures.tsv`.

## OBJ generation (LM-sparse + realize)

- **Run dir:** `/home/doyle/neo/data/official_lm_sparse_objs_v4_50_20260509T004116Z`
- **Binary:** `/home/doyle/neo/orchestrator/tools/euclid_oneshot/bin/euclid_oneshot`
- **Mode:** `objs-out-root (LM solve + realize, no check, no prover)`
- **Driver:** `parallel --nice 19 -j 96 --env OPENBLAS_NUM_THREADS bin/euclid_oneshot --input-list {} --out-dir <RUN> --objs-out-root <RUN>/objs ::: chunks/chunk_0..095`
- **Orchestrator git rev at launch (per manifest):** `53b50c8`
  - **Caveat:** the orchestrator commit that introduces `euclid_oneshot` is
    `13ef4fd`, which post-dates `53b50c8`.  Sources used by the run lived
    only in the working tree at launch time; they were committed afterwards
    as part of `13ef4fd`.  For exact reproducibility, the `euclid_lm`
    extraction must capture the same source bytes that produced these OBJs,
    not the merged `13ef4fd` tree.
- **Inputs:** 8,239,684 CLERS strings, derived from per-v prime files under
  `/home/doyle/neo/data/primes/{4..50}.txt` on doob.
- **Outputs:** 8,239,684 OBJ files under `<RUN>/objs/v<V>/<CLERS>.obj`.
- **Wall:** 36:31.02. **Exit status:** 0.

## Rigorous prover (molasses)

- **Run dir:** `/home/doyle/neo/data/molasses_official_lm_v4_50_20260509T011806Z`
- **Prover binary:** `/home/doyle/neo/ideal/src/euclid_prover`, md5
  `e376582e604a39b57291c40609d48f5f`.
- **Chunk worker:** `/home/doyle/neo/data/official_lm_sparse_objs_v4_50_20260509T004116Z/molasses_chunk_worker.sh`
- **Chunks:** 96. **Workers:** 96. **`nice`:** 19.
- **Pipeline per OBJ:** one `euclid_prover <obj>` process per OBJ, amortised
  across many OBJs in one bash process per chunk.
- **Inputs:** 8,239,684 OBJ paths (= the OBJ-gen output).
- **Outputs:**
  - `parts/chunk_NNN.tsv` × 96, totalling 8,239,684 result rows.
  - `logs/chunk_NNN_<CLERS>.log` × 532 (one per REJECT only).
- **Verdicts:** 8,239,152 ACCEPT, 532 REJECT, 0 ERROR or MISSING.
- **Wall:** 38:07:01. **Exit status:** 0. **CPU:** 5,258,104 s user + 105,652 s sys.

## Verdict file layout

Each row in `parts/*.tsv` is tab-separated:

```
col 1  v                   integer
col 2  clers               canonical CLERS string
col 3  obj_path            absolute path on doob
col 4  molasses_status     ACCEPT | REJECT | ERROR | MISSING
col 5  elapsed_seconds     %.4f
col 6  stdout_path         "-" on ACCEPT; absolute log path on REJECT/ERROR
col 7  stderr_path         "-" (combined into stdout_path)
col 8  summary             "final: <verdict>" plus existence/embedding/undented lines, semicolon-joined
```

## Audit reference

The audit that produced the committed failure list is
[`data/expected/v4_50/V4_50_PROOF_AUDIT.md`](../data/expected/v4_50/V4_50_PROOF_AUDIT.md).
That file's "Where each claim comes from" section anchors each count to
the doob shell output that produced it.

## Pre-existing failure list

The orchestrator also stores a separate failure list at
`~/Dropbox/neo/orchestrator/tools/euclid_oneshot/data/failures_4_50.tsv`
(1,025 rows).  Those came from the **fast nonrigorous float prover** that
runs inside `euclid_oneshot` (interval-stripped, LAPACK σ-witness).  493
of those 1,025 are ACCEPTed by the rigorous prover; only 532 are real
rigorous REJECTs.  This repo treats the 532-row list as the canonical
failure record for v=4..50.

## Open verification items

- `euclid_prover` source identity.  Doob built from `ideal/src/euclid_prover.c`;
  the extracted `~/Dropbox/neo/euclid_prover/` (at `8a11dfa`) needs to be
  confirmed byte-identical to that file at the doob-build commit.
- `euclid_lm` extraction.  Source bytes must match the working tree state of
  `orchestrator/tools/euclid_oneshot/` at OBJ-gen launch time, not the merged
  `13ef4fd` tree (the two differ by the `LM_MARCH_LIBONLY` mode added to
  `lm_march_c.c` after the OBJ run completed — confirm with `git diff` against
  the doob host history once the extraction lands).
