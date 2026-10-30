#!/usr/bin/env bash
# senza-wsl.test.sh — Windows without WSL (pk08, block A: D5, R8, A10). Everything runs with a reduced PATH: no wsl and no
# wsl.exe (on Windows System32 goes too, where it lives; FIC_PYTHON keeps the same interpreter), on synthetic projects in
# a temporary directory, with `ambiente: nativo` modules except where the case wants a wsl module:
#   1. maat-doctor.sh, copia_wsl auto -> exit 0 with «WSL assente» (Windows only: elsewhere «piattaforma non Windows»);
#   2. gates.sh, an `ambiente: wsl` module without WSL -> its gates BLOCKED with the reason, never PASS; the native module
#      next to it runs. Counterproof: without the rule (gates.sh mutant) the wsl module checks exit FAIL;
#   3. run_cp of run-phase.sh on a native module (the approach of cases 7a/7b of run-phase.test.sh, a fake wsl that
#      records): counterproof.sh directly, wsl never called. Counterproof: `wsl` hard-wired in run_cp (mutant of
#      run-phase.sh) -> the fake wsl is called, red;
#   4. watch-phase.sh without wsl (its counterproof, fixed `wsl`, is in phase-events.test.sh).
# On Linux everything runs (there is no wsl); only the doctor's «WSL assente» line is Windows-specific: SALTATO with the reason.
#   bash plugins/maat/scripts/senza-wsl.test.sh          (Git Bash or Linux)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
. "$HERE/python.sh" || true
[ -n "${FIC_PY:-}" ] || { echo "senza-wsl.test.sh: nessun Python utilizzabile" >&2; exit 2; }
unset MAAT_CONFIG FIC_REPO PROJECT_ROOT MAAT_ROOT CLAUDE_BIN FIC_PHASE FIC_GATES_VENV_PY FIC_GATES_WSL FIC_SESSION_GUARD \
  CLAUDE_PROJECT_DIR FIC_CP_CMD FIC_COUNTERPROOF PLAN_CHECK_ROOT FIC_LOCK FIC_GATES FIC_FINALIZE
export FIC_PYTHON=$FIC_PY PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8
pass=0 fail=0
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; tail -20 "$T/out" 2>/dev/null | sed 's/^/    /'; fi; }
WIN=0; case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*) WIN=1 ;; esac
PATH=$(out=""; IFS=:; for d in $PATH; do { [ -e "$d/wsl.exe" ] || [ -e "$d/wsl" ]; } && continue; out+="${out:+:}$d"; done; printf '%s' "$out")
export PATH
: > "$T/out"
check "premessa: wsl e wsl.exe fuori dal PATH" '! command -v wsl >/dev/null 2>&1 && ! command -v wsl.exe >/dev/null 2>&1'
repo() { (cd "$1" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  git add -A && git commit -qm init) || { echo "repo sintetico non creato: $1" >&2; exit 2; }; }

# --- 1. maat-doctor.sh: native modules, copia_wsl auto -------------------------------------------------------------------
mkdir -p "$T/bin" "$T/home/.claude"
printf '#!/bin/sh\necho "2.1.285 (Claude Code)"\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
P=$T/p; mkdir -p "$P/.claude/.ai-workflow"
cat > "$P/.claude/maat.json" <<'EOF'
{"versione_schema": 1, "piattaforma": {"copia_wsl": "auto"},
 "moduli": [{"nome": "m", "radice": ".", "ambiente": "nativo", "comandi": {"test": "bash run-test.sh {test}"},
             "controlli": [{"glob": "**/*.sh", "comando": "bash -n {file}"}]}],
 "guardia": {"produzione": ["prod[.]esempio[.]it"], "sonde": ["prod.esempio.it"]}}
EOF
echo '{"enabledPlugins": {"maat@prova": true}}' > "$P/.claude/settings.json"
printf '#!/bin/sh\nexit 0\n' > "$P/run-test.sh"
repo "$P"
(cd "$P" && env HOME="$T/home" USERPROFILE="$T/home" PATH="$T/bin:$PATH" bash "$HERE/maat-doctor.sh") > "$T/out" 2>&1; rc=$?
if [ "$WIN" = 1 ]; then
  check "doctor senza WSL, moduli nativi, copia_wsl auto -> exit 0, nessun MANCA, «WSL assente»" '[ "$rc" = 0 ] && ! grep -q "^MANCA" "$T/out" && grep -q "^OK WSL assente: copia veloce dei test non disponibile (wsl\.exe fuori dal PATH)" "$T/out"'
else
  echo "SALTATO [doctor «WSL assente»]: la piattaforma non è Windows (uname/OSTYPE): il doctor non cerca WSL"
  check "doctor fuori da Windows, moduli nativi -> exit 0, «WSL non serve»" '[ "$rc" = 0 ] && ! grep -q "^MANCA" "$T/out" && grep -q "^OK piattaforma non Windows: WSL non serve" "$T/out"'
fi

# --- 2. gates.sh: wsl module without WSL -> BLOCKED with the reason; the native module runs ----------------------------------
G=$T/g; mkdir -p "$G/.claude" "$G/n" "$G/w"
cat > "$G/.claude/maat.json" <<'EOF'
{"versione_schema": 1,
 "moduli": [{"nome": "n", "radice": "n", "ambiente": "nativo", "controlli": [{"glob": "**/*.sh", "comando": "bash -n {file}"}]},
            {"nome": "w", "radice": "w", "ambiente": "wsl", "controlli": [{"glob": "**/*.sh", "comando": "bash -n {file}"}]}]}
EOF
printf 'echo n\n' > "$G/n/a.sh"; printf 'echo w\n' > "$G/w/b.sh"
repo "$G"
gates() { (cd "$G" && MAAT_ROOT=$PLUGIN bash "$1" --run-dir "$T/$2.run" std n/a.sh w/b.sh) > "$T/out" 2>&1; }
gates "$HERE/gates.sh" g1; rc=$?
check "gates: modulo wsl senza WSL -> controlli BLOCKED con il motivo, esito BLOCKED (exit 3), mai PASS" '[ "$rc" = 3 ] && grep -q "^controlli-w: BLOCKED (eseguito) — WSL assente (wsl\.exe fuori dal PATH): il modulo w ha ambiente wsl" "$T/out" && ! grep -q "^[a-z-]*-w: PASS" "$T/out" && grep -q "^gates: esito=BLOCKED " "$T/out"'
check "  il modulo nativo accanto gira senza WSL (controlli-n PASS)" 'grep -q "^controlli-n: PASS (eseguito)" "$T/out"'
mkdir -p "$T/gm/lib"; cp "$HERE/lib/maat-paths.sh" "$T/gm/lib/"
sed 's/^if \[ -z "\${FIC_GATES_WSL:-}" \] && ! command -v wsl /if false \&\& ! command -v wsl /' "$HERE/gates.sh" > "$T/gm/gates.sh"
if cmp -s "$HERE/gates.sh" "$T/gm/gates.sh"; then fail=$((fail + 1)); echo "FAIL: controprova gates: la mutazione non si applica"
else
  gates "$T/gm/gates.sh" g2
  check "controprova: senza la regola i controlli del modulo wsl sono FAIL, non BLOCKED (il caso sopra sarebbe rosso)" 'grep -q "^controlli-w: FAIL" "$T/out" && ! grep -q "WSL assente" "$T/out"'
fi

# --- 3. run_cp of run-phase.sh: native module, counterproof.sh directly, never wsl -----------------------------------------
# As in run-phase.test.sh (cases 7a/7b): fake claude, gates.sh and finalize.sh, lock in a temporary directory, the plan
# in format 2 with a mutation and its list written by `plan-check.sh gen` (driver counterproofs), fake counterproof.sh
# (FIC_COUNTERPROOF) and a fake wsl in the PATH that records and exits 127.
export FIC_LOCK="$T/lock" FIC_REPO="$T/repo"
mkdir -p "$FIC_REPO/modules/api/app" "$FIC_REPO/modules/api/tests"; printf 'uno\n' > "$FIC_REPO/a.py"; repo "$FIC_REPO"
cat > "$T/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"result","result":"ESITO FASE review: OK — finto","structured_output":{"fase":"'"$FIC_PHASE"'","esito":"OK","motivo":"finto","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[],"copertura":[{"requisito":"RF1","test":["modules/api/tests/test_a.py::test_a"]}]}}'
EOF
printf '#!/usr/bin/env bash\necho "gates: esito=PASS chiave=k0 evidence=-"\n' > "$T/gates"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/fin"
cat > "$T/cp-diretto" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s\nPROJECT_ROOT=%s\n' "$*" "${PROJECT_ROOT:-}" > "$CPD"
printf '{"id":"T1","esito":"rosso_asserzione"}\n' > "$(dirname "$1")/T1.json"
exit 0
EOF
WB="$T/wslbin"; mkdir -p "$WB"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$FAKE_WSL_LOG"\nexit 127\n' > "$WB/wsl"
chmod +x "$T/claude" "$T/gates" "$T/fin" "$T/cp-diretto" "$WB/wsl"
printf '{"versione_schema": 1, "moduli": [{"nome": "be", "radice": "modules/api", "ambiente": "nativo", "report": "junit"}]}\n' > "$T/cfg-nativo.json"
echo "/full-implementation-cycle --worker=probe x" > "$T/prompt.md"
W3="$T/w3"; SPP="$W3/spec-p.md"; R3="$W3/spec-p.run"; mkdir -p "$R3"; echo a.py > "$R3/touched.txt"
printf '%s\n' "# P" "## Requisiti funzionali" "1. RF1 — A." "## Piano di implementazione" "Plan format: 2" \
  "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" "### File toccati" '- `a.py`' "### Passi" \
  "#### Blocco B1 — tutto" 'scrive: `a.py`' "dopo: nessuno" "" "| id | file | modifica | test |" "|---|---|---|---|" \
  '| P1 | `a.py` | uno | T1 |' "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" "|---|---|---|" \
  "| RF1 | P1 | T1 |" "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
  '| T1 | RF1 | `modules/api/tests/test_a.py::test_a` (nuovo) | rosso se: A | `modules/api/app/a.py` · `f` · `return 1` → `return 2` · rosso se: `assert 2 == 1` |' > "$SPP"
export PLAN_CHECK_ROOT="$FIC_REPO" MAAT_CONFIG="$T/cfg-nativo.json"
bash "$HERE/plan-check.sh" gen "$SPP" > "$T/out" 2>&1
check "  (fixture: gen ha scritto procedura.txt e mutations.json)" '[ -f "$R3/gen/procedura.txt" ] && grep -q "\"id\": \"T1\"" "$R3/counterproof/mutations.json"'
cprun() { # <run-phase.sh> <label>: driver counterproofs without FIC_CP_CMD, fake wsl in the PATH. A mutant is another
  # plugin: its fingerprint is confirmed before the launch and the real plugin's is confirmed again after (run-phase.test.sh)
  rm -f "$T/wsl.log"
  [ "$1" = "$HERE/run-phase.sh" ] || bash "$1" --harness-fp "$FIC_REPO" > "$R3/harness.fp"
  CPD="$T/$2.cpd" FAKE_WSL_LOG="$T/wsl.log" PATH="$WB:$PATH" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" FIC_FINALIZE="$T/fin" \
    FIC_COUNTERPROOF="$T/cp-diretto" bash "$1" "$R3" "$2" "$T/prompt.md" > "$T/out" 2>&1 </dev/null
  [ "$1" = "$HERE/run-phase.sh" ] || bash "$HERE/run-phase.sh" --harness-fp "$FIC_REPO" > "$R3/harness.fp"
}
cprun "$HERE/run-phase.sh" s1-review
check "run_cp, modulo nativo senza WSL: counterproof.sh diretto con PROJECT_ROOT, wsl mai chiamato" 'grep -q "^modo=parallelo controprove=driver" "$R3/log/s1-review.parallelo" && grep -q "^args=.*counterproof/mutations.json$" "$T/s1-review.cpd" && grep -qxF "PROJECT_ROOT=$FIC_REPO" "$T/s1-review.cpd" && grep -qx "exit=0" "$R3/log/s1-review.counterproof" && [ ! -f "$T/wsl.log" ]'
HC="$T/hc"; mkdir -p "$HC"; cp -r "$HERE" "$HC/scripts"; cp -r "$PLUGIN/schemas" "$PLUGIN/.claude-plugin" "$HC/"
find "$HC" -name __pycache__ -type d -prune -exec rm -rf {} +
sed 's/^  elif cp_in_wsl; then$/  elif true; then   # MUTANTE: wsl cablato/' "$HERE/run-phase.sh" > "$HC/scripts/run-phase.sh"
if cmp -s "$HERE/run-phase.sh" "$HC/scripts/run-phase.sh"; then fail=$((fail + 1)); echo "FAIL: controprova run_cp: la mutazione non si applica"
else
  cprun "$HC/scripts/run-phase.sh" s2-review
  check "controprova: wsl cablato in run_cp -> il modulo nativo passa da wsl (il caso sopra sarebbe rosso)" '[ -f "$T/wsl.log" ] && [ ! -f "$T/s2-review.cpd" ] && grep -qx "exit=127" "$R3/log/s2-review.counterproof"'
fi

# --- 4. watch-phase.sh without wsl -----------------------------------------------------------------------------------------
RD="$T/run con spazi"; mkdir -p "$RD/log"
{ printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"text","text":"▶ lavoro"}]}}'
  printf '%s\n' '{"type":"result","is_error":false,"result":"ESITO FASE 1: OK","duration_ms":1000,"num_turns":1}'; } > "$RD/log/f.jsonl"
echo 0 > "$RD/log/f.exit"
timeout 20 bash "$HERE/watch-phase.sh" "$RD" f > "$T/out" 2>&1; rc=$?
check "watch-phase senza wsl, run dir con spazi -> la riga di fine, exit 0" '[ "$rc" = 0 ] && tail -1 "$T/out" | grep -q "^■ ESITO FASE 1: OK"'

echo "senza-wsl.test.sh: $pass ok, $fail falliti"
[ "$fail" = 0 ]
