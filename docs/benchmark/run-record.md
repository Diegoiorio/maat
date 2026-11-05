# Run record

One record per run, for all 30 runs, failed and interrupted ones included. A run is never repeated or discarded.
`run-bench.sh run` writes the raw files in `records/<run-id>/` of `BENCH_HOME`, and `run-bench.sh hidden` adds the
score of the hidden tests; the record `record.json` is filled in from them following the template
`run-record.template.json`. The published copy is `records/<run-id>/` in this folder: `record.json` and the raw
files listed below, never the output of the hidden tests (only their score, until the end).

A field that is not known yet is `null`, never `0` or `[]`: `[]` means "none", `null` means "not there yet". The
blind review and the adjudication come after all 30 runs, so until then `blind_review_code`,
`blind_review_entries`, `confirmed_defects` and `undisclosed_defects` are `null`. [`grafici.py`](grafici.py) draws a
`null` as «not yet available».

| Field | Source |
|---|---|
| `run_id`, `task`, `side`, `order` | `schedule.tsv` |
| `spec_sha256` | `SHA256SUMS` (frozen spec) — and `spec_sha256_in_copy`, computed in the copy before the run |
| `upstream_repo`, `upstream_commit` | `run-bench.sh` (task table) |
| `base_snapshot_commit` | `.git/bench-base` of the copy (same for every copy of a task: fixed snapshot date) |
| `maat_tag`, `claude_code_version`, `model`, `os` | `environment.txt` (`run-bench.sh check`, at the start of the run) |
| `started_utc`, `ended_utc`, `wall_clock_s` | `started_utc`, `ended_utc`, `wall_clock_s` |
| `exit_code`, `timed_out` | `exit_code` (124 = the 4 h cap) |
| `outcome` | Maat: `IMPLEMENTED`, `NEEDS_VERIFICATION` (with its reason) or `STOP` (with its cause), from `outcome.txt` and the spec; baseline: `COMPLETED` (a final report), `NO_REPORT`, `ERROR` or `TIMEOUT` |
| `human_interventions` | list of `{when, reason, what}`; by the procedure there are none during a run (a question or a `STOP` ends the run) |
| `cost_usd_api_equivalent` | Maat: `cost-summary.txt` (phase-usage.py `--summary`, as printed); baseline: `total_cost_usd` of the `result` event; `null` if the run left none |
| `cost_breakdown` | Maat: per phase, from `cost-summary.txt`; baseline: tokens per model from the `result` event |
| `final_diff`, `final_diff_sha256` | `final.diff`, `final.diff.sha256` (`.claude/` excluded) |
| `report` | Maat: `spec-with-plan-and-review.md` + `outcome.txt`; baseline: `report.md` |
| `hidden_tests` | `{passed, total}` from `hidden_tests.txt` (`hidden: p/t`), written by `run-bench.sh hidden` right after the run; `null` if the runner gave no score (`hidden: error`, noted in `notes`) |
| `blind_review_code` | the code `R01` … `R30` ([`blind-review.md`](blind-review.md)) |
| `blind_review_entries` | the reviewer's entries, each with its adjudication: `{id, requirement, severity, verdict, reason}`, `verdict` = `confirmed`, `rejected` or `duplicate` (measure 3 = the `confirmed` ones) |
| `confirmed_defects` | the defect list of the run: confirmed review entries and hidden-test defects, merged ([`blind-review.md`](blind-review.md) §3) |
| `undisclosed_defects` | the defects of `confirmed_defects` judged undisclosed, each with the quote of the report (measure 1) |
| `notes` | anything unusual, written when it happens, never removed |

Raw files of a run: `environment.txt`, `started_utc`, `ended_utc`, `wall_clock_s`, `exit_code`, `final.diff`,
`final.diff.sha256`, `spec-after-run.sha256`, `env-packages.txt` (versions of the prepared environment), and
Maat: `driver-stdout.txt`, `outcome.txt`, `spec-with-plan-and-review.md`, `run-dir/`, `cost-summary.txt`; baseline:
`transcript.jsonl`, `stderr.txt`, `report.md`; then `hidden_tests.txt`.
