#!/usr/bin/env bash
# test-fast.sh — test e lint di un modulo su una COPIA LOCALE dei suoi pacchetti, nel filesystem Linux di WSL.
#
# Perche': da WSL su /mnt/c ogni lettura attraversa il confine della VM e un runner JavaScript e' fino a ~100x
# piu' lento del filesystem nativo. La copia toglie quel costo senza cambiare cosa si esegue: stessi file, stesse
# dipendenze, stesso comando.
#
# COSA ESEGUE lo dice .claude/maat.json del progetto (lettore unico: maat-config.py), mai questo script:
# - il modulo: MAAT_MODULO dall'ambiente (gates.sh lo mette nell'ambiente del comando, non nella riga), altrimenti
#   l'unico modulo che dichiara `copia`; piu' moduli con copia e nessun MAAT_MODULO -> exit 64;
# - la copia contiene `radice_pacchetti` del modulo (<copia> = <copia della radice del repo>/<radice_pacchetti>);
#   la radice del modulo vi sta allo stesso percorso relativo;
# - il comando DENTRO la copia e' il campo `copia` del modulo (test, lint con le sue alternative, lint_messaggi),
#   mai `comandi`: `comandi.test`/`comandi.lint` sono il comando che gates.sh esegue nel repo, cioe' questo script.
#   Un `copia` che chiamasse test-fast.sh lo rifiuta `maat-config.py valida` (S6): niente autorichiamo.
# La radice del progetto: FIC_REPO, altrimenti la prima cartella sopra quella di lavoro che contiene `.git` o
# `.claude/maat.json` (git di WSL non legge sempre un worktree creato da Windows: fic-mirror.sh lo traduce dopo).
#
# Uso (da Git Bash o da una sottosessione; lo script gira DENTRO WSL, da una cartella del progetto):
#   wsl -- bash -lc 'cd <radice del modulo> && bash <maat>/scripts/test-fast.sh <file di test…>'
#       test. I file sono relativi alla RADICE del modulo, come per il runner lanciato da li'.
#   wsl -- bash -lc 'cd <repo> && bash <maat>/scripts/test-fast.sh --lint [--cache] [--base <ref>] <file…>'
#       lint. I file sono relativi al REPOSITORY.
#       ⚠️ DUE CONVENZIONI DI PERCORSO nello stesso script, ed e' voluto: i test arrivano relativi alla radice del
#       modulo, il lint relativo al repo.
#   wsl -- bash -lc 'cd <repo> && bash <maat>/scripts/test-fast.sh --setup'
#       UNA TANTUM, a mano e fuori dalle sottosessioni (e di nuovo quando cambiano le dipendenze):
#       copia anche node_modules e registra l'impronta delle dipendenze. Prepara la copia della radice
#       CORRENTE: va rifatto una volta per ogni worktree (ognuno ha la sua, vedi Garanzie).
# vitest-fast.sh, accanto, e' l'involucro deprecato di una riga: stessi argomenti, stesso comportamento.
#
# SOLO PATH, MAI OPZIONI. Gli argomenti finiscono testualmente nella riga di comando del runner: una
# opzione arbitraria cambierebbe cio' che il gate significa (`--passWithNoTests` renderebbe PASS una
# selezione vuota, `--fix` riscriverebbe il codice) e un path assoluto o con `..` uscirebbe dal
# perimetro. Qualunque argomento che inizia per `-`, assoluto o con un segmento `..` -> exit 64.
#
# LINT — perimetro, classificazione fuori perimetro, cache:
# - un path sotto radice_pacchetti che NON esiste nel working tree (file eliminato dalla modifica) non arriva
#   al linter: e' dichiarato "eliminato, non lintato". Passato al linter lo farebbe uscire 2 e il gate sarebbe
#   BLOCKED su codice sano. Che il file sia davvero sparito lo verificano i test della feature, non il lint;
# - il GATE e' la RADICE del modulo. Un'estensione non lintabile (.ts/.tsx/.vue/.js) e' SKIPPED, deciso PRIMA
#   di eseguire: il linter uscirebbe >=2 e il gate sarebbe BLOCKED su codice sano;
# - i file lintabili sotto radice_pacchetti FUORI dalla radice, nei due segmenti apps/<x> o packages/<x>, non
#   sono pero' "innocui per definizione". Con `lint_base: true` nel modulo e `--base <ref>` vengono CLASSIFICATI
#   (vedi sotto); senza `--base` restano SKIPPED, dichiarati. Senza `lint_base` e fuori da radice_pacchetti
#   sono SKIPPED: non sono nel gate;
# - la cwd e' la `cartella` del comando di `copia` (default la radice del modulo), mai fissata altrove: una cwd
#   sbagliata risolverebbe la configurazione di un altro pacchetto e farebbe passare il gate a vuoto;
# - la cache e' OPT-IN (`--lint --cache`) e serve all'inner loop: il gate richiesto si invoca senza,
#   cosi' un PASS non puo' venire da voci di cache che nessuno ha rivalidato. Il file sta nella
#   RADICE della copia (`.fic-eslintcache-<radice relativa, / -> ->`), segnaposto {cache?…} del comando: un
#   percorso relativo finirebbe nella cartella del gruppo, dove `rsync --delete` lo cancella a ogni run. Nel
#   RIPIEGO la cache non si usa mai: la scriverebbe dentro il repository, dove non e' ignorata da git, e da li'
#   in poi ogni run vedrebbe "copia non allineata";
# - servono i `preparati` del modulo (file scritti dalla sua `preparazione`, glob relativi alla radice; per esempio
#   il tsconfig generato dal framework): le loro cartelle sono escluse dal sync perche' generate. Lo script copia
#   nella copia i file che corrispondono; se nell'origine manca il «file guida» (il primo glob senza caratteri
#   jolly, la stessa regola di ciclo-worktree.sh) l'esito e' BLOCKED (exit 2) con il rimedio (`preparazione` del
#   modulo), e NON si ripiega: su /mnt/c manca allo stesso modo e il lint inventerebbe errori su ogni import, cioe'
#   un FAIL su codice sano. Un modulo senza `preparati` non ha questo requisito;
#
# LINT FUORI DALLA RADICE — PREEXISTING / INTRODUCED / UNRESOLVED (serve `lint_base: true` e `--base <ref>`):
# - un pacchetto SENZA configurazione eslint non e' lintabile: SKIPPED e' vero, non e' "superficie non
#   verificata";
# - un pacchetto CON configurazione viene lintato due volte (comando `copia.lint_messaggi`, dalla radice del
#   pacchetto): il contenuto attuale, e il contenuto della BASE scritto nella COPIA allo stesso path (stessa
#   cartella = stessa configurazione risolta; scriverlo altrove cambierebbe la risoluzione degli import e
#   inventerebbe differenze). I due insiemi di messaggi si confrontano su `<file> + <testo> (<regola>)`, SENZA
#   riga e colonna: uno spostamento di riga non e' un errore nuovo. Solo nell'attuale = INTRODUCED (bloccante,
#   exit 1) · in entrambi = PREEXISTING (informativo: e' debito che il gate non guarda) · file assente nella
#   base = tutto INTRODUCED;
# - la prova della base si fa PRIMA dello stamp e il file si ripristina subito (anche via trap): cosi'
#   la rilevazione delle scritture del run resta intatta. Se lo script muore nel mezzo, la copia resta
#   disallineata e il run successivo la risincronizza (o, se non ci riesce, esce BLOCKED) — mai un falso PASS;
# - NEL RIPIEGO non si classifica: la prova della base richiederebbe di scrivere dentro il REPOSITORY.
#   Quei path diventano UNRESOLVED (exit 3), che per chi chiama e' "non conclusivo", mai PASS.
#
# Garanzie (le da' lo script, non la guardia: guard.py non legge dentro gli script):
# - destinazione locale DERIVATA DALLA RADICE del repository (`git rev-parse --show-toplevel`):
#   $HOME/fic-mirror/<radice_pacchetti> dal tree principale, $HOME/fic-mirror-<primi 12 caratteri dello sha256
#   della radice>/<radice_pacchetti> da un worktree collegato (git-dir diverso da git-common-dir). Cosi' un
#   harness sviluppato in un worktree non tocca la copia dei cicli del tree principale. Nessun argomento
#   la cambia, nessun host remoto: l'unico rsync e' fra due directory di questa macchina. Radice non
#   determinabile (git inutilizzabile) -> nessuna destinazione: BLOCKED come "manifest non calcolabile",
#   mai ~/fic-mirror per ripiego, che sarebbe la copia di un ALTRO tree. La regola sta in fic-mirror.sh,
#   condiviso con counterproof.sh: vale anche per un worktree creato da Git per Windows (il suo "gitdir: C:/…"
#   si traduce in /mnt/c/… per git di WSL, destinazione e manifest);
# - copia di un worktree senza node_modules (primo uso o --setup di un worktree che non li ha installati):
#   node_modules SEMINATI dalla copia del tree principale in hardlink, solo se quella e' valida e le
#   dipendenze del worktree coincidono con le sue (impronta normalizzata); altrimenti "copia assente" col motivo;
# - prima di ogni run, dentro il lock: sync INCREMENTALE sul manifest (harness-pt06). Il manifest (path +
#   sha256 dei file tracciati e non tracciati non ignorati di radice_pacchetti, piu' i .env* ignorati: TUTTO
#   cio' che il runner puo' caricare) si calcola sui due lati; i file da allineare sono il DIFF fra i due
#   (copiati se diversi, cancellati se assenti nell'origine), mai un elenco del chiamante. I file della copia
#   fuori dal manifest e assenti nell'origine (non tracciati cancellati, scritture di un run) si cancellano,
#   come faceva `rsync --delete`. Stato PER COPIA (<copia>/.fic-sync-src): la stat dell'origine (dimensione,
#   mtime, ctime, inode) con lo sha256 letto l'ultima volta, cosi' attraverso /mnt/c si rilegge solo cio'
#   che e' cambiato; la copia invece si rilegge sempre per intero (filesystem nativo), quindi nessuna
#   scrittura nella copia (counterproof.sh, un run interrotto) sfugge al confronto. Senza stato (primo run,
#   copia nuova) il sync e' COMPLETO: rsync -a --delete --checksum (esclusioni: l'elenco unico del nucleo,
#   FIC_MIRROR_EXCL di fic-mirror.sh), com'era prima. I file ignorati da git (fuori dal manifest) li porta solo il sync
#   completo: il runner non li carica;
# - PREMESSA della cache: ogni scrittura nell'origine cambia la stat (almeno la ctime), anche su drvfs e
#   anche da Windows — provata da test-fast.test.sh (sonda drvfs), non garantita. Rete di sicurezza: ogni
#   FIC_SYNC_AUDIT_RUNS run (default 20) o dopo FIC_SYNC_AUDIT_SECS secondi dall'ultimo controllo completo
#   (default 1800) l'origine si rilegge tutta, senza cache (stato in <copia>/.fic-sync-audit). Se la cache
#   aveva torto: "vitest-fast: cache stat incompleta, resync completo", cache buttata, sync completo;
# - le cartelle dei `preparati` del modulo e (con controprova.runner vitest) le cache di vite/vitest della copia
#   (fic_mirror_pulisci di fic-mirror.sh, la stessa pulizia di counterproof.sh) si ripuliscono SOLO quando cambia l'impronta delle
#   dipendenze (.fic-deps) o il file guida dei preparati nell'origine (stato in <copia>/.fic-sync-gen), non a ogni
#   run: il framework rigenera comunque i suoi file generati a ogni avvio;
# - poi la verifica di sempre: manifest della copia identico a quello dell'origine;
# - guardia di equivalenza, INTERNA ai test (non e' un'opzione del chiamante): con FIC_SYNC_EQUIV=1
#   nell'ambiente, dopo il run incrementale si rifa' il sync COMPLETO sulla stessa copia e si riesegue:
#   esito e manifest della copia devono coincidere, altrimenti esito=BLOCKED (equivalenza violata), exit 3;
# - node_modules non e' nel manifest: vale l'impronta di tutti i package.json (fuori da node_modules) e
#   di package-lock.json presa al --setup; se e' cambiata, dipendenze stantie, e la copia si RIALLINEA DA SOLA
#   dentro il lock (fic-mirror.sh, fic_deps_autorefresh): origine con node_modules -> la stessa operazione del
#   --setup (rsync, node_modules compresi, poi l'impronta); worktree o corsia senza node_modules -> fonte della
#   semina riallineata se stantia, poi semina di nuovo in hardlink. Riga "vitest-fast: dipendenze cambiate
#   (impronta <vecchia> -> <nuova>): copia riallineata dall'origine" (o "…riseminata da …"), poi deps_ok di
#   nuovo e i generati ripuliti (l'impronta e' in .fic-sync-gen). Mai npm install, mai la rete. Nessuna fonte
#   con node_modules, o rsync fallito -> BLOCKED col motivo, exit 3, mai un ripiego silenzioso. L'impronta e' sul
#   contenuto NORMALIZZATO (senza CR): due checkout dello stesso commit con fine riga diverse danno la stessa
#   impronta. Un .fic-deps scritto prima di questa regola (impronta dei byte) resta valido finche' i byte
#   non cambiano;
# - il runner gira con CI=true (nel comando di `copia`), nella copia E nel ripiego: una snapshot mancante
#   FALLISCE invece di essere scritta. Dopo il run la copia si riconfronta col manifest e si cercano file nuovi:
#   qualunque scrittura (snapshot in __snapshots__ o inline in un file di test) -> esito BLOCKED, exit 4: le
#   snapshot si generano su /mnt/c, dove entrano nel diff che la review vede. Una snapshot MANCANTE invece da'
#   FAIL (CI=true): stesso rimedio, generarla su /mnt/c;
# - copia occupata da un altro run -> si ATTENDE il lock (flock -w, tetto FIC_LOCK_WAIT secondi,
#   default 900); oltre il tetto -> BLOCKED, exit 3. Mai un ripiego silenzioso: su /mnt/c il run e'
#   3-17x piu' lento, e ripiegare perche' la copia e' occupata costava piu' che aspettarla;
# - copia non allineata dopo il sync -> UNA risincronizzazione (rsync completo) e nuovo confronto; se
#   resta disallineata -> BLOCKED, exit 3;
# - copia assente, dipendenze stantie non riallineabili, sync fallito, manifest non calcolabile (git) -> BLOCKED, exit 3,
#   con il motivo e il rimedio;
# - RIPIEGO su /mnt/c (lo stesso comando, lento ma valido) SOLO con FIC_ALLOW_MNT_C=1 esplicito
#   nell'ambiente: al posto di ognuno dei BLOCKED qui sopra, dichiarato nella prima riga e nella riga
#   d'esito ("luogo=mnt-c (ripiego dichiarato: FIC_ALLOW_MNT_C=1)").
#
# Output: le righe hanno il prefisso `vitest-fast:`, invariato (lo leggono gates.sh, finalize.sh e
# plan-check.sh). Prima riga "vitest-fast: luogo=copia" o "vitest-fast: luogo=mnt-c (ripiego: <motivo>; …)";
# nella copia la segue "vitest-fast: sync=completo" o "vitest-fast: sync=incrementale (<n> file allineati)";
# ultima riga "vitest-fast: esito=<PASS|FAIL|BLOCKED|SKIPPED|UNRESOLVED …> luogo=<copia|mnt-c|->".
# Exit: 0/1 = esito del runner (1 anche per un INTRODUCED fuori dalla radice) · 2 = BLOCKED di configurazione
#       (del lint: eslint, oppure tsconfig generato assente; di maat.json: comando di `copia` non risolto) ·
#       3 = UNRESOLVED (lint fuori dalla radice non classificabile: senza --base utilizzabile, o nel ripiego)
#       oppure BLOCKED (copia non utilizzabile: occupata oltre il tetto, assente, stantia non riallineabile,
#       disallineata) · 4 = BLOCKED (snapshot da generare su /mnt/c) ·
#       64 = uso errato, opzione al posto di un path, path non ancorati al repo, non in WSL, progetto o modulo
#       non determinabile (maat.json assente o non valido, piu' moduli con copia senza MAAT_MODULO)
#       (convenzione sysexits: NON 2, che per eslint significa "errore di configurazione" e deve
#       restare distinguibile → BLOCKED, mai FAIL).
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
DST=""   # derivata dalla radice del repository, dopo il controllo degli strumenti (vedi mirror_dir)
EXCL=()   # le esclusioni del sync: l'elenco unico del nucleo, FIC_MIRROR_EXCL di fic-mirror.sh (piu' sotto)

MODE=test
CACHE=0
BASE=""
LINT=(); SKIP=(); EXTRA=(); DELETED=()
case "${1:-}" in
  "") echo "uso: test-fast.sh <file di test…> | --lint [--cache] [--base <ref>] <file…> | --setup" >&2; exit 64 ;;
  --lint) MODE=lint; shift
          while :; do
            case "${1:-}" in
              --cache) CACHE=1; shift ;;
              --base)  BASE=${2:-}
                       [ -n "$BASE" ] || { echo "vitest-fast: --base richiede un riferimento git" >&2; exit 64; }
                       # Se il valore e' un file esistente il chiamante ha scordato il riferimento: senza
                       # questo controllo quel path sparirebbe dalla lista e il gate linterebbe meta'
                       # superficie uscendo 0.
                       [ -e "$BASE" ] && { echo "vitest-fast: --base vuole un riferimento git, non un path: $BASE" >&2; exit 64; }
                       shift 2 ;;
              *) break ;;
            esac
          done
          [ $# -gt 0 ] || { echo "uso: test-fast.sh --lint [--cache] [--base <ref>] <file…>" >&2; exit 64; } ;;
esac
command -v rsync >/dev/null && command -v flock >/dev/null && command -v sha256sum >/dev/null ||
  { echo "vitest-fast: servono rsync, flock e sha256sum (va eseguito in WSL)" >&2; exit 64; }

# Radice del progetto: FIC_REPO, altrimenti la prima cartella sopra quella di lavoro con `.git` (cartella o file
# di un worktree) o `.claude/maat.json`. Non dipende dalla posizione di questo script, che sta nel plugin.
trova_radice() {
  local d; d=$(pwd)
  while :; do
    if [ -e "$d/.git" ] || [ -f "$d/.claude/maat.json" ]; then printf '%s\n' "$d"; return 0; fi
    [ "$d" = / ] && return 1
    d=$(dirname "$d")
  done
}
if [ -n "${FIC_REPO:-}" ]; then ROOT=$FIC_REPO
else ROOT=$(trova_radice) || { echo "vitest-fast: progetto non trovato sopra $(pwd) (nessun .git ne' .claude/maat.json; o FIC_REPO)" >&2; exit 64; }
fi
ROOT=$(cd "$ROOT" 2>/dev/null && pwd) || { echo "vitest-fast: radice del progetto non accessibile: $ROOT" >&2; exit 64; }

# Modulo e comandi da maat.json, con il lettore unico (sempre lo stesso interprete del harness).
. "$HERE/python.sh" 2>/dev/null || true
[ -n "${FIC_PY:-}" ] || { echo "vitest-fast: nessun Python per leggere maat.json (python.sh)" >&2; exit 64; }
mc() { PROJECT_ROOT=$ROOT "$FIC_PY" "$HERE/maat-config.py" "$@"; }
MOD_OUT=$(mc copia-modulo) || { echo "vitest-fast: modulo della copia non determinabile da maat.json (maat-config.py copia-modulo, uscita $?)" >&2; exit 64; }
{ read -r MODULO; read -r RAD; read -r PKG; read -r LINT_BASE; read -r PREP; } <<< "$MOD_OUT"
[ -n "$PKG" ] || { echo "vitest-fast: radice_pacchetti del modulo $MODULO e' la radice del repository: la copia vuole una cartella" >&2; exit 64; }
if [ "$RAD" = "$PKG" ]; then GROUP=""; else GROUP=${RAD#"$PKG"/}; fi   # la radice, relativa a radice_pacchetti
G=${GROUP:+/$GROUP}                                                  # "$DST$G" = la radice del modulo nella copia
SRC=$(cd "$ROOT/$PKG" 2>/dev/null && pwd) || { echo "vitest-fast: $PKG non trovato in $ROOT" >&2; exit 64; }
export MAAT_MODULO=$MODULO   # i comandi di copia e una chiamata annidata del lettore vedono lo stesso modulo

# Destinazione, impronta delle dipendenze e semina: fic-mirror.sh, condiviso con counterproof.sh (stessa copia,
# stesso lock). Copia della RADICE del repository: ~/fic-mirror per il tree principale, ~/fic-mirror-<hash> per un
# worktree collegato, anche creato da Git per Windows (gitdir C:/… tradotto). Mai da un argomento. Radice non
# determinabile -> MIRROR vuoto.
. "$HERE/fic-mirror.sh" || { echo "vitest-fast: fic-mirror.sh non trovato accanto a test-fast.sh" >&2; exit 64; }
EXCL=("${FIC_MIRROR_EXCL[@]}")
if fic_mirror_init "$ROOT"; then MIRROR=$FIC_MIRROR; else MIRROR=""; fi
# CORSIA (harness-pt13): FIC_LANE=k (1..9, dall'ambiente, mai da un argomento; la passa run-phase.sh alle corsie
# con WSLENV) -> la copia della corsia, <copia della radice>-<k>: suo lock, sue cache vite/vitest, node_modules
# seminati in hardlink dalla copia della radice. Senza FIC_LANE la copia di sempre.
if [ -n "${FIC_LANE:-}" ]; then
  case "$FIC_LANE" in [1-9]) ;; *) echo "vitest-fast: FIC_LANE deve essere una cifra da 1 a 9: $FIC_LANE" >&2; exit 64 ;; esac
  [ -n "$MIRROR" ] && fic_lane_init "$FIC_LANE" && MIRROR=$FIC_MIRROR
fi
DST=${MIRROR:+$MIRROR/$PKG}
deps_fp() { fic_deps_fp "$@"; }
deps_ok() { fic_deps_ok "$SRC" "$DST"; }   # le dipendenze dell'origine sono quelle registrate al --setup

manifest_list() {  # tracciati + non tracciati non ignorati + .env* (anche ignorati), relativi a SRC
  { git -c safe.directory='*' -C "$SRC" ls-files -co --exclude-standard -z . | tr '\0' '\n'
    (cd "$SRC" && find . \( -name node_modules -o -name .nuxt -o -name .output \) -prune -o -name '.env*' -type f -print | sed 's|^\./||')
  } | LC_ALL=C sort -u
}

hashes() {  # <dir> <lista ordinata>: "sha  path" per ogni path della lista, nel suo ordine; ABSENT se manca
  # Un solo sha256sum per tutti i file (harness-pt06: uno per file costava ~5,7 s sui 1031 file della copia).
  # Stesso output di prima: sha256sum stampa "sha  path" come la riga scritta a mano, e l'ordine si
  # ripristina ordinando sul path (le liste sono in ordine LC_ALL=C). Un path con `\` farebbe scrivere a
  # sha256sum una riga con escape: quello si hasha da solo, come prima.
  local nul; nul=$(mktemp) || return 1   # fuori dalle due radici: mai un file nel repository o nella copia
  (cd "$1" && {
     while IFS= read -r f; do
       [ -n "$f" ] || continue
       if [ ! -f "$f" ]; then printf 'ABSENT  %s\n' "$f"
       elif [[ $f == *\\* ]]; then printf '%s  %s\n' "$(sha256sum < "$f" | cut -c1-64)" "$f"
       else printf '%s\0' "$f" >&3
       fi
     done < "$2" 3> "$nul"
     xargs -0 -r sha256sum -- < "$nul"
   } | LC_ALL=C sort -t ' ' -k3)
  rm -f "$nul"
}

# Il comando di `copia` del modulo (maat-config.py comando-copia): CMD_DIR = cartella assoluta d'esecuzione,
# CMD_LINE = comando espanso, con i file gia' quotati. Le opzioni --file/--test sono relative alla copia di
# radice_pacchetti (o all'origine, nel ripiego); il lettore le rende relative alla cartella del comando.
copia_cmd() {  # <tipo> --copia <dir> [opzioni del lettore…]
  local out
  out=$(mc comando-copia "$MODULO" "$@") || return $?
  CMD_DIR=${out%%$'\n'*}; CMD_LINE=${out#*$'\n'}
}
cmd_non_risolto() {  # <tipo> <uscita del lettore>: maat.json non da' un comando eseguibile -> BLOCKED, mai FAIL
  echo "vitest-fast: esito=BLOCKED (copia.$1 del modulo $MODULO non risolto da maat.json: maat-config.py comando-copia, uscita $2) luogo=-"
  exit 2
}

run_cmd() {  # <radice dei pacchetti: copia o origine> <file…>  — test relativi alla radice, lint a radice_pacchetti
  local base=$1 a=() f rc; shift
  if [ "$MODE" = lint ]; then
    for f in "$@"; do a+=(--file "$f"); done
    # {cache?…}: solo con --cache, alla radice della copia. harness-pt15: con lint-baseline.mjs il gate e' lo
    # script `lint` di package.json (come la CI) — e' la prima alternativa di copia.lint nel profilo.
    [ "$CACHE" -eq 1 ] && a+=(--cache "$base/.fic-eslintcache-${GROUP//\//-}")
    copia_cmd lint --copia "$base" ${a[@]+"${a[@]}"} || cmd_non_risolto lint $?
  else
    for f in "$@"; do a+=(--test "${GROUP:+$GROUP/}$f"); done
    copia_cmd test --copia "$base" ${a[@]+"${a[@]}"} || cmd_non_risolto test $?
  fi
  (cd "$CMD_DIR" && eval "$CMD_LINE"); rc=$?
  return $rc
}

# Esito dal codice d'uscita del runner. Per eslint: 0 verde, 1 errori di lint, >=2 guasto di
# configurazione o d'ambiente -> BLOCKED, mai FAIL (accuserebbe codice sano).
esito_di() {
  local rc=$1
  if [ "$rc" -eq 0 ]; then echo PASS
  elif [ "$MODE" = lint ] && [ "$rc" -ge 2 ]; then echo "BLOCKED (eslint: configurazione o ambiente, uscita $rc)"
  else echo FAIL
  fi
}

# `--setup` vale solo da solo: `--lint --setup <file>` altrimenti eseguirebbe il setup e uscirebbe 0
# senza lintare niente, cioe' un exit 0 che somiglia a un PASS su una verifica mai fatta.
case " $* " in
  *" --setup "*) [ "$1" = --setup ] && [ $# -eq 1 ] ||
    { echo "vitest-fast: --setup va usato da solo" >&2; exit 64; } ;;
esac
if [ "$1" = --setup ]; then
  [ -n "$DST" ] || { echo "vitest-fast: radice del repository non determinabile (git): nessuna copia preparata" >&2; exit 1; }
  mkdir -p "$DST"
  if [ ! -d "$SRC/node_modules" ]; then
    # Worktree senza dipendenze installate: node_modules dalla copia del tree principale, in hardlink
    # (fic-mirror.sh, SEMINA), poi i sorgenti. Mai un'installazione.
    rm -f "$DST/.fic-deps"
    why=$(fic_seed_node_modules "$SRC" "$DST") ||
      { echo "vitest-fast: $SRC non ha node_modules e la semina non e' possibile: $why" >&2; exit 1; }
    echo "vitest-fast: setup della copia in $DST (node_modules in hardlink da ~/fic-mirror)…"
    rsync -a --delete "${EXCL[@]}" "$SRC/" "$DST/" || exit 1
    echo "vitest-fast: setup completato, impronta dipendenze $(cut -c1-12 < "$DST/.fic-deps")"
    exit 0
  fi
  echo "vitest-fast: setup della copia in $DST (node_modules compresi)…"
  why=$(fic_deps_refresh "$SRC" "$DST") || { echo "vitest-fast: setup fallito: $why" >&2; exit 1; }
  echo "vitest-fast: setup completato, impronta dipendenze $(cut -c1-12 < "$DST/.fic-deps")"
  exit 0
fi

# Solo path, mai opzioni: gli argomenti finiscono testualmente nella riga di comando del runner, dove
# un'opzione cambierebbe cio' che il gate significa (`--passWithNoTests` -> PASS su una selezione vuota,
# `--fix` -> riscrittura del codice) e un path assoluto o con `..` uscirebbe dal perimetro. `--setup`,
# `--lint`, `--cache` e `--base` sono gia' stati consumati sopra.
for p in "$@"; do
  case "$p" in
    -*) echo "vitest-fast: solo path, niente opzioni per il runner: $p" >&2; exit 64 ;;
    /*) echo "vitest-fast: path assoluto non ammesso: $p" >&2; exit 64 ;;
    ..|../*|*/../*|*/..) echo "vitest-fast: segmento '..' non ammesso nel path: $p" >&2; exit 64 ;;
  esac
done

# Messaggi di eslint normalizzati: "<file>	<testo> (<regola>)", SENZA riga e colonna — uno stesso
# errore spostato di una riga non e' un errore nuovo. ⚠️ Il NOME DEL FILE resta, ed e' essenziale: senza,
# un errore introdotto in b.ts verrebbe assolto come preesistente solo perche' lo stesso testo esisteva
# nella base in a.ts — e i testi si ripetono identici fra file (`no-unused-vars`, `no-explicit-any`).
# Il path e' reso relativo alla radice della copia: le due passate girano nella stessa cwd, quindi
# combaciano, e la riga stampata dice in quale file sta l'errore. Torna il codice d'uscita del comando
# `copia.lint_messaggi` (2 se maat.json non lo da').
lint_msgs() {  # <radice dei pacchetti nella copia> <gruppo> <file relativi al gruppo…>
  local base=$1 grp=$2 a=() f; shift 2
  local out rc
  for f in "$@"; do a+=(--file "$grp/$f"); done
  copia_cmd lint_messaggi --copia "$base" --pacchetto "$grp" "${a[@]}" || return 2
  out=$( (cd "$CMD_DIR" && eval "$CMD_LINE") 2>&1 ); rc=$?
  printf '%s
' "$out" |
    sed -n 's/^\(.*\): line [0-9][0-9]*, col [0-9][0-9]*, \(Error\|Warning\) - /\1\t/p' |
    sed "s|^$base/||" | LC_ALL=C sort
  return $rc
}

# PREEXISTING / INTRODUCED / UNRESOLVED per i file lintabili sotto radice_pacchetti fuori dalla radice.
# Torna 0 (niente di nuovo), 1 (INTRODUCED: bloccante) o 3 (UNRESOLVED: non conclusivo).
CLASSIFICATI=0
classify_extra() {
  local has_intro=0 has_unres=0 grp e i q
  if [ -z "$BASE" ]; then
    echo "vitest-fast: fuori da $RAD, non classificati (manca --base):"
    for e in "${EXTRA[@]}"; do echo "  SKIPPED     ${e##*|}"; done
    return 0
  fi
  if ! git -c safe.directory='*' -C "$SRC" rev-parse --verify -q "$BASE^{commit}" >/dev/null 2>&1; then
    echo "vitest-fast: base '$BASE' non risolvibile: classificazione impossibile"
    for e in "${EXTRA[@]}"; do echo "  UNRESOLVED  ${e##*|}"; done
    return 3
  fi
  while IFS= read -r grp; do
    [ -n "$grp" ] || continue
    local rels=() paths=() olds=() r cfg cur base_msgs rcc intro pre rst
    for e in "${EXTRA[@]}"; do
      [ "${e%%|*}" = "$grp" ] || continue
      r=${e#*|}; rels+=("${r%%|*}"); paths+=("${e##*|}")
    done
    # Un pacchetto senza configurazione eslint non e' lintabile: qui SKIPPED e' vero. Un glob che non
    # combacia resta letterale, quindi il test e' su ogni candidato: `ls` con due pattern uscirebbe
    # non-zero anche quando il primo esiste, e ogni pacchetto sembrerebbe senza configurazione.
    cfg=0
    for r in "$DST/$grp"/.eslintrc* "$DST/$grp"/eslint.config.*; do [ -f "$r" ] && { cfg=1; break; }; done
    # anche la forma `"eslintConfig": {…}` dentro package.json: senza, un pacchetto davvero lintabile
    # verrebbe dichiarato "non lintabile", cioe' assolto
    [ "$cfg" -eq 0 ] && [ -f "$DST/$grp/package.json" ] &&
      grep -q '"eslintConfig"' "$DST/$grp/package.json" && cfg=1
    if [ "$cfg" -eq 0 ]; then
      echo "vitest-fast: $grp senza configurazione eslint (non lintabile):"
      printf '  SKIPPED     %s\n' "${paths[@]}"
      continue
    fi
    cur=$(lint_msgs "$DST" "$grp" "${rels[@]}"); rcc=$?
    if [ "$rcc" -ge 2 ]; then
      echo "vitest-fast: $grp eslint non eseguibile (uscita $rcc): classificazione impossibile"
      printf '  UNRESOLVED  %s\n' "${paths[@]}"
      has_unres=1; continue
    fi
    # Contenuto della base allo STESSO path della copia: e' l'unico posto che risolve la stessa
    # configurazione e gli stessi import. Ripristino subito dopo, e via trap se si muore qui.
    : > "$TMPD/swapped"
    for i in "${!rels[@]}"; do
      git -c safe.directory='*' -C "$SRC" show "$BASE:${paths[$i]}" > "$TMPD/base-content" 2>/dev/null || continue
      # Registrato PRIMA di scrivere: un `cp` che fallisce dopo aver troncato la destinazione lascerebbe
      # un file monco che il trap non saprebbe di dover ripristinare.
      echo "$grp/${rels[$i]}" >> "$TMPD/swapped"
      cp "$TMPD/base-content" "$DST/$grp/${rels[$i]}" || continue
      olds+=("${rels[$i]}")
    done
    base_msgs=""; rcc=0
    [ ${#olds[@]} -gt 0 ] && { base_msgs=$(lint_msgs "$DST" "$grp" "${olds[@]}"); rcc=$?; }
    # Ripristino verificato: l'elenco si svuota solo se ogni copia e' tornata a posto; altrimenti resta
    # al trap e il guasto si dichiara (una copia disallineata fa ripiegare il run successivo).
    rst=0
    while IFS= read -r q; do [ -n "$q" ] && { cp "$SRC/$q" "$DST/$q" || rst=1; }; done < "$TMPD/swapped"
    if [ "$rst" -ne 0 ]; then
      echo "vitest-fast: ripristino della copia non riuscito ($grp): il prossimo run la risincronizzera'" >&2
    else
      : > "$TMPD/swapped"
    fi
    if [ "$rcc" -ge 2 ]; then
      echo "vitest-fast: $grp eslint sulla base non eseguibile (uscita $rcc): classificazione impossibile"
      printf '  UNRESOLVED  %s\n' "${paths[@]}"
      has_unres=1; continue
    fi
    intro=$(comm -23 <(printf '%s
' "$cur" | grep -v '^$') <(printf '%s
' "$base_msgs" | grep -v '^$'))
    pre=$(comm -12 <(printf '%s
' "$cur" | grep -v '^$') <(printf '%s
' "$base_msgs" | grep -v '^$'))
    if [ -n "$pre" ]; then
      echo "vitest-fast: $grp PREEXISTING (gia' nella base, fuori dal gate):"
      printf '%s
' "$pre" | sed 's/^/  /'
    fi
    if [ -n "$intro" ]; then
      echo "vitest-fast: $grp INTRODUCED (assenti nella base):"
      printf '%s
' "$intro" | sed 's/^/  /'
      has_intro=1
    fi
    CLASSIFICATI=$((CLASSIFICATI + ${#paths[@]}))
    [ -n "$pre$intro" ] || echo "vitest-fast: $grp pulito contro la base: ${paths[*]}"
  done <<< "$(printf '%s
' "${EXTRA[@]}" | cut -d'|' -f1 | LC_ALL=C sort -u)"
  # Un INTRODUCED non va mascherato da un UNRESOLVED di un altro gruppo: bloccante vince.
  [ "$has_intro" -eq 1 ] && return 1
  [ "$has_unres" -eq 1 ] && return 3
  return 0
}

fallback() {  # <motivo> <file…>
  local why=$1 e; shift
  # ⚠️ Mai la cache nel ripiego: la scriverebbe DENTRO il repository (<radice_pacchetti>/.fic-eslintcache-*),
  # dove non e' ignorata da git. Entrerebbe nel manifest, e da li' in poi ogni run vedrebbe "copia non
  # allineata" e ripiegherebbe su /mnt/c per sempre — l'ottimizzazione annullata in silenzio. Il ripiego
  # non e' il percorso veloce dell'inner loop.
  CACHE=0
  echo "vitest-fast: luogo=mnt-c (ripiego: $why; dichiarato da FIC_ALLOW_MNT_C=1)"
  local rc=0 dich="luogo=mnt-c (ripiego dichiarato: FIC_ALLOW_MNT_C=1)"
  # Con solo file fuori dalla radice la lista del gate e' vuota: niente da eseguire qui.
  if [ "$MODE" != lint ] || [ $# -gt 0 ]; then
    run_cmd "$SRC" "$@"; rc=$?
  fi
  # ⚠️ Fuori dalla radice, nel ripiego, NON si classifica: la prova della base scriverebbe il contenuto
  # vecchio dentro il REPOSITORY. Non conclusivo -> UNRESOLVED, mai un PASS silenzioso.
  # Solo se una classificazione era stata CHIESTA: senza --base non si sarebbe classificato comunque, e
  # quei path restano SKIPPED come sul percorso della copia. Altrimenti l'inner loop, che --base non lo
  # passa, prenderebbe un BLOCKED ogni volta che la copia e' occupata, cioe' a ogni evento ordinario.
  if [ "$MODE" = lint ] && [ ${#EXTRA[@]} -gt 0 ]; then
    if [ -z "$BASE" ]; then
      echo "vitest-fast: fuori da $RAD, non classificati (manca --base):"
      for e in "${EXTRA[@]}"; do echo "  SKIPPED     ${e##*|}"; done
    else
      echo "vitest-fast: fuori da $RAD, NON classificati (ripiego su /mnt/c):"
      for e in "${EXTRA[@]}"; do echo "  UNRESOLVED  ${e##*|}"; done
      if [ "$rc" -eq 0 ]; then
        echo "vitest-fast: esito=UNRESOLVED (lint fuori dalla radice $RAD non classificabile nel ripiego) $dich"
        exit 3
      fi
    fi
  fi
  if [ "$MODE" = lint ] && [ $# -eq 0 ]; then
    echo "vitest-fast: esito=SKIPPED (fuori dalla radice del modulo: $RAD) $dich"
    exit 0
  fi
  echo "vitest-fast: esito=$(esito_di $rc) $dich"
  exit $rc
}

# Copia non utilizzabile: BLOCKED (exit 3), mai un ripiego silenzioso su /mnt/c. Il ripiego resta
# possibile solo se chi chiama lo chiede esplicitamente con FIC_ALLOW_MNT_C=1, e allora e' dichiarato
# nella prima riga e nella riga d'esito.
non_disponibile() {  # <motivo> <file…>
  [ "${FIC_ALLOW_MNT_C:-}" = 1 ] && fallback "$@"
  echo "vitest-fast: esito=BLOCKED (copia non utilizzabile: $1; ripiego su /mnt/c solo con FIC_ALLOW_MNT_C=1) luogo=-"
  exit 3
}

risincronizza() {  # sync COMPLETO con cancellazione (il sync di prima di pt06; primo run e ripiego del ripiego)
  rsync -a --delete --checksum "${EXCL[@]}" "$SRC/" "$DST/"
}

# ─── Sync incrementale (harness-pt06) ──────────────────────────────────────────────────────────────────
# Stato PER COPIA, nella radice della copia (escluso dal sync e dalla rilevazione delle scritture: `.fic-*`).
SYNC_SRC_CACHE=${DST:+$DST/.fic-sync-src}   # "<dim> <mtime> <ctime> <inode>\t<sha256>\t<path>" dell'origine
SYNC_GEN=${DST:+$DST/.fic-sync-gen}         # impronta dipendenze + tsconfig generato all'ultima pulizia

# Preparati e cache ripuliti solo quando cambia cio' da cui dipendono: le dipendenze (l'impronta registrata dal
# --setup, gia' verificata da deps_ok) o il file guida dei preparati nell'origine. Prima di pt06 lo si faceva a
# ogni run, e ogni run pagava la rigenerazione da zero. Nel modulo senza preparati conta solo l'impronta.
gen_key() {
  local t=assente
  [ -n "$GUIDA" ] && [ -f "$SRC$G/$GUIDA" ] && t=$(sha256sum < "$SRC$G/$GUIDA" | cut -c1-64)
  printf 'deps=%s preparati=%s\n' "$(cat "$DST/.fic-deps" 2>/dev/null)" "$t"
}
pulizia_del_modulo() { # PUL_RUN (controprova.runner) e PUL_PREP (preparati) del modulo della copia, da maat.json
  local out i
  PUL_RUN=""; PUL_PREP=()
  out=$(mc leggi --tutto | tr -d '\r') || return 1
  i=$(printf '%s\n' "$out" | awk -F'\t' -v m="$MODULO" '$1 ~ /^moduli\.[0-9]+\.nome$/ && $2 == m { split($1, a, "."); print a[2]; exit }')
  [ -n "$i" ] || return 1
  PUL_RUN=$(printf '%s\n' "$out" | awk -F'\t' -v k="moduli.$i.controprova.runner" '$1 == k { print $2; exit }')
  mapfile -t PUL_PREP < <(printf '%s\n' "$out" | awk -F'\t' -v p="moduli.$i.preparati." 'index($1, p) == 1 && substr($1, length(p) + 1) ~ /^[0-9]+$/ { print $2 }')
}
# letti una volta (PREP_OK): i preparati, il loro file guida (GUIDA: il primo glob senza caratteri jolly, come
# ciclo-worktree.sh) e il runner; 1 se maat.json non si legge
PREP_OK="" GUIDA=""
preparati_carica() {
  local g
  [ -n "$PREP_OK" ] && { [ "$PREP_OK" = 1 ]; return; }
  PREP_OK=0; pulizia_del_modulo || return 1
  for g in ${PUL_PREP[@]+"${PUL_PREP[@]}"}; do case $g in *[*?[]*) ;; *) GUIDA=$g; break ;; esac; done
  PREP_OK=1
}
pulisci_generati() {   # la pulizia del motore della copia (fic_mirror_pulisci), la stessa di counterproof.sh
  local k
  preparati_carica || return 1
  k=$(gen_key)
  [ -f "$SYNC_GEN" ] && [ "$(cat "$SYNC_GEN")" = "$k" ] && return 0
  fic_mirror_pulisci "$DST" "$GROUP" "$PUL_RUN" ${PUL_PREP[@]+"${PUL_PREP[@]}"} || return 1
  printf '%s\n' "$k" > "$SYNC_GEN"
  echo "vitest-fast: generati della copia ripuliti (preparati e cache: impronta delle dipendenze o file guida dei preparati cambiati)"
}

# Hash dell'origine come `hashes "$SRC" <lista>` (stesso formato, stesso ordine), ma attraverso /mnt/c si
# rileggono solo i file la cui stat (dimensione, mtime, ctime, inode, al nanosecondo) non e' quella registrata
# in SYNC_SRC_CACHE. PREMESSA: una scrittura aggiorna sempre la ctime, anche su drvfs (/mnt/c) e anche
# quando scrive Windows; provata da test-fast.test.sh (sonda drvfs, sezione 32) ma non garantita da nessuno.
# Per questo la cache NON e' l'unica difesa: vedi l'audit completo qui sotto (SYNC_AUDIT).
# La stat si prende PRIMA di leggere: se il file cambia nel mezzo, la stat registrata e' la vecchia e il run
# successivo lo rilegge. `stat -L`: un symlink conta per il suo bersaglio, come `hashes` (che lo legge).
# Aggiorna la cache (rinomina atomica).
hashes_src() {  # <lista> -> stdout
  local l=$1 cache=/dev/null
  [ -f "$SYNC_SRC_CACHE" ] && cache=$SYNC_SRC_CACHE
  (cd "$SRC" && tr '\n' '\0' < "$l" | xargs -0 -r stat -L --printf '%s %.9Y %.9Z %i\t%n\n' 2>/dev/null) > "$TMPD/stat"
  : > "$TMPD/todo"; : > "$TMPD/known"
  # stat assente = file assente (ABSENT, come `hashes`) · stat uguale a quella registrata = sha registrato ·
  # altrimenti il file si rilegge
  awk -F'\t' -v todo="$TMPD/todo" -v known="$TMPD/known" '
    FILENAME == ARGV[1] { ck[$3] = $1; ch[$3] = $2; next }
    FILENAME == ARGV[2] { s[$2] = $1; next }
    $0 == "" { next }
    !($0 in s) { print "ABSENT  " $0 > known; next }
    ($0 in ck) && ck[$0] == s[$0] { print ch[$0] "  " $0 > known; next }
    { print > todo }
  ' "$cache" "$TMPD/stat" "$l"
  hashes "$SRC" "$TMPD/todo" > "$TMPD/fresh"
  LC_ALL=C sort -t ' ' -k3 "$TMPD/known" "$TMPD/fresh" > "$TMPD/src.new"
  # nuova cache: stat presa sopra + sha di questo run, solo per i file presenti
  awk -F'\t' 'FILENAME == ARGV[1] { s[$2] = $1; next }
    { i = index($0, "  "); h = substr($0, 1, i - 1); p = substr($0, i + 2) }
    h != "ABSENT" && (p in s) { print s[p] "\t" h "\t" p }' "$TMPD/stat" "$TMPD/src.new" > "$SYNC_SRC_CACHE.tmp" &&
    mv -f "$SYNC_SRC_CACHE.tmp" "$SYNC_SRC_CACHE"
  rm -f "$TMPD/todo" "$TMPD/known" "$TMPD/fresh"
  cat "$TMPD/src.new"
}

# Rete di sicurezza della cache (SYNC_AUDIT): ogni FIC_SYNC_AUDIT_RUNS run (default 20) o quando l'ultimo
# controllo completo ha piu' di FIC_SYNC_AUDIT_SECS secondi (default 1800), l'origine si rilegge TUTTA,
# ignorando la cache, e si confronta con cio' che la cache ha detto. Una differenza vuol dire che la premessa
# della stat non ha tenuto: cache buttata, sync completo, avviso esplicito. Stato: "<epoch> <run dall'ultimo>".
SYNC_AUDIT=${DST:+$DST/.fic-sync-audit}
# Lo stato si VALIDA prima di ogni aritmetica: con `set -u` un valore come `abc` farebbe morire lo script
# senza riga d'esito, e `1.5` farebbe saltare l'audit per un errore aritmetico — a ogni run, perche' lo stato
# non verrebbe mai riscritto. Stato assente o non valido = `0 0`, cioe' audit dovuto (e poi riscritto valido).
# Le soglie non numeriche valgono il default.
audit_leggi() {  # -> AUD_EP AUD_NR, interi
  local ep="" nr=""
  [ -f "$SYNC_AUDIT" ] && read -r ep nr _ < "$SYNC_AUDIT" 2>/dev/null
  if [[ $ep =~ ^[0-9]+$ ]] && [[ $nr =~ ^[0-9]+$ ]]; then AUD_EP=$((10#$ep)); AUD_NR=$((10#$nr)); else AUD_EP=0; AUD_NR=0; fi
}
audit_dovuto() {
  local now runs=${FIC_SYNC_AUDIT_RUNS:-20} secs=${FIC_SYNC_AUDIT_SECS:-1800}
  [[ $runs =~ ^[0-9]+$ ]] || runs=20
  [[ $secs =~ ^[0-9]+$ ]] || secs=1800
  audit_leggi
  now=$(date +%s)
  [ $((AUD_NR + 1)) -ge "$((10#$runs))" ] || [ $((now - AUD_EP)) -ge "$((10#$secs))" ]
}
audit_registra() {  # <0 = controllo completo fatto | 1 = run con la sola cache>
  audit_leggi
  if [ "$1" = 0 ]; then printf '%s 0\n' "$(date +%s)" > "$SYNC_AUDIT"
  else printf '%s %s\n' "$AUD_EP" "$((AUD_NR + 1))" > "$SYNC_AUDIT"; fi
}

# Allinea la copia sul DIFF fra i due manifest: copiato se lo sha differisce, cancellato se assente
# nell'origine. `--remove-destination`: il file della copia si sostituisce, non si riscrive sul posto (un
# hardlink verso un'altra copia non verrebbe mai toccato). Poi i file della copia FUORI dal manifest che
# nell'origine non esistono (non tracciati cancellati, scritture di un run precedente): via, come
# `rsync --delete`. Torna il numero di file toccati su stdout.
allinea_diff() {  # <hash origine> <hash copia>
  local p n=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -e "$SRC/$p" ] || [ -L "$SRC/$p" ]; then
      mkdir -p "$DST/$(dirname "$p")" && cp -Pp --remove-destination "$SRC/$p" "$DST/$p" || return 1
    else
      rm -f "$DST/$p" || return 1
    fi
    n=$((n + 1))
  done < <(diff "$1" "$2" | sed -n 's/^< [^ ]*  //p' | LC_ALL=C sort -u)
  (cd "$DST" && find . \( -name node_modules -o -name .nuxt -o -name .output -o -name coverage -o -name .turbo \) -prune \
      -o \( -type f -o -type l \) ! -name '.fic-*' -print | sed 's|^\./||' | LC_ALL=C sort) > "$TMPD/dstfiles"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ ! -e "$SRC/$p" ] && [ ! -L "$SRC/$p" ]; then rm -f "$DST/$p" || return 1; n=$((n + 1)); fi
  done < <(LC_ALL=C comm -23 "$TMPD/dstfiles" "$TMPD/list")
  echo "$n"
}

# Lint: perimetro deciso PRIMA di eseguire (solo la radice del modulo, solo estensioni lintabili).
# Niente da lintare -> SKIPPED, senza toccare la copia. Il ciclo sta qui, non in una funzione: una
# sottoshell perderebbe le due liste. LINT e EXTRA hanno i path relativi a radice_pacchetti.
if [ "$MODE" = lint ]; then
  for p in "$@"; do
    p=${p#./}
    # File eliminato dalla modifica: niente da lintare (eslint uscirebbe 2 -> BLOCKED su codice sano).
    case "$p" in
      "$PKG"/*) if [ ! -e "$ROOT/$p" ]; then DELETED+=("$p"); continue; fi ;;
    esac
    case "$p" in
      "$RAD"/*)
        case "$p" in
          *.ts|*.tsx|*.vue|*.js) LINT+=("${p#"$PKG"/}") ;;
          *) SKIP+=("$p") ;;   # .md, .scss, immagini: eslint uscirebbe >=2 e il gate sarebbe BLOCKED
        esac ;;
      "$PKG"/*)
        # Altro pacchetto del workspace: non e' il gate, ma non e' nemmeno "innocuo per definizione" quando il
        # modulo dichiara lint_base. Gruppo = i due segmenti dopo radice_pacchetti (apps/<x> o packages/<x>),
        # cioe' la radice del pacchetto, cioe' la cwd che risolve la configurazione giusta.
        r=${p#"$PKG"/}; a=${r%%/*}; b=${r#*/}
        if [ "$LINT_BASE" = true ] && { [ "$a" = apps ] || [ "$a" = packages ]; } && [ "$b" != "${b#*/}" ]; then
          case "$p" in
            *.ts|*.tsx|*.vue|*.js) EXTRA+=("$a/${b%%/*}|${b#*/}|$p") ;;
            *) SKIP+=("$p") ;;
          esac
        else
          SKIP+=("$p")
        fi ;;
      *)
        # Un path che contiene la radice (o la sua parte sotto radice_pacchetti) ma non e' ancorato al repo
        # (assoluto, o con un prefisso diverso) e' un errore del chiamante, non un file fuori perimetro:
        # dichiararlo SKIPPED lascerebbe passare come "niente da lintare" un file che va lintato.
        if [[ $p == */"$RAD"/* ]] || { [ -n "$GROUP" ] && [[ $p == */"$GROUP"/* ]]; }; then
          echo "vitest-fast: path non relativo al repository: $p" >&2; exit 64
        fi
        SKIP+=("$p") ;;
    esac
  done
  [ ${#SKIP[@]} -eq 0 ] || {
    echo "vitest-fast: fuori dalla radice del modulo ($RAD), non lintati:"
    printf '  %s\n' "${SKIP[@]}"
  }
  [ ${#DELETED[@]} -eq 0 ] || {
    echo "vitest-fast: eliminati nel working tree, non lintati:"
    printf '  %s\n' "${DELETED[@]}"
  }
  if [ ${#LINT[@]} -eq 0 ] && [ ${#EXTRA[@]} -eq 0 ]; then
    if [ ${#SKIP[@]} -eq 0 ]; then
      echo "vitest-fast: esito=SKIPPED (solo file eliminati) luogo=-"
    else
      echo "vitest-fast: esito=SKIPPED (fuori dalla radice del modulo: $RAD) luogo=-"
    fi
    exit 0
  fi
  # ⚠️ I PREPARATI servono prima di qualunque ripiego (es. il tsconfig generato, che `<radice>/tsconfig.json`
  # estende: senza, eslint sbaglia la risoluzione di OGNI import — misurato, 10 errori inventati contro 1 vero).
  # Su /mnt/c mancano allo stesso modo, quindi ripiegare non aiuta: e' un guasto d'ambiente, cioe' BLOCKED (Step
  # 2.5), mai FAIL su codice sano. Il rimedio e' la `preparazione` del modulo. Modulo senza preparati: nessun requisito.
  if [ ${#LINT[@]} -gt 0 ]; then
    preparati_carica || { echo "vitest-fast: esito=BLOCKED (preparati del modulo $MODULO non leggibili da maat.json) luogo=-"; exit 2; }
    if [ -n "$GUIDA" ] && [ ! -f "$SRC$G/$GUIDA" ]; then
      echo "vitest-fast: esito=BLOCKED (preparato assente: $RAD/$GUIDA; eseguire '${PREP:-la preparazione del modulo}' in $RAD) luogo=-"
      exit 2
    fi
  fi
  set -- ${LINT[@]+"${LINT[@]}"}
fi

# Lint: servono i PREPARATI della radice. Le loro cartelle sono escluse dal sync (generate, pesano), quindi qui si
# portano i soli file dei glob di `preparati` (il file guida e' obbligatorio, gli altri se ci sono): per esempio
# il tsconfig generato, autoconsistente (i suoi path puntano a node_modules, presente nella copia).
# Va rifatto dopo ogni risincronizzazione, che ripulisce le cartelle dei preparati nella copia.
tsconfig_lint() {
  local g f rel
  [ "$MODE" = lint ] || return 0
  preparati_carica || return 1
  for g in ${PUL_PREP[@]+"${PUL_PREP[@]}"}; do
    for f in "$SRC$G/"$g; do   # $g senza virgolette: il * del glob si espande nell'origine
      [ -f "$f" ] || { [ "$g" = "$GUIDA" ] && return 1; continue; }
      rel=${f#"$SRC$G/"}
      mkdir -p "$(dirname "$DST$G/$rel")" && cp "$f" "$DST$G/$rel" || return 1
    done
  done
}

# Senza radice non c'e' una copia associabile a questo tree (e nemmeno il manifest, che usa lo stesso git).
[ -n "$DST" ] || non_disponibile "manifest non calcolabile (git: radice del repository non determinabile, nessuna copia associabile)" "$@"
# Primo uso della copia di un worktree: node_modules seminati dalla copia del tree principale (hardlink),
# se le dipendenze coincidono; altrimenti resta "copia assente", con il motivo.
SEED_WHY=""
if [ "$MIRROR" != "$HOME/fic-mirror" ] && ! { [ -d "$DST/node_modules" ] && [ -f "$DST/.fic-deps" ]; }; then
  if SEED_WHY=$(fic_seed_node_modules "$SRC" "$DST"); then
    if [ -n "$FIC_LANE_BASE" ]; then echo "vitest-fast: copia della corsia $FIC_LANE seminata da $FIC_LANE_BASE (node_modules in hardlink)"
    else echo "vitest-fast: copia del worktree seminata da ~/fic-mirror (node_modules in hardlink)"; fi
  elif [ -n "$FIC_LANE_BASE" ]; then
    SEED_WHY="; semina da $FIC_LANE_BASE non possibile: $SEED_WHY"
  else
    SEED_WHY="; semina da ~/fic-mirror non possibile: $SEED_WHY"
  fi
fi
[ -d "$DST/node_modules" ] && [ -f "$DST/.fic-deps" ] || non_disponibile "copia assente: eseguire --setup$SEED_WHY" "$@"
exec 9>"$DST/.fic-lock"
# Copia occupata da un altro run: si ATTENDE (tetto FIC_LOCK_WAIT secondi), non si ripiega su /mnt/c.
LOCK_WAIT=${FIC_LOCK_WAIT:-900}
flock -w "$LOCK_WAIT" 9 || non_disponibile "copia occupata da un altro run oltre ${LOCK_WAIT}s (FIC_LOCK_WAIT)" "$@"
# Dipendenze stantie: riallineamento automatico dentro il lock (fic-mirror.sh, fic_deps_autorefresh), poi di nuovo
# deps_ok. pulisci_generati qui sotto vede l'impronta nuova e ripulisce preparati e cache.
if ! deps_ok; then
  DEPS_OUT=$(fic_deps_autorefresh "$SRC" "$DST") ||
    non_disponibile "dipendenze stantie, riallineamento automatico non riuscito: $DEPS_OUT" "$@"
  echo "vitest-fast: $DEPS_OUT"
  deps_ok || non_disponibile "dipendenze stantie anche dopo il riallineamento automatico" "$@"
fi
pulisci_generati || non_disponibile "pulizia dei generati della copia fallita" "$@"

TMPD=$(mktemp -d)
# Il trap ripristina anche i file scambiati con la versione della base durante la classificazione: se si
# muore li' in mezzo, la copia resta disallineata e il run successivo dovrebbe risincronizzarla.
# Il segnale diventa un'uscita normale, cosi' il trap EXIT (e quindi il ripristino della copia) gira di
# sicuro. ⚠️ Misurato il 2026-09-23: il bash di questa macchina esegue il trap EXIT anche su un TERM non
# gestito, quindi la suite NON distingue la presenza di questa riga (la controprova per mutazione resta
# verde). Resta perche' rende il comportamento indipendente da quel dettaglio di bash, non perche' un
# test lo dimostri: e' dichiarato, non finto.
trap 'exit 143' TERM INT HUP
trap 'if [ -s "$TMPD/swapped" ]; then while IFS= read -r q; do [ -n "$q" ] && cp "$SRC/$q" "$DST/$q" 2>/dev/null; done < "$TMPD/swapped"; fi; rm -rf "$TMPD"' EXIT
manifest_list > "$TMPD/list" && git -c safe.directory='*' -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
  [ -n "$(git -c safe.directory='*' -C "$SRC" ls-files . | head -1)" ] || non_disponibile "manifest non calcolabile (git)" "$@"
# Sync: COMPLETO senza stato della copia (primo run, copia nuova), altrimenti INCREMENTALE sul diff dei due
# manifest (vedi Garanzie). In entrambi i casi il confronto qui sotto e' quello di sempre.
SYNC=incrementale; SYNC_N=0
if [ ! -f "$SYNC_SRC_CACHE" ]; then
  SYNC=completo
  risincronizza || non_disponibile "sync fallito" "$@"
fi
hashes_src "$TMPD/list" > "$TMPD/src"
if [ "$SYNC" = completo ]; then
  audit_registra 0          # senza cache hashes_src ha riletto tutto: vale come controllo completo
elif audit_dovuto; then
  hashes "$SRC" "$TMPD/list" > "$TMPD/src.full"
  if cmp -s "$TMPD/src" "$TMPD/src.full"; then
    audit_registra 0
  else
    echo "vitest-fast: cache stat incompleta, resync completo"
    diff "$TMPD/src" "$TMPD/src.full" | head -5 | sed 's/^/  /'
    rm -f "$SYNC_SRC_CACHE"; SYNC=completo
    risincronizza || non_disponibile "sync fallito" "$@"
    hashes_src "$TMPD/list" > "$TMPD/src"   # cache ricostruita da zero
    audit_registra 0
  fi
else
  audit_registra 1
fi
hashes "$DST" "$TMPD/list" > "$TMPD/dst"
if [ "$SYNC" = incrementale ]; then
  SYNC_N=$(allinea_diff "$TMPD/src" "$TMPD/dst") || non_disponibile "sync incrementale fallito" "$@"
  [ "$SYNC_N" -eq 0 ] || hashes "$DST" "$TMPD/list" > "$TMPD/dst"
fi
tsconfig_lint || non_disponibile "preparati del modulo non copiabili" "$@"
# Copia disallineata: UNA risincronizzazione (sync COMPLETO, manifest ricalcolato, stato dell'origine
# ricostruito da zero), poi nuovo confronto. L'impronta delle dipendenze non c'entra: quella e' gia' stata
# verificata (e se serviva riallineata) sopra.
if ! cmp -s "$TMPD/src" "$TMPD/dst"; then
  echo "vitest-fast: differenze fra origine e copia:"; diff "$TMPD/src" "$TMPD/dst" | head -5
  echo "vitest-fast: copia non allineata: risincronizzazione"
  rm -f "$SYNC_SRC_CACHE"; SYNC=completo
  { risincronizza && tsconfig_lint && manifest_list > "$TMPD/list" &&
      hashes_src "$TMPD/list" > "$TMPD/src" && audit_registra 0 && hashes "$DST" "$TMPD/list" > "$TMPD/dst" &&
      cmp -s "$TMPD/src" "$TMPD/dst"; } || {
    echo "vitest-fast: differenze dopo la risincronizzazione:"; diff "$TMPD/src" "$TMPD/dst" | head -5
    non_disponibile "copia non allineata dopo la risincronizzazione" "$@"
  }
fi

echo "vitest-fast: luogo=copia"
if [ "$SYNC" = completo ]; then echo "vitest-fast: sync=completo"; else echo "vitest-fast: sync=incrementale ($SYNC_N file allineati)"; fi

# La classificazione fuori perimetro scrive e ripristina file della copia: va fatta PRIMA dello stamp,
# altrimenti la rilevazione delle scritture del run la vedrebbe come una scrittura del runner.
EXTRA_RC=0
if [ "$MODE" = lint ] && [ ${#EXTRA[@]} -gt 0 ]; then
  classify_extra; EXTRA_RC=$?
fi

touch "$TMPD/stamp"
rc=0
if [ "$MODE" != lint ] || [ $# -gt 0 ]; then
  run_cmd "$DST" "$@"; rc=$?
fi

# Qualunque scrittura nella copia durante il run: file del manifest cambiati o file nuovi (esclusi
# node_modules, .nuxt, .output, coverage e la cache).
hashes "$DST" "$TMPD/list" > "$TMPD/after"
written=$( { diff "$TMPD/dst" "$TMPD/after" | sed -n 's/^> [^ ]*  //p'
             (cd "$DST" && find . \( -name node_modules -o -name .nuxt -o -name .output -o -name coverage -o -name .turbo \) -prune \
                -o -type f -newer "$TMPD/stamp" ! -name '.fic-*' -print | sed 's|^\./||'); } | LC_ALL=C sort -u)
if [ -n "$written" ]; then
  echo "vitest-fast: il run ha scritto nella copia:"; echo "$written" | head -10 | sed 's/^/  /'
  echo "vitest-fast: esito=BLOCKED (snapshot da generare su /mnt/c: rilancia su /mnt/c e fai rivedere i file generati) luogo=copia"
  exit 4
fi

# Guardia di equivalenza (harness-pt06), INTERNA ai test: FIC_SYNC_EQUIV=1 nell'ambiente, mai un argomento.
# Sulla stessa copia e sullo stesso stato dell'origine: manifest della copia (piu' i file della copia assenti
# nell'origine) e codice d'uscita del runner dopo il sync appena fatto, poi sync COMPLETO e di nuovo. Devono
# coincidere: un file cambiato che il sync incrementale non ha allineato qui diventa una differenza.
stato_copia() {  # manifest della copia + file della copia fuori manifest e assenti nell'origine
  local p
  hashes "$DST" "$TMPD/list"
  (cd "$DST" && find . \( -name node_modules -o -name .nuxt -o -name .output -o -name coverage -o -name .turbo \) -prune \
      -o \( -type f -o -type l \) ! -name '.fic-*' -print | sed 's|^\./||' | LC_ALL=C sort) |
    LC_ALL=C comm -23 - "$TMPD/list" | while IFS= read -r p; do
      [ -e "$SRC/$p" ] || [ -L "$SRC/$p" ] || echo "EXTRA  $p"
    done
}
if [ "${FIC_SYNC_EQUIV:-}" = 1 ]; then
  stato_copia > "$TMPD/eq.sync"
  risincronizza || { echo "vitest-fast: esito=BLOCKED (equivalenza: sync completo fallito) luogo=copia"; exit 3; }
  tsconfig_lint
  stato_copia > "$TMPD/eq.full"
  rc2=0
  if [ "$MODE" != lint ] || [ $# -gt 0 ]; then
    run_cmd "$DST" "$@" > "$TMPD/eq.out" 2>&1; rc2=$?
  fi
  if cmp -s "$TMPD/eq.sync" "$TMPD/eq.full" && [ "$rc" -eq "$rc2" ]; then
    echo "vitest-fast: equivalenza=OK (sync $SYNC e sync completo: stesso manifest, stessa uscita $rc)"
  else
    echo "vitest-fast: equivalenza=DIFF (sync $SYNC: uscita $rc · sync completo: uscita $rc2)"
    diff "$TMPD/eq.sync" "$TMPD/eq.full" | head -10 | sed 's/^/  /'
    echo "vitest-fast: esito=BLOCKED (equivalenza violata fra sync $SYNC e sync completo) luogo=copia"
    exit 3
  fi
fi
# Esito finale del lint. Un guasto di configurazione (BLOCKED) vince su tutto: non si accusa il codice
# quando l'ambiente non ha funzionato. Poi gli errori veri — del gate o INTRODUCED fuori perimetro —,
# poi UNRESOLVED, che e' "non conclusivo" e non deve mai diventare un PASS.
if [ "$MODE" = lint ]; then
  if [ "$rc" -ge 2 ]; then
    echo "vitest-fast: esito=BLOCKED (eslint: configurazione o ambiente, uscita $rc) luogo=copia"; exit 2
  elif [ "$rc" -eq 1 ] || [ "$EXTRA_RC" -eq 1 ]; then
    echo "vitest-fast: esito=FAIL luogo=copia"; exit 1
  elif [ "$EXTRA_RC" -eq 3 ]; then
    echo "vitest-fast: esito=UNRESOLVED (lint fuori dalla radice $RAD non classificabile) luogo=copia"; exit 3
  elif [ ${#LINT[@]} -eq 0 ]; then
    echo "vitest-fast: esito=SKIPPED (fuori dalla radice del modulo: $RAD; $CLASSIFICATI classificati su ${#EXTRA[@]}) luogo=copia"; exit 0
  fi
  echo "vitest-fast: esito=PASS luogo=copia"; exit 0
fi
echo "vitest-fast: esito=$(esito_di $rc) luogo=copia"
exit $rc
