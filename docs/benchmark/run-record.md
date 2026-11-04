# Run record

One record per run, for all 30 runs, failed and interrupted ones included. A run is never repeated or discarded.
`run-bench.sh run` writes the raw files in `records/<run-id>/`; the record `record.json` is filled in from them
following the template `run-record.template.json`.

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
| `cost_usd_api_equivalent` | Maat: `cost-summary.txt` (phase-usage.py `--summary`, as printed); baseline: `total_cost_usd` of the `result` event |
| `cost_breakdown` | Maat: per phase, from `cost-summary.txt`; baseline: tokens per model from the `result` event |
| `final_diff`, `final_diff_sha256` | `final.diff`, `final.diff.sha256` (`.claude/` excluded) |
| `report` | Maat: `spec-with-plan-and-review.md` + `outcome.txt`; baseline: `report.md` |
| `hidden_tests` | `{passed, total}` from the hidden runner (`hidden: p/t`), run after all runs |
| `blind_review_code`, `blind_review_entries`, `confirmed_defects`, `undisclosed_defects` | `blind-review.md` |
| `notes` | anything unusual, written when it happens, never removed |
