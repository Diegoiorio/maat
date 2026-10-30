# Worker `fix`

You are launched only on a `Next: FIX` of the driver: the fix budget (`Review rounds: n/3` and `post-approval
NEEDS_CHANGES: k/1`, a fix only with `n < 3` and `k < 1`) is code (`cycle-state.sh` row 11b). Launch
`maat:plan-implementer` in `fix` mode with **only** the blocker/major findings and the `FAIL` gates of the review
section, plus the do-not-touch and mixed lists of the run directory, plus the generated files of `.claude/maat.json`
(the lines of `"$FIC_PY" "${CLAUDE_PLUGIN_ROOT}/scripts/maat-config.py" generati`) with the `File generati:` text of
`workers/implement.md` (a test `FAIL` that only asks to realign a generated file is fixed by its command). Any other
unnamed file stays a deviation; `Rigenerati: <paths>` in the `ESITO` summary. Handle its report as `workers/implement.md`
says (deviation → STOP, unless all are `difensiva: …`: recorded, no STOP; migration → STOP, partial → one
relaunch in `fix` mode). The next review computes the
delta itself from the changed snapshot. JSON: `"fase": "fix"`.
