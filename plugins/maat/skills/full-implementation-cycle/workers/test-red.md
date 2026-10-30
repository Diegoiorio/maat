# Worker `test-red` — acceptance tests red before the code (format 2)

A code phase with a write scope of its own: the guard lets Edit/Write touch only the plan's test files and the
files the plan declares new (`` `path` (nuovo) ``); no full suite runs. Launch the `maat:acceptance-test-writer`
agent with the spec path, mode `test-red` and the scope
(`bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-check.sh" accept <spec>`). It writes one test per row of
`### Piano di test` and a stub per new symbol. Its `Deviazione dal piano` or `Bloccato su` → STOP. End with
`ESITO FASE test-red: OK — <tests, stubs>` and the JSON block (`"fase": "test-red"`).

The proof that each test is red on its assertion is the driver's, after you (`run-phase.sh`: targeted
`gates.sh`, then `plan-check.sh rossi`; any other red, a green or a conflict → `.esito` STOP). You do not
re-check it and you never «fix» a test to make it red on something else.

# Worker `test-stage` — tests on hold (S3)

The same agent in mode `test-stage`, while the plan is under its final gate: the same files under
`<run-dir>/staging/<repository path>` (the guard's scope is that folder), no test run, no lock, never the spec.
`ESITO FASE test-stage: OK — <files>`.
