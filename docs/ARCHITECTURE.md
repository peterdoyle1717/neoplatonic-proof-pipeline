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
| euclid_lm       | NOT YET CLEAN     | currently at `~/Dropbox/neo/orchestrator/tools/euclid_oneshot/` (vendored, not a separate repo) |
| euclid_prover   | tracked submodule | `git@github.com:peterdoyle1717/euclid_prover.git`   |

## COMPONENT NOT YET CLEAN: euclid_lm

- **Current path:** `~/Dropbox/neo/orchestrator/tools/euclid_oneshot/`
- **What's there:** `src/euclid_oneshot.c`, `src/lm_march.c`, `src/euclid_prover_float.c`,
  `src/euclid_check/*` (vendored from `~/Dropbox/neo/euclid_check/`), `Makefile`,
  scripts (`run_doob_vrange.sh`, `molasses_chunk_worker.sh`,
  `follow_molasses_when_objs_done.sh`), `docs/v4_50_run.md`, `data/failures_4_50*.tsv`.
- **Why not a separate repo yet:** committed directly inside the orchestrator
  (`13ef4fd Add euclid oneshot batch prover`).  Sources were originally drafted
  in `~/Dropbox/neo/ideal/src/` (`oneshot_c.c`, `lm_march_c.c`,
  `euclid_prover_float.c`) and copied verbatim into the orchestrator tree.  No
  upstream git history of its own.
- **Needed extraction:**
  1. Create `peterdoyle1717/euclid_lm` repo (private OK for now).
  2. Move `src/{euclid_oneshot.c, lm_march.c, euclid_prover_float.c}` and
     vendored `src/euclid_check/` from the orchestrator into the new repo.
  3. Bring the Makefile and the doob scripts along.
  4. Pin the resulting commit here as `submodules/euclid_lm`.
- **Provenance caveat for v=4..50 reference run.** The doob OBJ-generation
  manifest records `git_rev_orchestrator=53b50c8` — which is the orchestrator
  commit **before** `13ef4fd Add euclid oneshot batch prover`.  Sources used by
  the run lived only in the working tree at launch time; they were committed
  later as `13ef4fd`.  Once `euclid_lm` is extracted, its initial commit must
  capture the **same source contents** that produced the reference data.

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
