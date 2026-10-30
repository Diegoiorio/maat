#!/usr/bin/env bash
# replay.sh — rigioca UNA fase di un ciclo reale di /full-implementation-cycle in un git worktree
# usa-e-getta, con --no-dev, e la misura con cycle-report.py.
#
#   replay.sh <ciclo> <fase> [--harness <plugin>] [--source <dir>] [--worktree <path>] [--out <dir>]
#             [--inject <nome>]... [--dry-run]
#   replay.sh --check [--source <dir>]          i cicli del corpus: spec, run directory e base presenti?
#   replay.sh --remove <path> [--dry-run]       rimuove un worktree lasciato da un rigioco interrotto
#
#   Il progetto e' quello della cartella di lavoro (PROJECT_ROOT); il corpus e' il corpus.json indicato da
#   cartelle.corpus nella sua maat.json (relativo al repository; assente: nessun corpus, solo run directory per nome).
#   <ciclo>   id del corpus (per esempio `ciclo-1`) oppure il nome di QUALUNQUE run directory, anche fuori
#             corpus: `export-csv`, `spec-export-csv` o `spec-export-csv.run`
#             (base da base.txt)
#   <fase>    etichetta (`06-review`) o nome di fase (plan|implement|review|fix) se nel ciclo e' unica
#   --harness la RADICE DI UN PLUGIN maat (con .claude-plugin/plugin.json) da cui lanciare la fase: il suo
#             scripts/run-phase.sh, e lo stesso plugin caricato nella sotto-sessione (MAAT_PLUGIN_DIR, esportata
#             SEMPRE: il rigioco non dipende dall'abilitazione del plugin nel worktree) (default: MAAT_ROOT, il plugin
#             di questo script). Il harness NON si copia nel worktree
#   --source  la cartella con spec-*.md e spec-*.run/ (default: la cartella di lavoro, cartelle.lavoro, del tree
#             PRINCIPALE, risolto con `git rev-parse --git-common-dir`: le run directory sono gitignorate e stanno li')
#   --worktree dove creare il worktree (default: accanto al tree principale, fic-replay-<etichetta>-<ora>: corto,
#             per il limite dei percorsi di Windows);
#             il nome deve cominciare per fic-replay- e il percorso non deve esistere
#   --out     dove salvare log e report della fase rigiocata (default <source>/spec-<nome>.replay/<etichetta>-<ora>,
#             gitignorata dalla regola spec-*)
#   --inject  script di inject/ (senza .sh) da applicare al worktree prima della fase; ripetibile
#   --non-confrontabile  procede anche se le dipendenze allo stato della fase sono diverse da quelle del
#             tree principale (vedi sotto); il rigioco e' marcato NON CONFRONTABILE in report.txt e in
#             NON-CONFRONTABILE.txt dell'uscita
#   --dry-run stampa i comandi senza eseguirli: nessun worktree, nessun file, nessuna sessione
#
# Cosa fa, in ordine: `git worktree add --detach` alla base del ciclo; marcatore `fic-replay` nella git
# dir PROPRIA del worktree (fuori dal working tree, quindi mai superficie di review); il codice allo
# stato della fase — il .pre-tree dell'etichetta, altrimenti l'ultimo .post-tree precedente, altrimenti la
# base — applicato come modifiche NON committate (come nel ciclo vero); la spec (nel suo stato ATTUALE: la run
# directory non ne conserva le versioni) e la run
# directory fino alla fase esclusa (log e prompt delle etichette precedenti, base/do-not-touch/mixed se
# una implement o fix precede, touched.txt ricalcolato dalle coppie .pre/.post-tree precedenti); il
# prompt ORIGINALE della fase con --no-dev inserito dopo il nome e la skill col prefisso del plugin
# (/maat:full-implementation-cycle: la skill del plugin, non quella che il commit del ciclo avesse in .claude/skills);
# gli inject; la fase con scripts/run-phase.sh del plugin --harness, cwd nel worktree, MAAT_PLUGIN_DIR=<plugin>,
# con il lock del tree PRINCIPALE (FIC_LOCK: il mirror di vitest-fast e il DEV sono
# condivisi, quindi un rigioco non gira mai insieme a una fase di codice vera); copia dei log in --out;
# cycle-report.py su quella copia; `git worktree remove --force` SOLO dopo aver verificato che il
# percorso e' un worktree creato da replay.sh (nome fic-replay-*, marcatore col suo percorso, elencato da
# `git worktree list`, fuori dal tree principale e dal harness).
# Un rigioco interrotto mentre la fase gira ancora lascia il worktree (rimuoverlo sotto una sessione
# viva sarebbe peggio): si toglie dopo con --remove.
#
# Dipendenze (i gate della fase devono girare come nell'originale, senza installare nulla):
# - PRIMA di creare il worktree: i file delle dipendenze (package.json e package-lock.json della radice
#   e di modules/app, modules/api/requirements*.txt) allo stato della fase devono coincidere con quelli
#   del tree principale (`git diff` fra quel tree e il working tree principale, stessa logica di git
#   status: CRLF compresi). Se no: uscita 2, niente worktree; --non-confrontabile per procedere comunque;
# - node_modules (radice, modules/app, apps/*, packages/*) e modules/api/.venv del tree principale sono
#   COLLEGATI nel worktree (junction su Windows, symlink altrove), mai copiati ne' installati; di
#   apps/admin/.nuxt si copiano tsconfig.json e *.d.ts (il lint ne ha bisogno: vitest-fast.sh);
# - il .git del worktree punta alla git dir con un percorso RELATIVO (`git worktree add` scrive "gitdir: C:/…";
#   vitest-fast.sh e counterproof.sh ora lo traducono da se', via script/test/fic-mirror.sh: il relativo resta
#   come difesa in piu');
# - copia WSL del worktree: vitest-fast.sh e counterproof.sh usano ~/fic-mirror-<hash> (una per radice) e,
#   al primo uso, ne SEMINANO node_modules in hardlink dalla copia del tree principale, se le dipendenze
#   coincidono (impronta sul contenuto senza CR: le fine riga del checkout nuovo non contano piu', niente
#   copia dei byte). Impronta diversa: avviso nel log e nel report (la copia non si semina e i gate escono
#   BLOCKED), senza fermarsi;
# - rimozione: PRIMA le copie WSL del worktree (fic_lane_forget k=1,2 per le corsie, poi fic_mirror_forget:
#   mai ~/fic-mirror; se un run la tiene,
#   resta con un avviso — da cancellare poi con lo stesso comando), POI si tolgono i collegamenti (solo il
#   collegamento, mai ricorsivo), POI `git worktree remove --force`; se un collegamento resta, il worktree
#   NON si rimuove (seguirlo cancellerebbe le dipendenze del tree principale). Nessuna copia
#   ~/fic-mirror-<hash> orfana a fine rigioco.
# Limite noto: un prompt che cita percorsi assoluti del tree principale li cita ancora.
#
# Uscita: quella della fase · 0 --check/--remove/--dry-run riusciti · 1 --check con mancanze ·
#         2 uso o dati del ciclo non validi · 3 percorso rifiutato (non e' un worktree di replay.sh).

set -uo pipefail
unset MSYS_NO_PATHCONV
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
. "$HERE/../lib/maat-paths.sh" || exit 4   # MAAT_SCRIPTS (plugin) e PROJECT_ROOT (cartella di lavoro)
maat_progetto || exit 4
ROOT=$PROJECT_ROOT
CR="$MAAT_SCRIPTS/cycle-report.py"

die() { echo "replay: $*" >&2; exit 2; }
refuse() { echo "replay: RIFIUTO — $*" >&2; exit 3; }
q() { printf '%q' "$1"; }
# winpath, canon, collegamento e scollegamento delle dipendenze, .git relativo, impronta, copia WSL: la
# libreria condivisa con script/fic/ciclo-worktree.sh (messaggi col prefisso «replay:», come prima)
WT_TAG=replay DEP_LINKS_EXTRA=()
. "$MAAT_SCRIPTS/worktree-lib.sh" || die "$MAAT_SCRIPTS/worktree-lib.sh o $MAAT_SCRIPTS/fic-mirror.sh non trovati"
LAVORO=.claude/.ai-workflow   # la cartella di lavoro (cartelle.lavoro), relativa alla radice del repository
[ -n "$MAAT_WORK" ] && LAVORO=${MAAT_WORK#"$PROJECT_ROOT"/}

common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "git non trova il repository di $ROOT"
MAIN=$(cd "$(dirname "$common")" && pwd) || die "tree principale non risolto da $common"
MAINGIT=$(git -C "$MAIN" rev-parse --absolute-git-dir 2>/dev/null) || die "git dir del tree principale non risolta"
MAINC=$(canon "$MAIN") ROOTC=$(canon "$ROOT") MAATC=$(canon "$MAAT_ROOT")

# --- verifica: il percorso e' un worktree creato da replay.sh? (0 = si'; altrimenti il motivo su stderr) ---
ours() {
  local p c gd mk w found=0
  p=$1
  [ -d "$p" ] || { echo "non esiste: $p" >&2; return 1; }
  c=$(canon "$p")
  case "$c" in "$MAINC"|"$MAINC"/*) echo "e' il tree principale o sta dentro: $c" >&2; return 1 ;; esac
  case "$c" in "$ROOTC"|"$ROOTC"/*) echo "e' il tree del progetto o sta dentro: $c" >&2; return 1 ;; esac
  case "$c" in "$MAATC"|"$MAATC"/*) echo "e' il plugin (harness) o sta dentro: $c" >&2; return 1 ;; esac
  case "$(basename "$c")" in fic-replay-*) ;; *) echo "il nome non comincia per fic-replay-: $c" >&2; return 1 ;; esac
  [ "$(canon "$(git -C "$c" rev-parse --show-toplevel 2>/dev/null)")" = "$c" ] ||
    { echo "non e' la radice di un worktree git: $c" >&2; return 1; }
  gd=$(git -C "$c" rev-parse --absolute-git-dir 2>/dev/null)
  mk="$gd/fic-replay"
  [ -f "$mk" ] || { echo "manca il marcatore di replay.sh ($mk)" >&2; return 1; }
  [ "$(canon "$(sed -n 's/^path=//p' "$mk")")" = "$c" ] || { echo "il marcatore indica un altro percorso: $(sed -n 's/^path=//p' "$mk")" >&2; return 1; }
  while IFS= read -r w; do [ "$(canon "$w")" = "$c" ] && found=1; done < <(git -C "$MAIN" worktree list --porcelain | sed -n 's/^worktree //p')
  [ $found -eq 1 ] || { echo "non e' fra i worktree del repository principale: $c" >&2; return 1; }
  return 0
}

# FIC_REPLAY_LIB=1: solo le funzioni (per i test, che le provano su cartelle sintetiche)
[ "${FIC_REPLAY_LIB:-0}" = 1 ] && return 0

# --- argomenti ---
DRY=0 MODE=replay HARNESS=$MAAT_ROOT SRC="" WT="" OUT="" INJECT=() POS=() RM_PATH="" ALLOW_DEPS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --non-confrontabile) ALLOW_DEPS=1; shift ;;
    --check) MODE=check; shift ;;
    --remove) MODE=remove; RM_PATH=${2:-}; [ -n "$RM_PATH" ] || die "--remove vuole un percorso"; shift 2 ;;
    --harness) HARNESS=${2:-}; [ -n "$HARNESS" ] || die "--harness vuole la radice di un plugin"; shift 2 ;;
    --source) SRC=${2:-}; [ -n "$SRC" ] || die "--source vuole una cartella"; shift 2 ;;
    --worktree) WT=${2:-}; [ -n "$WT" ] || die "--worktree vuole un percorso"; shift 2 ;;
    --out) OUT=${2:-}; [ -n "$OUT" ] || die "--out vuole una cartella"; shift 2 ;;
    --inject) [ -n "${2:-}" ] || die "--inject vuole un nome"; INJECT+=("$2"); shift 2 ;;
    -*) die "opzione sconosciuta: $1" ;;
    *) POS+=("$1"); shift ;;
  esac
done
SRC=${SRC:-$MAIN/$LAVORO}
[ -d "$SRC" ] || die "cartella delle spec assente: $SRC"
SRC=$(cd "$SRC" && pwd)

# --- --remove ---
if [ "$MODE" = remove ]; then
  [ ${#POS[@]} -eq 0 ] || die "--remove non vuole altri argomenti"
  ours "$RM_PATH" || refuse "$RM_PATH non e' un worktree creato da replay.sh: non lo rimuovo"
  c=$(canon "$RM_PATH")
  echo "+ forget_mirror $(q "$c")"
  echo "+ unlink_deps $(q "$c")"
  echo "+ git -C $(q "$MAIN") worktree remove --force $(q "$c")"
  [ $DRY -eq 1 ] && exit 0
  forget_mirror "$c"
  unlink_deps "$c" || refuse "collegamenti ancora presenti in $c: non lo rimuovo (seguirebbe le dipendenze del tree principale)"
  git -C "$MAIN" worktree remove --force "$c"
  exit $?
fi

. "$MAAT_SCRIPTS/python.sh" || die "interprete Python non trovato (imposta FIC_PYTHON)"
# il corpus del PROGETTO (cartelle.corpus di maat.json, relativo al repository), mai uno del plugin
CORPUS_W=""
if [ -n "${MAAT_CONFIG:-}" ] || [ -f "$ROOT/.claude/maat.json" ]; then
  . "$MAAT_SCRIPTS/lib/maat-conf.sh" || die "lettore della configurazione non trovato: $MAAT_SCRIPTS/lib/maat-conf.sh"
  cc=$(PROJECT_ROOT=$ROOT maat_conf cartelle.corpus 2>/dev/null | tr -d '\r') || cc=""
  if [ -n "$cc" ]; then
    [ -f "$ROOT/$cc" ] || die "corpus di cartelle.corpus assente: $ROOT/$cc"
    CORPUS_W=$(winpath "$ROOT/$cc")
  fi
fi
corpus() { # $1 = id → "<run>\t<spec>\t<base>" ; senza argomento → tutte le righe "<id>\t<run>\t<spec>\t<base>"
  [ -n "$CORPUS_W" ] || return 0   # nessun corpus: solo run directory per nome
  "$FIC_PY" -c '
import json, sys
cs = json.load(open(sys.argv[1], encoding="utf-8"))["cicli"]
for c in cs:
    if len(sys.argv) < 3:
        print("\t".join([c["id"], c["run"], c["spec"], c["base"]]))
    elif c["id"] == sys.argv[2]:
        print("\t".join([c["run"], c["spec"], c["base"]]))
' "$CORPUS_W" "$@" | tr -d '\r'
}

# --- --check ---
if [ "$MODE" = check ]; then
  [ ${#POS[@]} -eq 0 ] || die "--check non vuole altri argomenti"
  [ -n "$CORPUS_W" ] || die "nessun corpus: cartelle.corpus non impostata nella maat.json del progetto ($ROOT)"
  miss=0
  while IFS=$'\t' read -r id run spec base; do
    s="ok"
    [ -f "$SRC/$spec" ] || { s="SPEC MANCANTE ($spec)"; miss=1; }
    [ -d "$SRC/$run" ] || { s="$s · RUN DIRECTORY MANCANTE ($run)"; miss=1; }
    b=$(tr -d '\r\n ' 2>/dev/null < "$SRC/$run/base.txt")
    [ "$b" = "$base" ] || { s="$s · base.txt ($b) diversa da corpus.json ($base)"; miss=1; }
    git -C "$MAIN" cat-file -e "$base^{commit}" 2>/dev/null || { s="$s · commit di base assente"; miss=1; }
    echo "$id: $s"
  done < <(corpus)
  exit $miss
fi

# --- ciclo e fase ---
[ ${#POS[@]} -eq 2 ] || die "uso: replay.sh <ciclo> <fase> [--harness <tree>] [--source <dir>] [--worktree <path>] [--out <dir>] [--inject <nome>]... [--dry-run] | --check | --remove <path>"
CYC=${POS[0]} FASE=${POS[1]}
row=$(corpus "$CYC")
if [ -n "$row" ]; then
  IFS=$'\t' read -r run spec cbase <<< "$row"
  NAME=${run#spec-}; NAME=${NAME%.run}
else
  NAME=${CYC#spec-}; NAME=${NAME%.run}; NAME=${NAME%.md}; cbase=""
fi
RUN_SRC="$SRC/spec-$NAME.run" SPEC_SRC="$SRC/spec-$NAME.md"
[ -f "$SPEC_SRC" ] || die "spec mancante: $SPEC_SRC"
[ -d "$RUN_SRC/log" ] || die "run directory mancante o senza log: $RUN_SRC"
BASE=$(tr -d '\r\n ' 2>/dev/null < "$RUN_SRC/base.txt")
[ -n "$cbase" ] && [ -n "$BASE" ] && [ "$cbase" != "$BASE" ] && die "base di corpus.json ($cbase) diversa da base.txt ($BASE)"
BASE=${BASE:-$cbase}
[ -n "$BASE" ] || die "base del ciclo sconosciuta: manca $RUN_SRC/base.txt"
git -C "$MAIN" cat-file -e "$BASE^{commit}" 2>/dev/null || die "commit di base assente dal repository: $BASE"

LABELS=$(for f in "$RUN_SRC"/prompts/*.md "$RUN_SRC"/log/*.jsonl; do
  [ -e "$f" ] || continue; b=$(basename "$f"); b=${b%.md}; b=${b%.jsonl}; echo "$b"
done | grep -E '^[0-9]+-[a-z]+$' | sort -u)
if printf '%s' "$FASE" | grep -qE '^[0-9]+-[a-z]+$'; then
  printf '%s\n' "$LABELS" | grep -qxF "$FASE" || die "etichetta $FASE assente in $RUN_SRC (etichette: $(echo $LABELS))"
  LABEL=$FASE
else
  case "$FASE" in plan|implement|review|fix) ;; *) die "fase sconosciuta: $FASE (plan|implement|review|fix o un'etichetta NN-fase)" ;; esac
  cand=$(printf '%s\n' "$LABELS" | grep -E "^[0-9]+-$FASE\$")
  [ -n "$cand" ] || die "nessuna fase $FASE in $RUN_SRC (etichette: $(echo $LABELS))"
  [ "$(printf '%s\n' "$cand" | wc -l)" -eq 1 ] || die "fase $FASE ambigua: indica l'etichetta ($(echo $cand))"
  LABEL=$cand
fi
PHASE=${LABEL#*-} NUM=$((10#${LABEL%%-*}))
PROMPT_SRC="$RUN_SRC/prompts/$LABEL.md"
[ -f "$PROMPT_SRC" ] || die "prompt originale assente: $PROMPT_SRC"
head -1 "$PROMPT_SRC" | grep -qE "^/(maat:)?full-implementation-cycle --worker=$PHASE [^ ]+" ||
  die "la prima riga del prompt non e' /full-implementation-cycle (o /maat:full-implementation-cycle) --worker=$PHASE <nome>: $PROMPT_SRC"

EARLIER=$(printf '%s\n' "$LABELS" | while read -r l; do [ -n "$l" ] && [ $((10#${l%%-*})) -lt $NUM ] && echo "$l"; done)
code_before=0
for l in $EARLIER; do case "$l" in *-implement|*-fix) code_before=1 ;; esac; done

# stato del codice all'inizio della fase
STATE="" STATE_FROM="base $BASE"
if [ -f "$RUN_SRC/log/$LABEL.pre-tree" ]; then
  STATE=$(tr -d '\r\n ' < "$RUN_SRC/log/$LABEL.pre-tree"); STATE_FROM="log/$LABEL.pre-tree"
else
  for l in $EARLIER; do
    [ -f "$RUN_SRC/log/$l.post-tree" ] && { STATE=$(tr -d '\r\n ' < "$RUN_SRC/log/$l.post-tree"); STATE_FROM="log/$l.post-tree"; }
  done
fi
if [ -n "$STATE" ]; then
  [ "$(git -C "$MAIN" cat-file -t "$STATE" 2>/dev/null)" = tree ] ||
    die "il tree $STATE ($STATE_FROM) non e' piu' nel repository (potato da git gc): stato della fase non ricostruibile"
fi
[ "$code_before" -eq 1 ] && [ -z "$STATE" ] && [ "$PHASE" != implement ] &&
  die "una fase di codice precede $LABEL ma nessun .post-tree la registra: stato del codice non ricostruibile"

# dipendenze: quelle del tree principale valgono per il codice della fase? (prima di creare qualunque cosa)
DEPS_DIFF=$(deps_diff "${STATE:-$BASE}") NONCONF=""
if [ -n "$DEPS_DIFF" ]; then
  [ $ALLOW_DEPS -eq 1 ] || die "dipendenze diverse fra lo stato della fase ($STATE_FROM) e il tree principale: $(echo $DEPS_DIFF). node_modules e venv collegati dal tree principale non sarebbero quelli di questo codice e i gate non girerebbero come nell'originale. Niente worktree creato. Per rigiocare comunque (rigioco NON CONFRONTABILE): --non-confrontabile"
  NONCONF="dipendenze diverse dal tree principale ($STATE_FROM): $(echo $DEPS_DIFF)"
  echo "replay: NON CONFRONTABILE — $NONCONF"
fi

# harness e inject
HARNESS=$(cd "$HARNESS" 2>/dev/null && pwd) || die "harness inesistente"
[ -f "$HARNESS/.claude-plugin/plugin.json" ] || die "--harness non e' la radice di un plugin (manca .claude-plugin/plugin.json): $HARNESS"
[ -f "$HARNESS/scripts/run-phase.sh" ] || die "il plugin non ha scripts/run-phase.sh: $HARNESS"
for n in ${INJECT[@]+"${INJECT[@]}"}; do
  case "$n" in _*|*/*) die "inject non valido: $n" ;; esac
  [ -f "$HERE/inject/$n.sh" ] || die "inject sconosciuto: $n (in $HERE/inject: $(ls "$HERE/inject" | sed -n 's/\.sh$//p' | grep -v '^_' | tr '\n' ' '))"
done

# worktree e uscita
STAMP=$(date +%Y%m%d-%H%M%S)-$$
[ -n "$WT" ] || WT="$(dirname "$MAIN")/fic-replay-$LABEL-$STAMP"
case "$(basename "$WT")" in fic-replay-*) ;; *) refuse "il worktree deve chiamarsi fic-replay-*: $WT" ;; esac
[ -e "$WT" ] && refuse "$WT esiste gia': non l'ho creato io, non lo uso"
pd=$(canon "$(dirname "$WT")") && [ -n "$pd" ] || refuse "la cartella madre di $WT non esiste"
WT="$pd/$(basename "$WT")"   # forma canonica: e' anche quella scritta nel marcatore
HARNESSC=$(canon "$HARNESS")
case "$WT" in "$MAINC"/*|"$ROOTC"/*|"$HARNESSC"/*) refuse "il worktree non puo' stare dentro il tree principale o il harness: $WT" ;; esac
OUT=${OUT:-$SRC/spec-$NAME.replay/$LABEL-$STAMP}

AIW="$WT/$LAVORO" RUN_DST="$WT/$LAVORO/spec-$NAME.run"
REL_RUN="$LAVORO/spec-$NAME.run"
LOCK="$MAINGIT/full-implementation-cycle.lock"

# act: stampa ed esegue (in --dry-run solo stampa); un passo di preparazione fallito ferma tutto (la
# trappola rimuove il worktree). act_rc: stampa, esegue e restituisce l'uscita (la fase, la misura).
act() { printf '+ %s\n' "$1"; [ $DRY -eq 1 ] && return 0; eval "$1" || die "passo fallito: $1"; }
act_rc() { printf '+ %s\n' "$1"; [ $DRY -eq 1 ] && return 0; eval "$1"; }

echo "replay: ciclo spec-$NAME · fase $LABEL · base $BASE · codice da $STATE_FROM · harness $HARNESS"
echo "replay: worktree $WT · uscita $OUT$([ $DRY -eq 1 ] && echo ' · DRY-RUN: nulla viene eseguito')"

CREATED="" DONE_CLEAN=0
cleanup() {
  [ -n "$CREATED" ] && [ $DONE_CLEAN -eq 0 ] || return 0
  DONE_CLEAN=1
  if [ -f "$RUN_DST/log/$LABEL.running" ] && [ ! -f "$RUN_DST/log/$LABEL.exit" ]; then
    echo "replay: la fase risulta ancora in corso: worktree lasciato. Quando e' finita: bash $(q "$HERE/replay.sh") --remove $(q "$CREATED")" >&2
    return 0
  fi
  mkdir -p "$OUT" && cp "$RUN_DST"/log/"$LABEL".* "$OUT"/ 2>/dev/null
  if ! ours "$CREATED"; then
    echo "replay: $CREATED non supera la verifica: NON rimosso" >&2
  elif forget_mirror "$CREATED" && ! unlink_deps "$CREATED"; then   # prima i collegamenti: la rimozione non deve mai seguirli
    echo "replay: collegamenti ancora presenti in $CREATED: worktree NON rimosso (seguirebbe le dipendenze del tree principale)" >&2
  else
    git -C "$MAIN" worktree remove --force "$CREATED" || echo "replay: rimozione del worktree fallita: $CREATED" >&2
  fi
}
trap cleanup EXIT

# 1. worktree alla base, marcatore nella sua git dir
[ $DRY -eq 1 ] || CREATED=$WT   # la trappola lo rimuove solo se supera la verifica
act "git -C $(q "$MAIN") worktree add --detach $(q "$WT") $BASE"
act "printf 'fic-replay\npath=%s\ncreated=%s\n' $(q "$WT") $STAMP > \"\$(git -C $(q "$WT") rev-parse --absolute-git-dir)/fic-replay\""
# 1b. gate eseguibili come nell'originale: .git relativo (git di WSL), dipendenze collegate, tsconfig di nuxi
act "fic_relgit $(q "$WT")"
while IFS= read -r p; do
  [ -n "$p" ] && act "link_dep $(q "$MAIN/$p") $(q "$WT/$p")"
done < <(dep_links "$MAIN")
NUXT=modules/app/apps/admin/.nuxt
[ -f "$MAIN/$NUXT/tsconfig.json" ] &&
  act "mkdir -p $(q "$WT/$NUXT") && cp $(q "$MAIN/$NUXT/tsconfig.json") $(q "$WT/$NUXT/") && { cp $(q "$MAIN/$NUXT")/*.d.ts $(q "$WT/$NUXT/") 2>/dev/null; true; }"
# 2. codice allo stato della fase, come modifiche non committate
[ -n "$STATE" ] && act "git -C $(q "$WT") read-tree -u --reset $STATE && git -C $(q "$WT") read-tree HEAD"
# 2b. dipendenze uguali per git (verificato sopra): l'impronta normalizzata coincide con quella del tree
# principale, cioe' la copia WSL del worktree si seminera' (fic-mirror.sh). Non con --non-confrontabile.
[ -z "$NONCONF" ] && act "deps_fp_check $(q "$MAIN") $(q "$WT")"
# 3. harness: NON copiato nel worktree (pk04a-1): la fase gira con scripts/run-phase.sh del plugin --harness (passo 6)
# 4. spec e run directory fino alla fase esclusa
act "mkdir -p $(q "$RUN_DST/log") $(q "$RUN_DST/prompts") && cp $(q "$SPEC_SRC") $(q "$AIW/")"
for l in $EARLIER; do
  act "cp $(q "$RUN_SRC/log")/$l.* $(q "$RUN_DST/log/")"
  [ -f "$RUN_SRC/prompts/$l.md" ] && act "cp $(q "$RUN_SRC/prompts/$l.md") $(q "$RUN_DST/prompts/")"
done
[ -f "$RUN_SRC/input.md" ] && act "cp $(q "$RUN_SRC/input.md") $(q "$RUN_DST/")"
if [ $code_before -eq 1 ]; then
  for f in base.txt do-not-touch.txt mixed.txt; do
    [ -f "$RUN_SRC/$f" ] && act "cp $(q "$RUN_SRC/$f") $(q "$RUN_DST/")"
  done
  act ": > $(q "$RUN_DST/touched.txt")"
  for l in $EARLIER; do
    [ -f "$RUN_SRC/log/$l.pre-tree" ] && [ -f "$RUN_SRC/log/$l.post-tree" ] &&
      act "git -C $(q "$MAIN") -c core.quotePath=false diff --name-only --no-renames $(tr -d '\r\n ' < "$RUN_SRC/log/$l.pre-tree") $(tr -d '\r\n ' < "$RUN_SRC/log/$l.post-tree") >> $(q "$RUN_DST/touched.txt")"
  done
  act "sort -u -o $(q "$RUN_DST/touched.txt") $(q "$RUN_DST/touched.txt")"
fi
# la skill del plugin (prefisso maat:), non una .claude/skills/full-implementation-cycle del commit del ciclo
if head -1 "$PROMPT_SRC" | grep -q -- '--no-dev'; then
  act "sed '1s|^/\\(maat:\\)\\{0,1\\}full-implementation-cycle |/maat:full-implementation-cycle |' $(q "$PROMPT_SRC") > $(q "$RUN_DST/prompts/$LABEL.md")"
else
  act "sed '1s|^/\\(maat:\\)\\{0,1\\}full-implementation-cycle \\(--worker=[a-z]* [^ ]*\\)|/maat:full-implementation-cycle \\2 --no-dev|' $(q "$PROMPT_SRC") > $(q "$RUN_DST/prompts/$LABEL.md")"
fi
# 5. inject
for n in ${INJECT[@]+"${INJECT[@]}"}; do act "bash $(q "$HERE/inject/$n.sh") $(q "$WT")"; done
# 6. la fase: run-phase.sh del plugin --harness, cwd nel worktree, il plugin caricato SEMPRE nella sotto-sessione
# (MAAT_PLUGIN_DIR → --plugin-dir: l'abilitazione del worktree non conta), con il lock del tree principale
act_rc "(cd $(q "$WT") && MAAT_PLUGIN_DIR=$(q "$HARNESS") FIC_LOCK=$(q "$LOCK") bash $(q "$HARNESS/scripts/run-phase.sh") $REL_RUN $LABEL $REL_RUN/prompts/$LABEL.md)"
code=$?
# 7. log in --out, misura
act_rc "mkdir -p $(q "$OUT") && cp $(q "$RUN_DST/log")/$LABEL.* $(q "$OUT/") && { cp $(q "$RUN_DST/touched.txt") $(q "$OUT/") 2>/dev/null; cp $(q "$AIW/spec-$NAME.md") $(q "$OUT/spec-dopo.md"); true; }"
OUT_JSONL=$(winpath "$OUT/$LABEL.jsonl")
MARK=""
[ -n "$NONCONF" ] && MARK="printf 'NON CONFRONTABILE — %s\n' $(q "$NONCONF") | tee $(q "$OUT/NON-CONFRONTABILE.txt"); "
[ -n "$FPWARN" ] && MARK="${MARK}printf 'AVVISO — %s\n' $(q "$FPWARN"); "
act_rc "{ $MARK$(q "$FIC_PY") $(q "$(winpath "$CR")") $(q "$OUT_JSONL"); } | tee $(q "$OUT/report.txt"); $(q "$FIC_PY") $(q "$(winpath "$CR")") --json $(q "$OUT_JSONL") > $(q "$OUT/report.json")"
# 8. rimozione, solo se il percorso supera la verifica e dopo aver tolto i collegamenti
if [ $DRY -eq 1 ]; then
  echo "+ forget_mirror $(q "$WT")"
  echo "+ unlink_deps $(q "$WT")"
  echo "+ (verifica: nome fic-replay-*, marcatore con il suo percorso, elencato da git worktree list; nessun collegamento rimasto) git -C $(q "$MAIN") worktree remove --force $(q "$WT")"
  exit 0
fi
cleanup
echo "replay: fase $LABEL finita con uscita $code · log e report in $OUT$([ -n "$NONCONF" ] && echo ' · NON CONFRONTABILE')$([ -n "$FPWARN" ] && echo " · AVVISO: $FPWARN")"
exit $code
