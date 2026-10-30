#!/usr/bin/env bash
# spazi.test.sh — percorsi con SPAZI e un carattere non ASCII («à») (pk08, passo 6, A6). Il plugin (una copia in
# «…/plugin con spazi à/maat», usata senza MAAT_ROOT: la radice si ricava dalla posizione degli script), il progetto
# («progetto con spazi à», un repo git sintetico), la run dir, la HOME delle copie, la configurazione esterna e il
# worktree hanno tutti spazi; dentro il progetto anche il modulo («modulo uno») e i file. Tutto in una cartella
# temporanea, cancellata alla fine. Casi:
#   1. risolutore: MAAT_ROOT e PROJECT_ROOT con spazi (lib/maat-paths.sh);
#   2. impronta del harness (run-phase.sh --harness-fp / --harness-paths / --harness-fp-confronta): tre righe, UGUALE,
#      un file del plugin con spazi nel nome entra nell'elenco e porta a CAMBIATO;
#   3. lock delle fasi di codice (run-phase.sh, claude finto): nella git dir del progetto con spazi, --lock-status
#      libero/occupato, fase concorrente 4, rilascio; impronta cambiata -> exit 6 e il RIMEDIO stampato, eseguito
#      com'e', riallinea; lock di ripiego fic_lock_dir/fic_unlock_dir (fic-mirror.sh) su una cartella con spazi;
#   4. gate (gates.sh, modulo nativo): controlli `bash -n {file}` e test `cat {test}` su file con spazi -> PASS,
#      evidenza nella run dir con spazi;
#   5. controprova (counterproof.sh, runner comando, HOME con spazi): copia di ripiego (PATH senza rsync e flock) e,
#      se c'e', rsync: rosso_generico e verde veri, copia ripristinata, lock rilasciato;
#   6. ciclo-worktree.sh crea | rimuovi: worktree «progetto con spazi à-fic-uno», collegamento di una dipendenza
#      (junction su Windows, symlink altrove), lock del worktree occupato -> STOP, rimozione con la fonte intatta;
#   7. plan-check.sh gen con MAAT_CONFIG con spazi (un modulo che c'e' solo li'): la riga cp di procedura.txt,
#      ESEGUITA com'e', fa girare le controprove con quella configurazione;
#   8. watch-phase.sh dal plugin con spazi su una run dir con spazi.
# Controprove per mutazione (copie del plugin con UNA virgoletta tolta; ognuna deve far diventare rosso il suo caso):
#   M1 run-phase.sh `hfp_win hfp_r $MAAT_ROOT` (piano, Test: «togliere le virgolette su un $MAAT_ROOT») -> caso 2;
#   M2 run-phase.sh `mkdir $L` in take_lock -> caso 3 (lock); M3 fic-mirror.sh `mkdir $d` in fic_lock_dir -> caso 3
#   (ripiego); M4 maat-config.py {file}/{test} senza sq -> caso 4; M5 counterproof.sh `cd $cwd` nel runner -> caso 5;
#   M6 fic-mirror.sh `cd $dst` nel tar del ripiego -> caso 5 (ripiego); M7 ciclo-worktree.sh `$WT` senza virgolette
#   in `git worktree add` -> caso 6; M8 plan-check.sh MAAT_CONFIG senza sq_se_serve nella riga cp -> caso 7;
#   M9 fic-mirror.sh pid scritto senza noclobber in fic_lock_dir -> caso 3 (lock ripreso da un altro, review giro 2).
#   bash plugins/maat/scripts/spazi.test.sh          (Git Bash o Linux)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
. "$HERE/python.sh" || true
[ -n "${FIC_PY:-}" ] || { echo "spazi.test.sh: nessun Python utilizzabile" >&2; exit 2; }
unset MAAT_CONFIG FIC_REPO PROJECT_ROOT MAAT_ROOT CLAUDE_BIN FIC_PHASE FIC_GATES_VENV_PY FIC_GATES_WSL FIC_SESSION_GUARD \
  CLAUDE_PROJECT_DIR FIC_CP_CMD FIC_COUNTERPROOF PLAN_CHECK_ROOT FIC_LOCK FIC_GATES FIC_FINALIZE FIC_GATES_HARNESS \
  FIC_GATES_ROOT MAAT_MODULO MAAT_PLUGIN_DIR MSYS_NO_PATHCONV
export FIC_PYTHON=$FIC_PY PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8 FIC_WT_WSL=0
pass=0 fail=0
T0=$(mktemp -d) || exit 2
T="$T0/tmp con spazi à"
WIN=0; case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*) WIN=1 ;; esac
unlink_all() { # i collegamenti rimasti sotto $T0, tolti SENZA seguirli (prima di rm -rf)
  local l
  find "$T0" -type l 2>/dev/null | while IFS= read -r l; do
    [ $WIN -eq 1 ] && MSYS2_ARG_CONV_EXCL='*' cmd.exe /c rmdir "$(cygpath -w "$l")" >/dev/null 2>&1; [ -L "$l" ] && rm -f "$l"; done
}
trap 'unlink_all; rm -rf "$T0"' EXIT
mkdir -p "$T" || exit 2
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; tail -20 "$T/out" 2>/dev/null | sed 's/^/    /'; fi; }
canon() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }
: > "$T/out"

# --- il plugin con spazi (copia senza __pycache__) e le sue copie mutanti ------------------------------------------------
PL="$T/plugin con spazi à/maat"; S="$PL/scripts"
mkdir -p "$(dirname "$PL")" && cp -r "$PLUGIN" "$PL" && find "$PL" -name __pycache__ -type d -prune -exec rm -rf {} + || exit 2
mutante() { # <nome> <file relativo al plugin> <espressione sed>: copia del plugin con la mutazione; stampa la radice.
  # Uscita 1 se la mutazione non cambia il file: la controprova non proverebbe niente. Gira in una sostituzione di
  # comando: il FAIL lo conta il chiamante, nella shell principale (`else non_applicabile`), mai qui
  local d="$T/mutanti con spazi/$1/maat"
  mkdir -p "$(dirname "$d")" && cp -r "$PL" "$d" || return 1
  sed "$3" "$PL/$2" > "$d/$2.mut" && mv "$d/$2.mut" "$d/$2" || return 1
  if cmp -s "$PL/$2" "$d/$2"; then echo "controprova $1: la mutazione non si applica a $2" >&2; return 1; fi
  printf '%s' "$d"
}
non_applicabile() { fail=$((fail + 1)); echo "FAIL: controprova $1 non applicabile (la mutazione non cambia il file o la copia non riesce)"; }

# --- il progetto con spazi: due moduli nativi, file con spazi nel nome -----------------------------------------------------
P="$T/progetto con spazi à"; AIW="$P/.claude/.ai-workflow"
mkdir -p "$AIW" "$P/modulo uno/dipendenze" "$P/modulo uno/generati con spazi" "$P/mod-due" || exit 2
CMDC='"controprova": {"runner": "comando", "comando": "bash {test}"}'
cat > "$P/.claude/maat.json" <<EOF
{"versione_schema": 1,
 "moduli": [{"nome": "uno", "radice": "modulo uno", "ambiente": "nativo",
             "comandi": {"test": "cat {test}"},
             "controlli": [{"glob": "**/*.sh", "comando": "bash -n {file}"}],
             "collega_nel_worktree": ["dipendenze"],
             "preparati": ["generati con spazi/guida.txt"], "preparazione": "true",
             $CMDC}]}
EOF
printf 'echo ciao\n' > "$P/modulo uno/script con spazi à.sh"
printf '// un test con spazi nel nome\n' > "$P/modulo uno/calcolo con spazi.test.js"
printf 'UNO=1\n' > "$P/modulo uno/core con spazi.txt"
printf 'grep -q ROSSO "core con spazi.txt" && { echo "rosso: ROSSO in core con spazi.txt"; exit 1; }\nexit 0\n' > "$P/modulo uno/prova con spazi.sh"
printf 'DUE=1\n' > "$P/mod-due/core.txt"   # i percorsi DENTRO un piano non hanno spazi (plan-check, rel_ok)
printf 'grep -q ROSSO core.txt && { echo "rosso: ROSSO in core.txt"; exit 1; }\nexit 0\n' > "$P/mod-due/prova.sh"
printf 'dipendenza installata\n' > "$P/modulo uno/dipendenze/dentro.txt"
printf 'preparato\n' > "$P/modulo uno/generati con spazi/guida.txt"
printf '.claude/.ai-workflow/spec-*\ndipendenze\ngenerati con spazi/\n' > "$P/.gitignore"   # senza barra: su Linux il collegamento e' un symlink
printf '# spec uno\n## Requisiti\n' > "$AIW/spec-uno.md"
(cd "$P" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  git config core.quotePath false && git add -A && git commit -qm init) || { echo "repo sintetico non creato: $P" >&2; exit 2; }
PC_=$(canon "$P") PLC=$(canon "$PL")
RD="$AIW/spec-uno.run"; mkdir -p "$RD"

# --- 1. risolutore ----------------------------------------------------------------------------------------------------------
(cd "$P" && bash "$S/lib/maat-paths.sh") > "$T/out" 2>&1
check "1. maat-paths.sh dal plugin con spazi, nel progetto con spazi: MAAT_ROOT e PROJECT_ROOT interi" 'grep -qxF "MAAT_ROOT=$PLC" "$T/out" && grep -qxF "PROJECT_ROOT=$PC_" "$T/out"'

# --- 2. impronta del harness ------------------------------------------------------------------------------------------------
impronta() { # <plugin>: harness.fp in $RD2, poi «UGUALE» atteso, un file nuovo con spazi -> CAMBIATO, tolto -> UGUALE
  local rp="$1/scripts/run-phase.sh" nf="$1/scripts/nota con spazi à.txt" a b c
  (cd "$P" && bash "$rp" --harness-fp) > "$T/hfp" 2>"$T/out" || return 1
  a=$(cd "$P" && bash "$rp" --harness-fp-confronta "$T/hfp")
  echo nota > "$nf"
  b=$(cd "$P" && bash "$rp" --harness-fp-confronta "$T/hfp")
  (cd "$P" && bash "$rp" --harness-paths) > "$T/paths" 2>&1
  rm -f "$nf"
  c=$(cd "$P" && bash "$rp" --harness-fp-confronta "$T/hfp")
  printf 'prima=%s\ncon-file=%s\ndopo=%s\n' "$a" "$b" "$c" >> "$T/out"
  [ "$a" = UGUALE ] && [[ $b == CAMBIATO\ * ]] && [ "$c" = UGUALE ] && grep -qxF "scripts/nota con spazi à.txt" "$T/paths"
}
check "2. impronta dal plugin con spazi: UGUALE, file con spazi nell'elenco -> CAMBIATO, tolto -> UGUALE" 'impronta "$PL"'
check "  harness.fp: impronta, versione, radice = il plugin con spazi" 'grep -qE "^impronta=[0-9a-f]{64}$" "$T/hfp" && grep -q "^versione=[0-9]" "$T/hfp" && grep -qxF "radice=$PLC" "$T/hfp" && [ "$(wc -l < "$T/hfp")" = 3 ]'
if M1=$(mutante m1-hfp scripts/run-phase.sh 's/hfp_win hfp_r "\$MAAT_ROOT"/hfp_win hfp_r $MAAT_ROOT/'); then
  check "controprova M1: \$MAAT_ROOT senza virgolette nell'impronta -> il caso 2 e' rosso" '! impronta "$M1"'
else non_applicabile M1; fi

# --- 3. lock delle fasi di codice (run-phase.sh con claude, gates.sh e finalize.sh finti) -----------------------------------
cat > "$T/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
sleep "${FAKE_SLEEP:-0}"
echo '{"type":"result","result":"ESITO FASE x: OK — finto","structured_output":{"fase":"'"$FIC_PHASE"'","esito":"OK","motivo":"finto","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}'
EOF
printf '#!/usr/bin/env bash\necho "gates: esito=PASS chiave=k0 evidence=-"\n' > "$T/gates"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/fin"
chmod +x "$T/claude" "$T/gates" "$T/fin"
PR="$T/prompt con spazi.md"; echo "/full-implementation-cycle --worker=probe x" > "$PR"
fase() { # <plugin> <run dir> <etichetta> [cartella]: una fase dalla cartella del progetto (default $P)
  (cd "${4:-$P}" && CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" FIC_FINALIZE="$T/fin" bash "$1/scripts/run-phase.sh" "$2" "$3" "$PR") </dev/null
}
LK="$P/.git/full-implementation-cycle.lock"
(cd "$P" && bash "$S/run-phase.sh" --lock-status) > "$T/out" 2>&1; rc=$?
check "3. --lock-status nel progetto con spazi, nessuna fase -> libero (0)" '[ "$rc" = 0 ] && grep -qx libero "$T/out"'
FAKE_SLEEP=8 fase "$PL" "$RD" 02-implement > "$T/02.out" 2>&1 & a=$!
for _ in $(seq 1 120); do [ -f "$LK/owner" ] && grep -q '^cpid=' "$LK/owner" && break; sleep 0.25; done
(cd "$P" && bash "$S/run-phase.sh" --lock-status) > "$T/out" 2>&1; rc=$?
check "  fase di codice in corso: lock nella git dir con spazi, --lock-status occupato (1) con la run dir intera" '[ "$rc" = 1 ] && grep -qF "occupato: run=$RD label=02-implement" "$T/out"'
fase "$PL" "$RD" 03-review > "$T/out" 2>&1; rc=$?
check "  fase di codice concorrente -> 4, «lock occupato», .exit nella run dir con spazi" '[ "$rc" = 4 ] && grep -q "lock occupato" "$RD/log/03-review.stderr" && [ "$(cat "$RD/log/03-review.exit")" = 4 ]'
wait "$a"; rc=$?; cp "$T/02.out" "$T/out"
check "  la prima fase finisce 0 e rilascia il lock; harness.fp scritto nella run dir" '[ "$rc" = 0 ] && [ ! -e "$LK" ] && [ "$(cat "$RD/log/02-implement.exit")" = 0 ] && grep -qxF "radice=$PLC" "$RD/harness.fp"'
echo nota > "$S/nota con spazi.txt"
fase "$PL" "$RD" 04-plan > "$T/out" 2>&1; rc=$?
RIM=$(sed -n "s/.*registra l'impronta attuale — \(.*\) — e rilancia.*/\1/p" "$RD/log/04-plan.stderr" | head -1)
check "  plugin cambiato -> exit 6, STOP col rimedio" '[ "$rc" = 6 ] && grep -q "^STOP: harness cambiato" "$RD/log/04-plan.stderr" && [ -n "$RIM" ]'
(cd "$P" && bash -c "$RIM") > "$T/out" 2>&1
fase "$PL" "$RD" 05-plan >> "$T/out" 2>&1; rc=$?
check "  il rimedio stampato, eseguito com'e' dal progetto, riallinea: la fase dopo esce 0" '[ "$rc" = 0 ] && [ "$(cat "$RD/log/05-plan.exit")" = 0 ]'
rm -f "$S/nota con spazi.txt"; (cd "$P" && bash "$S/run-phase.sh" --harness-fp > "$RD/harness.fp")
P2="$T/progetto mutante à"; mkdir -p "$P2" && (cd "$P2" && git init -q . && git config user.email t@t && git config user.name t &&
  git commit -q --allow-empty -m init)
if M2=$(mutante m2-lock scripts/run-phase.sh 's/^  until mkdir "\$L" 2>\/dev\/null; do$/  until mkdir $L 2>\/dev\/null; do/'); then
  fase "$M2" "$P2/spec-m.run" 06-implement "$P2" > "$T/out" 2>&1; rc=$?
  check "controprova M2: mkdir \$L senza virgolette -> la fase di codice non prende il lock (exit $rc, non 0)" '[ "$rc" != 0 ]'
else non_applicabile M2; fi
lockdir() { # <fic-mirror.sh>: lock di ripiego su una cartella con spazi: preso col pid, occupato, rilasciato, orfano ripreso
  local L="$T/lock con spazi à/m.lock.d"
  rm -rf "$T/lock con spazi à"; mkdir -p "$T/lock con spazi à" "$T/cwd lock"
  (cd "$T/cwd lock" && . "$1" || exit 9
   fic_lock_dir "$L" 2 || exit 1
   [ "$(cat "$L/pid")" = "${BASHPID:-$$}" ] || exit 2
   ( fic_lock_dir "$L" 1 ) && exit 3
   fic_unlock_dir "$L"; [ ! -e "$L" ] || exit 4
   sleep 0 & m=$!; wait "$m"; mkdir "$L" && echo "$m" > "$L/pid"
   fic_lock_dir "$L" 3 || exit 5
   fic_unlock_dir "$L"; [ ! -e "$L" ] && [ ! -e "$L.rec" ] || exit 6
   mkdir "$L"; ( fic_lock_dir "$L" 1 ) && exit 7          # senza pid e recente (meno di 10 s): non si riprende
   [ -d "$L" ] && [ ! -e "$L/pid" ] || exit 8
   s=$(( $(date +%s) - 30 ))                              # 30 s fa, in forma touch -t: BSD (date -r), poi GNU (date -d @)
   v=$(date -r "$s" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$s" +%Y%m%d%H%M.%S) || exit 13
   touch -t "$v" "$L" || exit 13                          # senza pid da 30 s: orfano, ripreso (review di pk08)
   fic_lock_dir "$L" 3 || exit 10
   [ "$(cat "$L/pid")" = "${BASHPID:-$$}" ] || exit 11
   fic_unlock_dir "$L"; [ ! -e "$L" ] && [ ! -e "$L.rec" ] || exit 12
   # ripreso da un altro fra il mkdir e la scrittura del pid (review giro 2): il mkdir finto scrive subito il pid di
   # un processo vivo ($$, la shell del test); chi ha fatto il mkdir non deve credersi padrone del lock
   mkdir() { command mkdir "$@" || return; [ "$1" = "$L" ] && [ ! -e "$L/pid" ] && echo "$$" > "$L/pid"; return 0; }
   ( fic_lock_dir "$L" 1 ) && exit 14
   unset -f mkdir
   [ "$(cat "$L/pid")" = "$$" ] || exit 15
   rm -rf -- "$L") > "$T/out" 2>&1
}
check "  fic_lock_dir/fic_unlock_dir su una cartella con spazi: preso, occupato, rilasciato, orfano ripreso, senza pid recente atteso, senza pid vecchio ripreso" 'lockdir "$S/fic-mirror.sh"'
if M3=$(mutante m3-lockdir scripts/fic-mirror.sh 's/^    until mkdir "\$d" 2>\/dev\/null; do$/    until mkdir $d 2>\/dev\/null; do/'); then
  check "controprova M3: mkdir \$d senza virgolette in fic_lock_dir -> il caso del ripiego e' rosso" '! lockdir "$M3/scripts/fic-mirror.sh"'
else non_applicabile M3; fi
if M9=$(mutante m9-pid scripts/fic-mirror.sh 's/if ! (set -C; echo "\$me" > "\$d\/pid")/if ! (echo "$me" > "$d\/pid")/'); then
  check "controprova M9: pid scritto sovrascrivendo in fic_lock_dir -> il caso del lock ripreso da un altro e' rosso" '! lockdir "$M9/scripts/fic-mirror.sh"'
else non_applicabile M9; fi

# --- 4. gate su un modulo nativo ----------------------------------------------------------------------------------------------
GF=("modulo uno/script con spazi à.sh" "modulo uno/calcolo con spazi.test.js")
gate() { (cd "$P" && bash "$1/scripts/gates.sh" --run-dir "$2" std "${GF[@]}") > "$T/out" 2>&1; }
gate "$PL" "$RD"; rc=$?
EV=$(sed -n 's/^gates: esito=.* evidence=\(.*\)$/\1/p' "$T/out" | tail -1)
check "4. gates.sh: controlli e test sui file con spazi -> PASS (exit 0)" '[ "$rc" = 0 ] && grep -q "^controlli-uno: PASS (eseguito)" "$T/out" && grep -q "^tests-uno: PASS (eseguito)" "$T/out" && grep -q "^gates: esito=PASS " "$T/out"'
check "  evidenza nella run dir con spazi, col file con spazi nel campo file" '[ -n "$EV" ] && [ -f "$EV/controlli-uno.json" ] && grep -qF "script con spazi à.sh" "$EV/controlli-uno.json" && grep -qF "calcolo con spazi.test.js" "$EV/tests-uno.json"'
if M4=$(mutante m4-sq scripts/maat-config.py 's/            return " ".join(sq(x) for x in (v or \[\]))/            return " ".join(x for x in (v or []))/'); then
  gate "$M4" "$T/run mutante.run"
  check "controprova M4: {file}/{test} senza quotatura -> i gate del caso 4 non sono PASS" '! grep -q "^controlli-uno: PASS" "$T/out" && ! grep -q "^gates: esito=PASS " "$T/out"'
else non_applicabile M4; fi

# --- 5. controprova, runner comando, HOME con spazi -----------------------------------------------------------------------------
path_senza() { # <cartella> <nome…>: il PATH con le cartelle che contengono uno dei <nome> sostituite da <cartella>, che
               # ne collega ogni file tranne quelli (come counterproof.test.sh)
  local dst=$1 d f b x hit out="" messa=0 skip; shift; skip=" $* "
  mkdir -p "$dst"
  local IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    hit=0; for x in "$@"; do [ -e "$d/$x" ] && hit=1; done
    if [ "$hit" = 0 ]; then out+="${out:+:}$d"; continue; fi
    for f in "$d"/*; do
      b=${f##*/}
      case "$skip" in *" $b "*) continue ;; esac
      [ -e "$dst/$b" ] || [ -L "$dst/$b" ] || ln -s "$f" "$dst/$b"
    done
    [ "$messa" = 1 ] || { out+="${out:+:}$dst"; messa=1; }
  done
  printf '%s' "$out"
}
mkdir -p "$RD/counterproof"
"$FIC_PY" -c 'import json, sys
def e(i, s):
    return {"id": i, "file": "modulo uno/core con spazi.txt", "simbolo": "UNO", "mutazione": {"cerca": "UNO=1", "sostituisci": s},
            "test": {"percorso": "modulo uno/prova con spazi.sh", "nome": "prova"}, "rosso_se": {"test_id": "prova", "asserzione": "rosso"},
            "superficie": "S"}
json.dump([e("S1", "UNO=1 ROSSO"), e("V1", "UNO=2")], open(sys.argv[1], "w", encoding="utf-8"))' "$RD/counterproof/mutations.json"
cpx() { # <plugin> <HOME> [<PATH>]: counterproof.sh sulle due mutazioni; 0 = esiti veri, copia ripristinata, lock rilasciato
  local h=$2
  rm -f "$RD/counterproof/S1.json" "$RD/counterproof/V1.json"; mkdir -p "$h"
  (cd "$P" && HOME=$h PATH=${3:-$PATH} PROJECT_ROOT=$P bash "$1/scripts/counterproof.sh" "$RD/counterproof/mutations.json") > "$T/out" 2>&1
  echo "exit=$?" >> "$T/out"
  grep -qx "exit=1" "$T/out" && grep -q "esito=FAIL prove=1/2 fail=1" "$T/out" &&
    grep -q '"esito": *"rosso_generico"' "$RD/counterproof/S1.json" && grep -q '"esito": *"verde"' "$RD/counterproof/V1.json" &&
    grep -qx "UNO=1" "$h/fic-mirror/modulo uno/core con spazi.txt" && [ -z "$(find "$h" -name '*.fic-lock*' -type d)" ] &&
    grep -qx "UNO=1" "$P/modulo uno/core con spazi.txt"
}
PX=$(path_senza "$T/bin senza rsync" rsync flock)
check "5. premessa: PATH senza rsync e flock, con tar e sha256sum" '! PATH=$PX command -v rsync >/dev/null && ! PATH=$PX command -v flock >/dev/null && PATH=$PX command -v tar >/dev/null && PATH=$PX command -v sha256sum >/dev/null'
check "  controprova col ripiego (HOME con spazi): rosso_generico e verde veri, copia e progetto intatti, lock rilasciato" 'cpx "$PL" "$T/casa ripiego à" "$PX"'
check "  ripieghi dichiarati" 'grep -q "^counterproof: rsync assente: copia di ripiego" "$T/out"'
if command -v rsync >/dev/null 2>&1 && command -v flock >/dev/null 2>&1; then
  check "  controprova con rsync e flock: stessi esiti" 'cpx "$PL" "$T/casa rsync à" && ! grep -q "rsync assente" "$T/out"'
else
  echo "SALTATO [controprova con rsync]: rsync o flock assenti su questa piattaforma (Git Bash): provato solo il ripiego"
fi
if M5=$(mutante m5-cd scripts/counterproof.sh 's/^  (cd "\$cwd" || exit 1$/  (cd $cwd || exit 1/'); then
  check "controprova M5: cd \$cwd senza virgolette nel runner -> il caso 5 e' rosso (la mutazione verde non resta verde)" '! cpx "$M5" "$T/casa m5 à" "$PX"'
else non_applicabile M5; fi
if M6=$(mutante m6-tar scripts/fic-mirror.sh 's/| (cd "\$dst" && tar -xpf -)$/| (cd $dst \&\& tar -xpf -)/'); then
  check "controprova M6: cd \$dst senza virgolette nel tar del ripiego -> il caso del ripiego e' rosso" '! cpx "$M6" "$T/casa m6 à" "$PX"'
else non_applicabile M6; fi

pulisci() { # <fic-mirror.sh>: fic_mirror_pulisci con un glob dei preparati con spazi: via la cartella giusta della copia e
  # nient'altro (divisa sugli spazi, `rm -rf` riceverebbe «gen», «con» e «spazi», gli ultimi relativi alla cartella corrente)
  local C="$T/copia con spazi à" W="$T/cwd pulisci"
  rm -rf "$C" "$W"; mkdir -p "$C/modulo uno/gen con spazi" "$C/modulo uno/gen" "$W/con" "$W/spazi"
  echo g > "$C/modulo uno/gen con spazi/a.txt"; echo t > "$C/modulo uno/gen/tieni.txt"; echo x > "$W/con/x"; echo x > "$W/spazi/x"
  (cd "$W" && . "$1" && fic_mirror_pulisci "$C" "modulo uno" "" "gen con spazi/*.txt") > "$T/out" 2>&1 || return 1
  [ ! -e "$C/modulo uno/gen con spazi" ] && [ -f "$C/modulo uno/gen/tieni.txt" ] && [ -f "$W/con/x" ] && [ -f "$W/spazi/x" ]
}
check "  fic_mirror_pulisci, glob dei preparati con spazi -> via solo quella cartella della copia" 'pulisci "$S/fic-mirror.sh"'
if M11=$(mutante m11-pulisci scripts/fic-mirror.sh 's/ g v IFS=   # pk08: IFS vuoto, una voce con spazi non si divide nel rm$/ g v/'); then
  check "controprova M11: fic_mirror_pulisci senza IFS vuoto -> rm tocca la cartella sbagliata della copia e «con»/«spazi» della cartella corrente" '! pulisci "$M11/scripts/fic-mirror.sh"'
else non_applicabile M11; fi

# --- 6. ciclo-worktree.sh crea | rimuovi ----------------------------------------------------------------------------------------
WT="$(dirname "$PC_")/progetto con spazi à-fic-uno"
cw() { (cd "$P" && bash "$1/scripts/ciclo-worktree.sh" "${@:2}") > "$T/out" 2>&1; }
cw "$PL" crea .claude/.ai-workflow/spec-uno.md; rc=$?
check "6. crea: worktree con spazi (ultima riga), branch fic/uno, spec copiata" '[ "$rc" = 0 ] && [ "$(tail -1 "$T/out")" = "$WT" ] && [ "$(git -C "$WT" symbolic-ref --short HEAD 2>/dev/null)" = fic/uno ] && cmp -s "$AIW/spec-uno.md" "$WT/.claude/.ai-workflow/spec-uno.md"'
check "  dipendenza collegata (collegamento, non copia) nel modulo con spazi" '[ -L "$WT/modulo uno/dipendenze" ] && grep -qx "dipendenza installata" "$WT/modulo uno/dipendenze/dentro.txt"'
check "  preparato in una cartella con spazi copiato nel worktree" '[ -f "$WT/modulo uno/generati con spazi/guida.txt" ] && grep -q "preparati copiati in modulo uno: 1 file" "$T/out"'
WLK=$(git -C "$WT" rev-parse --absolute-git-dir 2>/dev/null)/full-implementation-cycle.lock
(cd "$WT" && bash "$S/run-phase.sh" --lock-status) > "$T/out" 2>&1; rc=$?
check "  --lock-status dal worktree con spazi -> libero" '[ "$rc" = 0 ] && grep -qx libero "$T/out"'
sleep 60 & vivo=$!
mkdir -p "$WLK" && printf 'run=x\nlabel=09-implement\nsince=x\npid=%s\n' "$vivo" > "$WLK/owner"
cw "$PL" rimuovi uno --branch; rc=$?
check "  rimuovi col lock del worktree tenuto da un processo vivo -> STOP (3), worktree e collegamento intatti" '[ "$rc" = 3 ] && grep -q "lock delle fasi di codice del worktree non libero" "$T/out" && [ -L "$WT/modulo uno/dipendenze" ]'
kill "$vivo" 2>/dev/null; wait "$vivo" 2>/dev/null; rm -rf "$WLK"
cw "$PL" rimuovi uno --branch; rc=$?
check "  rimuovi: worktree e branch spariti, la dipendenza della fonte intatta" '[ "$rc" = 0 ] && [ ! -e "$WT" ] && ! git -C "$P" show-ref -q --verify refs/heads/fic/uno && grep -qx "dipendenza installata" "$P/modulo uno/dipendenze/dentro.txt"'
if M7=$(mutante m7-wt scripts/ciclo-worktree.sh 's/git -C "\$MAIN" worktree add -q -b "\$BRANCH" "\$WT" "\$BASE"/git -C "$MAIN" worktree add -q -b "$BRANCH" $WT "$BASE"/'); then
  cw "$M7" crea .claude/.ai-workflow/spec-uno.md; rc=$?
  check "controprova M7: \$WT senza virgolette in git worktree add -> crea non riesce (exit $rc)" '[ "$rc" != 0 ] && [ ! -e "$WT" ]'
  git -C "$P" worktree prune 2>/dev/null; git -C "$P" branch -q -D fic/uno 2>/dev/null
else non_applicabile M7; fi
cw_mut() { # <plugin mutante>: crea (l'uscita resta in $T/out), poi rimuovi --forza --branch col plugin vero
  cw "$1" crea .claude/.ai-workflow/spec-uno.md; cp "$T/out" "$T/out.crea"
  cw "$PL" rimuovi uno --forza --branch; cp "$T/out" "$T/out.rimuovi"; cp "$T/out.crea" "$T/out"
}
if M9=$(mutante m9-link scripts/worktree-lib.sh '/^    local IFS=   # pk08: niente divisione/d'); then
  cw_mut "$M9"
  check "controprova M9: dep_links senza IFS vuoto -> la dipendenza nel modulo con spazi non si collega" '! grep -q "dipendenze collegate dal tree principale: 1 " "$T/out" && [ ! -e "$WT" ]'
else non_applicabile M9; fi
if M10=$(mutante m10-prep scripts/ciclo-worktree.sh 's/^        oifs=\$IFS; IFS=; fs=("\$MAINC\/\$pre"\$g); IFS=\$oifs .*$/        fs=("$MAINC\/$pre"$g)/'); then
  cw_mut "$M10"
  check "controprova M10: preparati senza IFS vuoto -> il preparato nella cartella con spazi non si copia" '! grep -q "preparati copiati in modulo uno: 1 file" "$T/out" && [ ! -e "$WT" ]'
else non_applicabile M10; fi

# --- 7. plan-check.sh gen con MAAT_CONFIG con spazi ---------------------------------------------------------------------------
CF="$T/config con spazi à/maat.json"; mkdir -p "$(dirname "$CF")"
cat > "$CF" <<EOF
{"versione_schema": 1,
 "moduli": [{"nome": "due", "radice": "mod-due", "ambiente": "nativo", "comandi": {"test": "bash {test}"}, $CMDC}]}
EOF
SP="$AIW/spec-pc.md"
printf '%s\n' "# P" "## Requisiti funzionali" "1. RF1 — A." "## Piano di implementazione" "Plan format: 2" \
  "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" "### File toccati" '- `mod-due/core.txt`' "### Passi" \
  "#### Blocco B1 — tutto" 'scrive: `mod-due/core.txt`' "dopo: nessuno" "" "| id | file | modifica | test |" "|---|---|---|---|" \
  '| P1 | `mod-due/core.txt` | uno | T1 |' "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" "|---|---|---|" \
  "| RF1 | P1 | T1 |" "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
  '| T1 | RF1 | `mod-due/prova.sh::prova` | rosso se: rosso | `mod-due/core.txt` · `DUE` · `DUE=1` → `DUE=1 ROSSO` · rosso se: `rosso` |' > "$SP"
RCP=""
pcx() { # <plugin> <HOME>: gen con MAAT_CONFIG con spazi, poi la riga cp ESEGUITA com'e' -> la controprova di T1 gira
  local rp=${SP%.md}.run
  rm -rf "$rp"; mkdir -p "$2"
  (cd "$P" && MAAT_CONFIG=$CF bash "$1/scripts/plan-check.sh" gen "$SP") > "$T/out" 2>&1 || return 1
  RCP=$(sed -n 's/^cmd counterproof: //p' "$rp/gen/procedura.txt")
  printf 'riga cp: %s\n' "$RCP" >> "$T/out"
  [ -n "$RCP" ] || return 1
  (cd "$P" && HOME=$2 PATH=$PX bash -c "$RCP") >> "$T/out" 2>&1 || return 1
  grep -q "esito=PASS prove=1/1" "$T/out" && grep -q '"esito": *"rosso_generico"' "$rp/counterproof/T1.json"
}
check "7. plan-check gen, MAAT_CONFIG con spazi: la riga cp eseguita com'e' fa girare la controprova del modulo di quella configurazione" 'pcx "$PL" "$T/casa pc à"'
check "  la riga cp porta MAAT_CONFIG con spazi e il plugin con spazi" 'grep -qF "config con spazi à/maat.json" <<< "$RCP" && grep -qF "plugin con spazi à/maat/scripts/counterproof.sh" <<< "$RCP"'
if M8=$(mutante m8-mc scripts/plan-check.sh 's/        env += " MAAT_CONFIG=" + mc.sq_se_serve(tr(os.environ\["MAAT_CONFIG"\].replace("\\\\", "\/")))/        env += " MAAT_CONFIG=" + tr(os.environ["MAAT_CONFIG"].replace("\\\\", "\/"))/'); then
  check "controprova M8: MAAT_CONFIG senza quotatura nella riga cp -> il caso 7 e' rosso" '! pcx "$M8" "$T/casa m8 à"'
else non_applicabile M8; fi

# --- 8. watch-phase.sh dal plugin con spazi, run dir con spazi -----------------------------------------------------------------
WR="$T/run con spazi à.run"; mkdir -p "$WR/log"
{ printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"text","text":"▶ lavoro"}]}}'
  printf '%s\n' '{"type":"result","is_error":false,"result":"ESITO FASE 1: OK","duration_ms":1000,"num_turns":1}'; } > "$WR/log/f.jsonl"
echo 0 > "$WR/log/f.exit"
timeout 30 bash "$S/watch-phase.sh" "$WR" f > "$T/out" 2>&1; rc=$?
check "8. watch-phase.sh dal plugin con spazi, run dir con spazi -> la riga di fine, exit 0" '[ "$rc" = 0 ] && tail -1 "$T/out" | grep -q "^■ ESITO FASE 1: OK"'

echo "spazi.test.sh: $pass ok, $fail falliti"
[ "$fail" = 0 ]
