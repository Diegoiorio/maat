# Worker `plan`

Invoke `maat:plan-review-cycle` with the Skill tool, passing the spec path plus `--tests` / `--no-dev`, and `--full` or
`--light` when the prompt has them: the size of the cycle (1.7.0) is decided inside it, by `plan-check.sh taglia`.
Write a `▶` line for each round's outcome (reviewers, blocker/major in a phrase each, revisions, gate) and one for the
size (`Taglia:` and any `Escalation:`). `OK` only if the plan section now has `^Plan status: APPROVED`; otherwise
`STOP` with the open decision (the cut proposal of a spec over the ceiling included). A prompt line `RIAPERTURA
(driver): <cause> — …` (E2: the approved plan is above the small size): re-open the approved plan with the
re-opening procedure of `plan-review-cycle`, with no amendment, and review it in the full branch (`--full`, from
Step 2); its metric line says `taglia=piena`. JSON: `"fase": "plan"`.
