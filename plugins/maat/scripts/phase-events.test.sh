#!/usr/bin/env bash
# phase-events.test.sh — the end of the phase (■/✖) arrives only with the .exit file, not with the first `result`.
#   bash plugins/maat/scripts/phase-events.test.sh          (Git Bash o WSL)
#   PE=/path/variant.py bash .../phase-events.test.sh                      # counterproof on a mutation
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
PE=${PE:-$HERE/phase-events.py}
. "$HERE/python.sh"
[ -n "${FIC_PY:-}" ] || { echo "phase-events.test.sh: nessun Python utilizzabile" >&2; exit 2; }
export PYTHONIOENCODING=utf-8
pass=0 fail=0
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; sed 's/^/    /' "$T/out"; fi; }
ends() { grep -cE '^(■|✖)' "$T/out"; }   # phase end lines (alternation, not a class: multi-byte chars)

# log of a -p subsession with TWO turns: two `result` events, the second is the real outcome
L=$T/f.jsonl; X=$T/f.exit
{
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"text","text":"▶ primo turno"}]}}'
  printf '%s\n' '{"type":"result","is_error":false,"result":"ESITO FASE 1: intermedio","duration_ms":60000,"num_turns":3}'
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"text","text":"▶ secondo turno"}]}}'
  printf '%s\n' '{"type":"result","is_error":false,"result":"ESITO FASE 1: OK","duration_ms":120000,"num_turns":5}'
} > "$L"

# 1. two `result`, no .exit: progress yes, end no (the reader keeps waiting: timeout stops it)
timeout 6 "$FIC_PY" -u "$PE" "$L" "$X" > "$T/out" 2>&1; rc=$?
check "due result senza .exit -> nessuna riga di fine" '[ "$(ends)" = 0 ]'
check "  e il lettore non esce da solo (timeout)" '[ "$rc" = 124 ]'
check "  i due result sono righe di avanzamento" '[ "$(grep -c "turno concluso" "$T/out")" = 2 ]'
check "  nessun .result scritto prima della fine" '[ ! -e "$L.result" ]'

# 2. re-arm after .exit appears: a single end line, with the outcome of the LAST result
echo 0 > "$X"
timeout 20 "$FIC_PY" -u "$PE" "$L" "$X" > "$T/out" 2>&1; rc=$?
check "con .exit -> una riga di fine" '[ "$(ends)" = 1 ] && [ "$rc" = 0 ]'
check "  ed e' l'esito dell'ultimo result" 'grep -q "^■ ESITO FASE 1: OK" "$T/out"'
check "  il riarmo non ripete gli eventi gia' mostrati" '! grep -q "turno concluso" "$T/out"'
check "  .result scritto con la riga di fine" 'grep -q "^■ ESITO FASE 1: OK" "$L.result"'

# 3. same log, single read with .exit already present: one end line, after the two progress lines
L2=$T/g.jsonl; cp "$L" "$L2"
timeout 20 "$FIC_PY" -u "$PE" "$L2" "$X" > "$T/out" 2>&1; rc=$?
check "lettura unica con .exit -> una sola riga di fine, l'ultima" '[ "$(ends)" = 1 ] && [ "$rc" = 0 ] && tail -1 "$T/out" | grep -q "^■ ESITO FASE 1: OK"'

# 3b. 1.3.0: the English result line (the Italian one above is still read)
L5=$T/e.jsonl; printf '%s\n' '{"type":"result","is_error":false,"result":"work\nPHASE RESULT implement: OK — done","duration_ms":60000,"num_turns":2}' > "$L5"
echo 0 > "$T/e.exit"
timeout 20 "$FIC_PY" -u "$PE" "$L5" "$T/e.exit" > "$T/out" 2>&1; rc=$?
check "riga «PHASE RESULT … OK» -> la riga di fine la riporta" '[ "$rc" = 0 ] && [ "$(ends)" = 1 ] && tail -1 "$T/out" | grep -q "^■ PHASE RESULT implement: OK — done"'

# 4. .exit without any result: ✖ with no result, exit 1 (unchanged behaviour)
L3=$T/h.jsonl; head -1 "$L" > "$L3"; echo 1 > "$T/h.exit"
timeout 20 "$FIC_PY" -u "$PE" "$L3" "$T/h.exit" > "$T/out" 2>&1; rc=$?
check ".exit senza result -> ✖ senza risultato, exit 1" '[ "$rc" = 1 ] && [ "$(ends)" = 1 ] && grep -q "^✖ sottosessione terminata senza risultato (exit 1)" "$T/out"'

# 5. intermediate result and then a NON-zero exit (crash, interruption): the end is ✖, not ■
L4=$T/k.jsonl; head -2 "$L" > "$L4"; echo 1 > "$T/k.exit"
timeout 20 "$FIC_PY" -u "$PE" "$L4" "$T/k.exit" > "$T/out" 2>&1; rc=$?
check "result intermedio + .exit=1 -> ✖ (exit 1), nessun ■" '[ "$rc" = 1 ] && [ "$(ends)" = 1 ] && grep -q "^✖ sottosessione uscita con exit 1" "$T/out" && ! grep -q "^■" "$T/out"'

# 6. watch-phase.sh (pk08, D5): FIC_PY from python.sh and native paths, without WSL — PATH without wsl/wsl.exe (on Windows
#    System32 removed too: FIC_PYTHON keeps the same interpreter), run dir with spaces. Counterproof: hard-coded `wsl`
#    reintroduced in a mutant (as it was before pk08) => no end line, red.
PATH_SENZA_WSL=$(out=""; IFS=:; for d in $PATH; do { [ -e "$d/wsl.exe" ] || [ -e "$d/wsl" ]; } && continue; out+="${out:+:}$d"; done; printf '%s' "$out")
wp() { # <watch-phase.sh> <run dir>: one read with .exit already present
  mkdir -p "$2/log"; cp "$L" "$2/log/f.jsonl"; echo 0 > "$2/log/f.exit"
  PATH=$PATH_SENZA_WSL FIC_PYTHON=$FIC_PY timeout 20 bash "$1" "$2" f > "$T/out" 2>&1
}
wp "$HERE/watch-phase.sh" "$T/run con spazi"; rc=$?
check "watch-phase senza wsl nel PATH, run dir con spazi -> una riga di fine, exit 0" '[ "$rc" = 0 ] && [ "$(ends)" = 1 ] && tail -1 "$T/out" | grep -q "^■ ESITO FASE 1: OK"'
WM="$T/wp mut"; mkdir -p "$WM/lib"; cp "$HERE/python.sh" "$HERE/phase-events.py" "$WM/"
cp "$HERE/maat_msg.py" "$WM/"; cp "$HERE/lib/messages.tsv" "$HERE/lib/maat-msg.sh" "$WM/lib/"   # the catalog (1.4.0)
sed 's/then exec "\$FIC_PY" -u /then MSYS_NO_PATHCONV=1 exec wsl -- python3 -u /' "$HERE/watch-phase.sh" > "$WM/watch-phase.sh"
if cmp -s "$HERE/watch-phase.sh" "$WM/watch-phase.sh"; then fail=$((fail + 1)); echo "FAIL: controprova watch-phase: la mutazione non si applica"
else
  wp "$WM/watch-phase.sh" "$T/run mut"; rc=$?
  check "controprova: watch-phase con wsl fisso, senza wsl nel PATH -> nessuna riga di fine (il caso sopra sarebbe rosso)" '[ "$rc" != 0 ] && [ "$(ends)" = 0 ]'
fi

# 6b. 1.4.0: the WSL fallback (no Python here) passes MAAT_LINGUA of the caller, resolved (it|en), on the command
#     line of wsl (wsl.exe does not pass the environment); unset, nothing is forced (phase-events.py reads maat.json in
#     WSL). A fake python.sh without Python and a fake wsl that records its arguments. Counterproof: the env removed.
WF="$T/wp wsl"; mkdir -p "$WF/lib" "$WF/bin"; cp "$HERE/watch-phase.sh" "$HERE/phase-events.py" "$HERE/maat_msg.py" "$WF/"
cp "$HERE/lib/messages.tsv" "$HERE/lib/maat-msg.sh" "$WF/lib/"
printf '%s\n' 'FIC_PY=""; return 1' > "$WF/python.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" > "$WSL_ARGS"' > "$WF/bin/wsl"; chmod +x "$WF/bin/wsl"
wf() { # <watch-phase.sh> <MAAT_LINGUA or -unset>: the arguments given to wsl in $T/wsl.args
  rm -f "$T/wsl.args"; mkdir -p "$T/run wsl/log"
  if [ "$2" = -unset ]; then env -u MAAT_LINGUA WSL_ARGS="$T/wsl.args" PATH="$WF/bin:$PATH" bash "$1" "$T/run wsl" f > "$T/out" 2>&1
  else MAAT_LINGUA=$2 WSL_ARGS="$T/wsl.args" PATH="$WF/bin:$PATH" bash "$1" "$T/run wsl" f > "$T/out" 2>&1; fi
}
wf "$WF/watch-phase.sh" it
check "watch-phase, ripiego WSL: MAAT_LINGUA=it passata a wsl" 'grep -q "^-- env MAAT_LINGUA=it python3 -u .*phase-events.py " "$T/wsl.args"'
wf "$WF/watch-phase.sh" fr
check "  MAAT_LINGUA=fr: passata risolta (en)" 'grep -q "^-- env MAAT_LINGUA=en python3 -u " "$T/wsl.args"'
wf "$WF/watch-phase.sh" -unset
check "  MAAT_LINGUA assente: nessuna lingua forzata (la legge phase-events.py in WSL)" 'grep -q "^-- python3 -u " "$T/wsl.args"'
sed 's/^  lg=(); \[ -z .*$/  lg=()   # MUTANTE/' "$WF/watch-phase.sh" > "$WF/watch-phase.mut.sh"
if cmp -s "$WF/watch-phase.sh" "$WF/watch-phase.mut.sh"; then fail=$((fail + 1)); echo "FAIL: controprova 6b: la mutazione non si applica"
else
  wf "$WF/watch-phase.mut.sh" it
  check "controprova 6b: senza env la lingua non arriva a wsl (il primo caso sarebbe rosso)" '[ -f "$T/wsl.args" ] && ! grep -q "MAAT_LINGUA" "$T/wsl.args"'
fi

# 7. 1.4.0, English (MAAT_LINGUA=en): the words of the lines from the catalog; the ▶ lines, Decision: and the outcome
#    line are quoted as they are
LE=$T/en.jsonl
{
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"a1","name":"Agent","input":{"description":"rivede"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a1","content":"fatto"}]}}'
  printf '%s\n' '{"type":"result","is_error":false,"result":"lavoro senza riga finale","duration_ms":60000,"num_turns":3}'
} > "$LE"; echo 1 > "$T/en.exit"
MAAT_LINGUA=en timeout 20 "$FIC_PY" -u "$PE" "$LE" "$T/en.exit" 2>&1 | tr -d '\r' > "$T/out"; rc=${PIPESTATUS[0]}
check "en: avanzamento e fine in inglese, nessun italiano" '[ "$rc" = 1 ] && grep -qx "· launches agent: rivede" "$T/out" && grep -qx "← agent: rivede → done" "$T/out" && grep -q "^· turn finished: no PHASE RESULT line · 1.0 min · 3 turns" "$T/out" && grep -q "^✖ sub-session exited with exit 1 — last turn: phase finished (no PHASE RESULT line)" "$T/out" && ! grep -qE "lancia|agente|finito|turno|turni|sottosessione|nessuna riga" "$T/out"'
LE=$T/en2.jsonl   # another log: the reader resumes a log from its .pos and .pending
printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"text","text":"▶ inizio"}]}}' > "$LE"
MAAT_LINGUA=en timeout 20 "$FIC_PY" -u "$PE" "$LE" "$T/en.exit" > "$T/out" 2>&1; rc=$?
check "en: senza result -> ✖ in inglese (exit 1)" '[ "$rc" = 1 ] && grep -q "^✖ sub-session ended without a result (exit 1) — see en2.jsonl and .stderr" "$T/out"'
MAAT_LINGUA=en bash "$HERE/watch-phase.sh" > "$T/out" 2>&1; rc=$?
check "en: uso di watch-phase.sh in inglese" '[ "$rc" = 2 ] && grep -q "^usage: .*watch-phase.sh <run-dir> <label>$" "$T/out"'

echo "phase-events.test.sh: $pass/$((pass + fail)) ok"
[ "$fail" -eq 0 ]
