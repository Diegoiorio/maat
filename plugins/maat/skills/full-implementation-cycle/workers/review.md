# Worker `review`

1. A `*.meta` sidecar in `<run-dir>/counterproof/` (the old copy-and-restore recipe) → STOP: a file of the
   working tree may still be mutated; it is restored by hand, never automatically.
2. **Counterproofs.** The prompt ends with `VERIFY IN PARALLELO (driver, run-phase.sh): …` and says the driver
   runs them → they are already running outside this session: skip this step. Otherwise they are yours, all of
   them, every time: read `workers/controprove.md` and run them before step 3.
3. Invoke `maat:implementation-review-cycle` with the Skill tool, **by name** (`<name>`, mode a), forwarding
   `--tests`, `--no-dev`, `--with-e2e`, `--base`, plus as extra context: the `touched.txt` list («paths the
   feature's phases changed — measured, never exclude»), the do-not-touch list with its reason, your
   counterproof results with their observed output, and **as is** the prompt's lines
   `EVIDENZE DEI GATE (driver, run-phase.sh): <dir>`, `VERIFY IN PARALLELO (driver, run-phase.sh): …`,
   `DEVIAZIONI DIFENSIVE (driver, run-phase.sh): <file>` with the lines under it, and, for
   ring k>1 of a chain, `DIFF DELL'ANELLO (driver, run-phase.sh): <file> …` with its index (the ring's review
   surface, built by the driver: the reviewer reads it, never a diff against HEAD), plus the `Anelli
   precedenti:` files as exclusion candidates, written in `Excluded:` as `<path> — same chain, previous ring (<spec>)` (Italian: `stessa catena, anello
   precedente`; only the path counts) — a path also in this
   ring's `touched.txt` is never excluded.
   With `VERIFY IN PARALLELO` do not run nor wait for the level's suites and do not cite their results; with
   gates run by the model (you, the declared remote verification (`verifica_remota` in `.claude/maat.json`), a sub-agent) a static review in parallel is **forbidden**.
4. `PHASE RESULT review: OK — Review status <…> · Feature status <…> · Verification <…> · Review rounds <n>/3`
   (OK even for `NEEDS_CHANGES`: the driver decides what follows), then the JSON with the blocker/major in
   `finding` and, for every requirement, the IDs of the tests that cover it in `copertura`
   (`[{"requisito": "<ID>", "test": ["<pytest node id | frontend test file path | counterproof id>"]}]` — IDs,
   never results). `IMPLEMENTED` is the review's proposal: `finalize.sh` signs the state after the phase.
