# Worker `plan`

Invoke `maat:plan-review-cycle` (or `maat:plan-review-cycle-light` with `--light`) with the Skill tool, passing the spec
path plus `--tests` / `--no-dev`. Write a `▶` line for each round's outcome (reviewers, blocker/major in a phrase
each, revisions, gate). `OK` only if the plan section now has `^Plan status: APPROVED`; otherwise `STOP` with the
open decision (the cut proposal of a spec over the ceiling included). In format 2 the light branch runs only when
`plan-check.sh route` says `Percorso: leggero`: with `--light` and `Percorso: pieno` the plan skill goes on with
the full branch — say it in a `▶` line. JSON: `"fase": "plan"`.
