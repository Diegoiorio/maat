# Orchestrator — /full-implementation-cycle launched by the user

Read by the orchestrator only (`SKILL.md`, «Which mode you are in»); the workers never load it.

Prima di ogni comando Bash o PowerShell, scrivi `description` secondo `${CLAUDE_PLUGIN_ROOT}/docs/descrizione-comandi.md`.

## Orchestrator

1. **`<name>`**: a spec path → basename without `spec-` and `.md`. Pasted text → a kebab-case slug of its first
   heading (none → ask now) and the container `.claude/.ai-workflow/spec-<name>.md` with the text as `## Context`
   and `## Functional requirements`.
2. **S0, before the first phase only** (no `log/*.exit` yet): ask the user now the critical ambiguities (a draft
   spec → the `maat:spec-author` agent in analysis only); say whether the feature needs a migration (a human STOP when
   the implement writes it) and whether the spec may be split into a chain (the plan phase proposes the cut,
   once per feature). Nothing to ask → say so in one line. Always tell the user: «do not change files in this
   working tree during the cycle: to work in parallel use another worktree
   (`git worktree add ../<repo>-lavoro -b <branch> develop`)». If the user (or other sessions) will keep working
   in this tree during the cycle and `--worktree` was not given, suggest it: the cycle then runs in its own worktree.
3. **Launch the driver**, Bash with `run_in_background: true`:
   `. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" "${CLAUDE_PLUGIN_ROOT}/scripts/driver.py" run .claude/.ai-workflow/spec-<name>.md -- <flags>`.
   **`--worktree`** (never forwarded to the driver). The DEV stays shared (code sync, e2e context): the per-worktree
   lock protects only the local work, so another cycle or an e2e of the declared remote verification (`verifica_remota` in `.claude/maat.json`) could sync different code onto the
   same DEV and give a false PASS. Therefore: `--with-e2e` given → refuse before creating anything («`--with-e2e` is
   not allowed with `--worktree`: the DEV is shared. Verify on DEV afterwards, from the main tree, on the integrated code»);
   `--no-dev` is **always added** to the driver's flags (say so: the cycle ends at best `NEEDS_VERIFICATION`). Then,
   in the foreground,
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ciclo-worktree.sh" crea .claude/.ai-workflow/spec-<name>.md [--base <ref>]` — it creates or resumes
   `../<repo>-fic-<name>` on branch `fic/<name>` with the main tree's dependencies linked; exit ≠ 0 is a STOP (report
   its message); its last line is `<wt>`. From a linked worktree (the current folder is already a worktree) every
   subcommand refuses with exit 3: report it — launch from the main tree, or without `--worktree`. Then launch the driver **with cwd `<wt>`**, on the worktree's spec:
   `cd <wt> && . "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" "${CLAUDE_PLUGIN_ROOT}/scripts/driver.py" run .claude/.ai-workflow/spec-<name>.md -- <flags> --no-dev`.
   From here `<run-dir>` is `<wt>/.claude/.ai-workflow/spec-<name>.run`; the code-phase lock is the worktree's own.
4. **Follow it** with the Monitor (`timeout_ms: 1800000`, re-armed while the driver runs):
   `until [ -e <run-dir>/driver.log ]; do sleep 1; done; tail -n +1 -f <run-dir>/driver.log`. On each
   `▶ <label> avviata` you may arm a second Monitor on the phase:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/watch-phase.sh" <run-dir> <label>`. Add one line of your own
   only when a phase starts or ends.
5. **The end** is the driver's line `Driver result: <DONE|STOP|WAIT|BUSY|RUNNING> — <reason>` (exit 0 · 1 ·
   3 · 4 · 4; a driver of 1.2.x wrote `Esito driver:` with `OCCUPATO` · `IN CORSO`: the same). It already carries the cause: the `PHASE RESULT` line, the tail of `<label>.stderr` for a
   run-phase exit (4 lock busy · 5 guard not active, never relaunch without it · 6 harness changed, the remedy is
   in the line · 7 chain), the anti-loop, the fix budget. Exit 3 of run-phase (no `claude` binary) is a STOP:
   `CLAUDE_BIN=<path>` or an explicit `--inline` are the user's choice, never yours. `RUNNING` (a
   `log/<label>.running` with no `.exit`): arm the Monitor `watch-phase.sh <run-dir> <label>` on that label; if
   its log has not grown for more than 15 minutes, report it as stuck and ask. **Chains**: the driver follows
   them itself — a `WAIT` that names a ring moves it to that ring, a ring's `DONE` back to the mother (the
   `catena:` events); a final `WAIT` means nothing on the chain can run now: report the ring it names.
6. **Interrupt**: TaskStop the driver and the Monitors, say the sub-session was stopped; re-invoking resumes
   (with `--worktree` again: `crea` resumes the same worktree).
7. **`--worktree`, at the end** (any `Driver result`), **with cwd in the main tree** (the driver ran with cwd `<wt>`,
   and from a linked worktree `riporta` refuses with exit 3): `cd <main tree> && bash "${CLAUDE_PLUGIN_ROOT}/scripts/ciclo-worktree.sh" riporta
   <name>` (spec and run dir back to `.claude/.ai-workflow/`, never the code; a STOP means the main tree's spec changed
   meanwhile: report it). Tell the user: the changes are on branch `fic/<name>` in `<wt>`, **not committed** (the cycle
   never commits); to integrate them, commit in `<wt>` and merge `fic/<name>`, or `git -C <wt> diff | git apply` in the
   main tree (new files: `git -C <wt> add -N .` first); the DEV verification (the declared remote verification, e2e) comes after, from the
   main tree, on the integrated code; to remove it: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ciclo-worktree.sh" rimuovi <name> [--branch]` —
   never delete the folder by hand: its `node_modules` are junctions to the main tree's.

Never read a sub-session's `.jsonl` into this chat.

## Final response (orchestrator)

The cost block comes from a script, never computed by hand (with `--worktree`, run it after step 7):
`. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" "${CLAUDE_PLUGIN_ROOT}/scripts/phase-usage.py" --summary .claude/.ai-workflow/spec-<name>.run`;
copy its output as it is. If `riporta` stopped, give it the worktree's run dir instead (`<wt>/.claude/.ai-workflow/spec-<name>.run`).

```text
Full implementation cycle — spec-<name>.md
Outcome: IMPLEMENTED | NEEDS_VERIFICATION | STOP (<phase>: <reason>)
Cost:            <the block printed by phase-usage.py --summary, as it is>
Phases:          <label → PHASE RESULT line> one per line (driver.log)
Plan:            Plan status <…> · <metric line of the plan changelog>
Review:          Review status <…> · Feature status <…> · Verification <…> · Review rounds <n>/3
Evidence:        <the review's evidence table, as written in the spec>
Artefacts to accept or remove: <paths | none>
Open decisions: <none | list>
Other work in the working tree: <do-not-touch.txt — not touched | none>
Excluded files changed after the review: <EXCLUDED-CHANGED of cycle-state.sh | none>
Full logs: .claude/.ai-workflow/spec-<name>.run/log/
Worktree:        <none | <wt> · branch fic/<name> · integration and removal (step 7)>
No commit made: review the diff (git status / git diff) and commit it yourself.
```

On a STOP say exactly what the user must decide or run, and that re-invoking resumes from the right phase.
