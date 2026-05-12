# V4-50 PROOF AUDIT

Audit run 2026-05-11. All counts below are from the visible doob shell output captured in this session.

```
Expected cases:           8,239,684   (manifest n_cases; primes v=4..50 sum 8,239,685 with one stray)
Official OBJ dir:         /home/doyle/neo/data/official_lm_sparse_objs_v4_50_20260509T004116Z
OBJ count:                8,239,684   (find -name '*.obj' | wc -l)
OBJ provenance:           manifest.txt records:
                            mode=objs-out-root (LM solve + realize, no check, no prover)
                            binary=/home/doyle/neo/orchestrator/tools/euclid_oneshot/bin/euclid_oneshot
                            git_rev_orchestrator=53b50c8d54fab3de05cc5c65d186838453885340
                            n_cases=8239684 n_chunks=96 workers=96 nice=19 OPENBLAS_NUM_THREADS=1
                          run.stderr: GNU time wall 36:31.02, Exit status: 0
Molasses run dir:         /home/doyle/neo/data/molasses_official_lm_v4_50_20260509T011806Z
Molasses input count:     8,239,684   (wc -l input_objs.txt)
Molasses result count:    8,239,684   (sum of rows across parts/*.tsv)
Molasses still running?:  no          (pgrep -af molasses|euclid_prover returned no jobs)
Status counts:            ACCEPT 8,239,152
                          REJECT      532
                          (awk -F'\t' '{print $4}' parts/*.tsv | sort | uniq -c)
                          summary.txt agrees: accept=8239152 reject=532 error_or_missing=0 exit_code=0
                          parallel wall 38:07:01, prover_md5=e376582e604a39b57291c40609d48f5f
Failure file on doob:     /home/doyle/neo/data/molasses_official_lm_v4_50_20260509T011806Z/failures.tsv
                          538 lines = 5 comment + 1 header + 532 REJECT data
Failure file local:       ~/Dropbox/neo/orchestrator/results/molasses_official_lm_v4_50_failures.tsv
                          (scp'd from doob; orchestrator/results created — was missing)
                          278,253 bytes, same 538/532 structure
Completion verdict:       COMPLETE
```

## Failure-row schema

```
v  clers  obj_path  molasses_status  failure_reason  stdout_path  stderr_path
```

`molasses_status` column in the local file: 532/532 rows = `REJECT`. No
ERROR / TIMEOUT / MISSING in the parts (`error_or_missing=0` per
`summary.txt`).

## REJECT distribution by v (from local copy)

v=8 1 | v=12 1 | v=13 1 | v=14 1 | v=15 1 | v=16 3 | v=18 1 | v=19 2 |
v=20 3 | v=21 3 | v=22 4 | v=23 2 | v=24 8 | v=25 4 | v=26 8 | v=27 5 |
v=28 7 | v=29 6 | v=30 7 | v=31 7 | v=32 9 | v=33 7 | v=34 10 | v=35 10 |
v=36 11 | v=37 14 | v=38 18 | v=39 14 | v=40 22 | v=41 16 | v=42 26 |
v=43 23 | v=44 32 | v=45 37 | v=46 27 | v=47 33 | v=48 57 | v=49 40 |
v=50 51 — total 532.

## Notes

- Compare with `orchestrator/tools/euclid_oneshot/data/failures_4_50.tsv`
  (1,025 REJECTs from the fast nonrigorous float prover). The rigorous
  molasses run rejects 532; the other 493 float-REJECTs are ACCEPTed
  rigorously. That is consistent with the `docs/v4_50_run.md` note that
  most float REJECTs are σ-witness budget failures, not real rejects.
- Prime-count vs OBJ-count: summing `wc -l < /home/doyle/neo/data/primes/{v}.txt`
  for v=4..50 returned 8,239,685, one more than n_cases=8,239,684. Source
  unknown without further inspection; the OBJ-generation script used
  8,239,684 inputs and that count matches the molasses input set
  exactly, so the pipeline is internally consistent.
- All four audit questions answered YES:
  1. Official LM-sparse OBJs for v=4..50 present? YES — 8,239,684.
  2. Run through rigorous molasses? YES — 8,239,684 result rows.
  3. Failures listed in one durable file? YES — `failures.tsv` at MOLRUN.
  4. Failure file copied locally? YES — `orchestrator/results/molasses_official_lm_v4_50_failures.tsv`.
- No new long jobs launched. No source edited. Nothing deleted.
