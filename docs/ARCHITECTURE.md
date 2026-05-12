# Architecture

## Stable reproducibility route

```
primegen                  → prime CLERS list for v in [vmin, vmax]
clers                     → face-list decode (called inline by euclid_lm)
euclid_lm                 → LM-sparse solve + realize (in-process per chunk)
                            output: one OBJ per CLERS
euclid_prover (molasses)  → rigorous interval-arithmetic verdict per OBJ
                            output: TSV row, log on REJECT
collect_failures.sh       → failures.tsv (REJECT rows only)
```

The boundary between stages is plain files: TSVs of CLERS strings, then
directories of OBJ files, then TSVs of `<CLERS, verdict>` rows.  Each
stage runs as a chunked C binary or as a chunked shell driver around a
per-OBJ binary; no per-CLERS Python interpreters in any hot loop.

## Non-included routes

The following exist elsewhere in `~/Dropbox/neo/` but are **not** part of
this reproducibility pipeline:

| Path | Why excluded |
|---|---|
| `~/Dropbox/neo/ideal/`          | research repo for ideal hyperbolic horoball packings and the bracket-existence proof. Its OBJ-producing scripts (`puffup_c`, `hyperpuff_c`, `lm_march_c`) are upstream of the LM-sparse work but the reproducibility run uses the orchestrator's `euclid_oneshot` binary, not `ideal/src` directly. |
| `~/Dropbox/neo/homotopy_stage/` | alternative Euclidean realizer (`puffup_c`, α=0→π/3 homotopy). Documented as a peer route but not used for v=4..50. |
| oneshot float prover            | `euclid_oneshot` has a fast nonrigorous interval-stripped prover mode that runs in-memory after the LM solve.  It is used for triage, not for the rigorous proof of record. |
| `~/Dropbox/neo/euclid_approver/` | catalog of approved floppers / atom fusion. Bootstrap; not yet usable. |
| MMA preprover                   | `euclid_prover/mma_preprover/` — precision-needs estimator, not a certifier. |
| atlas generation                | publication site; orthogonal to reproducibility. |
| `~/Dropbox/neo/undented/`       | publication-target standalone build of the whole pipeline.  Different toolchain (neoeuc_c) — not what produced the v=4..50 reference data. |

## Component table

| Component       | Pinned commit | Upstream                                              |
|-----------------|---------------|-------------------------------------------------------|
| clers           | tracked submodule | `git@github.com:peterdoyle1717/clers.git`           |
| primegen        | tracked submodule | `https://github.com/peterdoyle1717/primegen.git`    |
| euclid_lm       | tracked submodule | `~/Dropbox/neo/euclid_lm/` (extracted 2026-05-11 from `orchestrator/tools/euclid_oneshot/` working tree) |
| euclid_prover   | tracked submodule | `git@github.com:peterdoyle1717/euclid_prover.git`   |

## euclid_lm extraction (done 2026-05-11)

- **Source repo:** `~/Dropbox/neo/euclid_lm/`.  Pipeline submodule pin
  follows that repo's `main` branch.
- **Origin:** extracted from `~/Dropbox/neo/orchestrator/tools/euclid_oneshot/`
  **working tree** state on 2026-05-11 (not orchestrator HEAD `13ef4fd`,
  which predates the `--objs-out-root` flag the reference run depended on).
- **Trim:** the initial extraction kept the orchestrator's full triage
  binary (LM + euclid_check + float-prover); a follow-up commit on euclid_lm
  trimmed that to the minimal OBJ producer (LM-sparse + realize + OBJ
  writer only).  Binary name: `bin/euclid_lm`.  CLI:
  `--input-list FILE --objs-out-root DIR`.
- **Provenance caveat for v=4..50 reference run.** The doob OBJ-generation
  manifest records `git_rev_orchestrator=53b50c8` — earlier than `13ef4fd`.
  Sources used by the run lived only in the orchestrator working tree at
  launch time.  The OBJ-emission code path (CLERS decoder + realize +
  write_obj + LM solve) was byte-copied into `euclid_lm/src/euclid_lm.c`
  from the orchestrator working tree on 2026-05-11.  The CCAE v=4 OBJ
  produced by the trimmed `bin/euclid_lm` byte-matches the prior
  `bin/euclid_oneshot --objs-out-root` output on the same CLERS, confirming
  the kept code is functionally unchanged.  A doob-side `md5sum` of
  orchestrator source files at the time of the reference build would be
  needed to certify byte-equivalence to the production binary's source.
- **What was dropped (belongs elsewhere):**
  - `data/failures_4_50*.tsv` — historical float-prover output; the
    pipeline keeps the rigorous molasses failure list in
    `data/expected/v4_50/`.
  - `scripts/{molasses_chunk_worker.sh, follow_molasses_when_objs_done.sh}`
    — molasses orchestration belongs in this repo's `scripts/`, not in
    the solver.
  - `src/euclid_prover_float.c`, `src/euclid_check/*` — the in-memory
    triage stage; the rigorous prover lives in its own submodule.

## Realizer placement

`~/Dropbox/neo/euclid_realize/` is a separate clean repo intended as the
canonical bends→OBJ writer (its `README.md` declares the unified-route
contract: `solver --bends-out → puffup-bends 1 → euclid_realize → OBJ →
euclid_check`).  The v=4..50 reference run did **not** use it — the realize
step ran inline inside `euclid_oneshot`.  Per the reproducibility rule
(include the realizer only if it's separately used), it is **not** a submodule
here.  When `euclid_lm` is extracted, the inline realize logic stays inside
it, mirroring what was actually run.

## Prover provenance

- Reference doob binary: `/home/doyle/neo/ideal/src/euclid_prover` with
  `prover_md5=e376582e604a39b57291c40609d48f5f` (recorded in molasses
  `manifest.txt`).
- This binary was built from doob's mirror of `~/Dropbox/neo/ideal/` —
  i.e. from `ideal/src/euclid_prover.c`, **not** from the extracted
  `~/Dropbox/neo/euclid_prover/` repo.
- Verification TODO: confirm that `ideal/src/euclid_prover.c` at the
  doob-build commit is byte-identical to `~/Dropbox/neo/euclid_prover/src/euclid_prover.c`
  at `8a11dfa` (current `main`).  If they agree, `submodules/euclid_prover`
  is a faithful pin for reproducibility.  If they diverge, record which
  source corresponds to the reference run.

## Speed discipline

This repo inherits the project rules from
`~/Dropbox/neo/CLAUDE.md`:

- no per-CLERS OS-process spawning in any sweep,
- chunked C binaries with SuperLU for the LM solve,
- doob runs at `nice -n 19`, up to 96 workers,
- no Python interpreter in a sweep's hot loop,
- the per-OBJ rigorous prover is one process per OBJ (it does not support a
  chunked mode), so molasses uses a chunked shell **worker** that amortises
  the process cost across many OBJs in one bash process (see
  `scripts/run_prover.sh`).
