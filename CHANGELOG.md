# Changelog

Format: one section per version (`MAJOR.MINOR.PATCH`), most recent first.

## 1.5.1 — the Python driver always decides; bash only on request

**Why a patch:** with an intact plugin a cycle does and prints the same as 1.5.0: the certificate was VALIDO, so the
driver already decided. What changes is what happens when something is wrong.

- **The driver decides** `next` and `valida`, always. The bash table of `cycle-state.sh` and the internal validator
  of `run-phase.sh` decide only with `FIC_DRIVER=0`:

  | `FIC_DRIVER` | 1.5.0 | 1.5.1 |
  |---|---|---|
  | unset or empty | certificate VALIDO → Python, otherwise bash | Python |
  | `1` | Python | Python (the same as the default) |
  | `0` | bash | bash |
  | any other value | the certificate decides | Python, with a line `AVVISO: FIC_DRIVER=<value> …` |

  The choice is the same in the three places (`cycle-state.sh`, `run-phase.sh` for `valida`, `driver.py run`) and it
  is inherited: in one invocation one engine decides. With `FIC_DRIVER=0`, `driver.log` says `motore bash` at the
  first entry into each spec.
- **No silent fallback.** A driver that fails, no Python, or a Python older than 3.10 now give a `STOP` with the
  reason and the remedy, instead of the bash code with a warning. The Python check holds with either engine, also
  with `FIC_DRIVER=0` (the bash table needs Python too); its remedy is `FIC_PYTHON=<python 3.10 or newer>`. The remedy
  of a failed driver is `FIC_DRIVER=0`. A failed `valida` leaves no `result.json` behind. Inside `run-phase.sh` the
  four readers of `cycle-state.sh` see such a `STOP` (it is the only output without a `State:` line): a phase not
  launched (exit 7, at the start and at the review of a ring) or a `STOP` outcome (at the end of a phase and of the
  `chiusura`), never an `OK` outcome with an empty `state=`.
- **The certificate no longer switches anything at runtime.** `driver.equiv` is the proof, at each release, that the
  fallback is equivalent to the driver. The strict check in CI does not change (VALIDO on `main`, on tags and on pull
  requests to `main`). `driver.py certificato` still shows its status. Its header still says that the wrappers call
  the driver only with valid hashes: that was the 1.5.0 behaviour, and the header is a frozen line, rewritten in 1.5.2.
- **Going back to bash in the middle of a cycle, and forth again, needs no confirmation:** `FIC_DRIVER` is not part
  of the harness fingerprint. `plugins/maat/scripts/rollback.test.sh` proves it with the real `run-phase.sh`: a cycle
  started with one engine and resumed with the other, after each phase that writes to disk, continues with the same
  run dirs, the same `harness.fp`, the same `Next` and the same end, in both directions (17 resumes, plus five
  counterproofs). **Limit:** it covers a format-1 cycle (plan, implement, review, fix) and a STOP with its recovery,
  in Italian. The rollback is not proven on a chain (mother and rings) nor on a format-2 cycle with lanes, nor in
  English: there the equivalence of the two engines rests on `driver.equiv` and on the old-against-new oracle.
- **Oracle:** `tools/oracolo.sh --motore bash|predefinito` (default `bash`, the 1.5.0 behaviour: `FIC_DRIVER=0` on
  both sides, it proves the bash table did not change). `predefinito` unsets `FIC_DRIVER`, so each side decides with
  its default engine: it proves the real decider did not change. At the top one line per side shows the verdict of
  its certificate (informative, it never changes the exit code).
- **Faster proofs.** The CI runs the suites in three jobs at the same time, one per group of `tools/suite-gruppi.list`
  (`tools/suite.sh --gruppo <k>/<n>`); the check «linux» is green only when all three are, and each job has a limit
  of 30 minutes instead of 45 for the single job. On a Linux machine, `tools/suite-parallelo.sh` runs the same groups
  on three clones at once and runs a suite red in parallel again alone before calling it red; it does not start while
  `tools/certifica.sh` or a Maat cycle on Windows is running. `tools/giro-completo.sh` gains `--linux-parallelo` and
  `--windows-breve`: the short proof on Windows, `tools/prova-breve-windows.list`, about 50 minutes in Git Bash
  instead of the whole Windows part.
- **Proof of compatibility:** TODO blocco I — certificate rewritten (hashes of the four certified files touched:
  `driver.py`, `cycle-state.sh`, `run-phase.sh`, `messages.tsv`; same corpus, same fingerprint `6b484b23826a`); oracle
  1.5.0 against 1.5.1 with both engines; `rollback.test.sh` on Linux and the short proof on Windows; the full run on
  Linux.
- **Upgrading:** as with every release, a cycle in progress stops with «harness changed». Remedy:
  `bash "<MAAT_ROOT>/scripts/run-phase.sh" --harness-fp > <run dir>/harness.fp`, then run the cycle again; from then
  on the driver decides. Who set `FIC_DRIVER=0` keeps bash. Who had modified the plugin by hand (certificate SCADUTO)
  now gets the driver; before, bash in silence. Any other value of `FIC_DRIVER` now prints an `AVVISO`.
  `FIC_DRIVER_CERT` no longer affects the wrappers nor `run` (it stays for `certificato`, `equiv` and
  `tools/certifica.sh`). A Python 3.8 or 3.9, outside what is supported, now stops the cycle.
- **Roadmap:** 1.5.2 removes the bash code (after a period without regressions and one real minimal cycle on
  Windows); 1.5.3 multi-platform CI, with the Windows proof that today runs by hand.

## 1.5.0 — the driver certified on public examples, reproducible

**Why 1.5.0 and not a patch:** the proof behind the driver certificate changes nature. Until 1.4.0 it was made on 15
closed cycles of a private project, which nobody else could run again. Now it is made on public examples in this repo,
anyone can repeat it in a few minutes, and the CI repeats it at every push. The format of the certificate changes
(its `corpus` line says on which examples and with which validators), and `driver.py equiv` prints new lines. What a
cycle does and prints does not change, with one exception: `MAAT_LINGUA` set by hand now reaches WSL (below).

- **Public examples:** `tools/esempi-equiv/`, seven small git repositories built from models by
  `tools/esempi-equiv/costruisci.sh`: 65 specs and 49 jsonl, in the Italian 1.2.x and the English 1.3+ formats,
  single cycles and chains. Two closed lists say what they cover: `righe.list`, every row of the resume table of
  `cycle-state.sh` (49 labels), and `rami-valida.list`, every branch of the outcome validator and every phase (28
  labels). `tools/esempi-equiv.test.sh` fails if a label has no case, if a spec changes its word of `Next`, if a
  counted jsonl is empty, or if no jsonl labelled with a branch really goes through it (`run-phase.sh --valida`
  against the expectation written in `rami-valida.list`). The builder is deterministic (no git configuration of the machine, fixed identity, dates,
  permissions and line endings). The test checks it on the same machine, in two folders and at two different seconds:
  on Linux two builds of the whole corpus give the same fingerprint; on Windows (a whole build costs ~15 min) the
  check is reduced to the one mini-repo whose files carry the sha of the base commit, built again against its
  fingerprint in the first build. Across platforms it was compared by hand for this release: a whole build in Git
  Bash on Windows and one on Linux give the same fingerprint (`6b484b23826a`).
- **The certificate in one command:** `bash tools/certifica.sh` builds the examples and proves the driver on them;
  `--scrivi` also writes `plugins/maat/scripts/driver.equiv`, from Linux only. The `corpus` line gains, at its end,
  ` · impronta <12 hex> · validatori minimo,jsonschema`: the fingerprint of the examples and the validators proven
  (the part before is that of 1.4.0).
- **Two validators:** the outcome validator uses `jsonschema` when the interpreter has it, a minimal one otherwise.
  Both are now proven, in CI too (a venv with `jsonschema==4.23.0`). Writing the certificate needs both interpreters;
  preparing them is a one-time installation, described in `docs/TESTING-harness.md`.
- **Strict check in CI:** on pushes to `main`, on tags and on pull requests to `main`, the certificate must be VALIDO
  and carry the fingerprint of the examples. A pull request to `main` that touches a certified file (`driver.py`,
  `cycle-state.sh`, `run-phase.sh`, `messages.tsv`, `maat-msg.sh`, `maat_msg.py`) or changes the examples is red
  until it also commits the certificate rewritten with `tools/certifica.sh --scrivi`. Other branches: no strict check.
- **Warnings of `equiv`:** for each spec whose `Next` is not `DONE`, a line `equiv: AVVISO — …` says what the proof on
  it covers (the row that decides that word; only the fingerprint branch, when its `harness.fp` is not `UGUALE`).
  Each pass ends with `equiv: aperte=<n> · impronta-non-uguale=<k>`, after the summary line, which does not change.
  The warnings do not block `--certifica`. `driver.py equiv --impronta <folders>` prints only the fingerprint.
- **`MAAT_LINGUA` reaches WSL:** `run-phase.sh` adds it to `WSLENV`, so a value set by hand also reaches the commands
  that the phase session and each lane run in `wsl`. Before, inside WSL the `lingua` of `.claude/maat.json` was read
  again; it mattered only when the two differed.
- **The old-against-new oracle is in the repo:** `bash tools/oracolo.sh <old> <new> <project>…` compares two
  versions of the plugin (folders or git refs) on the same projects, in `it` and in `en`, without writing them;
  `tools/oracolo.test.sh` runs it on the examples.
- **`comandi-equivalenza.test.sh` runs again.** It compares the commands of the gates with a reference harness of the
  private history, and since 1.1.0 it was skipped everywhere that history was missing. The reference side is now
  frozen in `plugins/maat/tests/comandi-equivalenza/riferimento.txt`, with no value of the machine in it: the test
  runs in WSL and on Linux, in CI included.
- **More checks in the suites:** section 10 of `messages.test.sh` runs `lingua-converti.py copertura` and `check` on
  the conversion tables (not skipped in CI); section 9 of `driver.test.sh` compares driver and bash in both languages
  at every call, and a comparison where a side prints no `Next:` line fails.
- **Guard of the full run:** `tools/giro-completo.sh` and `tools/suite.sh` mark `PLUGIN CAMBIATO` when a file of the
  plugin changes during the run, and `giro-completo.sh` warns when the Linux clone and the worktree are not the same
  tree. `tools/suite.list` accepts the tests of the repo (`tools/<name>.test.sh`).
- **Times:** on Linux the proof on the examples takes about 2 minutes. In Git Bash on Windows it is slow
  (`tools/esempi-equiv.test.sh` from about 1 to 1 h 45 min, the oracle on the examples about 70 min): the examples
  are kept whole, the certificate is written from Linux, and in the Windows part of the full run the oracle runs in
  WSL. `tools/esempi-equiv.test.sh` stays in Git Bash there: it is the proof for Windows. In Git Bash
  `tools/giro-completo.sh` now gives each suite up to 5 hours instead of 90 minutes (`driver.test.sh` took about
  4 hours there for this release).
- **Proof of compatibility:** the certificate on the public examples is VALIDO in `it` and `en` with both
  validators (65 specs, 49 jsonl, no difference; minimal validator 155 s, `jsonschema` 175 s on Linux). The oracle
  1.4.0 against 1.5.0 gives the same `Next` for all 65 specs of the examples, in `it` and in `en`. On the private
  corpus of 1.4.0, proven once more for this release: the oracle gives 15 specs equal out of 15 in both languages,
  and `driver.py equiv` finds no difference (15 specs, 83 jsonl), but its new warnings say that all 15 cycles are
  open and 11 have a `harness.fp` that is not `UGUALE`: on those the two sides stop on the same branch, so that
  corpus proves less than it seemed. The public examples are now the proof that counts.
- **Upgrading:** as with every release, a cycle in progress stops with «harness changed». Remedy:
  `bash "<MAAT_ROOT>/scripts/run-phase.sh" --harness-fp > <run dir>/harness.fp`, then run the cycle again.

## 1.4.0 — runtime messages in English, `"lingua": "it"` keeps them Italian

**Why 1.4.0 and not a patch:** the output changes for whoever has no `lingua` in `.claude/maat.json`. The messages
that the scripts print for a person are now **English by default**: the text after `STOP — `, the explanation after
`VIOLAZIONE` and `AVVISO`, usage errors, remedies, progress lines, the reports of `maat-doctor`, `cycle-report` and
`phase-usage`. **Remedy, to keep Italian:** add `"lingua": "it"` to `.claude/maat.json`; the output is then byte for
byte the one of 1.3.0. No behaviour changes: only the text.

- **The language:** `MAAT_LINGUA` (`it` or `en`, for one command or a test run) wins over `"lingua"` of
  `.claude/maat.json`, which wins over the default `en`. `guard.py` follows the same order. This is what the 1.3.0
  entry announced for «1.3.1»: it happens here, in 1.4.0.
- **One catalog:** `scripts/lib/messages.tsv` (`key<TAB>en<TAB>it`), read by `lib/maat-msg.sh` (bash) and
  `maat_msg.py` (Python) with the same bytes. A missing key or catalog prints the key between `‹ ›` and one warning on
  stderr; the exit code does not change.
- **Frozen on purpose** (the same in every language, listed with their reason in
  `scripts/lib/protocol-strings.list`): a protocol prefix stays, the human text after it follows the language.

| what | examples |
|---|---|
| the whole stdout of `plan-check.sh basis` (it enters `State`) and of `contract` (its keys are read by the skills) | `Catena: anello k/n di …`, `Recorded: assente`, `Superfici a rischio:`, `Pavimento:` |
| chain state, closing line, lines of `cycle-state.sh` read by other scripts | `assente;` `chiuso;` `aperto;`, `Chiusura: IMPLEMENTED — `, `Base anello:`, `STOP — catena`, the step word `CHIUSURA` of `Next:` |
| harness fingerprint and lock tokens | `UGUALE` `CAMBIATO` `ILLEGGIBILE` `NON-CALCOLABILE`; `--lock-status`: `libero` `occupato` `dentro il ciclo` `sconosciuto` |
| `key: esito=` lines, block lines, plan fingerprint, markers inside the prompts | `rossi: esito=`, `posteriori: esito=`, `blocco <id>: scrive=… · dopo=…`, `Impronta piano:`, `EVIDENZE DEI GATE`, `DEVIAZIONI DIFENSIVE` |
| values read by another script | `(assente)`, `(nessuno)`, `nessuna`, `(vuoto)`; the prefixes `finalize non eseguito (` / `finalize fallito (`, `modo=`, `scartato: ` |
| driver certificate output | `UGUALE` / `DIVERSO`, `certificato: VALIDO\|ASSENTE\|SCADUTO` |
| identifiers | keys and values of `.claude/maat.json`, run dir file names, sub-commands, the phase name `chiusura` |

- **Keywords that stay Italian:** `VIOLAZIONE`, `AVVISO`, `ERRORE DURO`, `Percorso:`, `Scheletro:`, `S2:` are read by
  the skills and the tests, so they do not change; the explanation after them follows the language. Moving them to
  English, with both forms read, is a separate change.
- **Read in both languages:** where one script reads the message of another, the reader accepts the Italian and the
  English form («python non trovato» / «python not found», «non coperto» / «not covered»). `maat-doctor` prints
  `OK` · `WARNING` · `MISSING` in English, `OK` · `ATTENZIONE` · `MANCA` in Italian. The `STOP — ` classes of
  `cycle-report` recognise the English texts too; on the Italian texts they give the same class as in 1.3.0.
- **Lines written into the spec** (`Verification:`, `Finalize:`, the requirement evidence) follow the language; their
  prefixes stay, and every reader reads lines written in either language.
- **Unchanged:** the header and the values of `metrics.csv`, the keys and values of the JSON of `cycle-report`, the
  keys of the phase result JSON and of `.claude/maat.json`.
- **Prompts:** where a prompt quotes a message that now follows the language, it quotes both forms. The agents write
  their free text (after `STOP — `, in the reports) in the language of `lingua`, like the `▶ ` lines; the report
  keywords stay those of 1.3.0.
- **The language is part of the harness fingerprint** (the resolved one: `MAAT_LINGUA`, otherwise `lingua`).
  Changing `lingua`, or running with another `MAAT_LINGUA`, in the middle of a cycle stops it with «harness
  changed», like any change of the harness. The key of the gate evidence contains the translated reasons, so after a
  change of language some gates run again.
- **Tests:** every suite runs with `MAAT_LINGUA=it` and keeps its Italian assertions; English cases are added next
  to them. `scripts/messages.test.sh` checks the catalog and the anti-leak rule: no literal that its scanner recognises
  as Italian in a plugin script outside the catalog and `protocol-strings.list` (in the repo only: installed in the
  cache, that part is skipped). `tools/lingua-inventario.py` measures what is left
  (`docs/TESTING-harness.md`, «The two languages»).
- **Driver certificate:** it also covers `messages.tsv`, `lib/maat-msg.sh` and `maat_msg.py`, and `driver.py equiv`
  runs the proof in both languages.
- **Proof of compatibility:** on the 15 closed cycles of the driver certificate (all Italian), the 1.3.0 code and
  the 1.4.0 code with `MAAT_LINGUA=it` give the **whole** `cycle-state.sh` output and the output of `plan-check.sh
  basis` and `contract` identical, cycle by cycle; with `MAAT_LINGUA=en` the `State`, the last code phase, the step
  of `Next`, `basis` and `contract` are identical (each side run from its own plugin tree, with the harness
  fingerprint of the run dirs regenerated for that tree and language). The driver certificate is regenerated in both
  languages: `spec=15 diverse=0 · jsonl=83 diversi=0` in each.
- **Roadmap:** what was planned as 1.4.x moves to 1.5.x: multi-platform CI is now 1.5.3, and the benchmark comes
  after it.
- **Upgrading:** as with every release, a cycle in progress stops with «harness changed». Remedy:
  `bash "<MAAT_ROOT>/scripts/run-phase.sh" --harness-fp > <run dir>/harness.fp`, then run the cycle again. Set
  `"lingua"` **before** recording the fingerprint, or the next change of language stops the cycle again.

## 1.3.0 — formats in English, Italian still read

The formats that people and agents write and Maat reads are now written in English. Every reader accepts **both**
forms, so specs, approved plans and run dirs made with earlier versions keep working without changes.

| Italian (still read) | English (written from now on) |
|---|---|
| `## Piano di implementazione` · `## Review implementazione` · `### Changelog revisione piano` | `## Implementation plan` · `## Implementation review` · `### Plan review changelog` |
| `### Piano di test` · `Tracciabilità requisiti` · `File toccati` · `Passi` · `Decisioni` · `Stringhe e data-test` | `### Test plan` · `Requirement traceability` · `Touched files` · `Steps` · `Decisions` · `Strings and data-test` |
| `#### Blocco` · `scrive:` · `dopo:`, table headers and cells (`asserzione`, `rosso se:`, `(nuovo)`, `verificato`…) | `#### Block` · `writes:` · `after:`, `assertion`, `red if:`, `(new)`, `verified`… |
| `Superfici a rischio:` (`permessi dati contratto-api …` / `nessuna`), `[pavimento: …]`, `⚠️ Rischio aperto` | `Risk surfaces:` (`permissions data api-contract …` / `none`), `[floor: …]`, `⚠️ Open risk` |
| `Figlie:` · `Dipende da:` · `Interfaccia per:` · `Taglio: rifiutato` | `Children:` · `Depends on:` · `Interface for:` · `Split: rejected` |
| `Requisiti funzionali` / `Criteri di accettazione`, ids `RF1` / `CA1` | `Functional requirements` / `Acceptance criteria`, ids `FR1` / `AC1` |
| `ESITO FASE <fase>: OK\|STOP — …` · `Esito driver:` (`OCCUPATO`, `IN CORSO`) | `PHASE RESULT <phase>: OK\|STOP — …` · `Driver result:` (`BUSY`, `RUNNING`) |
| agent report lines (`Esito:`, `Deviazione dal piano:`, `Bloccato su:`…), `difensiva: `, `(provvisorio: …)`, `nessuno` | `Result:`, `Plan deviation:`, `Blocked on:`…, `defensive: `, `(provisional: …)`, `none` |

- **Existing sections keep their heading**: the prompts write English only for sections they create. The same
  section in both languages is an error (plan-check violation; a spec with both review headings stops the cycle).
- A child spec uses the id family of its parent; `RF1` and `FR1` are different ids.
- **Don't translate an approved plan**: the headings are part of its fingerprint, the approval would expire.
- **Unchanged on purpose:** the lines that scripts pass to each other, the run dir file names, the keys of the phase
  result JSON and of `.claude/maat.json`, the `metrics.csv` header. The text after `STOP — ` and the other runtime
  messages are still Italian, so a line can be mixed (`PHASE RESULT implement: STOP — …` in Italian): they become
  English in 1.3.1.
- **Proof of compatibility:** the Italian test fixtures all stay; English twins give the same results. On the 15
  closed cycles used for the driver certificate (all in the Italian format) the 1.2.1 code and the 1.3.0 code give
  the same `State`, `Next` and plan checks, cycle by cycle (each side run from its own plugin tree, with the harness
  fingerprint of the run dirs regenerated for that tree) (`MAAT_ORACOLO_121=1` runs the same comparison on the
  plan-check fixtures). The driver certificate is regenerated.
- **Upgrading:** as with every release, a cycle in progress stops with «harness changed». Remedy:
  `bash "<MAAT_ROOT>/scripts/run-phase.sh" --harness-fp > <run dir>/harness.fp`, then run the cycle again.

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
