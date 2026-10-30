#!/usr/bin/env bash
# phase-usage.test.sh — the cost summary of a cycle (phase-usage.py --summary), on synthetic run directories:
#   1. phases picked like driver.py (log/NN-<label>.jsonl); lane logs (.corsia-<k>.jsonl) added to their phase, minutes
#      = the longest lane; a review relaunched in the same log = two sessions, costs summed (by session_id, or by the
#      segments between fic_scartato markers); a closing phase with no session; total, minutes, phases, 5h quota;
#   2. a phase .running or without .exit -> «(not finished)» and «at least»; 5h window reset; no phase logs;
#      wrong arguments (exit 2);
#   3. the output without --summary and the --json output are unchanged: golden files in tests/phase-usage/, made
#      with the script of 1.2.0;
#   4. counterproofs by mutation: (a) one maximum per file, (b) lanes as phases, (c) lane minutes summed.
#   bash plugins/maat/scripts/phase-usage.test.sh          (Git Bash or Linux)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
. "$HERE/python.sh" || { echo "Python interpreter not found" >&2; exit 2; }
pass=0 fail=0
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -20 | sed 's/^/    /'; }
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
PU="$HERE/phase-usage.py"
GOLD="$PLUGIN/tests/phase-usage"

# gen <run dir> <case>: writes the phase logs of a synthetic run (the same content on every platform)
gen() {
  "$FIC_PY" - "$(nat "$1")" "$2" <<'PY'
import json, os, sys
run, case = sys.argv[1], sys.argv[2]
d = os.path.join(run, "log"); os.makedirs(d, exist_ok=True)
def rl(u): return {"type": "rate_limit_event", "rate_limit_info": {"unifiedWindows": {"five_hour": {"utilization": u}}}}
def init(): return {"type": "system", "subtype": "init", "tools": ["Read", "Bash", "mcp__x__y"]}
def asst(i, sid):
    return {"type": "assistant", "session_id": sid, "message": {"id": "m%s" % i, "usage": {"input_tokens": 1000,
            "cache_read_input_tokens": 5000, "cache_creation_input_tokens": 200},
            "content": [{"type": "tool_use", "id": "t%s" % i, "name": "Read", "input": {"file_path": "a.py"}}]}}
def res(cost, ms, sid):
    e = {"type": "result", "subtype": "success", "total_cost_usd": cost, "duration_ms": ms, "num_turns": 3,
         "usage": {"output_tokens": 400}, "modelUsage": {"m1": {"costUSD": cost}}}
    if sid:
        e["session_id"] = sid
    return e
def log(name, evs, done=True):
    with open(os.path.join(d, name + ".jsonl"), "w", encoding="utf-8", newline="\n") as fh:
        for e in evs:
            fh.write(json.dumps(e) + "\n")
    if done:
        open(os.path.join(d, name + ".exit"), "w").write("0\n")
sid = case != "nosid"
if case in ("full", "nosid"):
    log("01-plan", [init(), rl(0.10), asst(1, "A"), res(1.00, 60000, "A" if sid else None)])
    log("02-implement", [{"type": "system", "subtype": "fic_corsie"}, {"type": "result", "subtype": "fic_corsie", "result": "x"}])
    for k, (c, ms, u) in ((1, (2.00, 300000, 0.20)), (2, (1.50, 120000, 0.25))):
        with open(os.path.join(d, "02-implement.corsia-%d.jsonl" % k), "w", encoding="utf-8", newline="\n") as fh:
            for e in (init(), rl(u), asst("L%d" % k, "L%d" % k), res(c, ms, ("L%d" % k) if sid else None)):
                fh.write(json.dumps(e) + "\n")
    log("03-review", [init(), asst(3, "R1"), res(0.30, 30000, "R1" if sid else None),
                      res(0.40, 30000, "R1" if sid else None), {"type": "system", "subtype": "fic_scartato"},
                      init(), rl(0.30), asst(4, "R2"), res(0.70, 120000, "R2" if sid else None)])
    log("04-chiusura", [])
elif case == "running":
    log("01-plan", [init(), rl(0.10), asst(1, "A"), res(1.00, 60000, "A")])
    log("02-implement", [init(), asst(2, "B"), res(0.50, 60000, "B")], done=False)
    open(os.path.join(d, "02-implement.running"), "w").write("")
elif case == "reset":
    log("01-plan", [init(), rl(0.80), res(1.00, 60000, "A")])
    log("02-review", [init(), rl(0.05), res(1.00, 60000, "B")])
elif case == "reset1":   # the window resets inside one log
    log("01-plan", [init(), rl(0.90), asst(1, "A"), rl(0.02), res(1.00, 60000, "A")])
elif case == "noexit":   # stopped with neither .exit nor .running
    log("01-plan", [init(), rl(0.10), res(1.00, 60000, "A")], done=False)
PY
}
mkdir -p "$T/full.run" "$T/nosid.run" "$T/running.run" "$T/reset.run" "$T/reset1.run" "$T/noexit.run" "$T/empty.run/log"
for c in full nosid running reset reset1 noexit; do gen "$T/$c.run" "$c"; done
sumof() { (cd "$T" && "$FIC_PY" "$(nat "${2:-$PU}")" --summary "$1.run" 2>&1); }
has() { # <label> <output> <fixed line>
  if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else ko "$1" "$2"; fi; }
row() { printf '  %-26s %9s  %6s min%s' "$1" "$2" "$3" "${4:+  ($4)}"; }   # a phase row: <label> <$cost> <minutes> [notes]

# --- 1. the complete cycle ---
S=$(sumof full)
has "totale, minuti, fasi e quota" "$S" "Cost: \$5.60 API-equivalent · 9.0 min · 4 phases · 5h quota 10% -> 30%"
has "fase semplice" "$S" "$(row 01-plan '$1.00' 1.0)"
has "corsie: una riga, costo sommato, minuti = la corsia più lunga" "$S" "$(row 02-implement '$3.50' 5.0 '2 lanes')"
has "review rilanciata: due sessioni sommate" "$S" "$(row 03-review '$1.10' 3.0 '2 sessions')"
has "chiusura senza sessione" "$S" "$(printf '  %-26s %9s  (no session)' 04-chiusura -)"
case $S in *corsia*) ko "le corsie non sono righe a sé" "$S" ;; *) ok ;; esac
case $(printf '%s\n' "$S" | tail -1) in "Note: API-equivalent cost"*) ok ;; *) ko "riga Note in fondo" "$S" ;; esac
S=$(sumof nosid)
has "senza session_id: sessioni separate da fic_scartato" "$S" "$(row 03-review '$1.10' 3.0 '2 sessions')"
has "senza session_id: totale" "$S" "Cost: \$5.60 API-equivalent · 9.0 min · 4 phases · 5h quota 10% -> 30%"

# --- 2. unfinished, window reset, no logs, arguments ---
S=$(sumof running)
has "fase in corso: at least" "$S" "Cost: at least \$1.50 API-equivalent · 2.0 min · 2 phases · 5h quota 10% -> 10%"
has "fase in corso: not finished" "$S" "$(row 02-implement '$0.50' 1.0 'not finished')"
S=$(sumof noexit)
has "senza .exit né .running: at least" "$S" "Cost: at least \$1.00 API-equivalent · 1.0 min · 1 phase · 5h quota 10% -> 10%"
has "senza .exit né .running: not finished" "$S" "$(row 01-plan '$1.00' 1.0 'not finished')"
S=$(sumof reset)
has "finestra 5h azzerata fra due fasi" "$S" "Cost: \$2.00 API-equivalent · 2.0 min · 2 phases · 5h quota window reset during the cycle"
S=$(sumof reset1)
has "finestra 5h azzerata dentro un log" "$S" "Cost: \$1.00 API-equivalent · 1.0 min · 1 phase · 5h quota window reset during the cycle"
S=$(sumof empty); rc=$?
if [ "$S" = "Cost: not measured (no phase logs)" ] && [ $rc -eq 0 ]; then ok; else ko "nessun log di fase: una riga, exit 0" "$S rc=$rc"; fi
(cd "$T" && "$FIC_PY" "$(nat "$PU")" --summary missing.run >/dev/null 2>&1); rc=$?
[ $rc -eq 2 ] && ok || ko "cartella inesistente: exit 2" "rc=$rc"
(cd "$T" && "$FIC_PY" "$(nat "$PU")" --summary --json full.run >/dev/null 2>&1); rc=$?
[ $rc -eq 2 ] && ok || ko "--summary con --json: exit 2" "rc=$rc"

# --- 3. the existing outputs do not change (golden files made with the 1.2.0 script) ---
# the --json output carries the log path: compared by file name, the same on every platform
normj() { "$FIC_PY" -c 'import json, os, sys
r = json.load(sys.stdin)
for x in r: x["log"] = os.path.basename(x["log"].replace("\\", "/"))
print(json.dumps(r, ensure_ascii=False, indent=1, sort_keys=True))'; }
out=$(cd "$T" && "$FIC_PY" "$(nat "$PU")" full.run | tr -d '\r')
if [ "$out" = "$(tr -d '\r' < "$GOLD/full.txt")" ]; then ok; else ko "uscita senza --summary invariata" "$(diff <(printf '%s\n' "$out") "$GOLD/full.txt")"; fi
out=$(cd "$T" && "$FIC_PY" "$(nat "$PU")" full.run --json | normj | tr -d '\r')
if [ "$out" = "$(tr -d '\r' < "$GOLD/full.json")" ]; then ok; else ko "uscita --json invariata" "$(diff <(printf '%s\n' "$out") "$GOLD/full.json")"; fi
# MAAT_PU_GOLD=<old phase-usage.py>: rewrites the golden files from that script (only to regenerate them)
if [ -n "${MAAT_PU_GOLD:-}" ]; then
  (cd "$T" && "$FIC_PY" "$(nat "$MAAT_PU_GOLD")" full.run) > "$GOLD/full.txt"
  (cd "$T" && "$FIC_PY" "$(nat "$MAAT_PU_GOLD")" full.run --json) | normj > "$GOLD/full.json"
  echo "golden files rewritten from $MAAT_PU_GOLD"
fi

# --- 4. counterproofs: each mutant must make its case red ---
mutant() { # <name> <old line, fixed text> <new line>: copy of the script with one line replaced
  local m="$T/pu-$1.py"
  "$FIC_PY" -c 'import sys
s = open(sys.argv[1], encoding="utf-8").read()
if s.count(sys.argv[2]) != 1: sys.exit(1)
open(sys.argv[3], "w", encoding="utf-8").write(s.replace(sys.argv[2], sys.argv[4]))' "$(nat "$PU")" "$2" "$(nat "$m")" "$3" && echo "$m"
}
REV=$(row 03-review '$1.10' 3.0 '2 sessions')
if m=$(mutant a '            cost += sum(s["cost"] for s in sess.values())' '            cost += max([s["cost"] for s in sess.values()] or [0])'); then
  printf '%s\n' "$(sumof full "$m")" | grep -qxF -- "$REV" && ko "controprova (a): con un massimo per file la review è ancora \$1.10" || ok
else ko "controprova (a): la mutazione non si applica"; fi
IMP=$(row 02-implement '$3.50' 5.0 '2 lanes')
if m=$(mutant b 'PHASE_LOG = re.compile(r"^([0-9]+-[^.]*)\.jsonl$")' 'PHASE_LOG = re.compile(r"^([0-9]+-[^.]*(?:\.corsia-[0-9]+)?)\.jsonl$")'); then
  S=$(sumof full "$m")
  case $S in *corsia*) ok ;; *) ko "controprova (b): con le corsie come fasi non compaiono righe di corsia" "$S" ;; esac
else ko "controprova (b): la mutazione non si applica"; fi
if m=$(mutant c '        m = max(mins[1:]) + mins[0] if lanes else mins[0]' '        m = sum(mins)'); then
  printf '%s\n' "$(sumof full "$m")" | grep -qxF -- "$IMP" && ko "controprova (c): con i minuti delle corsie sommati la riga è ancora 5.0 min" || ok
else ko "controprova (c): la mutazione non si applica"; fi

echo "phase-usage.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
