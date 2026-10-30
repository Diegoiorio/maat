#!/usr/bin/env bash
# guard.test.sh — test deterministici di guard.py (nucleo + regole del progetto) e di guard-hook.sh (hook del plugin).
#   bash scripts/guard.test.sh
# Ogni caso: il JSON che Claude passerebbe all'hook, l'esito atteso (0 ammesso, ask chiede, 2 negato).
#   1. equivalenza sull'esempio nuxt-fastapi: i casi di prima della divisione (fixture tests/guard-esempio.cases) con
#      examples/nuxt-fastapi.maat.json → stessa decisione e stesso livello;
#   2. guard-hook.sh (i casi dell'hook di .claude/settings.json di prima, riscritti; senza Python: ask su tutto);
#   3. nucleo da solo, maat.json assente o non valido, radice del progetto, MAAT_CONFIG;
#   4. involucri del plugin (passo 3-bis); 5. lista DENY; 6. motivi in tre parti, lingua, richiamo nelle skill (R11).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# forma C:/… dove c'e' cygpath (Git Bash), altrimenti il percorso com'e' (Linux, pk08)
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
. "$HERE/python.sh" || { echo "interprete Python non trovato" >&2; exit 1; }
REPO=$(cd "$HERE/../../.." && { pwd -W 2>/dev/null || pwd; })
MAAT=$(cd "$HERE/.." && { pwd -W 2>/dev/null || pwd; })
# una cartella assoluta FUORI dal repo (scratchpad) per la fixture: la forma di prima su Windows, POSIX altrove (pk08)
case $REPO in [A-Za-z]:/*) SCRATCH=C:/Temp/claude/scratch ;; *) SCRATCH=/tmp/claude/scratch ;; esac
# Tree PRINCIPALE (non un worktree collegato, dove git commit/checkout/add sono ammessi): cwd dei casi che si
# aspettano la conferma o il divieto su quei comandi. Dal tree principale e' REPO stesso.
MAINTREE=$(dirname "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)")
fail=0 n=0
unset FIC_SESSION_GUARD MAAT_CONFIG CLAUDE_PROJECT_DIR MAAT_ROOT FIC_PHASE   # mai ereditate: ogni sezione le sceglie
export PYTHONDONTWRITEBYTECODE=1
SSJ=$(nat "$MAAT/examples/nuxt-fastapi.maat.json")

# Repo temporaneo con un worktree COLLEGATO: MAIN ha git-dir == git-common-dir, WT no.
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
git init -q "$T/main" && (cd "$T/main" && git config user.email t@t && git config user.name t && echo a > a && git add a 2>/dev/null && git commit -qm init && git worktree add -q "$T/wt" -b wt) || { echo "setup del repo temporaneo fallito" >&2; exit 1; }
MAIN=$(cd "$T/main" && { pwd -W 2>/dev/null || pwd; }) WT=$(cd "$T/wt" && { pwd -W 2>/dev/null || pwd; })

run() { # $1 atteso, $2 fase, $3 JSON
  n=$((n + 1))
  local got
  printf '%s' "$3" | FIC_PHASE="$2" FIC_REPO="$REPO" "$FIC_PY" "$HERE/guard.py" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$1" ]; then fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [$2] $3"; fi
}
bash_cmd() { # JSON di un tool Bash con il comando $1
  "$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$REPO"
}
write_path() { # $1 tool, $2 percorso
  "$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2]},"cwd":sys.argv[3]}))' "$1" "$2" "$REPO"
}
deny()  { run 2 "${2:-implement}" "$(bash_cmd "$1")"; }
allow() { run 0 "${2:-implement}" "$(bash_cmd "$1")"; }
# corsia di implementazione (harness-pt13)
srun() { # $1 atteso, $2 FIC_WRITE_SCOPE, $3 JSON
  n=$((n + 1))
  local got
  printf '%s' "$3" | FIC_PHASE=implement FIC_LANE=1 FIC_WRITE_SCOPE="$2" FIC_REPO="$REPO" "$FIC_PY" "$HERE/guard.py" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$1" ]; then fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [scope=$2] $3"; fi
}
# cartella di lavoro da cartelle.lavoro (pk04a-1): il progetto RL ha la sua maat.json, e run-phase.sh esporta
# MAAT_CONFIG con quella del progetto
RL="$T/lavoro conf"; mkdir -p "$RL/.claude"
printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}], "cartelle": {"lavoro": "lavoro/cicli"}}\n' > "$RL/.claude/maat.json"
RLW=$(cd "$RL" && { pwd -W 2>/dev/null || pwd; })
lrun() { # $1 atteso, $2 fase, $3 percorso relativo al progetto, [$4 FIC_WRITE_SCOPE]
  n=$((n + 1)); local got
  "$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]},"cwd":sys.argv[2]}))' "$3" "$RLW" |
    MAAT_CONFIG="$RLW/.claude/maat.json" FIC_PHASE="$2" FIC_LANE=1 FIC_WRITE_SCOPE="${4:-}" FIC_REPO="$RLW" "$FIC_PY" "$HERE/guard.py" >/dev/null 2>&1; got=$?
  [ "$got" = "$1" ] || { fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [cartelle.lavoro, $2 ${4:-}] $3"; }
}
ujson() { # $1 comando, $2 cwd, $3 tool (default Bash)
  "$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[3],"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2" "${3:-Bash}"
}
# esito dell'hook: 0 = ammesso (nessun output) · ask = chiede conferma (JSON su stdout, exit 0) · 2 = negato
verdict() { # $1 exit, $2 stdout
  if [ "$1" = 0 ] && [ -z "$2" ]; then echo 0
  elif [ "$1" = 0 ] && printf '%s' "$2" | grep -Eq '"permissionDecision": ?"ask"'; then echo ask
  else echo "exit=$1:$2"; fi
}
urun() { # $1 atteso (0|ask|2), $2 cwd, $3 comando, $4 tool, $5 FIC_PHASE (vuota = sessione principale)
  n=$((n + 1))
  local out rc got
  out=$(ujson "$3" "$2" "${4:-Bash}" | env -u FIC_REPO FIC_PHASE="${5:-}" "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null); rc=$?
  got=$(verdict "$rc" "$out"); [ "$rc" = 2 ] && got=2
  if [ "$got" != "$1" ]; then fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [universal ${4:-Bash} fase=${5:-} cwd $2 config=${MAAT_CONFIG:-}] $3"; fi
}
udeny()  { urun ask "${2:-$REPO}" "$1" "${3:-Bash}"; }   # sessione principale: chiede conferma
uallow() { urun 0 "${2:-$REPO}" "$1" "${3:-Bash}"; }
pdeny()  { urun 2 "${2:-$REPO}" "$1" "${3:-Bash}" implement; }   # sotto-sessione: nega
# il motivo della risposta ask (stdin: lo stdout dell'hook)
motivo() { "$FIC_PY" -c 'import json,sys
sys.stdout.reconfigure(encoding="utf-8"); sys.stdin.reconfigure(encoding="utf-8")
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])
except Exception: print("")'; }

# ================================================================ 1. equivalenza sull'esempio nuxt-fastapi
export MAAT_CONFIG="$SSJ"
n0=$n f0=$fail
. "$MAAT/tests/guard-esempio.cases"
unset MAAT_CONFIG FIC_SESSION_GUARD
echo "equivalenza nuxt-fastapi: $((n - n0 - fail + f0))/$((n - n0)) casi uguali a prima"
# falsificabile: run_tests.sh e' una suite solo perche' guardia.suite lo dichiara (non e' cablato nel nucleo)
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1],encoding="utf-8")); del c["guardia"]["suite"]; json.dump(c,open(sys.argv[2],"w",encoding="utf-8"))' "$SSJ" "$T/senza-suite.json"
export MAAT_CONFIG=$(nat "$T/senza-suite.json")
allow "cd modules/api && ./run_tests.sh" plan
deny  "cd modules/api && .venv/Scripts/python.exe -m pytest tests" plan
unset MAAT_CONFIG
# rilascio eseguito direttamente dalla sua cartella (review pk05, blocker 1): grave come prima della divisione
export MAAT_CONFIG="$SSJ"
udeny "cd script && ./deploy-production.sh deploy"
FIC_SESSION_GUARD=prod udeny "cd script && ./deploy-production.sh deploy"
pdeny "cd script && ./deploy-production.sh deploy"
deny  "cd script && ./deploy-production.sh deploy"
# falsificabile: senza deploy-production in guardia.produzione lo stesso comando passa
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1],encoding="utf-8")); c["guardia"]["produzione"].remove("deploy-production"); json.dump(c,open(sys.argv[2],"w",encoding="utf-8"))' "$SSJ" "$T/senza-deploy.json"
export MAAT_CONFIG=$(nat "$T/senza-deploy.json")
uallow "cd script && ./deploy-production.sh deploy"
unset MAAT_CONFIG

# ================================================================ 2. hook del plugin: guard-hook.sh
# Progetto di prova con l'esempio nuxt-fastapi come .claude/maat.json; CLAUDE_PROJECT_DIR arriva in forma Windows.
SS="$T/progetto ss"; mkdir -p "$SS/.claude" "$SS/sotto/cartella"; cp "$MAAT/examples/nuxt-fastapi.maat.json" "$SS/.claude/maat.json"
SSW=$(cd "$SS" && { pwd -W 2>/dev/null || pwd; })
case $SSW in [A-Za-z]:/*) PDIR=$(printf '%s' "$SSW" | tr '/' '\\') ;; *) PDIR=$SSW ;; esac   # su Linux resta nativo
HOOKJ=$("$FIC_PY" -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$MAAT/hooks/hooks.json")
n=$((n + 1))
[ "$HOOKJ" = 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard-hook.sh"' ] || { fail=$((fail + 1)); echo "FAIL: hooks.json non lancia guard-hook.sh ($HOOKJ)"; }
hout() { # $1 comando, $2 FIC_PYTHON, $3 tool, $4 FIC_PHASE, $5 cwd · stdout dell'hook, rc in HRC
  ujson "$1" "${5:-$REPO}" "${3:-Bash}" | env -u MAAT_CONFIG CLAUDE_PROJECT_DIR="$PDIR" FIC_PYTHON="${2:-}" FIC_PHASE="${4:-}" bash "$HERE/guard-hook.sh" 2>/dev/null
}
hrun() { # $1 atteso (0|ask|2), $2 comando, $3 FIC_PYTHON (vuoto = quello trovato), $4 tool, $5 FIC_PHASE, $6 cwd
  n=$((n + 1))
  local out rc got
  out=$(hout "$2" "${3:-}" "${4:-Bash}" "${5:-}" "${6:-}"); rc=$?
  got=$(verdict "$rc" "$out"); [ "$rc" = 2 ] && got=2
  if [ "$got" != "$1" ]; then fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [guard-hook.sh, py=${3:-auto} ${4:-Bash} fase=${5:-}] $2"; fi
}
hrun ask "wsl -- bash -lc 'ssh root@prod.example.internal true'"
hrun ask "git push"
hrun 0   "git status --short"
hrun 0   "git status" "" PowerShell
hrun ask "git push" "" PowerShell
hrun ask "docker compose up" "" PowerShell
hrun 2   "git push" "" Bash implement
# il review worker lancia le controprove: l'hook di sessione non deve negarle
hrun 0   "wsl -- bash -lc 'bash $WREPO/script/test/counterproof.sh $WREPO/.claude/.ai-workflow/spec-x.run/counterproof/mutations.json'" "" Bash review
# senza Python: mai fail-open — ask su OGNI comando in sessione, exit 2 in sotto-sessione
NOPY="$T/non-esiste.exe"
hrun ask "curl -s https://app.example.com/health" "$NOPY"
hrun ask "git push" "$NOPY"
hrun ask "docker ps" "$NOPY"
hrun ask "docker compose up" "$NOPY" PowerShell
hrun ask "ls -la" "$NOPY"                 # prima: 0 (ripiego a regex); ora ask, voluto (pk05)
hrun ask "git status --short" "$NOPY"     # prima: 0; ora ask, voluto (pk05)
hrun 2   "git push" "$NOPY" Bash implement
hrun 2   "ls" "$NOPY" Bash implement
n=$((n + 1))
hout "git push" "$NOPY" | "$FIC_PY" -c 'import json,sys; h=json.load(sys.stdin)["hookSpecificOutput"]; sys.exit(0 if h["hookEventName"]=="PreToolUse" and h["permissionDecision"]=="ask" and h["permissionDecisionReason"].startswith("Python non trovato: guardia non disponibile") else 1)' \
  || { fail=$((fail + 1)); echo "FAIL: formato JSON della risposta ask senza Python"; }
# guard.py che va in crash (uscita diversa da 0/2): chiede conferma, o nega in sotto-sessione — mai fail-open
printf '#!/usr/bin/env bash\n[ "${1:-}" = -c ] && exit 0\ncat >/dev/null; exit 1\n' > "$T/py-rotto"; chmod +x "$T/py-rotto"
hrun ask "ls -la" "$T/py-rotto"
hrun 2   "ls -la" "$T/py-rotto" Bash implement
n=$((n + 1))
m=$(hout "ls -la" "$T/py-rotto" | motivo)
case $m in "guardia in errore (uscita 1)"*) ;; *) fail=$((fail + 1)); echo "FAIL: motivo di py-rotto: $m" ;; esac
# in sotto-sessione l'hook del plugin chiama --universal senza uscite anticipate: legge il contenuto di bash <script>
# (controprova: un'uscita anticipata «exit 0 se FIC_PHASE» lo fa diventare 0)
mkdir -p "$T/main/script"
printf '#!/usr/bin/env bash\nssh -i k root@prod.example.internal true\n' > "$T/main/script/h-prod.sh"
hrun 2   "bash script/h-prod.sh" "" Bash implement "$MAIN"
hrun ask "bash script/h-prod.sh" "" Bash "" "$MAIN"
# radice del progetto: CLAUDE_PROJECT_DIR, non la cwd del comando (una sottocartella senza maat.json)
hrun ask "curl -s https://www.example.org/" "" Bash "" "$SSW/sotto/cartella"
n=$((n + 1))
m=$(hout "curl -s https://www.example.org/" "" Bash "" "$SSW/sotto/cartella" | motivo)
case $m in *"guardia.produzione"*) case $m in *"maat.json non"*) fail=$((fail + 1)); echo "FAIL: radice dalla cwd: $m" ;; esac ;;
  *) fail=$((fail + 1)); echo "FAIL: radice del progetto: il motivo non e' quello della produzione: $m" ;; esac
# sotto-sessione: MAAT_CONFIG impostato e CLAUDE_PROJECT_DIR assente → le regole del progetto valgono
n=$((n + 1))
o=$(ujson "curl -s https://www.example.org/" "$REPO" | env -u CLAUDE_PROJECT_DIR MAAT_CONFIG="$SSW/.claude/maat.json" bash "$HERE/guard-hook.sh" 2>/dev/null | motivo)
case $o in *"guardia.produzione"*) ;; *) fail=$((fail + 1)); echo "FAIL: MAAT_CONFIG senza CLAUDE_PROJECT_DIR: $o" ;; esac
n=$((n + 1))
ujson "bash script/dev/dev-sql.sh --apply x" "$REPO" | env -u CLAUDE_PROJECT_DIR MAAT_CONFIG="$SSW/.claude/maat.json" FIC_PHASE=implement bash "$HERE/guard-hook.sh" >/dev/null 2>&1
[ $? = 2 ] || { fail=$((fail + 1)); echo "FAIL: MAAT_CONFIG in sotto-sessione: dev-sql.sh --apply non negato"; }
# guardia ridotta attraverso l'hook
export FIC_SESSION_GUARD=prod
hrun ask "git push"
hrun 0   "npm install"
hrun 2   "npm install" "" Bash implement
unset FIC_SESSION_GUARD

# ================================================================ 3. nucleo, maat.json assente o non valido
MIN="$T/min"; mkdir -p "$MIN"; printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}]}\n' > "$MIN/maat.json"
printf '{"versione_schema": 1}\n' > "$T/rotta.json"            # manca moduli: non valida
printf '{"versione_schema": 1, "moduli": [\n' > "$T/troncata.json"   # JSON illeggibile
export MAAT_CONFIG; MAAT_CONFIG=$(nat "$MIN/maat.json")   # valido, senza sezione guardia: solo il nucleo
udeny  "git push --force origin x"
udeny  "ssh host"
udeny  "npm install"
uallow "ls"
uallow "curl https://esempio.it"
unset MAAT_CONFIG                                                # assente: nessuna fonte
udeny  "curl https://esempio.it"
uallow "ls"
pdeny  "curl https://esempio.it"
n=$((n + 1))
m=$(ujson "curl https://esempio.it" "$REPO" | "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)
case $m in *"maat.json non trovato"*) ;; *) fail=$((fail + 1)); echo "FAIL: maat.json assente, motivo: $m" ;; esac
n=$((n + 1))   # CLAUDE_PROJECT_DIR verso un progetto senza il file: stesso ripiego
m=$(ujson "curl https://esempio.it" "$REPO" | CLAUDE_PROJECT_DIR="$(nat "$T/main")" "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)
case $m in *"maat.json non trovato"*) ;; *) fail=$((fail + 1)); echo "FAIL: progetto senza maat.json, motivo: $m" ;; esac
for f in rotta troncata; do
  MAAT_CONFIG=$(nat "$T/$f.json") udeny "curl https://esempio.it"
  n=$((n + 1))
  m=$(ujson "curl https://esempio.it" "$REPO" | MAAT_CONFIG=$(nat "$T/$f.json") "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)
  case $m in *"maat.json non valido"*) ;; *) fail=$((fail + 1)); echo "FAIL: maat.json $f, motivo: $m" ;; esac
  MAAT_CONFIG=$(nat "$T/$f.json") uallow "ls"
  MAAT_CONFIG=$(nat "$T/$f.json") udeny "git push"      # il nucleo resta
done
# guardia ridotta: con maat.json non valido un host resta grave
export FIC_SESSION_GUARD=prod
MAAT_CONFIG=$(nat "$T/rotta.json") udeny "curl https://esempio.it"
MAAT_CONFIG=$(nat "$T/rotta.json") uallow "npm install"
unset FIC_SESSION_GUARD

# ================================================================ 4. involucri del plugin (passo 3-bis)
# Un plugin finto sotto .claude/plugins, con uno spazio; MAAT_ROOT in forma C:/…, il comando in forma /mnt/<drive>/…
PF="$T/home/.claude/plugins/maat prova"; mkdir -p "$PF/scripts"
printf '#!/usr/bin/env bash\nrsync -a a/ b/\n' > "$PF/scripts/test-fast.sh"
printf '#!/usr/bin/env bash\nssh root@h true\n' > "$PF/scripts/altro.sh"
PFW=$(cd "$PF" && { pwd -W 2>/dev/null || pwd; }); PFM=$(printf '%s' "$PFW" | sed 's#^\(.\):#/mnt/\L\1#')
export MAAT_CONFIG="$SSJ"
MAAT_ROOT="$PFW" uallow "wsl -- bash -lc 'bash \"$PFM/scripts/test-fast.sh\" x.test.ts'"
MAAT_ROOT="$PFW" uallow "bash \"$PFW/scripts/test-fast.sh\" x.test.ts"
MAAT_ROOT="$PFW" udeny  "wsl -- bash -lc 'bash \"$PFM/scripts/altro.sh\" x'"         # non e' un involucro: si legge
udeny "wsl -- bash -lc 'bash \"$PFM/scripts/test-fast.sh\" x.test.ts'"                # un altro plugin: si legge
unset MAAT_CONFIG

# ================================================================ 5. lista DENY (--disallowedTools di run-phase.sh)
OGGI=("Bash(ssh:*)" "Bash(scp:*)" "Bash(sftp:*)" "Bash(rsync:*)"
  "Bash(bash script/deploy-production.sh:*)" "Bash(bash script/rsync-once.sh:*)" "Bash(bash script/rsync.sh:*)"
  "Bash(bash script/prod:*)" "Bash(script/deploy-production.sh:*)" "Bash(script/rsync-once.sh:*)"
  "Bash(git commit:*)" "Bash(git push:*)" "Bash(git reset:*)" "Bash(git checkout:*)" "Bash(git switch:*)"
  "Bash(git clean:*)" "Bash(git stash:*)" "Bash(git rebase:*)" "Bash(git merge:*)" "Bash(git restore:*)"
  "Bash(docker:*)" "Bash(psql:*)" "Bash(pip install:*)" "Bash(npm install:*)" "Bash(rm -rf:*)")
DL=$(MAAT_CONFIG="$SSJ" "$FIC_PY" "$HERE/guard.py" --deny-list | tr -d '\r')
for v in "${OGGI[@]}"; do
  n=$((n + 1)); grep -qxF -- "$v" <<< "$DL" || { fail=$((fail + 1)); echo "FAIL: lista DENY senza $v"; }
done
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1],encoding="utf-8")); del c["guardia"]["vietati_extra"]; json.dump(c,open(sys.argv[2],"w",encoding="utf-8"))' "$SSJ" "$T/senza-vietati.json"
DL2=$(MAAT_CONFIG=$(nat "$T/senza-vietati.json") "$FIC_PY" "$HERE/guard.py" --deny-list | tr -d '\r')
n=$((n + 1))   # falsificabile: senza vietati_extra le voci rsync mancano
! grep -qF "rsync-once.sh" <<< "$DL2" || { fail=$((fail + 1)); echo "FAIL: le voci rsync non vengono da vietati_extra"; }
DL3=$(MAAT_CONFIG=$(nat "$MIN/maat.json") "$FIC_PY" "$HERE/guard.py" --deny-list | tr -d '\r')
n=$((n + 1))   # senza guardia: solo il nucleo
[ "$(grep -c . <<< "$DL3")" = 19 ] || { fail=$((fail + 1)); echo "FAIL: lista DENY del solo nucleo: $DL3"; }

# ================================================================ 6. R11: motivi in tre parti, lingua, richiamo
tre() { # $1 descrizione, $2 il motivo (UTF-8)
  n=$((n + 1))
  printf '%s' "$2" | "$FIC_PY" -c 'import sys
sys.stdin.reconfigure(encoding="utf-8")
p = sys.stdin.read().split(" — ")
ok = len(p) == 3 and all(x.strip() for x in p) and p[1].startswith(("regola del nucleo", "regola del progetto"))
sys.exit(0 if ok else 1)' || { fail=$((fail + 1)); echo "FAIL: motivo non in tre parti [$1]: $2"; }
}
ask_di() { # $1 comando, $2 cwd · il motivo con l'esempio nuxt-fastapi
  ujson "$1" "${2:-$REPO}" | MAAT_CONFIG="$SSJ" "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo
}
tre produzione "$(ask_di "curl -s https://www.example.org/")"
tre produzione_script "$(ask_di "bash script/x-prod.sh" "$MAIN")"
tre rilascio "$(ask_di "bash script/deploy-production.sh deploy")"
tre involucro_opzione "$(ask_di "bash script/dev/dev-sql.sh --apply x")"
tre heredoc_py "$(ask_di $'python - <<\'EOF\'\nopen("f", "w").write("x")\nEOF')"
tre find_delete "$(ask_di "find . -name x -delete")"
tre git_worktree "$(ask_di "git commit -m x" "$MAIN")"
tre "git_worktree, percorso con il separatore" "$(ask_di "git -C 'x — y' commit -m x" "$MAIN")"
tre git_push "$(ask_di "git push")"
tre git_stato "$(ask_di "git stash" "$WT")"
tre git_forza "$(ask_di "git branch -D x")"
tre git_storia "$(ask_di "git filter-branch HEAD")"
tre remoto "$(ask_di "ssh 'a — b'")"
tre docker "$(ask_di "docker ps")"
tre db "$(ask_di "psql -c x")"
tre install "$(ask_di "npm install")"
tre rm_rf "$(ask_di "rm -rf x")"
tre remove_item "$(ask_di "Remove-Item -Recurse -Force x")"
tre input "$(printf 'non json' | MAAT_CONFIG="$SSJ" "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)"
tre config_assente "$(ujson "curl https://esempio.it" "$REPO" | "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)"
tre config_non_valido "$(ujson "curl https://esempio.it" "$REPO" | MAAT_CONFIG=$(nat "$T/rotta.json") "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)"
tre "guard-hook.sh senza Python" "$(hout "ls" "$NOPY" | motivo)"
tre "guard-hook.sh con py-rotto" "$(hout "ls" "$T/py-rotto" | motivo)"
# ogni voce della tabella, in it e in en, ha tre parti; le seconde nominano la regola
n=$((n + 1))
"$FIC_PY" -c 'import importlib.util, sys
s = importlib.util.spec_from_file_location("g", sys.argv[1]); g = importlib.util.module_from_spec(s); s.loader.exec_module(g)
bad = []
for k, v in g.MSG.items():
    for lang, pref in (("it", ("regola del nucleo", "regola del progetto")), ("en", ("core rule", "project rule"))):
        t = v[lang]
        if len(t) != 3 or not all(x.strip() for x in t) or any(" — " in x for x in t) or not t[1].startswith(pref) or "{" in t[1] + t[2]:
            bad.append((k, lang))
if bad:
    print(bad)
sys.exit(1 if bad else 0)' "$HERE/guard.py" || { fail=$((fail + 1)); echo "FAIL: tabella MSG di guard.py"; }
# lingua: en se dichiarata; it con una lingua fuori tabella (maat.json non valido) o con maat.json non valido
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1])); c["lingua"]=sys.argv[3]; json.dump(c,open(sys.argv[2],"w"))' "$MIN/maat.json" "$T/en.json" en
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1])); c["lingua"]=sys.argv[3]; json.dump(c,open(sys.argv[2],"w"))' "$MIN/maat.json" "$T/xx.json" xx
lingua() { # $1 atteso (it|en), $2 file
  n=$((n + 1))
  local m; m=$(ujson "git push" "$REPO" | MAAT_CONFIG=$(nat "$2") "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)
  case "$1:$m" in "it:"*" — regola del nucleo"*|"en:"*" — core rule"*) ;; *) fail=$((fail + 1)); echo "FAIL: lingua $1 con $2: $m" ;; esac
}
lingua en "$T/en.json"
lingua it "$T/xx.json"
lingua it "$T/rotta.json"
lingua it "$T/non-esiste.json"
# richiamo della regola della descrizione dei comandi nelle 5 skill della sessione principale (R11.1)
n=$((n + 1))
[ -s "$MAAT/docs/descrizione-comandi.md" ] || { fail=$((fail + 1)); echo "FAIL: docs/descrizione-comandi.md assente"; }
for s in full-implementation-cycle plan-review-cycle plan-review-cycle-light implementation-review-cycle setup; do
  n=$((n + 1))
  grep -rqF 'scrivi `description` secondo `${CLAUDE_PLUGIN_ROOT}/docs/descrizione-comandi.md`' "$MAAT/skills/$s" \
    || { fail=$((fail + 1)); echo "FAIL: la skill $s non richiama docs/descrizione-comandi.md"; }
done

# 7. review di pk08: fuori da Windows il confronto dentro/fuori dal repo (fasi e corsia) piega le maiuscole su
#    /mnt/<lettera>/ (drvfs) e sul Mac; su Linux nativo no (Repo e repo sono due cartelle). Il Mac si simula SOLO qui,
#    con sys.platform = "darwin" prima di eseguire guard.py. I percorsi non esistono: conta solo il confronto.
#    La forma piegata decide SOLO dentro/fuori dal repo: il percorso relativo per corsia, FIC_SCOPE e cartella di
#    lavoro conserva le maiuscole (review giro 2): `A.TXT` non vale la corsia `a.txt`, `.Claude/.AI-workflow/` non e'
#    la cartella di lavoro. Controprove automatiche, su copie del plugin: piega_repo sempre False -> rossi i casi /mnt
#    e Mac «dentro il repo»; rel piegato anche lui -> rosso il caso `A.TXT`; copia senza mutazioni -> tutto verde.
GOS=$("$FIC_PY" -c 'import os, sys; print("win" if os.name == "nt" or sys.platform.startswith(("msys", "cygwin")) else "posix")')
GPLAT=$("$FIC_PY" -c 'import sys; print(sys.platform)')
GUARD="$HERE/guard.py"   # le controprove lo spostano su una copia mutante
prun() { # $1 atteso, $2 fase, $3 FIC_REPO, $4 percorso, [$5 FIC_WRITE_SCOPE], [$6 darwin], [$7 FIC_SCOPE]
  n=$((n + 1)); local got j
  j=$("$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1]},"cwd":"/"}))' "$4")
  if [ -n "${6:-}" ]; then
    printf '%s' "$j" | FIC_PHASE="$2" FIC_LANE=1 FIC_WRITE_SCOPE="${5:-}" FIC_SCOPE="${7:-}" FIC_REPO="$3" "$FIC_PY" -c 'import runpy, sys
p = sys.argv[1]; sys.argv = [p]; sys.platform = "darwin"; runpy.run_path(p, run_name="__main__")' "$GUARD" >/dev/null 2>&1
  else
    printf '%s' "$j" | FIC_PHASE="$2" FIC_LANE=1 FIC_WRITE_SCOPE="${5:-}" FIC_SCOPE="${7:-}" FIC_REPO="$3" "$FIC_PY" "$GUARD" >/dev/null 2>&1
  fi
  got=$?
  [ "$got" = "$1" ] || { fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [maiuscole, $2 ${5:-} ${6:-} ${7:+scope}] repo=$3 percorso=$4"; }
}
printf 'a.txt\nsotto/\n' > "$T/scope-minuscolo"
SCM=$(nat "$T/scope-minuscolo")
casi_maiuscole() {
  local DR=/mnt/c/fic-guard-maiuscole/Repo NR=/home/fic-guard-maiuscole/Repo
  prun 2 plan "$DR" /mnt/c/fic-guard-maiuscole/repo/x.txt            # drvfs: maiuscole diverse, stesso repo -> negata
  prun 2 plan "$DR" /mnt/c/FIC-GUARD-MAIUSCOLE/REPO/sotto/x.txt
  prun 2 plan "$DR" "$DR/x.txt"
  prun 0 plan "$DR" /mnt/c/fic-guard-maiuscole/repo/.claude/.ai-workflow/spec-x.md   # cartella di lavoro: ammessa
  prun 2 plan "$DR" /mnt/c/fic-guard-maiuscole/repo/.Claude/.AI-workflow/spec-x.md   # maiuscole diverse: non lo e'
  prun 0 plan "$DR" /mnt/c/fic-guard-maiuscole/altro/x.txt          # fuori dal repo
  prun 2 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/b.txt a.txt # corsia: fuori da scrive:
  prun 0 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/a.txt a.txt # corsia: dentro, repo con maiuscole diverse
  prun 2 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/A.TXT a.txt # corsia con maiuscole diverse: negata
  prun 0 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/.claude/.ai-workflow/spec-x.run/f a.txt   # run dir
  prun 2 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/.Claude/.AI-workflow/spec-x.run/f a.txt
  prun 0 test-red "$DR" /mnt/c/fic-guard-maiuscole/repo/sotto/t.txt "" "" "$SCM"   # FIC_SCOPE: dentro
  prun 2 test-red "$DR" /mnt/c/fic-guard-maiuscole/repo/A.TXT "" "" "$SCM"         # FIC_SCOPE: maiuscole diverse
  prun 2 test-red "$DR" /mnt/c/fic-guard-maiuscole/repo/Sotto/t.txt "" "" "$SCM"
  if [ "$GPLAT" = darwin ]; then
    echo "SALTATO [maiuscole, Linux nativo]: il Python della guardia e' del Mac (sys.platform darwin), il confronto piega sempre"
  else
    prun 0 plan "$NR" /home/fic-guard-maiuscole/repo/x.txt            # Linux nativo: un'altra cartella
    prun 2 plan "$NR" "$NR/x.txt"
    prun 0 implement "$NR" /home/fic-guard-maiuscole/repo/b.txt a.txt
  fi
  prun 2 plan /Users/u/Repo /Users/u/repo/x.txt "" darwin             # Mac simulato: negata
  prun 2 implement /Users/u/Repo /Users/u/repo/b.txt a.txt darwin
  prun 0 implement /Users/u/Repo /Users/u/repo/a.txt a.txt darwin
  prun 2 implement /Users/u/Repo /Users/u/repo/A.TXT a.txt darwin
  prun 0 plan /Users/u/Repo /Users/u/altro/x.txt "" darwin
}
gmutante() { # <nome> <testo da sostituire, vuoto = nessuna mutazione> <testo nuovo>: copia del plugin, guard.py
  # mutato in UNA sola occorrenza (altrimenti uscita 1: la controprova non proverebbe niente); stampa il guard.py
  local d="$T/mutanti/$1"
  mkdir -p "$d" && cp -r "$MAAT/." "$d/" || return 1
  if [ -n "$2" ]; then
    "$FIC_PY" -c 'import sys
s = open(sys.argv[1], encoding="utf-8").read()
if s.count(sys.argv[2]) != 1:
    sys.exit(1)
open(sys.argv[1], "w", encoding="utf-8", newline="\n").write(s.replace(sys.argv[2], sys.argv[3]))' "$d/scripts/guard.py" "$2" "$3" || return 1
  fi
  printf '%s' "$d/scripts/guard.py"
}
controprova_maiuscole() { # <nome> <regex che deve comparire fra i FAIL, vuota = nessun FAIL atteso> <testo> <nuovo>
  local g out
  n=$((n + 1))
  g=$(gmutante "$1" "$3" "$4") || { fail=$((fail + 1)); echo "FAIL: controprova $1 non applicabile (copia o mutazione)"; return; }
  out=$(GUARD=$g; casi_maiuscole)   # in una subshell: i FAIL della copia non contano qui
  if [ -z "$2" ]; then
    [ -z "$(grep '^FAIL' <<< "$out")" ] || { fail=$((fail + 1)); echo "FAIL: controprova $1: la copia senza mutazioni non e' verde"; printf '%s\n' "$out" | sed 's/^/    /'; }
  else
    grep -Eq "$2" <<< "$out" || { fail=$((fail + 1)); echo "FAIL: controprova $1: nessun caso rosso come atteso ($2)"; printf '%s\n' "$out" | sed 's/^/    /'; }
  fi
}
if [ "$GOS" = posix ]; then
  casi_maiuscole
  controprova_maiuscole nulla "" "" ""
  controprova_maiuscole piega-mai '^FAIL .*repo=/mnt/c/fic-guard-maiuscole/Repo percorso=/mnt/c/fic-guard-maiuscole/repo/x\.txt' \
    '    return not WIN_PATHS and (sys.platform == "darwin" or bool(re.match(r"^/mnt/[a-zA-Z](/|$)", r)))' '    return False'
  controprova_maiuscole piega-mai-mac '^FAIL .*darwin.*repo=/Users/u/Repo percorso=/Users/u/repo/x\.txt' \
    '    return not WIN_PATHS and (sys.platform == "darwin" or bool(re.match(r"^/mnt/[a-zA-Z](/|$)", r)))' '    return False'
  controprova_maiuscole rel-piegato '^FAIL \(atteso 2, ottenuto 0\) \[maiuscole, implement a\.txt .*repo=/mnt/c/fic-guard-maiuscole/Repo percorso=/mnt/c/fic-guard-maiuscole/repo/A\.TXT$' \
    $'        return p[len(r) + 1:]\n    return p' $'        return pl[len(rl) + 1:]\n    return p'
else
  echo "SALTATO [maiuscole fuori da Windows]: Python di Windows, il confronto piega gia' sempre (casi di equivalenza)"
fi

echo "guard.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
