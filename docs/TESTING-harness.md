# Harness tests

Applies to the `plugins/maat` plugin of this repo: how to run the suites on Windows and on Linux, the genericity
test and the driver certificate.

## The two roots

| variable | what it is | how it is resolved |
|---|---|---|
| `MAAT_ROOT` | the plugin root (`scripts/`, `skills/`, `agents/`, `schemas/`) | `MAAT_ROOT` from the environment, otherwise two levels above `scripts/lib/maat-paths.sh`; it must contain `.claude-plugin/plugin.json`, otherwise exit 4 |
| `PROJECT_ROOT` | the root of the project the cycle works on | `FIC_REPO`, otherwise `git rev-parse --show-toplevel` from the **working directory** (never from the script's location); outside a git repo: clear error, exit 4 |
| `MAAT_SCRIPTS`, `MAAT_SKILLS`, `MAAT_AGENTS`, `MAAT_SCHEMAS` | under `MAAT_ROOT` | — |
| `MAAT_WORK` | the project's working folder | `PROJECT_ROOT/<cartelle.lavoro>` from `.claude/maat.json` (default `.claude/.ai-workflow`) |

There is a single resolver: `scripts/lib/maat-paths.sh` (bash, sourced with `.`) and `scripts/maat_paths.py` (Python,
same rules). Run directly, each prints the variables one per line, in the form `NAME=value`:

```bash
cd <project> && bash <plugin>/scripts/lib/maat-paths.sh
```

The lock of the code phases does **not** use `PROJECT_ROOT`: `run-phase.sh` computes it with
`git rev-parse --absolute-git-dir` from the working directory (in a linked worktree it is the worktree's).
`FIC_LOCK` overrides it.

## Override environment variables

The names are the same as before; only the default changes.

| group | variables | default |
|---|---|---|
| harness root | `FIC_GATES_HARNESS` (gates.sh, finalize.sh), `CONTEXT_PACK_HARNESS`, `HARNESS_MERGE_HARNESS`, `FIC_DRIVER_ROOT` | `MAAT_ROOT` |
| repository to read | `FIC_GATES_ROOT`, `CONTEXT_PACK_ROOT` | `PROJECT_ROOT` |
| plugin in the subsession | `MAAT_PLUGIN_DIR` | unset: no `--plugin-dir` (the plugin is enabled in the project); `replay.sh` always sets it |
| repo and lock | `FIC_REPO`, `FIC_LOCK` | toplevel of the working directory · git dir of the working directory |
| cycle components | `FIC_RUN_PHASE`, `FIC_CONTEXT_PACK`, `FIC_GATES`, `FIC_FINALIZE`, `FIC_DRIVER_PY`, `FIC_DRIVER_CERT`, … | the plugin's scripts |
| other | `PLAN_CHECK_ROOT`, `CLAUDE_BIN`, `FIC_PYTHON`, `MAAT_CONFIG` | — |

Under an overridden harness root the plugin structure applies: a mutated copy of the plugin (test counterproofs) is
passed whole, not just one script.

## How to run the suites from the plugin

Each suite creates its own synthetic repos in a temporary folder and touches neither the plugin repo nor a real
project. From Git Bash:

```bash
bash plugins/maat/scripts/<name>.test.sh
```

- Short: `maat-paths`, `maat-config`, `gates`, `finalize`, `ciclo-worktree`, `context-pack`, `cycle-report`,
  `harness-merge`, `guard`, `stop-hook`, `session-start`, `phase-usage`, `blocks-independent`, `phase-events`,
  `test-review-surface.sh`, `plan-check`,
  `senza-wsl` (pk08: Windows without WSL, PATH without `wsl`/`wsl.exe`; about 5 minutes, two `run-phase.sh` phases),
  `spazi` (pk08: plugin, project, run dir and worktree with spaces and «à»; about 5 minutes on Windows, 1 on Linux;
  also on Linux, from the clone in WSL with `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin FIC_WT_WSL=0`).
- Long (run them together, in the background): `cycle-state`, `run-phase`, `driver` (section 9 of `driver.test.sh`
  runs all of `cycle-state.test.sh`; `DRIVER_TEST_RAPIDO=1` skips it).
- In WSL: `test-fast.test.sh`, `vitest-classify.test.sh`, `counterproof.test.sh`. `comandi-equivalenza.test.sh`
  uses git inside WSL: it does not run from a worktree created from Windows (its `.git` points to `C:/`, which Linux
  git cannot resolve); run it from a clone in WSL (`git clone -b <branch> /mnt/c/…/maat ~/maat-linux`).
- Skipped with a declared reason (specific to the guide project): part 2 of `vitest-classify.test.sh`.
  `guard.test.sh` (pk05) tests the plugin hook (`guard-hook.sh`) and its equivalence with the guide project's guard
  on the fixture `tests/guard-esempio.cases`.
- `maat-paths.test.sh` also contains the **anti-structure search**: no reference to the guide project's structure
  (`.claude/skills/`, `script/fic`, `script/test`, `$HERE/../..`, `/../test`, `/../../../script/`) outside comments and
  tests, with the exclusions declared in the test (project commands of the WSL wrappers until pk04b; the fingerprint
  one was closed by pk04a-2).

## Windows and Linux

**Windows** (Git Bash, from the worktree or from the clone on `C:`): `bash plugins/maat/scripts/<name>.test.sh`, one
suite at a time. The three WSL suites (`test-fast`, `counterproof`, `vitest-classify`) are run from WSL on the same
folder:

```bash
wsl -- bash -lc 'cd /mnt/c/<…>/maat && bash plugins/maat/scripts/test-fast.test.sh'
```

**Linux.** There is no dedicated Linux machine: a **clone inside WSL** is used with a pure Linux PATH, so that no
Windows tool (`cmd.exe`, `wsl.exe`, `py.exe`, the Store Python) gets into the test.

```bash
wsl -- bash -lc 'git clone -b <branch> /mnt/c/<…>/maat ~/maat-linux'      # once; then git fetch and reset on the branch
wsl -- bash -lc 'cd ~/maat-linux && PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin FIC_WT_WSL=0 \
  timeout 5400 bash plugins/maat/scripts/<name>.test.sh'
```

- `FIC_WT_WSL=0` tells the worktree tests not to go through WSL: on Linux they are already at home.
- The clone must be realigned to the branch before every run (files copied by hand disappear): no changes inside the
  clone.
- `comandi-equivalenza.test.sh` runs **only** from the Linux clone: the `.git` of a worktree created from Windows
  points to `C:/`.
- `MAAT_ORACOLO_121=1 bash plugins/maat/scripts/plan-check.test.sh` also compares, on every Italian fixture, the
  output of `plan-check.sh` of 1.2.1 (commit `a2c5b99`, read with git) with the current one, byte for byte: the proof
  that 1.3.0 reads the Italian formats as before. Off by default (it doubles the run time).

**The full run** (all suites, Linux first then Windows, one at a time, with a summary per platform):
`bash tools/giro-completo.sh <results folder> <worktree> <branch>`, from Git Bash. `<worktree>` is the Windows folder
of the branch to test, in the form `/c/…`; `<branch>` is the branch the Linux clone is realigned to; the clone is
always `~/maat-linux` (another one with `MAAT_LINUX_CLONE`). For example:
`bash tools/giro-completo.sh /tmp/esiti /c/<…>/maat-lavoro wip/lavoro`. Each suite writes
`<folder>/<linux|windows>/<name>.log` and one line in `riepilogo.txt` (exit code, seconds, last line). Duration: a few
hours, because of the long suites.

**The list of suites** is `tools/suite.list`, one name per line, in the order they run; `giro-completo.sh` and
`tools/suite.sh` both read it. A new suite goes into the list: `tools/suite.sh` refuses (exit 2) a list that misses a
`*.test.sh` or names a file that does not exist.

## CI

`.github/workflows/ci.yml` runs at every push and pull request on GitHub: `ubuntu-latest`, Python 3.10 (the lowest
supported version), Node 20, a test git identity, then `bash tools/suite.sh esiti`: every suite of the list, one at a
time, with `FIC_WT_WSL=0` like the Linux run. The job fails if a suite exits with a code other than 0; the logs and
`riepilogo.txt` are kept as the `esiti` artifact. Locally the same run is
`bash tools/suite.sh <results folder>` from a Linux clone.

What CI does not cover: Windows (Git Bash and WSL) and macOS, which come with multi-platform CI (1.4.3). Until then
the Windows part of `giro-completo.sh` runs before each release. What skips with a declared reason, as in the Linux
clone: part 2 of `vitest-classify.test.sh` (specific to the guide project) and `comandi-equivalenza.test.sh`, which
needs a commit of the private history.

## Genericity

`genericita.test.sh` (Git Bash or WSL) checks that the plugin does not carry the guide project along with it.

1. **Core** (`scripts/`, `skills/`, `agents/`, `hooks/`, `schemas/`): none of the guide project's names (paths,
   services, `.nuxt`, …), outside the test fixtures and the exceptions declared in the test, each with its reason.
   An exception that no longer covers any line is a FAIL. The runner lines (`junitxml`, `--reporter=json`) live only
   in the profiles and the examples.
2. **Documentation** (the repo's `docs/`, except `docs/piani/`; the `README.md` of the repo and of the plugin): no
   name of the guide project. Exception: the real file names of the plugin (`guard-esempio.cases`,
   `nuxt-fastapi.maat.json`). The proper names of your guide project (name, host, services) are not in the repo: put
   them, one per line as regex alternatives, in the local file `.genericita-nomi` at the repo root (ignored by git),
   or point to another file with `MAAT_NOMI_RISERVATI`. Without the file the test checks only the generic names and a
   fake name, used by the counterproofs.
3. **Guide links:** every internal `href` of `docs/GUIDA-FLUSSI.html` leads to an anchor (`id`) that exists in the
   page or to a file that exists next to the guide. `http(s):`, `mailto:` and `data:` are not checked. Only grep and
   existence tests: no link checker to install.
4. **Mutation counterproofs**, on copies: a guide project name in a comment of `gates.sh` ⇒ red; a name in a copy of
   the guide ⇒ red; an `href` to a nonexistent file or a nonexistent anchor ⇒ red; the restored copy turns green
   again.

## The `MAAT_ROOT` snapshot

The plugin must never receive project files. `maat-paths.test.sh` (section 8) works on a **copy** of the plugin and
takes a snapshot of it before and after (every file with its sha256, including new and deleted files): any
difference makes the suite fail. The snapshot is used instead of `chmod -R a-w`, which on Windows/MSYS does not
prevent creating files. The Python sources set `sys.dont_write_bytecode = True` before importing `maat_paths`, so
no `__pycache__` appears under the plugin.

```bash
snap() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }
```

## The harness fingerprint (pk04a-2)

On a cycle's first launch `run-phase.sh` writes `<run-dir>/harness.fp`, three lines:

```text
impronta=<64 hex digits>
versione=<version from .claude-plugin/plugin.json>
radice=<MAAT_ROOT, in the form C:/…>
```

(`impronta` = fingerprint, `versione` = version, `radice` = root.)

- **What goes in:** every file under `MAAT_ROOT` (relative path, `LC_ALL=C` order, sha256 of the content without CR)
  except the single `HARNESS_EXCLUDE` list of `run-phase.sh` — `__pycache__`, `assets`, `*.swp`, `*.orig`,
  `.DS_Store`, `*~`, matched against every path component — plus `<project>/.claude/maat.json` (absent: a fixed
  line, so creating or deleting it changes the fingerprint). No git and no `.gitignore`: a stray file left in the
  plugin folder (for example a `.bak`) stops the cycles. The **project's** skills (for example `dev-verify`) are not
  part of it: changing one does not stop a cycle.
- **Who decides:** a single function, `run-phase.sh --harness-fp-confronta <harness.fp> [<repo>]`, used by
  `run-phase.sh` (exit 6), `cycle-state.sh` and `driver.py next` (`Next: STOP — …`). It prints one line: `UGUALE`
  (equal), `CAMBIATO <reg> <att>` (changed), `FORMATO-PRECEDENTE <reg> <att>` (previous format: a single line of 64
  hex digits, cycle started with the internal harness), `ILLEGGIBILE <att>` (unreadable: empty, truncated, no
  fingerprint) or `NON-CALCOLABILE` (cannot be computed). Only `UGUALE` lets the cycle go on; `versione=` and
  `radice=` do not count (the same plugin from another folder gives `UGUALE`).
- **Diagnostics:** `run-phase.sh --harness-paths` lists the files that go into the fingerprint.

**Confirming an intended change.** The STOP message prints the remedy with an absolute path; run from the project
folder, it rewrites the file in the new format:

```bash
bash "<MAAT_ROOT>/scripts/run-phase.sh" --harness-fp > "<run-dir>/harness.fp"
```

Outside a repository the command exits with 1 and leaves the file **empty**: the cycle stays stopped (`ILLEGGIBILE`).

## Recertifying the driver (`driver.equiv`)

`driver.equiv` carries the hash of `driver.py`, `cycle-state.sh` and `run-phase.sh`: if one of the three changes,
the certificate has expired and the wrappers fall back to the bash code (it works, it is just slower). It is
recertified on the real run dirs of a project, from its main folder and **read-only**:

```bash
cd <project>
O=<temporary folder>; mkdir -p "$O/info" "$O/pack"   # git objects written by review-surface.sh tree
PYTHONDONTWRITEBYTECODE=1 GIT_OPTIONAL_LOCKS=0 GIT_OBJECT_DIRECTORY="$O" \
  GIT_ALTERNATE_OBJECT_DIRECTORIES="<project>/.git/objects" FIC_DRIVER_CERT=<temporary file> \
  "$FIC_PY" "<MAAT_ROOT>/scripts/driver.py" equiv --certifica .claude/.ai-workflow   # FIC_REPO not set
```

`review-surface.sh tree` runs `git add -A` and `write-tree` on a temporary index: without `GIT_OBJECT_DIRECTORY` the
objects would end up in the project's `.git`; `GIT_OPTIONAL_LOCKS=0` keeps git from updating the real index.

- Required outcome `diverse=0 · diversi=0`; a `DIVERSO` (different) is a STOP with the diff, it is not recertified by
  hand.
- Before and after, a snapshot (list and sha256) of `.claude/.ai-workflow/spec-*.md` and `.claude/.ai-workflow/*.run/`:
  it must be identical.
- Then the file is copied to `scripts/driver.equiv` and `driver.py certificato` must say VALIDO (valid).
  `driver.equiv` is under `MAAT_ROOT`: recertifying changes the harness fingerprint.

### Variant: certifying on a copy of the project

This is the form used on 2026-10-29 (certificate of 0.3.0): the real project stays completely out, not even read
with the variables above.

1. **The copy:** a clone of the project branch in a temporary folder, with `git -c core.longpaths=true clone …`
   (on Windows the run dir paths exceed 260 characters), plus the specs and run dirs of **closed** cycles
   (`.claude/.ai-workflow/spec-*.md` and `*.run/`), copied from the project. On 2026-10-29: 15 closed cycles (chains,
   single cycles, one cycle in STOP, three from the old regime).
2. **Before:** snapshot (list and sha256) of the specs and run dirs of the real project.
3. **The certification:** the command above, run from the root of the **copy** (git objects in the temporary folder
   as above). Required outcome `diverse=0 · diversi=0`; on 2026-10-29: `spec=15 diverse=0 · jsonl=83 diversi=0`.
4. **After:** the same snapshot of the real project, identical to the one taken before.
5. The certificate is copied to `scripts/driver.equiv` and `driver.py certificato` must say VALIDO.

Duration: about **3 hours on Windows**, almost all of it in the `review-surface.sh check` controls in bash. The copy
can be kept for the next certification (only the plugin changes); if the temporary folder has been emptied, it is
redone, never on the project's tree.
