# Test del harness

Vale per il plugin `plugins/maat` di questo repo: come si lanciano le suite su Windows e su Linux, il test di
genericità e il certificato del driver.

## Le due radici

| variabile | cos'è | come si risolve |
|---|---|---|
| `MAAT_ROOT` | la radice del plugin (`scripts/`, `skills/`, `agents/`, `schemas/`) | `MAAT_ROOT` dell'ambiente, altrimenti due livelli sopra `scripts/lib/maat-paths.sh`; deve contenere `.claude-plugin/plugin.json`, altrimenti uscita 4 |
| `PROJECT_ROOT` | la radice del progetto su cui lavora il ciclo | `FIC_REPO`, altrimenti `git rev-parse --show-toplevel` dalla **cartella di lavoro** (mai dalla posizione dello script); fuori da un repo git: errore chiaro, uscita 4 |
| `MAAT_SCRIPTS`, `MAAT_SKILLS`, `MAAT_AGENTS`, `MAAT_SCHEMAS` | sotto `MAAT_ROOT` | — |
| `MAAT_WORK` | la cartella di lavoro del progetto | `PROJECT_ROOT/<cartelle.lavoro>` di `.claude/maat.json` (default `.claude/.ai-workflow`) |

Il risolutore è uno solo: `scripts/lib/maat-paths.sh` (bash, incluso con `.`) e `scripts/maat_paths.py` (Python, stesse
regole). Lanciato direttamente, ciascuno stampa le variabili una per riga, nella forma `NOME=valore`:

```bash
cd <progetto> && bash <plugin>/scripts/lib/maat-paths.sh
```

Il lock delle fasi di codice **non** usa `PROJECT_ROOT`: `run-phase.sh` lo calcola con `git rev-parse --absolute-git-dir`
dalla cartella di lavoro (in un worktree collegato è quello del worktree). `FIC_LOCK` lo sostituisce.

## Variabili d'ambiente di override

Restano i nomi di prima; cambia solo il default.

| gruppo | variabili | default |
|---|---|---|
| radice del harness | `FIC_GATES_HARNESS` (gates.sh, finalize.sh), `CONTEXT_PACK_HARNESS`, `HARNESS_MERGE_HARNESS`, `FIC_DRIVER_ROOT` | `MAAT_ROOT` |
| repository da leggere | `FIC_GATES_ROOT`, `CONTEXT_PACK_ROOT` | `PROJECT_ROOT` |
| plugin nella sotto-sessione | `MAAT_PLUGIN_DIR` | assente: nessun `--plugin-dir` (il plugin è abilitato nel progetto); `replay.sh` la imposta sempre |
| repo e lock | `FIC_REPO`, `FIC_LOCK` | toplevel della cartella di lavoro · git dir della cartella di lavoro |
| componenti del ciclo | `FIC_RUN_PHASE`, `FIC_CONTEXT_PACK`, `FIC_GATES`, `FIC_FINALIZE`, `FIC_DRIVER_PY`, `FIC_DRIVER_CERT`, … | gli script del plugin |
| altro | `PLAN_CHECK_ROOT`, `CLAUDE_BIN`, `FIC_PYTHON`, `MAAT_CONFIG` | — |

Sotto una radice del harness sostituita vale la struttura del plugin: una copia mutata del plugin (controprove dei
test) si passa intera, non solo uno script.

## Come lanciare le suite dal plugin

Ogni suite crea i propri repo sintetici in una cartella temporanea e non tocca né il repo del plugin né un progetto
vero. Da Git Bash:

```bash
bash plugins/maat/scripts/<nome>.test.sh
```

- Brevi: `maat-paths`, `maat-config`, `gates`, `finalize`, `ciclo-worktree`, `context-pack`, `cycle-report`,
  `harness-merge`, `guard`, `stop-hook`, `blocks-independent`, `phase-events`, `test-review-surface.sh`, `plan-check`,
  `senza-wsl` (pk08: Windows senza WSL, PATH senza `wsl`/`wsl.exe`; circa 5 minuti, due fasi di `run-phase.sh`),
  `spazi` (pk08: plugin, progetto, run dir e worktree con spazi e «à»; circa 5 minuti su Windows, 1 su Linux; anche su
  Linux, dal clone in WSL con `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin FIC_WT_WSL=0`).
- Lunghe (da lanciare insieme, in background): `cycle-state`, `run-phase`, `driver` (la sezione 9 di `driver.test.sh`
  porta tutto `cycle-state.test.sh`; `DRIVER_TEST_RAPIDO=1` la salta).
- In WSL: `test-fast.test.sh`, `vitest-classify.test.sh`, `counterproof.test.sh`. `comandi-equivalenza.test.sh`
  usa git dentro WSL: da un worktree creato da Windows non gira (il suo `.git` punta a `C:/`, che il git di Linux non
  risolve); si lancia da un clone in WSL (`git clone -b <ramo> /mnt/c/…/maat ~/maat-linux`).
- Saltate con motivo dichiarato (specifiche del progetto guida): la parte 2 di `vitest-classify.test.sh`.
  `guard.test.sh` (pk05) prova l'hook del plugin (`guard-hook.sh`) e l'equivalenza con la guardia del progetto guida
  sulla fixture `tests/guard-esempio.cases`.
- `maat-paths.test.sh` contiene anche la **ricerca anti-struttura**: nessun riferimento alla struttura del progetto guida
  (`.claude/skills/`, `script/fic`, `script/test`, `$HERE/../..`, `/../test`, `/../../../script/`) fuori da commenti e
  test, con le esclusioni dichiarate nel test (comandi di progetto dei wrapper WSL fino a pk04b; quella
  dell'impronta l'ha chiusa pk04a-2).

## Windows e Linux

**Windows** (Git Bash, dal worktree o dal clone su `C:`): `bash plugins/maat/scripts/<nome>.test.sh`, una suite alla
volta. Le tre suite di WSL (`test-fast`, `counterproof`, `vitest-classify`) si lanciano da WSL sulla stessa cartella:

```bash
wsl -- bash -lc 'cd /mnt/c/<…>/maat && bash plugins/maat/scripts/test-fast.test.sh'
```

**Linux.** Non c'è una macchina Linux dedicata: si usa un **clone dentro WSL** con un PATH Linux puro, così nessuno
strumento di Windows (`cmd.exe`, `wsl.exe`, `py.exe`, il Python dello Store) entra nel test.

```bash
wsl -- bash -lc 'git clone -b <ramo> /mnt/c/<…>/maat ~/maat-linux'      # una volta; poi git fetch e reset sul ramo
wsl -- bash -lc 'cd ~/maat-linux && PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin FIC_WT_WSL=0 \
  timeout 5400 bash plugins/maat/scripts/<nome>.test.sh'
```

- `FIC_WT_WSL=0` dice ai test dei worktree di non passare da WSL: su Linux sono già a casa loro.
- Il clone va riallineato al ramo prima di ogni giro (le copie a mano di file spariscono): niente modifiche dentro il
  clone.
- `comandi-equivalenza.test.sh` gira **solo** dal clone Linux: il `.git` di un worktree creato da Windows punta a `C:/`.

**Il giro completo** (tutte le suite, prima Linux poi Windows, una alla volta, con un riepilogo per piattaforma):
`bash tools/giro-completo.sh <cartella esiti> <worktree> <ramo>`, da Git Bash. `<worktree>` è la cartella Windows
del ramo da provare, in forma `/c/…`; `<ramo>` è il ramo su cui si riallinea il clone Linux, che è sempre
`~/maat-linux` (un altro con `MAAT_LINUX_CLONE`). Per esempio: `bash tools/giro-completo.sh /tmp/esiti /c/<…>/maat-lavoro wip/lavoro`. Ogni suite scrive
`<cartella>/<linux|windows>/<nome>.log` e una riga in `riepilogo.txt` (codice d'uscita, secondi, ultima riga). Durata:
alcune ore, per le suite lunghe.

## Genericità

`genericita.test.sh` (Git Bash o WSL) controlla che il plugin non porti con sé il progetto guida.

1. **Nucleo** (`scripts/`, `skills/`, `agents/`, `hooks/`, `schemas/`): nessuno dei nomi del progetto guida (percorsi,
   servizi, `.nuxt`, …), fuori dalle fixture dei test e dalle eccezioni dichiarate nel test, ognuna con il suo motivo.
   Un'eccezione che non copre più nessuna riga è un FAIL. Le righe dei runner (`junitxml`, `--reporter=json`) stanno
   solo nei profili e negli esempi.
2. **Documentazione** (`docs/` del repo, tranne `docs/piani/`; `README.md` del repo e del plugin): nessun nome del
   progetto guida. Eccezione: i nomi di file veri del plugin (`guard-esempio.cases`, `nuxt-fastapi.maat.json`).
   I nomi propri del tuo progetto guida (nome, host, servizi) non stanno nel repo: mettili, uno per riga come
   alternative regex, nel file locale `.genericita-nomi` alla radice del repo (ignorato da git), o indica un altro
   file con `MAAT_NOMI_RISERVATI`. Senza il file il test controlla solo i nomi generici e un nome finto, usato dalle
   controprove.
3. **Link della guida:** ogni `href` interno di `docs/GUIDA-FLUSSI.html` porta a un'ancora (`id`) che esiste nella
   pagina o a un file che esiste accanto alla guida. `http(s):`, `mailto:` e `data:` non si controllano. Solo grep e
   test di esistenza: nessun link-checker da installare.
4. **Controprove per mutazione**, su copie: un nome del progetto guida in un commento di `gates.sh` ⇒ rosso; un nome in
   una copia della guida ⇒ rosso; un `href` verso un file inesistente o un'ancora inesistente ⇒ rosso; la copia
   ripristinata torna verde.

## L'istantanea di `MAAT_ROOT`

Il plugin non deve mai ricevere file del progetto. `maat-paths.test.sh` (sezione 8) lavora su una **copia** del plugin e
ne prende un'istantanea prima e dopo (ogni file con il suo sha256, compresi i file nuovi e quelli cancellati): una
differenza fa fallire la suite. Si usa l'istantanea e non `chmod -R a-w`, che su Windows/MSYS non impedisce di creare
file. I sorgenti Python impostano `sys.dont_write_bytecode = True` prima di importare `maat_paths`, così sotto il
plugin non nasce `__pycache__`.

```bash
snap() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }
```

## L'impronta del harness (pk04a-2)

Al primo lancio di un ciclo `run-phase.sh` scrive `<run-dir>/harness.fp`, tre righe:

```text
impronta=<64 esadecimali>
versione=<version di .claude-plugin/plugin.json>
radice=<MAAT_ROOT, forma C:/…>
```

- **Cosa entra:** ogni file sotto `MAAT_ROOT` (percorso relativo, ordine `LC_ALL=C`, sha256 del contenuto senza CR)
  tranne l'elenco unico `HARNESS_EXCLUDE` di `run-phase.sh` — `__pycache__`, `assets`, `*.swp`, `*.orig`,
  `.DS_Store`, `*~`, confrontati con ogni componente del percorso — più `<progetto>/.claude/maat.json` (assente: una
  riga fissa, così crearlo o cancellarlo cambia l'impronta). Niente git e niente `.gitignore`: un file estraneo
  lasciato nella cartella del plugin (per esempio un `.bak`) ferma i cicli. Le skill del **progetto** (per esempio
  `dev-verify`) non ne fanno parte: una loro modifica non ferma un ciclo.
- **Chi decide:** una funzione sola, `run-phase.sh --harness-fp-confronta <harness.fp> [<repo>]`, usata da
  `run-phase.sh` (exit 6), `cycle-state.sh` e `driver.py next` (`Next: STOP — …`). Stampa una riga: `UGUALE`,
  `CAMBIATO <reg> <att>`, `FORMATO-PRECEDENTE <reg> <att>` (una riga sola di 64 esadecimali: ciclo iniziato col
  harness interno), `ILLEGGIBILE <att>` (vuoto, troncato, senza impronta) o `NON-CALCOLABILE`. Solo `UGUALE` lascia
  andare avanti; `versione=` e `radice=` non contano (lo stesso plugin da un'altra cartella dà `UGUALE`).
- **Diagnosi:** `run-phase.sh --harness-paths` elenca i file che entrano nell'impronta.

**Confermare un cambio voluto.** Il messaggio di STOP stampa il rimedio a percorso assoluto; lanciato dalla cartella
del progetto riscrive il file nel formato nuovo:

```bash
bash "<MAAT_ROOT>/scripts/run-phase.sh" --harness-fp > "<run-dir>/harness.fp"
```

Fuori da un repository il comando esce con 1 e lascia il file **vuoto**: il ciclo resta fermo (`ILLEGGIBILE`).

## Ricertificare il driver (`driver.equiv`)

`driver.equiv` porta l'hash di `driver.py`, `cycle-state.sh` e `run-phase.sh`: se uno dei tre cambia, il certificato
è scaduto e gli involucri ripiegano sul codice bash (funziona, è solo più lento). Si ricertifica sulle run dir vere di
un progetto, dalla sua cartella principale e **in sola lettura**:

```bash
cd <progetto>
O=<cartella temporanea>; mkdir -p "$O/info" "$O/pack"   # oggetti git scritti da review-surface.sh tree
PYTHONDONTWRITEBYTECODE=1 GIT_OPTIONAL_LOCKS=0 GIT_OBJECT_DIRECTORY="$O" \
  GIT_ALTERNATE_OBJECT_DIRECTORIES="<progetto>/.git/objects" FIC_DRIVER_CERT=<file temporaneo> \
  "$FIC_PY" "<MAAT_ROOT>/scripts/driver.py" equiv --certifica .claude/.ai-workflow   # FIC_REPO non impostata
```

`review-surface.sh tree` fa `git add -A` e `write-tree` su un indice temporaneo: senza `GIT_OBJECT_DIRECTORY` gli
oggetti finirebbero nel `.git` del progetto; `GIT_OPTIONAL_LOCKS=0` evita che git aggiorni l'indice vero.

- Esito richiesto `diverse=0 · diversi=0`; un `DIVERSO` è uno STOP con il diff, non si ricertifica a mano.
- Prima e dopo, un'istantanea (elenco e sha256) di `.claude/.ai-workflow/spec-*.md` e `.claude/.ai-workflow/*.run/`:
  deve essere identica.
- Poi il file si copia in `scripts/driver.equiv` e `driver.py certificato` deve dire VALIDO. `driver.equiv` è sotto
  `MAAT_ROOT`: ricertificare cambia l'impronta del harness.

### Variante: certificare su una copia del progetto

È la forma usata il 2026-10-29 (certificato della 0.3.0): il progetto vero resta del tutto fuori, nemmeno in lettura
con le variabili sopra.

1. **La copia:** un clone del ramo del progetto in una cartella temporanea, con `git -c core.longpaths=true clone …`
   (su Windows i percorsi delle run dir superano i 260 caratteri), più le spec e le run dir di cicli **chiusi**
   (`.claude/.ai-workflow/spec-*.md` e `*.run/`), copiate dal progetto. Il 2026-10-29: 15 cicli chiusi (catene, cicli
   singoli, un ciclo in STOP, tre del regime vecchio).
2. **Prima:** istantanea (elenco e sha256) delle spec e delle run dir del progetto vero.
3. **La certificazione:** il comando sopra, lanciato dalla radice della **copia** (oggetti git nella cartella temporanea
   come sopra). Esito richiesto `diverse=0 · diversi=0`; il 2026-10-29: `spec=15 diverse=0 · jsonl=83 diversi=0`.
4. **Dopo:** stessa istantanea del progetto vero, identica a quella di prima.
5. Il certificato si copia in `scripts/driver.equiv` e `driver.py certificato` deve dire VALIDO.

Durata: circa **3 ore su Windows**, quasi tutte nei controlli di `review-surface.sh check` in bash. La copia si può
tenere per la certificazione successiva (cambia solo il plugin); se la cartella temporanea è stata svuotata si rifà,
mai sul tree del progetto.
