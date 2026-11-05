# Run record

One record per run, for all 30 runs, failed and interrupted ones included. A run is never repeated or discarded.
`run-bench.sh run` writes the raw files in `records/<run-id>/` of `BENCH_HOME`, and `run-bench.sh hidden` adds the
score of the hidden tests; the record `record.json` is filled in from them following the template
`run-record.template.json`. The published copy is `records/<run-id>/` in this folder: `record.json` and the raw
files listed below, never the output of the hidden tests (only their score, until the end).

A field that is not known yet is `null`, never `0`, `false` or `[]`: `[]` means "none", `null` means "not there
(yet)". The blind review and the adjudication come after all 30 runs, so until then `blind_review_code`,
`blind_review_entries`, `confirmed_defects` and `undisclosed_defects` are `null` («pending» in the charts); a
measure that a finished run did not produce (no cost, no hidden score after its one retry) stays `null` too
(«missing» in the charts, with the reason in `notes`).

| Field | Source |
|---|---|
| `run_id`, `task`, `side`, `order` | `schedule.tsv` |
| `spec_sha256` | `SHA256SUMS` (frozen spec) — and `spec_sha256_in_copy`, from `spec-in-copy.sha256` (computed by `prepare`, which refuses a copy whose spec differs) |
| `upstream_repo`, `upstream_commit` | `run-bench.sh` (task table) |
| `base_snapshot_commit` | `.git/bench-base` of the copy (same for every copy of a task: fixed snapshot date) |
| `maat_tag`, `claude_code_version`, `model`, `os` | `environment.txt` (`run-bench.sh check`, exact versions, before the record exists) |
| `model_check` | `model-check.txt`: the model of every session (the `init` event of the baseline transcript, of every Maat phase log) against `ANTHROPIC_MODEL`; a mismatch is recorded, not repeated |
| `started_utc`, `ended_utc`, `wall_clock_s` | `started_utc`, `ended_utc`, `wall_clock_s` |
| `exit_code`, `timed_out` | `exit_code`; `timed_out` = 124 or 137 (the 4 h cap of `timeout -k`) |
| `outcome` | see «Outcome» below |
| `quota` | `quota.txt`: `true` when the transcript, stderr or logs show the usage limit («usage limit», «limit reached», `rate_limit_error`, «out of extra usage»): the run is recorded as it is, with the reason «quota», and reported apart |
| `contaminated` | `audit.txt`: `true` when the audit finds a path outside the run's copy in what the run left (another copy, the mirrors, the records, the hidden tests, `docs/piani`, `/mnt`); the hits are published, the run is not repeated |
| `human_interventions` | list of `{when, reason, what}`; by the procedure there are none during a run (a question or a `STOP` ends the run) |
| `cost_usd_api_equivalent` | Maat: `cost-summary.txt` (phase-usage.py `--summary`, as printed); baseline: `total_cost_usd` of the `result` event; a session cut by the cap writes no cost: its tokens are in `usage_from_transcript` (baseline, `report.md`) or in its phase log (Maat), and the cost is the sum of the costs written, marked as a lower bound in `notes` |
| `cost_breakdown` | Maat: per phase, from `cost-summary.txt`; baseline: tokens per model (`usage_from_transcript`) |
| `final_diff`, `final_diff_sha256` | `final.diff`, `final.diff.sha256` (`.claude/` excluded) |
| `report` | Maat: `spec-with-plan-and-review.md` + `outcome.txt`; baseline: `report.md` |
| `hidden_tests` | `{passed, total}` from `hidden_tests.txt` (`hidden: p/t`, t the fixed total of the task), written by `run-bench.sh hidden` right after the run; `null` after a second infrastructure error |
| `blind_review_code` | the code `R01` … `R30` ([`blind-review.md`](blind-review.md)) |
| `blind_review_entries` | the reviewer's entries, each with its adjudication: `{id, requirement, severity, verdict, reason}`, `verdict` = `confirmed`, `rejected` or `duplicate` (measure 3 = the `confirmed` ones) |
| `confirmed_defects` | the defect list of the run: confirmed review entries and hidden-test defects, merged ([`blind-review.md`](blind-review.md) §3) |
| `undisclosed_defects` | the defects of `confirmed_defects` judged undisclosed, each with the quote of the report (measure 1) |
| `notes` | anything unusual, written when it happens, never removed (`notes.txt` of the record, e.g. the retry of the hidden tests) |

## Outcome

| Side | What the run left | `outcome` | `outcome_detail` |
|---|---|---|---|
| any | `exit_code` 124 or 137 (the cap) | `TIMEOUT` | — |
| Maat | `Driver result: DONE — …` (review `APPROVED`, feature `IMPLEMENTED`) | `IMPLEMENTED` | the DONE line |
| Maat | `Driver result: STOP — …` and `Feature status: NEEDS_VERIFICATION` in the spec | `NEEDS_VERIFICATION` | what remains to verify, from the STOP line |
| Maat | any other `Driver result: STOP`, `WAIT`, `BUSY` or `RUNNING` | `STOP` | the cause, from the line |
| Maat | no `Driver result` line | `ERROR` | the last lines of `driver-stdout.txt` |
| baseline | a `result` event with a final message | `COMPLETED` | — |
| baseline | a `result` event with no message, or an error result | `NO_REPORT` | its `subtype` |
| baseline | no `result` event | `ERROR` | the last lines of `stderr.txt` |

## Raw files of a run

`environment.txt`, `started_utc`, `ended_utc`, `wall_clock_s`, `exit_code`, `final.diff`, `final.diff.sha256`,
`spec-in-copy.sha256`, `spec-after-run.sha256`, `env-packages.txt` (versions of the prepared environment, from
`prepare`), `audit.txt`, `model-check.txt`, `quota.txt`, and Maat: `driver-stdout.txt`, `outcome.txt`,
`spec-with-plan-and-review.md`, `run-dir/`, `cost-summary.txt`; baseline: `transcript.jsonl`, `stderr.txt`,
`report.md`; then `hidden_tests.txt` (and `notes.txt` when something is noted).
