# Worker `test-red` — acceptance tests red before the code (format 2)

A code phase with a write scope of its own: the guard lets Edit/Write touch only the plan's test files, the
files the plan declares new (`` `path` (new) `` or `` (nuovo) ``) and the other touched files for additive stubs
(`stub <path>`); no full suite runs. Launch the `maat:acceptance-test-writer`
agent with the spec path, mode `test-red` and the scope
(`bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-check.sh" accept <spec>`). It writes one test per row of
`### Test plan` (`### Piano di test`) and a stub per new symbol. A prompt line `RIPRESA (driver): … stub mancanti: …`
goes to the agent as it is. Its `Plan deviation` or `Blocked on` (also the
Italian `Deviazione dal piano`, `Bloccato su`) → STOP. End with `PHASE RESULT test-red: OK — <tests, stubs>` and the JSON block (`"fase": "test-red"`).

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
