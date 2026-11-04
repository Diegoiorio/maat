# Maat — plugin overview

Maat — Multi-Agent Assurance Toolkit: a cycle of plan, implementation, review and sign-off, with evidence,
measurements and a guard. Version in `.claude-plugin/plugin.json`; what's new in `CHANGELOG.md` at the repo root.

Installation, from the main folder of the project:

```bash
claude plugin marketplace add https://github.com/Diegoiorio/maat.git#v1.6.0 --scope project
claude plugin install maat@maat --scope project
```

**Configuration, usage, updating and platforms:** in the [repo README](../../README.md). This page only lists what
the plugin contains.

| folder | contents |
|---|---|
| `skills/` | `/maat:full-implementation-cycle`, `/maat:plan-review-cycle`, `/maat:plan-review-cycle-light`, `/maat:implementation-review-cycle`, `/maat:setup` |
| `agents/` | `spec-author`, `spec-plan-reviewer`, `spec-plan-reviewer-light`, `acceptance-test-writer`, `plan-implementer`, `implementation-reviewer` (with the `maat:` prefix) |
| `scripts/` | driver, phases, gates, sign-off, guard, WSL copy, counterproofs, `maat.json` reader, doctor; each script has its own `*.test.sh` suite next to it |
| `hooks/` | the session guard (`PreToolUse` on Bash and PowerShell) and the `SessionStart` hook that loads the command-description rule (`docs/descrizione-comandi.md`) into every session |
| `schemas/` | schema of `.claude/maat.json` and of the phase outcome |
| `profiles/` | ready-made modules for common stacks, used by `/maat:setup` |
| `examples/` | two complete `maat.json` files: `nuxt-fastapi` (Nuxt + FastAPI, with WSL) and `bash-node` (bash and Node, no tests) |
| `docs/` | writing rules for command descriptions |
| `assets/` | logo and icons (single source: `assets/genera.py`) |

Inside a skill the plugin root is `${CLAUDE_PLUGIN_ROOT}`; in scripts it is `MAAT_ROOT`. The plugin never receives
project files: everything that depends on the project lives in the project's `.claude/maat.json`.

Read-only diagnostics: `bash <plugin root>/scripts/maat-doctor.sh` (`--piattaforma` prints `windows-wsl`,
`windows-senza-wsl` or `altro`; `--prova-test` also runs one test per module and so is no longer read-only).

Flow guide: the repo's `docs/GUIDA-FLUSSI.html`. Plugin tests: the repo's `docs/TESTING-harness.md`.
