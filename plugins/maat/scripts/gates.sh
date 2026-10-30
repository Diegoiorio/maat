#!/usr/bin/env bash
# gates.sh — i gate del livello di test, eseguiti dal DRIVER (run-phase.sh) fuori dalle sotto-sessioni,
# con l'evidenza su file e il riuso a chiave identica (harness-pt04, 1d-1e). Moduli e comandi vengono da
# .claude/maat.json (lettore unico scripts/maat-config.py, interfaccia scripts/lib/maat-conf.sh), mai da qui (R3.3).
#
#   bash gates.sh --run-dir <run-dir> <livello> <file toccati…>
#   bash gates.sh --verify <run-dir>/evidence/<chiave>
#
# <livello>: min | std | full | legacy (legacy = std). I file sono relativi al repository (touched.txt).
#
# INSTRADAMENTO: ogni file va al modulo di `maat_modulo_di` — «radice» (conta per test, controlli, lint e build del
# modulo) o «pacchetti» (sotto radice_pacchetti ma fuori dalla radice: solo lint e build). Un file fuori da ogni
# modulo non e' coperto da nessun gate: lo dice la riga «non coperto: …».
#
# GATE — quelli di `maat_gate_richiesti <livello>` (sezione `gate` di maat.json), un file JSON per ciascuno:
#   tests-<modulo>      comandi.test sui test che regola_test (accanto, specchio, nessuna) seleziona per i file della
#                       radice. Nessun test selezionato -> SKIPPED «nessun test esistente per: …»; nessun file sotto la
#                       radice -> SKIPPED «nessun file sotto <radice>» (mai la suite intera); modulo SENZA comando di
#                       test (o con regola nessuna) e con file toccati -> NOT RUN «dichiarato: nessun test», mai PASS;
#   controlli-<modulo>  ogni voce {glob, comando, se_presente?} sui file toccati della radice che corrispondono al
#                       glob, un'invocazione per file. FAIL se una voce eseguita esce != 0; PASS se almeno una e'
#                       stata eseguita; SKIPPED se nessun file corrisponde; NOT RUN se tutte le voci pertinenti sono
#                       saltate (se_presente assente dal PATH: voce SALTATA nel campo `voci` del JSON e nel motivo);
#   lint, build         comandi.lint (con {base?…} = <run-dir>/base.txt, se esiste) e comandi.build sui file della
#                       radice e dei pacchetti del modulo; `lint-<modulo>`/`build-<modulo>` se piu' moduli li dichiarano.
#   Ogni comando gira dalla sua `cartella` (radice | radice_pacchetti | repo), con MAAT_MODULO=<modulo> nell'ambiente
#   (non nella riga); ambiente wsl -> dentro WSL, nativo -> qui. I gate dei moduli nativi girano IN PARALLELO alla
#   corsia wsl; nella corsia wsl vanno in serie (la copia di test-fast.sh ha un lock solo).
#
# EVIDENZA: <run-dir>/evidence/<chiave>/<gate>.json con i campi gate, esito (PASS|FAIL|BLOCKED|SKIPPED|NOT RUN),
# comando, exit, durata_s, report (file nella stessa cartella; null se il gate non e' stato eseguito), riepilogo,
# motivo, file (selettori o path), chiave, eseguito_il, e `voci` per i controlli. Accanto: chiave.txt (le componenti
# della chiave in chiaro) e argomenti.txt (livello e file, per --verify). Il formato del report lo dice il campo
# `report` del MODULO, mai il nome del gate:
#   junit    report <gate>.junit.xml ({report} del comando): PASS solo col JUnit leggibile e almeno un test;
#   vitest   report <gate>.log: PASS solo con la riga "esito=" del wrapper e il riepilogo "Tests … passed";
#   nessuno  report <gate>.log: PASS con uscita 0 e log non vuoto, come build.
# lint e' giudicato dalla riga "esito=" del wrapper (test-fast.sh). MAI UN PASS SENZA REPORT: -> BLOCKED.
#
# CHIAVE: sha256 di: tree del working tree INTERO (review-surface.sh tree: tracciati, staged e non tracciati non
# ignorati), livello e comandi (radice del plugin -> <maat>, radice del progetto -> <repo>: la chiave non dipende da
# dove e' installato il plugin; il cambio di versione lo intercetta l'impronta del harness), node e TZ in WSL (solo
# se un modulo ha ambiente wsl), python= (l'interprete di {python} dei moduli che lo usano, precedenza di
# maat-config.py; la versione di un modulo wsl e' quella di WSL), le voci `chiave` dei moduli ({etichetta, file} ->
# impronta del file o «assente»; {etichetta, comando} -> la sua uscita, DENTRO WSL per un modulo wsl che usa {python}:
# l'interprete esiste solo li'), TZ e CI (qui).
#
# {python} DI UN MODULO WSL (da un caso reale): senza FIC_GATES_VENV_PY l'interprete si cerca DENTRO WSL fra i
# candidati di moduli[].python (stringa o lista, relativi alla radice; vince il primo che esiste), altrimenti
# piattaforma.python (relativo al repo), altrimenti python3; un nome senza / si cerca nel PATH di WSL. Nessuno esiste
# -> i gate del modulo che usano {python} sono BLOCKED «python WSL assente», mai PASS. Il comando della ricerca non ha
# variabili di shell: `wsl -- bash -lc` lo fa passare da un primo interprete che le espanderebbe vuote. Per lo stesso
# motivo una voce `chiave` eseguita in WSL non deve usare variabili di shell. Nessuna granularita' per modulo: un byte cambiato ovunque -> chiave
# nuova, tutto si riesegue. Riuso SOLO a chiave identica e solo di PASS/FAIL/SKIPPED/NOT RUN col report presente: un
# BLOCKED si riesegue. Se il tree cambia mentre i gate girano, quelli eseguiti diventano BLOCKED (l'evidenza non
# sarebbe di nessun albero).
#
# Uscita: 0 tutti PASS/SKIPPED/NOT RUN · 1 almeno un FAIL · 3 almeno un BLOCKED, nessun FAIL (anche maat.json
#   assente o non valido) · 2 uso.
#   --verify: 0 FRESH (la chiave della cartella e' quella di adesso) · 1 STALE · 3 non verificabile (BLOCKED: maat.json
#   assente o non valido, tree non calcolabile) · 2 uso.
# Stdout: una riga per gate "<gate>: <ESITO> (eseguito|riuso) — <riepilogo o motivo>", la riga "non coperto: …" se
#   qualche file e' fuori dai moduli, poi l'ultima "gates: esito=<ESITO>[ (NOT RUN dichiarato: <gate…>)]
#   chiave=<chiave> evidence=<cartella>".
# Variabili (per i test): FIC_GATES_ROOT repository (default: PROJECT_ROOT, il progetto della cartella di lavoro) ·
# FIC_GATES_HARNESS radice del plugin (default MAAT_ROOT; scripts/review-surface.sh, scripts/python.sh,
# scripts/lib/maat-conf.sh e il {maat} dei comandi) · FIC_GATES_WSL programma che riceve UN comando bash da eseguire
# in WSL (default: wsl -- bash -lc) · FIC_GATES_VENV_PY interprete di {python} (vince su maat.json e sulla ricerca in
# WSL; per un modulo wsl e' un percorso di WSL, usato cosi' com'e') · MAAT_CONFIG.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT (plugin) e PROJECT_ROOT (cartella di lavoro)
HROOT=${FIC_GATES_HARNESS:-$MAAT_ROOT}
ROOT=${FIC_GATES_ROOT:-$PROJECT_ROOT}
RS="$HROOT/scripts/review-surface.sh"
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
win() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }
wslp() { # C:/x/y -> /mnt/c/x/y
  local w; w=$(win "$1")
  case $w in [A-Za-z]:/*) printf '/mnt/%s%s' "$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')" "${w:2}" ;; *) printf '%s' "$w" ;; esac
}
sq() { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }
in_wsl() { # $1 = comando bash da eseguire dentro WSL
  if [ -n "${FIC_GATES_WSL:-}" ]; then "$FIC_GATES_WSL" "$1"; else MSYS_NO_PATHCONV=1 wsl -- bash -lc "$1"; fi
}
sha() { sha256sum | cut -c1-64; }
tree_now() { (cd "$ROOT" && bash "$RS" tree) 2>/dev/null; }

run_dir="" verify=""
while [ $# -gt 0 ]; do
  case $1 in
    --run-dir) [ $# -ge 2 ] || usage; run_dir=$2; shift 2 ;;
    --verify) [ $# -ge 2 ] || usage; verify=$2; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "gates: opzione sconosciuta: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
if [ -n "$verify" ]; then
  [ $# -eq 0 ] && [ -f "$verify/argomenti.txt" ] || { echo "gates: --verify vuole una cartella evidence/<chiave> con argomenti.txt" >&2; exit 2; }
  run_dir=$(cd "$verify/../.." && pwd) || exit 2
  mapfile -t args < <(tr -d '\r' < "$verify/argomenti.txt")
  set -- ${args[@]+"${args[@]}"}
fi
[ -n "$run_dir" ] && [ $# -ge 1 ] || usage
# Assoluto: i comandi dei test girano nella cartella del modulo, e un {report} relativo finirebbe li' (file nuovo
# non ignorato => «albero cambiato durante i gate», report mai trovato). run-phase.sh passa la run dir relativa.
case $run_dir in /*|[A-Za-z]:[/\\]*) ;; *) run_dir="$PWD/$run_dir" ;; esac
level=$1; shift
case $level in min|std|full|legacy) ;; *) echo "gates: livello sconosciuto: $level (min|std|full|legacy)" >&2; exit 2 ;; esac
[ -n "$ROOT" ] || { maat_progetto; exit 4; }
. "$HROOT/scripts/python.sh" || { echo "gates: interprete Python non trovato" >&2; exit 2; }
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1
py() { sed '1,/^#__PYTHON__$/d' "$0" | "$FIC_PY" - "$@"; }   # il codice arriva da una pipe: nessun file temporaneo

blocca() { echo "gates: esito=BLOCKED ($1) chiave=- evidence=-"; exit 3; }
TMPD=$(mktemp -d) || blocca "cartella temporanea non creabile"
trap 'rm -rf "$TMPD"' EXIT
errore() { tr -d '\r' < "$TMPD/err" | sed 's/^maat-config: //' | grep -v '^$' | head -3 | tr '\n' ' ' | sed 's/ *$//'; }

# --- configurazione: il lettore unico, caricato una volta nella shell principale ---
export PROJECT_ROOT=$ROOT   # il lettore trova <repo>/.claude/maat.json (MAAT_CONFIG vince)
. "$HROOT/scripts/lib/maat-conf.sh" 2>"$TMPD/err" || blocca "lib/maat-conf.sh non caricabile: $(errore)"
maat_conf_carica 2>"$TMPD/err" || blocca "maat.json: $(errore)"
lettore() { "$FIC_PY" "$_MAAT_PY" "$@"; }
normp() { local p=${1//\\//}; while [ "${p#./}" != "$p" ]; do p=${p#./}; done; p=${p%/}; [ "$p" = . ] && p=""; printf '%s' "$p"; }

MODS=()
declare -A M_IDX M_RAD M_RADS M_PAC M_PACS M_AMB M_REP
i=0
while n=$(maat_conf "moduli.$i.nome" 2>/dev/null); do
  MODS+=("$n"); M_IDX[$n]=$i
  M_RADS[$n]=$(maat_conf "moduli.$i.radice"); M_RAD[$n]=$(normp "${M_RADS[$n]}")
  M_PACS[$n]=$(maat_conf "moduli.$i.radice_pacchetti"); M_PAC[$n]=$(normp "${M_PACS[$n]}")
  M_AMB[$n]=$(maat_conf "moduli.$i.ambiente" --default nativo)
  M_REP[$n]=$(maat_conf "moduli.$i.report" --default nessuno)
  i=$((i + 1))
done
dichiara() { maat_conf "moduli.${M_IDX[$1]}.$2" >/dev/null 2>&1; }   # <modulo> <chiave.puntata>

mapfile -t FILES < <(printf '%s\n' "$@" | tr -d '\r' | sed 's|^\./||' | grep -v '^$' | LC_ALL=C sort -u)

# --- instradamento: radice (test, controlli, lint, build) o pacchetti (solo lint e build) ---
declare -A RADF ALLF
UNCOV=()
for f in ${FILES[@]+"${FILES[@]}"}; do
  out=$(maat_modulo_di "$f" 2>"$TMPD/err" | tr -d '\r'); rc=$?   # pipefail: l'uscita del lettore
  case $rc in
    0) n=${out%% *}; dove=${out#* }
       [ "$dove" = radice ] && RADF[$n]+="$f"$'\n'
       ALLF[$n]+="$f"$'\n' ;;
    2) UNCOV+=("$f") ;;
    *) blocca "modulo-di $f: uscita $rc $(errore)" ;;
  esac
done
righe() { printf '%s' "${1:-}" | grep -v '^$'; }

# --- i gate del livello e i loro comandi ---
gl=$(maat_gate_richiesti "$level" ${FILES[@]+"${FILES[@]}"} 2>"$TMPD/err" | tr -d '\r') || blocca "gate-richiesti: $(errore)"
WROOT=$(wslp "$ROOT")
base=""; [ -f "$run_dir/base.txt" ] && base=$(tr -d '\r\n ' < "$run_dir/base.txt")
radice_di() { if [ "${M_AMB[$1]}" = wsl ]; then printf '%s' "$WROOT"; else printf '%s' "$ROOT"; fi; }
maat_di() { if [ "${M_AMB[$1]}" = wsl ]; then wslp "$HROOT"; else printf '%s' "$HROOT"; fi; }
# {maat} finisce in una riga di bash: Git Bash non deve riscrivere MAAT_ROOT (/mnt/c/… -> C:/Program Files/Git/mnt/c/…)
NOCONV="MAAT_ROOT${MSYS2_ENV_CONV_EXCL:+;$MSYS2_ENV_CONV_EXCL}"
cartella() { if [ "$2" = . ]; then radice_di "$1"; else printf '%s/%s' "$(radice_di "$1")" "$2"; fi; }   # <modulo> <rel>

# {python} dei moduli wsl, cercato DENTRO WSL (vedi l'intestazione). Da un caso reale: il venv Windows derivato
# (altre versioni di FastAPI) rispondeva diversamente dalla produzione e un test era passato verde.
declare -A PYW PYWMISS
PYW_ASSENTE=/python-wsl-assente   # segnaposto: un comando che lo contiene e' BLOCKED, mai eseguito
if [ -z "${FIC_GATES_VENV_PY:-}" ]; then
  for m in ${MODS[@]+"${MODS[@]}"}; do
    [ "${M_AMB[$m]}" = wsl ] || continue
    FIC_GATES_VENV_PY=$PYW_ASSENTE lettore python "$m" >/dev/null 2>&1 || continue   # il modulo non usa {python}
    i=${M_IDX[$m]} cand=() wp=() base=${M_RAD[$m]} probe_py=""
    if maat_conf "moduli.$i.python.0" >/dev/null 2>&1; then
      j=0; while c=$(maat_conf "moduli.$i.python.$j" 2>/dev/null); do cand+=("$c"); j=$((j + 1)); done
    elif c=$(maat_conf "moduli.$i.python" 2>/dev/null); then cand=("$c")
    elif c=$(maat_conf piattaforma.python 2>/dev/null); then cand=("$c") base=""
    else cand=(python3) base=""; fi
    for k in "${!cand[@]}"; do
      c=${cand[$k]//\\//}
      case $c in
        */*) case $c in /*) p=$c ;; [A-Za-z]:/*) p=$(wslp "$c") ;; *) p="$WROOT${base:+/$base}/${c#./}" ;; esac
             t="[ -x $(sq "$p") ]" ;;
        *) p=$c t="command -v $(sq "$c") >/dev/null 2>&1" ;;
      esac
      wp[$k]=$p probe_py+="${probe_py:+el}if $t; then echo $k; "
    done
    k=$(in_wsl "${probe_py}fi" 2>/dev/null </dev/null | tr -d '\r' | tail -1)
    if [[ $k =~ ^[0-9]+$ ]] && [ -n "${wp[$k]:-}" ]; then PYW[$m]=${wp[$k]}
    else PYWMISS[$m]="python WSL assente: ${wp[*]}"; fi
  done
fi
con_py() { # <modulo> <comando…>: il comando con l'interprete di {python} del modulo (FIC_GATES_VENV_PY)
  local m=$1 vpy=${FIC_GATES_VENV_PY:-} excl=${MSYS2_ENV_CONV_EXCL:-}; shift
  if [ -n "${PYW[$m]:-}" ]; then vpy=${PYW[$m]}; elif [ -n "${PYWMISS[$m]:-}" ]; then vpy=$PYW_ASSENTE; fi
  # un percorso di WSL: Git Bash non deve riscriverlo per il Python di Windows (/mnt/c/… -> C:/Program Files/Git/…)
  [ "${M_AMB[$m]}" = wsl ] && excl="FIC_GATES_VENV_PY${excl:+;$excl}"
  FIC_GATES_VENV_PY=$vpy MSYS2_ENV_CONV_EXCL=$excl "$@"
}
comando() { # <modulo> <tipo> [opzioni] -> C_REL (cartella relativa), C_CMD (comando), C_ERR; ritorna l'uscita del lettore
  local m=$1 out rc; shift
  out=$(MSYS2_ENV_CONV_EXCL=$NOCONV MAAT_ROOT=$(maat_di "$m") con_py "$m" maat_comando "$m" "$@" 2>"$TMPD/err" | tr -d '\r'); rc=$?
  C_ERR=$(errore); C_REL=$(printf '%s\n' "$out" | sed -n 1p); C_CMD=$(printf '%s\n' "$out" | sed -n '2,$p')
  if [ "$rc" -eq 0 ] && [ -n "${PYWMISS[$m]:-}" ] && printf '%s' "$C_CMD" | grep -qF "$PYW_ASSENTE"; then
    C_ERR=${PYWMISS[$m]}; return 5
  fi
  return "$rc"
}
# Uscita 3 del lettore per un {python} non risolvibile («python non trovato»): un guasto d'ambiente, BLOCKED — mai
# NOT RUN «dichiarato», che e' solo di cio' che maat.json dichiara (se_presente assente, nessun comando di test).
senza_python() { case $C_ERR in *"python non trovato"*) return 0 ;; esac; return 1; }
GATES=()
declare -A GMOD GTIPO CMD EXEC GDIR SKIPWHY NRWHY BLKWHY GFILES CTL SALT
while IFS=$'\t' read -r g m tipo; do
  [ -n "$g" ] || continue
  GATES+=("$g"); GMOD[$g]=$m GTIPO[$g]=$tipo
  mapfile -t rf < <(righe "${RADF[$m]:-}")
  mapfile -t af < <(righe "${ALLF[$m]:-}")
  case $tipo in
    test)
      if ! dichiara "$m" comandi.test; then
        NRWHY[$g]="dichiarato: nessun test"; GFILES[$g]=$(printf '%s\n' ${rf[@]+"${rf[@]}"})
      elif [ ${#rf[@]} -eq 0 ]; then SKIPWHY[$g]="nessun file sotto ${M_RADS[$m]}"
      else
        a=(); for f in "${rf[@]}"; do a+=(--file "$f"); done
        sel=$(lettore test-di "$m" "${a[@]}" 2>"$TMPD/err" | tr -d '\r') || { BLKWHY[$g]="test-di $m: $(errore)"; continue; }
        mapfile -t S < <(righe "$sel")
        if [ ${#S[@]} -eq 0 ]; then SKIPWHY[$g]="nessun test esistente per: ${rf[*]}"; continue; fi
        a=(); for t in "${S[@]}"; do a+=(--test "$t"); done
        comando "$m" test "${a[@]}" --report '<report>'; rc=$?
        case $rc in
          0) GDIR[$g]=$(cartella "$m" "$C_REL"); EXEC[$g]=$C_CMD; CMD[$g]="cd $(sq "${GDIR[$g]}") && $C_CMD"
             if [ "$C_REL" = . ]; then GFILES[$g]=$(printf '%s\n' "${S[@]}"); else GFILES[$g]=$(printf '%s\n' "${S[@]}" | sed "s|^$C_REL/||"); fi ;;
          3) if senza_python; then BLKWHY[$g]="comando test di $m: ${C_ERR#NOT RUN (dichiarato): }"
             else NRWHY[$g]=${C_ERR#NOT RUN (dichiarato): }; NRWHY[$g]="dichiarato: ${NRWHY[$g]}"; fi ;;
          *) BLKWHY[$g]="comando test di $m non risolto (uscita $rc): $C_ERR" ;;
        esac
      fi ;;
    controlli)
      GFILES[$g]=$(printf '%s\n' ${rf[@]+"${rf[@]}"})
      if [ ${#rf[@]} -eq 0 ]; then SKIPWHY[$g]="nessun file sotto ${M_RADS[$m]}"; continue; fi
      a=(); for f in "${rf[@]}"; do a+=(--file "$f"); done
      comando "$m" controlli "${a[@]}"; rc=$?
      SALT[$g]=$(tr -d '\r' < "$TMPD/err" | sed -n 's/^maat-config: \(SALTATA: .*\)/\1/p')
      case $rc in
        0) c="" ; CTL[$g]=""
           while IFS= read -r d && IFS= read -r x; do
             CTL[$g]+="$(cartella "$m" "$d")"$'\t'"$x"$'\n'
             c="${c:+$c ; }cd $(sq "$(cartella "$m" "$d")") && $x"
           done <<< "$C_REL"$'\n'"$C_CMD"
           CMD[$g]=$c ;;
        3) NRWHY[$g]="controlli saltati: $(printf '%s\n' "${SALT[$g]}" | sed 's/^SALTATA: //' | paste -sd ';' - | sed 's/;/; /g')" ;;
        2) SKIPWHY[$g]="nessun file toccato corrisponde ai controlli di $m" ;;
        *) BLKWHY[$g]="controlli di $m non risolti (uscita $rc): $C_ERR" ;;
      esac ;;
    lint|build)
      GFILES[$g]=$(printf '%s\n' ${af[@]+"${af[@]}"})
      if [ ${#af[@]} -eq 0 ]; then SKIPWHY[$g]="nessun file sotto ${M_PACS[$m]}"; continue; fi
      a=()
      if [ "$tipo" = lint ]; then for f in "${af[@]}"; do a+=(--file "$f"); done; [ -n "$base" ] && a+=(--base "$base"); fi
      comando "$m" "$tipo" ${a[@]+"${a[@]}"}; rc=$?
      case $rc in
        0) GDIR[$g]=$(cartella "$m" "$C_REL"); EXEC[$g]=$C_CMD; CMD[$g]="cd $(sq "${GDIR[$g]}") && $C_CMD" ;;
        3) if senza_python; then BLKWHY[$g]="comando $tipo di $m: ${C_ERR#NOT RUN (dichiarato): }"
           else NRWHY[$g]=${C_ERR#NOT RUN (dichiarato): }; NRWHY[$g]="dichiarato: ${NRWHY[$g]}"; fi ;;
        *) BLKWHY[$g]="comando $tipo di $m non risolto (uscita $rc): $C_ERR" ;;
      esac ;;
  esac
done <<< "$gl"
# Modulo `ambiente: wsl` senza WSL (wsl e wsl.exe fuori dal PATH; pk08, D5): i suoi gate da eseguire sono BLOCKED con il
# motivo, mai eseguiti — lanciati darebbero «comando non trovato», cioe' un FAIL per i controlli e un BLOCKED senza
# motivo per un report (la promessa del doctor: «i suoi gate saranno BLOCKED»). Con FIC_GATES_WSL decide quel programma.
if [ -z "${FIC_GATES_WSL:-}" ] && ! command -v wsl >/dev/null 2>&1 && ! command -v wsl.exe >/dev/null 2>&1; then
  for g in ${GATES[@]+"${GATES[@]}"}; do
    [ "${M_AMB[${GMOD[$g]}]}" = wsl ] && { [ -n "${CMD[$g]:-}" ] || [ -n "${BLKWHY[$g]:-}" ]; } &&
      BLKWHY[$g]="WSL assente (wsl.exe fuori dal PATH): il modulo ${GMOD[$g]} ha ambiente wsl — metti \`ambiente: nativo\` o installa WSL"
  done
fi

# --- chiave ---
file_sha() { if [ -f "$1" ]; then sha < "$1"; else echo assente; fi; }
# radice del plugin e del progetto nella chiave: <maat> e <repo>, in tutte le forme (la piu' lunga prima)
NK=$( { for x in "$HROOT" "$(win "$HROOT")" "$(wslp "$HROOT")"; do printf '%s\t%s\t<maat>\n' "${#x}" "$x"; done
        for x in "$ROOT" "$(win "$ROOT")" "$WROOT"; do printf '%s\t%s\t<repo>\n' "${#x}" "$x"; done; } | LC_ALL=C sort -t $'\t' -k1,1nr | awk -F '\t' '!v[$2]++')
normk() { local s=$1 l x t; while IFS=$'\t' read -r l x t; do [ -n "$x" ] && s=${s//"$x"/$t}; done <<< "$NK"; printf '%s' "$s"; }
TREE=$(tree_now)
[ -n "$TREE" ] || blocca "tree del working tree non calcolabile: review-surface.sh tree"
wsl_mod=""; for m in ${MODS[@]+"${MODS[@]}"}; do [ "${M_AMB[$m]}" = wsl ] && wsl_mod=1; done
probe=""
if [ -n "$wsl_mod" ]; then
  probe=$(in_wsl 'printf "node=%s\n" "$(node --version 2>&1 | head -1)"; printf "tz_wsl=%s|%s\n" "${TZ-}" "$(date +%Z%z)"' 2>/dev/null | tr -d '\r')
  [ -n "$probe" ] || probe="node=wsl non raggiungibile"
fi
pyl=()
declare -A KWSL   # moduli wsl che usano {python}: versione e voci comando della chiave in WSL
for m in ${MODS[@]+"${MODS[@]}"}; do
  p=$(con_py "$m" lettore python "$m" 2>/dev/null | tr -d '\r'); rc=$?
  [ $rc -eq 2 ] && continue
  v=assente
  if [ "${M_AMB[$m]}" = wsl ]; then
    KWSL[$m]=1
    if [ $rc -eq 0 ] && [ "$p" != "$PYW_ASSENTE" ]; then
      v=$(in_wsl "$(sq "$p") --version 2>&1 || echo assente" 2>/dev/null </dev/null | tr -d '\r' | tail -1)
    fi
  elif [ $rc -eq 0 ] && { [ -f "$p" ] || command -v "$p" >/dev/null 2>&1; }; then v=$("$p" --version 2>&1 | tr -d '\r'); fi
  pyl+=("$m"$'\t'"$v")
done
comp=$(
  echo "schema=gates-1"
  echo "tree=$TREE"
  echo "livello=$level"
  for g in ${GATES[@]+"${GATES[@]}"}; do
    if [ -n "${BLKWHY[$g]:-}" ]; then echo "cmd.$g=BLOCKED $(normk "${BLKWHY[$g]}")"
    elif [ -n "${NRWHY[$g]:-}" ]; then echo "cmd.$g=NOT RUN $(normk "${NRWHY[$g]}")"
    elif [ -n "${CMD[$g]:-}" ]; then echo "cmd.$g=$(normk "${CMD[$g]}")"
    else echo "cmd.$g=SKIPPED ${SKIPWHY[$g]}"; fi
  done
  [ -n "$probe" ] && echo "$probe"
  for x in ${pyl[@]+"${pyl[@]}"}; do
    if [ ${#pyl[@]} -eq 1 ]; then echo "python=${x#*$'\t'}"; else echo "python.${x%%$'\t'*}=${x#*$'\t'}"; fi
  done
  for m in ${MODS[@]+"${MODS[@]}"}; do
    while IFS=$'\t' read -r et tipo cart val; do
      [ -n "$et" ] || continue
      d=$ROOT; [ "$cart" = . ] || d="$ROOT/$cart"
      wd=$WROOT; [ "$cart" = . ] || wd="$WROOT/$cart"
      case $tipo in
        file) echo "$et=$(file_sha "$d/$val")" ;;
        comando)
          if [ -n "${KWSL[$m]:-}" ]; then   # stdin chiuso: wsl.exe consumerebbe le righe di questo ciclo
            echo "$et=$(in_wsl "if cd $(sq "$wd") 2>/dev/null; then bash -c $(sq "$val") 2>/dev/null </dev/null; else echo assente; fi" 2>/dev/null </dev/null | tr -d '\r' | paste -sd ' ' -)"
          elif [ -d "$d" ]; then echo "$et=$(cd "$d" && bash -c "$val" 2>/dev/null </dev/null | tr -d '\r' | paste -sd ' ' -)"; else echo "$et=assente"; fi ;;
        *) echo "$et=assente" ;;
      esac
    done < <(if [ -n "${KWSL[$m]:-}" ]; then mr=$(wslp "$HROOT"); else mr=$HROOT; fi
             MSYS2_ENV_CONV_EXCL=$NOCONV MAAT_ROOT=$mr con_py "$m" lettore chiave "$m" 2>/dev/null | tr -d '\r')
  done
  echo "TZ=${TZ-<non impostata>}"
  echo "CI=${CI-<non impostata>}"
)
KEY=$(printf '%s\n' "$comp" | sha)

if [ -n "$verify" ]; then
  if [ "$KEY" = "$(basename "$verify")" ]; then echo FRESH; exit 0; fi
  echo "STALE (chiave attuale $KEY)"; exit 1
fi

EV="$run_dir/evidence/$KEY"
mkdir -p "$EV" || { echo "gates: esito=BLOCKED (cartella dell'evidenza non creabile: $EV) chiave=$KEY evidence=-"; exit 3; }
printf '%s\n' "$comp" > "$EV/chiave.txt"
printf '%s\n' "$level" ${FILES[@]+"${FILES[@]}"} > "$EV/argomenti.txt"
WEV=$(win "$EV")

# --- esecuzione ---
now_ms() { date +%s%3N; }
esegui() { # <modulo> <cartella assoluta> <comando>: MAAT_MODULO nell'ambiente, non nella riga
  # stderr unito DENTRO WSL: unito fuori, wsl.exe consegna due flussi che si sovrascrivono nel log (un blocco FAIL
  # di vitest perso sotto il riepilogo => «Tn verde», «N falliti, N-1 blocchi»). Da un caso reale.
  # MAAT_CONFIG (se impostata) arriva anche dentro WSL, tradotta: test-fast.sh vi legge la stessa configurazione
  if [ "${M_AMB[$1]}" = wsl ]; then in_wsl "{ export MAAT_MODULO=$(sq "$1")${MAAT_CONFIG:+; export MAAT_CONFIG=$(sq "$(wslp "$MAAT_CONFIG")")}; cd $(sq "$2") && $3; } 2>&1"
  else (cd "$2" && MAAT_MODULO=$1 bash -c "$3"); fi
}
run_gate() { # $1 = gate. Riuso a chiave identica, altrimenti esecuzione e JSON.
  local g=$1 rc=0 r t0 kind why="" m=${GMOD[$1]} cmd="" x rp d c files=()
  if [ -n "$(py stato "$WEV" "$g")" ]; then echo riuso > "$EV/.$g.stato"; return 0; fi
  rm -f "$EV/$g.json" "$EV/$g.log" "$EV/$g.junit.xml" "$EV/.$g.voci"
  echo eseguito > "$EV/.$g.stato"
  mapfile -t files < <(righe "${GFILES[$g]:-}")
  t0=$(now_ms)
  if [ -n "${BLKWHY[$g]:-}" ]; then kind=blocked why=${BLKWHY[$g]}
  elif [ -n "${NRWHY[$g]:-}" ]; then kind=notrun why=${NRWHY[$g]}
  elif [ -z "${CMD[$g]:-}" ]; then kind=skip why=${SKIPWHY[$g]:-}
  elif [ "${GTIPO[$g]}" = controlli ]; then
    kind=controlli cmd=${CMD[$g]}
    : > "$EV/$g.log"
    while IFS=$'\t' read -r d c; do
      [ -n "$c" ] || continue
      printf '== %s\n' "$c" >> "$EV/$g.log"
      esegui "$m" "$d" "$c" >> "$EV/$g.log" 2>&1 </dev/null; r=$?
      printf '== uscita %s\n' "$r" >> "$EV/$g.log"
      if [ $r -eq 0 ]; then printf 'PASS\t%s\t%s\n' "$r" "$c"; else printf 'FAIL\t%s\t%s\n' "$r" "$c"; rc=1; fi >> "$EV/.$g.voci"
    done <<< "${CTL[$g]}"
    while IFS= read -r x; do [ -n "$x" ] && printf 'SALTATA\t\t%s\n' "${x#SALTATA: }" >> "$EV/.$g.voci"; done <<< "${SALT[$g]:-}"
  else
    case ${GTIPO[$g]} in test) kind=${M_REP[$m]} ;; *) kind=${GTIPO[$g]} ;; esac
    cmd=${CMD[$g]}
    if [ "${M_AMB[$m]}" = wsl ]; then rp=$(wslp "$EV/$g.junit.xml"); else rp=$(win "$EV/$g.junit.xml"); fi
    x=${EXEC[$g]//"'<report>'"/$(sq "$rp")}
    esegui "$m" "${GDIR[$g]}" "$x" > "$EV/$g.log" 2>&1; rc=$?
  fi
  py scrivi "$WEV" "$g" "$kind" "$cmd" "$rc" "$(( $(now_ms) - t0 ))" "$why" "$KEY" ${files[@]+"${files[@]}"} >/dev/null
  rm -f "$EV/.$g.voci"
}
NAT=() WL=()
for g in ${GATES[@]+"${GATES[@]}"}; do if [ "${M_AMB[${GMOD[$g]}]}" = wsl ]; then WL+=("$g"); else NAT+=("$g"); fi; done
( for g in ${NAT[@]+"${NAT[@]}"}; do run_gate "$g"; done ) & natpid=$!
for g in ${WL[@]+"${WL[@]}"}; do run_gate "$g"; done
wait $natpid

# L'albero e' cambiato mentre i gate giravano: cio' che e' stato eseguito non e' evidenza di nessun albero.
after=$(tree_now)
if [ "$after" != "$TREE" ]; then
  for g in ${GATES[@]+"${GATES[@]}"}; do
    [ "$(cat "$EV/.$g.stato" 2>/dev/null)" = eseguito ] &&
      py invalida "$WEV" "$g" "albero cambiato durante i gate (tree $TREE -> ${after:-non calcolabile})" >/dev/null
  done
fi
for g in ${GATES[@]+"${GATES[@]}"}; do py riga "$WEV" "$g" "$(cat "$EV/.$g.stato" 2>/dev/null)"; rm -f "$EV/.$g.stato"; done
[ ${#UNCOV[@]} -eq 0 ] || echo "non coperto: ${UNCOV[*]} (fuori da ogni modulo di maat.json)"
tot=$(py totale "$WEV" ${GATES[@]+"${GATES[@]}"})
echo "gates: esito=$tot chiave=$KEY evidence=$WEV"
case ${tot%% *} in PASS|SKIPPED) exit 0 ;; FAIL) exit 1 ;; *) exit 3 ;; esac

#__PYTHON__
import datetime
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
RIUSABILI = ("PASS", "FAIL", "SKIPPED", "NOT RUN")


def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return ANSI.sub("", f.read())
    except OSError:
        return None


def load(ev, g):
    try:
        with open(os.path.join(ev, g + ".json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save(ev, g, d):
    tmp = os.path.join(ev, g + ".json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, os.path.join(ev, g + ".json"))


def junit(p):
    """(test, falliti, errori, saltati) da un report JUnit, None se assente o illeggibile."""
    try:
        root = ET.parse(p).getroot()
    except (OSError, ET.ParseError):
        return None
    suites = [root] if root.tag == "testsuite" else root.findall("testsuite")
    if not suites:
        return None
    tot = [0, 0, 0, 0]
    for s in suites:
        for i, k in enumerate(("tests", "failures", "errors", "skipped")):
            try:
                tot[i] += int(s.get(k, "0"))
            except ValueError:
                return None
    return tuple(tot)


def wrapper_line(text):
    """Ultima riga 'vitest-fast: esito=…' del wrapper (test-fast.sh): (esito, riga) o (None, None)."""
    for ln in reversed(text.splitlines()):
        m = re.search(r"vitest-fast: esito=(\w+)", ln)
        if m:
            return m.group(1), ln.strip()
    return None, None


def judge(ev, g, kind, rc):
    """(esito, report, riepilogo, motivo) dal FORMATO (kind: junit | vitest | nessuno | lint | build | controlli),
    mai dal nome del gate. Mai PASS senza report."""
    if kind == "junit":
        rep = g + ".junit.xml"
        j = junit(os.path.join(ev, rep))
        if j is None:
            return "BLOCKED", None, "", f"nessun report JUnit (uscita {rc}): vedi {g}.log"
        n, fl, er, sk = j
        riep = f"{n} test, {fl} falliti, {er} errori, {sk} saltati"
        if rc == 0 and fl + er == 0 and n > 0:
            return "PASS", rep, riep, ""
        if rc == 1 and fl + er > 0:
            return "FAIL", rep, riep, ""
        return "BLOCKED", rep, riep, f"uscita {rc} incoerente col report o senza test raccolti"
    rep = g + ".log"
    text = read(os.path.join(ev, rep))
    if not text or not text.strip():
        return "BLOCKED", None, "", f"nessun output del runner (uscita {rc})"
    if kind == "controlli":
        voci = leggi_voci(ev, g)
        ese = [v for v in voci if v["esito"] != "SALTATA"]
        ko = [v for v in ese if v["esito"] == "FAIL"]
        riep = "%d voci eseguite, %d fallite, %d saltate" % (len(ese), len(ko), len(voci) - len(ese))
        if rc == 0 and ese and not ko:
            return "PASS", rep, riep, ""
        if ko:
            return "FAIL", rep, riep, ""
        return "BLOCKED", rep, riep, f"uscita {rc} incoerente con le voci"
    if kind in ("build", "nessuno"):
        last = text.strip().splitlines()[-1].strip()
        if rc == 0:
            return "PASS", rep, last, ""
        if rc in (126, 127, 255) or rc < 0:
            return "BLOCKED", rep, last, f"comando non eseguibile (uscita {rc}: programma o ambiente assenti)"
        return "FAIL", rep, last, ""
    esito, line = wrapper_line(text)
    if esito is None:
        return "BLOCKED", rep, "", f"nessuna riga 'esito=' del wrapper (uscita {rc})"
    if kind == "vitest":
        summ = [l.strip() for l in text.splitlines() if re.match(r"\s*Tests\s+\d", l)]
        riep = summ[-1] if summ else line
        if rc == 0 and esito == "PASS":
            if not summ or "passed" not in summ[-1]:
                return "BLOCKED", rep, line, "PASS del wrapper senza il riepilogo di vitest (Tests … passed)"
            return "PASS", rep, riep, ""
        if rc == 1 and esito == "FAIL":
            return "FAIL", rep, riep, ""
        return "BLOCKED", rep, riep, line
    # lint
    if rc == 0 and esito == "PASS":
        return "PASS", rep, line, ""
    if rc == 0 and esito == "SKIPPED":
        return "SKIPPED", rep, line, line
    if rc == 1 and esito == "FAIL":
        return "FAIL", rep, line, ""
    return "BLOCKED", rep, line, line


def leggi_voci(ev, g):
    """Le voci dei controlli scritte da gates.sh (.<gate>.voci): esito<TAB>exit<TAB>comando o motivo."""
    out = []
    t = read(os.path.join(ev, "." + g + ".voci")) or ""
    for ln in t.splitlines():
        p = ln.split("\t", 2)
        if len(p) < 3:
            continue
        if p[0] == "SALTATA":
            c, _sep, mot = p[2].partition(" — ")
            out.append({"comando": c, "esito": "SALTATA", "exit": None, "motivo": mot})
        else:
            out.append({"comando": p[2], "esito": p[0], "exit": int(p[1]) if p[1].lstrip("-").isdigit() else None,
                        "motivo": ""})
    return out


def cmd_scrivi(ev, g, kind, cmd, rc, dur, why, key, *files):
    rc = int(rc)
    voci = leggi_voci(ev, g)
    if kind == "skip":
        esito, rep, riep, mot, cmd, rc = "SKIPPED", None, "", why, None, None
    elif kind == "notrun":
        esito, rep, riep, mot, cmd, rc = "NOT RUN", None, "", why, None, None
    elif kind == "blocked":
        esito, rep, riep, mot, rc = "BLOCKED", None, "", why, None
    else:
        esito, rep, riep, mot = judge(ev, g, kind, rc)
    d = {"gate": g, "esito": esito, "comando": cmd or None, "exit": rc,
         "durata_s": round(int(dur) / 1000.0, 1), "report": rep, "riepilogo": riep,
         "motivo": mot, "file": list(files), "chiave": key,
         "eseguito_il": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    if voci:
        d["voci"] = voci
    save(ev, g, d)
    print(esito)


def cmd_stato(ev, g):
    """Stampa l'esito se il gate e' riusabile (PASS/FAIL/SKIPPED/NOT RUN, report presente), niente altrimenti."""
    d = load(ev, g)
    if not d or d.get("esito") not in RIUSABILI:
        return
    rep = d.get("report")
    if rep and not os.path.isfile(os.path.join(ev, rep)):
        return
    if d["esito"] in ("PASS", "FAIL") and not rep:
        return
    print(d["esito"])


def cmd_invalida(ev, g, why):
    d = load(ev, g)
    if d:
        d["esito"], d["motivo"] = "BLOCKED", why
        save(ev, g, d)


def cmd_riga(ev, g, stato):
    d = load(ev, g) or {"esito": "BLOCKED", "motivo": "evidenza non scritta"}
    detail = d.get("riepilogo") if d.get("esito") in ("PASS", "FAIL") else d.get("motivo")
    print(f"{g}: {d['esito']} ({stato or 'eseguito'}) — {detail or ''}".rstrip(" —"))


def cmd_totale(ev, *gates):
    es = [(g, (load(ev, g) or {}).get("esito", "BLOCKED")) for g in gates]
    nr = [g for g, e in es if e == "NOT RUN"]
    tutti = [e for _g, e in es]
    if "FAIL" in tutti:
        tot = "FAIL"
    elif any(e not in ("PASS", "SKIPPED", "NOT RUN") for e in tutti):
        tot = "BLOCKED"
    elif all(e in ("SKIPPED", "NOT RUN") for e in tutti):
        tot = "SKIPPED"
    else:
        tot = "PASS"
    print(tot + (" (NOT RUN dichiarato: %s)" % " ".join(nr) if nr else ""))


sys.stdout.reconfigure(encoding="utf-8")
{"scrivi": cmd_scrivi, "stato": cmd_stato, "invalida": cmd_invalida, "riga": cmd_riga,
 "totale": cmd_totale}[sys.argv[1]](*sys.argv[2:])
