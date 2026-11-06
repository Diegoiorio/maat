# /full-implementation-cycle — reference

Documentation of the cycle that no phase loads: the run directory, inline mode, chains, sub-session
permissions, and at the end the rules that have become code. The phases read only `SKILL.md` and their own
`workers/<fase>.md`; the orchestrator reads `orchestratore.md`. The resumption table is the header of
`cycle-state.sh` (the same one, in Python, in `${CLAUDE_PLUGIN_ROOT}/scripts/driver.py next`).

## Inline mode

- **Inline mode** — **only** when the user passes `--inline` explicitly. The orchestrator runs the
  worker phases itself, one after another, in this session. It works, but the context accumulates — say
  so when it happens. There is no guard and no lock in this mode (they live in `run-phase.sh`), so you
  do its bookkeeping yourself, exactly as it does:
  - before every code phase (review included), close each `log/*.pre-tree` without its
    `.post-tree`: `git -c core.quotePath=false diff --name-only --no-renames <pre> <tree now>` appended
    to `<run-dir>/touched.txt` (sort -u), then `<tree now>` into `.post-tree` — `<tree now>` is
    `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-surface.sh" tree`;
  - around an implement/fix: `tree` into `log/<label>.pre-tree` before, and the same closing after;
  - after each phase: its `PHASE RESULT` line and `state=<State of cycle-state.sh>` into
    `log/<label>.esito`. `cycle-state.sh` reads `.esito` as the phase's record; an implement/fix with no
    `.post-tree` is a STOP, never a review;
  - after each review: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize.sh" --level <level in force> <run-dir>`, its output into
    `log/<label>.finalize`, and if it is missing or exits with anything but 0/1/4, the review's `.esito` is
    `PHASE RESULT review: STOP — finalize non eseguito|fallito` (harness-pt08). Without it, in a run directory
    of the new regime `cycle-state.sh` never gives `DONE`: the `Finalize:` line must carry the fingerprint of
    the current `Reviewed snapshot:`, and only finalize writes it.
  ⚠️ **An environment failure never selects this mode by itself.** `run-phase.sh` exit `3` (no `claude`
  binary found) is a **STOP**: say that the binary was not found and that `CLAUDE_BIN=<path>` or
  `--inline` — a deliberate choice, with the guard and the lock gone — are the two ways out. Falling back
  on its own would silently trade away the two protections that make unattended phases acceptable, at the
  exact moment nobody is looking.

## What this skill adds, and what it does not

It **composes** the two existing skills; it does not restate their rules. Planning rules (lenses,
delta, fresh-eyes gate, `plan-check.sh`) live in `plan-review-cycle`; review rules (snapshot,
required gates, `Feature status`, counters) live in `implementation-review-cycle`. Copying them here
would make them diverge. This skill adds only: the implementation phase, the fix loop, the
orchestration across sub-sessions, resumption, and one final report.

`/plan-review-cycle` and `/implementation-review-cycle` keep working alone, unchanged.
`implementation-review-cycle` says "do NOT fix automatically; recommend a separate fix step": this
skill **is** that separate fix step.

It reads what those skills **write** — `Plan status:`, `Approved basis:`, `Test level:`,
`### Piano di test`, `Review status:`, `Feature status:`, `Verification:`, `Reviewed snapshot:`,
`Reviewed contract:`, `Review rounds: n/3 · post-approval NEEDS_CHANGES: k/1`, the manifest
`Scope:`/`Excluded:` — mostly through `cycle-state.sh`. If one of those formats changes, that script
and this skill must be updated with it. A plan in **format 2** (`Plan format: 2`, defined in
`plan-review-cycle`) is read the same way, plus its blocks and its generated procedure:
`cycle-state.sh` then prints `Plan format: 2` and `Generated: FRESH | STALE | assente` — the state of
`<run-dir>/gen/procedura.txt` against the plan's fingerprint (it never changes `Next:`).

## The run directory

`.claude/.ai-workflow/spec-<name>.run/` — ignored by git through the existing `spec-*` rule, so it is
never review surface, and inside the project, so sub-sessions can write it (they cannot write
outside the project). It holds:

- `input.md` — pasted specification text, when there was no spec file;
- `prompts/<label>.md`, `log/<label>.{jsonl,stderr,exit,running}` — one per phase run;
- `base.txt`, `do-not-touch.txt`, `mixed.txt` — written by the implement worker, read by later ones;
- `touched.txt` — the paths the implement/fix phases changed, **measured** by `run-phase.sh` (tree
  before and after each of those phases, under the lock); `log/<label>.{pre,post}-tree` behind it. A
  phase killed together with its sub-session leaves no lock to reclaim: its `.pre-tree` is closed at
  the feature's next code phase, so other work done in between is over-included (the safe direction);
  a review launched by hand on the spec reads this file too;
- `log/<label>.altri-flussi` — paths changed during the phase that the sub-session **never named** in any
  `tool_use` (`run-phase.sh`, ALTRI FLUSSI): in test-red an out-of-scope one is another flow's work → into
  `do-not-touch.txt`, out of `touched.txt`, an `AVVISO` and no STOP (named, or a log without `result` → STOP); in
  implement/fix it stays in `touched.txt`, only annotated. Prevention, said at S0: «do not change files in this working
  tree during the cycle: to work in parallel use another worktree
  (`git worktree add ../<repo>-lavoro -b <branch> develop`)», or the cycle itself in its own worktree (`--worktree`,
  «Worktree mode» below);
- `log/<label>.esito` — the phase's `PHASE RESULT` line (`ESITO FASE` up to 1.2.x, still read) (from the final `result` event only) and the
  `State` at its end, written by `run-phase.sh`: how `cycle-state.sh` knows an implement or a fix
  finished;
- `log/<label>.result.json` — the phase's **structured outcome** (harness-pt08), written by `run-phase.sh`
  only when the JSON block of the final `result` event is valid for `${CLAUDE_PLUGIN_ROOT}/schemas/phase-result.schema.json`
  (see "Worker mode"). Missing or invalid output → no file, and `.esito` says `STOP — invalid output:
  <errors>` (Italian: `uscita non valida:`) with the worker's own `PHASE RESULT` line kept under `originale=`. **`.esito` is the authority**: when
  the prose and the JSON disagree the more conservative wins — prose `OK` with a JSON that is `STOP`, has
  `deviazioni` (unless all start with `defensive: ` or `difensiva: `) or a `bloccato_su` → `.esito` is `STOP — JSON: …` (prose under `originale=`); prose `STOP`
  stays `STOP`. `cycle-state.sh` counts a phase as `OK` only if both `.esito` and `result.json` say so;
- `log/<label>.finalize` — after every review that exited 0, `${CLAUDE_PLUGIN_ROOT}/scripts/finalize.sh` **signs the final
  state**: it confirms `Feature status: IMPLEMENTED` only if every gate the level requires has
  `evidence/<current key>/<gate>.json` `PASS` (or `SKIPPED`) and every counterproof is red on its assertion
  (`counterproof/<id>.json`, or the review's evidence table when there is no `mutations.json`); otherwise it
  writes `NEEDS_VERIFICATION` with the missing gate. **Verdict = AND** (harness-pt09): a required gate `FAIL` or a
  counterproof that is not red (`rosso_import`, `rosso_raccolta`, `rosso_diverso`, `verde`) is `FAIL` even with the
  review `APPROVED` — finalize writes `Review status: NEEDS_CHANGES`, `Feature status: PLANNED`, `Verification:
  PARTIAL (finalize.sh: …)` and `Finalize: FAIL` (exit 3), and `cycle-state.sh` sends it to `FIX` within the
  budget; a `BLOCKED` gate or a missing result stays `NEEDS_VERIFICATION`. With `--copertura
  log/<label>.result.json` it also joins the review's requirement → test-ID map to the results of VERIFY and
  writes the `Requirement evidence (finalize.sh: …)` table under the `Finalize:` line: an ID with no result leaves
  the requirement «not covered» (Italian: «non coperto»; data, not a verdict). The review writes the verdict; the script signs the state.
  **Fail-closed**: finalize missing, or exiting with anything but 0/1/4 → `.esito` is `STOP — finalize non
  eseguito|fallito`; and in a run directory of the new regime (with `evidence/` or any `*.result.json`, also
  renamed `.result.json.visto`) `cycle-state.sh` gives `DONE` only with a `Finalize: IMPLEMENTED — snapshot
  <x12> — …` line whose fingerprint is that of the **current** `Reviewed snapshot:` and which is not older
  than the last review launched — otherwise `REVIEW`. A review by hand or `--inline` must run finalize itself
  (see "Inline mode"). Old run directories give `DONE` as before;
- `log/<label>.gates` and `evidence/<key>/` — the **gates run by the driver** (harness-pt04):
  `run-phase.sh` runs `${CLAUDE_PLUGIN_ROOT}/scripts/gates.sh` **outside** the sub-session after every implement/fix that
  ended `OK` and before every review, with the level in force and the files of `touched.txt`. Each gate
  (`tests-<module>` with the module's test command, `controlli-<module>`, and at `full` `lint` and `build` of the
  modules that declare them) leaves
  `evidence/<key>/<gate>.json` (esito, comando, exit, durata_s, report, riepilogo, motivo, file) next to
  its runner report; `<key>` is a sha256 of the whole working tree (untracked files included), the
  commands, the interpreter and tool versions, the modules' `chiave` entries (dependencies, generated files),
  `TZ` and `CI`. Same key → reuse, no rerun: the review right after an implement does not run its suites again.
  The gates of `nativo` modules run in parallel with the `wsl` lane. `log/<label>.prompt` is the review's actual prompt: the original plus the
  evidence line;
- `log/<label>.parallelo` — how the review phase ran (harness-pt09): `modo=parallelo controprove=driver|worker
  chiave=<x12>`, or `modo=sequenza — <why>`, plus a `scartato: …` line when the key changed. **Review ∥ VERIFY**:
  `run-phase.sh` computes the tree key (`review-surface.sh tree`, plus the sha256 of `counterproof/mutations.json`
  when the driver runs the counterproofs) and starts, **together**, VERIFY — `gates.sh`, then `counterproof.sh`
  through WSL **only if** `mutations.json` is the list `plan-check.sh gen` generates now from the approved plan
  (`gen/procedura.txt` with the current `Impronta piano:` and the list byte-identical to one regenerated by the
  driver; any other list — format 1, written by the worker in an earlier round, plan changed — keeps the
  counterproofs with the worker, which rewrites it every round as before; output in `log/<label>.counterproof`;
  the background VERIFY writes `vpid=` in the lock's owner, so the lock is not freed while it runs) — and the review
  sub-session, whose prompt ends with `VERIFY IN PARALLELO (driver, run-phase.sh): …`. When both have finished it
  recomputes the key: changed → **both results are discarded** (the spec is put back from
  `log/<label>.spec-pre`, the round's `<id>.json` are deleted — the worker's too —, `.gates`/`.counterproof` become
  `*.scartato`, the `evidence/<key>/` named in `.gates` becomes `<key>.scartato` so `gates.sh` cannot reuse it nor
  `finalize.sh` read it as FRESH, an
  event `fic_scartato` in the log marks where the valid output starts) and they are rerun **in sequence**. The
  sequence is the old one (gates, then the review with `EVIDENZE DEI GATE`) and is also used with
  `FIC_REVIEW_PARALLEL=0`, with a recorded `Review status: APPROVED` (promotion and gate-only paths do not launch
  the reviewer and do not change), and when the key cannot be computed;
- `chiusura.txt` — on a chain's **mother** only: the outcome of the closure phase, written by `run-phase.sh`
  (`Chiusura: IMPLEMENTED — base <b> · tree <t> · gates PASS · e2e <…> · <UTC>` or `NEEDS_VERIFICATION —
  <reason>`); to relaunch a failed closure, rename it `chiusura.txt.visto` (see "Chains");
- `counterproof/` — `mutations.json` and one `<id>.json` result per counterproof, written by
  `${CLAUDE_PLUGIN_ROOT}/scripts/counterproof.sh` (see "Counterproofs"). The `cp-run.sh` files and sidecars left in older
  run directories are history: no new cycle uses them;
- `test-red/` (format 2, harness-pt11) — `rossi.json` (each acceptance test's red on the base with stubs:
  esito, message, position), `stubs.json` (the exported symbols of each new file at the close of `test-red`),
  `tests.txt` (the acceptance test files' hashes, the `tests <fp>` of the `Approved basis`); `log/<label>.scope`
  (the guard's write scope), `log/<label>.gates` and `log/<label>.rossi` (the driver's verification);
- `staging/`, `staging.fp` (S3) — acceptance tests written by a `test-stage` phase while the plan was under its
  final gate, bound to the plan's fingerprint at launch; consumed (`staging.copiato`) or discarded by `test-red`;
- `context-pack.md` — the **context pack**, written only by `${CLAUDE_PLUGIN_ROOT}/scripts/context-pack.sh`: files and symbols
  the spec names (verified: they exist or not), per-file signatures (exports, `.vue` props/emits, FastAPI
  routes, Pydantic models) and the tests that cite them, tests citing the spec's strings and `data-test`,
  DB columns of the named tables (`contesto` of `.claude/maat.json`: «DB schema not declared» (Italian: «schema DB non dichiarato») without it; when
  the schema command fails, its exit code and the first line of its output), a header with date, commit
  and the spec's fingerprint; ≤ ~5k tokens. **Orientation, not authority: the code wins over the pack.**

## Worktree mode (`--worktree`)

For when other sessions work in the main tree during the cycle: their `git add -A` cannot commit the cycle's files
halfway, and the cycle's review does not see their files in its diff. Opt-in; without the flag nothing changes.
`${CLAUDE_PLUGIN_ROOT}/scripts/ciclo-worktree.sh` (test: `ciclo-worktree.test.sh`, fake repo and fake HOME, with a mutation counterproof):

- `crea <spec> [--base <ref>]` — worktree `../<repo>-fic-<name>` on branch `fic/<name>` from `--base` (default the main
  tree's `HEAD`); an existing one is resumed only if it is its own (marker `.claude/.ai-workflow/spec-<name>.worktree`
  inside the worktree, gitignored by the `spec-*` rule), otherwise STOP; a `fic/<name>` branch without its worktree is a
  STOP too. **Before creating anything**, the dependency files (the `file_dipendenze` of the modules in
  `.claude/maat.json`) must be equal between the base and the main working tree, else STOP. It **links**,
  never copies nor installs, the folders of the modules' `collega_nel_worktree` (installed dependencies) of the
  main tree — junctions on Windows, symlinks elsewhere, the same code as
  `corpus/replay.sh` (`${CLAUDE_PLUGIN_ROOT}/scripts/worktree-lib.sh`) —; copies the spec and its run directory (gitignored: the checkout
  does not bring them; on resume the worktree's win); copies the modules' `preparati` (files written by their
  `preparazione`) from the main tree when their guide file is there (the lint and `vitest-classify` need them:
  without them the lint is `BLOCKED`); checks the worktree's WSL
  copy `~/fic-mirror-<hash>` (node_modules seeded in hardlinks from `~/fic-mirror`); prints the path (last line);
- `stato <name>` — where, branch, the cycle's `State`/`Next` (`cycle-state.sh` on the worktree's spec), lock, changed files;
- `riporta <name> [--forza]` — spec and run directory back to the main tree's `.claude/.ai-workflow/`, for
  `cycle-report.py` and the user; never the code. The run directory is **aligned**, not merged (full copy next to it,
  then it replaces the old one). STOP if the main tree's spec or run directory changed after the copy (fingerprints in
  the marker; `--forza` overwrites);
- `rimuovi <name> [--branch] [--forza]` — STOP while a phase of the worktree is alive: code-phase lock held, or
  `<run-dir>/plan.lock` with a live pid (never forced); a `log/<label>.running` without `.exit` (alive, or dead without
  closing) is a STOP unless `--forza`. STOP with uncommitted changes, or with the worktree's spec or run directory not
  brought back to the main tree (`cmp`, `diff -rq`: run `riporta` first) — `--forza` loses them. Then it deletes the
  worktree's WSL copies (lanes included); **unlinks first**, then checks that no link at all is left, registered or not
  (`find -type l`, Windows reparse points with `dir /AL /S`, `find -type l` from WSL; a failing check is a STOP) — one
  left → STOP; then `git worktree remove`; the branch only with `--branch` (`git branch -d`). ⚠️ Measured:
  `git worktree remove`, even without `--force`, **follows a junction** and empties its target: removing without
  unlinking would empty the main tree's real `node_modules`. A symlink tracked by the repository (none today) would
  count as a link left: false positive, STOP.

The cycle runs the worktree's `driver.py` and `run-phase.sh` with cwd in the worktree: the code-phase lock is in the
worktree's git dir (`.git/worktrees/<id>/`) and the WSL copy is the worktree's (`~/fic-mirror-<hash>`), so only the
**local** work of two cycles in two worktrees runs side by side. **The DEV stays shared** (code sync, e2e context): a
second cycle, or an e2e of the declared remote verification (`verifica_remota` in `.claude/maat.json`) from the main tree, could sync different code onto it and give a false PASS.
So `--worktree` forces `--no-dev` (the cycle ends at best `NEEDS_VERIFICATION`) and refuses `--with-e2e`; the DEV
verification is done afterwards, from the main tree, on the integrated code. `driver.py` and `run-phase.sh` do not
change. Integration is the user's: commit in the worktree and merge `fic/<name>`, or `git -C <wt> diff | git apply` in
the main tree.

## S3 · tests on hold

**S3 · tests on hold:** with a format-2 plan, when the plan phase's `▶` line announces its final gate
(fresh eyes / S2), you may launch `<NN>-test-stage` in the background next to it (same steps 1–3, its own
Monitor): it writes the acceptance tests under `<run-dir>/staging/`, takes no lock and never writes the spec.
The `test-red` that follows copies them if the approved plan has the same fingerprint, discards them otherwise.

## Feature paths

Needed by preflight and counterproofs:
- if an `## Implementation review` (`## Review implementazione`) section exists: its manifest (`Scope:` / `Excluded:`);
- before that: `<run-dir>/touched.txt` (measured), plus dirty paths (`git status --porcelain`) that
  match a file or a directory prefix named by the plan, plus every path the implementer reported
  under `Touched files:` (`File toccati:`).

A path in `touched.txt` or reported by the implementer is never excluded by you: exclusions are the
review's decision, with its rules, and the review never excludes a `touched.txt` path. Every other
dirty path is **another flow's work**.

## Chains (harness-pt12)

A spec too large for one plan becomes a **chain**: the plan phase measures the skeleton, `spec-author`
(mode `split`) proposes the rings, `plan-check.sh split` checks that every `RF`/`CA` of the mother lands in
one and only one child, and the user approves the cut once. The **mother** then carries `Children:
spec-<nome>-1-…, spec-<nome>-2-…`; each **ring** (child) is a spec with its own run directory, plan, gates,
review and `finalize.sh` — no ring closes without its `Finalize: IMPLEMENTED`. The rules are code in
`cycle-state.sh` (rows C1–C4) and `plan-check.sh basis`; here is what they mean for you.

- **On the mother** `cycle-state.sh` says `WAIT — catena: ring k/n (…) not closed` (Italian: `… anello k/n (…) non chiuso`) while a ring is open: run
  the cycle on that ring's spec. When all rings are closed it says `CHIUSURA`: launch the closure phase on
  the **mother's** run directory, label `NN-chiusura`, prompt `/maat:full-implementation-cycle --worker=chiusura
  <mother>`. `run-phase.sh` does it under the code lock: `touched.txt` = union of the rings', `base.txt` = the
  first ring's, gates at level `full` on the final tree; a sub-session only if the rings have
  `[e2e-locator:` lines. It writes `<run-dir>/chiusura.txt`; the mother is `DONE` only with `Chiusura:
  IMPLEMENTED` on the current code.
- **On ring k>1**: `PLAN` becomes `WAIT` until ring k−1's plan is `APPROVED` (L6: plans run ahead of the
  code); `IMPLEMENT` becomes `WAIT` until ring k−1 is closed. At the start of the ring (no code phase yet) the
  working tree must be ring k−1's last `.post-tree`: otherwise `STOP` (human edits the ring would take as its
  own); `run-phase.sh` refuses the launch with exit 7 too.
- **Same working tree** (the commit stays the user's): `cycle-state.sh` prints, for ring k>1, `Anelli
  precedenti:` — the files of the previous rings' `touched.txt`: **same chain, previous ring**, never another
  flow's work, never mixed, and they never trigger `completion`; `Base anello:` — ring k−1's `.post-tree`,
  never HEAD; `Diff anello:` — the paths changed since that base. Before the ring's review `run-phase.sh`
  writes `log/<label>.anello.diff` (from `Base anello` to the current tree, on the ring's `touched.txt`) and
  appends it to the review prompt: that diff, not one against HEAD, is what the reviewer reads.
- **A ring is closed** only with `Review status: APPROVED`, `Feature status: IMPLEMENTED` and a fresh
  `Finalize: IMPLEMENTED` (on the current `Reviewed snapshot`, not older than the last review) —
  `plan-check.sh closed <spec>`, the one criterion used everywhere; no legacy fallback.
- **Basis of a ring**: `madre`, `prec` and, once ring k−1 is closed, `interfaccia` join `spec` and `plan`
  (`plan-check.sh basis`). The ring's plan becomes `STALE` — row 6, re-open it with a delta round — when the
  mother changes, ring k−1's plan is re-opened, its real interface differs, or any file the plan cites is in
  ring k−1's `touched.txt` while the plan was approved before k−1 closed.

## The size of the cycle (1.7.0)

Two sizes: **`piccola`** (small: a lighter flow) and **`piena`** (full: the flow of 1.6, unchanged). A script decides,
never a model: `plan-check.sh taglia <spec> [--diff <file>] [--override full|light]` prints one fact per line, the
`Fatti:` line and last `Taglia: piccola | piena — <reasons>`. `piccola` only if **every** fact is under its threshold
(defaults; a project changes them in `piano.taglia.soglie` of `.claude/maat.json`):

| fact | measured on | small if |
|---|---|---|
| F1 source files | `Touched files` minus the test files of the test table | ≤ 3 |
| F2 new source files | `` `path` (new) `` among F1 | ≤ 1 |
| F3 steps · F4 requirements · F5 tests | rows of `Steps` · the **maximum** of the traceability ids and of the ids in the spec above the plan · rows of `Test plan` | ≤ 6 · ≤ 12 · ≤ 10 |
| F6 plan lines | as `skeleton` | ≤ 250 |
| F7 critical surfaces · F8 api-contract | declared, or detected by `piano.superfici_critiche` on a path | none |
| F9 migrations · F10 destructive words · F11 security words | `piano.migrazioni` on a path · `DESTR` · a fixed list plus `piano.taglia.parole_sicurezza` (spec, plan, diff) | none |
| F12 deleted files · F13 new public symbols (with `--diff`) | `deleted file mode` · Python def/class, JS/TS export, Go capitalised names at top level | none · ≤ 2 |
| F14 size request | the optional plan line `Size request: full — <reason>` | absent |

A fact that cannot be measured (format 1, a missing section, `maat.json` invalid, a diff unreadable, a language with
no symbol rule) is `piena`. `shared-logic` and `import` declared alone do not make it `piena`. The model can only ask
for more weight (`Size request: full`, any other value is a `lint` `VIOLAZIONE`).

**When.** T1 in the plan phase (`plan-review-cycle`, after `route`): `piccola` → one round of
`spec-plan-reviewer-light`, `plan-check.sh e1` on its reply (a blocker, more than 2 major, a partial reply → the full
branch from Step 2; `STOP_HUMAN_DECISION_REQUIRED` stays a stop), the verified majors applied without a second round;
the metric line ends with `taglia=piccola|piena`. T2 in `driver.py run` on the approved plan: a plan approved small
whose facts are above → **E2**, the plan phase again with `--full` and the line `RIAPERTURA (driver): …` (the
re-opening). T3 after every implement/fix, with `--diff` of the `touched.txt` paths: a path outside the plan or a fact
above → **E3**. After every review: `.gates` not green or a required gate `NOT RUN` → **E4**; `NEEDS_CHANGES` → **E5**.

**What changes with `piccola`.** One plan-review round; the implement in one lane (`FIC_LANES=0`); one code-review
round (the full `implementation-review-cycle`, never `light.md`, with the line `TAGLIA (driver): piccola`); a `FIX`
without an escalation is a STOP. Gates, the level of the tests (`--tests` or `std`), test-red, the counterproofs and
`finalize.sh` do not change: `IMPLEMENTED` needs the same proofs.

**`<run-dir>/taglia.txt`**: append-only, one line per decision (`<utc> · <moment> · Taglia: … · fatti F1=… …` or
`<utc> · <moment> · Escalation: piccola → piena — <cause>`); from `piena` it never goes back. Absent = `piena`: a
cycle started before 1.7 goes on in the full flow (its plan phases with `--full`). The driver prints the same lines
(`driver: Taglia: …`, `driver: Escalation: …`); `cycle-report.py` prints `Size: <size> (<reason> · escalation: <n>)`.
**Overrides:** `--full` (always `piena`), `--light` (`piccola` above the numeric thresholds F1–F6 and F13, never
above F7–F12, F14 or a file outside the plan); both together: usage error before any phase. `piano.taglia.automatica:
false` turns the automatic size off (`piena` unless `--light`); a `maat.json` with `piano.taglia` declares `"harness":
">=1.7"` (S11). Tests: `plan-check.test.sh` (1.7.0 section), `driver.test.sh` §13, `maat-config.test.sh`.

## Termination

No counter of this skill's own: the review's counters (rounds, post-approval budget, recurrence) are
written in its section and bound the loop across invocations. STOP also on a deviation from the
plan (not on purely defensive ones, `defensive: `: recorded, judged by the review), a migration to apply, `NEEDS HUMAN DECISION` from either skill, and a `NEEDS_VERIFICATION`
obtained in this invocation, whatever its cause (a later invocation makes one promotion attempt:
`cycle-state.sh` row 12) — a `BLOCKED` environment gate (tunnel, WSL timeout), `NOT RUN (--no-dev)`,
`NOT RUN (file misto)`, an approval made stale by the freshness check, gate artefacts the user must
accept. Code is not "fixed" for an environment problem: report the cause and the command.

## Sub-session permissions — declared, not hidden

Sub-sessions run in `bypassPermissions` (in `-p` mode only bypass lets them write the spec under
`.claude/`, measured) with two layers: a deny list by prefix, which a `wsl -- bash -lc '…'` wrapper
defeats; and **`guard.py`**, a PreToolUse hook that reads the whole command inside the wrappers and
denies a closed list — anything naming PROD (hosts, IPs, public names, release scripts: the `guardia` of
`.claude/maat.json`), direct `ssh`/`scp`/`sftp`/`rsync` (remote access goes through the project's declared
helpers and the remote verification), database writes through the project's helpers, git that changes state, docker, psql, installs, `rm -rf`; in the
`plan`/`review` phases also Edit/Write outside `.claude/.ai-workflow/`; in the `plan` phase also a full
suite (vitest, pytest, `run_tests.sh` with no file or selector). Next to it, a **`Stop` hook**
(`${CLAUDE_PLUGIN_ROOT}/scripts/stop-hook.py`) denies the end of a turn whose last message has no `PHASE RESULT` line, or while
a background job the transcript shows is not collected; with `stop_hook_active` it always lets the turn
end, so it cannot loop, and it fails open. It is not a sandbox (none
exists on native Windows): what it covers and what stays open is written in the docstring of
`guard.py`. The hook itself fails open; `run-phase.sh` refuses to launch when its self-test does not
get a denial (exit 5). Code phases (`implement`, `review`, `fix`) run **one at a time** across all
features, under a lock in `.git` (exit 4); plan phases of **different** specs run in parallel, two plan
phases on the **same** spec do not (`<run-dir>/plan.lock`, exit 4 with its owner). `/implementation-review-cycle`
and an e2e of the remote verification launched by hand ask `run-phase.sh --lock-status` and stop while a code phase
runs. The lock does not attribute code: `touched.txt` does, measured around each implement/fix phase.
Tests: `guard.test.sh`, `run-phase.test.sh`, `cycle-state.test.sh`, `${CLAUDE_PLUGIN_ROOT}/scripts/gates.test.sh`,
`${CLAUDE_PLUGIN_ROOT}/scripts/stop-hook.test.sh`, `${CLAUDE_PLUGIN_ROOT}/scripts/finalize.test.sh`, `${CLAUDE_PLUGIN_ROOT}/scripts/blocks-independent.test.sh`.

## Rules in code (harness-pt14)

The rules that left the prose of `full-implementation-cycle`, `plan-review-cycle` and `implementation-review-cycle`
when orchestration moved to the driver. Each one is applied by the script named and watched by the test named;
no rule that was not already code has been removed: it stayed in prose, in the file loaded by the phase that
uses it (`workers/<fase>.md`, `autore.md`, `revisori.md`, `formato-1.md`, `freschezza.md`,
`gate-manuali.md`, `light.md`, `prompt-revisore.md`, `workers/controprove.md`) or above.

| Rule (where it was) | Script that applies it | Test |
|---|---|---|
| Choice of the next phase, resumption table (FIC «Resumption», step 3) | `cycle-state.sh` / `driver.py next` | `cycle-state.test.sh` (on the driver, the only engine since 1.6.0), `tools/esempi-equiv.test.sh` (the expected outputs) |
| Anti-loop: same phase and same `State:` → STOP (FIC «Resumption») | `driver.py run` | `driver.test.sh` §4, counterproof §6 |
| `PHASE RESULT … STOP` (or `ESITO FASE … STOP`) → STOP; run-phase exits 4/5/6/7 as STOP/WAIT (FIC step 5) | `driver.py run` | `driver.test.sh` §4 |
| `NEEDS_VERIFICATION` obtained in this invocation → STOP (FIC «Resumption», «Termination») | `driver.py run` | `driver.test.sh` §4 |
| Phase still running (`.running` without `.exit`) → no launch (FIC step 2) | `driver.py run` (exit 4) | `driver.test.sh` §4 |
| Numbered labels, `--worker=<fase>` phase prompt, forwarded flags (FIC step 4) | `driver.py run` | `driver.test.sh` §4 |
| Context pack before each phase (FIC step 4.0) | `driver.py run` → `context-pack.sh` | `driver.test.sh` §4, `context-pack.test.sh` |
| Chain: on a mother in WAIT, work on the ring it names; a closed ring leads back to the mother (FIC «Chains», «On the mother») | `driver.py run` | `driver.test.sh` §4 |
| One engine (1.6.0): `FIC_DRIVER` set → one `AVVISO`, nothing else changes; `FIC_CYCLE_STATE` (tests only) → `run` takes Next/State from that script | `driver.py run` | `driver.test.sh` §4 |
| Phase budget per invocation | `driver.py run --max-fasi` | `driver.test.sh` §4 |
| The size of the cycle (1.7.0): facts F1–F14 with thresholds, fail-closed to `piena`, `--override`, `piano.taglia` («The size of the cycle») | `plan-check.sh taglia` | `plan-check.test.sh` (1.7.0 section, a counterproof per rule) |
| One round of the small plan review and its escalation E1 (a blocker, more than 2 major, a partial reply) | `plan-check.sh e1` | `plan-check.test.sh` |
| `Size request:` only `full` (the model may only ask for more weight, R3) | `plan-check.sh lint` | `plan-check.test.sh` |
| T2 on the approved plan and the reopening E2; T3 after implement/fix (E3); gates and review (E4, E5); `taglia.txt` append-only and one-way; one lane; no FIX with the small size; `--full` with `--light` = usage | `driver.py run` (`taglia_passo`) | `driver.test.sh` §13 |
| A file declared new in a folder that does not exist yet (T3 of the benchmark) | `plan-check.sh lint2` (`path_ok`) | `plan-check.test.sh`, `guard.test.sh` (scope), `test-review-surface.sh` (single files of a new folder) |
| `piano.taglia` in `maat.json` needs `"harness": ">=1.7"` (S11) | `maat-config.py valida` | `maat-config.test.sh` |
| Fix budget (`n<3`, `k<1`) (FIC «Worker fix») | `cycle-state.sh` row 11b | `cycle-state.test.sh` |
| Structured outcome: JSON valid for the schema, deviazioni/bloccato_su → STOP, the more conservative of prose and JSON wins (FIC «Worker mode», «Run directory») | `run-phase.sh` + `driver.py valida`; `cycle-state.sh` 7s/11s | `run-phase.test.sh` 6b, `driver.test.sh` §2, counterproof §6 |
| Deviations all `defensive: ` (`difensiva: `) (purely defensive, no effect on the plan's cases) → no STOP: a line in `log/deviazioni-difensive.txt`, `AVVISO` in `.esito`, a note in the plan changelog (outside the fingerprint), the list passed to the review (a non-defensive one = major); even one without the prefix → STOP (FIC «Hard rules») | `run-phase.sh` (`difensive`, line `DEVIAZIONI DIFENSIVE`) + `driver.py`; `cycle-state.sh` 7s/11s | `run-phase.test.sh` 6b-bis, `driver.test.sh` §2, `cycle-state.test.sh` |
| Attribution (`touched.txt`, `.pre/.post-tree`) and STOP if not measured (FIC «Run directory», «Resumption») | `run-phase.sh`, `cycle-state.sh` row 7 | `run-phase.test.sh` §5, `cycle-state.test.sh` |
| Touched file among the excluded ones → STOP (FIC «Resumption») | `cycle-state.sh` 10b | `cycle-state.test.sh` |
| Level suites run outside the sub-session, evidence by key (FIC «Run directory», IRC Step 2.5) | `run-phase.sh` → `gates.sh` (`--verify`) | `gates.test.sh`, `run-phase.test.sh` |
| Review ∥ VERIFY, discard on a changed key, driver counterproofs only on a coherent `gen` list (FIC «Run directory», «Worker review», IRC Step 2.5) | `run-phase.sh` | `run-phase.test.sh` §8, §8b-8d |
| Signing of the final state, verdict = AND, a fresh `Finalize:` for DONE (FIC «Run directory», IRC Step 3) | `finalize.sh`, `cycle-state.sh` 13f | `finalize.test.sh`, `cycle-state.test.sh` |
| Check of the test-red reds and acceptance tests unchanged after implement/fix; a test file in a block's `scrive:` = prescribed change: acceptance functions unchanged (ast) or not checkable → OK with `AVVISO` and `tests` fingerprint re-recorded, function changed → STOP (FIC «Worker test-red») | `run-phase.sh` (`verify_red`, `tests_guard`), `plan-check.sh rossi` | `run-phase.test.sh` §10, `plan-check.test.sh` |
| Lanes: block independence, after-the-fact check, merged lists, PHASE RESULT line derived from the lane's JSON if missing (FIC «Worker implement») | `blocks-independent.py`, `run-phase.sh` (`launch_lanes`), decision in `driver.py` | `blocks-independent.test.sh`, `run-phase.test.sh` §11, `driver.test.sh` §7 |
| Implementer blocks in format 2 (FIC «Implement, in 2–4 blocks»): lotti with estimated context under the ceiling | `driver.py` (`lotti`, line `LOTTI`) | `driver.test.sh` §7 |
| Chains: C1–C4, WAIT/STOP, ring diff, closure (FIC «Chains») | `cycle-state.sh`, `run-phase.sh` (exit 7, `ring_prompt`, closure) | `cycle-state.test.sh`, `run-phase.test.sh` §9 |
| Code lock and per-spec lock (FIC «Sub-session permissions») | `run-phase.sh` | `run-phase.test.sh` §2-3 |
| Harness fingerprint (FIC step 5, exit 6) | `run-phase.sh`, `cycle-state.sh` row 0 | `run-phase.test.sh` §7, `cycle-state.test.sh` |
| Sub-session prohibitions: PROD, ssh/rsync, state-changing git, docker, psql, installs (child-rules) | `guard.py` (PreToolUse hook) | `guard.test.sh` |
| No end of turn without `PHASE RESULT` or with uncollected jobs (child-rules) | `stop-hook.py` | `stop-hook.test.sh` |
| Structure of a format-2 plan: traceability ↔ tests ↔ steps ↔ files, blocks, test table, removed strings still asserted, presence/absence by position (PRC «Plan format 2», «Lint») | `plan-check.sh lint2` | `plan-check.test.sh` |
| EXISTING non-regression tests outside the table of the Test plan (Piano di test): a row with the assertion «stays green» (or «remains green», «keeps passing»; Italian «resta verde», «rimane verde», «continua a passare») → VIOLAZIONE; they go in the note under the table, traceability «not verifiable by test (invariance, …)» (Italian «non verificabile a test (invarianza, …)») (PRC `autore.md`, harness-pt15) | `plan-check.sh lint2` (`INVARIANZA`) | `plan-check.test.sh` |
| Reds possible on the base (1.6.0, block Z): a Python call in a row's backticks that does not fit the signature of an EXISTING function of the Touched files (stubs go only into new files) and a red that does not name the `TypeError` → VIOLAZIONE; a Python test id `file.py::Class.method` → VIOLAZIONE with the `::` form; a row in a module with `report: nessuno` → AVVISO (test-red would be BLOCKED) | `plan-check.sh lint2` (`CONTROLLO-FIRMA-LINT2`, `CONTROLLO-ID-PY-LINT2`) | `plan-check.test.sh` |
| Position of a red in the test file: the pytest `file:line` line or, for another runner's JUnit (unittest), the deepest traceback frame `File "…/<test file>", line N` | `plan-check.sh rossi` (`POSIZIONE-TRACEBACK`) | `plan-check.test.sh` |
| GENERATED files regenerable by implement/fix without a deviation, with their command (FIC «Worker implement», «Worker fix», harness-pt15); a generated file regenerated by a single lane that declares it is that lane's | `generati` of `.claude/maat.json` (`maat-config.py generati [--verifica]`, S9), `blocks-independent.py --posteriori` | `maat-config.test.sh` §8b, `blocks-independent.test.sh` |
| Light/full path from the files (path table, thresholds) (PRC «L5») | `plan-check.sh route` | `plan-check.test.sh` |
| S2 decision: clean on the current fingerprint, rejected findings (PRC «Review ≤4 rounds») | `plan-check.sh s2` | `plan-check.test.sh` |
| Size ceilings (≤15 steps, ≤40 files, ≤400 lines) and refused cut (PRC «Size») | `plan-check.sh skeleton` | `plan-check.test.sh` |
| Check of the cut into rings (PRC «Size», point 3) | `plan-check.sh split` | `plan-check.test.sh` |
| Computed delta, empty or whole = error, `xref:` lines (PRC «Step 2-bis») | `plan-check.sh delta` | `plan-check.test.sh` |
| Basis fields of a ring (madre, prec, interfaccia, L6 touched) and `tests` (PRC «Size» point 4, Step 3) | `plan-check.sh basis` | `plan-check.test.sh` |
| L6 pipeline: ring k+1's plan waits for ring k's plan (PRC «Size» point 4) | `cycle-state.sh` C3 | `cycle-state.test.sh` |
| Reading the plan contract (IRC Step 1) | `plan-check.sh contract` | `plan-check.test.sh` |
| Eligibility for the gate-only path, EXCLUDED-CHANGED (IRC «Freshness») | `review-surface.sh check` | `test-review-surface.sh` |
| Classification of lint outside the module's `radice` (IRC Step 2.5) | `test-fast.sh --lint --base` | `test-fast.test.sh` |
| Execution and outcomes of the counterproofs (FIC «Counterproofs») | `counterproof.sh` | `counterproof.test.sh` |
| Lines loaded per phase ≤300 (pt14 goal) | `driver.py righe` | `driver.test.sh` §8 |
