#!/usr/bin/env bash
# cycle-report.test.sh — cycle-report.py on a synthetic run directory with known .jsonl files: A, buckets,
# reruns, B, STOPs expected to the second; --append on a temporary file; counterproofs by mutation
# run here, on mutated copies of the script.
#   bash script/fic/cycle-report.test.sh
#   CR=/path/variant.py bash script/fic/cycle-report.test.sh   # the suite on a variant
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # plugin root
SCRIPTS_DIR=$HERE   # replay.sh reassigns HERE and ROOT when it is sourced (FIC_REPLAY_LIB=1)
CR=${CR:-$HERE/cycle-report.py}
. "$ROOT/scripts/python.sh" || { echo "interprete Python non trovato" >&2; exit 1; }
pass=0 fail=0
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
WP=$(cygpath -m "$W" 2>/dev/null || printf '%s' "$W")   # path readable by Windows Python too
# the mutants written in $W import the message catalog next to themselves (1.4.0: maat_msg.py and lib/messages.tsv)
mkdir -p "$W/lib" && cp "$HERE/maat_msg.py" "$W/" && cp "$HERE/lib/messages.tsv" "$W/lib/"
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /'; }

# --- event generators (12:00 UTC on 15/01/2026; ts = MM:SS) ---
T=2026-01-15T12
A() { # $1 ts, $2 message id, $3 content blocks, [$4 parent_tool_use_id already quoted]
  printf '{"type":"assistant","session_id":"%s","timestamp":"%s:%sZ","parent_tool_use_id":%s,"message":{"id":"%s","content":[%s]}}\n' \
    "$SID" "$T" "$1" "${4:-null}" "$2" "$3"
}
U() { # $1 ts, $2 tool_use_id (empty = prompt), [$3 parent_tool_use_id already quoted]
  local c='{"type":"text","text":"prompt"}'
  [ -n "$2" ] && c='{"type":"tool_result","tool_use_id":"'"$2"'","content":"ok"}'
  printf '{"type":"user","session_id":"%s","timestamp":"%s:%sZ","parent_tool_use_id":%s,"message":{"content":[%s]}}\n' \
    "$SID" "$T" "$1" "${3:-null}" "$c"
}
TOOL() { printf '{"type":"tool_use","id":"%s","name":"%s","input":%s}' "$1" "$2" "$3"; }
SH() { TOOL "$1" Bash '{"command":"'"$2"'"}'; }
TXT='{"type":"text","text":"x"}'
RES() { # $1 duration_ms, $2 total_cost_usd, $3 cache read (cumulative), [$4 result text]
  printf '{"type":"result","session_id":"%s","duration_ms":%s,"total_cost_usd":%s,"result":"%s","modelUsage":{"m":{"cacheReadInputTokens":%s,"cacheCreationInputTokens":10,"outputTokens":5,"costUSD":%s}}}\n' \
    "$SID" "$1" "$2" "${4:-fine}" "$3" "$2"
}
RL() { printf '{"type":"rate_limit_event","session_id":"%s","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":%s}}}}\n' "$SID" "$1"; }
TR() { # transcript: $1 file, then the ts values
  local f=$1; shift; mkdir -p "$(dirname "$f")"; : > "$f"
  for t in "$@"; do printf '{"type":"user","sessionId":"x","timestamp":"%s:%sZ"}\n' "$T" "$t" >> "$f"; done
}
VIT="bash script/test/vitest-fast.sh tests/a.test.ts"

# --- synthetic cycle: plan OK · implement STOP (deviation) · implement OK · review OK ---
R="$W/runs/spec-syn.run"; L="$R/log"; P="$W/projects/proj"
mkdir -p "$L" "$R/evidence/k1" "$R/counterproof"
printf '{"durata": 30}\n' > "$R/evidence/k1/vitest.json"
printf '{"durata": "1.5min"}\n' > "$R/counterproof/CP1.json"
printf '[]\n' > "$R/counterproof/mutations.json"

SID=s1
{ RL 0.10
  A 00:00 m1 "$(TOOL r1 Read '{"file_path":"a.md"}')"; U 00:30 r1        # file 30
  A 01:00 m2 "$TXT"                                                      # model 30
  RL 0.12; RES 90000 1.5 1000
} > "$L/01-plan.jsonl"
printf 'ESITO FASE plan: OK — approvato\n' > "$L/01-plan.esito"
TR "$P/s1.jsonl" 00:00 02:00

SID=s2
{ A 03:00 m1 "$(SH t1 "$VIT 2>&1 | tail -5")"; U 05:00 t1                # vitest 120
  A 05:30 m2 "$(SH t2 "$VIT | tail -30")"; U 06:30 t2                     # model 30 · vitest 60, RERUN
  A 07:00 m3 "$(TOOL t3 Edit '{"file_path":"C:/r/modules/x.ts"}')"; U 07:10 t3   # model 30 · file 10: source
  A 07:40 m4 "$(SH t4 "$VIT")"; U 08:00 t4                                # model 30 · vitest 20, after a write
  A 08:10 m5 "$(TOOL t5 Edit '{"file_path":"C:/r/.claude/.ai-workflow/spec-syn.md"}')"; U 08:15 t5   # 10 · file 5
  A 08:20 m6 "$(SH t6 "$VIT")"; U 08:50 t6                                # model 5 · vitest 30, RERUN
  A 09:00 m7 "$TXT"                                                       # model 10
  RES 360000 2.0 2000
} > "$L/02-implement.jsonl"
printf 'ESITO FASE implement: STOP — deviazione dal piano: il passo 3 contraddice un test\n' > "$L/02-implement.esito"
TR "$P/s2.jsonl" 03:00 09:00

SID=s3
{ A 30:00 m1 "$(SH t1 "bash cp.sh CP1")"; U 32:00 t1                      # controprove 120
  A 32:30 m2 "$(TOOL t2 Agent '{"subagent_type":"plan-implementer","prompt":"x"}')"   # model 30
  U 32:31 "" '"t2"'
  A 32:40 sm1 "$(SH s1 "sleep 60; tail out.log")" '"t2"'; U 33:40 s1 '"t2"'   # model 9 · polling 60
  A 33:45 sm2 "$(SH s2 "$VIT")" '"t2"'; U 33:55 s2 '"t2"'                    # model 5 · vitest 10: after a STOP
  A 33:58 sm3 "$TXT" '"t2"'                                                  # model 3
  U 35:00 t2                                                                 # agenti 150
  A 35:30 m3 "$TXT"                                                          # model 30
  RES 330000 3.0 3000
} > "$L/03-implement.jsonl"
printf 'ESITO FASE implement: OK — fatto\n' > "$L/03-implement.esito"
TR "$P/s3.jsonl" 30:00 36:00

SID=s4
{ A 40:00 m1 "$(SH t1 "git status")"; U 40:05 t1                          # git/harness 5
  A 40:20 m2 "$TXT"                                                        # model 15
  RES 25000 0.5 500
  A 50:00 m3 "$TXT"                                                        # passive wait 580 (spans the result)
  RL 0.30; RES 10000 0.7 800 "ESITO FASE review: OK — approvato"          # outcome from the result: no .esito
} > "$L/04-review.jsonl"
TR "$P/s4.jsonl" 40:00 50:10
TR "$P/s4/subagents/agent-a.jsonl" 51:00                                  # a sub-agent lengthens the phase

# cycle without transcript: B not measurable
N="$W/runs/spec-nb.run/log"; mkdir -p "$N"
SID=s9; { A 00:00 m1 "$TXT"; RES 60000 0.1 10; } > "$N/01-plan.jsonl"

# --- cycle with parallel threads and background tasks (wall-clock time, never counted twice) ---
UR() { # tool_result with text: $1 ts, $2 tool_use_id, $3 text
  printf '{"type":"user","session_id":"%s","timestamp":"%s:%sZ","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"%s"}]}}\n' \
    "$SID" "$T" "$1" "$2" "$3"
}
INIT() { printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$SID"; }
PL="$W/runs/spec-par.run/log"; mkdir -p "$PL"
SID=p1   # all results at the end: the init marks the end of turn
{ INIT
  A 00:00 m1 "$(TOOL g1 Agent '{"subagent_type":"spec-plan-reviewer","run_in_background":true,"prompt":"x"}')"
  UR 00:01 g1 "Async agent launched successfully. agentId: agx1"          # agenti 1
  A 00:01 sa1 "$TXT" '"g1"'
  A 00:11 m2 "$TXT"                        # orchestrator 10 in parallel with the reviewer: 5 and 5
  A 01:01 sa2 "$TXT" '"g1"'                # reviewer: 5 + 50
  A 02:01 sa3 "$TXT" '"g1"'                # reviewer 60
  INIT
  A 02:31 m3 "$TXT"                        # off-turn 00:11-02:31: reviewer work 110, passive wait 30
  RES 11000 0.1 100; RES 30000 0.2 200
} > "$PL/01-plan.jsonl"
SID=p2
{ A 10:00 m1 "$(TOOL t1 Bash '{"command":"'"$VIT"' > o1.txt","run_in_background":true}')"
  UR 10:01 t1 "Command running in background with ID: bgaa1"             # vitest 1
  A 10:05 m2 "$(SH t2 "until grep -q done o1.txt; do sleep 5; done")"; U 11:05 t2   # model 4 · wait on t1 (file): vitest 60
  A 11:10 m3 "$(TOOL t3 Bash '{"command":"'"$VIT"' > o2.txt","run_in_background":true}')"
  UR 11:11 t3 "Command running in background with ID: bgbb2"             # model 5 · vitest 1, RERUN
  A 11:15 m4 "$(TOOL t4 BashOutput '{"bash_id":"bgbb2"}')"; U 11:55 t4   # model 4 · wait on t3 (id): vitest 40
  A 12:00 m5 "$(SH t5 'for i in $(seq 1 9); do grep -q x f.log && break; timeout 5 tail f.log; done')"; U 12:30 t5  # 5 · polling 30
  A 12:35 m6 "$(SH t6 "cd modules/api; ./.venv/Scripts/pytest.exe -q tests/a.py")"; U 12:45 t6   # model 5 · pytest 10
  A 12:50 m7 "$(TOOL t7 Agent '{"subagent_type":"plan-implementer","prompt":"x"}')"   # model 5
  U 12:50 "" '"t7"'
  A 13:00 sm1 "$(SH s1 "ping -n 11 127.0.0.1")" '"t7"'; U 13:10 s1 '"t7"'   # sub-agent: model 10 · polling 10
  U 13:40 t7                               # agenti 50; the sub-agent's final message: model 30
  A 13:50 m8 "$TXT"                        # model 10
  RES 230000 0.3 300
} > "$PL/02-implement.jsonl"

CHECK='
import json, sys
group, path = sys.argv[1], sys.argv[2]
cs = {c["spec"]: c for c in json.load(open(path, encoding="utf-8"))}
c, bad = cs["spec-syn"], []
def eq(name, got, exp):
    num = isinstance(exp, float) and isinstance(got, (int, float))
    if not (abs(got - exp) < 0.01 if num else got == exp):
        bad.append("%s: atteso %r, ottenuto %r" % (name, exp, got))
if group == "base":
    eq("A", c["A_s"], 935.0)
    eq("A driver", c["driver_s"], 120.0)
    eq("A per fase", {k: round(v, 1) for k, v in c["A_by_phase_s"].items()},
       {"plan": 90.0, "implement": 690.0, "review": 35.0})
    exp = {"vitest": 240, "eslint": 0, "pytest": 0, "build": 0, "controprove": 120, "polling": 60,
           "git/harness": 5, "file": 45, "agenti": 150, "bash": 0, "altro": 0}
    eq("bucket", {k: round(v, 1) for k, v in c["buckets_s"].items()}, {k: float(v) for k, v in exp.items()})
    eq("modello", c["model_s"], 237.0)
    eq("modello del sub-agente", c["model_by_thread_s"].get("implement/plan-implementer"), 17.0)
    eq("attesa passiva", c["passive_wait_s"], 580.0)
    eq("costo", c["cost_usd"], 7.2)
    eq("token", c["tokens"], {"cache_read": 6800, "cache_write": 40, "output": 20})
    eq("quota 5h", c["quota_5h"], [0.1, 0.3])
    eq("STOP", [(s["fase"], s["causa"]) for s in c["stops"]], [("02-implement", "deviazione")])
    eq("STOP per causa", c["stops_by_cause"], {"deviazione": 1})
    eq("esito dal result", c["phases"][3]["esito"], "OK")
    eq("data", c["date"], "2026-01-15")
elif group == "rerun":
    eq("riesecuzioni", [(r["fase"], round(r["s"], 1)) for r in c["reruns"]],
       [("02-implement", 60.0), ("02-implement", 30.0)])
    eq("(a) eliminabile", c["aggregates_s"]["a_eliminabile"], 90.0)
    eq("(b) gate al primo run", c["aggregates_s"]["b_gate_primo_run"], 330.0)
    eq("(c) modello", c["aggregates_s"]["c_modello"], 237.0)
    eq("resto", c["aggregates_s"]["resto"], 50.0)
elif group == "B":
    eq("B", c["B_s"], 1800.0)
    eq("pause dopo STOP", [(p["dopo"], round(p["s"], 1)) for p in c["stop_pauses"]], [("02-implement", 1260.0)])
    n = cs["spec-nb"]
    eq("B non misurabile", n["B_s"], None)
    eq("sessioni senza transcript", n["B_missing_sessions"], ["s9"])
elif group == "par":
    c = cs["spec-par"]
    p1, p2 = c["phases"]
    r = lambda d: {k: round(v, 1) for k, v in d.items()}
    eq("fili paralleli: modello per filo", r(p1["model_by_thread_s"]), {"orchestratore": 5.0, "spec-plan-reviewer": 115.0})
    eq("fine turno dall init: attesa passiva", round(p1["passive_wait_s"], 1), 30.0)
    eq("lavoro fuori turno", round(p1["off_turn_work_s"], 1), 110.0)
    exp = {"vitest": 102, "eslint": 0, "pytest": 10, "build": 0, "controprove": 0, "polling": 40, "git/harness": 0,
           "file": 0, "agenti": 50, "bash": 0, "altro": 0}
    eq("background e classificazione: bucket", r(p2["buckets_s"]), {k: float(v) for k, v in exp.items()})
    eq("messaggio finale del sub-agente", r(p2["model_by_thread_s"]), {"orchestratore": 38.0, "plan-implementer": 40.0})
    eq("riesecuzione in background", [(x["fase"], round(x["s"], 1)) for x in c["reruns"]], [("02-implement", 41.0)])
print("\n".join(bad))
sys.exit(1 if bad else 0)
'
report() { # $1 script -> JSON into $W/out.json
  "$FIC_PY" "$1" --json --projects "$WP/projects" "$WP/runs/spec-syn.run" "$WP/runs/spec-nb.run" "$WP/runs/spec-par.run" \
    > "$W/out.json" 2> "$W/err.txt"
}
group() { # $1 group -> outcome of the comparison with the expected values; details in $W/why.txt
  "$FIC_PY" -c "$CHECK" "$1" "$WP/out.json" > "$W/why.txt" 2>&1
}
tree_sum() { find "$W/runs" -type f -exec cksum {} + | sort; }

# --- expected values ---
before=$(tree_sum)
if report "$CR"; then ok; else ko "cycle-report --json esce con errore" "$(cat "$W/err.txt")"; fi
for g in base rerun B par; do
  if group "$g"; then ok; else ko "attesi: $g" "$(cat "$W/why.txt")"; fi
done
[ "$before" = "$(tree_sum)" ] && ok || ko "sola lettura: la run directory e' cambiata"

# readable output
out=$("$FIC_PY" "$CR" --projects "$WP/projects" "$WP/runs/spec-syn.run" "$WP/runs/spec-nb.run" 2>&1)
printf '%s\n' "$out" | grep -q "^== spec-syn .* A 15\.6 min .* B 30\.0 min" && ok || ko "tabella: riga del ciclo" "$out"
printf '%s\n' "$out" | grep -q "STOP 02-implement \[deviazione\]" && ok || ko "tabella: STOP" "$out"
printf '%s\n' "$out" | grep -q "^== spec-nb .* B non misurabile" && ok || ko "tabella: B non misurabile" "$out"
printf '%s\n' "$out" | grep -q "^== TOTALE 2 cicli" && ok || ko "tabella: totale" "$out"
# a single .jsonl is a one-phase cycle
one=$("$FIC_PY" "$CR" --projects "$WP/projects" "$WP/runs/spec-syn.run/log/02-implement.jsonl" 2>&1)
printf '%s\n' "$one" | grep -q "A 6\.0 min" && ok || ko "un solo .jsonl" "$one"

# --- --append: only the given file, one line per cycle, header once ---
REAL="$ROOT/.claude/.ai-workflow/metrics.csv"
real_before=$(cksum "$REAL" 2>/dev/null || echo assente)
M="$W/m/metrics.csv"; mkdir -p "$W/m"
"$FIC_PY" "$CR" --append --metrics "$WP/m/metrics.csv" --projects "$WP/projects" "$WP/runs/spec-syn.run" >/dev/null 2>&1 && ok || ko "--append esce con errore"
"$FIC_PY" "$CR" --append --metrics "$WP/m/metrics.csv" --projects "$WP/projects" "$WP/runs/spec-syn.run" "$WP/runs/spec-nb.run" >/dev/null 2>&1 && ok || ko "--append (seconda volta) esce con errore"
csvcheck=$("$FIC_PY" -c '
import csv, sys
rows = list(csv.reader(open(sys.argv[1], encoding="utf-8", newline="")))
exp = ["data", "spec", "fasi", "A_min", "B_min", "bucket_a_min", "bucket_b_min", "bucket_c_min", "bucket_resto_min",
       "costo_usd", "token_cache_letti", "token_cache_scritti", "token_output", "riesecuzioni", "stop", "stop_cause",
       "harness"]
bad = []
if rows[0] != exp: bad.append("intestazione: %r" % rows[0])
if len(rows) != 4: bad.append("righe: %d (attese 1 + 3)" % len(rows))
d = dict(zip(rows[0], rows[1]))
want = {"data": "2026-01-15", "spec": "spec-syn", "fasi": "01-plan 02-implement 03-implement 04-review",
        "A_min": "15.6", "B_min": "30.0", "bucket_a_min": "1.5", "bucket_b_min": "5.5", "costo_usd": "7.20",
        "token_cache_letti": "6800", "riesecuzioni": "2", "stop": "1", "stop_cause": "deviazione=1",
        "harness": "interno"}
bad += ["%s: %r (atteso %r)" % (k, d.get(k), v) for k, v in want.items() if d.get(k) != v]
if rows[1] != rows[2]: bad.append("la stessa run da due righe diverse")
if dict(zip(rows[0], rows[3])).get("B_min") != "non misurabile": bad.append("B_min del ciclo senza transcript")
print("\n".join(bad))
' "$WP/m/metrics.csv" 2>&1)
[ -z "$csvcheck" ] && ok || ko "metrics.csv" "$csvcheck"
[ "$real_before" = "$(cksum "$REAL" 2>/dev/null || echo assente)" ] && ok || ko "il metrics.csv reale e' stato toccato"
[ "$before" = "$(tree_sum)" ] && ok || ko "--append ha scritto nella run directory"
"$FIC_PY" "$CR" --metrics "$WP/m/x.csv" "$WP/runs/spec-syn.run" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && [ ! -e "$W/m/x.csv" ] && ok || ko "--metrics senza --append va rifiutato (rc=$rc)"
# --metrics default: the work folder of the current folder's PROJECT, not three levels above the script
# (pk04a-1, schema L)
MR="$W/mr"; mkdir -p "$MR/.claude/.ai-workflow" && git -C "$MR" init -q . >/dev/null 2>&1
(cd "$MR/.claude" && "$FIC_PY" "$CR" --append --projects "$WP/projects" "$WP/runs/spec-syn.run" >/dev/null 2>&1)
[ -s "$MR/.claude/.ai-workflow/metrics.csv" ] && [ ! -e "$ROOT/.claude" ] && ok ||
  ko "--append senza --metrics: metrics.csv nella cartella di lavoro del progetto (e niente sotto il plugin)"

# --- the cycle's harness (pk04a-2, A8): versione= and radice= of harness.fp in the report and in the harness column ---
HV="$W/hv/spec-hv.run"; mkdir -p "$HV" && cp -r "$R/log" "$HV/"
printf 'impronta=%064d\nversione=0.9.0\nradice=C:/plug/maat\n' 0 > "$HV/harness.fp"
has09() { grep -q "Harness: maat 0\.9\.0 — C:/plug/maat" <<< "$1"; }
hv=$("$FIC_PY" "$CR" --projects "$WP/projects" "$WP/hv/spec-hv.run" 2>&1)
has09 "$hv" && ok || ko "rapporto: Harness: maat 0.9.0 — <radice>" "$hv"
HI="$W/hv/spec-hi.run"; mkdir -p "$HI" && cp -r "$R/log" "$HI/"; grep -v '^versione=' "$HV/harness.fp" > "$HI/harness.fp"
hi=$("$FIC_PY" "$CR" --projects "$WP/projects" "$WP/hv/spec-hi.run" 2>&1)
{ grep -q "Harness: harness interno" <<< "$hi" && ! has09 "$hi"; } && ok ||
  ko "controprova: senza la riga versione= il rapporto dice «harness interno» e il caso 0.9.0 cade" "$hi"
HE="$W/hv/spec-he.run"; mkdir -p "$HE" && cp -r "$R/log" "$HE/"; sed 's/^versione=.*/versione=/' "$HV/harness.fp" > "$HE/harness.fp"
he=$("$FIC_PY" "$CR" --projects "$WP/projects" "$WP/hv/spec-he.run" 2>&1)
grep -q "Harness: maat versione ignota — C:/plug/maat" <<< "$he" && ok || ko "versione= vuota: «maat versione ignota», mai «maat »" "$he"
mcols() { # $1 csv file → per row: number of fields and last field, "|" between rows
  "$FIC_PY" -c 'import csv, sys
print("|".join("%d:%s" % (len(r), r[-1]) for r in csv.reader(open(sys.argv[1], encoding="utf-8", newline=""))))' "$1" | tr -d '\r'
}
"$FIC_PY" "$CR" --append --metrics "$WP/hv/m.csv" --projects "$WP/projects" "$WP/hv/spec-hv.run" >/dev/null 2>&1
[ "$(mcols "$W/hv/m.csv")" = "17:harness|17:maat 0.9.0" ] && ok || ko "--append: colonna harness = maat 0.9.0" "$(mcols "$W/hv/m.csv")"
# metrics.csv with the older-format header (no harness) and one row → migration, then the new row
OLDH="data,spec,fasi,A_min,B_min,bucket_a_min,bucket_b_min,bucket_c_min,bucket_resto_min,costo_usd,token_cache_letti,token_cache_scritti,token_output,riesecuzioni,stop,stop_cause"
vecchio() { printf '%s\r\n%s\r\n' "$OLDH" "2026-01-01,spec-v,01-plan,1.0,2.0,0.0,0.0,0.0,0.0,0.10,1,2,3,0,0," > "$1"; }
vecchio "$W/hv/old.csv"
"$FIC_PY" "$CR" --append --metrics "$WP/hv/old.csv" --projects "$WP/projects" "$WP/hv/spec-hv.run" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && [ "$(mcols "$W/hv/old.csv")" = "17:harness|17:|17:maat 0.9.0" ] && grep -q "^2026-01-01,spec-v,01-plan," "$W/hv/old.csv" && ok ||
  ko "migrazione: intestazione nuova, riga vecchia con harness vuoto, riga nuova maat 0.9.0 (rc=$rc)" "$(mcols "$W/hv/old.csv")"
if ls "$W/hv" | grep -q '\.tmp-'; then ko "migrazione: temporaneo lasciato"; else ok; fi
sed 's/^            why = prepara_metriche(path)$/            why = None/' "$CR" > "$W/mut-migra.py"
if cmp -s "$CR" "$W/mut-migra.py"; then ko "controprova migrazione: la mutazione non si applica"; else
  vecchio "$W/hv/old2.csv"
  "$FIC_PY" "$W/mut-migra.py" --append --metrics "$WP/hv/old2.csv" --projects "$WP/projects" "$WP/hv/spec-hv.run" >/dev/null 2>&1
  [ "$(mcols "$W/hv/old2.csv")" != "17:harness|17:|17:maat 0.9.0" ] && ok ||
    ko "controprova migrazione: senza la migrazione il caso resta verde"
fi
printf 'x,y\r\n1,2\r\n' > "$W/hv/ignota.csv"; cp "$W/hv/ignota.csv" "$W/hv/ignota.prima"
"$FIC_PY" "$CR" --append --metrics "$WP/hv/ignota.csv" --projects "$WP/projects" "$WP/hv/spec-hv.run" >/dev/null 2>"$W/hv/ignota.err"; rc=$?
[ $rc -eq 2 ] && cmp -s "$W/hv/ignota.csv" "$W/hv/ignota.prima" && grep -q "sconosciuta" "$W/hv/ignota.err" && ok ||
  ko "intestazione sconosciuta: exit 2 col motivo, file identico byte per byte (rc=$rc)" "$(cat "$W/hv/ignota.err")"

# --- counterproofs by mutation: on mutated copies of the script, the groups turn RED ---
mutant() { # $1 name, $2 sed expression, $3 group that must turn red
  local m="$W/mut-$1.py"
  sed "$2" "$CR" > "$m"
  if cmp -s "$CR" "$m"; then ko "controprova $1: la mutazione non si applica (lo script e' cambiato?)"; return; fi
  if ! report "$m"; then ko "controprova $1: il mutante non gira" "$(cat "$W/err.txt")"; return; fi
  if group "$3"; then ko "controprova $1: il gruppo $3 resta verde sul mutante"; else ok; fi
}
[ "$(grep -c '^            if key in seen:$' "$CR")" = 1 ] && ok || ko "controprova rerun: riga della classificazione non unica"
mutant rerun 's/^            if key in seen:$/            if False:/' rerun
[ "$(grep -c 'b_s = span - sum(x\["s"\] for x in pauses)' "$CR")" = 1 ] && ok || ko "controprova B: riga del calcolo non unica"
mutant segno-B 's/b_s = span - sum(x\["s"\] for x in pauses)/b_s = span + sum(x["s"] for x in pauses)/' B

# --- corpus: corpus.json and replay.sh --dry-run (prints the commands without running them; refuses worktree
# paths it did not create), from the plugin against a SYNTHETIC PROJECT (pk04a-1: the project is the work
# folder, the harness is the plugin and is not copied into the worktree). One real replay, with the fake claude (explicit plugin). ---
RP="$ROOT/scripts/corpus/replay.sh"

# synthetic project: two commits (the frontend lockfile changes in the second), node_modules installed (gitignored)
PJ="$W/p/proj"; mkdir -p "$PJ"
(cd "$PJ" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  mkdir -p .claude/.ai-workflow modules/app && printf 'spec-*\n' > .claude/.ai-workflow/.gitignore && printf 'node_modules\n' > .gitignore &&
  printf '{"lock":1}\n' > modules/app/package-lock.json && git add -A && git commit -qm uno &&
  printf '{"lock":2}\n' > modules/app/package-lock.json && git commit -qam due && mkdir -p modules/app/node_modules/x) >/dev/null 2>&1
rp() { (cd "$PJ" && bash "$RP" "$@"); }
SRCD="$W/src"; RS="$SRCD/spec-rp.run"; mkdir -p "$RS/log" "$RS/prompts"
# Phase state = HEAD of the MAIN tree (the synthetic project): dependencies equal to the main tree's.
MAINREPO=$PJ
HEAD_SHA=$(git -C "$MAINREPO" rev-parse HEAD); TREE=$(git -C "$MAINREPO" rev-parse 'HEAD^{tree}')
printf '# spec\n' > "$SRCD/spec-rp.md"
printf '%s\n' "$HEAD_SHA" > "$RS/base.txt"
for l in 01-plan 02-implement 03-review; do
  printf '/full-implementation-cycle --worker=%s rp --tests=std — contesto\nriga 2\n' "${l#*-}" > "$RS/prompts/$l.md"
  : > "$RS/log/$l.jsonl"
done
echo "$TREE" > "$RS/log/02-implement.pre-tree"; echo "$TREE" > "$RS/log/02-implement.post-tree"
PARENT="$W/p"
state() { git -C "$PJ" worktree list --porcelain | grep -c '^worktree '; ls -d "$PARENT"/fic-replay-* 2>/dev/null; find "$W/src" -exec cksum {} + 2>/dev/null | sort; }
st_before=$(state)

out=$(rp rp review --source "$SRCD" --dry-run 2>&1); rc=$?
[ $rc -eq 0 ] && ok || ko "replay --dry-run esce $rc" "$out"
has() { printf '%s\n' "$out" | grep -qF -- "$1" && ok || ko "replay --dry-run: manca «$1»" "$out"; }
has "worktree add --detach"
has " $HEAD_SHA"
has "read-tree -u --reset $TREE"
has "diff --name-only --no-renames $TREE $TREE"
has "--no-dev|"
has "run-phase.sh .claude/.ai-workflow/spec-rp.run 03-review .claude/.ai-workflow/spec-rp.run/prompts/03-review.md"
has "cycle-report.py"
has "worktree remove --force"
has "/maat:full-implementation-cycle \\2 --no-dev|"
n=$(printf '%s\n' "$out" | grep -cE '^\+ cp .*/src/spec-rp\.run/log/0[0-9]-[a-z]+\.\* ')
[ "$n" = 2 ] && ok || ko "replay --dry-run: copiati i log di $n etichette (attese 2: 01-plan, 02-implement)" "$out"
[ "$st_before" = "$(state)" ] && ok || ko "replay --dry-run ha eseguito qualcosa (worktree, cartelle o file cambiati)"

# a hand-picked --worktree, new and well named, is accepted (and not created)
out=$(rp rp review --source "$SRCD" --worktree "$W/fic-replay-nuovo" --dry-run 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q 'worktree add --detach .*fic-replay-nuovo' && [ ! -e "$W/fic-replay-nuovo" ] && ok ||
  ko "replay --worktree nuovo (rc=$rc)" "$out"
# paths that replay.sh did not create: refused (exit 3), without printing any git command
mkdir -p "$W/fic-replay-esiste"
refused() { # $1 description, then the command
  local d=$1 o r; shift
  o=$("$@" 2>&1); r=$?
  [ $r -eq 3 ] && ! printf '%s\n' "$o" | grep -q '^+ ' && ok || ko "rifiuto atteso: $d (rc=$r)" "$o"
}
refused "--worktree gia' esistente" rp rp review --source "$SRCD" --worktree "$W/fic-replay-esiste" --dry-run
refused "--worktree senza prefisso fic-replay-" rp rp review --source "$SRCD" --worktree "$W/altro" --dry-run
refused "--remove di una cartella non creata da replay" rp --remove "$W/fic-replay-esiste" --dry-run
refused "--remove del tree principale" rp --remove "$PJ" --dry-run
refused "--remove del harness (il plugin)" rp --remove "$ROOT" --dry-run
rp rp fix --source "$SRCD" --dry-run >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && ok || ko "fase assente nel ciclo: uscita attesa 2, ottenuta $rc"
[ "$st_before" = "$(state)" ] && ok || ko "i rifiuti hanno lasciato tracce"

# --- dependencies: linked from the main tree only if they match at the phase state, otherwise refusal
# before creating anything; the removal takes the links away FIRST and never touches the source ---
# pk04b-2: what to link and which files decide the dependencies is declared by maat.json (worktree-lib.sh): here the
# guide project's example, which recreates the former lists; only for these cases (MAAT_CONFIG, then unset)
MSS="$W/maat-ss.json"; cp "$ROOT/examples/nuxt-fastapi.maat.json" "$MSS"; export MAAT_CONFIG=$MSS
MAINT=$(cd "$PJ" && pwd)
out=$(rp rp review --source "$SRCD" --dry-run 2>&1); rc=$?
[ $rc -eq 0 ] && ok || ko "replay --dry-run (dipendenze uguali) esce $rc" "$out"
has "+ fic_relgit "
has "+ deps_fp_check "
if printf '%s\n' "$out" | grep -q '^+ deps_bytes '; then ko "replay --dry-run: deps_bytes non serve piu' (impronta normalizzata)" "$out"; else ok; fi
# the harness is NOT copied into the worktree (pk04a-1, step 9): the phase starts with the plugin's scripts/run-phase.sh
# and MAAT_PLUGIN_DIR=<plugin>, even when the plugin is the default one (MAAT_ROOT)
if printf '%s\n' "$out" | grep -qE '^\+ rm -rf .* && cp -r '; then ko "replay --dry-run: copia ancora il harness nel worktree" "$out"; else ok; fi
has "MAAT_PLUGIN_DIR=$(printf '%q' "$ROOT") "
has "bash $(printf '%q' "$ROOT/scripts/run-phase.sh") .claude/.ai-workflow/spec-rp.run 03-review "
lf=$(printf '%s\n' "$out" | grep -n '^+ forget_mirror ' | cut -d: -f1); lu0=$(printf '%s\n' "$out" | grep -n '^+ unlink_deps ' | cut -d: -f1)
[ -n "$lf" ] && [ -n "$lu0" ] && [ "$lf" -lt "$lu0" ] && ok || ko "replay --dry-run: forget_mirror (copia WSL del worktree) deve precedere unlink_deps ($lf/$lu0)" "$out"
nd=0
for d in "$MAINT"/node_modules "$MAINT"/modules/app/node_modules "$MAINT"/modules/app/apps/*/node_modules \
         "$MAINT"/modules/app/packages/*/node_modules "$MAINT"/modules/api/.venv; do
  [ -e "$d" ] || continue; nd=$((nd + 1)); r=${d#"$MAINT"/}
  printf '%s\n' "$out" | grep -qE -- "^\+ link_dep [^ ]*/$r [^ ]*/fic-replay-[^ /]*/$r\$" && ok || ko "replay --dry-run: manca il collegamento di $r" "$out"
done
[ "$(printf '%s\n' "$out" | grep -c '^+ link_dep ')" = "$nd" ] && ok || ko "replay --dry-run: collegamenti attesi $nd" "$out"
lu=$(printf '%s\n' "$out" | grep -n '^+ unlink_deps ' | cut -d: -f1); lr=$(printf '%s\n' "$out" | grep -n 'worktree remove --force' | cut -d: -f1)
[ -n "$lu" ] && [ -n "$lr" ] && [ "$lu" -lt "$lr" ] && ok || ko "replay --dry-run: unlink_deps deve precedere worktree remove ($lu/$lr)" "$out"
out=$(rp --remove "$W/fic-replay-esiste" --dry-run 2>&1)   # refused earlier: no unlink printed
if printf '%s\n' "$out" | grep -q 'unlink_deps'; then ko "--remove rifiutato ha stampato unlink_deps" "$out"; else ok; fi

# different dependencies: the parent of the last commit that changed the frontend lockfile (in the synthetic
# project: the first commit; it used to be the guide project's history)
SRCX="$W/srcx"; RX="$SRCX/spec-rpx.run"; mkdir -p "$RX/log" "$RX/prompts"
OLD=$(git -C "$PJ" rev-parse "$(git -C "$PJ" rev-list -1 HEAD -- modules/app/package-lock.json)^")
printf '# spec\n' > "$SRCX/spec-rpx.md"; printf '%s\n' "$OLD" > "$RX/base.txt"
for l in 01-plan 02-review; do
  printf '/full-implementation-cycle --worker=%s rpx --tests=std\n' "${l#*-}" > "$RX/prompts/$l.md"; : > "$RX/log/$l.jsonl"
done
if git -C "$MAINT" diff --quiet "$OLD" -- modules/app/package-lock.json; then
  ko "premessa: il lockfile a $OLD dovrebbe differire dal tree principale"
else
  st2=$(state)
  out=$(rp rpx review --source "$SRCX" --dry-run 2>&1); rc=$?
  [ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q 'dipendenze diverse' && printf '%s\n' "$out" | grep -q 'modules/app/package-lock.json' &&
    printf '%s\n' "$out" | grep -q -- '--non-confrontabile' && ! printf '%s\n' "$out" | grep -q '^+ ' && ok ||
    ko "dipendenze diverse: rifiuto atteso (uscita 2, nessun comando) — rc=$rc" "$out"
  out=$(rp rpx review --source "$SRCX" --dry-run --non-confrontabile 2>&1); rc=$?
  [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q '^replay: NON CONFRONTABILE — dipendenze diverse' &&
    printf '%s\n' "$out" | grep -q "NON CONFRONTABILE — %s.*NON-CONFRONTABILE\.txt.*report\.txt" &&
    printf '%s\n' "$out" | grep -q '^+ link_dep ' && ok ||
    ko "--non-confrontabile: rigioco marcato e collegamenti stampati attesi (rc=$rc)" "$out"
  if printf '%s\n' "$out" | grep -qE '^\+ deps_(bytes|fp_check) '; then
    ko "--non-confrontabile: i byte delle dipendenze non vanno copiati" "$out"; else ok; fi
  [ "$st2" = "$(state)" ] && ok || ko "rifiuto per dipendenze: lasciate tracce"
fi
unset MAAT_CONFIG

# REAL replay with the fake claude (pk04a-1, step 9): without --harness, in the worktree of a project WITHOUT enabledPlugins,
# the phase gets MAAT_PLUGIN_DIR=<MAAT_ROOT> and the sub-session --plugin-dir <MAAT_ROOT>; the prompt uses the plugin's
# skill. Counterproof on a mutated copy of the plugin: MAAT_PLUGIN_DIR only if the plugin differs from MAAT_ROOT ⇒ no
# --plugin-dir.
SRCQ="$W/srcq"; RQ="$SRCQ/spec-rq.run"; mkdir -p "$RQ/log" "$RQ/prompts"
printf '# spec\n' > "$SRCQ/spec-rq.md"; printf '%s\n' "$HEAD_SHA" > "$RQ/base.txt"
printf '/full-implementation-cycle --worker=plan rq --tests=std\n' > "$RQ/prompts/01-plan.md"
cat > "$W/claude-rq" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SPY.args"; cat > "$SPY.stdin"
echo '{"type":"result","result":"ESITO FASE plan: OK — finto","structured_output":{"fase":"plan","esito":"OK","motivo":"finto","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}'
EOF
chmod +x "$W/claude-rq"
rq() { # $1 replay.sh to use, $2 spy
  (cd "$PJ" && env -u MAAT_ROOT -u MAAT_PLUGIN_DIR -u FIC_REPO -u FIC_LOCK -u FIC_PHASE CLAUDE_BIN="$W/claude-rq" SPY="$2" \
    FIC_LANES=0 bash "$1" rq plan --source "$SRCQ" --out "$W/out-$(basename "$2")" </dev/null)
}
pdir() { grep -A1 -x -- "--plugin-dir" "$1" 2>/dev/null | sed -n 2p; }
rq "$RP" "$W/spia-rq" > "$W/rq.out" 2>&1
check_pd=$(pdir "$W/spia-rq.args")
[ -n "$check_pd" ] && [ "$(cd "$check_pd" 2>/dev/null && pwd)" = "$ROOT" ] && ok ||
  ko "rigioco senza --harness: la sotto-sessione deve ricevere --plugin-dir <MAAT_ROOT> (ottenuto «$check_pd»)" "$(tail -15 "$W/rq.out")"
head -1 "$W/spia-rq.stdin" 2>/dev/null | grep -q '^/maat:full-implementation-cycle --worker=plan rq --no-dev' && ok ||
  ko "rigioco: prompt con la skill del plugin e --no-dev" "$(head -1 "$W/spia-rq.stdin" 2>/dev/null)"
[ ! -f "$PJ/.claude/settings.json" ] && ok || ko "premessa: il progetto sintetico non deve abilitare il plugin"
ls -d "$PARENT"/fic-replay-01-plan-* >/dev/null 2>&1 && ko "rigioco: worktree non rimosso" "$(ls -d "$PARENT"/fic-replay-* 2>&1)" || ok
PQ="$W/mut rq/maat"; mkdir -p "$(dirname "$PQ")" && cp -r "$ROOT" "$PQ" && find "$PQ" -name __pycache__ -type d -prune -exec rm -rf {} +
"$FIC_PY" -c 'import sys
p = sys.argv[1]; a = "&& MAAT_PLUGIN_DIR=$(q \"$HARNESS\") FIC_LOCK="
b = "&& $([ \"$(canon \"$HARNESS\")\" != \"$MAATC\" ] && echo \"MAAT_PLUGIN_DIR=$(q \"$HARNESS\")\") FIC_LOCK="
t = open(p, encoding="utf-8", newline="").read()
if t.count(a) != 1: sys.exit(1)
open(p, "w", encoding="utf-8", newline="").write(t.replace(a, b))' "$PQ/scripts/corpus/replay.sh" && ok ||
  ko "premessa: mutazione «MAAT_PLUGIN_DIR solo se diverso da MAAT_ROOT» non applicata"
rq "$PQ/scripts/corpus/replay.sh" "$W/spia-rq2" > "$W/rq2.out" 2>&1
[ -f "$W/spia-rq2.args" ] && [ -z "$(pdir "$W/spia-rq2.args")" ] && ok ||
  ko "controprova: col mutante la fase deve partire senza --plugin-dir (il caso sopra sarebbe rosso)" "$(tail -15 "$W/rq2.out")"

# the PROJECT's corpus (cartelle.corpus of its maat.json), never the plugin's
out=$(rp --check --source "$SRCD" 2>&1); rc=$?
[ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q 'nessun corpus: cartelle.corpus' && ok || ko "--check senza cartelle.corpus: uscita 2 «nessun corpus» (rc=$rc)" "$out"
mkdir -p "$PJ/corpus"
printf '{"cicli": [{"id": "uno", "run": "spec-rp.run", "spec": "spec-rp.md", "base": "%s"}]}\n' "$HEAD_SHA" > "$PJ/corpus/c.json"
printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}], "cartelle": {"corpus": "corpus/c.json"}}\n' > "$PJ/.claude/maat.json"
out=$(rp --check --source "$SRCD" 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$out" = "uno: ok" ] && ok || ko "--check col corpus di cartelle.corpus del progetto (rc=$rc)" "$out"
out=$(rp uno review --source "$SRCD" --dry-run 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q '^replay: ciclo spec-rp · fase 03-review' && ok || ko "id del corpus del progetto risolto (rc=$rc)" "$out"
rm -rf "$PJ/corpus" "$PJ/.claude/maat.json"

# linking and unlinking on synthetic folders (the real replay.sh functions, FIC_REPLAY_LIB=1)
LK="$W/lk"; WTX="$LK/fic-replay-sint"
mkdir -p "$LK/main/node_modules" "$LK/main/modules/app/node_modules/pkg" "$LK/main/modules/api/.venv/Scripts" \
         "$WTX/modules/app/apps/admin/node_modules"
echo tieni > "$LK/main/node_modules/r.txt"; echo tieni > "$LK/main/modules/app/node_modules/pkg/index.js"
echo tieni > "$LK/main/modules/api/.venv/Scripts/python.txt"
echo del-worktree > "$WTX/modules/app/apps/admin/node_modules/mio.txt"   # REAL folder of the worktree
src_sum() { find "$LK/main" -exec cksum {} + 2>/dev/null | sort; }
src_before=$(src_sum)
lk=$( ( FIC_REPLAY_LIB=1; export MAAT_CONFIG=$MSS; . "$RP" || { echo "sorgente di replay.sh fallito"; exit 0; }
  ls=$(dep_links "$LK/main" | tr '\n' ' ')
  [ "$ls" = "node_modules modules/app/node_modules modules/api/.venv " ] || echo "dep_links: «$ls»"
  for p in $ls; do link_dep "$LK/main/$p" "$WTX/$p" || echo "link_dep $p fallito"; done
  for p in $ls; do [ -L "$WTX/$p" ] || echo "$p non e' un collegamento"; done
  [ "$(cat "$WTX/modules/app/node_modules/pkg/index.js" 2>/dev/null)" = tieni ] || echo "il collegamento non mostra la sorgente"
  mkdir -p "$LK/main/modules/app/apps/admin/node_modules"
  link_dep "$LK/main/modules/app/apps/admin/node_modules" "$WTX/modules/app/apps/admin/node_modules" 2>/dev/null &&
    echo "link_dep ha sostituito una cartella esistente"
  rmdir "$LK/main/modules/app/apps/admin/node_modules"
  unlink_deps "$WTX" || echo "unlink_deps esce non zero"
  for p in $ls; do { [ -L "$WTX/$p" ] || [ -e "$WTX/$p" ]; } && echo "$p resta dopo unlink_deps"; done
  [ "$(cat "$WTX/modules/app/apps/admin/node_modules/mio.txt" 2>/dev/null)" = del-worktree ] ||
    echo "unlink_deps ha toccato una cartella vera del worktree"
  rm -rf "$WTX"   # what git worktree remove --force does: after unlinking it cannot reach the source
) 2>&1)
[ -z "$lk" ] && ok || ko "collegamenti su cartelle sintetiche" "$lk"
[ "$src_before" = "$(src_sum)" ] && ok || ko "la rimozione del worktree ha toccato la SORGENTE dei collegamenti" "$(diff <(echo "$src_before") <(src_sum))"

# dependency fingerprint on synthetic folders: same content except CRLF/LF ⇒ same fingerprint, without
# copying anything (the formula is the one shared with vitest-fast.sh: fic_deps_fp of script/test/fic-mirror.sh)
FB="$W/fb"; FM="$FB/main/modules/app" FW="$FB/fic-replay-fb/modules/app"
for d in "$FM" "$FW"; do mkdir -p "$d/apps/admin" "$d/node_modules/x" "$d/.nuxt" "$d/.output"; done
printf '{\n  "name": "app"\n}\n' > "$FM/package.json"; printf '{\r\n  "name": "app"\r\n}\r\n' > "$FW/package.json"
printf '{"lock":1}\n' > "$FM/package-lock.json"; printf '{"lock":1}\r\n' > "$FW/package-lock.json"
printf '{"n":"admin"}\n' > "$FM/apps/admin/package.json"; printf '{"n":"admin"}\n' > "$FW/apps/admin/package.json"
for f in node_modules/x/package.json .nuxt/package.json .output/package.json tsconfig.json; do
  printf 'main\n' > "$FM/$f"; printf 'wt\r\n' > "$FW/$f"   # outside the selection: they do not count
done
fbsum() { find "$FW" -type f -exec cksum {} + | sort; }
fb=$( ( FIC_REPLAY_LIB=1; export MAAT_CONFIG=$MSS; . "$RP" || { echo "sorgente di replay.sh fallito"; exit 0; }
  before=$(fbsum)
  [ "$(deps_fp "$FB/main")" = "$(deps_fp "$FB/fic-replay-fb")" ] || echo "impronte diverse con sole fine riga diverse"
  [ "$(deps_fp "$FB/main")" = "$( . "$SCRIPTS_DIR/fic-mirror.sh"; fic_deps_fp "$FM")" ] || echo "deps_fp diversa da fic_deps_fp (vitest-fast.sh)"
  grep -q '^\. "\$HERE/fic-mirror.sh"' "$SCRIPTS_DIR/test-fast.sh" || echo "test-fast.sh non usa fic-mirror.sh"
  deps_fp_check "$FB/main" "$FB/fic-replay-fb" >/dev/null 2>&1; [ -z "$FPWARN" ] || echo "avviso con impronte uguali: $FPWARN"
  [ "$before" = "$(fbsum)" ] || echo "il controllo ha scritto nel worktree"
  printf 'x\n' >> "$FW/apps/admin/package.json"
  deps_fp_check "$FB/main" "$FB/fic-replay-fb" > "$FB/w.txt" 2>&1; rc=$?; w=$(cat "$FB/w.txt")
  [ $rc -eq 0 ] && printf '%s' "$w" | grep -q 'AVVISO.*non si semina' && printf '%s' "$FPWARN" | grep -q 'copia assente' ||
    echo "impronte diverse: avviso atteso senza errore (rc=$rc) «$w»"
) 2>&1)
[ -z "$fb" ] && ok || ko "impronta delle dipendenze su cartelle sintetiche" "$fb"

# --- 1.3.0: the outcome line in both languages (PHASE RESULT written since 1.3.0, ESITO FASE of old run dirs) ---
EL="$W/esiti"; mkdir -p "$EL"
printf 'PHASE RESULT implement: STOP — deviazione dal piano: passo 3\nstate=x\n' > "$EL/01-implement.esito"
printf 'ESITO FASE implement: STOP — deviazione dal piano: passo 3\nstate=x\n' > "$EL/02-implement.esito"
eo=$(cd "$EL" && "$FIC_PY" -B -c 'import importlib.util, sys   # -B: no __pycache__ in the plugin (maat-doctor checks it)
s = importlib.util.spec_from_file_location("cr", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
for b in ("01-implement", "02-implement"):
    e, why = m.esito_of(b + ".jsonl", [])
    print(b, e, m.stop_class(why))' "$(cygpath -m "$CR" 2>/dev/null || printf '%s' "$CR")" 2>&1 | tr -d '\r')
[ "$eo" = "$(printf '01-implement STOP deviazione\n02-implement STOP deviazione')" ] && ok || ko "riga d'esito inglese e italiana: stesso STOP e stessa causa" "$eo"

# --- 1.4.0: English summary, STOP_CLASSES in both languages ---
# the readable output in English (MAAT_LINGUA=en): same numbers, the class names and the JSON/CSV values of D7 as they are
out=$(MAAT_LINGUA=en "$FIC_PY" "$CR" --projects "$WP/projects" "$WP/runs/spec-syn.run" "$WP/runs/spec-nb.run" 2>&1)
printf '%s\n' "$out" | grep -q "^== spec-syn .* phases 4  A 15\.6 min .* B 30\.0 min" &&
  printf '%s\n' "$out" | grep -q "STOP 02-implement \[deviazione\]" && printf '%s\n' "$out" | grep -q "^== spec-nb .* B not measurable" &&
  printf '%s\n' "$out" | grep -q "^== TOTAL 2 cycles" && printf '%s\n' "$out" | grep -q "^   aggregates (min): (a) reruns " &&
  ! printf '%s\n' "$out" | grep -v "^   STOP " | grep -qE "fasi|misurabile|aggregati|riesecuzioni|lavoro fuori|modello per filo|attesa passiva|cicli|letti|pause dopo" &&
  ok || ko "en: tabella in inglese, stessi numeri, nessun italiano fuori dal testo degli STOP" "$out"
jo=$(MAAT_LINGUA=en "$FIC_PY" "$CR" --json --projects "$WP/projects" "$WP/runs/spec-nb.run" 2>&1)
ji=$("$FIC_PY" "$CR" --json --projects "$WP/projects" "$WP/runs/spec-nb.run" 2>&1)
[ "$jo" = "$ji" ] && ok || ko "en: il JSON e' lo stesso dell'italiano (D7)" "$(diff <(echo "$ji") <(echo "$jo") | head -5)"
out=$(MAAT_LINGUA=en "$FIC_PY" "$CR" --metrics x.csv "$WP/runs/spec-syn.run" 2>&1); rc=$?
[ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q -- "--metrics only goes with --append" && ok || ko "en: errore d'uso in inglese (rc=$rc)" "$out"

# The classes of the Italian texts are those of v1.3.0 (Revisione 2 §3): every Italian text of the catalog and every STOP
# reason written by a suite (.esito and result fixtures), plus the .esito of a real corpus if MAAT_CORPUS_ESITI names
# its folder. The English cases: one per class, from the English text of the catalog (the run-phase.* entries of block B
# and the others that end after `STOP — `), or a text an agent writes there where no script writes one (quota, question).
cat > "$W/classi.py" <<'EOF'
import glob, importlib.util, os, re, subprocess, sys
sys.dont_write_bytecode = True
def load(p, n):
    s = importlib.util.spec_from_file_location(n, p); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
    return m
cmd, new = sys.argv[1], load(sys.argv[2], "cr_new")
if cmd == "it":   # <new> <v1.3.0 module> <catalog> <test files…>
    old, texts = load(sys.argv[3], "cr_old"), set()
    for l in open(sys.argv[4], encoding="utf-8").read().split("\n"):
        p = l.split("\t")
        if len(p) == 3 and not l.startswith("#"):
            texts.add(p[2])
    rx = re.compile(r"(?:PHASE RESULT|ESITO FASE) [\w%-]+: STOP\s*(?:[—–-]+\s*)?([^\n'\"\\]*)")
    files = sys.argv[5:] + glob.glob(os.path.join(os.environ.get("MAAT_CORPUS_ESITI") or "-", "**", "*.esito"), recursive=True)
    for f in files:
        texts.update(m.group(1) for m in rx.finditer(open(f, encoding="utf-8", errors="replace").read()))
    diff = [(t[:90], old.stop_class(t), new.stop_class(t)) for t in sorted(texts) if old.stop_class(t) != new.stop_class(t)]
    for d in diff[:5]:
        print("DIVERSA: %r v1.3.0=%s 1.4.0=%s" % d)
    print("testi=%d diverse=%d" % (len(texts), len(diff)))
elif cmd == "en":   # <new> <maat_msg.py>
    os.environ["MAAT_LINGUA"] = "en"
    T = load(sys.argv[3], "maat_msg").T
    cases = [
        ("deviazione", T("run-phase.tg_deviation", files="tests/a.test.ts")),
        ("gate", T("run-phase.red_blocked", det="exit 1", label="02-test-red")),
        ("gate", T("plan-check.red_other", texts="`x`")),
        ("concorrenza", T("run-phase.lock_busy")),
        ("concorrenza", "another session is changing the same files at the same time"),
        ("timeout", T("counterproof.timeout")),
        ("timeout", "the sub-session timed out after 30 minutes"),
        ("quota", "usage limit reached: the 5h window resets at 14:00"),
        ("decisione", T("cycle-state.plan_nhd")),
        ("decisione", "a question for the user: keep the old column or drop it?"),
    ]
    for want, text in cases:
        got = new.stop_class(text)
        print("%s %s %s %r" % ("OK" if got == want else "KO", want, got, text[:80]))
EOF
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
CR130="$W/cr-130.py"
if git -C "$SCRIPTS_DIR" show v1.3.0:plugins/maat/scripts/cycle-report.py > "$CR130" 2>/dev/null && [ -s "$CR130" ]; then
  SUITES=(); for f in "$SCRIPTS_DIR"/*.test.sh; do SUITES+=("$(nat "$f")"); done
  cls_it() { "$FIC_PY" "$W/classi.py" it "$(nat "$1")" "$(nat "$CR130")" "$(nat "$SCRIPTS_DIR/lib/messages.tsv")" \
               "${SUITES[@]}" 2>&1 | tr -d '\r'; }
  o=$(cls_it "$CR")
  printf '%s\n' "$o" | grep -qE '^testi=[0-9]{3,} diverse=0$' && ok || ko "it: le classi dei testi italiani sono quelle di v1.3.0" "$o"
  # counterproof: an English twin that matches the `red` of test-red (no lookbehind) changes Italian texts → red
  "$FIC_PY" -c 'import sys
t = open(sys.argv[1], encoding="utf-8").read()
q = chr(34) + "),"   # the twin without its lookbehind: \bred also matches the red of test-red
open(sys.argv[2], "w", encoding="utf-8").write(t.replace(r"|(?<![\w-])reds?\b" + q, r"|\breds?\b" + q, 1))' \
    "$(nat "$CR")" "$(nat "$W/mut-red.py")"
  if cmp -s "$CR" "$W/mut-red.py"; then ko "controprova test-red: la mutazione non si applica"
  else o=$(cls_it "$W/mut-red.py"); printf '%s\n' "$o" | grep -qE 'diverse=[1-9]' && ok || ko "controprova: un gemello en su «red» di test-red resta verde" "$o"; fi
else
  echo "SALTATO [classi it contro v1.3.0: git show v1.3.0 non disponibile (plugin fuori dal repository)]"
fi
cls_en() { "$FIC_PY" "$W/classi.py" en "$(nat "$1")" "$(nat "$SCRIPTS_DIR/maat_msg.py")" 2>&1 | tr -d '\r'; }
o=$(cls_en "$CR")
[ "$(printf '%s\n' "$o" | grep -c '^OK ')" = 10 ] && ok || ko "en: un caso per classe, dai testi inglesi del catalogo" "$o"
# counterproof: the STOP_CLASSES of v1.3.0 (Italian only) → the English cases are red
"$FIC_PY" - "$(nat "$CR")" "$(nat "$CR130")" "$(nat "$W/mut-it.py")" <<'EOF'
import re, sys
new, old = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
rx = re.compile(r"^STOP_CLASSES = \[.*?^\]", re.S | re.M)
open(sys.argv[3], "w", encoding="utf-8").write(rx.sub(lambda m: rx.search(old).group(0), new, count=1))
EOF
if [ ! -s "$W/mut-it.py" ] || cmp -s "$CR" "$W/mut-it.py"; then ko "controprova STOP_CLASSES solo italiane: la mutazione non si applica"
else o=$(cls_en "$W/mut-it.py"); printf '%s\n' "$o" | grep -q '^KO ' && ok || ko "controprova: con le regex solo italiane i casi inglesi restano verdi" "$o"; fi

# replay.sh in English: the same dry-run, refusals and usage, with the reasons from the catalog
out=$(MAAT_LINGUA=en rp rp review --source "$SRCD" --dry-run 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q '^replay: cycle spec-rp · phase 03-review' &&
  printf '%s\n' "$out" | grep -q 'DRY-RUN: nothing is run' && printf '%s\n' "$out" | grep -q '^+ (check: name fic-replay-\*' &&
  ! printf '%s\n' "$out" | grep -E '^replay: |^\+ \(' | grep -qE "ciclo|fase |uscita|nulla|verifica|codice da" &&
  ok || ko "en: replay --dry-run in inglese (rc=$rc)" "$out"
out=$(MAAT_LINGUA=en rp --remove "$W/fic-replay-esiste" --dry-run 2>&1); rc=$?
[ $rc -eq 3 ] && printf '%s\n' "$out" | grep -q "^replay: REFUSED — .* is not a worktree created by replay.sh: not removing it" &&
  ! printf '%s\n' "$out" | grep -qE "RIFIUTO|non e'|manca" && ok || ko "en: rifiuto di --remove in inglese (rc=$rc)" "$out"
out=$(MAAT_LINGUA=en rp 2>&1); rc=$?
[ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q "^replay: usage: replay.sh <cycle> <phase>" && ok || ko "en: uso di replay.sh in inglese (rc=$rc)" "$out"
# the injects (no suite of their own): usage and the refusal of a path that is not a corpus worktree, in both languages
IJ="$SCRIPTS_DIR/corpus/inject/lint-vue.sh"; mkdir -p "$W/non-repo"
out=$(cd "$PJ" && MAAT_LINGUA=en bash "$IJ" 2>&1); rc=$?
[ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q "^inject lint-vue: usage: .*lint-vue.sh <corpus worktree> \[options\]$" && ok || ko "en: uso di un inject (rc=$rc)" "$out"
out=$(cd "$PJ" && MAAT_LINGUA=en GIT_CEILING_DIRECTORIES="$W" bash "$IJ" "$W/non-repo" 2>&1); rc=$?
[ $rc -eq 3 ] && printf '%s\n' "$out" | grep -q "^inject lint-vue: REFUSED — not a git repository: " && ok || ko "en: rifiuto di un inject fuori da git (rc=$rc)" "$out"
out=$(cd "$PJ" && GIT_CEILING_DIRECTORIES="$W" bash "$IJ" "$W/non-repo" 2>&1); rc=$?
[ $rc -eq 3 ] && printf '%s\n' "$out" | grep -q "^inject lint-vue: RIFIUTO — non e' un repository git: " && ok || ko "it: rifiuto di un inject fuori da git (rc=$rc)" "$out"

echo "cycle-report.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
