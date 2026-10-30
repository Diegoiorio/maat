# Changelog

Format: one section per version (`MAJOR.MINOR.PATCH`), most recent first.

## 1.2.1 — cost summary, Linux CI, what is proven

- **Cost summary at the end of every full cycle.** `phase-usage.py --summary <run dir>` prints total cost
  (API-equivalent), minutes, phases and 5h quota, then one row per phase; the final response of
  `/maat:full-implementation-cycle` carries it as printed, instead of figures copied by hand. The two lanes of a split
  implementation count as one phase (minutes = the longer lane); a review relaunched in the same log counts both
  sessions; a phase still running makes the total «at least»; a reset of the 5h window is stated. The output without
  `--summary` and the `--json` output do not change. Test: `scripts/phase-usage.test.sh`, with counterproofs.
- **Linux CI** on GitHub Actions (`.github/workflows/ci.yml`): every suite at every push and pull request, with
  Python 3.10. The suites are listed once, in `tools/suite.list`, read by the new `tools/suite.sh` (CI) and by
  `tools/giro-completo.sh`; `tools/suite.sh` refuses a list that misses a suite. `bash-node.test.sh` no longer
  drops from `PATH` the whole directory that holds `shellcheck` (on the CI runner, `/usr/bin`): it replaces it with a
  copy without `shellcheck`.
- **README:** «Verified AI development for Claude Code»; new sections «When to use Maat» and «What is proven and what
  is not», each claim with the file that supports it; CI badge. The same line opens the plugin and marketplace
  descriptions (the marketplace one was still in Italian).
- **Benchmark protocol** (`docs/BENCHMARK-PROTOCOL.md`), fixed before any run: does Maat complete a change on its own,
  and is the result better than Claude Code alone, measured first of all by the defects its own report does not
  disclose. Not run yet.
- `driver.py`, `cycle-state.sh` and `run-phase.sh` are unchanged: the driver certificate stays valid.

## 1.2.0 — English, explained permission requests, chain rings no longer stale

- **English everywhere except the formats:** documentation (README, flows guide, testing guide), code comments,
  agent and skill prompts, schema descriptions and help texts are now in English. Not yet translated, on purpose:
  runtime messages and the formats Maat reads (spec and plan headings, `.claude/maat.json` keys). They change in
  1.3.0, which will keep accepting the Italian forms.
- **English is the default language.** `lingua` in `.claude/maat.json` now defaults to `en` (was `it`), for the
  guard's reasons and for the explanations below. Set `"lingua": "it"` to keep Italian; `/maat:setup` writes `en`.
  Progress lines of a cycle follow the same setting; new specs are written in the language of the request
  (default English), with the parsed headings still in Italian.
- **Every permission request is explained.** A new `SessionStart` hook (`scripts/session-start.sh`) loads the
  command-description rule (`docs/descrizione-comandi.md`, now in English) into every session of the project, in
  the configured language: Claude writes, under each Bash or PowerShell command it asks to run, one sentence on what
  it does and where, the main commands, and a warning when the action cannot be undone or leaves the machine.
  Before, the rule applied only inside the Maat flows. Test: `scripts/session-start.test.sh`.
- **Fix: rings k>1 of a chain no longer stay STALE.** Reviewers write the files of previous rings in `Excluded:`
  with a note (`<path> — stessa catena, anello precedente (<spec>)`); the note made the path match no file, so those
  files counted as new surface, the ring stayed STALE and the driver stopped on its anti-loop even with an
  APPROVED review. `cycle-state.sh` and `review-surface.sh` (`read_paths`, the single reader, also for manual
  `/maat:implementation-review-cycle` runs) now drop the note after « — »; the reviewer instructions state the
  format `<path> — <reason>`. Tests in `cycle-state.test.sh` and `test-review-surface.sh`, red without the fix.
- The driver certificate (`scripts/driver.equiv`) is regenerated: `driver.py`, `cycle-state.sh` and
  `run-phase.sh` changed (comments and the fix above).

## 1.1.0 — first public release

First published release, under the MIT license. The plugin code is that of 1.0.0, used privately until now; for
publication the license, author, examples and test data change.

- **MIT license**, author Diego Iorio; a «Disclaimer» section in the README.
- **Examples and tests without data from real projects:** test hosts, IP addresses and paths are fake (`example.com`,
  `example.org`, `example.internal`, RFC 5737 documentation addresses and private networks). The examples are named
  `examples/nuxt-fastapi.maat.json` and `examples/bash-node.maat.json`; the guard fixture
  `tests/guard-esempio.cases`; the suite `scripts/bash-node.test.sh`.
- **`genericita.test.sh`:** the proper names of the guide project are read from an untracked local file
  (`.genericita-nomi`, or `MAAT_NOMI_RISERVATI`); the counterproofs use a fake name.
- **`tools/giro-completo.sh`:** the full run of the suites (Linux, then Windows), with mandatory worktree and branch.

### What it contains

- **Full cycle** `/maat:full-implementation-cycle <spec>`: plan reviewed until approved, implementation,
  independent review, fixes, sign-off (`IMPLEMENTED`, `NEEDS_VERIFICATION` or `STOP` with the reason). Each phase in a
  separate subsession; automatic resume by running the same command again; spec chains; `--worktree`.
- **Single cycles:** `/maat:plan-review-cycle`, `/maat:plan-review-cycle-light`, `/maat:implementation-review-cycle`.
- **Guided setup** `/maat:setup` and **diagnostics** `scripts/maat-doctor.sh`.
- **Per-project configuration** in `.claude/maat.json` (modules, test and lint commands, guard, paths not to
  touch), with a schema, ready-made profiles and examples.
- **Session and phase guard:** blocks production, git that changes state, installations, remote access.
- **Gates and counterproofs:** the tests chosen for the touched files, mutation counterproofs, sign-off with the
  evidence.
- **Python driver** certified equivalent to the bash code on real cycles (`scripts/driver.equiv`).
- **Platforms:** Windows with and without WSL, Linux; paths with spaces and accented letters.
- **Documentation:** README, flow guide (`docs/GUIDA-FLUSSI.html`), test guide (`docs/TESTING-harness.md`),
  flow H for developing Maat (`.claude/skills/flusso-h/`).
