---
name: full-implementation-cycle
description: "Runs the whole chain autonomously and in order — /plan-review-cycle until the plan is APPROVED, then implements it with the plan-implementer agent, then /implementation-review-cycle, fixing blocker/major findings and re-reviewing within the review's own budget. The deterministic driver (the plugin's scripts/driver.py) decides and launches each phase as a separate headless Claude sub-session with an empty context, so this chat only receives short progress lines. Accepts a spec file or pasted specification text. Resumable: re-invoking it continues from the right phase. Does not commit. The two underlying skills stay independently callable."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, BashOutput, Task, Skill, Monitor, TaskStop
argument-hint: "<path to spec-<name>.md, or pasted specification text> [--tests=min|std|full] [--light] [--no-dev] [--with-e2e] [--base=<ref>] [--worktree] [--inline]"
---

# Full Implementation Cycle

Radice del plugin: `${CLAUDE_PLUGIN_ROOT}`. Nei file di questa skill che leggi con Read, `${CLAUDE_PLUGIN_ROOT}` vale questo percorso: sostituiscilo prima di eseguire un comando.

One feature, in order: **plan** (`/plan-review-cycle`, or `-light`) → **test-red** (format-2 plans) →
**implement** (`plan-implementer`) → **review** (`/implementation-review-cycle`) → **fix → review** while the
review says `NEEDS_CHANGES` and its budget allows. The **driver** `${CLAUDE_PLUGIN_ROOT}/scripts/driver.py` chooses and launches
every phase; the rules it applies are code, listed with their tests in `riferimento.md` («Rules in code»).

$ARGUMENTS

## Which mode you are in

- `$ARGUMENTS` starts with `--worker=<fase> <name>` → **worker**: read
  `${CLAUDE_PLUGIN_ROOT}/skills/full-implementation-cycle/workers/<fase>.md`, do only that phase («Worker contract» below), stop.
- `--inline` given explicitly → read «Inline mode» in `riferimento.md` (no guard, no lock: say so).
- Otherwise → **orchestrator**: read `${CLAUDE_PLUGIN_ROOT}/skills/full-implementation-cycle/orchestratore.md` and follow it.

## Hard rules

- No `git commit`, `push`, branch, `stash`: the changes stay in the working tree for the user.
- Never write the spec's plan or review section yourself; never apply `minor`/`nit` findings.
- Never pass `--light` to the implementation review. A deviation from the approved plan is a human STOP, except
  a **purely defensive** one (a robustness branch, a fallback for a case the plan or the schema exclude, an
  internal helper — no effect on any case the plan foresees: behaviour, API contract, expected visible string,
  permissions, data written): declared as `difensiva: <file:riga> — <cosa fa> — <perché non tocca i casi
  previsti>` it does not stop the cycle; `run-phase.sh` records it and the next code review judges it. In doubt it
  is not defensive.

## Flags

Forwarded after `--` to every phase: `--tests` and `--no-dev` (with `--no-dev` the cycle stops at
`NEEDS_VERIFICATION` — say so at the start); `--light` selects `plan-review-cycle-light` for the plan phase only;
`--with-e2e` and `--base=<ref>` reach the review. The level in force: `--tests`, else the plan's `Test level:`.
`--worktree` is the orchestrator's, never forwarded: the cycle runs in its own worktree `../<repo>-fic-<name>` (branch
`fic/<name>`, made by `${CLAUDE_PLUGIN_ROOT}/scripts/ciclo-worktree.sh`, not by you); the DEV stays shared, so it forces `--no-dev` and
refuses `--with-e2e` (DEV checks later, from the main tree) — `orchestratore.md`, steps 3 and 7.

## Worker contract

Nobody can answer you: a needed decision is a STOP. Write a `▶ ` line (one line, in the language of `lingua` in `.claude/maat.json`, default English) at each milestone.
The last line is `ESITO FASE <fase>: OK — <summary>` or `ESITO FASE <fase>: STOP — <reason>`, then, in the same
message, one fenced `json` block valid for `${CLAUDE_PLUGIN_ROOT}/schemas/phase-result.schema.json`:

```json
{"fase": "<plan|test-red|test-stage|implement|review|fix|probe>", "esito": "OK", "motivo": "<the ESITO summary>",
 "deviazioni": [], "bloccato_su": "nessuno", "file": ["<path>"],
 "gate_interni": [{"comando": "<command>", "esito": "PASS", "dettaglio": "<last line>"}],
 "finding": [{"severita": "major", "file": "<path>", "riga": 12, "testo": "<claim>"}]}
```

Every deviation from the plan goes in `deviazioni` («adapted», «minor» and «equivalent» ones too); a purely
defensive one starts with `difensiva: ` (Hard rules). A skill you
invoke with the Skill tool: its final response and its «stop» are an intermediate report, its prohibitions
scope its own steps, and its verdict is read from the status lines it wrote in the spec, never from its prose.
**probe** (`--worker=probe <name>`): changes nothing; `▶` lines with whether the spec exists, its status lines
and the `Next:` of `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cycle-state.sh" <spec>`; end `ESITO FASE probe: OK — <next phase>`.

