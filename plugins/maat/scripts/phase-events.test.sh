#!/usr/bin/env bash
# phase-events.test.sh — the end of the phase (■/✖) arrives only with the .exit file, not with the first `result`.
#   bash plugins/maat/scripts/phase-events.test.sh          (Git Bash o WSL)
#   PE=/path/variant.py bash .../phase-events.test.sh                      # counterproof on a mutation
set -uo pipefail
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
WM="$T/wp mut"; mkdir -p "$WM"; cp "$HERE/python.sh" "$HERE/phase-events.py" "$WM/"
sed 's/then exec "\$FIC_PY" -u /then MSYS_NO_PATHCONV=1 exec wsl -- python3 -u /' "$HERE/watch-phase.sh" > "$WM/watch-phase.sh"
if cmp -s "$HERE/watch-phase.sh" "$WM/watch-phase.sh"; then fail=$((fail + 1)); echo "FAIL: controprova watch-phase: la mutazione non si applica"
else
  wp "$WM/watch-phase.sh" "$T/run mut"; rc=$?
  check "controprova: watch-phase con wsl fisso, senza wsl nel PATH -> nessuna riga di fine (il caso sopra sarebbe rosso)" '[ "$rc" != 0 ] && [ "$(ends)" = 0 ]'
fi

echo "phase-events.test.sh: $pass/$((pass + fail)) ok"
[ "$fail" -eq 0 ]
