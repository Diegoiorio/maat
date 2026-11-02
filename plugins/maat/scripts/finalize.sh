#!/usr/bin/env bash
# finalize.sh — signs the final state of a feature (harness-pt08): the review writes the verdict, the script
# confirms `Feature status: IMPLEMENTED` only with the evidence, otherwise it moves it to NEEDS_VERIFICATION.
#
#   bash script/fic/finalize.sh [--level min|std|full|legacy] [--copertura <result.json>] <run-dir>
#
# <run-dir> = .claude/.ai-workflow/spec-<name>.run; the spec is <run-dir without .run>.md. run-phase.sh runs it
# after every review that exits 0 (outcome in log/<label>.finalize), with the level in force.
#
# IT ACTS only if the "## Review implementazione" (or "## Implementation review") section (outside the fences) has
# `Review status: APPROVED` and `Feature status: IMPLEMENTED`: it never promotes beyond the review verdict (obligations, e2e and snapshot are
# known only to the review). Otherwise it touches nothing (exit 4).
# IT CONFIRMS IMPLEMENTED only if:
#   1. every REQUIRED gate — the gates.sh list, `maat_gate_richiesti <level> <files of touched.txt>` from
#      .claude/maat.json: tests-<module> for every module with a test command or with touched files, controlli-<module>
#      for every module with checks, lint if the level requires it (build is optional, as in the review) — has
#      evidence/<CURRENT key>/<gate>.json with esito PASS and the report next to it, or SKIPPED (nothing to
#      run, with the reason: satisfied as in the review). NOT RUN (declared: module without tests, skipped entries)
#      does not satisfy and is not an error: the signature is at most NEEDS_VERIFICATION, with the reason «nessun test nel
#      modulo X, controlli verdi» (or «controlli saltati: …»). The directory is the one whose argomenti.txt is
#      <level> + the files of touched.txt, and that `gates.sh --verify` declares FRESH; the "chiave" field of the JSON
#      must be the directory name;
#   2. every counterproof is red on assertion: if <run-dir>/counterproof/mutations.json exists, each of its ids has
#      <id>.json with esito rosso_asserzione (counterproof.sh, harness-pt05) — or rosso_generico (command runner:
#      red without report), which satisfies but is a WEAK proof, declared («prove deboli: …» in the detail and a
#      «prova debole: …» line on stdout); non_eseguita (module without counterproof) is NOT RUN (declared): like a
#      NOT RUN gate it does not satisfy and is not an error (at most NEEDS_VERIFICATION); otherwise every required row of the
#      review evidence table that names a counterproof has Result PASS. An entry with
#      "assorbita": true (L2, harness-pt11: new file, red at the base with a stub, green after) counts only if
#      `plan-check.sh l2` confirms it on the current code (lines in <run-dir>/counterproof/l2.txt: tests fingerprint
#      FRESH, stub = exported symbols, every symbol in an acceptance test) or if it is red on assertion anyway;
#      otherwise evidence is missing (NEEDS_VERIFICATION, not FAIL).
# VERDICT = AND (harness-pt09): a required gate FAIL (controlli-<module> included), or a counterproof that is not red (rosso_import, rosso_raccolta,
# rosso_diverso, verde; or a counterproof row of the table with Result FAIL), is FAIL even with the review
# APPROVED: it writes `Review status: NEEDS_CHANGES`, `Feature status: PLANNED`, `Verification: PARTIAL (finalize.sh:
# <what>)` (the «APPROVED + any FAIL» row of the review decision table; cycle-state.sh sends it to FIX).
# OTHERWISE, if evidence is missing (absent, BLOCKED, old key, counterproof blocked or without result) it writes
# `Feature status: NEEDS_VERIFICATION` and `Verification: PARTIAL (finalize.sh: <what is missing>)`. When confirming
# IMPLEMENTED, a provisional `Verification:` (review in parallel with VERIFY) becomes `VERIFIED (finalize.sh: …)`.
# In all cases it writes (or replaces) the line `Finalize: <IMPLEMENTED|NEEDS_VERIFICATION|FAIL> — snapshot <x12> —
# <detail> · <UTC time>` under `Feature status:`, where <x12> is the fingerprint (sha256, 12 digits, spaces squeezed) of the
# verified `Reviewed snapshot:`: cycle-state.sh (line 13f) gives DONE only if it matches the current snapshot.
# The spec line endings stay as they were (CRLF included).
# MERGE (harness-pt09, --copertura <log/<label>.result.json of the review>): the "copertura" field (requirement -> test
# IDs, written by the reviewer without results) is merged MECHANICALLY with the VERIFY results and becomes the
# "Requirement evidence (finalize.sh: …)" table under the Finalize: line (replaced at every signature). Results by
# FORMAT of the module report (field `report`), never by gate name: junit -> from the JUnit of tests-<module> in the
# FRESH directory (pytest node id -> classname/name); vitest -> from the wrapper report (test-fast.sh), which has no
# per-test outcome: FAIL from the "FAIL <id>" lines, PASS only for an ID that is a test file with the line "✓ <file>";
# nessuno -> no per-test result. The module root in front of an ID is removed; the table suffix
# is the gate label. Counterproofs from counterproof/<id>.json. An ID without result -> requirement «non
# coperto»: it is a table datum, it does not change the verdict (which stays the AND above). Without --copertura no
# table.
#
# Level: --level, otherwise the plan's Test level: line (plan-check.sh contract), otherwise legacy.
# Exit: 0 IMPLEMENTED confirmed · 1 NEEDS_VERIFICATION written · 3 FAIL written · 4 nothing to sign (spec
# untouched) · 2 usage.
# Stdout: one line for each missing item, then "finalize: esito=<IMPLEMENTED|NEEDS_VERIFICATION|FAIL|INVARIATO> — <…>".
# LANGUAGE (1.4.0): the reasons, the detail of the Verification:/Finalize: lines and the Evidence table follow the
# language of the messages (catalog: English by default, Italian with "lingua": "it"; the quoted texts above are the
# Italian ones). Prefixes, separators and outcome words stay as they are; «non coperto» and «not covered» are both
# counted as a requirement not covered.
# Variables: FIC_GATES gates.sh to use for --verify (default: the one next to this script) · FIC_GATES_ROOT and the other
# gates.sh variables pass through the environment (FIC_GATES_ROOT is also the project of maat.json; MAAT_CONFIG replaces it) ·
# FIC_GATES_HARNESS plugin root (default MAAT_ROOT; scripts/plan-check.sh, scripts/python.sh,
# scripts/lib/maat-conf.sh).
# Tests: scripts/finalize.test.sh (next to this script).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/maat-paths.sh" || exit 4   # MAAT_ROOT (plugin)
# Messages (1.4.0): the catalog next to this script. The language is resolved once and exported (gates.sh and
# plan-check.sh read the same one); the embedded Python imports maat_msg.py from MAAT_MSG_PY. The lines written in
# the spec keep their prefixes and separators here: only the detail ({det}) follows the language.
. "$HERE/lib/maat-msg.sh"; maat_msg_carica
maat_lingua -v MAAT_LINGUA; export MAAT_LINGUA
MAAT_MSG_PY=$(maat_cygm "$HERE/maat_msg.py" 2>/dev/null || printf '%s' "$HERE/maat_msg.py"); export MAAT_MSG_PY
HROOT=${FIC_GATES_HARNESS:-$MAAT_ROOT}
GATES=${FIC_GATES:-$HERE/gates.sh}
PC="$HROOT/scripts/plan-check.sh"
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
win() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }

level="" cop=""
while [ $# -gt 0 ]; do
  case $1 in
    --level) [ $# -ge 2 ] || usage; level=$2; shift 2 ;;
    --copertura) [ $# -ge 2 ] || usage; cop=$2; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "finalize: $(msg finalize.unknown_option opt="$1")" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] || usage
run=${1%/}
[ -d "$run" ] || { echo "finalize: $(msg finalize.no_run_dir run="$run")" >&2; exit 2; }
SPEC="${run%.run}.md"
[ -f "$SPEC" ] || { echo "finalize: $(msg finalize.no_spec spec="$SPEC")" >&2; exit 2; }
. "$HROOT/scripts/python.sh" || { echo "finalize: $(msg finalize.no_python)" >&2; exit 2; }
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8 PYTHONDONTWRITEBYTECODE=1
py() { sed '1,/^#__PYTHON__$/d' "$0" | "$FIC_PY" - "$@"; }   # the code comes from a pipe: no temporary file
WSPEC=$(win "$SPEC")

# --- is there anything to sign? ---
st=$(py stato "$WSPEC" | tr -d '\r')
rs=${st%%|*} fs=${st#*|}
case "$rs/$fs" in
  APPROVED*/IMPLEMENTED*) ;;
  *) echo "finalize: esito=INVARIATO — $(msg finalize.nothing_to_sign rs="${rs}" fs="${fs}")"; exit 4 ;;
esac

# --- level in force and required gates ---
if [ -z "$level" ]; then
  level=$(bash "$PC" contract "$SPEC" 2>/dev/null | tr -d '\r' | sed -n 's/^Test level: \([a-z]*\).*/\1/p' | head -1)
  case $level in min|std|full) ;; *) level=legacy ;; esac
fi
case $level in min|std|full|legacy) ;; *) echo "finalize: $(msg finalize.unknown_level level="$level")" >&2; exit 2 ;; esac
FILES=()
[ -f "$run/touched.txt" ] && mapfile -t FILES < <(tr -d '\r' < "$run/touched.txt" | sed 's|^\./||' | grep -v '^$' | LC_ALL=C sort -u)

# --- required gates: the gates.sh list (maat_gate_richiesti, same level and files), build excluded (optional,
# as in the review). For each gate its module; for each module the report format and the root (merge). ---
export PROJECT_ROOT=${FIC_GATES_ROOT:-$PROJECT_ROOT}   # the gates.sh project: <repo>/.claude/maat.json
REQ=() GM=() MODINFO=() conf_err=""
if . "$HROOT/scripts/lib/maat-conf.sh" 2>/dev/null && maat_conf_carica 2>/dev/null &&
   gl=$(maat_gate_richiesti "$level" ${FILES[@]+"${FILES[@]}"} 2>/dev/null | tr -d '\r'); then
  while IFS=$'\t' read -r g m t; do
    [ -n "$g" ] && [ "$t" != build ] || continue
    REQ+=("$g"); GM+=("$g=$m")
  done <<< "$gl"
  i=0
  while n=$(maat_conf "moduli.$i.nome" 2>/dev/null); do
    MODINFO+=("$n|$(maat_conf "moduli.$i.report" --default nessuno)|$(maat_conf "moduli.$i.radice")"); i=$((i + 1))
  done
else
  conf_err=$( { [ -n "${FIC_PY:-}" ] && "$FIC_PY" "$HROOT/scripts/maat-config.py" valida; } 2>&1 | tr -d '\r' | sed 's/^maat-config: //' | head -2 | tr '\n' ' ')
  conf_err=${conf_err:-$(msg finalize.reader_unusable)}
fi

# --- evidence at the current key: same arguments as gates.sh (level + touched.txt), then --verify ---
want=$(printf '%s\n' "$level" ${FILES[@]+"${FILES[@]}"})
ev="" stale=""
while IFS= read -r d; do
  [ -n "$d" ] && [ -f "$d/argomenti.txt" ] || continue
  [ "$(tr -d '\r' < "$d/argomenti.txt")" = "$want" ] || continue
  if bash "$GATES" --verify "$d" >/dev/null 2>&1; then ev=$d; break; fi   # confronto della chiave
  stale="$stale $(basename "$d" | cut -c1-12)"
done < <(ls -dt "$run"/evidence/*/ 2>/dev/null | sed 's|/$||')

# Verdict = AND (harness-pt09): every missing line is "F|…" (gate FAIL, counterproof not red: the code is
# wrong) or "N|…" (absent, BLOCKED, old key: evidence is missing). One F -> FAIL even with the review APPROVED.
miss=() nfail=0 weak=()
# "W|…" = counterproof rosso_generico: satisfies (PASS) but is a WEAK proof, declared in the detail and on stdout
add() { [ -n "$1" ] || return 0; case $1 in F\|*) nfail=$((nfail + 1)) ;; W\|*) weak+=("${1#W|}"); return 0 ;; esac; miss+=("${1#[FN]|}"); }
if [ -n "$conf_err" ]; then
  add "N|$(msg finalize.gates_unknown err="${conf_err% }")"
elif [ -z "$ev" ]; then
  add "N|$(msg finalize.no_evidence level="$level" stale="${stale:+ — $(msg finalize.old_keys stale="$stale")}")"
else
  while IFS= read -r m; do add "$m"; done < <(py gate "$(win "$ev")" ${GM[@]+"${GM[@]}"} | tr -d '\r')
fi
# L2 (harness-pt11): mutations marked "assorbita" (new files) count only if plan-check.sh l2 confirms them on the
# current code (tests fingerprint FRESH, stub = exported symbols, every symbol in an acceptance test).
l2f=""
if [ -f "$run/counterproof/mutations.json" ] && grep -q '"assorbita": *true' "$run/counterproof/mutations.json"; then
  l2f="$run/counterproof/l2.txt"
  bash "$PC" l2 "$SPEC" --run-dir "$run" 2>&1 | tr -d '\r' > "$l2f"
fi
while IFS= read -r m; do add "$m"; done < <(py controprove "$(win "$run")" "$WSPEC" "${l2f:+$(win "$l2f")}" | tr -d '\r')

# Merge requirement -> test ID -> results (harness-pt09): the section's Evidence table, after the signature.
unisci() {
  [ -n "$cop" ] || return 0
  if [ ! -f "$cop" ]; then echo "finalize: $(msg finalize.no_coverage cop="$cop")"; return 0; fi
  py unisci "$WSPEC" "$(win "$cop")" "$([ -n "$ev" ] && win "$ev")" "$(win "$run")" ${MODINFO[@]+"${MODINFO[@]}"} | tr -d '\r'
}

deboli=""
if [ ${#weak[@]} -gt 0 ]; then
  for w in "${weak[@]}"; do printf '%s\n' "$(msg finalize.weak_proof w="$w")"; done
  deboli=$(printf '%s; ' "${weak[@]}"); deboli=" ($(msg finalize.weak_proofs list="${deboli%; }"))"
fi
if [ ${#miss[@]} -eq 0 ]; then
  det="$(msg finalize.det_ok gates="${REQ[*]}" key="$(basename "$ev" | cut -c1-12)")$deboli"
  py scrivi "$WSPEC" IMPLEMENTED "$det" || { echo "finalize: $(msg finalize.spec_unwritable)" >&2; exit 2; }
  unisci
  echo "finalize: esito=IMPLEMENTED — $(msg finalize.confirmed det="$det")"
  exit 0
fi
printf '%s\n' "${miss[@]}"
det=$(printf '%s; ' "${miss[@]}"); det=${det%; }$deboli
if [ $nfail -gt 0 ]; then
  py scrivi "$WSPEC" FAIL "$det" || { echo "finalize: $(msg finalize.spec_unwritable)" >&2; exit 2; }
  unisci
  echo "finalize: esito=FAIL — $det"
  exit 3
fi
py scrivi "$WSPEC" NEEDS_VERIFICATION "$det" || { echo "finalize: $(msg finalize.spec_unwritable)" >&2; exit 2; }
unisci
echo "finalize: esito=NEEDS_VERIFICATION — $det"
exit 1

#__PYTHON__
import datetime
import hashlib
import importlib.util
import json
import os
import re
import sys

_s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
_m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_m)
T = _m.T   # the message catalog (1.4.0), next to finalize.sh

FENCE = re.compile(r"^[ \t]*(```|~~~)")


def leggi(spec):
    with open(spec, encoding="utf-8", newline="") as f:
        return f.read().splitlines(keepends=True)


def corpo(line):
    return line.rstrip("\r\n")


def review(lines):
    """Indexes of the lines of the review section outside the fences (as cycle-state.sh)."""
    out, inf, on = [], False, False
    for i, ln in enumerate(lines):
        t = corpo(ln)
        if FENCE.match(t):
            inf = not inf
            continue
        if inf:
            continue
        if not on and t.startswith(("## Review implementazione", "## Implementation review")):
            on = True
        if on:
            out.append(i)
    return out


def primo(lines, idx, pref):
    return next((i for i in idx if corpo(lines[i]).startswith(pref)), None)


def valore(lines, idx, pref):
    i = primo(lines, idx, pref)
    return "" if i is None else corpo(lines[i])[len(pref):].strip()


def cmd_stato(spec):
    lines = leggi(spec)
    idx = review(lines)
    print("%s|%s" % (valore(lines, idx, "Review status:"), valore(lines, idx, "Feature status:")))


def load(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def cmd_gate(ev, *coppie):
    """One line for each required gate («gate=module» pairs) that does not satisfy: PASS with the report, or SKIPPED;
    key = folder. NOT RUN (declared: module without tests, skipped entries) does not satisfy but is not an error:
    at most NEEDS_VERIFICATION, with the reason «no test in the module X, checks green» (or «checks skipped»).
    FAIL of any required gate, controlli-<module> included: F."""
    key = os.path.basename(ev.rstrip("/\\"))
    gm = [c.split("=", 1) for c in coppie]
    nomi = {g for g, _m in gm}

    def gate(g):
        d = load(os.path.join(ev, g + ".json"))
        if not isinstance(d, dict):
            return None, "N|" + T("finalize.ev_missing", g=g, key=key[:12])
        if d.get("chiave") != key:
            return None, "N|" + T("finalize.ev_key", g=g)
        return d, None

    for g, m in gm:
        d, err = gate(g)
        if err:
            print(err)
            continue
        es = d.get("esito")
        if es == "PASS":
            rep = d.get("report")
            if not rep or not os.path.isfile(os.path.join(ev, rep)):
                print("N|" + T("finalize.pass_no_report", g=g))
        elif es == "NOT RUN":
            ctl = "controlli-" + m
            if g == "tests-" + m:
                c = gate(ctl)[0] if ctl in nomi else None
                ce = c.get("esito") if isinstance(c, dict) else None
                if ce == "PASS":
                    print("N|" + T("finalize.nr_checks_green", g=g, why=d.get("motivo") or T("finalize.declared"), m=m))
                elif ce == "NOT RUN":
                    print("N|" + T("finalize.nr_checks_skipped", g=g, why=d.get("motivo") or T("finalize.declared"), m=m,
                                   why2=c.get("motivo") or T("finalize.no_reason")))
                else:
                    print("N|" + T("finalize.nr_no_test", g=g, why=d.get("motivo") or T("finalize.declared"), m=m))
            elif not (g == ctl and ("tests-" + m) in nomi and
                      (gate("tests-" + m)[0] or {}).get("esito") == "NOT RUN"):
                print("N|%s: NOT RUN (%s)" % (g, d.get("motivo") or T("finalize.no_reason")))
        elif es != "SKIPPED":
            print("%s|%s: %s (%s)" % ("F" if es == "FAIL" else "N", g, es,
                                      d.get("motivo") or d.get("riepilogo") or T("finalize.no_reason")))


# counterproof.sh outcomes (harness-pt05) that mean "wrong code": FAIL; blocked and absent: missing evidence
CP_FAIL = ("rosso_import", "rosso_raccolta", "rosso_diverso", "verde")
# rosso_generico (command runner): red without report, PASS but WEAK proof -> satisfies, and is declared (W| line);
# non_eseguita (module without counterproof): declared NOT RUN -> does not satisfy and is not an error (N| line)
CP_DEBOLE = "rosso_generico"
CP_NON_ESEGUITA = "non_eseguita"


def non_eseguita(r):
    m = (r.get("motivo") or "").strip()
    return m if m.startswith("NOT RUN") else "NOT RUN (%s)" % T("finalize.declared") + (": " + m if m else "")


def cmd_controprove(run, spec, l2file=""):
    mj = os.path.join(run, "counterproof", "mutations.json")
    if os.path.isfile(mj):
        lst = load(mj)
        if not isinstance(lst, list):
            print("N|" + T("finalize.mj_unreadable"))
            return
        l2 = {}
        if l2file and os.path.isfile(l2file):
            with open(l2file, encoding="utf-8", errors="replace") as f:
                for ln in f:
                    m = re.match(r"^L2 (\S+): (OK|NO)(?: — (.*))?$", ln.strip())
                    if m:
                        l2[m.group(1)] = (m.group(2), m.group(3) or "")
        for e in lst:
            mid = e.get("id") if isinstance(e, dict) else None
            if not mid:
                print("N|" + T("finalize.mj_no_id"))
                continue
            r = load(os.path.join(run, "counterproof", str(mid) + ".json"))
            if e.get("assorbita") is True:  # L2: counts only if plan-check.sh l2 confirms it on the current code
                st = l2.get(str(mid))
                if (st and st[0] == "OK") or (isinstance(r, dict) and r.get("esito") == "rosso_asserzione"):
                    continue
                print("N|" + T("finalize.l2_invalid", mid=mid, why=st[1] if st else T("finalize.l2_unverified")))
                continue
            if not isinstance(r, dict):
                print("N|" + T("finalize.cp_no_result", mid=mid))
            elif r.get("esito") == CP_DEBOLE:
                print("W|" + T("finalize.cp_weak", mid=mid, why=r.get("motivo") or T("finalize.no_assertion")))
            elif r.get("esito") == CP_NON_ESEGUITA:
                print("N|" + T("finalize.cp_line", mid=mid, why=non_eseguita(r)))
            elif r.get("esito") != "rosso_asserzione":
                print("%s|%s" % ("F" if r.get("esito") in CP_FAIL else "N",
                                 T("finalize.cp_outcome", mid=mid, es=r.get("esito"), why=r.get("motivo") or "")))
        return
    lines = leggi(spec)
    for i in review(lines):
        t = corpo(lines[i]).strip()
        if not t.startswith("|"):
            continue
        cells = [c.strip() for c in t.strip("|").split("|")]
        if len(cells) < 4 or not re.search(r"counterproof|controprov", cells[0], re.I):
            continue
        if cells[1].lower() == "no":
            continue
        if not cells[3].upper().startswith("PASS"):
            print("%s|%s" % ("F" if cells[3].upper().startswith("FAIL") else "N",
                             T("finalize.cp_table", cell=cells[0], res=cells[3] or T("finalize.no_outcome"))))


def cmd_scrivi(spec, stato, det):
    lines = leggi(spec)
    idx = review(lines)
    fsi = primo(lines, idx, "Feature status:")
    if fsi is None:
        sys.exit(1)
    eol = lines[fsi][len(corpo(lines[fsi])):] or "\n"
    ora = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    det = " ".join(det.split())
    ver = None
    if stato in ("NEEDS_VERIFICATION", "FAIL"):
        # FAIL (harness-pt09, verdict = AND): the review decision row "APPROVED + un gate FAIL"
        lines[fsi] = "Feature status: %s" % ("PLANNED" if stato == "FAIL" else stato) + eol
        if stato == "FAIL":
            ri = primo(lines, idx, "Review status:")
            if ri is not None:
                lines[ri] = "Review status: NEEDS_CHANGES" + lines[ri][len(corpo(lines[ri])):]
        ver = "Verification: PARTIAL (finalize.sh: %s)" % det
    elif any(w in valore(lines, idx, "Verification:").lower() for w in ("provvisori", "provisional")):
        # provisional verdict of the review in parallel with VERIFY (harness-pt09): confirmed by the merge
        ver = "Verification: VERIFIED (finalize.sh: %s)" % det
    if ver is not None:
        vi = primo(lines, idx, "Verification:")
        if vi is None:
            lines.insert(fsi + 1, ver + eol)
            idx = review(lines)
        else:
            lines[vi] = ver + lines[vi][len(corpo(lines[vi])):]
    # fingerprint of the verified Reviewed snapshot: the same as snap_fp in cycle-state.sh (line 13f)
    snap = re.sub(r"[ \t]+", " ", valore(lines, idx, "Reviewed snapshot:")).strip(" ")
    sfp = hashlib.sha256(snap.encode("utf-8")).hexdigest()[:12]
    fin = "Finalize: %s — snapshot %s — %s · %s" % (stato, sfp, det, ora) + eol
    old = [i for i in idx if corpo(lines[i]).startswith("Finalize:")]
    for i in reversed(old):
        del lines[i]
    fsi = primo(lines, review(lines), "Feature status:")
    lines.insert(fsi + 1, fin)
    salva(spec, lines)


def salva(spec, lines):
    tmp = spec + ".finalize.tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write("".join(lines))
    os.replace(tmp, spec)


# --- merge requirement -> test ID -> VERIFY results (harness-pt09) ---
EV_HEAD = "Requirement evidence (finalize.sh"
# An evidence cell that starts with one of these is a requirement not covered (finalize.uncovered_*): the Italian and
# the English form, so a table written in either language is counted the same (the reviewer writes them too).
UNCOVERED = ("non coperto", "not covered")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def risultati_junit(ev, gate):
    """{(classname, name): outcome} from the JUnit of a gate (module with a junit report) in the FRESH evidence; empty
    if there is none."""
    import xml.etree.ElementTree as ET
    out = {}
    d = load(os.path.join(ev, gate + ".json")) if ev else None
    if not isinstance(d, dict) or not d.get("report"):
        return out
    try:
        root = ET.parse(os.path.join(ev, d["report"])).getroot()
    except (OSError, ET.ParseError):
        return out
    for tc in root.iter("testcase"):
        if tc.find("failure") is not None or tc.find("error") is not None:
            es = "FAIL"
        elif tc.find("skipped") is not None:
            es = "SKIPPED"
        else:
            es = "PASS"
        out[(tc.get("classname") or "", tc.get("name") or "")] = es
    return out


def senza_radice(t, radice):
    r = radice.replace("\\", "/").strip("/")
    while r.startswith("./"):
        r = r[2:]
    if r and r != "." and t.startswith(r + "/"):
        return t[len(r) + 1:]
    return t


def chiave_junit(tid, radice):
    """pytest node id (tests/x.py::C::t, also with the module root in front) -> (classname, name) of the JUnit."""
    t = senza_radice(tid.strip().replace("\\", "/"), radice)
    parti = t.split("::")
    if len(parti) < 2 or not parti[0].endswith(".py"):
        return None
    return (".".join([parti[0][:-3].replace("/", ".")] + parti[1:-1]), parti[-1])


def log_vitest(ev, gate):
    d = load(os.path.join(ev, gate + ".json")) if ev else None
    if not isinstance(d, dict) or not d.get("report"):
        return []
    try:
        with open(os.path.join(ev, d["report"]), encoding="utf-8", errors="replace") as f:
            return [" ".join(ANSI.sub("", l).split()) for l in f.read().splitlines()]
    except OSError:
        return []


def esito_vitest(righe, tid, radice):
    """The wrapper report (test-fast.sh) has no per-test outcome: FAIL from the "FAIL <id>" lines, PASS only at the
    file level ("✓ <file>" line). Nothing else is a result. The module root in front of the ID is removed."""
    t = senza_radice(" ".join(tid.strip().replace("\\", "/").split()), radice)
    fine = r"(\s|$)"
    if any(re.match(r"(FAIL|❯|×)\s+" + re.escape(t) + fine, l) for l in righe):
        return "FAIL"
    if " > " not in t and any(re.match(r"✓\s+" + re.escape(t) + fine, l) for l in righe):
        return "PASS"
    return None


def cmd_unisci(spec, cop, ev, run, *moduli):
    """moduli: «name|report|root»; the report format (junit, vitest, nessuno) says how to read the results of the
    gate tests-<name>, never the gate name. A module with report nessuno gives no per-test results."""
    obj = load(cop)
    cov = obj.get("copertura") if isinstance(obj, dict) else None
    if not isinstance(cov, list):
        print("finalize: " + T("finalize.no_cov_map", cop=cop))
        return
    mods = [x.split("|", 2) for x in moduli if x.count("|") >= 2]
    ju = [("tests-" + n, rad, risultati_junit(ev, "tests-" + n)) for n, rep, rad in mods if rep == "junit"]
    vi = [("tests-" + n, rad, log_vitest(ev, "tests-" + n)) for n, rep, rad in mods if rep == "vitest"]

    def risultato(tid):
        for g, rad, res in ju:
            k = chiave_junit(tid, rad)
            if k is None:
                continue
            if k in res:
                return res[k] + " (%s)" % g
        if any(chiave_junit(tid, rad) is not None for _g, rad, _r in ju):
            return None
        r = load(os.path.join(run, "counterproof", tid.strip() + ".json")) if re.match(r"^[\w.-]+$", tid.strip()) else None
        if isinstance(r, dict) and r.get("esito"):
            es = r["esito"]
            if es == CP_DEBOLE:
                return "PASS (%s)" % T("finalize.cp_weak_cell", es=es)
            if es == CP_NON_ESEGUITA:
                return "NOT RUN (%s)" % T("finalize.cp_cell", es=es)
            return "%s (%s)" % ("PASS" if es == "rosso_asserzione" else "BLOCKED" if es == "bloccato" else "FAIL",
                                T("finalize.cp_cell", es=es))
        for g, rad, righe in vi:
            es = esito_vitest(righe, tid, rad)
            if es is not None:
                return es + " (%s)" % g
        return None

    cella = lambda s: " ".join(str(s).split()).replace("|", "\\|")
    righe, scoperti = [], 0
    for voce in cov:
        if not isinstance(voce, dict):
            continue
        ids = [str(i) for i in voce.get("test") or [] if str(i).strip()]
        ris = [(i, risultato(i)) for i in ids]
        senza = [i for i, r in ris if r is None]
        if not ids:
            evid = T("finalize.uncovered_no_id")
        elif senza:
            evid = T("finalize.uncovered_no_result", ids="; ".join(senza))
        else:
            evid = " · ".join("%s → %s" % (i, r) for i, r in ris)
        scoperti += evid.startswith(UNCOVERED)
        righe.append("| %s | %s | %s |" % (cella(voce.get("requisito", "")), cella("; ".join(ids) or "—"), cella(evid)))

    lines = leggi(spec)
    idx = review(lines)
    fi = primo(lines, idx, "Finalize:")
    if fi is None:
        return
    eol = lines[fi][len(corpo(lines[fi])):] or "\n"
    old = primo(lines, idx, EV_HEAD)
    if old is not None:   # the table of a previous finalize: header and the "|" lines that follow it
        j = old + 1
        while j < len(lines) and corpo(lines[j]).lstrip().startswith("|"):
            j += 1
        del lines[old:j]
        fi = primo(lines, review(lines), "Finalize:")
    k12 = os.path.basename(ev.rstrip("/\\"))[:12] if ev else T("finalize.no_current_key")
    blocco = ["%s: %s)" % (EV_HEAD, T("finalize.ev_head", k12=k12)),
              "| Requirement | Test IDs | Evidence |", "|---|---|---|"] + righe
    lines[fi + 1:fi + 1] = [b + eol for b in blocco]
    salva(spec, lines)
    print("finalize: " + T("finalize.ev_composed", n=len(righe), k=scoperti))


sys.stdout.reconfigure(encoding="utf-8")
{"stato": cmd_stato, "gate": cmd_gate, "controprove": cmd_controprove, "scrivi": cmd_scrivi,
 "unisci": cmd_unisci}[sys.argv[1]](*sys.argv[2:])
