---
name: setup
description: Guided setup of Maat in a project (/maat:setup). Detects the stack read-only, proposes modules and profiles, asks only what cannot be inferred (production, release, wrappers, remote verification, paths not to touch), writes .claude/maat.json after confirmation, tests the guard and runs maat-doctor.sh.
allowed-tools: Read, Write, Glob, Grep, Bash
argument-hint: "(no arguments: run it from the project root)"
---

# /maat:setup

Radice del plugin: `${CLAUDE_PLUGIN_ROOT}`. Nei file di questa skill che leggi con Read, `${CLAUDE_PLUGIN_ROOT}` vale questo percorso: sostituiscilo prima di eseguire un comando.

Prima di ogni comando Bash o PowerShell, scrivi `description` secondo `${CLAUDE_PLUGIN_ROOT}/docs/descrizione-comandi.md`.

Runs in the **main session**, with the user. Goal (R5): after the two install commands, a valid
`.claude/maat.json` and `maat-doctor.sh` with no MANCA, with no manual edits.

Hard rules:
- **No project file is written before the confirmation** of step 4. Steps 1–3 are read-only
  (Read, Glob, Grep, commands that do not write).
- One question at a time, with a ready proposal: the user confirms or corrects.
- The plugin's Python is found with `python.sh` (`bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" …'`),
  as in the commands below: never a `python` picked at random from the PATH.

## 1. Stack detection (read-only)

Look, from the repo root (exclude `node_modules`, `.venv`, `.git` and generated folders), for:
- `package.json`: dependencies `nuxt`, `vitest`, `jest`, the `test` script;
- `pyproject.toml`, `requirements*.txt`, `pytest.ini`/`conftest.py`, `pytest` among the dependencies;
- `tests/` folders, `*.test.*` and `*.spec.*` files, `*.sh` scripts;
- workspace: `turbo.json`, `pnpm-workspace.yaml`, `workspaces` in a `package.json`. The workspace gives the candidate
  module roots (its apps and packages) and the **workspace folder** (where `node_modules` and the
  `package.json` with the `workspaces` field live), which step 2 uses as `radice_pacchetti`.

Then the platform, which decides the modules' environment:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/maat-doctor.sh --piattaforma
```

It prints `windows-wsl`, `windows-senza-wsl` or `altro` (Windows is decided by `uname`, not by the presence of `wsl.exe`; WSL
absent = `wsl.exe` not in the PATH, or `wsl -- true` failing). Only with `windows-wsl` do the profiles stay as
they are; otherwise step 2 uses `--nativo`.

## 2. Proposal: modules and profiles

The plugin's profiles (`${CLAUDE_PLUGIN_ROOT}/profiles/`):

| Signal found in step 1 | Profile |
|---|---|
| `package.json` with `nuxt` and `vitest` | `nuxt-vitest` |
| Python with `pytest` (`requirements*.txt` or `pyproject.toml`) | `fastapi-pytest` |
| `package.json` with no framework (possibly `*.test.js` with `node --test`) | `node-semplice` |
| no suite (only scripts, JSON, configuration) | `generico-senza-test` |

Build the proposal (one `--radice <module>=<path>` per profile, in the same order):

```bash
bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" "$@"' _ ${CLAUDE_PLUGIN_ROOT}/scripts/maat-config.py componi <profilo>… --radice <modulo>=<percorso>… [--nativo]
```

- **`--nativo`** if step 1 did not give `windows-wsl`: `componi` sets `ambiente: nativo` on every module, removes
  `copia`, sets `piattaforma.copia_wsl: no` and runs in the repo the commands that used to go through the WSL copy. Tell
  the user, with the reason («WSL not reachable» or «platform is not Windows»).
- **Lint with alternatives (`copia.lint` as a list):** with `--nativo` `componi` picks the first alternative without
  `se_esiste`, or whose `se_esiste` file exists in the project (relative to its folder), so run `componi`
  from the project root. In the confirmation table check it yourself: if the module root contains the file of one of the
  profile's `se_esiste` (e.g. `lint-baseline.mjs` of `nuxt-vitest`) and the proposed lint is not that
  alternative's, propose to the user the command of that alternative (without `{cache?…}`).
- `componi` prints the JSON and writes nothing.

Show the **confirmation table**, one row per module:

| Module | Root | radice_pacchetti | Profile | Environment | Test command |
|---|---|---|---|---|---|

- **`radice_pacchetti`:** `componi` sets it equal to `radice`. Ask for it for each module, proposing the workspace
  folder found in step 1 (e.g. `frontend` for the module `frontend/apps/web`); with no workspace it stays `radice`.
- **Environment:** `wsl` only if step 1 gave `windows-wsl` and the profile asks for it; otherwise `nativo`, with
  `piattaforma.copia_wsl: no`.
- The user confirms or corrects (names, roots, profiles, commands). A correction is applied to the in-memory JSON and the
  table is shown again.

## 3. Questions only about what cannot be inferred

One at a time, each with «none» as an accepted answer:

1. **Production hosts and domains.** From the same answer write:
   - in `guardia.produzione` one regex per entry, with escaped dots (`www\.example\.com`) and case-insensitive
     (the guard applies it so);
   - in `guardia.sonde` the **literal** hosts (`www.example.com`): they are the probes that test the guard. Every probe
     must match at least one regex, and every host regex must have its probe.
2. **Release scripts** (`guardia.rilascio`): paths relative to the repo, always denied.
3. **Remote access wrappers** (`guardia.involucri`): scripts that wrap ssh or the remote copy, with the
   options to deny, if any (`{script, opzioni_negate}`).
4. **Project suite scripts** (`guardia.suite`): scripts that launch the whole suite (e.g. `run_tests.sh`), with
   the `pytest` or `vitest` selection rules.
5. **Remote verification** (`verifica_remota`): yes/no and the command. Without it, the cycle uses `--no-dev`.
6. **Paths not to touch** (`da_non_toccare`): globs.

## 4. Writing `.claude/maat.json`

- If the file **does not exist**: show the full JSON and ask for confirmation.
- If it **already exists**: write the proposal to a temporary file **outside the repo** and show the diff
  (`git diff --no-index -- .claude/maat.json <temporary file>`); ask for confirmation before overwriting.
- Only after the «yes»: write `.claude/maat.json`, create the work folder (`cartelle.lavoro`, default
  `.claude/.ai-workflow`) if missing, then validate:

```bash
bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && "$FIC_PY" "$@"' _ ${CLAUDE_PLUGIN_ROOT}/scripts/maat-config.py valida
```

A `valida` error is fixed in the file (showing the fix to the user) and validated again: never go on with
an invalid file.

## 5. Testing the guard rules

For **every** host of `guardia.sonde`: the fake command `curl -s https://<host>/` must get **ask** from the session
guard. The test JSON goes in a temporary file **outside the repo**, written with Write (so the host does not appear
in the command, which the real guard would otherwise ask you to confirm):

```json
{"tool_name": "Bash", "tool_input": {"command": "curl -s https://<host>/"}}
```

```bash
bash -c '. "${CLAUDE_PLUGIN_ROOT}/scripts/python.sh" && MAAT_CONFIG="$(pwd -W 2>/dev/null || pwd)/.claude/maat.json" "$FIC_PY" "${CLAUDE_PLUGIN_ROOT}/scripts/guard.py" --universal < "$1"' _ <temporary file>
```

The output must contain `"permissionDecision": "ask"`. A host that passes without ask means a regex that does not
cover it: fix `guardia.produzione` (step 4) and try again.

## 6. `maat-doctor.sh`

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/maat-doctor.sh
```

Read-only. Every MANCA has its remedy after « — »: apply it with the user (or explain it, if it is an install
the user does) and run the doctor again. The ATTENZIONE lines are reported, they do not block. `--prova-test` also runs one test per
module, but leaves read-only mode (cache and coverage): propose it, never run it without the user's yes.

## 7. Summary to paste into `CLAUDE.md`

Five lines, **shown and not written** (the user pastes them, if they want):

```text
Maat <plugin version> — configuration: .claude/maat.json (modules: <names>; guard: <n> production rules).
Read-only diagnosis: bash <plugin root>/scripts/maat-doctor.sh
Plan and review: /maat:plan-review-cycle (or -light) on a spec in <work folder>.
Implementation and sign-off: /maat:full-implementation-cycle <spec>.
Review of an implementation: /maat:implementation-review-cycle <spec>.
```

The version comes from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`.
