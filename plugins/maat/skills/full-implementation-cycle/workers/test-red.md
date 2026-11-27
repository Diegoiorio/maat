# Worker `test-red` — acceptance tests red before the code (format 2)

A code phase with a write scope of its own: the guard lets Edit/Write touch only the plan's test files, the
files the plan declares new (`` `path` (new) `` or `` (nuovo) ``) and the other touched files for additive stubs
(`stub <path>`); no full suite runs. Launch the `maat:acceptance-test-writer`
agent with the spec path, mode `test-red` and the scope
(`bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-check.sh" accept <spec>`). It writes one test per row of
`### Test plan` (`### Piano di test`) and a stub per new symbol. A prompt line `RIPRESA (driver): … stub mancanti: …`
goes to the agent as it is. Its `Plan deviation` or `Blocked on` (also the
Italian `Deviazione dal piano`, `Bloccato su`) → STOP, except a `Plan deviation` of the `test-data:` family (below).
End with `PHASE RESULT test-red: OK — <tests, stubs>` and the JSON block (`"fase": "test-red"`).

## Test deviation (`test-data: <Tn> — <what changes> — <why>`, also `dati-test: `)

Only data, fixtures, internal names or the organization of the tests — never an assertion, a requirement, a file or
the name of a test. For each one, before closing, launch in the **foreground** (never `run_in_background`) the agent
`maat:spec-plan-reviewer-light` with a prompt made of these blocks, each pasted **verbatim** (without its prefix):
the lines `judge instructions:`, `test row:`, `trace row:` and `other row:` (the other planned tests of the same file) of
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-check.sh" deviazione - <spec> <Tn>`, the deviation text (with or without its
`test-data:` label), and the output of
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-check.sh" diff-test <spec> <its test file> --run-dir <run-dir>`, run after
the test file is final. A diff of up to 200 lines is pasted verbatim; a longer one (up to 2000 lines): run the same
command with `--file` and paste its one line `diff file: <path> · sha256 <sha>` instead of the diff.
ACCEPT on all → `PHASE RESULT test-red: OK — …` with `"esito": "OK"`, `"bloccato_su": "nessuno"` and the deviations in
`deviazioni`; a STOP of the judge → STOP. The driver checks the call in your transcript and recomputes the diff.

The proof that each test is red on its assertion is the driver's, after you (`run-phase.sh`: targeted
`gates.sh`, then `plan-check.sh rossi`; any other red, a green or a conflict → `.esito` STOP). You do not
re-check it and you never «fix» a test to make it red on something else. A `stub` file changed beyond an addition
is a STOP («stub non additivo»); a red on a missing symbol (`rosso_simbolo`) is resumed by the driver with the stubs.
On a STOP the files of the phase are parked in `<run-dir>/staging/` and the tree goes back to its start; the next
test-red copies them back and runs the agent again.

# Worker `test-stage` — tests on hold (S3)

The same agent in mode `test-stage`, while the plan is under its final gate: the same files under
`<run-dir>/staging/<repository path>` (the guard's scope is that folder), no test run, no lock, never the spec.
`PHASE RESULT test-stage: OK — <files>`.
