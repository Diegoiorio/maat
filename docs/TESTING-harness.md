# Harness tests

Applies to the `plugins/maat` plugin of this repo: how to run the suites on Windows and on Linux, the genericity
test, the driver certificate and its public examples, and the old-against-new oracle.

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
| cycle components | `FIC_RUN_PHASE`, `FIC_CONTEXT_PACK`, `FIC_GATES`, `FIC_FINALIZE`, `FIC_DRIVER_PY`, … | the plugin's scripts |
| engine that decides (1.5.1) | `FIC_DRIVER` | unset: the Python driver (table below) |
| driver certificate | `FIC_DRIVER_CERT`: only for `driver.py certificato`, `driver.py equiv --certifica` and `tools/certifica.sh`; since 1.5.1 it affects neither the wrappers nor `run` | `scripts/driver.equiv` |
| other | `PLAN_CHECK_ROOT`, `CLAUDE_BIN`, `FIC_PYTHON`, `MAAT_CONFIG` | — |

Under an overridden harness root the plugin structure applies: a mutated copy of the plugin (test counterproofs) is
passed whole, not just one script.

**`FIC_DRIVER`, the engine (1.5.1).** The same choice in the three places that decide (`cycle-state.sh`,
`run-phase.sh` for `valida`, `driver.py run`), inherited from one to the other, so in one invocation one engine
decides:

| `FIC_DRIVER` | 1.5.0 | 1.5.1 |
|---|---|---|
| unset or empty | certificate VALIDO → Python, otherwise bash | **Python** |
| `1` | Python | Python (the same as the default, accepted for compatibility) |
| `0` | bash | **bash** (unchanged) |
| any other value | the certificate decides | Python, with a line `AVVISO: FIC_DRIVER=<value> …` on stderr (in `run`: an event) |

Before the choice, with either engine, the Python check: no interpreter (`python.sh` fails) or one older than 3.10 →
`Next: STOP — …` (`cycle-state.sh`), `PHASE RESULT <phase>: STOP — …` (`run-phase.sh`), `Driver result: STOP — …`
(`run`), with the remedy `FIC_PYTHON=<python 3.10 or newer>`. `FIC_DRIVER` does not enter the harness fingerprint and
does not need to be in `WSLENV` (none of the three runs inside `wsl`). How to go back to bash: «Going back to the bash
engine».

**Message language (`MAAT_LINGUA`, 1.4.0).** The messages the scripts print for a person come from the catalog
`scripts/lib/messages.tsv` (`msg` in bash, `lib/maat-msg.sh`; `T` in Python, `maat_msg.py`). The language is
`MAAT_LINGUA` (`it|en`; any other value: `en`; empty: unset), otherwise `lingua` of `.claude/maat.json`, otherwise
`en`; `guard.py` follows the same precedence. Since 1.5.0 `run-phase.sh` adds `MAAT_LINGUA` to `WSLENV` (no
duplicate, the entries and flags already there kept), so a value set by hand also reaches what the phase session and
each lane run in `wsl`, instead of the `lingua` read again there from `.claude/maat.json`. The section below says how
the two languages are tested.

## The two languages (1.4.0)

- **Italian, unchanged.** Every suite starts with `export MAAT_LINGUA=it`: its assertions are on the Italian text,
  the same as in 1.3.0, so a green suite proves that `"lingua": "it"` prints what 1.3.0 printed. The cases that test
  the reading of `lingua` (guard, session-start, maat-config) drop the variable (`env -u MAAT_LINGUA` or a local
  `unset`).
- **English cases.** Next to the Italian ones, the suites of the scripts that print messages have cases with
  `MAAT_LINGUA=en` on their main output: the English text is there and no Italian is left, except the frozen lines. `cycle-state.test.sh` runs every `expect`
  in English too (`CS_EN=0` skips that part, it makes the suite slower). In `plan-check.test.sh`,
  `MAAT_VINCOLO2=1` checks that the stdout of `basis` and `contract` is byte for byte the same with `MAAT_LINGUA=it`,
  with `MAAT_LINGUA=en` and with `plan-check.sh` of `v1.3.0` (off by default).
- **The catalog and the anti-leak test.** `messages.test.sh` tests `scripts/lib/messages.tsv`: bash and Python give
  the same language and the same bytes, the catalog format (unique keys, the same placeholders in both columns, no
  Italian in the `en` column, no key missing or unused), the fallback `‹key›`, and the static **anti-leak** test: no
  Italian literal in a plugin script outside the catalog and `scripts/lib/protocol-strings.list`. Its counterproofs
  run on a mutated copy of the plugin (an Italian `echo` added, a list entry deleted…) and must be red.
- **The inventory.** `python tools/lingua-inventario.py` (read-only) scans every `.sh`/`.py` of the plugin and prints
  the residual: the lines that still hold Italian once the frozen parts of `protocol-strings.list` are taken out
  (`--rows` lists them; an entry of the list that covers nothing is reported as unused).
  `python tools/lingua-inventario.py --consumers` looks at the other side: the places (scripts, tests, skills,
  agents) that read Italian text another script prints. `messages.test.sh` uses the same scanner; outside the repo
  (plugin installed in the cache) those sections are skipped with the reason.
- **The conversion.** The messages were moved by `tools/lingua-converti.py` from the tables of
  `tools/lingua-conversioni/`. `check <table>` compares every Italian entry with its literal in `v1.3.0`;
  `copertura <table>...` checks that every Italian-looking literal of the cited lines is covered by an entry, or
  declared in `non-messaggi.list` or `protocol-strings.list` (a wrong `#n` index passes `check`, not `copertura`).
  Run both, on all the tables, after any change to a table; a one-word literal outside the scanner vocabulary is
  seen by neither, so check those rows by hand.
- **The conversion tables in the suite (1.5.0).** Section 10 of `messages.test.sh` runs `copertura` on all the
  tables and `check` on each one, so nobody has to remember it. Like the anti-leak test it works in the repo only: it
  is SKIPPED, with the reason, from the installed plugin or in a clone without the tag `v1.3.0` (a shallow clone).
  On GitHub Actions a skip is a FAIL (the CI clones with `fetch-depth: 0`, tags included).
- **Driver against bash in both languages (1.5.0).** Section 9 of `driver.test.sh` runs every case of
  `cycle-state.test.sh` and compares the output of `cycle-state.sh` with that of `driver.py next`, now in `it` **and**
  in `en` at every call (the calls `en_twin` already makes in English are compared only in English). A difference is
  recorded with its language; a comparison where one side prints no `Next:` line is a failure too, so two sides that
  both fail silently do not count as «the same».
- **Frozen lines.** `protocol-strings.list` says, line by line, which Italian text stays in every language and why
  (the lines that scripts pass to each other, the keywords `VIOLAZIONE`, `AVVISO`, `ERRORE DURO`, `Percorso:`,
  `Scheletro:`, `S2:`). A new Italian literal goes either into the catalog or into the list, with its reason.

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
- Long (one at a time, in the background): `rollback` (1.5.1, «Going back to the bash engine»;
  `ROLLBACK_TEST_RAPIDO=1` keeps scenario S1 only), `cycle-state`, `run-phase`, `driver` (section 9 of
  `driver.test.sh` runs all of `cycle-state.test.sh`; `DRIVER_TEST_RAPIDO=1` skips it).
- **The suites prove the default engine (1.5.1).** `cycle-state.test.sh` and `run-phase.test.sh` run with
  `FIC_DRIVER` unset, so the Python driver decides; the bash table is proven at every call by section 9 of
  `driver.test.sh`, the internal validator by its section 2, both by `equiv` on the examples. A **variant** given to
  a suite for a mutation counterproof follows the same rule: a variant of the bash table
  (`FIC_DRIVER=0 CS=<variant> bash plugins/maat/scripts/cycle-state.test.sh`) or a variant of `run-phase.sh` that
  changes `VALIDA_PY` (`FIC_DRIVER=0 RP=<variant> bash plugins/maat/scripts/run-phase.test.sh`) is tested with
  `FIC_DRIVER=0`: without it the driver decides and the mutation is not seen (a false green).
- In WSL (they need `rsync` and `flock`): `test-fast.test.sh`, `vitest-classify.test.sh`, `counterproof.test.sh`,
  `comandi-equivalenza.test.sh`. Since 1.5.0 `comandi-equivalenza.test.sh` reads no git history, so it also runs in
  WSL on a worktree created from Windows (see «The commands of the gates: frozen reference»).
- Tests of the repo, in `tools/` (they make sense only in the repo, not from the installed plugin):
  `tools/suite.test.sh`, `tools/esempi-equiv.test.sh` (the public examples of the driver certificate),
  `tools/oracolo.test.sh` (the old-against-new oracle). Run them from the repo root: `bash tools/<name>.test.sh`.
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
- Git cannot read a worktree created from Windows from inside WSL (its `.git` points to `C:/`): the few cases that
  need the history of this repo (the oracle with git refs) are SKIPPED there and run on the Linux clone.
- `MAAT_ORACOLO_121=1 bash plugins/maat/scripts/plan-check.test.sh` also compares, on every Italian fixture, the
  output of `plan-check.sh` of 1.2.1 (commit `a2c5b99`, read with git) with the current one, byte for byte: the proof
  that 1.3.0 reads the Italian formats as before. Off by default (it doubles the run time).

**The full run** (all suites, Linux first then Windows, one at a time, with a summary per platform):
`bash tools/giro-completo.sh <results folder> <worktree> <branch>`, from Git Bash. `<worktree>` is the Windows folder
of the branch to test, in the form `/c/…`; `<branch>` is the branch the Linux clone is realigned to; the clone is
always `~/maat-linux` (another one with `MAAT_LINUX_CLONE`). For example:
`bash tools/giro-completo.sh /tmp/esiti /c/<…>/maat-lavoro wip/lavoro`. Each suite writes
`<folder>/<linux|windows>/<name>.log` and one line in `riepilogo.txt` (exit code, seconds, last line). Duration: about
40 minutes on Linux, about 10 hours on Windows (1.5.0), because of the long suites. Two options (1.5.1), before the
arguments:

- `--linux-parallelo`: the Linux part with `tools/suite-parallelo.sh` (below), three clones at once, about 15 minutes
  instead of 40. Clones in `MAAT_LINUX_CLONI` (relative to the WSL home, default `maat-linux maat-linux-2
  maat-linux-3`). If the machine is busy the run stops before the Windows part.
- `--windows-breve`: the Windows part runs only the short proof (below), about 50 minutes.

For a release since 1.5.1: `bash tools/giro-completo.sh --linux-parallelo --windows-breve <folder> <worktree> <branch>`.

- In the Windows part most suites run in Git Bash on the worktree; the suites that need `rsync` and `flock`
  (`test-fast`, `counterproof`, `vitest-classify`, `comandi-equivalenza`) and `tools/oracolo.test.sh` run in WSL on
  the same worktree (`/mnt/c/…`). `tools/esempi-equiv.test.sh` stays in Git Bash on purpose: it is the proof of the
  driver on Windows (see «Recertifying the driver»).
- **Guard of the run (1.5.0).** Don't touch the plugin while the run is going: the harness fingerprint changes and
  the suites that check it fail for no real reason. `giro-completo.sh` and `tools/suite.sh` take a fingerprint of the
  plugin files (the list of `run-phase.sh --harness-paths`, content without CR) before the first suite and after each
  one; a suite after which it changed gets `PLUGIN CAMBIATO` in its line of `riepilogo.txt`, and the exit is 1. On
  Linux the fingerprint is taken on the clone.
- At the top of both `riepilogo.txt`, an `AVVISO` line when the Linux clone is not at the commit of the worktree, or
  when the worktree has uncommitted changes under `plugins/` or `tools/`: the two parts would not test the same tree.

**Times on Windows and on Linux** (measured for 1.5.0). The proof on the public examples is slow in Git Bash:
`review-surface.sh` runs `git add -A` on a temporary index for every check, and process start-up costs much more on
Windows.

| what | Git Bash (Windows) | WSL or Linux |
|---|---|---|
| `tools/esempi-equiv.test.sh` | about 56 minutes | about 2 minutes (CI: about 128 s per validator) |
| `tools/oracolo.test.sh`, the oracle on the whole corpus | about 70 minutes | a few minutes |
| `plugins/maat/scripts/rollback.test.sh` (1.5.1) | `ROLLBACK_TEST_RAPIDO=1`: about 52 minutes | complete: about 3.6 minutes (218 s) |
| `plugins/maat/scripts/driver.test.sh` (1.5.1) | `DRIVER_TEST_RAPIDO=1`: about 39 minutes (machine loaded) | complete: about 6.4 minutes (382 s; section 9 +29 s over 1.5.0) |

The corpus has 65 specs, almost one per row of the table plus the mothers and rings of the chains: it is kept whole,
not trimmed for speed. That is why the full run sends `tools/oracolo.test.sh` to WSL in its Windows part too, and why
the certificate is written from Linux.

**The list of suites** is `tools/suite.list`, one name per line, in the order they run; `giro-completo.sh` and
`tools/suite.sh` both read it. A plain name is `plugins/maat/scripts/<name>.test.sh`; an entry with a `/` is a path
from the repo root (`tools/esempi-equiv.test.sh`). Both scripts resolve an entry with the same function (`suite_file`,
`tools/lib/guardia-plugin.sh`). A new suite goes into the list: `tools/suite.sh` refuses (exit 2) a list that misses a
`*.test.sh` of the plugin or a `tools/*.test.sh`, or names a file that does not exist.

**The groups (1.5.1)** are `tools/suite-gruppi.list`, one line `<group> <entry>`: three groups of similar length on
Linux (about 13.5 minutes each on the clone in WSL), used by the CI (one job per group) and by the parallel run (one
clone per group). `bash tools/suite.sh --gruppo <k>/<n> <folder>` runs group k only, in the order of `suite.list`, and
refuses (exit 2) a groups file that does not cover `suite.list` exactly (an entry in no group or in two, an entry not
in the list) or that has not exactly the groups 1..n. A new suite goes into both files; to rebalance, move a line
using the times of the last `riepilogo.txt`. `tools/esempi-equiv.test.sh`, the one that reads `MAAT_CERT_RICHIESTO`,
is in group 3.

### The parallel run (1.5.1)

`bash tools/suite-parallelo.sh <folder> <ref>`, from Linux or WSL, from any checkout of the repo: group k of
`tools/suite-gruppi.list` runs in clone k (`MAAT_LINUX_CLONI`, one clone per group, relative to `$HOME` or absolute,
default `maat-linux maat-linux-2 maat-linux-3`), all at the same time, each with `tools/suite.sh --gruppo k/n`. Create
the clones once (`git clone <repo> ~/maat-linux-2`, …) with origin pointing to a repo that has `<ref>`; the script
realigns them (fetch, `checkout --detach`, `clean`), so nothing must be changed inside them.

- **It does not start (exit 3)** when the machine is busy: another parallel run (a lock, `MAAT_PARALLELO_LOCK`),
  `tools/certifica.sh` running (the certificate never runs together with anything, and the parallel run never
  together with the certificate), or a Maat cycle running on Windows (a Windows process whose command line has
  `driver.py run`, read from WSL through `powershell.exe`; outside WSL this part is skipped). `MAAT_PARALLELO_FORZA=1`
  skips the check of the processes, not the lock. A cycle on Linux is not seen: don't start the run while one goes.
- **A suite red in parallel is run again alone**, in its clone, after every group has ended. Green alone: its line of
  `riepilogo.txt` says `ROSSA SOLO IN PARALLELO` and it counts as green, but it depends on the others (load, a shared
  path) and goes into a group of its own; red again: `ROSSA ANCHE DA SOLA`, exit 1. A suite after which its clone's
  plugin changed (`PLUGIN CAMBIATO`, the guard of `suite.sh` on each clone) is not run again.
- `<folder>/riepilogo.txt`: one line per suite in the order of `suite.list` (`g<group>`, exit, seconds, last line),
  then `parallelo: gruppi=… · in parallelo …s · con i rilanci …s · rosse=… · rosse-solo-in-parallelo=…` and `FINE`;
  `<folder>/gruppo-<k>/` holds the logs; `<folder>/clone.txt` the commit of each clone (all the same, otherwise exit 2).
- Before 1.5.1 the suites were checked for shared state: they create their files in `mktemp -d` and set a `HOME` of
  their own where it matters (`test-fast`, `counterproof`, the cycle suites); `guard.test.sh` sets a fixed
  `SCRATCH=/tmp/claude/scratch` that nothing uses.
- **Not yet accepted on the real suites.** Its own cases are in `tools/suite.test.sh` (section 7: fake clones, a suite
  red only in parallel, a suite always red, the lock, a counterproof). The comparison with the run one at a time on
  the same commit is made by the CI, split in the same groups, at the push of 1.5.1: since 1.5.1 the full runs are made
  on the CI; the parallel run is for a local check when the CI is not at hand.

### The short proof on Windows (1.5.1)

Since 1.5.1 a release does not run the whole Windows part (about 10 hours in Git Bash) but a short proof:
`tools/prova-breve-windows.list`, the quick suites in Git Bash, about 48 minutes (1.5.0 times: `tools/suite.test.sh`,
`stop-hook`, `blocks-independent`, `phase-usage`, `session-start`, `harness-merge`, `phase-events`, `maat-config`,
`context-pack`, `genericita`, `senza-wsl`, `maat-paths`, `messages`, `cycle-report`, `guard`, `bash-node`,
`test-review-surface`, `gates`). It runs with `bash tools/giro-completo.sh --windows-breve …`. A line may start with
`VAR=value` words, which the suite runs with. Left out: `ROLLBACK_TEST_RAPIDO=1 rollback` (about 52 minutes: with it
the proof would take about 1 h 40 min); run it by hand when a release changes the wrappers, and with it
`DRIVER_TEST_RAPIDO=1 driver` (the `cygpath` cases). What the short proof does not cover on Windows — the long suites
and `tools/esempi-equiv.test.sh` (the fingerprint of the examples Windows ≡ Linux was proven in 1.5.0) — passes to the
multi-platform CI (1.5.3).

## CI

`.github/workflows/ci.yml` runs at every push and pull request on GitHub. Since 1.5.1 in **three jobs at the same
time**, one per group of `tools/suite-gruppi.list` («The groups»): each one `ubuntu-latest`, Python 3.10 (the lowest
supported version), Node 20, a test git identity, the `jsonschema` venv, then `bash tools/suite.sh --gruppo <k>/3
esiti`, one suite at a time with `FIC_WT_WSL=0` like the Linux run. A job fails if a suite exits with a code other
than 0, or if the groups file does not match `suite.list` or the three jobs of the matrix; its logs and
`riepilogo.txt` are kept as the artifact `esiti-gruppo-<k>`. The check to require is **`linux`**: a last job, green
only if all three groups are (`fail-fast: false`, so a red group does not stop the others). Limit per job: 30 minutes
(the longest group about 15 minutes plus the setup, × 1.5; before, one job of 45 minutes used about 42). Locally the
same run is `bash tools/suite.sh <results folder>` from a Linux clone, or the parallel run.

**The two validators (1.5.0).** The outcome validator of `run-phase.sh --valida` and `driver.py valida` uses the
`jsonschema` module when the interpreter has it, a minimal validator otherwise. The CI proves both: the system Python
has no `jsonschema` (minimal validator), and a step creates a venv of its own with `jsonschema==4.23.0` and exports
`MAAT_PY_JSONSCHEMA` to its interpreter. `tools/esempi-equiv.test.sh` runs the proof once per validator.

**Strict check of the certificate.** With `MAAT_CERT_RICHIESTO=1`, `tools/esempi-equiv.test.sh` also requires
`driver.equiv` VALIDO, the fingerprint of its `corpus` line equal to that of the corpus just built, `validatori
minimo,jsonschema`, and no validator skipped. The CI sets it on pushes to `main`, on tags and on pull requests to
`main`; on other branches the check is off, so half-done work can still be pushed. So **a pull request to `main` that
touches a certified file** (`driver.py`, `cycle-state.sh`, `run-phase.sh`, `lib/messages.tsv`, `lib/maat-msg.sh`,
`maat_msg.py`) is red (certificate SCADUTO) until the same pull request commits the `driver.equiv` rewritten with
`bash tools/certifica.sh --scrivi` from Linux. The same holds for a pull request that changes the examples, or what
computes them (`plan-check.sh basis`, `review-surface.sh snapshot` and `fingerprint`): red because the fingerprint
differs, same remedy.

What CI does not cover: Windows (Git Bash and WSL) and macOS, which come with multi-platform CI (1.5.3). Until then
the short proof on Windows runs before each release (since 1.5.1; before, the whole Windows part of
`giro-completo.sh`). What skips with a declared reason, as in the Linux
clone: part 2 of `vitest-classify.test.sh` (specific to the guide project). Since 1.5.0 `comandi-equivalenza.test.sh`
and section 10 of `messages.test.sh` run in CI too.

## The commands of the gates: frozen reference

`comandi-equivalenza.test.sh` compares the commands the gates run (`gates.sh`, `finalize.sh`) on a synthetic
repository with those of the reference harness, the last one with hard-wired commands (a commit of the private
development history). Until 1.4.0 it read that commit with git, so it was SKIPPED everywhere the commit was missing,
which means everywhere outside the private repo.

Since 1.5.0 the output of the reference side is **frozen** in `plugins/maat/tests/comandi-equivalenza/riferimento.txt`
(one section per case and view, already normalized). The test compares the current plugin with that file and reads
no git history, so it runs in WSL and on Linux, in CI included. It needs `rsync` and `flock`.

- The synthetic repository is deterministic: fixed git identity and dates, no git configuration of the machine, a fake
  `node` that prints `v20.0.0`, `TZ=UTC`. The normalizations are declared at the top of the test: `<repo>`, `<copia>`,
  `<report>`, the base commit as `<base>` and, in the view `chiave`, `tree=<40 hex digits>` as `tree=<tree>`.
- A **hygiene** case checks the reference itself: no `node=v` other than the fake's, no `tz_wsl=` other than the fixed
  one, no 40-digit sha.
- **Regenerating it** needs the private history: `MAAT_RIF_REPO=<repo with the reference commit> bash
  plugins/maat/scripts/comandi-equivalenza.test.sh --rigenera` runs the reference side, rewrites
  `riferimento.txt` and then compares. Do it only when a normalization changes; the file changes only together with
  the test.

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
  line, so creating or deleting it changes the fingerprint), and since 1.4.0 a line `lingua <it|en>` with the
  **resolved** language of the messages (`MAAT_LINGUA`, otherwise `lingua` of `maat.json`, otherwise `en`): changing
  the language in the middle of a cycle stops it like any other change of the harness. No git and no `.gitignore`: a stray file left in the
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

`driver.equiv` carries the hash of `driver.py`, `cycle-state.sh`, `run-phase.sh`, `lib/messages.tsv`,
`lib/maat-msg.sh` and `maat_msg.py` (CR removed): if one of them changes, the certificate has expired (SCADUTO).
Since 1.5.1 the certificate **decides nothing at runtime**: the driver decides whatever it says, and the bash code
only with `FIC_DRIVER=0` («Going back to the bash engine»). It is the proof, at each release, that the fallback decides
like the driver. A SCADUTO certificate makes the CI red on `main`, on tags and on pull requests to `main` (strict
check, «CI»); `driver.py certificato` shows the verdict and the hashes that differ. The header that `--certifica`
writes still says that the wrappers call the driver only when the hashes match: it is a frozen line
(`lib/protocol-strings.list`) that describes 1.5.0, kept as it is until 1.5.2. Its last line says what it was proven
on:

```text
corpus spec=<N> jsonl=<M> · lingue it,en · <date> · impronta <12 hex> · validatori minimo,jsonschema
```

`impronta` is the fingerprint of the examples (below) and `validatori` the outcome validators proven (1.5.0; the
part before ` · impronta` is the one of 1.4.0).

**The reference, since 1.5.0:** the certificate is made on the public examples, from Linux, in one command:

```bash
bash tools/certifica.sh            # verify: build, prove, write the certificate to a temporary file only
bash tools/certifica.sh --scrivi   # the same, then copy it to plugins/maat/scripts/driver.equiv (Linux only)
```

The script builds the examples in a temporary folder, runs `driver.py equiv --certifica` on them once per validator
(first the minimal one, then `jsonschema`), checks that `driver.py certificato` says VALIDO and that the `corpus` line
carries the fingerprint of the examples just built. It prints the duration: a few minutes on Linux. Never run it
together with anything else (suites, the full run, the other proof).

- **Only from Linux.** `--scrivi` refuses (exit 2) outside Linux: Linux is where the CI checks the certificate. On
  Windows run it in WSL on the path of the worktree, so the file lands directly in the worktree:
  `wsl -- bash -lc 'cd /mnt/c/<worktree path> && bash tools/certifica.sh --scrivi'`.
- **Two interpreters.** `--scrivi` also refuses without both validators, or with a `jsonschema` of a version other
  than the one fixed in `.github/workflows/ci.yml` (today `4.23.0`):
  - for `jsonschema`: `MAAT_PY_JSONSCHEMA=<python with jsonschema==4.23.0>`, otherwise `~/maat-venv/bin/python`;
  - for the minimal validator: an interpreter **without** `jsonschema`, `MAAT_PY_MINIMO=<python>`, otherwise the
    Python that `scripts/python.sh` finds, if it does not import `jsonschema`. In WSL the system `python3` may well
    have it (an older version, from the distribution's packages): then it cannot be the minimal one, and it is not the
    CI's version either.
- **Preparing them is an installation**, done once and by hand (Maat never installs anything by itself):

  ```bash
  python3 -m venv ~/maat-venv && ~/maat-venv/bin/pip install jsonschema==4.23.0   # validator jsonschema
  python3 -m venv ~/maat-venv-minimo                                              # validator minimo: no packages
  MAAT_PY_MINIMO=~/maat-venv-minimo/bin/python bash tools/certifica.sh --scrivi
  ```

  A new venv does not see the packages of the system Python, so `~/maat-venv-minimo` has no `jsonschema`. When a
  validator is missing, `certifica.sh` prints the command to create it.
- After `--scrivi`: `driver.equiv` is under `MAAT_ROOT`, so recertifying changes the harness fingerprint. Commit it
  in the same pull request as the change that made it expire (see «CI»).
- **The guarantee for Windows** is not the certificate but `tools/esempi-equiv.test.sh` in the Windows part of the
  full run, in Git Bash: there the branches that exist only on Windows (the `cygpath` paths of the driver, the
  `C:/…` forms) are proven too. It is slow there (about 56 minutes). It was a step of every release until 1.5.0; the
  short proof on Windows of 1.5.1 leaves it out (the logic of the driver does not change; the fingerprint Windows ≡
  Linux was proven in 1.5.0), and it comes back with the multi-platform CI (1.5.3).

## Going back to the bash engine (1.5.1)

Until 1.5.2 the original bash code is still in the plugin: the resume table of `cycle-state.sh` and the internal
validator of `run-phase.sh` (`VALIDA_PY`). It decides **only on request**.

- **When:** a defect of the driver, for example a `STOP — driver.py next failed (exit …)` or a `PHASE RESULT <phase>:
  STOP — driver.py valida failed …` (Italian: `non riuscito`), whose text gives the remedy. Not for a missing or old
  Python: the bash code needs Python too, so that `STOP` has the same remedy with either engine (`FIC_PYTHON`).
- **How:** `FIC_DRIVER=0` for one command (`FIC_DRIVER=0 "$FIC_PY" <MAAT_ROOT>/scripts/driver.py run …`) or exported
  for the session. Nothing to confirm: `FIC_DRIVER` is not in the harness fingerprint, so the cycle goes on in the same
  run dirs. To go forward again, drop the variable. `driver.log` says `motore bash (FIC_DRIVER=0)` (`bash engine` in
  English) at the first entry into each spec.
- **What is proven** by `plugins/maat/scripts/rollback.test.sh`, with the real `run-phase.sh`, `cycle-state.sh` and
  `plan-check.sh` and a fake `claude`, gates and finalize: a cycle started with one engine and resumed with the other,
  after each phase that writes to disk, in both directions, continues with the same run dirs, the same `harness.fp`,
  the same `Next`, the same end and the same files (a photo of the repo with a closed list of normalizations), and the
  engine asked for is really the one that decided. Scenarios: a format-1 cycle (plan, implement, review
  NEEDS_CHANGES, fix, review APPROVED); a STOP outcome and its recovery, defensive deviations, a phase interrupted;
  and the driver failing at the end of an implement, resumed with bash (only the implement with the `STOP` outcome
  runs again). 17 resumes and five counterproofs (`FIC_DRIVER` in the fingerprint, a different `State`, a field
  more or a different form in `result.json`, a resume that does not change engine), each red where expected.
- **What is not proven:** the rollback on a chain (mother and rings) and on a format-2 cycle with lanes, and in
  English. There the two engines are proven equivalent in their decisions by `driver.equiv` and by the oracle, not by
  a resume with the other engine. The fake phases are not a real project: the real minimal cycle on Windows is asked
  for before 1.5.2 removes the bash code.
- **Times:** complete on Linux about 3.6 minutes; `ROLLBACK_TEST_RAPIDO=1` (S1 only, the driver failure and two
  counterproofs, 11 resumes) about 1.5 minutes on Linux and 52 minutes in Git Bash. `ROLLBACK_TEST_TIENI=1` keeps the
  temporary folder for a diagnosis.

**In two languages (1.4.0).** `equiv` runs the whole proof twice, first with `MAAT_LINGUA=it` and then with
`MAAT_LINGUA=en` (a line `equiv: lingua <l>` opens each pass), and writes the certificate only if both say
`diverse=0 · diversi=0`; the `corpus` line then says `lingue it,en`. The `harness.fp` files are left as they are,
never regenerated for the proof; the language inside the fingerprint is proven by the suites (`run-phase.test.sh`,
`cycle-state.test.sh`).

**Cycles not closed (1.5.0).** For each spec whose `Next` is not `DONE`, `equiv` prints a line `equiv: AVVISO — <spec>
not closed (Next: <word>)`: the proof on that spec covers the row that decides that word, not the path to `DONE`.
When the spec has a `harness.fp` whose verdict is not `UGUALE`, the warning says the proof covers only the fingerprint
branch. Each pass ends with `equiv: aperte=<n> · impronta-non-uguale=<k>`, after the usual summary line. The warnings
do not block `--certifica`: the examples have open cycles on purpose, because their rows are the ones to prove.
`driver.py equiv --impronta <folders>` prints only the fingerprint of the examples, without the proof.

### The public examples (`tools/esempi-equiv/`)

Seven small git repositories, built from models, with 65 specs and 49 counted jsonl: Italian (1.2.x) and English
(1.3+) formats, single cycles and chains (closed, open, with code or tree changed after the closing).

- **What they cover**, as two closed lists: `righe.list`, every row of the resume table of `cycle-state.sh` (and of
  the chains and of the `result.json` rules), one label per distinct outcome; `rami-valida.list`, every branch of the
  outcome validator and every phase. The manifest `casi.tsv` gives each spec the expected first word of `Next` and the
  row that decides it, and each jsonl the branches it goes through.
- **The builder**, `bash tools/esempi-equiv/costruisci.sh <empty folder>`, creates the repositories, copies the
  models and fills a closed list of computed placeholders (commit and tree sha, Approved basis, snapshots,
  `Finalize`, `state=`) with the same plugin scripts that compute them in a real cycle. It is deterministic: no git
  configuration of the machine, fixed identity, dates, permissions and line endings. Two builds give the same
  fingerprint, on Windows and on Linux. Last it prints `impronta <64 hex>`.
- **The test**, `bash tools/esempi-equiv.test.sh`: two builds with the same fingerprint; every label of the two lists
  has a case, every spec and jsonl built is in `casi.tsv` and vice versa, no counted jsonl is empty; then `equiv`
  with each validator available: every spec `UGUALE`, `diverse=0 · diversi=0` in `it` and `en`, and the word of `Next`
  of every spec equal to `casi.tsv` in both languages.
- **Adding a case:** the spec and its run dir go under `tools/esempi-equiv/<mini-repo>/modelli/.ai-workflow/` (code
  states under `stati/<n>/`), one line in `casi.tsv` for the spec and one for each jsonl; a new row of the table also
  gets a label in `righe.list`, a new validator branch one in `rami-valida.list`. Use only generic names (the
  genericity test checks the folder). A change to the examples changes their fingerprint: the certificate must be
  rewritten (`tools/certifica.sh --scrivi`), or the strict check is red.

### Variables of the tests of the repo

| variable or option | where | what it does |
|---|---|---|
| `MAAT_PY_JSONSCHEMA` | `esempi-equiv.test.sh`, `certifica.sh` | the interpreter with `jsonschema` (second validator); without it: `SALTATO: jsonschema` (`certifica.sh` also looks for `~/maat-venv`) |
| `MAAT_PY_MINIMO` | `esempi-equiv.test.sh`, `certifica.sh` | an interpreter without `jsonschema` (first validator), when the one of `python.sh` has it |
| `MAAT_CERT_RICHIESTO=1` | `esempi-equiv.test.sh` | the strict check of `driver.equiv` (see «CI») |
| `MAAT_ESEMPI_DETERMINISMO=completo\|ridotto` | `esempi-equiv.test.sh` | the second build of the determinism case: the whole corpus (`completo`, default on Linux) or one mini-repo (`ridotto`, default elsewhere: a whole build costs about 15 minutes on Windows) |
| `MAAT_ORACOLO_TEST=completo\|ridotto` | `oracolo.test.sh` | the case with both sides from a git ref, on the whole corpus or on two small mini-repos (same defaults) |
| `MAAT_ORACOLO_REPO` | `oracolo.sh` | the repository the git refs are read from (default: this one) |
| `oracolo.sh --esiti <folder>` | `oracolo.sh` | keeps the records of each side and language (`<folder>/<side>-<language>/<project>/<spec>.txt`) |
| `oracolo.sh --motore bash\|predefinito` | `oracolo.sh` | the engine of `cycle-state.sh` on both sides: `FIC_DRIVER=0` (default) or unset |
| `--rigenera` with `MAAT_RIF_REPO` | `comandi-equivalenza.test.sh` | rewrites the frozen reference from the private history (see «The commands of the gates») |
| `ROLLBACK_TEST_RAPIDO=1`, `ROLLBACK_TEST_TIENI=1` | `rollback.test.sh` | scenario S1 only (+ the driver failure, counterproofs (a) and (d)); keep the temporary folder |
| `suite.sh --gruppo <k>/<n>` | `tools/suite.sh` | group k of `tools/suite-gruppi.list` only (CI, parallel run) |
| `MAAT_LINUX_CLONI`, `MAAT_PARALLELO_FORZA=1`, `MAAT_PARALLELO_LOCK` | `suite-parallelo.sh`, `giro-completo.sh --linux-parallelo` | the clones, one per group; skip the check of the processes; the lock file |
| `--linux-parallelo`, `--windows-breve` | `giro-completo.sh` | the Linux part in parallel; the short proof on Windows (`tools/prova-breve-windows.list`) |

### The old-against-new oracle (`tools/oracolo.sh`)

A check of each release, separate from the certificate: two versions of the plugin on the same projects, the output of
the resume table compared.

```bash
bash tools/oracolo.sh [--esiti <folder>] [--motore bash|predefinito] <old> <new> <project>…
```

- `<old>`, `<new>`: a plugin folder or a git ref of this repository (for example `v1.4.0` and `HEAD`).
  `<project>`: a project root with `.claude/.ai-workflow/`, for example a mini-repo of the examples built.
- The projects are never written: each side works on a fresh copy, and the two sides run in turn **in the same
  paths**, so the plugin root and the paths that appear in the output are the same by construction. For each side and
  language the valid `harness.fp` files are rewritten for that side (except the fixtures listed in
  `.claude/oracolo-conserva`), keeping their mtime.
- Compared, for every spec: in `it` the whole output of `cycle-state.sh`, `plan-check.sh basis` and `contract`; in
  `en` the `State`, the last code phase, the first word of `Next`, `basis` and `contract`. Last line `oracolo: spec=N ·
  it uguali=… · en uguali=… · diverse=…`, the diffs below. Exit 0 identical, 1 a difference, 2 usage.
- `--motore` (1.5.1) chooses the engine of `cycle-state.sh` on both sides. `bash` (the default, as in 1.5.0) sets
  `FIC_DRIVER=0`: it proves the bash table did not change. `predefinito` unsets `FIC_DRIVER`: each side decides as its
  users get it (1.5.1 always the Python driver; 1.5.0 the driver only with a VALIDO certificate), so it proves the real
  decider did not change. At each release both are run. At the top, one line per side, `oracolo: motore <m> ·
  certificato <side> <verdict>` (the verdict of `driver.py certificato` of that side): with `predefinito` an old side
  SCADUTO would decide with bash, and the comparison would lose its meaning. The line is informative and never changes
  the exit code.
- `tools/oracolo.test.sh` runs it on the examples (same plugin on both sides: identical) with five mutations that must
  be red (two of them, 1.5.1, check that `--motore` really changes the engine). About 6 minutes on Linux, about 70 in
  Git Bash: the full run sends it to WSL.

### Optional: the private corpus

Until 1.4.0 the reference proof was made on the real run dirs of a private project: 15 closed cycles and 83 jsonl.
It is no longer required. It is still worth doing when a release changes the **logic** of `next` or `valida`: real
data (agent prose, rare jsonl events, real lengths) can show a difference that nobody thought to model in the
examples. The certificate written stays the public one.

From the main folder of the project, **read-only**:

```bash
cd <project>
O=<temporary folder>; mkdir -p "$O/info" "$O/pack"   # git objects written by review-surface.sh tree
PYTHONDONTWRITEBYTECODE=1 GIT_OPTIONAL_LOCKS=0 GIT_OBJECT_DIRECTORY="$O" \
  GIT_ALTERNATE_OBJECT_DIRECTORIES="<project>/.git/objects" FIC_DRIVER_CERT=<temporary file> \
  "$FIC_PY" "<MAAT_ROOT>/scripts/driver.py" equiv --certifica .claude/.ai-workflow   # FIC_REPO not set
```

`review-surface.sh tree` runs `git add -A` and `write-tree` on a temporary index: without `GIT_OBJECT_DIRECTORY` the
objects would end up in the project's `.git`; `GIT_OPTIONAL_LOCKS=0` keeps git from updating the real index.

- Required outcome `diverse=0 · diversi=0`; a `DIVERSO` (different) is a STOP with the diff, it is not fixed by hand.
- Before and after, a snapshot (list and sha256) of `.claude/.ai-workflow/spec-*.md` and `.claude/.ai-workflow/*.run/`:
  it must be identical.
- The certificate goes to a temporary file (`FIC_DRIVER_CERT`) and is not copied into the plugin.

**On a copy of the project.** This keeps the real project completely out, not even read with the variables above:

1. **The copy:** a clone of the project branch in a temporary folder, with `git -c core.longpaths=true clone …`
   (on Windows the run dir paths exceed 260 characters), plus the specs and run dirs of **closed** cycles
   (`.claude/.ai-workflow/spec-*.md` and `*.run/`), copied from the project.
2. **Before:** snapshot (list and sha256) of the specs and run dirs of the real project.
3. **The proof:** the command above, run from the root of the **copy** (git objects in the temporary folder as
   above). Required outcome `diverse=0 · diversi=0`.
4. **After:** the same snapshot of the real project, identical to the one taken before.

Duration: about **3–4 hours on Windows**, almost all of it in the `review-surface.sh check` controls in bash, whose
cost grows with the size of the project's tree. The copy can be kept for the next time (only the plugin changes); if
the temporary folder has been emptied, it is redone, never on the project's tree.
