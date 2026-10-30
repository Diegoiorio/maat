# worktree-lib.sh — funzioni condivise dei worktree del harness: dipendenze del tree principale COLLEGATE (mai
# copiate ne' installate), controllo che coincidano, scollegamento sicuro, .git relativo, copia WSL del worktree.
# Si INCLUDE con `.` da script/fic/corpus/replay.sh (rigioco di una fase) e da script/fic/ciclo-worktree.sh (ciclo
# in un worktree dedicato): non si esegue, e non ha effetti finche' non si chiama una funzione.
# Estratta da replay.sh senza cambiarne il comportamento (test: script/fic/cycle-report.test.sh, sezione corpus;
# script/fic/ciclo-worktree.test.sh).
#
# Il chiamante imposta: MAIN (tree principale, per deps_diff e per la sua maat.json) · FIC_PY (per fic_relgit, da
# python.sh; se manca lo carica wt_conf) · WT_TAG (prefisso dei messaggi, default «replay»).
# Cosa collegare e quali file decidono le dipendenze NON e' scritto qui: lo dichiara maat.json del tree principale
# (MAAT_CONFIG, altrimenti $MAIN/.claude/maat.json), per modulo: collega_nel_worktree (le cartelle collegate),
# file_dipendenze (i file che le decidono), preparati e preparazione (i file preparati copiati nel worktree, in
# ciclo-worktree.sh), copia (il modulo della copia WSL: impronta e semina). Letta una volta con maat-config.py
# importato (wt_conf_carica); progetto non configurato: niente da collegare ne' da confrontare.
# Uscita del `.`: 1 se fic-mirror.sh non si trova accanto a questo file.
#
# ⚠️ Una cartella di worktree con le dipendenze collegate, cancellata SEGUENDO i collegamenti, svuota le
# dipendenze VERE del tree principale. Prima unlink_deps (solo il collegamento, mai ricorsivo), poi la verifica
# che nessun collegamento resti, poi la rimozione.

WTLIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
. "$WTLIB_DIR/lib/maat-paths.sh" || return 1   # fic-mirror.sh sta in MAAT_SCRIPTS, accanto a questo file
WTLIB_TEST=$MAAT_SCRIPTS

winpath() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }
# Forma canonica di un percorso ESISTENTE (C:/…): con MSYS lo stesso posto ha piu' nomi (/tmp e
# C:/Users/…/Temp, /c/… e C:/…), quindi ogni confronto fra percorsi passa da qui. Vuoto → vuoto.
canon() { [ -n "${1:-}" ] && (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }

# --- configurazione del tree principale (maat.json): righe «tipo<TAB>…», percorsi relativi al repository ---
#   link  <percorso>                                     una voce di collega_nel_worktree (puo' contenere *)
#   dep   <glob>                                         una voce di file_dipendenze (pathspec :(glob) di git)
#   prep  <radice> <file guida> <preparazione> <glob>…   un modulo con preparati (guida: il primo glob senza jolly)
#   copia <radice_pacchetti> <radice> <file guida>       un modulo con copia (radice del repo = «.»)
# Guida e preparazione vuote valgono «-» (chi legge le riconverte): con IFS=$'\t' due tab di fila sono un solo
# separatore, e un campo vuoto farebbe slittare quelli dopo.
WT_CONF_PY=$(cat <<'EOF'
import importlib.util, sys
import sys; sys.dont_write_bytecode = True   # nessun __pycache__ sotto MAAT_ROOT
s = importlib.util.spec_from_file_location("maat_config", sys.argv[1])
mc = importlib.util.module_from_spec(s)
s.loader.exec_module(mc)
try:
    cfg, _p = mc.carica(sys.argv[2])
except mc.Uscita as u:
    if u.codice == 4:   # progetto non configurato: niente da collegare ne' da confrontare
        sys.exit(0)
    sys.stderr.write("maat.json: %s\n" % (u.messaggio or "configurazione non valida (uscita %d)" % u.codice))
    sys.exit(1)
r = mc.risolto(cfg)
def j(base, x):
    x = mc.norm(x)
    return base + "/" + x if base and x else (base or x)
for m in r["moduli"]:
    for v in m.get("collega_nel_worktree", []):
        v = {"percorso": v} if isinstance(v, str) else v
        print("link\t" + j(mc.cartella_di(m, v.get("cartella", "radice")), v["percorso"]))
    for v in m.get("file_dipendenze", []):
        v = {"glob": v} if isinstance(v, str) else v
        print("dep\t" + j(mc.cartella_di(m, v.get("cartella", "radice")), v["glob"]))
def v(x):   # campo vuoto -> «-»: il tab e' IFS-whitespace, read fonderebbe i campi vuoti e quelli dopo slitterebbero
    return x or "-"
for m in r["moduli"]:
    pr = [mc.norm(g) for g in m.get("preparati", [])]
    rad = mc.norm(m["radice"]) or "."
    guida = next((g for g in pr if not any(c in g for c in "*?[")), "")
    if pr:
        print("\t".join(["prep", rad, v(guida), v(m.get("preparazione", ""))] + pr))
    if m.get("copia"):
        print("\t".join(["copia", mc.norm(m["radice_pacchetti"]) or ".", rad, v(guida)]))
EOF
)
_WT_CONF="" _WT_CONF_OK=""
wt_conf_carica() { # legge maat.json del tree principale una volta (le subshell ereditano la cache): 1 se non valida
  local cfg out
  [ -n "${FIC_PY:-}" ] || . "$MAAT_SCRIPTS/python.sh" || { echo "${WT_TAG:-replay}: interprete Python non trovato (maat.json)" >&2; return 1; }
  cfg=${MAAT_CONFIG:-${MAIN:-${PROJECT_ROOT:-.}}/.claude/maat.json}
  out=$("$FIC_PY" -c "$WT_CONF_PY" "$(winpath "$MAAT_SCRIPTS/maat-config.py")" "$(winpath "$cfg")" 2>&1) ||
    { echo "${WT_TAG:-replay}: $(printf '%s' "$out" | tr -d '\r' | tail -1) ($cfg)" >&2; return 1; }
  _WT_CONF=$(printf '%s' "$out" | tr -d '\r') _WT_CONF_OK=1
}
wt_conf() { # le righe della configurazione (sopra), lette alla prima chiamata
  [ -n "$_WT_CONF_OK" ] || wt_conf_carica || return 1
  [ -z "$_WT_CONF" ] || printf '%s\n' "$_WT_CONF"
}

# --- dipendenze del tree principale nel worktree: collegate, mai copiate ne' installate ---
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WIN=1 ;; *) WIN=0 ;; esac
# file che decidono le dipendenze collegate (file_dipendenze): se differiscono, non sono quelle del codice
dep_ps() { local k g; while IFS=$'\t' read -r k g; do [ "$k" = dep ] && printf ':(glob)%s\n' "$g"; done < <(wt_conf); return 0; }
deps_diff() { # $1 tree-ish → i file delle dipendenze diversi dal working tree principale (o solo li')
  local ps=()
  mapfile -t ps < <(dep_ps)
  [ ${#ps[@]} -gt 0 ] || return 0   # nessun file di dipendenze dichiarato: niente da confrontare
  { git -C "$MAIN" -c core.quotePath=false diff --name-only "$1" -- "${ps[@]}" || echo "(git diff fallito)"
    git -C "$MAIN" -c core.quotePath=false ls-files -o --exclude-standard -- "${ps[@]}"; } | LC_ALL=C sort -u
}
dep_links() { # $1 radice → i percorsi relativi delle dipendenze installate (collega_nel_worktree) presenti sotto la radice
  local r=$1 k g p
  while IFS=$'\t' read -r k g; do
    [ "$k" = link ] && [ -n "$g" ] || continue
    local IFS=   # pk08: niente divisione, una radice o una voce con spazi resta un percorso solo
    for p in "$r"/$g; do   # $g senza virgolette: il * della voce si espande
      { [ -e "$p" ] || [ -L "$p" ]; } && printf '%s\n' "${p#"$r"/}"
    done
  done < <(wt_conf)
  return 0
}
link_dep() { # $1 sorgente (cartella esistente), $2 collegamento da creare (non deve esistere)
  [ -d "$1" ] || { echo "${WT_TAG:-replay}: sorgente del collegamento assente: $1" >&2; return 1; }
  { [ -e "$2" ] || [ -L "$2" ]; } && { echo "${WT_TAG:-replay}: $2 esiste gia': non lo sostituisco" >&2; return 1; }
  mkdir -p "$(dirname "$2")" || return 1
  if [ $WIN -eq 1 ]; then   # junction: niente privilegi; MSYS non deve convertire /c e /J
    MSYS2_ARG_CONV_EXCL='*' cmd.exe /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null || return 1
  else
    ln -s "$1" "$2" || return 1
  fi
  [ -L "$2" ]
}
unlink_deps() { # $1 radice del worktree: toglie SOLO i collegamenti (mai ricorsivo: la sorgente non si tocca).
  # Una cartella vera allo stesso posto e' del worktree: resta. 1 se un collegamento non si toglie.
  local r=$1 p left=0
  while IFS= read -r p; do
    [ -n "$p" ] && [ -L "$r/$p" ] || continue
    # rmdir senza /s su una junction toglie la junction, non il contenuto della destinazione
    [ $WIN -eq 1 ] && MSYS2_ARG_CONV_EXCL='*' cmd.exe /c rmdir "$(cygpath -w "$r/$p")" >/dev/null 2>&1
    [ -L "$r/$p" ] && rm -f "$r/$p"   # symlink: unlink(), non segue
    [ -L "$r/$p" ] && { echo "${WT_TAG:-replay}: collegamento non rimosso: $r/$p" >&2; left=1; }
  done < <(dep_links "$r")
  return $left
}
fic_relgit() { # $1 worktree: .git con gitdir RELATIVO, leggibile anche dal git di WSL (vitest-fast.sh)
  local wt=$1 gd rel
  gd=$(git -C "$wt" rev-parse --absolute-git-dir) || return 1
  rel=$("$FIC_PY" -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]).replace(os.sep, "/"))' \
        "$gd" "$(canon "$wt")" 2>/dev/null | tr -d '\r')
  if [ -z "$rel" ]; then
    echo "${WT_TAG:-replay}: AVVISO — gitdir relativo non calcolabile (unita' diverse?): resta quello assoluto, che vitest-fast.sh traduce" >&2
    return 0
  fi
  printf 'gitdir: %s\n' "$rel" > "$wt/.git" &&
    [ "$(canon "$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)")" = "$(canon "$gd")" ] && return 0
  printf 'gitdir: %s\n' "$gd" > "$wt/.git"   # ripristino: il worktree deve restare rimovibile
  echo "${WT_TAG:-replay}: gitdir relativo non valido ($rel): ripristinato quello assoluto" >&2
  return 1
}
# Impronta delle dipendenze della copia: la STESSA di test-fast.sh e counterproof.sh (fic_deps_fp di fic-mirror.sh,
# contenuto senza CR) sulla radice_pacchetti del modulo con copia di maat.json; nessun modulo con copia: vuota. E'
# la condizione della semina delle dipendenze nella copia WSL del worktree.
[ -n "$WTLIB_TEST" ] && [ -f "$WTLIB_TEST/fic-mirror.sh" ] || { echo "worktree-lib: fic-mirror.sh non trovato: $WTLIB_TEST/fic-mirror.sh" >&2; return 1; }
. "$WTLIB_TEST/fic-mirror.sh" || return 1
deps_fp() { # $1 radice → impronta come test-fast.sh (che la calcola sulla radice_pacchetti del modulo con copia)
  local rp
  rp=$(wt_conf | awk -F'\t' '$1 == "copia" { print $2; exit }')
  if [ -n "$rp" ] && [ -d "$1/$rp" ]; then fic_deps_fp "$1/$rp"; else printf '' | sha256sum | cut -c1-64; fi
}
FPWARN=""
deps_fp_check() { # $1 tree principale, $2 worktree: impronte diverse → avviso (log e report), mai un errore
  local a b
  a=$(deps_fp "$1") b=$(deps_fp "$2")
  [ "$a" = "$b" ] && { echo "${WT_TAG:-replay}: impronta delle dipendenze della copia uguale al tree principale (${a:0:12})"; return 0; }
  FPWARN="impronta delle dipendenze della copia diversa dal tree principale (${b:0:12} ≠ ${a:0:12}): la copia WSL del worktree non si semina, test-fast e counterproof usciranno BLOCKED (copia assente)"
  echo "${WT_TAG:-replay}: AVVISO — $FPWARN" >&2
  return 0
}
wslp() { # percorso C:/… → /mnt/c/… (per il git di WSL); gli altri restano come sono
  local p=$1 d
  case "$p" in [A-Za-z]:/*) d=$(printf '%s' "${p:0:1}" | tr '[:upper:]' '[:lower:]'); printf '/mnt/%s/%s' "$d" "${p:3}" ;; *) printf '%s' "$p" ;; esac
}
forget_mirror() { # $1 worktree: cancella le copie WSL delle sue corsie (~/fic-mirror-<hash>-1|2, harness-pt13) e
  # la sua copia ~/fic-mirror-<hash> (mai ~/fic-mirror); mai un errore.
  # Lo script va a bash su STDIN: con `wsl.exe -- bash -c "…"` $k e $r arrivavano gia' espansi (vuoti: misurato
  # 2026-09-30), quindi le corsie non si cancellavano mai e l'uscita era sempre 0.
  local lib=$WTLIB_TEST/fic-mirror.sh wt=$1 l w out rc
  if [ $WIN -eq 1 ]; then l=$(wslp "$(winpath "$lib")") w=$(wslp "$(canon "$wt")"); else l=$lib w=$wt; fi
  out=$({ printf 'L=%q R=%q\n' "$l" "$w"
          printf '%s\n' '. "$L" || exit 1' \
            'r=0; for k in 1 2; do fic_lane_forget "$R" "$k" || r=1; done; fic_mirror_forget "$R" || r=1; exit $r'
        } | if [ $WIN -eq 1 ]; then MSYS_NO_PATHCONV=1 wsl.exe -- bash -s; else bash -s; fi 2>&1); rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  [ $rc -eq 0 ] || echo "${WT_TAG:-replay}: AVVISO — copia WSL del worktree non cancellata del tutto (in uso?); poi, da WSL: . $l && fic_lane_forget $w 1; fic_lane_forget $w 2; fic_mirror_forget $w" >&2
  return 0
}
