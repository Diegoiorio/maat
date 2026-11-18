#!/usr/bin/env bash
# driver-esiti.test.sh — the 1.8.0 sections of the tests of driver.py, split off driver.test.sh (1.8.0, CI: the whole
# file no longer fitted the per-suite limit of the Windows runner). Same preamble, same throwaway repo, same helpers
# (copied from driver.test.sh: check, drv, ok_json, spec_approved, tmut); every case and counterproof as it was.
#   bash plugins/maat/scripts/driver-esiti.test.sh
#   DRV=/path/variant.py bash .../driver-esiti.test.sh   # the suite against another driver
# Sections (the numbering of driver.test.sh):
#  14 classifica: the five classes of a finished phase, unit cases on synthetic run dirs, (d) only for plan and
#     test-red · 14b the checks of the types of an Open decision · 15 the resumes in run: .ripresa on the stopped
#     phase, its line in driver.log, the RIPRESA (driver) prompt line, limits per cycle, no progress, the second
#     invocation after the limit, final STOPs, FIC_RIPRESE=0 and ciclo.riprese 0, a .ripresa not registered, the
#     probes, the test-data deviations, with counterproofs
#  16 (1.8.1, G2-3) the usage limit or an API error of a sub-session: errore_api, classifica, the STOP of run with its
#     reason and the driver.log line, «(stderr vuoto)», the relaunch after the limit in review, implement and test-red
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # plugin root
FC=$ROOT/scripts
DRV=${DRV:-$HERE/driver.py}
. "$FC/python.sh" || { echo "driver-esiti.test.sh: nessun interprete Python (FIC_PYTHON)"; exit 2; }
export FIC_DRIVER_ROOT=$ROOT
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
cp "$HERE/maat_paths.py" "$T/"   # the mutated drivers written in $T import maat_paths from next to themselves (pk04a-1)
# 1.4.0: and maat_msg.py, which reads the catalog next to itself (lib/messages.tsv): a copy uses its own catalog
cp "$HERE/maat_msg.py" "$T/"; mkdir -p "$T/lib"; cp "$HERE/lib/messages.tsv" "$HERE/lib/maat-msg.sh" "$T/lib/"
export HOME="$T/home"; mkdir -p "$HOME"
unset FIC_DRIVER FIC_DRIVER_PY FIC_RUN_PHASE FIC_CONTEXT_PACK FIC_MAX_FASI FIC_REPO FIC_LOCK
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; if [ -n "${DRV_DEBUG:-}" ]; then tail -6 "$T/run.out" | sed "s/^/    out| /"; sed "s/^/    tg| /" "${RT:-/nessuna}/taglia.txt" 2>/dev/null; sed "s/^/    calls| /" "$FAKE_CALLS" 2>/dev/null; tail -8 "${RT:-/nessuna}/driver.log" 2>/dev/null | sed "s/^/    log| /"; fi; fi; }
drv() { "$FIC_PY" "$DRV" "$@"; }

# from section 2 of driver.test.sh
ok_json() { # $1 phase, $2 esito, $3 deviazioni, $4 bloccato_su
  printf '{"fase":"%s","esito":"%s","motivo":"finto","deviazioni":%s,"bloccato_su":"%s","file":[],"gate_interni":[],"finding":[]}' "$1" "$2" "$3" "$4"
}

# --- throwaway repo for wrappers, run and impronta ---
W=$T/repo; mkdir -p "$W"; cd "$W" || exit 2
git init -q .; git config user.email t@t; git config user.name t; git config core.autocrlf false
mkdir -p src .claude/.ai-workflow; printf 'spec-*\n' > .claude/.ai-workflow/.gitignore
printf 'uno\n' > src/a.py; git add -A; git commit -qm init
SP=.claude/.ai-workflow/spec-x.md; RUN=.claude/.ai-workflow/spec-x.run
PC=$ROOT/scripts/plan-check.sh
spec_approved() {
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." "## Piano di implementazione" \
    "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" "### Passi" "1. Modificare \`src/a.py\`." \
    "### Changelog revisione piano" "- giro 1: ok" > "$SP"
  local cur; cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$SP"
}
spec_approved
export FC FAKE_CALLS=$T/calls
CW=.claude/.ai-workflow
# from section 13 of driver.test.sh
tmut() { # <name> <sed> → $T/drv-<name>.py, 1 if the mutation does not apply
  sed "$2" "$DRV" > "$T/drv-$1.py"; ! cmp -s "$DRV" "$T/drv-$1.py"; }


# --- 14. (1.8.0, B8) classifica(fase, run_fs, label, spec_fs): the class of a finished phase, a function only (the cycle
# does not call it yet, B9). Synthetic run dirs: <name>.run/log/01-<phase>.* and the spec <name>.md. Each case prints
# «<name> <class> <rule> <proof>»; the counterproofs mutate the driver (tmut) and their case goes red.
CL=$T/cl; mkdir -p "$CL"
cat > "$T/cl.py" <<'EOF'
import importlib.util, os, sys
sys.dont_write_bytecode = True
s = importlib.util.spec_from_file_location("drv_cl", sys.argv[1]); d = importlib.util.module_from_spec(s)
s.loader.exec_module(d)
cl = sys.argv[2]
for a in sys.argv[3:]:
    nome, fase = a.split(":")
    r = d.classifica(fase, os.path.join(cl, nome + ".run"), "01-" + fase, os.path.join(cl, nome + ".md"))
    assert r.classe in d.CLASSI and tuple(r)[:4] == (r.classe, r.regola, r.causa, r.prova)
    dd = "|".join(getattr(r, "decisioni", ("(campo assente)",)))   # B8 review: the decision texts
    sys.stdout.buffer.write(("%s\t%s\t%s\t%s\t%s\t%s\n" % (nome, r.classe, r.regola, r.prova.replace(os.sep, "/").rsplit("/", 1)[-1] if r.prova.endswith(".md") else r.prova, dd, r.causa)).encode("utf-8"))
EOF
clp() { # <name> <phase> <exit> <esito line> <result.json|-> <Plan status line> [more lines of the spec]
  local n=$1 f=$2 d=$CL/$1.run/log; mkdir -p "$d"
  printf '%s
' "$3" > "$d/01-$f.exit"; printf '%s
state=abc
' "$4" > "$d/01-$f.esito"
  [ "$5" = - ] || printf '%s
' "$5" > "$d/01-$f.result.json"
  printf '# Spec

FR1. something.

## Piano di implementazione

%s
' "$6" > "$CL/$n.md"
  shift 6; [ $# -eq 0 ] || printf '%s
' "$@" >> "$CL/$n.md"
  : > "$d/01-$f.jsonl"
}
bg() { # <name> <phase>: the jsonl of a session that launched an agent in background and was woken up with it open
  printf '%s\n' '{"type":"system","subtype":"init"}' \
    '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"l1","name":"Agent","input":{"subagent_type":"maat:spec-plan-reviewer","prompt":"lens","run_in_background":true}}]}}' \
    '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"l1","content":"Async agent launched successfully.\nagentId: agx1 (internal ID)"}]}}' \
    '{"type":"system","subtype":"init"}' \
    '{"type":"result","subtype":"success","result":"STOP"}' > "$CL/$1.run/log/01-$2.jsonl"
}
rossi() { # <name> <esito> <riassunto> <json of "test"> <json of "conflitti"> [riassunto of the .rossi line, if different]
  mkdir -p "$CL/$1.run/test-red"
  printf '{"esito":"%s","riassunto":"%s","evidence":"x","conflitti":%s,"test":%s}\n' "$2" "$3" "$5" "$4" > "$CL/$1.run/test-red/rossi.json"
  printf 'rosso T1: ...\nrossi: esito=%s — %s\nstubs: ok\n' "$2" "${6:-$3}" > "$CL/$1.run/log/01-test-red.rossi"
}
# --- 14b. (1.8.0, B10, D3) the checks of the types of an Open decision: for each mechanical type a valid case (STOP,
# UMANO) and one with the line falsified by the phase itself (RIPRENDIBILE, declassata); the non-mechanical types are
# UMANO and say «decisione non verificata da script»
jl() { # <file> then pairs <command> <result>: a jsonl of the main session with those Bash calls and their results
  "$FIC_PY" - "$@" <<'EOF'
import json, sys
f, rest = sys.argv[1], sys.argv[2:]
out = ['{"type":"system","subtype":"init"}']
for i in range(0, len(rest), 2):
    out.append(json.dumps({"type": "assistant", "parent_tool_use_id": None, "message": {"content": [
        {"type": "tool_use", "id": "b%d" % i, "name": "Bash", "input": {"command": rest[i]}}]}}))
    out.append(json.dumps({"type": "user", "parent_tool_use_id": None, "message": {"content": [
        {"type": "tool_result", "tool_use_id": "b%d" % i, "content": rest[i + 1]}]}}))
out.append('{"type":"result","subtype":"success","result":"STOP"}')
open(f, "w", encoding="utf-8").write("\n".join(out) + "\n")
EOF
}
rv() { # <file> <n> <subagent_type> [<result text>]: n Agent calls of the main session, each with its result
  "$FIC_PY" - "$@" <<'EOF'
import json, sys
f, n, tipo = sys.argv[1], int(sys.argv[2]), sys.argv[3]
res = sys.argv[4] if len(sys.argv) > 4 else "Decision: NEEDS_CHANGES"
out = ['{"type":"system","subtype":"init"}']
for i in range(n):
    out.append(json.dumps({"type": "assistant", "parent_tool_use_id": None, "message": {"content": [
        {"type": "tool_use", "id": "a%d" % i, "name": "Agent", "input": {"subagent_type": tipo, "prompt": "lens"}}]}}))
    out.append(json.dumps({"type": "user", "parent_tool_use_id": None, "message": {"content": [
        {"type": "tool_result", "tool_use_id": "a%d" % i, "content": res}]}}))
open(f, "w", encoding="utf-8").write("\n".join(out) + "\n")
EOF
}
OKI=$(ok_json implement OK '[]' nessuno); STI=$(ok_json implement STOP '[]' nessuno)
OKP=$(ok_json plan OK '[]' nessuno); STP=$(ok_json plan STOP '[]' "decisione umana")
STR=$(ok_json test-red STOP '[]' nessuno); STV=$(ok_json review STOP '[]' nessuno)
AP='Plan status: APPROVED'; DR='Plan status: DRAFT'; NH='Plan status: NEEDS HUMAN DECISION'
clp tec-exit plan 4 "PHASE RESULT plan: STOP — lock" - "$DR"
clp tec-esito implement 0 "the phase said nothing useful" "$OKI" "$AP"
clp tec-nores implement 0 "PHASE RESULT implement: STOP — uscita non valida: nessun blocco JSON" - "$AP"
clp tec-fase implement 0 "PHASE RESULT implement: OK — fatto" "$(ok_json review OK '[]' nessuno)" "$AP"
clp tec-gates test-red 0 "PHASE RESULT test-red: STOP — gates" "$STR" "$AP"; echo "gates: esito=BLOCKED (no runner) chiave=- evidence=-" > "$CL/tec-gates.run/log/01-test-red.gates"
clp ok implement 0 "PHASE RESULT implement: OK — fatto" "$OKI" "$AP"
clp ok-json implement 0 "PHASE RESULT implement: OK — fatto" "$(ok_json implement OK '["passo 8 adattato"]' nessuno)" "$AP"
clp draft plan 0 "PHASE RESULT plan: STOP — round 1 not collected" "$STP" "$DR"
clp nhd-budget plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" "" "Open decision: budget — four iterations used, three majors still open"
rv "$CL/nhd-budget.run/log/01-plan.jsonl" 9 maat:spec-plan-reviewer   # (B10) the budget is counted on the transcripts
clp nhd-prova plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" "- Decisione aperta: prova — il contatore a 16 bit non regge 100000 livelli" "- Prova eseguita: \`python3 tools/depth.py 100000\` → «RecursionError: depth 65536»"
jl "$CL/nhd-prova.run/log/01-plan.jsonl" "python3 tools/depth.py 100000" "RecursionError: depth 65536"   # (B10) the executed proof
clp nhd-spec plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" "Open decision: spec — FR2 can be read in two ways and the code does not settle it"
clp nhd-assente plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH"
clp nhd-tipo plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" "Open decision: hunch — the counter looks too small"
clp nhd-forma plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" "Open decision: the counter looks too small"
clp nhd-ancora plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" "Open decision: spec — the push in src/x.rs:12 cannot go deeper"
clp nhd-recinto plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" '```' "Open decision: budget — inside a fence" '```' "### Changelog revisione piano" "Open decision: budget — in the changelog"
clp nhd-mista plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" "Open decision: spec — four iterations used" "Open decision: hunch — and a guess"
clp plan-aperti plan 0 "PHASE RESULT plan: STOP — reviews pending" "$STP" "$AP"; bg plan-aperti plan
clp plan-stop plan 0 "PHASE RESULT plan: STOP — something else" "$STP" "$AP"
clp impl-aperti implement 0 "PHASE RESULT implement: STOP — agents pending" "$STI" "$AP"; bg impl-aperti implement
clp rev-aperti review 0 "PHASE RESULT review: STOP — agents pending" "$STV" "$AP"; bg rev-aperti review
clp tr-aperti test-red 0 "PHASE RESULT test-red: STOP — judge pending" "$STR" "$AP"; bg tr-aperti test-red
clp tr-simbolo test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-simbolo STOP "T1 rosso_simbolo" '{"T1":{"esito":"rosso_simbolo","motivo":"symbol","messaggio":"./decode_test.go:12:5: undefined: MaxDepth","simbolo":"undefined: MaxDepth","posizione":null,"file":"decode_test.go","nome":"TestDepth"},"T2":{"esito":"dimostrato","motivo":"ok","messaggio":"","posizione":null,"file":"a","nome":"b"}}' '[]'
clp tr-token test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-token STOP "T1 rosso_simbolo" '{"T1":{"esito":"rosso_simbolo","motivo":"symbol","messaggio":"error[E0425]: cannot find value","posizione":null,"file":"a.rs","nome":"t"}}' '[]'
clp tr-vecchio test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-vecchio STOP "T1 rosso_simbolo" '{"T1":{"esito":"rosso_simbolo","motivo":"symbol","messaggio":"undefined: MaxDepth","simbolo":"undefined: MaxDepth","posizione":null,"file":"a","nome":"b"}}' '[]' "T1 verde"
clp tr-asserto test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-asserto STOP "T1 rosso_raccolta" '{"T1":{"esito":"rosso_raccolta","motivo":"collection","messaggio":"SyntaxError: invalid syntax","posizione":null,"file":"a","nome":"b"}}' '[]'
# (B12) a rosso_raccolta whose text is a missing symbol, without the token of rossi: the driver does not match it again
clp tr-raccolta test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-raccolta STOP "T1 rosso_raccolta" '{"T1":{"esito":"rosso_raccolta","motivo":"collection","messaggio":"./decode_test.go:12:5: undefined: MaxDepth","posizione":null,"file":"a","nome":"b"}}' '[]'
clp tr-limite test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-limite STOP "T5 limite_dimostrato" '{"T5":{"esito":"limite_dimostrato","motivo":"probe","messaggio":"TooDeeplyNested","sonda":{"decisione":"c0ffee03","affermazione":"the nesting limit","atteso":"TooDeeplyNested","riga":9},"posizione":null,"file":"a","nome":"b"}}' '[]'
regcl() { # <name> <key>: a registered .ripresa (01-plan) declassifying <key> in the run dir of a case (B11)
  printf '%s\n' "classe=RIPRENDIBILE" "regola=decisione" "fase=plan" "esito=rilancio" "n=1" "declassata: $2" > "$CL/$1.run/log/01-plan.ripresa"
  printf '2026-11-16T10:00:00Z Ripresa: 01-plan · esito=rilancio · n=1 · declassata=%s · sha=%s\n' "$2" "$(sha256sum < "$CL/$1.run/log/01-plan.ripresa" | cut -c1-12)" > "$CL/$1.run/driver.log"
}
regcl tr-limite c0ffee03   # (B11) a limite_dimostrato proves the decision only with its registered resume
clp tr-limfalso test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-limfalso STOP "T5 limite_dimostrato" '{"T5":{"esito":"limite_dimostrato","motivo":"probe","messaggio":"TooDeeplyNested","sonda":{"decisione":"c0ffee03","affermazione":"the nesting limit","atteso":"TooDeeplyNested","riga":9},"posizione":null,"file":"a","nome":"b"}}' '[]'
clp tr-conflitto test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-conflitto STOP "conflict" '{"T1":{"esito":"rosso_raccolta","motivo":"c","messaggio":"undefined: MaxDepth","posizione":null,"file":"a","nome":"b"}}' '["tests/test_old.py:3 asserts the absence of x"]'
clp tr-dev test-red 0 "PHASE RESULT test-red: STOP — JSON: deviazioni" "$(ok_json test-red OK '["passo 2 adattato"]' nessuno)" "$AP"
clp tr-okdev test-red 0 "PHASE RESULT test-red: OK — rossi dimostrati" "$(ok_json test-red OK '["test-data: T4 — other fixture names — routes collide", "difensiva: a.py:3 — ramo"]' nessuno)" "$AP"
printf 'test-data: T4 — other fixture names — routes collide\tACCEPT\t0123abcd\n' > "$CL/tr-okdev.run/log/01-test-red.deviazioni-test"
clp tr-devno test-red 0 "PHASE RESULT test-red: OK — rossi dimostrati" "$(ok_json test-red OK '["dati-test: T4 — other fixture names — routes collide"]' nessuno)" "$AP"
printf 'dati-test: T4 — other fixture names — routes collide\tSTOP — requisito non coperto\t0123abcd\n' > "$CL/tr-devno.run/log/01-test-red.deviazioni-test"
# (B8 review) a rejected test-data deviation with an open agent; a valid Open decision with an open agent; rossi
# BLOCKED; a plan OK line on a plan still DRAFT or NEEDS HUMAN DECISION
clp tr-devrif test-red 0 "PHASE RESULT test-red: STOP — judge said no" "$(ok_json test-red STOP '["test-data: T4 — other fixture names — routes collide"]' nessuno)" "$AP"; bg tr-devrif test-red
printf 'test-data: T4 — other fixture names — routes collide\tSTOP — requisito non coperto\t0123abcd\n' > "$CL/tr-devrif.run/log/01-test-red.deviazioni-test"
clp nhd-aperti plan 0 "PHASE RESULT plan: STOP — decisione" "$STP" "$NH" "Open decision: spec — four iterations used"; bg nhd-aperti plan
clp tr-blocked test-red 0 "PHASE RESULT test-red: STOP — rossi" "$STR" "$AP"
rossi tr-blocked BLOCKED "no runner" '{}' '[]'
clp plan-ok-draft plan 0 "PHASE RESULT plan: OK — done" "$OKP" "$DR"
clp plan-ok-nhd plan 0 "PHASE RESULT plan: OK — done" "$OKP" "$NH"
clp rev-nhd review 0 "PHASE RESULT review: STOP — decisione" "$STV" "$AP"; printf '\n## Review implementazione\n\nReview status: NEEDS HUMAN DECISION\n' >> "$CL/rev-nhd.md"
CASI="tec-exit:plan tec-esito:implement tec-nores:implement tec-fase:implement tec-gates:test-red ok:implement ok-json:implement draft:plan nhd-budget:plan nhd-prova:plan nhd-spec:plan nhd-assente:plan nhd-tipo:plan nhd-forma:plan nhd-ancora:plan nhd-recinto:plan nhd-mista:plan plan-aperti:plan plan-stop:plan impl-aperti:implement rev-aperti:review tr-aperti:test-red tr-simbolo:test-red tr-token:test-red tr-vecchio:test-red tr-asserto:test-red tr-raccolta:test-red tr-limite:test-red tr-limfalso:test-red tr-conflitto:test-red tr-dev:test-red tr-okdev:test-red tr-devno:test-red rev-nhd:review tr-devrif:test-red nhd-aperti:plan tr-blocked:test-red plan-ok-draft:plan plan-ok-nhd:plan"
cla() { "$FIC_PY" "$T/cl.py" "$1" "$CL" $CASI > "$T/cl.out" 2>&1; tr -d '\r' < "$T/cl.out"; }
clv() { printf '%s\n' "$CLO" | awk -F'\t' -v n="$1" '$1 == n { print $2 " " $3 " " $4 }'; }   # <name> → «class rule proof»
CLO=$(cla "$DRV")
check "classifica: la funzione si importa e risponde su tutti i casi" '[ "$(printf "%s\n" "$CLO" | grep -c "	")" = "$(echo $CASI | wc -w)" ] && ! grep -q Traceback "$T/cl.out"'
check "classifica TECNICO: .exit 4 (lock) · nessuna riga PHASE RESULT · STOP senza result.json · result.json di un'altra fase · gates BLOCKED" '[ "$(clv tec-exit)" = "TECNICO exit log/01-plan.exit" ] && [ "$(clv tec-esito)" = "TECNICO esito log/01-implement.esito" ] && [ "$(clv tec-nores)" = "TECNICO result log/01-implement.esito" ] && [ "$(clv tec-fase)" = "TECNICO result log/01-implement.result.json" ] && [ "$(clv tec-gates)" = "TECNICO blocked log/01-test-red.gates" ]'
check "classifica OK: riga OK e result.json coerente → OK; riga OK ma deviazioni nel result.json → UMANO (fail-closed)" '[ "$(clv ok)" = "OK ok log/01-implement.esito" ] && [ "$(clv ok-json)" = "UMANO json log/01-implement.result.json" ]'
check "classifica (a): plan STOP con Plan status DRAFT → RIPRENDIBILE, la prova e' log/01-plan.result.json (i rilievi aperti)" '[ "$(clv draft)" = "RIPRENDIBILE draft log/01-plan.result.json" ] && printf "%s\n" "$CLO" | grep -q "^draft	.*	piano non approvato (DRAFT)$"'
check "classifica: NEEDS HUMAN DECISION con Open decision valida (budget, «- Decisione aperta: prova», spec senza ancora) → UMANO, la prova e' la spec" '[ "$(clv nhd-budget)" = "UMANO decisione nhd-budget.md" ] && [ "$(clv nhd-prova)" = "UMANO decisione nhd-prova.md" ] && [ "$(clv nhd-spec)" = "UMANO decisione nhd-spec.md" ] && printf "%s\n" "$CLO" | grep -q "^nhd-prova	.*	decisione umana: proof — il contatore"'
check "classifica (b): NEEDS HUMAN DECISION senza riga, tipo fuori lista, forma senza «—», spec con un ancora src/x.rs:12 → RIPRENDIBILE" '[ "$(clv nhd-assente)" = "RIPRENDIBILE decisione nhd-assente.md" ] && [ "$(clv nhd-tipo)" = "RIPRENDIBILE decisione nhd-tipo.md" ] && [ "$(clv nhd-forma)" = "RIPRENDIBILE decisione nhd-forma.md" ] && [ "$(clv nhd-ancora)" = "RIPRENDIBILE decisione nhd-ancora.md" ] && printf "%s\n" "$CLO" | grep -q "^nhd-ancora	.*(src/x.rs:12)"'
check "classifica (b): una riga in un recinto o nel changelog non conta; una valida e una fuori lista → RIPRENDIBILE" '[ "$(clv nhd-recinto)" = "RIPRENDIBILE decisione nhd-recinto.md" ] && [ "$(clv nhd-mista)" = "RIPRENDIBILE decisione nhd-mista.md" ]'
check "classifica (d): plan e test-red STOP con un agente in background aperto alla chiusura → RIPRENDIBILE (prova: il jsonl); plan STOP senza → UMANO" '[ "$(clv plan-aperti)" = "RIPRENDIBILE aperti log/01-plan.jsonl" ] && [ "$(clv tr-aperti)" = "RIPRENDIBILE aperti log/01-test-red.jsonl" ] && [ "$(clv plan-stop)" = "UMANO stop log/01-plan.esito" ] && printf "%s\n" "$CLO" | grep -q "^plan-aperti	.*: agx1$"'
check "classifica (d) solo plan e test-red: implement e review STOP con lo stesso agente non raccolto → UMANO, STOP finale" '[ "$(clv impl-aperti)" = "UMANO stop log/01-implement.esito" ] && [ "$(clv rev-aperti)" = "UMANO stop log/01-review.esito" ]'
check "classifica (c): rossi di questa fase con il token rosso_simbolo (il suo «simbolo», o il messaggio) → RIPRENDIBILE" '[ "$(clv tr-simbolo)" = "RIPRENDIBILE simbolo test-red/rossi.json" ] && [ "$(clv tr-token)" = "RIPRENDIBILE simbolo test-red/rossi.json" ] && printf "%s\n" "$CLO" | grep -q "^tr-simbolo	.*stub mancanti: T1: undefined: MaxDepth$"'
check "classifica (c): rossi.json di un test-red precedente (la riga di .rossi non torna) o un errore che non e' un simbolo → UMANO" '[ "$(clv tr-vecchio)" = "UMANO stop log/01-test-red.esito" ] && [ "$(clv tr-asserto)" = "UMANO stop log/01-test-red.esito" ]'
check "classifica (c, B12): un rosso_raccolta «undefined: MaxDepth» senza il token di rossi → UMANO (driver e rossi non divergono)" '[ "$(clv tr-raccolta)" = "UMANO stop log/01-test-red.esito" ]'
check "classifica UMANO provato in test-red: limite_dimostrato, conflitto con la suite (prima del simbolo mancante), deviazione non test-data" '[ "$(clv tr-limite)" = "UMANO limite test-red/rossi.json" ] && [ "$(clv tr-conflitto)" = "UMANO conflitto test-red/rossi.json" ] && [ "$(clv tr-dev)" = "UMANO deviazione log/01-test-red.result.json" ]'
check "classifica OK-DEVIAZIONE: test-red OK con la test-data accettata in .deviazioni-test (e una difensiva); verdetto STOP → UMANO" '[ "$(clv tr-okdev)" = "OK-DEVIAZIONE deviazione-test log/01-test-red.deviazioni-test" ] && [ "$(clv tr-devno)" = "UMANO deviazione-test log/01-test-red.result.json" ]'
check "classifica: review con Review status NEEDS HUMAN DECISION → UMANO" '[ "$(clv rev-nhd)" = "UMANO review rev-nhd.md" ]'
cld() { printf '%s\n' "$CLO" | awk -F'\t' -v n="$1" '$1 == n { print $5 }'; }   # <name> → the decision texts
check "classifica (review B8): deviazione test-data rifiutata con un agente aperto → UMANO (prima di (d)); decisione valida con un agente aperto → UMANO" '[ "$(clv tr-devrif)" = "UMANO deviazione-test log/01-test-red.result.json" ] && [ "$(clv nhd-aperti)" = "UMANO decisione nhd-aperti.md" ]'
check "classifica (review B8): rossi BLOCKED → TECNICO; riga OK di un piano DRAFT o NEEDS HUMAN DECISION → UMANO (fail-closed)" '[ "$(clv tr-blocked)" = "TECNICO blocked test-red/rossi.json" ] && [ "$(clv plan-ok-draft)" = "UMANO piano plan-ok-draft.md" ] && [ "$(clv plan-ok-nhd)" = "UMANO piano plan-ok-nhd.md" ]'
check "classifica (review B8): il campo decisioni porta il testo delle Open decision (valide per UMANO, non valide per RIPRENDIBILE)" '[ "$(cld nhd-budget)" = "four iterations used, three majors still open" ] && [ "$(cld nhd-tipo)" = "the counter looks too small" ] && [ "$(cld nhd-forma)" = "the counter looks too small" ] && [ "$(cld nhd-mista)" = "and a guess" ] && [ -z "$(cld draft)" ]'
clmut() { # <name> <sed> <case> <expected class rule proof of the mutated driver>
  if tmut "$1" "$2"; then
    CLO=$(cla "$T/drv-$1.py")
    CLC=$3 CLA=$4
    check "controprova classifica ($1): $3 diventa «$4» (rosso)" '[ "$(clv "$CLC")" = "$CLA" ]'
  else check "controprova classifica ($1): la mutazione si applica" false; fi
}
clmut solo-plan 's/^\( *\)if fase in FASI_RIPRESA:  # RIPRESA-SOLO-PLAN-TEST-RED$/\1if True:/' impl-aperti "RIPRENDIBILE aperti log/01-implement.jsonl"
clmut draft 's/^\( *\)if fase == "plan" and stato.startswith("DRAFT"):  # RIPRESA-DRAFT$/\1if False:/' draft "UMANO stop log/01-plan.esito"
clmut ancora 's/^\( *\)if tipo == "spec" and a:  # SPEC-CON-ANCORA$/\1if False:/' nhd-ancora "UMANO decisione nhd-ancora.md"
clmut valida 's/^\( *\)if all(e\[1\] for e in esami):  # DECISIONE-VALIDA$/\1if any(e[1] for e in esami):/' nhd-mista "UMANO decisione nhd-mista.md"
clmut simbolo 's/^\( *\)if v.get("esito") == "rosso_simbolo":  # ROSSO-SIMBOLO$/\1if False:/' tr-simbolo "UMANO stop log/01-test-red.esito"
clmut rifiutata 's/^\( *\)if fuori:  # DEVIAZIONE-RIFIUTATA$/\1if False:/' tr-devrif "RIPRENDIBILE aperti log/01-test-red.jsonl"
clmut piano-ok 's/^\( *\)if fase == "plan" and (nhd or stato.startswith("DRAFT")):   # an OK line on a plan not approved  # PIANO-OK$/\1if False:/' plan-ok-draft "OK ok log/01-plan.esito"
check "classifica (B11): limite_dimostrato con la sonda di una ripresa registrata → UMANO limite; senza la ripresa (rossi.json scritto dalla fase) → UMANO stop" '[ "$(clv tr-limite)" = "UMANO limite test-red/rossi.json" ] && [ "$(clv tr-limfalso)" = "UMANO stop log/01-test-red.esito" ]'
clmut limite 's/^\( *\)and isinstance(v.get("sonda"), dict) and v\["sonda"\].get("decisione") in dk\]  # LIMITE-CON-RIPRESA$/\1]/' tr-limfalso "UMANO limite test-red/rossi.json"
clmut vecchio 's/^\( *\)return None  # ROSSI-DI-QUESTA-FASE$/\1pass/' tr-vecchio "RIPRENDIBILE simbolo test-red/rossi.json"
NHS="PHASE RESULT plan: STOP — decisione"
CMDP='python3 tools/depth.py 100000'
clp p-ok plan 0 "$NHS" "$STP" "$NH" "Open decision: proof — the 16-bit counter cannot hold 100000 levels" "Executed proof: \`$CMDP\` → «RecursionError: depth 65536»"
jl "$CL/p-ok.run/log/01-plan.jsonl" "$CMDP" "Traceback ...
RecursionError: depth 65536"
clp p-nessuna plan 0 "$NHS" "$STP" "$NH" "Open decision: proof — the 16-bit counter cannot hold 100000 levels"
clp p-inventata plan 0 "$NHS" "$STP" "$NH" "Open decision: proof — the 16-bit counter cannot hold 100000 levels" "Executed proof: \`$CMDP\` → «RecursionError: depth 65536»"
jl "$CL/p-inventata.run/log/01-plan.jsonl" "$CMDP" "ok: 100000 levels"
clp p-echo plan 0 "$NHS" "$STP" "$NH" "Open decision: proof — impossible" "Executed proof: \`cd src && X=1 echo impossibile \$((65535+1))\` → «65536»"
jl "$CL/p-echo.run/log/01-plan.jsonl" "cd src && X=1 echo impossibile \$((65535+1))" "impossibile 65536"
clp p-pyc plan 0 "$NHS" "$STP" "$NH" "Open decision: prova — impossible" "- Prova eseguita: \`python -c 'print(\"impossibile\")'\` → «impossibile»"
jl "$CL/p-pyc.run/log/01-plan.jsonl" "python -c 'print(\"impossibile\")'" "impossibile"
clp p-spec plan 0 "$NHS" "$STP" "$NH" "Open decision: proof — impossible" "Executed proof: \`$CMDP\` → «something»"
jl "$CL/p-spec.run/log/01-plan.jsonl" "$CMDP" "something"
clp p-side plan 0 "$NHS" "$STP" "$NH" "Open decision: proof — the 16-bit counter cannot hold 100000 levels" "Executed proof: \`$CMDP\` → «RecursionError: depth 65536»"
printf '%s\n' '{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"s1","name":"Bash","input":{"command":"python3 tools/depth.py 100000"}}]}}' \
  '{"type":"user","isSidechain":true,"message":{"content":[{"type":"tool_result","tool_use_id":"s1","content":"RecursionError: depth 65536"}]}}' > "$CL/p-side.run/log/01-plan.jsonl"
clp b-ok plan 0 "$NHS" "$STP" "$NH" "Open decision: budget — four iterations used, three majors still open"
rv "$CL/b-ok.run/log/01-plan.jsonl" 6 maat:spec-plan-reviewer; rv "$CL/b-ok.run/log/02-plan.jsonl" 3 maat:spec-plan-reviewer; echo 0 > "$CL/b-ok.run/log/02-plan.exit"
clp b-giri plan 0 "$NHS" "$STP" "$NH" "Open decision: budget — four iterations used" "### Plan review changelog" "Metrica ciclo: giri=4 · R1=2/3 · esito=stop"
rv "$CL/b-giri.run/log/01-plan.jsonl" 3 maat:spec-plan-reviewer
clp b-light plan 0 "$NHS" "$STP" "$NH" "Open decision: budget — the one round of the small size said stop"
rv "$CL/b-light.run/log/01-plan.jsonl" 1 maat:spec-plan-reviewer-light "Decision: STOP_HUMAN_DECISION_REQUIRED
Coverage statement: all"
clp b-light-ok plan 0 "$NHS" "$STP" "$NH" "Open decision: budget — the one round of the small size said stop"
rv "$CL/b-light-ok.run/log/01-plan.jsonl" 1 maat:spec-plan-reviewer-light "Decision: APPROVED"
riempi() { local i=0; while [ $i -lt 410 ]; do echo "- line $i of a long plan"; i=$((i + 1)); done; }
clp c-ok plan 0 "$NHS" "$STP" "$NH" "Open decision: taglio — skeleton above the ceiling, cut proposal in 2 rings" "Plan format: 2" "$(riempi)"
clp c-sotto plan 0 "$NHS" "$STP" "$NH" "Open decision: cut — skeleton above the ceiling, cut proposal in 2 rings" "Plan format: 2" "### Plan review changelog" "scheletro sopra il tetto: proposta di taglio in 2 anelli"
scope_spec() { # <name> <decision text>: a spec with requirements and an Out of scope section above the plan
  printf '%s\n' "# Spec" "" "## Functional requirements" "" "- FR1. Export the report." "- FR2. Sort it." "" "## Out of scope" "" \
    "- The export to CSV stays out of this change." "" "## Implementation plan" "" "$NH" "Open decision: scope — $2" > "$CL/$1.md"
}
clp s-ok plan 0 "$NHS" "$STP" "$NH"; scope_spec s-ok "FR1 needs a CSV file, but the spec says «The export to CSV stays out of this change.»"
clp s-inventata plan 0 "$NHS" "$STP" "$NH"; scope_spec s-inventata "FR1 needs a CSV file, but the spec says «The export to XLSX stays out.»"
clp s-noid plan 0 "$NHS" "$STP" "$NH"; scope_spec s-noid "the report needs a CSV file, but «The export to CSV stays out of this change.»"
for ty in recurrence ricorrenza dispute partial; do
  clp nm-$ty plan 0 "$NHS" "$STP" "$NH" "Open decision: $ty — the same major again, no new evidence"
done
clp nm-dopo plan 0 "$NHS" "$STP" "$NH" "Open decision: spec — FR2 can be read in two ways"
printf '%s\n' "classe=RIPRENDIBILE" "regola=decisione" "fase=plan" "esito=rilancio" "n=1" "declassata: 0badc0de" > "$CL/nm-dopo.run/log/00-plan.ripresa"
printf '2026-11-16T10:00:00Z Ripresa: 00-plan · esito=rilancio · n=1 · declassata=0badc0de · sha=%s\n' "$(sha256sum < "$CL/nm-dopo.run/log/00-plan.ripresa" | cut -c1-12)" > "$CL/nm-dopo.run/driver.log"
# (B10-B11 review) the DOPO-DECLASSATA signal from driver.log (the .ripresa deleted); more ways around the printing filter;
# two proofs under one decision, one forged; the R<n> ids of a «## Requisiti» section
clp nm-dopo-del plan 0 "$NHS" "$STP" "$NH" "Open decision: spec — FR2 can be read in two ways"
printf '2026-11-16T10:00:00Z Ripresa: 00-plan · esito=rilancio · n=1 · declassata=0badc0de · sha=000000000000\n' > "$CL/nm-dopo-del.run/driver.log"
for c in "p-cdsemi|cd src; printf 'impossibile %s' 65536|impossibile 65536" "p-gitshow|git show HEAD:src/name.rs|let depth: u16 = 0;" \
         "p-shc|bash -c 'cat src/name.rs'|let depth: u16 = 0;" "p-env|env X=1 nice -n 5 rg u16 src|let depth: u16 = 0;" \
         "p-graffa|{ tr a-z A-Z < src/name.rs; }|LET DEPTH: U16" \
         "p-nopager|git --no-pager show HEAD:src/name.rs|let depth: u16 = 0;" "p-gitp|git -P grep -n u16|let depth: u16 = 0;" \
         "p-gitc|git -c core.pager=cat show HEAD:src/name.rs|let depth: u16 = 0;" \
         "p-gitdir|git --git-dir=.git show HEAD:src/name.rs|let depth: u16 = 0;" "p-usrenv|/usr/bin/env cat src/name.rs|let depth: u16 = 0;" \
         "p-bashl|bash -l -c 'cat src/name.rs'|let depth: u16 = 0;" "p-timeout|timeout 5 cat src/name.rs|let depth: u16 = 0;" \
         "p-backslash|\\cat src/name.rs|let depth: u16 = 0;" "p-stdbuf|stdbuf -oL cat src/name.rs|let depth: u16 = 0;" \
         "p-xargs|xargs cat < files.txt|let depth: u16 = 0;"; do
  IFS='|' read -r nm cmd res <<< "$c"
  clp "$nm" plan 0 "$NHS" "$STP" "$NH" "Open decision: proof — the 16-bit counter cannot hold 100000 levels" "Executed proof: \`$cmd\` → «$res»"
  jl "$CL/$nm.run/log/01-plan.jsonl" "$cmd" "$res"
done
clp p-due plan 0 "$NHS" "$STP" "$NH" "Open decision: proof — the 16-bit counter cannot hold 100000 levels" "Executed proof: \`$CMDP\` → «RecursionError: depth 65536»" "Executed proof: \`python3 tools/depth.py 7\` → «RecursionError: depth 7»"
jl "$CL/p-due.run/log/01-plan.jsonl" "$CMDP" "RecursionError: depth 65536"
clp s-r plan 0 "$NHS" "$STP" "$NH"
printf '%s\n' "# Spec" "" "## Requisiti" "" "- R1. Esportare il report." "" "## Fuori ambito" "" "- L'esportazione in CSV resta fuori da questa modifica." "" \
  "## Piano di implementazione" "" "$NH" "Open decision: scope — R1 vuole un file CSV, ma la spec dice «L'esportazione in CSV resta fuori da questa modifica.»" > "$CL/s-r.md"
CASI="p-ok:plan p-nessuna:plan p-inventata:plan p-echo:plan p-pyc:plan p-spec:plan p-side:plan b-ok:plan b-giri:plan b-light:plan b-light-ok:plan c-ok:plan c-sotto:plan s-ok:plan s-inventata:plan s-noid:plan nm-recurrence:plan nm-ricorrenza:plan nm-dispute:plan nm-partial:plan nm-dopo:plan nhd-spec:plan nm-dopo-del:plan p-cdsemi:plan p-gitshow:plan p-shc:plan p-env:plan p-graffa:plan p-due:plan s-r:plan p-nopager:plan p-gitp:plan p-gitc:plan p-gitdir:plan p-usrenv:plan p-bashl:plan p-timeout:plan p-backslash:plan p-stdbuf:plan p-xargs:plan"
CLO=$(cla "$DRV")
check "tipi: la funzione risponde su tutti i casi nuovi" '[ "$(printf "%s\n" "$CLO" | grep -c "	")" = "$(echo $CASI | wc -w)" ] && ! grep -q Traceback "$T/cl.out"'
cln() { printf '%s\n' "$CLO" | awk -F'\t' -v n="$1" '$1 == n { print $6 }'; }   # <name> → the cause
check "proof: Executed proof trovata nel jsonl della fase (comando esatto, estratto nel risultato) → UMANO, lo STOP che deve ancora fermarsi" '[ "$(clv p-ok)" = "UMANO decisione p-ok.md" ]'
check "proof falsificata → RIPRENDIBILE: senza riga, estratto non nel risultato, echo dopo cd e VAR=, estratto nel comando (python -c), estratto copiato dalla spec, solo in un sidechain" '[ "$(clv p-nessuna)" = "RIPRENDIBILE decisione p-nessuna.md" ] && [ "$(clv p-inventata)" = "RIPRENDIBILE decisione p-inventata.md" ] && [ "$(clv p-echo)" = "RIPRENDIBILE decisione p-echo.md" ] && [ "$(clv p-pyc)" = "RIPRENDIBILE decisione p-pyc.md" ] && [ "$(clv p-spec)" = "RIPRENDIBILE decisione p-spec.md" ] && [ "$(clv p-side)" = "RIPRENDIBILE decisione p-side.md" ]'
check "  le cause: prova assente, non trovata nel jsonl, comando che stampa, estratto scritto nel comando o nella spec" 'cln p-nessuna | grep -q "senza una riga Prova eseguita" && cln p-inventata | grep -q "non trovata in log/01-plan.jsonl" && cln p-echo | grep -q "stampa soltanto" && cln p-pyc | grep -q "estratto scritto nel comando o nella spec" && cln p-spec | grep -q "estratto scritto nel comando o nella spec"'
check "budget: 9 risultati di maat:spec-plan-reviewer nei jsonl delle fasi plan (6+3) → UMANO; giri=4 nella metrica ma 3 risultati → RIPRENDIBILE" '[ "$(clv b-ok)" = "UMANO decisione b-ok.md" ] && [ "$(clv b-giri)" = "RIPRENDIBILE decisione b-giri.md" ] && cln b-giri | grep -q "con 3 risultati"'
check "budget, taglia piccola: il risultato del revisore leggero con E1: STOP (rieseguito) → UMANO; con APPROVED → RIPRENDIBILE" '[ "$(clv b-light)" = "UMANO decisione b-light.md" ] && [ "$(clv b-light-ok)" = "RIPRENDIBILE decisione b-light-ok.md" ]'
check "cut: skeleton rieseguito SOPRA IL TETTO (exit 1) → UMANO; la nota di taglio nel changelog ma skeleton sotto il tetto → RIPRENDIBILE" '[ "$(clv c-ok)" = "UMANO decisione c-ok.md" ] && [ "$(clv c-sotto)" = "RIPRENDIBILE decisione c-sotto.md" ]'
check "scope: riga di Out of scope citata ed esistente + ID FR1 → UMANO; riga inventata, o senza ID di requisito → RIPRENDIBILE" '[ "$(clv s-ok)" = "UMANO decisione s-ok.md" ] && [ "$(clv s-inventata)" = "RIPRENDIBILE decisione s-inventata.md" ] && [ "$(clv s-noid)" = "RIPRENDIBILE decisione s-noid.md" ]'
check "non meccanici (recurrence, ricorrenza, dispute, partial, spec): UMANO con «decisione non verificata da script: <tipo>»" 'for x in nm-recurrence nm-ricorrenza nm-dispute nm-partial; do [ "$(clv $x)" = "UMANO decisione $x.md" ] || exit 1; done; cln nm-ricorrenza | grep -q "· decisione non verificata da script: recurrence$" && cln nm-partial | grep -q "decisione non verificata da script: partial$" && cln nhd-spec | grep -q "decisione non verificata da script: spec$"'
check "non meccanico dopo una ripresa che aveva declassato una chiave → UMANO e «dopo la ripresa che aveva declassato <chiave>»" '[ "$(clv nm-dopo)" = "UMANO decisione nm-dopo.md" ] && cln nm-dopo | grep -q "decisione non verificata da script: spec · dopo la ripresa che aveva declassato 0badc0de$" && ! cln nhd-spec | grep -q "dopo la ripresa"'
check "(review B10-B11) dopo una declassata il cui .ripresa e' stato cancellato: il segnale viene da driver.log (DA10)" '[ "$(clv nm-dopo-del)" = "UMANO decisione nm-dopo-del.md" ] && cln nm-dopo-del | grep -q "dopo la ripresa che aveva declassato 0badc0de$"'
check "(review B10-B11) filtro: «cd x;», git show, bash -c '"'"'cat'"'"', env/nice + rg, «{ tr …; }» → comando che stampa, RIPRENDIBILE" '(for x in p-cdsemi p-gitshow p-shc p-env p-graffa; do [ "$(clv $x)" = "RIPRENDIBILE decisione $x.md" ] && cln $x | grep -q "stampa soltanto" || exit 1; done)'
check "(review B12-B13) filtro: git --no-pager/-P/-c/--git-dir, /usr/bin/env, bash -l -c, timeout 5, \\cat, stdbuf, xargs → comando che stampa, RIPRENDIBILE" '(for x in p-nopager p-gitp p-gitc p-gitdir p-usrenv p-bashl p-timeout p-backslash p-stdbuf p-xargs; do [ "$(clv $x)" = "RIPRENDIBILE decisione $x.md" ] && cln $x | grep -q "stampa soltanto" || { echo "$x: $(clv $x)"; exit 1; }; done)'
check "(review B10-B11) due Executed proof sotto una decisione, la seconda inventata → RIPRENDIBILE" '[ "$(clv p-due)" = "RIPRENDIBILE decisione p-due.md" ] && cln p-due | grep -q "non trovata in log/01-plan.jsonl"'
check "(review B10-B11) scope con «## Requisiti» e l ID R1 delle spec di Maat → UMANO" '[ "$(clv s-r)" = "UMANO decisione s-r.md" ]'
if tmut dopodel 's/^\( *\)dk = declassate_registro(run_fs) .*$/\1dk = sorted(set(k for _l, r in riprese(run_fs)[0] for k in r.get("declassata") or []))/'; then
  CLO=$(cla "$T/drv-dopodel.py")
  check "controprova dopodel: con le declassate lette dai .ripresa il segnale sparisce col file (rosso)" '! cln nm-dopo-del | grep -q "dopo la ripresa"'
else check "controprova dopodel: la mutazione si applica" false; fi
clmut puntoevirgola 's/\[ \\t\]\*(?:&&|;)\[ \\t\]\*"),$/[ \\t]*\&\&[ \\t]*"),/' p-cdsemi "UMANO decisione p-cdsemi.md"
clmut gitshow 's/^STAMPA_GIT = ("grep", "show")$/STAMPA_GIT = ()/' p-gitshow "UMANO decisione p-gitshow.md"
clmut shc 's/^\( *\)s = _SHELL_C.match(t)$/\1s = None/' p-shc "UMANO decisione p-shc.md"
clmut envp 's/(?:env|command|exec|time|nice|builtin|timeout|stdbuf|xargs|nohup)/(?:NIENTE)/' p-env "UMANO decisione p-env.md"
clmut gitopz 's/^\( *\)g = _GIT_SUB.match(t)  # GIT-OPZIONI$/\1g = re.match(r"git(?:[ \\t]+-[Cc][ \\t]+\\S+)*[ \\t]+(\\S+)", t)/' p-nopager "UMANO decisione p-nopager.md"
clmut copiato 's/^\( *\)if estr in cmd or estr in "\\n".join(_sopra_piano(spec_fs)):$/\1if False:/' p-pyc "UMANO decisione p-pyc.md"
clmut leggero 's/^\( *\)if rc == 0 and any(l.startswith("E1: STOP") for l in .*$/\1if False:/' b-light "RIPRENDIBILE decisione b-light.md"
clmut reqr 's/(?:RF|CA|FR|AC|R)\[0-9\]+/(?:RF|CA|FR|AC)[0-9]+/' s-r "RIPRENDIBILE decisione s-r.md"
CLO=$(cla "$DRV")
clmut jsonl 's/^\( *\)trov = tr.bash_trovato(.*# PROVA-NEL-JSONL$/\1trov = True/' p-inventata "UMANO decisione p-inventata.md"
clmut stampa 's/^\( *\)return p in STAMPA  # FILTRO-STAMPA$/\1return False/' p-echo "UMANO decisione p-echo.md"
clmut budget 's/^\( *\)if n >= BUDGET_RISULTATI:  # BUDGET-CONTATO$/\1if True:/' b-giri "UMANO decisione b-giri.md"
clmut taglio 's/^\( *\)if rc == 1 and "Scheletro: SOPRA IL TETTO" in out:  # TAGLIO-RIESEGUITO$/\1if True:/' c-sotto "UMANO decisione c-sotto.md"
clmut ambito 's/^\( *\)if not any(c in t for c in citabili):  # AMBITO-CITATO$/\1if False:/' s-inventata "UMANO decisione s-inventata.md"
clmut tipo 's/^\( *\)if not vale:  # CONTROLLO-DEL-TIPO$/\1if False:/' p-nessuna "UMANO decisione p-nessuna.md"
rm -f "$T"/drv-jsonl.py "$T"/drv-stampa.py "$T"/drv-budget.py "$T"/drv-taglio.py "$T"/drv-ambito.py "$T"/drv-tipo.py
rm -f "$T"/drv-envp.py "$T"/drv-graffa.py "$T"/drv-gitopz.py
rm -f "$T"/drv-dopodel.py "$T"/drv-puntoevirgola.py "$T"/drv-gitshow.py "$T"/drv-shc.py "$T"/drv-copiato.py "$T"/drv-leggero.py "$T"/drv-reqr.py
rm -rf "$CL" "$T"/drv-solo-plan.py "$T"/drv-draft.py "$T"/drv-ancora.py "$T"/drv-valida.py "$T"/drv-simbolo.py "$T"/drv-vecchio.py "$T"/drv-rifiutata.py "$T"/drv-piano-ok.py "$T"/drv-limite.py


# --- 15. (1.8.0, B9) the resumes in run: a fake run-phase.sh whose phases end STOP as run-phase writes them (.exit 0,
# .esito, a valid result.json, the jsonl), FAKE_MODE chooses what the phase does to the spec. The first word of Next
# and the State come from the real `next` (rows R1-R3). Every rule has its counterproof on a mutated copy (tmut).
SR=$CW/spec-r.md; RR=$CW/spec-r.run
spec_r() { printf '%s\n' "# R" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." "## Piano di implementazione" \
  "Plan status: ${1:-DRAFT}" "Test level: std" "### Passi" "1. Modificare \`src/a.py\`." > "$SR"; }
cat > "$T/rp-ripresa" <<'EOF'
#!/usr/bin/env bash
# fake run-phase.sh for the resumes: <run-dir> <label> <prompt>
d=$1 l=$2; mkdir -p "$d/log"; echo "$l" >> "$FAKE_CALLS"; spec="${d%.run}.md"; cp "$3" "$FAKE_CALLS.$l.prompt"
ph=${l#*-}; fnd=""; bloc=nessuno; es=STOP; riga="PHASE RESULT $ph: STOP — round 1 not collected"
: > "$d/log/$l.jsonl"
case "$FAKE_MODE" in
  draft) printf '%s\n' "2. Passo aggiunto da $l." >> "$spec" ;;   # progress: the plan changes at every phase
  ok) riga="PHASE RESULT $ph: OK — done"; es=OK ;;
  ok-draft) riga="PHASE RESULT $ph: OK — done"; es=OK; printf '%s\n' "2. Passo aggiunto da $l." >> "$spec" ;;   # (B9 review) OK on a DRAFT
  draft-cancella|draft-altera) printf '%s\n' "2. Passo aggiunto da $l." >> "$spec"   # (DA10) the phase touches a .ripresa
    if [ "$l" = 02-plan ]; then
      if [ "$FAKE_MODE" = draft-cancella ]; then rm -f "$d/log/01-plan.ripresa"; else echo "n=0" >> "$d/log/01-plan.ripresa"; fi
    fi ;;
  tr-uguale|tr-diverso) mkdir -p "$d/test-red"; riga="PHASE RESULT test-red: STOP — rossi"   # (DA9) a missing symbol
    sym=MaxDepth; [ "$FAKE_MODE" = tr-diverso ] && sym="Max${l%%-*}"
    printf '{"esito":"STOP","riassunto":"T1 rosso_simbolo","evidence":"x","conflitti":[],"test":{"T1":{"esito":"rosso_simbolo","motivo":"symbol","messaggio":"./decode_test.go:12:5: undefined: %s","simbolo":"undefined: %s","posizione":null,"file":"decode_test.go","nome":"TestDepth"}}}\n' "$sym" "$sym" > "$d/test-red/rossi.json"
    printf 'rossi: esito=STOP — T1 rosso_simbolo\n' > "$d/log/$l.rossi" ;;
  draft-fermo) fnd='{"severita":"major","file":"src/a.py","riga":1,"testo":"the same finding"}' ;;   # no progress
  nhd-valida|nhd-tipo|nhd-proof|nhd-budget) sed -i 's/^Plan status: DRAFT$/Plan status: NEEDS HUMAN DECISION/' "$spec"; bloc="decisione umana"
    case "$FAKE_MODE" in
      nhd-valida) printf '%s\n' "Open decision: spec — FR1 can be read in two ways and the code does not settle it" >> "$spec" ;;
      nhd-proof) printf '%s\n' "Open decision: proof — the counter looks too small ($l)" >> "$spec" ;;   # no Executed proof
      nhd-budget) printf '%s\n' "Open decision: budget — four iterations used ($l)" >> "$spec" ;;   # no reviewer in the jsonl
      *) printf '%s\n' "Open decision: hunch — the counter looks too small ($l)" >> "$spec" ;;
    esac ;;
  ok-nhd) riga="PHASE RESULT $ph: OK — done"; es=OK; bloc="decisione umana"   # (B10-B11 review) OK line, a valid spec decision
    sed -i 's/^Plan status: DRAFT$/Plan status: NEEDS HUMAN DECISION/' "$spec"
    printf '%s\n' "Open decision: spec — FR1 can be read in two ways and the code does not settle it" >> "$spec" ;;
  tr-rilievi) mkdir -p "$d/test-red"; riga="PHASE RESULT test-red: STOP — rossi"   # (DA9) same symbol, other findings
    fnd='{"severita":"minor","file":"a.go","riga":1,"testo":"finding of '"$l"'"}'
    printf '{"esito":"STOP","riassunto":"T1 rosso_simbolo","evidence":"x","conflitti":[],"test":{"T1":{"esito":"rosso_simbolo","motivo":"symbol","messaggio":"./decode_test.go:12:5: undefined: MaxDepth","simbolo":"undefined: MaxDepth","posizione":null,"file":"decode_test.go","nome":"TestDepth"}}}\n' > "$d/test-red/rossi.json"
    printf 'rossi: esito=STOP — T1 rosso_simbolo\n' > "$d/log/$l.rossi" ;;
  impl-bg) riga="PHASE RESULT implement: STOP — agents pending"
    printf '%s\n' '{"type":"system","subtype":"init"}' \
      '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"l1","name":"Agent","input":{"subagent_type":"maat:plan-implementer","prompt":"lane","run_in_background":true}}]}}' \
      '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"l1","content":"Async agent launched successfully.\nagentId: agz1 (internal ID)"}]}}' \
      '{"type":"system","subtype":"init"}' '{"type":"result","subtype":"success","result":"STOP"}' > "$d/log/$l.jsonl" ;;
esac
printf '{"fase":"%s","esito":"%s","motivo":"m","deviazioni":[],"bloccato_su":"%s","file":[],"gate_interni":[],"finding":[%s]}\n' "$ph" "$es" "$bloc" "$fnd" > "$d/log/$l.result.json"
printf '%s\nstate=x\n' "$riga" > "$d/log/$l.esito"; echo 0 > "$d/log/$l.exit"
exit 0
EOF
chmod +x "$T/rp-ripresa"
rrun() { # $1 FAKE_MODE, then variables → rc, $T/run.out (the run dir is kept: a second invocation reads it)
  rm -f "$FAKE_CALLS"*; : > "$FAKE_CALLS"
  env "${@:2}" FAKE_MODE=$1 FIC_RUN_PHASE="$T/rp-ripresa" FIC_CONTEXT_PACK=- "$FIC_PY" "${RRUN_DRV:-$DRV}" run "$SR" > "$T/run.out" 2>&1; rc=$?; }
rnuovo() { rm -rf "$RR"; spec_r "${1:-DRAFT}"; }
rcalls() { tr '\n' ' ' < "$FAKE_CALLS"; }
rf() { sed -n "s/^$2=//p" "$RR/log/$1.ripresa" 2>/dev/null | tr -d '\r'; }   # <label> <field> of a .ripresa
rnuovo; rrun draft
check "ripresa: plan STOP con la spec DRAFT → log/01-plan.ripresa esito=rilancio n=1, la riga in driver.log" '[ "$(rf 01-plan esito) $(rf 01-plan n) $(rf 01-plan classe) $(rf 01-plan regola)" = "rilancio 1 RIPRENDIBILE draft" ] && grep -q " Ripresa: 01-plan · esito=rilancio · n=1 · declassata=- · sha=[0-9a-f]\{12\}$" "$RR/driver.log"'
check "  02-plan col prompt «RIPRESA (driver): 1/2 — piano non approvato (DRAFT) — rilievi aperti: log/01-plan.result.json»" 'grep -qx "RIPRESA (driver): 1/2 — piano non approvato (DRAFT) — rilievi aperti: log/01-plan.result.json" "$FAKE_CALLS.02-plan.prompt" && ! grep -q "RIPRESA" "$FAKE_CALLS.01-plan.prompt"'
check "  terza volta → 03-plan.ripresa esito=limite, STOP «limite delle riprese» (exit 1), nessun 04-plan" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan 02-plan 03-plan " ] && [ "$(rf 02-plan esito)" = rilancio ] && grep -q "^RIPRESA (driver): 2/2 — " "$FAKE_CALLS.03-plan.prompt" && [ "$(rf 03-plan esito) $(rf 03-plan n)" = "limite 2" ] && grep -q "Driver result: STOP — limite delle riprese: 2/3 nel ciclo, 2/2 per plan: piano non approvato (DRAFT)" "$T/run.out"'
cp -r "$RR" "$T/rr-limite"; cp "$SR" "$T/sr-limite"
rrun draft
check "ripresa: seconda invocazione dopo il limite, stessa run dir e spec ancora DRAFT → STOP senza lanci" '[ $rc -eq 1 ] && [ "$(rcalls)" = "" ] && grep -q "Driver result: STOP — STOP — 03-plan fermata: limite delle riprese" "$T/run.out"'
rlim() { rm -rf "$RR"; cp -r "$T/rr-limite" "$RR"; cp "$T/sr-limite" "$SR"; }
if tmut r2 's/^\( *\)if d.get("esito") in ("limite", "senza-progresso"):  # RIPRESA-STOP$/\1if False:/'; then
  rlim; RRUN_DRV="$T/drv-r2.py" rrun draft
  check "  senza la riga R2 la riga R3 (DRAFT con .ripresa limite e State uguale) tiene da sola: STOP senza lanci" '[ $rc -eq 1 ] && [ "$(rcalls)" = "" ] && grep -q "Driver result: STOP — STOP — 03-plan fermata: limite delle riprese" "$T/run.out"'
else check "controprova R2: la mutazione si applica" false; fi
if tmut r23 's/^\( *\)if d.get("esito") in ("limite", "senza-progresso"):  # RIPRESA-STOP$/\1if False:/; s/^\( *\)if dp and .*# DRAFT-LIMITE$/\1if False:/'; then
  rlim; RRUN_DRV="$T/drv-r23.py" rrun draft
  check "controprova: senza R2 ne R3 la riga DRAFT → PLAN rilancia il piano oltre il limite (04-plan: rosso)" '[ "$(rcalls)" = "04-plan " ]'
else check "controprova R2+R3: la mutazione si applica" false; fi
rlim; sed -i 's/^Contesto\.$/Contesto cambiato./' "$SR"; rrun draft
check "ripresa: dopo una modifica della spec (State diverso) il ciclo riparte (04-plan) e il contatore resta quello del ciclo: subito al limite" '[ $rc -eq 1 ] && [ "$(rcalls)" = "04-plan " ] && [ "$(rf 04-plan esito)" = limite ] && ! grep -q "RIPRESA" "$FAKE_CALLS.04-plan.prompt"'
if tmut cl 's/^\( *\)c = classifica(fase, run_fs, label, spec_fs) if rmax > 0 else None  # CLASSIFICA$/\1c = None/'; then
  rnuovo; RRUN_DRV="$T/drv-cl.py" rrun draft
  check "controprova: senza classifica (lo STOP della 1.7) il primo caso finisce STOP dopo 01-plan, nessuna .ripresa (rosso)" '[ "$(rcalls)" = "01-plan " ] && [ ! -f "$RR/log/01-plan.ripresa" ]'
else check "controprova classifica: la mutazione si applica" false; fi
rnuovo; rrun draft-fermo
check "ripresa senza progresso: stessa impronta del piano e stessi rilievi → 02-plan.ripresa esito=senza-progresso, STOP con la causa" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan 02-plan " ] && [ "$(rf 02-plan esito)" = senza-progresso ] && grep -q "Driver result: STOP — ripresa senza progresso (stesso piano, stessi rilievi aperti): piano non approvato (DRAFT)" "$T/run.out"'
check "  il rilancio con lo State invariato non e il vecchio anti-loop: la chiave e (word, state, n_ripresa)" '! grep -q "anti-loop" "$T/run.out" && [ -n "$(rf 01-plan rilievi | grep -x "[0-9a-f]\{8\}")" ]'
if tmut progresso 's/^\( *\)if uguale:  # PROGRESSO$/\1if False:/'; then
  rnuovo; RRUN_DRV="$T/drv-progresso.py" rrun draft-fermo
  check "controprova: senza il controllo del progresso il caso arriva al limite, non alla causa (rosso)" '[ "$(rcalls)" = "01-plan 02-plan 03-plan " ] && grep -q "Driver result: STOP — limite delle riprese" "$T/run.out"'
else check "controprova progresso: la mutazione si applica" false; fi
if tmut chiave 's/ and state == prev\[1\] and nrip == prev\[3\]:  # ANTI-LOOP$/ and state == prev[1]:  # ANTI-LOOP/'; then
  rnuovo; RRUN_DRV="$T/drv-chiave.py" rrun draft-fermo
  check "controprova: con la chiave (word, state) di 1.7 il rilancio a State invariato e un anti-loop (rosso)" 'grep -q "Driver result: STOP — anti-loop" "$T/run.out" && [ "$(rcalls)" = "01-plan " ]'
else check "controprova chiave anti-loop: la mutazione si applica" false; fi
# final STOPs: an implement with an agent not collected ((d) only plan and test-red), a valid Open decision
rnuovo APPROVED; rrun impl-bg
check "ripresa: implement STOP con un agente in background non raccolto → STOP finale, nessuna ripresa, la prova nella riga" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-implement " ] && [ ! -f "$RR/log/01-implement.ripresa" ] && grep -q "Driver result: STOP — PHASE RESULT implement: STOP — agents pending · prova: .*spec-r.run/log/01-implement.esito" "$T/run.out"'
rnuovo; rrun nhd-valida
check "ripresa: plan NEEDS HUMAN DECISION con Open decision: spec valida → STOP finale, nessun rilancio (non sovra-accetta)" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan " ] && [ ! -f "$RR/log/01-plan.ripresa" ] && grep -q "· prova: .*spec-r.md" "$T/run.out"'
rnuovo; rrun nhd-proof FIC_RIPRESE=1
K=$(printf '%s' "the counter looks too small (01-plan)" | sha256sum | cut -c1-8)
check "ripresa: Open decision proof senza prova → RIPRENDIBILE, «declassata: <chiave>» nel .ripresa e in driver.log; FIC_RIPRESE=1 → limite alla seconda" '[ "$(rcalls)" = "01-plan 02-plan " ] && grep -qx "declassata: $K" "$RR/log/01-plan.ripresa" && grep -q " Ripresa: 01-plan · esito=rilancio · n=1 · declassata=$K · " "$RR/driver.log" && [ "$(rf 02-plan esito) $(rf 02-plan max)" = "limite 1" ]'
# (B10-B11 review, D3.1) only a claim about the code is declassified: a type out of the list or a falsified budget are
# relaunched with the generic line (cause + result.json of the stopped phase), no declassata:, so no probe can use the key
for m in nhd-tipo nhd-budget; do
  rnuovo; rrun $m FIC_RIPRESE=1
  check "ripresa (review B10-B11, $m): RIPRENDIBILE senza «declassata:» (.ripresa e driver.log declassata=-), riga generica col result.json" '[ "$(rcalls)" = "01-plan 02-plan " ] && [ "$(rf 01-plan esito) $(rf 01-plan regola)" = "rilancio decisione" ] && ! grep -q "^declassata: " "$RR/log/01-plan.ripresa" && grep -q " Ripresa: 01-plan · esito=rilancio · n=1 · declassata=- · " "$RR/driver.log" && grep -q "^RIPRESA (driver): 1/1 — .* — rilievi aperti: log/01-plan.result.json$" "$FAKE_CALLS.02-plan.prompt" && ! grep -q "decisione umana senza prova eseguita" "$FAKE_CALLS.02-plan.prompt"'
done
KB=$(printf '%s' "four iterations used (01-plan)" | sha256sum | cut -c1-8)
cat > "$T/declassate.py" <<'EOF'
import importlib.util, sys
sys.dont_write_bytecode = True
s = importlib.util.spec_from_file_location("drv_dk", sys.argv[1]); d = importlib.util.module_from_spec(s); s.loader.exec_module(d)
print(" ".join(k for _l, r in d.riprese(sys.argv[2])[0] for k in r.get("declassata") or []))
EOF
check "  budget falsificato: la sua chiave non e' fra le declassate delle riprese registrate (quelle che lint2 e rossi leggono)" '[ -z "$("$FIC_PY" "$T/declassate.py" "$DRV" "$RR" | tr -d "\r")" ] && ! grep -q "$KB" "$RR/driver.log"'
if tmut declassa 's/^\( *\)return tipo == "proof" or .*# DECLASSA-SOLO-PROOF$/\1return True/'; then
  rnuovo; RRUN_DRV="$T/drv-declassa.py" rrun nhd-budget FIC_RIPRESE=1
  check "controprova: declassando ogni decisione non valida il budget falsificato ha «declassata: <chiave>» (rosso)" 'grep -qx "declassata: $KB" "$RR/log/01-plan.ripresa"'
else check "controprova declassa: la mutazione si applica" false; fi
rm -f "$T/drv-declassa.py"
# off: FIC_RIPRESE=0 and ciclo.riprese 0 give the STOP of 1.7
rnuovo; rrun draft FIC_RIPRESE=0
check "ripresa spenta: FIC_RIPRESE=0 → STOP con la riga della fase dopo 01-plan, nessuna .ripresa (1.7)" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan " ] && [ ! -f "$RR/log/01-plan.ripresa" ] && grep -q "Driver result: STOP — PHASE RESULT plan: STOP — round 1 not collected$" "$T/run.out"'
printf '%s\n' '{"versione_schema":1,"harness":">=1.8","moduli":[{"nome":"a","radice":"."}],"ciclo":{"riprese":0}}' > "$T/maat-r0.json"
rnuovo; rrun draft MAAT_CONFIG="$T/maat-r0.json"
check "ripresa spenta: maat.json ciclo.riprese 0 → lo STOP della 1.7" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan " ] && [ ! -f "$RR/log/01-plan.ripresa" ]'
# a .ripresa that no driver wrote (a phase can write the run dir): not counted, an AVVISO
forgia() { rnuovo; mkdir -p "$RR/log"; printf '%s\n' "classe=RIPRENDIBILE" "fase=plan" "esito=rilancio" "n=1" "n_fase=1" "max=1" > "$RR/log/00-plan.ripresa"; }
forgia; rrun draft FIC_RIPRESE=1
check "ripresa: un .ripresa senza la sua riga in driver.log non conta (01 rilancio, 02 limite) ed e detto in un AVVISO" '[ "$(rcalls)" = "01-plan 02-plan " ] && grep -q "AVVISO: .*00-plan.ripresa non è registrato in driver.log: ignorato" "$RR/driver.log"'
if tmut reg 's/^\( *\)if _ripresa_riga(label, d, .*# RIPRESA-REGISTRATA$/\1if True:/'; then
  # (DA10) the counts come from driver.log: what the registration still guards is R1/R2 of next. A phase writes a STOP
  # 00-plan and a .ripresa esito=limite at the State of now: registered, next would stop without launching
  forgia2() { rnuovo; mkdir -p "$RR/log"; printf '%s\n' "PHASE RESULT plan: STOP — x" > "$RR/log/00-plan.esito"
    printf '%s\n' "classe=RIPRENDIBILE" "fase=plan" "esito=limite" "n=1" "n_fase=1" "max=1" \
      "state=$("$FIC_PY" "$DRV" next "$SR" 2>/dev/null | sed -n 's/^State: //p' | tr -d '\r')" > "$RR/log/00-plan.ripresa"; }
  forgia2; rrun draft FIC_RIPRESE=1
  check "ripresa: un .ripresa esito=limite forgiato da una fase (non registrato) non ferma next: 01-plan parte" 'grep -qx 01-plan "$FAKE_CALLS"'
  forgia2; RRUN_DRV="$T/drv-reg.py" rrun draft FIC_RIPRESE=1
  check "controprova: senza il controllo della registrazione il .ripresa forgiato ferma il ciclo senza lanci (rosso)" '[ "$(rcalls)" = "" ]'
else check "controprova registrazione: la mutazione si applica" false; fi
# (B9 review) an OK line is classified too: a plan OK on a spec still DRAFT is a final STOP, not the uncounted DRAFT -> PLAN
rnuovo; rrun ok-draft
check "ripresa (review B9): plan OK con la spec DRAFT → classifica dopo la riga OK: STOP finale dopo 01-plan con la prova" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan " ] && [ ! -f "$RR/log/01-plan.ripresa" ] && grep -q "Driver result: STOP — PHASE RESULT plan: OK — done · riga OK di una fase plan con Plan status DRAFT: non approvato · prova: .*spec-r.md" "$T/run.out"'
# (B9 fix 2) that UMANO STOP is registered in driver.log and the next invocation stops too (row R4 of next)
check "  B9 fix 2: la riga «Stop umano: 01-plan · regola=piano · state=<State>» in driver.log" 'grep -q " Stop umano: 01-plan · regola=piano · state=[0-9a-f]\{12\}$" "$RR/driver.log"'
cp -r "$RR" "$T/rr-okdraft"; cp "$SR" "$T/sr-okdraft"
rrun ok
check "  B9 fix 2: seconda invocazione, spec invariata → STOP senza lanci (non la riga DRAFT → PLAN)" '[ $rc -eq 1 ] && [ "$(rcalls)" = "" ] && grep -q "Driver result: STOP — STOP — 01-plan ha dato OK su un piano ancora DRAFT" "$T/run.out"'
rokd() { rm -rf "$RR"; cp -r "$T/rr-okdraft" "$RR"; cp "$T/sr-okdraft" "$SR"; }
if tmut r4 's/^\( *\)if su is not None and .*# DRAFT-STOP-UMANO$/\1if False:/'; then
  rokd; RRUN_DRV="$T/drv-r4.py" rrun ok
  check "  controprova: senza la riga R4 la seconda invocazione rilancia il piano senza contarlo (02-plan: rosso)" 'grep -qx 02-plan "$FAKE_CALLS"'
else check "controprova R4: la mutazione si applica" false; fi
if tmut r4reg 's/^\( *\)ev("%s%s · regola=%s · state=%s" .*# STOP-UMANO-REGISTRATO$/\1pass/'; then
  rnuovo; RRUN_DRV="$T/drv-r4reg.py" rrun ok-draft; RRUN_DRV="$T/drv-r4reg.py" rrun ok
  check "  controprova: senza la riga in driver.log la seconda invocazione rilancia il piano (02-plan: rosso)" 'grep -qx 02-plan "$FAKE_CALLS"'
else check "controprova registrazione R4: la mutazione si applica" false; fi
rokd; sed -i 's/^Contesto\.$/Contesto cambiato./' "$SR"; rrun ok
check "  B9 fix 2: spec cambiata (State diverso) → il piano riparte (02-plan)" 'grep -qx 02-plan "$FAKE_CALLS"'
# (final review 1.8.0) the state= of that line when next gives no State: the identity of the spec file
# (sha:<sha256[:12]>), «-» only when the spec cannot be read either (R4 of next: cycle-state.test.sh)
cat > "$T/stato-su.py" <<'EOF'
import importlib.util, sys
sys.dont_write_bytecode = True
s = importlib.util.spec_from_file_location("drv_su", sys.argv[1]); d = importlib.util.module_from_spec(s); s.loader.exec_module(d)
print(d.stato_stop_umano(["x", "State: 0123456789ab", "Next: PLAN — x"], sys.argv[2]))
print(d.stato_stop_umano(["Next: STOP — no State"], sys.argv[2]))
print(d.stato_stop_umano(["State: not computable", "Next: STOP — x"], sys.argv[2]))
print(d.stato_stop_umano([], sys.argv[2] + ".absent"))
EOF
SUX="0123456789ab
sha:$(sha256sum "$SR" | cut -c1-12)
sha:$(sha256sum "$SR" | cut -c1-12)
-"
check "  (review finale) state= della riga Stop umano: lo State; senza State l impronta sha:<12> della spec; senza nemmeno la spec «-»" '[ "$("$FIC_PY" "$T/stato-su.py" "$DRV" "$SR" | tr -d "\r")" = "$SUX" ]'
if tmut su 's/^    return st if re.fullmatch(r"\[0-9a-f\]+", st) else (impronta_spec(spec_fs) or "-")$/    return st or "-"/'; then
  check "  controprova: senza l impronta della spec lo State ignoto torna «-» (rosso)" '[ "$("$FIC_PY" "$T/stato-su.py" "$T/drv-su.py" "$SR" | tr -d "\r")" != "$SUX" ]'
else check "controprova impronta Stop umano: la mutazione si applica" false; fi
rm -f "$T/stato-su.py" "$T/drv-su.py"
rm -rf "$T/rr-okdraft" "$T/sr-okdraft" "$T/drv-r4.py" "$T/drv-r4reg.py"
if tmut clok 's/^\( *\)c = classifica(fase, run_fs, label, spec_fs)  # CLASSIFICA-OK$/\1c = Classe("OK", "ok", "", "")/'; then
  rnuovo; RRUN_DRV="$T/drv-clok.py" rrun ok-draft FIC_MAX_FASI=3
  check "controprova: senza classifica sulla riga OK la riga DRAFT → PLAN rilancia il piano senza contarlo (02-plan: rosso)" 'case "$(rcalls)" in "01-plan 02-plan "*) true ;; *) false ;; esac && [ ! -f "$RR/log/01-plan.ripresa" ]'
else check "controprova classifica OK: la mutazione si applica" false; fi
# (B9 review) the total cap of the cycle is the limit that triggers: FIC_RIPRESE=5, the fourth STOP is the limit 3/3
rnuovo; rrun draft FIC_RIPRESE=5
check "ripresa (review B9): FIC_RIPRESE=5 → 01..04-plan, 04-plan.ripresa esito=limite n=3, STOP «limite delle riprese: 3/3 nel ciclo»" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan 02-plan 03-plan 04-plan " ] && [ "$(rf 04-plan esito) $(rf 04-plan n)" = "limite 3" ] && grep -q "Driver result: STOP — limite delle riprese: 3/3 nel ciclo, 3/5 per plan" "$T/run.out"'
if tmut tetto 's/ or n_tot >= RIPRESE_CICLO:  # LIMITE-RIPRESE$/:  # LIMITE-RIPRESE/'; then
  rnuovo; RRUN_DRV="$T/drv-tetto.py" rrun draft FIC_RIPRESE=5
  check "controprova: senza il tetto di 3 per ciclo la quinta fase parte (05-plan: rosso)" 'grep -qx 05-plan "$FAKE_CALLS"'
else check "controprova tetto del ciclo: la mutazione si applica" false; fi
# (DA10) the count comes from the Ripresa: lines of driver.log: a registered .ripresa deleted or edited by a phase does
# not lower it (01 rilancio n=1, 02 rilancio n=2, 03 limite)
for m in draft-cancella draft-altera; do
  rnuovo; rrun $m
  check "ripresa (DA10, $m): 01-plan.ripresa toccato dalla fase 02-plan → il contatore resta: 02-plan n=2, 03-plan limite" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan 02-plan 03-plan " ] && [ "$(rf 02-plan esito) $(rf 02-plan n)" = "rilancio 2" ] && [ "$(rf 03-plan esito)" = limite ]'
done
if tmut registro 's/^\( *\)ril = rilanci_registro(run_fs)  # LIMITI-DAL-REGISTRO$/\1ril = [l for l, x in riprese(run_fs)[0] if x.get("esito") == "rilancio"]/'; then
  rnuovo; RRUN_DRV="$T/drv-registro.py" rrun draft-cancella
  check "controprova: contando dai file il .ripresa cancellato abbassa il contatore (02-plan n=1, 04-plan: rosso)" '[ "$(rf 02-plan n)" = 1 ] && grep -qx 04-plan "$FAKE_CALLS"'
else check "controprova conteggio dal registro: la mutazione si applica" false; fi
# (DA9) a test-red resume inside run (a fake next that says TEST-RED): the progress is the cause, the missing symbols
cat > "$T/cs-tr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "State: tr-fisso" "Next: TEST-RED — finto"
EOF
chmod +x "$T/cs-tr"
rnuovo APPROVED; rrun tr-uguale FIC_CYCLE_STATE="$T/cs-tr"
check "ripresa test-red (DA9): stesso simbolo mancante due volte → 01 rilancio (prompt 1/2 in 02), 02 senza-progresso, STOP" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-test-red 02-test-red " ] && [ "$(rf 01-test-red esito) $(rf 01-test-red regola)" = "rilancio simbolo" ] && grep -qx "RIPRESA (driver): 1/2 — stub mancanti: T1: undefined: MaxDepth — scrivi gli stub additivi nei file \`stub\` dello scope (e in quelli nuovi), solo per nomi del piano; un «cannot import name» può essere anche un refuso nell'"'"'import del test stesso: confrontalo col piano; non cambiare mai un'"'"'asserzione" "$FAKE_CALLS.02-test-red.prompt" && [ "$(rf 02-test-red esito)" = senza-progresso ] && grep -q "Driver result: STOP — ripresa senza progresso" "$T/run.out"'
check "  la chiave rilievi di test-red porta l'impronta dei simboli: «-;<8 hex>»" '[ -n "$(rf 01-test-red rilievi | grep -x -- "-;[0-9a-f]\{8\}")" ]'
rnuovo APPROVED; rrun tr-diverso FIC_CYCLE_STATE="$T/cs-tr"
check "ripresa test-red (DA9): un simbolo diverso a ogni fase → seconda ripresa, poi il limite 2/2" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-test-red 02-test-red 03-test-red " ] && [ "$(rf 02-test-red esito)" = rilancio ] && [ "$(rf 03-test-red esito)" = limite ]'
if tmut causa 's/^\( *\)uguale = bool(prec) and (prec\[-1\].get("rilievi") or "").rsplit(";", 1)\[-1\] == kc  # PROGRESSO-TEST-RED$/\1uguale = bool(prec)/'; then
  rnuovo APPROVED; RRUN_DRV="$T/drv-causa.py" rrun tr-diverso FIC_CYCLE_STATE="$T/cs-tr"
  check "controprova: senza la causa nella chiave i simboli diversi sembrano senza progresso (02 senza-progresso: rosso)" '[ "$(rf 02-test-red esito)" = senza-progresso ]'
else check "controprova causa test-red: la mutazione si applica" false; fi
# (B10-B11 review, DA9) only the cause counts in test-red: the same missing symbol with other findings is no progress
rnuovo APPROVED; rrun tr-rilievi FIC_CYCLE_STATE="$T/cs-tr"
check "ripresa test-red (DA9, review B10-B11): stesso simbolo, rilievi diversi → 02 senza-progresso" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-test-red 02-test-red " ] && [ "$(rf 01-test-red esito)" = rilancio ] && [ "$(rf 02-test-red esito)" = senza-progresso ]'
if tmut solocausa 's/^\( *\)uguale = bool(prec) and (prec\[-1\].get("rilievi") or "").rsplit(";", 1)\[-1\] == kc  # PROGRESSO-TEST-RED$/\1uguale = bool(prec) and prec[-1].get("piano") == d["piano"] and prec[-1].get("rilievi") == d["rilievi"]/'; then
  rnuovo APPROVED; RRUN_DRV="$T/drv-solocausa.py" rrun tr-rilievi FIC_CYCLE_STATE="$T/cs-tr"
  check "controprova: confrontando anche i rilievi il simbolo ripetuto sembra un progresso (02 rilancio: rosso)" '[ "$(rf 02-test-red esito)" = rilancio ]'
else check "controprova solo la causa: la mutazione si applica" false; fi
rm -f "$T/drv-solocausa.py"
# (B9 review) resumes off after a rilancio record: the relaunch prompt carries no RIPRESA line
rnuovo; rrun draft FIC_MAX_FASI=1
rrun draft FIC_RIPRESE=0 FIC_MAX_FASI=1
check "ripresa spenta dopo un rilancio registrato: 02-plan senza la riga RIPRESA (driver)" '[ "$(rcalls)" = "02-plan " ] && [ "$(rf 01-plan esito)" = rilancio ] && ! grep -q "RIPRESA" "$FAKE_CALLS.02-plan.prompt"'
if tmut attive 's/^\( *\)rip = ripresa_in_corso(run_fs, fase, state) if rmax > 0 else None .*# RIGA-SE-ATTIVE$/\1rip = ripresa_in_corso(run_fs, fase, state)/'; then
  rnuovo; rrun draft FIC_MAX_FASI=1
  RRUN_DRV="$T/drv-attive.py" rrun draft FIC_RIPRESE=0 FIC_MAX_FASI=1
  check "controprova: senza la condizione sulle riprese attive il prompt di 02-plan porta la riga RIPRESA (rosso)" 'grep -q "^RIPRESA (driver): " "$FAKE_CALLS.02-plan.prompt"'
else check "controprova riga se attive: la mutazione si applica" false; fi
# (B9 review) ciclo.riprese unreadable → 0 with one AVVISO; the proof of a decision is relative to the repository
rnuovo; rrun draft FIC_RIPRESE=abc
check "ripresa: FIC_RIPRESE=abc → lo STOP della 1.7 e un solo AVVISO «ciclo.riprese illeggibile»" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan " ] && [ "$(grep -c "AVVISO: ciclo.riprese illeggibile (FIC_RIPRESE=abc)" "$T/run.out")" = 1 ]'
if tmut avviso 's/^\( *\)avvisa("AVVISO: " + T("driver-180.riprese_illeggibili", why=r\[1\]))$/\1pass/'; then
  rnuovo; RRUN_DRV="$T/drv-avviso.py" rrun draft FIC_RIPRESE=abc
  check "controprova: senza l AVVISO di riprese_max il valore illeggibile passa in silenzio (rosso)" '! grep -q "AVVISO: ciclo.riprese illeggibile" "$T/run.out"'
else check "controprova AVVISO riprese_max: la mutazione si applica" false; fi
printf '{ non json\n' > "$T/maat-rotto.json"
rnuovo; rrun draft MAAT_CONFIG="$T/maat-rotto.json"
check "ripresa: maat.json invalido → 0 riprese e un AVVISO" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan " ] && [ "$(grep -c "AVVISO: ciclo.riprese illeggibile" "$T/run.out")" = 1 ]'
rnuovo; rrun nhd-tipo
check "ripresa: la prova di una decisione nel .ripresa e' relativa alla radice (spec-r.md), mai un percorso assoluto" 'p=$(rf 01-plan prova); case "$p" in /*|?:*) false ;; *spec-r.md) true ;; *) false ;; esac'
if tmut relativa 's/^\( *\)pv = _rel(c.prova, root) if root and os.path.isabs(c.prova) else c.prova .*$/\1pv = c.prova/'; then
  rnuovo; RRUN_DRV="$T/drv-relativa.py" rrun nhd-tipo
  check "controprova: senza _rel la prova del .ripresa e' un percorso assoluto (rosso)" 'p=$(rf 01-plan prova); case "$p" in /*|?:*) true ;; *) false ;; esac'
else check "controprova prova relativa: la mutazione si applica" false; fi
rm -f "$T/drv-attive.py" "$T/drv-avviso.py" "$T/drv-relativa.py"
rm -f "$T"/drv-clok.py "$T"/drv-tetto.py "$T"/drv-registro.py "$T"/drv-causa.py "$T/cs-tr" "$T/maat-rotto.json"
# (B10, D3) the relaunch on a declassified decision: the prompt names its key, the same as the .ripresa and driver.log
rnuovo; rrun nhd-proof FIC_RIPRESE=1
K=$(printf '%s' "the counter looks too small (01-plan)" | sha256sum | cut -c1-8)
check "ripresa (B10): il prompt di 02-plan dice «decisione umana senza prova eseguita — decisione <chiave>: <testo>», la chiave del .ripresa e di driver.log" 'grep -q "^RIPRESA (driver): 1/1 — decisione umana senza prova eseguita — decisione $K: the counter looks too small (01-plan) (" "$FAKE_CALLS.02-plan.prompt" && grep -qx "declassata: $K" "$RR/log/01-plan.ripresa" && grep -q " Ripresa: 01-plan · .* · declassata=$K · " "$RR/driver.log"'
check "  (review B10-B11) la riga nomina il result.json della fase fermata, non la spec: «— rilievi aperti: log/01-plan.result.json»" 'grep -q "^RIPRESA (driver): 1/1 — decisione umana senza prova eseguita — .* — rilievi aperti: log/01-plan.result.json$" "$FAKE_CALLS.02-plan.prompt"'
if tmut rilres 's/^\( *\)f = "log\/%s.result.json" % label if .*# RILIEVI-RESULT$/\1f = rip.get("prova")/'; then
  rnuovo; RRUN_DRV="$T/drv-rilres.py" rrun nhd-proof FIC_RIPRESE=1
  check "controprova: con la prova della regola (la spec) la riga non nomina il result.json (rosso)" '! grep -q "rilievi aperti: log/01-plan.result.json$" "$FAKE_CALLS.02-plan.prompt"'
else check "controprova rilievi result.json: la mutazione si applica" false; fi
# (B10-B11 review) an OK line on a plan NEEDS HUMAN DECISION with a valid non-mechanical decision: the driver.log line too
rnuovo; rrun ok-nhd
check "ripresa (review B10-B11): riga OK con una decisione spec valida → STOP e la riga «Decisione non verificata da script:» in driver.log" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan " ] && grep -q " Decisione non verificata da script: 01-plan · decisione umana: spec — " "$RR/driver.log"'
if tmut nvok 's/^\( *\)ev("%s%s · %s" % (NON_VERIFICATA_RIGA, label, .*# NON-VERIFICATA-OK$/\1pass/'; then
  rnuovo; RRUN_DRV="$T/drv-nvok.py" rrun ok-nhd
  check "controprova: senza la scrittura nel ramo OK driver.log non ha la riga (rosso)" '! grep -q " Decisione non verificata da script: " "$RR/driver.log"'
else check "controprova decisione non verificata OK: la mutazione si applica" false; fi
rm -f "$T/drv-rilres.py" "$T/drv-nvok.py"
# (B10) a non-mechanical decision: the final STOP says so, driver.log keeps the line for cycle-report.py and the review
rnuovo; rrun nhd-valida
check "ripresa (B10): Open decision: spec → STOP finale con «decisione non verificata da script: spec» e la riga in driver.log" '[ $rc -eq 1 ] && [ "$(rcalls)" = "01-plan " ] && grep -q "Driver result: STOP — .*decisione non verificata da script: spec · prova: .*spec-r.md" "$T/run.out" && grep -q " Decisione non verificata da script: 01-plan · decisione umana: spec — " "$RR/driver.log"'
cat > "$T/cs-rev" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "State: rev-fisso" "Next: REVIEW — finto"
EOF
chmod +x "$T/cs-rev"
rrun ok FIC_CYCLE_STATE="$T/cs-rev" FIC_MAX_FASI=1
check "  la review successiva riceve «DECISIONE NON VERIFICATA (driver): 01-plan · …» nel prompt" 'grep -q "^DECISIONE NON VERIFICATA (driver): 01-plan · decisione umana: spec — .* — una decisione umana del piano che nessuno script ha verificato" "$FAKE_CALLS.02-review.prompt"'
rm -f "$T/cs-rev"
# (B11, D3) a probe disproved in test-red: the review prompt shows the declassified claim next to the row of the probe
rnuovo APPROVED; mkdir -p "$RR/log" "$RR/test-red"
printf '%s\n' "PHASE RESULT test-red: OK — rossi" "state=x" > "$RR/log/01-test-red.esito"; echo 0 > "$RR/log/01-test-red.exit"
printf '{"esito":"OK","riassunto":"2 ok","evidence":"x","conflitti":[],"test":{"T5":{"esito":"sonda_smentita","motivo":"m","messaggio":"","posizione":null,"file":"a","nome":"b","sonda":{"decisione":"c0ffee04","affermazione":"the 16-bit counter cannot hold 100000 levels","atteso":"TooDeeplyNested","riga":9}}}}\n' > "$RR/test-red/rossi.json"
printf 'rossi: esito=OK — 2 ok\n' > "$RR/log/01-test-red.rossi"
cat > "$T/cs-rev2" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "State: rev-fisso" "Next: REVIEW — finto"
EOF
chmod +x "$T/cs-rev2"
# (B10-B11 review) the probe counts only with its key declassified by a registered resume (as LIMITE-CON-RIPRESA)
rrun ok FIC_CYCLE_STATE="$T/cs-rev2" FIC_MAX_FASI=1
check "review (review B10-B11): sonda_smentita la cui chiave nessuna ripresa registrata ha declassato → niente riga SONDA SMENTITA" '! grep -q "SONDA SMENTITA" "$FAKE_CALLS.02-review.prompt"'
rm -rf "$RR/log/02-review"* "$RR/prompts"
printf '%s\n' "classe=RIPRENDIBILE" "regola=decisione" "fase=plan" "esito=rilancio" "n=1" "declassata: c0ffee04" > "$RR/log/00-plan.ripresa"
printf '2026-11-16T10:00:00Z Ripresa: 00-plan · esito=rilancio · n=1 · declassata=c0ffee04 · sha=%s\n' "$(sha256sum < "$RR/log/00-plan.ripresa" | cut -c1-12)" >> "$RR/driver.log"
if tmut smentita 's/^\( *\)if isinstance(s, dict) and s.get("decisione") in dk:  # SMENTITA-CON-RIPRESA$/\1if isinstance(s, dict):/'; then
  mv "$RR/log/00-plan.ripresa" "$T/00-plan.ripresa.bak"
  RRUN_DRV="$T/drv-smentita.py" rrun ok FIC_CYCLE_STATE="$T/cs-rev2" FIC_MAX_FASI=1
  check "controprova: senza il controllo della chiave la sonda non registrata entra nel prompt (rosso)" 'grep -q "^SONDA SMENTITA (driver): T5" "$FAKE_CALLS.02-review.prompt"'
  mv "$T/00-plan.ripresa.bak" "$RR/log/00-plan.ripresa"; rm -rf "$RR/log/02-review"* "$RR/prompts" "$T/drv-smentita.py"
else check "controprova sonda smentita registrata: la mutazione si applica" false; fi
rrun ok FIC_CYCLE_STATE="$T/cs-rev2" FIC_MAX_FASI=1
check "review (B11): il prompt mostra la sonda smentita accanto alla riga: «SONDA SMENTITA (driver): T5 — <affermazione> — decisione <chiave> — …»" 'grep -q "^SONDA SMENTITA (driver): T5 — the 16-bit counter cannot hold 100000 levels — decisione c0ffee04 — una sonda di test-red ha smentito" "$FAKE_CALLS.02-review.prompt"'
printf 'rossi: esito=OK — altro\n' > "$RR/log/01-test-red.rossi"; rm -rf "$RR/log/02-review"* "$RR/prompts"
rrun ok FIC_CYCLE_STATE="$T/cs-rev2" FIC_MAX_FASI=1
check "  un rossi.json che non e' quello dell'ultimo test-red (la riga di .rossi non torna) non entra nel prompt" '! grep -q "SONDA SMENTITA" "$FAKE_CALLS.02-review.prompt"'
rm -f "$T/cs-rev2"
# (B13, A1) a second invocation after a test-red OK-DEVIAZIONE: _json_rule reads .deviazioni-test (row 7d of next)
rnuovo APPROVED; mkdir -p "$RR/log"
ST=$("$FIC_PY" "$DRV" next "$SR" 2>/dev/null | sed -n 's/^State: //p' | tr -d '\r')
printf '%s\nstate=%s\n' "PHASE RESULT test-red: OK — rossi" "$ST" > "$RR/log/01-test-red.esito"; echo 0 > "$RR/log/01-test-red.exit"; : > "$RR/log/01-test-red.jsonl"
printf '{"fase":"test-red","esito":"OK","motivo":"m","deviazioni":["test-data: T4 — other base paths — routes collide"],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}\n' > "$RR/log/01-test-red.result.json"
printf 'test-data: T4 — other base paths — routes collide\tACCEPT — only the bases change\t%064d\n' 0 > "$RR/log/01-test-red.deviazioni-test"
nx() { "${1:-$FIC_PY}" "${2:-$DRV}" next "$SR" 2>/dev/null | sed -n 's/^Next: //p' | tr -d '\r'; }
check "next (B13): dopo un test-red OK-DEVIAZIONE con .deviazioni-test → IMPLEMENT" 'nx | grep -q "^IMPLEMENT"'
mv "$RR/log/01-test-red.deviazioni-test" "$T/dt.bak"
check "next (B13): lo stesso run dir senza .deviazioni-test → STOP (la deviazione test-data non e accettata)" 'nx | grep -q "^STOP — 01-test-red: result.json STOP"'
mv "$T/dt.bak" "$RR/log/01-test-red.deviazioni-test"
if tmut jrtd 's/ and not (x.startswith(TEST_DATA) and x in acc)\]:  # JSON-RULE-TEST-DATA$/]:  # JSON-RULE-TEST-DATA/'; then
  check "controprova: senza .deviazioni-test letto da _json_rule la deviazione accettata ferma il ciclo (rosso)" 'nx "$FIC_PY" "$T/drv-jrtd.py" | grep -q "^STOP"'
else check "controprova _json_rule test-data: la mutazione si applica" false; fi
rm -f "$T/drv-jrtd.py"
# (review B12-B13) a deviation longer than 300 characters is compared whole; the echoed template is not an ACCEPT
LUNGA="test-data: T4 — $(printf 'other base paths %.0s' $(seq 1 25))— routes collide"
printf '{"fase":"test-red","esito":"OK","motivo":"m","deviazioni":["%s"],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}\n' "$LUNGA" > "$RR/log/01-test-red.result.json"
printf '%s\tACCEPT — only the bases change\t%064d\n' "$LUNGA" 0 > "$RR/log/01-test-red.deviazioni-test"
check "next (review B12-B13): deviazione accettata di oltre 300 caratteri → IMPLEMENT (confronto sul testo intero)" '[ ${#LUNGA} -gt 300 ] && nx | grep -q "^IMPLEMENT"'
if tmut intere 's/^\( *\)dev = \[" ".join(str(x).split()) for x in .*# DEV-INTERE$/\1dev = [one(x) for x in (d.get("deviazioni") or []) if str(x).strip()]/'; then
  check "controprova: troncando a 300 caratteri la deviazione accettata ferma il ciclo (rosso)" 'nx "$FIC_PY" "$T/drv-intere.py" | grep -q "^STOP"'
else check "controprova deviazione intera: la mutazione si applica" false; fi
printf '%s\tACCEPT | STOP — <reason>\t%064d\n' "$LUNGA" 0 > "$RR/log/01-test-red.deviazioni-test"
check "next (review B12-B13): un verdetto «ACCEPT | STOP — <reason>» (il modello ripetuto) non accetta → STOP" 'nx | grep -q "^STOP — 01-test-red: result.json STOP"'
rm -f "$T/drv-intere.py"
rm -rf "$RR" "$SR" "$T/rr-limite" "$T/sr-limite" "$FAKE_CALLS"* "$T"/drv-r2.py "$T"/drv-r23.py "$T"/drv-cl.py "$T"/drv-progresso.py "$T"/drv-chiave.py "$T"/drv-reg.py
# --- 16. (1.8.1, G2-3) the usage limit of a sub-session: a STOP with its reason, not a mute exit 1. The fixture is the
# real event of a 5-hour limit (reduced and anonymised: no session or request ids): a normal result, the synthetic
# assistant message, then the last `result` with api_error_status 429 and api_error usage_limit_reached. (a) errore_api
# and classifica on synthetic run dirs; (b) run with a fake run-phase.sh exiting 1 (limit, 529, nothing); (c) the
# relaunch through the REAL run-phase.sh after a usage-limit STOP in review, in implement and in test-red (files parked
# by the STOP, back in the tree): the same phase again, no chain STOP, no lock left. Counterproof: no jsonl read.
LIM_N9=$T/n9-limite.jsonl
cat > "$LIM_N9" <<'EOF'
{"type":"result","subtype":"success","is_error":false,"stop_reason":"end_turn","session_id":"s-n9","duration_ms":118000,"total_cost_usd":0.5,"result":"Reviewer launched in background: waiting for its notification."}
{"type":"assistant","message":{"id":"m-n9","container":null,"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","stop_sequence":"","type":"message","content":[{"type":"text","text":"You've hit your 5-hour limit · resets 5:10pm (Europe/Rome)"}],"context_management":null},"parent_tool_use_id":null,"session_id":"s-n9","error":"rate_limit","is_api_error_message":true,"api_error_status":429,"api_error":"usage_limit_reached","api_error_params":{"rate_limit_info":{"status":"rejected","rateLimitType":"five_hour","overageStatus":"rejected","isUsingOverage":false}},"api_error_origin":"first_party"}
{"duration_api_ms":118778,"stop_reason":"stop_sequence","session_id":"s-n9","total_cost_usd":0.7681564000000001,"permission_denials":[],"terminal_reason":"api_error","is_error":true,"num_turns":1,"subtype":"success","api_error_status":429,"api_error_origin":"first_party","api_error":"usage_limit_reached","result":"You've hit your 5-hour limit · resets 5:10pm (Europe/Rome)","type":"result","duration_ms":605,"result_index":2}
EOF
E529='{"type":"result","subtype":"success","is_error":true,"api_error_status":529,"api_error":"overloaded_error","result":"Overloaded","duration_ms":300}'
LIM_IT="limite d'uso raggiunto (You've hit your 5-hour limit · resets 5:10pm (Europe/Rome)): rilancia il driver dopo quell'ora; la fase riparte da capo"
LIM_EN="usage limit reached (You've hit your 5-hour limit · resets 5:10pm (Europe/Rome)): relaunch the driver after that time; the phase starts again from the beginning"
# (a) errore_api and classifica: «<case> <class> <rule> <proof> <cause>» and «<case> api <limite> <e> <s> <msg>»
LA=$T/lim-a; mkdir -p "$LA"
lca() { # <case> <exit> <jsonl content|-> : run dir $LA/<case>.run, phase review
  mkdir -p "$LA/$1.run/log"; printf '%s\n' "$2" > "$LA/$1.run/log/01-review.exit"
  [ "$3" = - ] || printf '%s\n' "$3" > "$LA/$1.run/log/01-review.jsonl"
  printf '# S\n' > "$LA/$1.md"
}
lca n9 1 "$(cat "$LIM_N9")"; lca e529 1 "$E529"; lca senza 1 -; lca vuoto 1 ""
lca prima 1 "$(cat "$LIM_N9"; echo '{"type":"result","is_error":false,"result":"ripreso"}')"
lca rotto 1 "$(echo '{"type":"result",'; cat "$LIM_N9")"
lca rate 1 '{"type":"result","is_error":true,"api_error":"rate_limit_error","result":"Rate limited"}'
cat > "$T/lim-a.py" <<'EOF'
import importlib.util, os, sys
sys.dont_write_bytecode = True
s = importlib.util.spec_from_file_location("drv_lim", sys.argv[1]); d = importlib.util.module_from_spec(s)
s.loader.exec_module(d)
for n in sys.argv[3:]:
    rf = os.path.join(sys.argv[2], n + ".run")
    a = d.errore_api(rf, "01-review") if hasattr(d, "errore_api") else "(errore_api assente)"
    r = d.classifica("review", rf, "01-review", os.path.join(sys.argv[2], n + ".md"))
    sys.stdout.buffer.write(("%s\t%s\t%s\t%s\t%s\n" % (n, r.classe, r.regola, r.prova, r.causa)).encode("utf-8"))
    sys.stdout.buffer.write(("%s\tapi\t%s\n" % (n, a if not isinstance(a, dict) else "%s %s %s %s" % (
        a["limite"], a["e"], a["s"], a["msg"]))).encode("utf-8"))
EOF
lim_a() { "$FIC_PY" "$T/lim-a.py" "$1" "$LA" n9 e529 senza vuoto prima rotto rate 2>&1 | tr -d '\r'; }
LAO=$(lim_a "$DRV")
lav() { printf '%s\n' "$LAO" | awk -F'\t' -v n="$1" -v k="${2:-}" '$1 == n && (k == "api") == ($2 == "api") { $1 = ""; print substr($0, 2) }'; }
check "16 (1.8.1, G2-3) errore_api: l'ultimo result del jsonl reale (429, usage_limit_reached) → limite, con il testo del result" '[ "$(lav n9 api)" = "api True usage_limit_reached 429 You'"'"'ve hit your 5-hour limit · resets 5:10pm (Europe/Rome)" ]' "$LAO"
check "  529 overloaded_error → errore API, non limite · rate_limit_error senza stato → limite" '[ "$(lav e529 api)" = "api False overloaded_error 529 Overloaded" ] && [ "$(lav rate api)" = "api True rate_limit_error - Rate limited" ]'
check "  jsonl assente, vuoto, o con un result senza campi DOPO l'errore → None (conta l'ULTIMO result); una riga illeggibile si salta" '[ "$(lav senza api)" = "api None" ] && [ "$(lav vuoto api)" = "api None" ] && [ "$(lav prima api)" = "api None" ] && [ "$(lav rotto api)" = "api True usage_limit_reached 429 You'"'"'ve hit your 5-hour limit · resets 5:10pm (Europe/Rome)" ]'
check "  classifica con .exit 1: limite → TECNICO api log/01-review.jsonl con la causa del limite; 529 → la causa errore API; senza errore → TECNICO exit come in 1.8.0" '[ "$(lav n9)" = "TECNICO api log/01-review.jsonl $LIM_IT" ] && [ "$(lav e529)" = "TECNICO api log/01-review.jsonl errore API overloaded_error (stato 529): Overloaded — rilancia il driver; la fase riparte da capo" ] && [ "$(lav senza)" = "TECNICO exit log/01-review.exit la fase è finita con exit 1" ] && [ "$(lav prima)" = "TECNICO exit log/01-review.exit la fase è finita con exit 1" ]' "$LAO"
# (b) run, fake run-phase.sh: the sub-session exited 1, its jsonl written, the stderr empty unless said
cat > "$T/rp-lim" <<'EOF'
#!/usr/bin/env bash
d=$1 l=$2; mkdir -p "$d/log"; echo "$l" >> "$FAKE_CALLS"; : > "$d/log/$l.stderr"
case "$LIM_MODE" in
  limite) cp "$LIM_N9" "$d/log/$l.jsonl" ;;
  e529) printf '%s\n' "$E529" > "$d/log/$l.jsonl" ;;
  vuoto) : > "$d/log/$l.jsonl" ;;
  stderr) : > "$d/log/$l.jsonl"; echo "claude: connessione chiusa" > "$d/log/$l.stderr" ;;
  limite-stderr) cp "$LIM_N9" "$d/log/$l.jsonl"; echo "claude: uscita 1" > "$d/log/$l.stderr" ;;
esac
echo 1 > "$d/log/$l.exit"; exit 1
EOF
chmod +x "$T/rp-lim"
export LIM_N9 E529
lrun() { # <mode> [variables] → rc, output in $T/run.out
  rm -rf "$RUN" "$FAKE_CALLS"; spec_approved
  env "${@:2}" LIM_MODE=$1 FIC_RUN_PHASE="$T/rp-lim" FIC_CONTEXT_PACK=- "$FIC_PY" "${LRUN_DRV:-$DRV}" run "$SP" > "$T/run.out" 2>&1; rc=$?
}
limrow() { grep -c "^[0-9T:Z-]* Limite d'uso: 01-implement · usage_limit_reached · 429$" "$RUN/driver.log"; }
lrun limite
check "16 run: sotto-sessione uscita 1 sul limite d'uso → «STOP — run-phase exit 1 (sotto-sessione uscita 1): limite d'uso raggiunto (<result>): rilancia …», exit 1" '[ $rc -eq 1 ] && grep -qxF "driver: Driver result: STOP — run-phase exit 1 (sotto-sessione uscita 1): $LIM_IT" "$T/run.out"' "$(tail -2 "$T/run.out")"
check "  driver.log: una riga «Limite d'uso: 01-implement · usage_limit_reached · 429», nessuna «Stop umano:»" '[ "$(limrow)" = 1 ] && ! grep -q "Stop umano: " "$RUN/driver.log"'
lrun limite MAAT_LINGUA=en
check "  in inglese: «usage limit reached (<result>): relaunch the driver …», la riga di driver.log con il prefisso di protocollo «Limite d'uso: »" '[ $rc -eq 1 ] && grep -qxF "driver: Driver result: STOP — run-phase exit 1 (sub-session exited 1): $LIM_EN" "$T/run.out" && [ "$(limrow)" = 1 ]' "$(tail -2 "$T/run.out")"
lrun limite-stderr
check "  limite con uno stderr non vuoto → la causa del limite, poi la coda dello stderr" '[ $rc -eq 1 ] && grep -qxF "driver: Driver result: STOP — run-phase exit 1 (sotto-sessione uscita 1): $LIM_IT · claude: uscita 1" "$T/run.out"'
lrun e529
check "16 run: errore API 529 → «errore API overloaded_error (stato 529): Overloaded — rilancia …», nessuna riga Limite d'uso" '[ $rc -eq 1 ] && grep -qxF "driver: Driver result: STOP — run-phase exit 1 (sotto-sessione uscita 1): errore API overloaded_error (stato 529): Overloaded — rilancia il driver; la fase riparte da capo" "$T/run.out" && ! grep -q "Limite d.uso: " "$RUN/driver.log"' "$(tail -2 "$T/run.out")"
lrun vuoto
check "16 run: nessun errore API e stderr vuoto → il motivo di oggi con «(stderr vuoto)», non niente" '[ $rc -eq 1 ] && grep -qxF "driver: Driver result: STOP — run-phase exit 1 (sotto-sessione uscita 1): (stderr vuoto)" "$T/run.out" && ! grep -q "Limite d.uso: " "$RUN/driver.log"' "$(tail -2 "$T/run.out")"
lrun vuoto MAAT_LINGUA=en
check "  in inglese «(stderr empty)»" 'grep -qxF "driver: Driver result: STOP — run-phase exit 1 (sub-session exited 1): (stderr empty)" "$T/run.out"'
lrun stderr
check "  nessun errore API e uno stderr → la sua coda, come in 1.8.0" 'grep -qxF "driver: Driver result: STOP — run-phase exit 1 (sotto-sessione uscita 1): claude: connessione chiusa" "$T/run.out"'
# counterproof: errore_api that does not read the jsonl → the cause goes back to empty (here «(stderr vuoto)») and
# classifica back to TECNICO exit
if tmut nojsonl 's/os.path.join(run_fs, "log", label + ".jsonl"), encoding="utf-8", errors="replace") as fh:  # LEGGE-JSONL$/os.path.join(run_fs, "log", label + ".non-letto"), encoding="utf-8", errors="replace") as fh:/'; then
  LRUN_DRV="$T/drv-nojsonl.py" lrun limite
  check "controprova: senza la lettura del jsonl la causa torna vuota («(stderr vuoto)»), nessuna riga Limite d'uso (rosso)" '! grep -qF "$LIM_IT" "$T/run.out" && grep -qxF "driver: Driver result: STOP — run-phase exit 1 (sotto-sessione uscita 1): (stderr vuoto)" "$T/run.out" && [ "$(limrow)" = 0 ]'
  check "controprova: senza la lettura del jsonl classifica torna TECNICO exit (rosso)" '[ "$(LAO=$(lim_a "$T/drv-nojsonl.py"); lav n9)" = "TECNICO exit log/01-review.exit la fase è finita con exit 1" ]'
else check "controprova lettura del jsonl: la mutazione si applica" false; fi
rm -f "$T/drv-nojsonl.py"
# (c) the relaunch through the REAL run-phase.sh and cycle-state.sh: a fake claude hits the usage limit in LIM_FASE (the
# first LIM_VOLTE launches of that phase), otherwise it does the phase as in section 11 of driver.test.sh
EFP=$(printf '' | sha256sum | cut -c1-12)
printf '#!/usr/bin/env bash\necho "gates: esito=PASS chiave=k0 evidence=-"\n' > "$T/gates"; chmod +x "$T/gates"
cat > "$T/fin-lim" <<EOF
#!/usr/bin/env bash
d=\${!#}; printf 'Finalize: IMPLEMENTED — snapshot %s — signed · %s\n' "$EFP" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "\${d%.run}.md"
echo "finalize: esito=IMPLEMENTED"
EOF
chmod +x "$T/fin-lim"
cat > "$T/claude-lim" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo "$FIC_PHASE" >> "$LIM_CALLS"
if [ "$FIC_PHASE" = test-red ] && [ -f "$FIC_REPO/src/test_c.py" ]; then echo "test_c.py nell'albero" >> "$LIM_CALLS"; fi
if [ "$FIC_PHASE" = "$LIM_FASE" ] && [ "$(grep -cx "$FIC_PHASE" "$LIM_CALLS")" -le "${LIM_VOLTE:-1}" ]; then
  case "$FIC_PHASE" in
    implement) echo "parziale" >> "$FIC_REPO/src/a.py" ;;
    test-red) printf 'def test_c():\n    assert 1 == 2\n' > "$FIC_REPO/src/test_c.py" ;;
  esac
  cat "$LIM_N9"; exit 1
fi
case "$FIC_PHASE" in
  implement) echo "fatto" >> "$FIC_REPO/src/a.py"
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/a.py"}}]}}'
    echo '{"type":"result","result":"PHASE RESULT implement: OK — done","structured_output":{"fase":"implement","esito":"OK","motivo":"done","deviazioni":[],"bloccato_su":"none","file":["src/a.py"],"gate_interni":[],"finding":[]}}' ;;
  review) printf '%s\n' "" "## Implementation review" "Review status: APPROVED" "Feature status: IMPLEMENTED" >> "$E2E_SPEC"
    echo '{"type":"result","result":"PHASE RESULT review: OK — approved","structured_output":{"fase":"review","esito":"OK","motivo":"approved","deviazioni":[],"bloccato_su":"none","file":[],"gate_interni":[],"finding":[]}}' ;;
esac
EOF
chmod +x "$T/claude-lim"
export LIM_CALLS=$T/lim-calls
rlim() { # <phase> [variables]: driver.py run with the real run-phase.sh → rc, output in $T/rlim.out (appended: two runs)
  env "${@:2}" LIM_FASE=$1 E2E_SPEC="$W/$SP" FIC_LOCK="$T/lock" FIC_REPO="$W" CLAUDE_BIN="$T/claude-lim" FIC_GATES="$T/gates" \
    FIC_FINALIZE="$T/fin-lim" FIC_LANES=0 FIC_CONTEXT_PACK=- "$FIC_PY" "$DRV" run "$SP" > "$T/rlim.out" 2>&1 </dev/null
  rc=$?
}
labels() { ls "$RUN/log" 2>/dev/null | sed -n 's/\.exit$//p' | tr '\n' ' '; }
nolock() { [ ! -e "$T/lock" ] && [ ! -e "$RUN/plan.lock" ] && [ -z "$(ls "$RUN/log" 2>/dev/null | grep '\.running$')" ]; }
lim_stop() { [ $rc -eq 1 ] && grep -qF "driver: Driver result: STOP — run-phase exit 1 (sotto-sessione uscita 1): $LIM_IT" "$T/rlim.out"; }   # then « · <stderr tail>»
lim_reset() { rm -rf "$RUN" "$T/lock" "$LIM_CALLS"; git checkout -q -- src; git clean -qfd -- src; }
# review (not a code phase): implement OK, review on the limit → STOP; the relaunch → the review again → DONE
lim_reset; spec_approved
rlim review; r1=$rc; lim_stop; s1=$?; l1=$(labels); nl1=$(nolock && echo si)
check "16 rilancio (review): implement OK, review sul limite d'uso → STOP con la causa del limite, nessun lock rimasto" '[ $s1 -eq 0 ] && [ "$l1" = "01-implement 02-review " ] && [ "$nl1" = si ] && grep -q " Limite d.uso: 02-review · usage_limit_reached · 429$" "$RUN/driver.log"' "$(tail -3 "$T/rlim.out")"
rlim review
check "  driver.py rilanciato senza altro → next rifà la review (03-review), DONE, nessuno STOP «catena», nessun lock rimasto" '[ $rc -eq 0 ] && [ "$(labels)" = "01-implement 02-review 03-review " ] && grep -q "^driver: Next: REVIEW" "$T/rlim.out" && grep -q "^driver: Driver result: DONE" "$T/rlim.out" && ! grep -q "catena" "$T/rlim.out" && nolock' "$(tail -4 "$T/rlim.out")"
# implement (a code phase, a partial write left in the tree): the relaunch → the implement again → review → DONE
lim_reset; spec_approved
rlim implement; s1=1; lim_stop && s1=0; l1=$(labels); nl1=$(nolock && echo si)
check "16 rilancio (implement): implement sul limite d'uso → STOP con la causa del limite, nessun lock rimasto" '[ $s1 -eq 0 ] && [ "$l1" = "01-implement " ] && [ "$nl1" = si ]' "$(tail -3 "$T/rlim.out")"
rlim implement
check "  driver.py rilanciato → next rifà l'implement (02-implement), poi review e DONE, nessuno STOP «catena», nessun lock" '[ $rc -eq 0 ] && [ "$(labels)" = "01-implement 02-implement 03-review " ] && grep -q "^driver: Next: IMPLEMENT" "$T/rlim.out" && grep -q "^driver: Driver result: DONE" "$T/rlim.out" && ! grep -q "catena" "$T/rlim.out" && nolock' "$(tail -4 "$T/rlim.out")"
# test-red: the phase writes its test, hits the limit; run-phase parks the file (staging/, origine=stop); the relaunch
# → test-red again with the file back in the tree before the sub-session (here it hits the limit again: LIM_VOLTE=2)
spec_f2r() { # format-2 plan, approved, one new acceptance test not written yet → next says TEST-RED
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." "## Piano di implementazione" \
    "Plan format: 2" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
    "### File toccati" "- \`src/a.py\`" "- \`src/test_c.py\` (nuovo)" \
    "### Passi" "#### Blocco B1 — a" "scrive: \`src/a.py\`, \`src/test_c.py\`" "dopo: nessuno" "" \
    "| id | file | modifica | test |" "|---|---|---|---|" "| P1 | \`src/a.py\` | x | T1 |" \
    "### Tracciabilità requisiti" "| Req | Passi del piano | Verifica |" "|---|---|---|" "| RF1 | P1 | T1 |" \
    "### Piano di test" "| ID | requisito | file | asserzione | mutazione |" "|---|---|---|---|---|" \
    "| T1 | RF1 | \`src/test_c.py::test_c\` (nuovo) | rosso se: \`assert 1 == 2\` | — |" \
    "### Changelog revisione piano" "- giro 1: ok" > "$SP"
  local cur; cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$SP"
}
lim_reset; spec_f2r
rlim test-red LIM_VOLTE=2; s1=1; lim_stop && s1=0; l1=$(labels); nl1=$(nolock && echo si)
check "16 rilancio (test-red): test-red sul limite d'uso → STOP con la causa del limite, il test scritto parcheggiato (staging/, origine=stop), fuori dall'albero, nessun lock" '[ $s1 -eq 0 ] && [ "$l1" = "01-test-red " ] && [ "$nl1" = si ] && [ -f "$RUN/staging/src/test_c.py" ] && [ "$(cat "$RUN/staging.origine" 2>/dev/null)" = stop ] && [ ! -f src/test_c.py ] && grep -q "Driver result: STOP — .* · AVVISO: 1 file della fase parcheggiati in " "$T/rlim.out"' "$(tail -3 "$T/rlim.out"; cat "$LIM_CALLS" 2>/dev/null)"
rlim test-red LIM_VOLTE=2
check "  driver.py rilanciato → next rifà il test-red (02-test-red) con il file parcheggiato di nuovo nell'albero prima della sotto-sessione, nessuno STOP «catena», nessun lock" '[ "$(labels)" = "01-test-red 02-test-red " ] && grep -q "^driver: Next: TEST-RED" "$T/rlim.out" && [ "$(tr "\n" " " < "$LIM_CALLS")" = "test-red test-red test_c.py nell'"'"'albero " ] && grep -q "file parcheggiati da uno STOP di test-red ricopiati" "$RUN/log/02-test-red.stderr" && lim_stop && ! grep -q "catena" "$T/rlim.out" && nolock' "$(tail -4 "$T/rlim.out"; cat "$LIM_CALLS" 2>/dev/null)"
lim_reset; rm -f "$T/rlim.out" "$T/lim-a.py" "$T/rp-lim" "$T/claude-lim" "$T/fin-lim"; rm -rf "$LA"; spec_approved
cd /
echo "driver-esiti.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
