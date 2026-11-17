# Counterproofs of the review worker

Read only when they are yours: the prompt has no `VERIFY IN PARALLELO` line saying the driver runs them (a
`plan-check.sh gen` list still coherent with the plan). A counterproof `FAIL` is recorded and passed to the review,
which writes it as a failed required gate and spends a round — that is what bounds the loop. You may rewrite
`mutations.json` every round.

The plan gates the declared remote verification (`verifica_remota` in `.claude/maat.json`) cannot run: a mutation of the feature's code must turn the named test red
on the named assertion. They run through **one script**, only in the WSL mirror — the working tree is
never touched, so there is nothing to copy, restore or pair by hand:

1. **write `<run-dir>/counterproof/mutations.json`** (Write is allowed there in the review phase): a
   JSON list, one entry per counterproof of the plan —
   `{"id", "file", "simbolo", "mutazione": {"cerca", "sostituisci"}, "test": {"percorso", "nome"},
   "rosso_se": {"test_id", "asserzione"}, "superficie"?}`. `file` and `test.percorso` are relative to
   the repository; `cerca` is an exact text that occurs **once** in the file; `rosso_se` is the test's
   id (vitest full name, pytest node id) plus a text of the assertion's failure message. A "revert" gate
   is written as the substitution that removes the feature's code at the named symbol. The format and
   the esiti are documented in the script's header. **Format 2: do not write it** — run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-check.sh" gen .claude/.ai-workflow/spec-<name>.md`, which
   generates it from the plan's test table (the rows with a mutation), with the rest of the procedure
   in `<run-dir>/gen/procedura.txt` (its `cmd counterproof:` line is the command of step 3). Exit 1 =
   a malformed row: the counterproofs are `BLOCKED` with its message, never rewritten by hand;
2. if the gate names **no** file or symbol (e.g. "revert the whole feature") → no entry,
   `NOT RUN (il gate non nomina file)`; if one of the files is **mixed** → `NOT RUN (file misto)`; if the
   mutated file and the test are in **different modules** of `.claude/maat.json` (a file of one module
   observed with a test of another: the script refuses it with exit 64, because the other runner cannot see the
   mutation) → no entry, `NOT RUN (moduli diversi)`. All three are reported with the command the user
   can run by hand (for the last one: apply the mutation, run the named test with its own runner, restore);
3. **run it** (Bash, background, collected before step 3 of the review worker):
   the `cmd counterproof:` line of `<run-dir>/gen/procedura.txt`, or
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/counterproof.sh" .claude/.ai-workflow/spec-<name>.run/counterproof/mutations.json`
   from the repository root — inside WSL (`wsl -- bash -lc '…'`, paths as `/mnt/<drive>/…`) when a module of the
   mutations has `ambiente: wsl`.
   It takes the mirror's lock with a wait (`FIC_LOCK_WAIT`, default 900 s) and **never** falls back to
   `/mnt/c`; it syncs and verifies the mirror, runs each mutation's test alone, restores and re-hashes.
   Exact duplicates run once. Mutations of runner `vitest` under the `radice` of the module with `copia` run
   **in parallel** on private copies when memory allows (gradino 2); the others run serially in the mirror.
   A module at the **repository root** (`"radice": "."`, 1.8.0) runs too, if it has no `copia`: it syncs the whole
   mirror (never `.git`, the cycles folder, the `.fic-*` copy state or the `collega_nel_worktree` folders of the other
   modules) and takes the lock of every module first, under one wait. A module **with** `copia` at the root is still
   refused (exit 64): that is the limit left, said by `maat-doctor` before the cycle;
4. **pass the `<id>.json` files to the review** — their `esito`, `controprova`, `messaggio` and
   `output_coda` are the observed output. Only `rosso_asserzione` is a full proof (`PASS`); `rosso_generico`
   (module runner `comando`: the command exited non-zero, no report says on which assertion) is `PASS` too but
   a **weak** proof — the review counts it as such and says so; `rosso_import`, `rosso_raccolta`, `rosso_diverso`
   and `verde` are `FAIL`; `bloccato` is `BLOCKED`; `non_eseguita` (the module declares no `controprova` in
   `maat.json`) is `NOT RUN (dichiarato)`, never green nor red. **L2** (harness-pt11):
   an entry `gen` marked `"assorbita": true` — a **new** file whose test was red on the `red if` (`rosso se`) assertion on
   the base with stubs (`test-red`) and is green now — is not run (`esito: "assorbita"`): that pair is its
   counterproof. `finalize.sh` accepts it only if `plan-check.sh l2` confirms it on the current code (`tests`
   fingerprint unchanged, the stubs are exactly the new exported symbols, each of them used by an acceptance
   test). Before each review the driver applies that same check and removes `assorbita` from the entries
   that fail it (harness-pt15: they are run like any other). Modified existing files keep every counterproof;
5. exit codes: `0` all proofs · `1` some `FAIL` · `2` some `bloccato` · **`3` environment** (lock not
   obtained, mirror absent or stale, sync failed, or the mirror changed during the parallel stage):
   **the results of this run do not count, even if some `<id>.json` exist** — the gates are `BLOCKED`,
   never `FAIL` or `PASS` · **`5` mirror not restored** → STOP · `64` a malformed `mutations.json` (fix
   it and rerun).

A counterproof that needs DEV, the database, e2e or any shared state stays outside the script and runs
by hand, **serially**, always.
