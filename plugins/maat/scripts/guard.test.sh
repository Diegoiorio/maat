#!/usr/bin/env bash
# guard.test.sh — deterministic tests of guard.py (core + project rules) and of guard-hook.sh (the plugin hook).
#   bash scripts/guard.test.sh
# Each case: the JSON Claude would pass to the hook, the expected outcome (0 allowed, ask asks, 2 denied).
#   1. equivalence on the nuxt-fastapi example: the cases from before the split (fixture tests/guard-esempio.cases) with
#      examples/nuxt-fastapi.maat.json → same decision and same level;
#   2. guard-hook.sh (the cases of the former .claude/settings.json hook, rewritten; without Python: ask on everything);
#   3. core alone, maat.json missing or invalid, project root, MAAT_CONFIG;
#   4. plugin wrappers (step 3-bis); 5. DENY list; 6. three-part reasons, language, reminder in the skills (R11).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# C:/… form where cygpath exists (Git Bash), otherwise the path as is (Linux, pk08)
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
. "$HERE/python.sh" || { echo "interprete Python non trovato" >&2; exit 1; }
REPO=$(cd "$HERE/../../.." && { pwd -W 2>/dev/null || pwd; })
MAAT=$(cd "$HERE/.." && { pwd -W 2>/dev/null || pwd; })
# an absolute folder OUTSIDE the repo (scratchpad) for the fixture: the former form on Windows, POSIX elsewhere (pk08)
case $REPO in [A-Za-z]:/*) SCRATCH=C:/Temp/claude/scratch ;; *) SCRATCH=/tmp/claude/scratch ;; esac
# MAIN tree (not a linked worktree, where git commit/checkout/add are allowed): cwd of the cases that
# expect a confirmation or a denial on those commands. From the main tree it is REPO itself.
MAINTREE=$(dirname "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)")
fail=0 n=0
unset FIC_SESSION_GUARD MAAT_CONFIG CLAUDE_PROJECT_DIR MAAT_ROOT FIC_PHASE   # never inherited: each section chooses them
export PYTHONDONTWRITEBYTECODE=1
SSJ=$(nat "$MAAT/examples/nuxt-fastapi.maat.json")

# Temporary repo with a LINKED worktree: MAIN has git-dir == git-common-dir, WT does not.
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
git init -q "$T/main" && (cd "$T/main" && git config user.email t@t && git config user.name t && echo a > a && git add a 2>/dev/null && git commit -qm init && git worktree add -q "$T/wt" -b wt) || { echo "setup del repo temporaneo fallito" >&2; exit 1; }
MAIN=$(cd "$T/main" && { pwd -W 2>/dev/null || pwd; }) WT=$(cd "$T/wt" && { pwd -W 2>/dev/null || pwd; })

run() { # $1 expected, $2 phase, $3 JSON
  n=$((n + 1))
  local got
  printf '%s' "$3" | FIC_PHASE="$2" FIC_REPO="$REPO" "$FIC_PY" "$HERE/guard.py" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$1" ]; then fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [$2] $3"; fi
}
bash_cmd() { # JSON of a Bash tool with the command $1
  "$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$REPO"
}
write_path() { # $1 tool, $2 path
  "$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2]},"cwd":sys.argv[3]}))' "$1" "$2" "$REPO"
}
deny()  { run 2 "${2:-implement}" "$(bash_cmd "$1")"; }
allow() { run 0 "${2:-implement}" "$(bash_cmd "$1")"; }
# implementation lane (harness-pt13)
srun() { # $1 expected, $2 FIC_WRITE_SCOPE, $3 JSON
  n=$((n + 1))
  local got
  printf '%s' "$3" | FIC_PHASE=implement FIC_LANE=1 FIC_WRITE_SCOPE="$2" FIC_REPO="$REPO" "$FIC_PY" "$HERE/guard.py" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$1" ]; then fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [scope=$2] $3"; fi
}
# working folder from cartelle.lavoro (pk04a-1): the RL project has its own maat.json, and run-phase.sh exports
# MAAT_CONFIG with the project's one
RL="$T/lavoro conf"; mkdir -p "$RL/.claude"
printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}], "cartelle": {"lavoro": "lavoro/cicli"}}\n' > "$RL/.claude/maat.json"
RLW=$(cd "$RL" && { pwd -W 2>/dev/null || pwd; })
lrun() { # $1 expected, $2 phase, $3 path relative to the project, [$4 FIC_WRITE_SCOPE]
  n=$((n + 1)); local got
  "$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]},"cwd":sys.argv[2]}))' "$3" "$RLW" |
    MAAT_CONFIG="$RLW/.claude/maat.json" FIC_PHASE="$2" FIC_LANE=1 FIC_WRITE_SCOPE="${4:-}" FIC_REPO="$RLW" "$FIC_PY" "$HERE/guard.py" >/dev/null 2>&1; got=$?
  [ "$got" = "$1" ] || { fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [cartelle.lavoro, $2 ${4:-}] $3"; }
}
ujson() { # $1 command, $2 cwd, $3 tool (default Bash)
  "$FIC_PY" -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[3],"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2" "${3:-Bash}"
}
# hook outcome: 0 = allowed (no output) · ask = asks for confirmation (JSON on stdout, exit 0) · 2 = denied
verdict() { # $1 exit, $2 stdout
  if [ "$1" = 0 ] && [ -z "$2" ]; then echo 0
  elif [ "$1" = 0 ] && printf '%s' "$2" | grep -Eq '"permissionDecision": ?"ask"'; then echo ask
  else echo "exit=$1:$2"; fi
}
urun() { # $1 expected (0|ask|2), $2 cwd, $3 command, $4 tool, $5 FIC_PHASE (empty = main session)
  n=$((n + 1))
  local out rc got
  out=$(ujson "$3" "$2" "${4:-Bash}" | env -u FIC_REPO FIC_PHASE="${5:-}" "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null); rc=$?
  got=$(verdict "$rc" "$out"); [ "$rc" = 2 ] && got=2
  if [ "$got" != "$1" ]; then fail=$((fail + 1)); echo "FAIL (atteso $1, ottenuto $got) [universal ${4:-Bash} fase=${5:-} cwd $2 config=${MAAT_CONFIG:-}] $3"; fi
}
udeny()  { urun ask "${2:-$REPO}" "$1" "${3:-Bash}"; }   # main session: asks for confirmation
uallow() { urun 0 "${2:-$REPO}" "$1" "${3:-Bash}"; }
pdeny()  { urun 2 "${2:-$REPO}" "$1" "${3:-Bash}" implement; }   # sub-session: denies
# the reason of the ask response (stdin: the hook's stdout)
motivo() { "$FIC_PY" -c 'import json,sys
sys.stdout.reconfigure(encoding="utf-8"); sys.stdin.reconfigure(encoding="utf-8")
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])
except Exception: print("")'; }

# ================================================================ 1. equivalence on the nuxt-fastapi example
export MAAT_CONFIG="$SSJ"
n0=$n f0=$fail
. "$MAAT/tests/guard-esempio.cases"
unset MAAT_CONFIG FIC_SESSION_GUARD
echo "equivalenza nuxt-fastapi: $((n - n0 - fail + f0))/$((n - n0)) casi uguali a prima"
# falsifiable: run_tests.sh is a suite only because guardia.suite declares it (it is not hard-wired in the core)
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1],encoding="utf-8")); del c["guardia"]["suite"]; json.dump(c,open(sys.argv[2],"w",encoding="utf-8"))' "$SSJ" "$T/senza-suite.json"
export MAAT_CONFIG=$(nat "$T/senza-suite.json")
allow "cd modules/api && ./run_tests.sh" plan
deny  "cd modules/api && .venv/Scripts/python.exe -m pytest tests" plan
unset MAAT_CONFIG
# release run directly from its folder (review pk05, blocker 1): severe as before the split
export MAAT_CONFIG="$SSJ"
udeny "cd script && ./deploy-production.sh deploy"
FIC_SESSION_GUARD=prod udeny "cd script && ./deploy-production.sh deploy"
pdeny "cd script && ./deploy-production.sh deploy"
deny  "cd script && ./deploy-production.sh deploy"
# falsifiable: without deploy-production in guardia.produzione the same command passes
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1],encoding="utf-8")); c["guardia"]["produzione"].remove("deploy-production"); json.dump(c,open(sys.argv[2],"w",encoding="utf-8"))' "$SSJ" "$T/senza-deploy.json"
export MAAT_CONFIG=$(nat "$T/senza-deploy.json")
uallow "cd script && ./deploy-production.sh deploy"
unset MAAT_CONFIG

# ================================================================ 2. plugin hook: guard-hook.sh
# Test project with the nuxt-fastapi example as .claude/maat.json; CLAUDE_PROJECT_DIR arrives in Windows form.
SS="$T/progetto ss"; mkdir -p "$SS/.claude" "$SS/sotto/cartella"; cp "$MAAT/examples/nuxt-fastapi.maat.json" "$SS/.claude/maat.json"
SSW=$(cd "$SS" && { pwd -W 2>/dev/null || pwd; })
case $SSW in [A-Za-z]:/*) PDIR=$(printf '%s' "$SSW" | tr '/' '\\') ;; *) PDIR=$SSW ;; esac   # on Linux it stays native
HOOKJ=$("$FIC_PY" -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$MAAT/hooks/hooks.json")
n=$((n + 1))
[ "$HOOKJ" = 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard-hook.sh"' ] || { fail=$((fail + 1)); echo "FAIL: hooks.json non lancia guard-hook.sh ($HOOKJ)"; }
hout() { # $1 command, $2 FIC_PYTHON, $3 tool, $4 FIC_PHASE, $5 cwd · stdout of the hook, rc in HRC
  ujson "$1" "${5:-$REPO}" "${3:-Bash}" | env -u MAAT_CONFIG CLAUDE_PROJECT_DIR="$PDIR" FIC_PYTHON="${2:-}" FIC_PHASE="${4:-}" bash "$HERE/guard-hook.sh" 2>/dev/null
}
hrun() { # $1 expected (0|ask|2), $2 command, $3 FIC_PYTHON (empty = the one found), $4 tool, $5 FIC_PHASE, $6 cwd
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
# the review worker launches the counterproofs: the session hook must not deny them
hrun 0   "wsl -- bash -lc 'bash $WREPO/script/test/counterproof.sh $WREPO/.claude/.ai-workflow/spec-x.run/counterproof/mutations.json'" "" Bash review
# without Python: never fail-open — ask on EVERY command in the session, exit 2 in a sub-session
NOPY="$T/non-esiste.exe"
hrun ask "curl -s https://app.example.com/health" "$NOPY"
hrun ask "git push" "$NOPY"
hrun ask "docker ps" "$NOPY"
hrun ask "docker compose up" "$NOPY" PowerShell
hrun ask "ls -la" "$NOPY"                 # before: 0 (regex fallback); now ask, intended (pk05)
hrun ask "git status --short" "$NOPY"     # before: 0; now ask, intended (pk05)
hrun 2   "git push" "$NOPY" Bash implement
hrun 2   "ls" "$NOPY" Bash implement
n=$((n + 1))
hout "git push" "$NOPY" | "$FIC_PY" -c 'import json,sys; h=json.load(sys.stdin)["hookSpecificOutput"]; sys.exit(0 if h["hookEventName"]=="PreToolUse" and h["permissionDecision"]=="ask" and h["permissionDecisionReason"].startswith("Python non trovato: guardia non disponibile") else 1)' \
  || { fail=$((fail + 1)); echo "FAIL: formato JSON della risposta ask senza Python"; }
# guard.py crashing (exit other than 0/2): asks for confirmation, or denies in a sub-session — never fail-open
printf '#!/usr/bin/env bash\n[ "${1:-}" = -c ] && exit 0\ncat >/dev/null; exit 1\n' > "$T/py-rotto"; chmod +x "$T/py-rotto"
hrun ask "ls -la" "$T/py-rotto"
hrun 2   "ls -la" "$T/py-rotto" Bash implement
n=$((n + 1))
m=$(hout "ls -la" "$T/py-rotto" | motivo)
case $m in "guardia in errore (uscita 1)"*) ;; *) fail=$((fail + 1)); echo "FAIL: motivo di py-rotto: $m" ;; esac
# in a sub-session the plugin hook calls --universal with no early exits: it reads the content of bash <script>
# (counterproof: an early exit «exit 0 se FIC_PHASE» turns it into 0)
mkdir -p "$T/main/script"
printf '#!/usr/bin/env bash\nssh -i k root@prod.example.internal true\n' > "$T/main/script/h-prod.sh"
hrun 2   "bash script/h-prod.sh" "" Bash implement "$MAIN"
hrun ask "bash script/h-prod.sh" "" Bash "" "$MAIN"
# project root: CLAUDE_PROJECT_DIR, not the command's cwd (a subfolder without maat.json)
hrun ask "curl -s https://www.example.org/" "" Bash "" "$SSW/sotto/cartella"
n=$((n + 1))
m=$(hout "curl -s https://www.example.org/" "" Bash "" "$SSW/sotto/cartella" | motivo)
case $m in *"guardia.produzione"*) case $m in *"maat.json non"*) fail=$((fail + 1)); echo "FAIL: radice dalla cwd: $m" ;; esac ;;
  *) fail=$((fail + 1)); echo "FAIL: radice del progetto: il motivo non e' quello della produzione: $m" ;; esac
# sub-session: MAAT_CONFIG set and CLAUDE_PROJECT_DIR missing → the project rules apply
n=$((n + 1))
o=$(ujson "curl -s https://www.example.org/" "$REPO" | env -u CLAUDE_PROJECT_DIR MAAT_CONFIG="$SSW/.claude/maat.json" bash "$HERE/guard-hook.sh" 2>/dev/null | motivo)
case $o in *"guardia.produzione"*) ;; *) fail=$((fail + 1)); echo "FAIL: MAAT_CONFIG senza CLAUDE_PROJECT_DIR: $o" ;; esac
n=$((n + 1))
ujson "bash script/dev/dev-sql.sh --apply x" "$REPO" | env -u CLAUDE_PROJECT_DIR MAAT_CONFIG="$SSW/.claude/maat.json" FIC_PHASE=implement bash "$HERE/guard-hook.sh" >/dev/null 2>&1
[ $? = 2 ] || { fail=$((fail + 1)); echo "FAIL: MAAT_CONFIG in sotto-sessione: dev-sql.sh --apply non negato"; }
# reduced guard through the hook
export FIC_SESSION_GUARD=prod
hrun ask "git push"
hrun 0   "npm install"
hrun 2   "npm install" "" Bash implement
unset FIC_SESSION_GUARD

# ================================================================ 3. core, maat.json missing or invalid
MIN="$T/min"; mkdir -p "$MIN"; printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}]}\n' > "$MIN/maat.json"
printf '{"versione_schema": 1}\n' > "$T/rotta.json"            # moduli missing: invalid
printf '{"versione_schema": 1, "moduli": [\n' > "$T/troncata.json"   # unreadable JSON
export MAAT_CONFIG; MAAT_CONFIG=$(nat "$MIN/maat.json")   # valid, no guardia section: core only
udeny  "git push --force origin x"
udeny  "ssh host"
udeny  "npm install"
uallow "ls"
uallow "curl https://esempio.it"
unset MAAT_CONFIG                                                # missing: no source
udeny  "curl https://esempio.it"
uallow "ls"
pdeny  "curl https://esempio.it"
n=$((n + 1))
m=$(ujson "curl https://esempio.it" "$REPO" | "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)
case $m in *"maat.json not found"*|*"maat.json non trovato"*) ;; *) fail=$((fail + 1)); echo "FAIL: maat.json assente, motivo: $m" ;; esac
n=$((n + 1))   # CLAUDE_PROJECT_DIR pointing to a project without the file: same fallback
m=$(ujson "curl https://esempio.it" "$REPO" | CLAUDE_PROJECT_DIR="$(nat "$T/main")" "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)
case $m in *"maat.json not found"*|*"maat.json non trovato"*) ;; *) fail=$((fail + 1)); echo "FAIL: progetto senza maat.json, motivo: $m" ;; esac
for f in rotta troncata; do
  MAAT_CONFIG=$(nat "$T/$f.json") udeny "curl https://esempio.it"
  n=$((n + 1))
  m=$(ujson "curl https://esempio.it" "$REPO" | MAAT_CONFIG=$(nat "$T/$f.json") "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)
  case $m in *"invalid maat.json"*|*"maat.json non valido"*) ;; *) fail=$((fail + 1)); echo "FAIL: maat.json $f, motivo: $m" ;; esac
  MAAT_CONFIG=$(nat "$T/$f.json") uallow "ls"
  MAAT_CONFIG=$(nat "$T/$f.json") udeny "git push"      # the core remains
done
# reduced guard: with an invalid maat.json a host stays severe
export FIC_SESSION_GUARD=prod
MAAT_CONFIG=$(nat "$T/rotta.json") udeny "curl https://esempio.it"
MAAT_CONFIG=$(nat "$T/rotta.json") uallow "npm install"
unset FIC_SESSION_GUARD

# ================================================================ 4. plugin wrappers (step 3-bis)
# A fake plugin under .claude/plugins, with a space; MAAT_ROOT in C:/… form, the command in /mnt/<drive>/… form
PF="$T/home/.claude/plugins/maat prova"; mkdir -p "$PF/scripts"
printf '#!/usr/bin/env bash\nrsync -a a/ b/\n' > "$PF/scripts/test-fast.sh"
printf '#!/usr/bin/env bash\nssh root@h true\n' > "$PF/scripts/altro.sh"
PFW=$(cd "$PF" && { pwd -W 2>/dev/null || pwd; }); PFM=$(printf '%s' "$PFW" | sed 's#^\(.\):#/mnt/\L\1#')
export MAAT_CONFIG="$SSJ"
MAAT_ROOT="$PFW" uallow "wsl -- bash -lc 'bash \"$PFM/scripts/test-fast.sh\" x.test.ts'"
MAAT_ROOT="$PFW" uallow "bash \"$PFW/scripts/test-fast.sh\" x.test.ts"
MAAT_ROOT="$PFW" udeny  "wsl -- bash -lc 'bash \"$PFM/scripts/altro.sh\" x'"         # not a wrapper: it is read
udeny "wsl -- bash -lc 'bash \"$PFM/scripts/test-fast.sh\" x.test.ts'"                # another plugin: it is read
unset MAAT_CONFIG

# ================================================================ 5. DENY list (--disallowedTools of run-phase.sh)
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
n=$((n + 1))   # falsifiable: without vietati_extra the rsync entries are missing
! grep -qF "rsync-once.sh" <<< "$DL2" || { fail=$((fail + 1)); echo "FAIL: le voci rsync non vengono da vietati_extra"; }
DL3=$(MAAT_CONFIG=$(nat "$MIN/maat.json") "$FIC_PY" "$HERE/guard.py" --deny-list | tr -d '\r')
n=$((n + 1))   # without guardia: core only
[ "$(grep -c . <<< "$DL3")" = 19 ] || { fail=$((fail + 1)); echo "FAIL: lista DENY del solo nucleo: $DL3"; }

# ================================================================ 6. R11: three-part reasons, language, reminder
tre() { # $1 description, $2 the reason (UTF-8)
  n=$((n + 1))
  printf '%s' "$2" | "$FIC_PY" -c 'import sys
sys.stdin.reconfigure(encoding="utf-8")
p = sys.stdin.read().split(" — ")
ok = len(p) == 3 and all(x.strip() for x in p) and p[1].startswith(("regola del nucleo", "regola del progetto", "core rule", "project rule"))
sys.exit(0 if ok else 1)' || { fail=$((fail + 1)); echo "FAIL: motivo non in tre parti [$1]: $2"; }
}
ask_di() { # $1 command, $2 cwd · the reason with the nuxt-fastapi example
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
# every table entry, in it and in en, has three parts; the second parts name the rule
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
# language: as declared (it, en); en (the default) with a language not in the table, an invalid or a missing maat.json
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1])); c["lingua"]=sys.argv[3]; json.dump(c,open(sys.argv[2],"w"))' "$MIN/maat.json" "$T/it.json" it
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1])); c["lingua"]=sys.argv[3]; json.dump(c,open(sys.argv[2],"w"))' "$MIN/maat.json" "$T/en.json" en
"$FIC_PY" -c 'import json,sys; c=json.load(open(sys.argv[1])); c["lingua"]=sys.argv[3]; json.dump(c,open(sys.argv[2],"w"))' "$MIN/maat.json" "$T/xx.json" xx
lingua() { # $1 expected (it|en), $2 file
  n=$((n + 1))
  local m; m=$(ujson "git push" "$REPO" | MAAT_CONFIG=$(nat "$2") "$FIC_PY" "$HERE/guard.py" --universal 2>/dev/null | motivo)
  case "$1:$m" in "it:"*" — regola del nucleo"*|"en:"*" — core rule"*) ;; *) fail=$((fail + 1)); echo "FAIL: lingua $1 con $2: $m" ;; esac
}
lingua it "$T/it.json"
lingua en "$T/en.json"
lingua en "$T/xx.json"
lingua en "$T/rotta.json"
lingua en "$T/non-esiste.json"
# reminder of the command-description rule in the 5 skills of the main session (R11.1)
n=$((n + 1))
[ -s "$MAAT/docs/descrizione-comandi.md" ] || { fail=$((fail + 1)); echo "FAIL: docs/descrizione-comandi.md assente"; }
for s in full-implementation-cycle plan-review-cycle plan-review-cycle-light implementation-review-cycle setup; do
  n=$((n + 1))
  grep -rqF 'scrivi `description` secondo `${CLAUDE_PLUGIN_ROOT}/docs/descrizione-comandi.md`' "$MAAT/skills/$s" \
    || { fail=$((fail + 1)); echo "FAIL: la skill $s non richiama docs/descrizione-comandi.md"; }
done

# 7. pk08 review: outside Windows the inside/outside-the-repo comparison (phases and lane) folds case on
#    /mnt/<letter>/ (drvfs) and on the Mac; not on native Linux (Repo and repo are two folders). The Mac is simulated ONLY here,
#    with sys.platform = "darwin" before running guard.py. The paths do not exist: only the comparison matters.
#    The folded form decides ONLY inside/outside the repo: the relative path for lane, FIC_SCOPE and working
#    folder keeps its case (review round 2): `A.TXT` does not match the lane `a.txt`, `.Claude/.AI-workflow/` is not
#    the working folder. Automatic counterproofs, on plugin copies: piega_repo always False -> /mnt and Mac
#    «inside the repo» cases red; rel folded too -> the `A.TXT` case red; copy without mutations -> all green.
GOS=$("$FIC_PY" -c 'import os, sys; print("win" if os.name == "nt" or sys.platform.startswith(("msys", "cygwin")) else "posix")')
GPLAT=$("$FIC_PY" -c 'import sys; print(sys.platform)')
GUARD="$HERE/guard.py"   # the counterproofs move it to a mutant copy
prun() { # $1 expected, $2 phase, $3 FIC_REPO, $4 path, [$5 FIC_WRITE_SCOPE], [$6 darwin], [$7 FIC_SCOPE]
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
  prun 2 plan "$DR" /mnt/c/fic-guard-maiuscole/repo/x.txt            # drvfs: different case, same repo -> denied
  prun 2 plan "$DR" /mnt/c/FIC-GUARD-MAIUSCOLE/REPO/sotto/x.txt
  prun 2 plan "$DR" "$DR/x.txt"
  prun 0 plan "$DR" /mnt/c/fic-guard-maiuscole/repo/.claude/.ai-workflow/spec-x.md   # working folder: allowed
  prun 2 plan "$DR" /mnt/c/fic-guard-maiuscole/repo/.Claude/.AI-workflow/spec-x.md   # different case: it is not
  prun 0 plan "$DR" /mnt/c/fic-guard-maiuscole/altro/x.txt          # outside the repo
  prun 2 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/b.txt a.txt # lane: outside `scrive:`
  prun 0 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/a.txt a.txt # lane: inside, repo with different case
  prun 2 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/A.TXT a.txt # lane with different case: denied
  prun 0 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/.claude/.ai-workflow/spec-x.run/f a.txt   # run dir
  prun 2 implement "$DR" /mnt/c/fic-guard-maiuscole/repo/.Claude/.AI-workflow/spec-x.run/f a.txt
  prun 0 test-red "$DR" /mnt/c/fic-guard-maiuscole/repo/sotto/t.txt "" "" "$SCM"   # FIC_SCOPE: inside
  prun 2 test-red "$DR" /mnt/c/fic-guard-maiuscole/repo/A.TXT "" "" "$SCM"         # FIC_SCOPE: different case
  prun 2 test-red "$DR" /mnt/c/fic-guard-maiuscole/repo/Sotto/t.txt "" "" "$SCM"
  if [ "$GPLAT" = darwin ]; then
    echo "SALTATO [maiuscole, Linux nativo]: il Python della guardia e' del Mac (sys.platform darwin), il confronto piega sempre"
  else
    prun 0 plan "$NR" /home/fic-guard-maiuscole/repo/x.txt            # native Linux: another folder
    prun 2 plan "$NR" "$NR/x.txt"
    prun 0 implement "$NR" /home/fic-guard-maiuscole/repo/b.txt a.txt
  fi
  prun 2 plan /Users/u/Repo /Users/u/repo/x.txt "" darwin             # simulated Mac: denied
  prun 2 implement /Users/u/Repo /Users/u/repo/b.txt a.txt darwin
  prun 0 implement /Users/u/Repo /Users/u/repo/a.txt a.txt darwin
  prun 2 implement /Users/u/Repo /Users/u/repo/A.TXT a.txt darwin
  prun 0 plan /Users/u/Repo /Users/u/altro/x.txt "" darwin
}
gmutante() { # <name> <text to replace, empty = no mutation> <new text>: plugin copy, guard.py
  # mutated in ONE occurrence only (otherwise exit 1: the counterproof would prove nothing); prints the guard.py
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
controprova_maiuscole() { # <name> <regex that must appear among the FAILs, empty = no FAIL expected> <text> <new>
  local g out
  n=$((n + 1))
  g=$(gmutante "$1" "$3" "$4") || { fail=$((fail + 1)); echo "FAIL: controprova $1 non applicabile (copia o mutazione)"; return; }
  out=$(GUARD=$g; casi_maiuscole)   # in a subshell: the copy's FAILs do not count here
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
