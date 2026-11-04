#!/usr/bin/env bash
# rollback.test.sh — Maat 1.5.1: the way back to the bash engine (FIC_DRIVER=0) and forward to Python, on the same
# project, in the middle of a cycle. The orchestrator is always `driver.py run`; the ENGINE is who decides: P = Python
# (FIC_DRIVER unset: `driver.py next` inside run and in the wrappers, `driver.py valida` in run-phase.sh), B = bash
# (FIC_DRIVER=0: run takes Next/State from standalone cycle-state.sh, run-phase.sh validates with VALIDA_PY). A rollback
# is one invocation of run with one engine followed by the next with the other one. Real run-phase.sh, cycle-state.sh
# and plan-check.sh; fake claude (by FIC_PHASE), gates and finalize; throwaway git repo, temporary HOME. Only "it":
# changing language stops a cycle on purpose (1.4.0), it is not a rollback.
#   bash plugins/maat/scripts/rollback.test.sh
#   ROLLBACK_TEST_RAPIDO=1 bash plugins/maat/scripts/rollback.test.sh   # S1 only (+ P17), counterproofs (a) and (d)
#   ROLLBACK_TEST_TIENI=1 …   # keeps the temporary folder (references, resumes, photos) for a diagnosis
#
# MECHANICS. References: for each scenario and engine X ∈ {P, B} the whole scenario with X, one phase per invocation
# (`driver.py run --max-fasi 1`); after the invocation that closes point k the copy C_X(k) (`cp -a` of the WHOLE repo,
# .git included: .pre-tree/.post-tree are git objects that must exist in the restored repo) and its photo F_X(k). Plus
# one single run without --max-fasi, which must end like the sliced one (same labels, same end). Resumes: for each
# point k and the other engine Y: C_X(k) back in the SAME path (rm -rf, cp -a, .git included), lock clean, then
# `driver.py run` with Y (default budget) up to the end; the human actions of the scenario (identical in both
# directions) between the invocations.
# Scenarios (Diego's cut, 03/11: S2 lanes and S3 chains are out, their decision equivalence stays proved by
# driver.equiv and the oracle; their rollback is not proved here):
#   S1 format 1, spec without a plan: P1 01-plan · P2 02-implement · P3 03-review NEEDS_CHANGES · P4 04-fix ·
#      P5 05-review APPROVED (DONE)
#   S4 STOP and recovery, format 1: P14 01-implement with a non-defensive deviation (STOP result.json; then the human
#      renames it .result.json.visto) · P15 02-implement with defensive deviations only (AVVISO, REVIEW) · P16 a phase
#      interrupted (log/03-review.running without .exit, written by the test: RUNNING, exit 4; then the human removes it)
#   P17 S1, P→B only: P2 with the driver failing on `next` at the end-of-phase reader of run-phase.sh (the spy, armed
#      by a counter file), then the resume with B
# 8 points × 2 directions + P17 = 17 resumes; ROLLBACK_TEST_RAPIDO=1: S1 × 2 + P17 = 11.
# ASSERTIONS for each resume (scenario, point k, direction X→Y):
#   R0 (once per scenario, S1) the two references are equal step by step: F_P(k) = F_B(k), same Next lines
#   R1 no spurious STOP: final Driver result and exit those of R_X (and those of R_X before each human action); no
#      exit 6 of run-phase.sh, no «harness cambiato»/«harness changed»
#   R2 same run dirs: per spec with a run dir, the sorted list of log/*.esito and log/*.exit of R_X
#   R3 same harness.fp, byte for byte, as F_X(k) and as the end of R_X; --harness-fp-confronta UGUALE with FIC_DRIVER=0
#      and without
#   R4 same Next at the resume: first `driver: Next:` of the resume = the one of R_X after k; on F_X(k), before the
#      resume, cycle-state.sh with FIC_DRIVER=0 and without prints the same output
#   R5 same final photo as R_X
#   R6 Y really decided: the «motore bash» event in each invocation iff Y = B; the FIC_DRIVER_PY spy called iff Y = P
#   P17 (instead of R1-R2): (i) the faulty invocation launches only 02-implement, exit 1; (ii) the resume with B starts
#      from IMPLEMENT, 01-plan the only plan; (iii) only the implement with the STOP outcome is launched again, once;
#      (iv) DONE and the photo of R_B but for the phase in more; (v) R3 and R6
# THE PHOTO: the files of the test repo (work tree and .claude/, without .git: out of the comparison, never out of the
# restore) with the sha256 of the normalised content. NORMALISATIONS, the closed list (anything else that differs is red):
#   N1 UTC times AAAA-MM-GGThh:mm:ssZ → <ora> (the Finalize: line written by finalize, the since of the messages)
#   N2 driver.log and log/*.stderr out of the photo (the engine event and the times: R4 and R6 read them)
#   N3 log/*.running and the lock files (plan.lock, pid) out of the photo
# COUNTERPROOFS (on a copy of the plugin, which has its own fingerprint: the whole scenario runs in the copy; S1, P→B):
#   (a) run-phase.sh with FIC_DRIVER in the fingerprint (HFP_PY) → R1 and R3 red (proof of D5)
#   (b) driver.py with one more line in the State hash → R4 red at P2, R0 red
#   (c) valida of driver.py adding a field to result.json → R1 and R5 red (the schema has additionalProperties false)
#   (c′) valida writing result.json with indent=2 (valid) → R5 red, R1 green, at P1; R0 red
#   (d) the resume function not setting FIC_DRIVER=0 (a mutated copy of the function, in this suite) → R6 red
set -uo pipefail
export MAAT_LINGUA=it   # the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # plugin root
. "$HERE/python.sh" || { echo "rollback.test.sh: nessun interprete Python (FIC_PYTHON)"; exit 2; }
RAPIDO=${ROLLBACK_TEST_RAPIDO:-0}
T=$(mktemp -d) || exit 2
[ "${ROLLBACK_TEST_TIENI:-0}" = 1 ] && echo "rollback.test.sh: cartella tenuta $T" || trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset FIC_DRIVER FIC_DRIVER_PY FIC_DRIVER_CERT FIC_DRIVER_ROOT FIC_RUN_PHASE FIC_CONTEXT_PACK FIC_MAX_FASI FIC_REPO \
  FIC_LOCK FIC_CYCLE_STATE FIC_CORSIE MAAT_ROOT MAAT_CONFIG SPIA_CONTATORE
pass=0 fail=0 riprese=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
pyw() { cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }   # a path for native Python in an environment variable
t0=$(date +%s)

W=$T/repo   # the test repo: references and resumes always in this path (absolute paths and roots coincide)
SP=.claude/.ai-workflow/spec-x.md
RUN=.claude/.ai-workflow/spec-x.run
EFP=$(printf '' | sha256sum | cut -c1-12)   # finalize's fingerprint of an empty Reviewed snapshot (driver.test.sh §11)
SPY=$T/spia.log

# --- fakes -------------------------------------------------------------------------------------------------------
# claude by FIC_PHASE (RB_SCEN = scenario). plan: the plan APPROVED with the Approved basis of plan-check.sh basis.
# implement/fix: a FIXED content of src/a.py (an implement launched again in completion writes the same file: P17).
# review: S1 NEEDS_CHANGES at the first round, then APPROVED/IMPLEMENTED; S4 APPROVED at once. S4 implement: the first
# one with a non-defensive deviation (STOP), the next ones with a defensive one only.
cat > "$T/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
sp=$E2E_SPEC; run=${sp%.md}.run
res() { # $1 phase, $2 reason, $3 deviazioni (JSON), $4 file (JSON items)
  printf '{"type":"result","result":"PHASE RESULT %s: OK — %s","structured_output":{"fase":"%s","esito":"OK","motivo":"%s","deviazioni":%s,"bloccato_su":"nessuno","file":[%s],"gate_interni":[],"finding":[]}}\n' \
    "$1" "$2" "$1" "$2" "${3:-[]}" "${4:-}"
}
edit() { echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/a.py"}}]}}'; }
case "$FIC_PHASE" in
  plan)
    printf '%s\n' "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
      "### Passi" "1. Modificare \`src/a.py\`." "### Changelog revisione piano" "- giro 1: ok" >> "$sp"
    cur=$(bash "$RB_PC" basis "$sp" | sed -n 's/^Basis: //p')
    sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$sp"
    res plan "piano scritto" ;;
  implement)
    printf 'uno\nimplement\n' > "$FIC_REPO/src/a.py"; edit; dev='[]'
    if [ "$RB_SCEN" = S4 ]; then
      if [ "$(ls "$run/log" 2>/dev/null | grep -c 'implement\.esito$')" -eq 0 ]; then dev='["campo rinominato rispetto al piano"]'
      else dev='["difensiva: ramo per un file vuoto"]'; fi
    fi
    res implement fatto "$dev" '"src/a.py"' ;;
  fix) printf 'uno\nimplement\nfix\n' > "$FIC_REPO/src/a.py"; edit; res fix corretto '[]' '"src/a.py"' ;;
  review)
    if [ "$RB_SCEN" = S1 ] && ! grep -q '^## Review implementazione' "$sp"; then
      printf '%s\n' "" "## Review implementazione" "Review status: NEEDS_CHANGES" "Feature status: PLANNED" \
        "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" >> "$sp"
      res review "da correggere"
    elif [ "$RB_SCEN" = S1 ]; then
      sed -i 's/^Review status: .*/Review status: APPROVED/; s/^Feature status: .*/Feature status: IMPLEMENTED/; s|^Review rounds: .*|Review rounds: 2/3 · post-approval NEEDS_CHANGES: 0/1|' "$sp"
      res review approvata
    else
      printf '%s\n' "" "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" \
        "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" >> "$sp"
      res review approvata
    fi ;;
esac
EOF
chmod +x "$T/claude"
printf '#!/usr/bin/env bash\necho "gates: esito=PASS chiave=k0 evidence=-"\n' > "$T/gates"; chmod +x "$T/gates"
# finalize: signs an APPROVED review with the snapshot finalize would write for an empty Reviewed snapshot (§11)
cat > "$T/fin" <<EOF
#!/usr/bin/env bash
d=\${!#}; s=\${d%.run}.md
if grep -q '^Review status: APPROVED' "\$s"; then
  printf 'Finalize: IMPLEMENTED — snapshot %s — signed · %s\n' "$EFP" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "\$s"
  echo "finalize: esito=IMPLEMENTED"
else echo "finalize: esito=NEEDS_CHANGES"; fi
EOF
chmod +x "$T/fin"
# the FIC_DRIVER_PY spy (R6): records `next`/`valida` and hands them to driver.py (SPIA_DRV). P17: with SPIA_CONTATORE
# naming a file that holds N, the N-th `next` from then on exits 1 (once). A counter, not «every next»: the target is
# the end-of-phase reader of run-phase.sh (:1747) only; in a real cycle more `next` calls can come in the same
# invocation (finalize.sh and gates.sh run in the phase, the review readers, cycle-state.sh by hand), and a spy that
# failed on all of them would test something else. Here the test arms N = 1 right before the implement.
cat > "$T/spia.py" <<'EOF'
import os, runpy, sys
open(os.environ["SPY"], "a").write(sys.argv[1] + "\n")
k = os.environ.get("SPIA_CONTATORE", "")
if sys.argv[1] == "next" and k and os.path.isfile(k):
    n = int(open(k).read().strip() or "0") - 1
    open(k, "w").write("%d\n" % n)
    if n == 0:
        open(os.environ["SPY"], "a").write("next-guasto\n")
        sys.stderr.write("rumore\nTraceback finto: next rotto\n\n")
        sys.exit(1)
sys.argv = [os.environ["SPIA_DRV"]] + sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
EOF
# the photo: "<sha256> <path>", the normalisations N1-N3 of the header and nothing else
cat > "$T/foto.py" <<'EOF'
import hashlib, os, re, sys
root = sys.argv[1]
ora = re.compile(rb"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")    # N1
fuori = re.compile(r"(^|/)driver\.log$|(^|/)log/[^/]*\.(stderr|running)$|\.lock$")   # N2, N3
righe = []
for d, dirs, files in os.walk(root):
    rel = os.path.relpath(d, root).replace(os.sep, "/")
    rel = "" if rel == "." else rel + "/"
    if rel == "" and ".git" in dirs:
        dirs.remove(".git")
    for f in files:
        p = rel + f
        if fuori.search(p):
            continue
        b = open(os.path.join(d, f), "rb").read()
        righe.append("%s %s" % (hashlib.sha256(ora.sub(b"<ora>", b)).hexdigest(), p))
sys.stdout.write("".join(r + "\n" for r in sorted(righe, key=lambda r: r[65:])))
EOF
foto() { "$FIC_PY" "$T/foto.py" "$1"; }   # $1 = folder

# --- the test repo and the scenarios ----------------------------------------------------------------------------
nuovo_repo() { # $1 scenario → a fresh repo in $W, saved as $CX/C0
  rm -rf "$W" "$T/lock"; mkdir -p "$W"
  (cd "$W" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false \
    && mkdir -p src .claude/.ai-workflow && printf 'spec-*\n' > .claude/.ai-workflow/.gitignore \
    && printf 'uno\n' > src/a.py && git add -A && git commit -qm init) || exit 2
  printf '%s\n' "# X" "## Contesto" "Contesto ($1)." "## Requisiti funzionali" "1. Fare A." > "$W/$SP"
  if [ "$1" = S4 ]; then
    printf '%s\n' "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
      "### Passi" "1. Modificare \`src/a.py\`." "### Changelog revisione piano" "- giro 1: ok" >> "$W/$SP"
    local cur; cur=$(cd "$W" && bash "$ROOT/scripts/plan-check.sh" basis "$SP" | sed -n 's/^Basis: //p')
    sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$W/$SP"
  fi
  salva "$CX/C0"
}
salva() { rm -rf "$1"; cp -a "$W" "$1"; }
ripristina() { rm -rf "$W" "$T/lock"; cp -a "$1" "$W"; }
# the steps of each scenario: I = one invocation with --max-fasi 1, H:<action> = a human action; @<point> = the point
# closed by that step. The resume steps: R = one invocation with the default budget.
S1_PASSI=(I@P1 I@P2 I@P3 I@P4 I@P5)
S4_PASSI=(I@P14 I H:visto I@P15 H:running@P16 I H:norunning I)
riprese_di() { # $1 point → the resume steps
  case $1 in P14) echo "R H:visto R" ;; P16) echo "R H:norunning R" ;; *) echo R ;; esac
}
azione() { # $1 human action (the same in both directions)
  case $1 in
    visto) mv "$W/$RUN/log/01-implement.result.json" "$W/$RUN/log/01-implement.result.json.visto" ;;
    running) echo "pid=999999" > "$W/$RUN/log/03-review.running" ;;
    norunning) rm -f "$W/$RUN/log/03-review.running" ;;
  esac
}

# one invocation of driver.py run of the plugin $PR: $1 engine P|B, $2 output file, then the arguments → irc
inv() {
  local m; case $1 in B) m=(FIC_DRIVER=0) ;; *) m=(-u FIC_DRIVER) ;; esac
  rm -rf "$T/lock"
  (cd "$W" && env "${m[@]}" RB_SCEN="$SCEN" RB_PC="$PR/scripts/plan-check.sh" E2E_SPEC="$W/$SP" SPY="$SPY" \
    SPIA_DRV="$(pyw "$PR/scripts/driver.py")" FIC_DRIVER_PY="$T/spia.py" FIC_DRIVER_ROOT="$PR" FIC_LOCK="$T/lock" \
    FIC_REPO="$W" CLAUDE_BIN="$T/claude" FIC_GATES="$T/gates" FIC_FINALIZE="$T/fin" FIC_LANES=0 FIC_CONTEXT_PACK=- \
    "$FIC_PY" "$PR/scripts/driver.py" run "$SP" "${@:3}" > "$2" 2>&1 </dev/null)
  irc=$?
}
norm() { sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<ora>/g' "$@"; }   # N1 on the output lines
risultato() { grep '^driver: Driver result: ' "$1" | tail -1 | norm; }   # the end line of an invocation
prima_next() { grep -m1 '^driver: Next: ' "$1" | norm; }
etichette() { ls "$W/$RUN/log" 2>/dev/null | sed -n 's/\.esito$//p' | tr '\n' ' '; }
elenco_run() { # R2: per run dir, the sorted .esito and .exit of its log
  (cd "$1" && find . -path ./.git -prune -o -type d -name '*.run' -print | LC_ALL=C sort | while IFS= read -r d; do
    echo "$d: $(ls "$d/log" 2>/dev/null | grep -E '\.(esito|exit)$' | LC_ALL=C sort | tr '\n' ' ')"; done)
}

# the references of scenario $SCEN with engine $1, in $CX/ref-$1: per step n the output n.out and n.rc; per point the
# copy C-<point>, its photo C-<point>.foto and N-<point> = the first Next line of the next invocation (the last Next
# of the scenario after the last step); the end: FINE (copy), FINE.foto, FINE.run (R2)
riferimento() {
  local X=$1 d=$CX/ref-$1 n=0 s p q q0 t a nx
  rm -rf "$d"; mkdir -p "$d"; ripristina "$CX/C0"; rm -f "$SPY"
  local -n passi=${SCEN}_PASSI
  for s in "${passi[@]}"; do
    n=$((n + 1)); a=${s%@*}; p=""; [ "$a" != "$s" ] && p=${s#*@}
    case $a in
      I) inv "$X" "$d/$n.out" --max-fasi 1; echo "$irc" > "$d/$n.rc" ;;
      H:*) azione "${a#H:}" ;;
    esac
    [ -n "$p" ] && { salva "$d/C-$p"; foto "$d/C-$p" > "$d/C-$p.foto"; echo "$n" > "$d/C-$p.passo"; }
  done
  salva "$d/FINE"; foto "$d/FINE" > "$d/FINE.foto"; elenco_run "$d/FINE" > "$d/FINE.run"; echo "$n" > "$d/FINE.passi"
  for p in $(ls "$d" | sed -n 's/^C-\(P[0-9]*\)\.passo$/\1/p'); do
    # the first Next of the next invocation; but if a human action the resume does not make comes first (P15: the
    # .running of P16), or the point closes the scenario, the last Next of the invocation that closed the point
    q0=$(cat "$d/C-$p.passo"); q=$q0; nx=""; t=0
    while [ "$q" -lt "$n" ]; do
      q=$((q + 1)); [ -f "$d/$q.out" ] && { nx=$(prima_next "$d/$q.out"); t=1; break; }
      case " $(riprese_di "$p") " in *" $(passo_n "$q") "*) ;; *) break ;; esac
    done
    [ $t = 0 ] && nx=$(grep '^driver: Next: ' "$d/$q0.out" | tail -1 | norm)   # the point closes the scenario
    printf '%s\n' "$nx" > "$d/N-$p"
  done
}
passo_n() { local -n pp=${SCEN}_PASSI; local s=${pp[$(($1 - 1))]}; echo "${s%@*}"; }   # $1 index → the step
passo_di() { # $1 step without its point → its index in the steps of $SCEN (the first one)
  local -n pp=${SCEN}_PASSI; local i=0 s
  for s in "${pp[@]}"; do i=$((i + 1)); [ "${s%@*}" = "$1" ] && { echo $i; return; }; done
}
ultimo_out() { ls "$1"/*.out | sed 's|.*/||; s|\.out$||' | sort -n | tail -1; }   # $1 = ref dir → the last invocation

# a resume: C_X(k) back in place, the R4 pre-check, then the resume steps with engine Y → $CX/rip-X-k-Y/
riprendi() { # $1 X, $2 point, $3 Y
  local X=$1 k=$2 Y=$3 d=$CX/rip-$1-$2-$3 n=0 s
  rm -rf "$d"; mkdir -p "$d"; ripristina "$CX/ref-$X/C-$k"; rm -f "$SPY"
  (cd "$W" && env FIC_DRIVER=0 FIC_REPO="$W" bash "$PR/scripts/cycle-state.sh" "$SP" > "$d/cs-B" 2>&1)
  (cd "$W" && env -u FIC_DRIVER FIC_REPO="$W" FIC_DRIVER_ROOT="$PR" bash "$PR/scripts/cycle-state.sh" "$SP" > "$d/cs-P" 2>&1)
  for s in $(riprese_di "$k"); do
    n=$((n + 1))
    case $s in
      R) inv "$Y" "$d/$n.out"; echo "$irc" > "$d/$n.rc" ;;  # MOTORE-RIPRESA
      H:*) azione "${s#H:}"; echo "$s" > "$d/$n.azione" ;;
    esac
  done
  [ -f "$SPY" ] && cp "$SPY" "$d/spia" || : > "$d/spia"
  salva "$d/FINE"; foto "$d/FINE" > "$d/FINE.foto"; elenco_run "$d/FINE" > "$d/FINE.run"
}

# --- the assertions (0 = holds); DIAG=1 prints why one does not -------------------------------------------------
DIAG=1
diag() { [ "$DIAG" = 1 ] && printf '    %s\n' "$@" >&2; return 1; }
r0() { # R0: the two references of $SCEN are equal step by step
  local p n ok=0
  for p in $(ls "$CX/ref-P" | sed -n 's/^C-\(P[0-9]*\)\.passo$/\1/p'); do
    cmp -s "$CX/ref-P/C-$p.foto" "$CX/ref-B/C-$p.foto" || { diag "R0 $p foto:" "$(diff "$CX/ref-P/C-$p.foto" "$CX/ref-B/C-$p.foto" | head -6)"; ok=1; }
  done
  for n in $(ls "$CX/ref-P" | sed -n 's/\.out$//p'); do
    [ "$(grep '^driver: Next: ' "$CX/ref-P/$n.out" | norm)" = "$(grep '^driver: Next: ' "$CX/ref-B/$n.out" 2>/dev/null | norm)" ] \
      || { diag "R0 passo $n: righe Next diverse"; ok=1; }
    [ "$(risultato "$CX/ref-P/$n.out")" = "$(risultato "$CX/ref-B/$n.out")" ] && cmp -s "$CX/ref-P/$n.rc" "$CX/ref-B/$n.rc" \
      || { diag "R0 passo $n: Driver result o exit diversi"; ok=1; }
  done
  return $ok
}
r1() { # $1 X, $2 point, $3 Y
  local d=$CX/rip-$1-$2-$3 r=$CX/ref-$1 n last a q ok=0
  last=$(ls "$d" | sed -n 's/\.out$//p' | sort -n | tail -1)
  [ "$(risultato "$d/$last.out")" = "$(risultato "$r/$(ultimo_out "$r").out")" ] && cmp -s "$d/$last.rc" "$r/$(ultimo_out "$r").rc" \
    || { diag "R1 fine: $(risultato "$d/$last.out") rc=$(cat "$d/$last.rc")" "  atteso: $(risultato "$r/$(ultimo_out "$r").out") rc=$(cat "$r/$(ultimo_out "$r").rc")"; ok=1; }
  for a in $(ls "$d" | sed -n 's/\.azione$//p'); do   # before each human action: the result of R_X before the same one
    q=$(passo_di "$(cat "$d/$a.azione")")
    [ -n "$q" ] && [ "$(risultato "$d/$((a - 1)).out")" = "$(risultato "$r/$((q - 1)).out")" ] && cmp -s "$d/$((a - 1)).rc" "$r/$((q - 1)).rc" \
      || { diag "R1 prima di $(cat "$d/$a.azione"): $(risultato "$d/$((a - 1)).out")"; ok=1; }
  done
  if grep -qi 'harness cambiato\|harness changed' "$d"/*.out "$d"/FINE/$RUN/log/*.stderr 2>/dev/null; then diag "R1: harness cambiato nei log"; ok=1; fi
  if grep -qx 6 "$d"/FINE/$RUN/log/*.exit 2>/dev/null; then diag "R1: exit 6 di run-phase.sh"; ok=1; fi
  return $ok
}
r2() { cmp -s "$CX/rip-$1-$2-$3/FINE.run" "$CX/ref-$1/FINE.run" || diag "R2:" "$(diff "$CX/ref-$1/FINE.run" "$CX/rip-$1-$2-$3/FINE.run")"; }
r3() { # harness.fp byte for byte, and --harness-fp-confronta UGUALE with either engine, on the end of the resume
  local d=$CX/rip-$1-$2-$3/FINE e0 e1
  cmp -s "$d/$RUN/harness.fp" "$CX/ref-$1/C-$2/$RUN/harness.fp" && cmp -s "$d/$RUN/harness.fp" "$CX/ref-$1/FINE/$RUN/harness.fp" \
    || { diag "R3: harness.fp diverso"; return 1; }
  e0=$(cd "$d" && FIC_DRIVER=0 bash "$PR/scripts/run-phase.sh" --harness-fp-confronta "$RUN/harness.fp" "$d" 2>/dev/null)
  e1=$(cd "$d" && env -u FIC_DRIVER bash "$PR/scripts/run-phase.sh" --harness-fp-confronta "$RUN/harness.fp" "$d" 2>/dev/null)
  [ "${e0%% *}" = UGUALE ] && [ "${e1%% *}" = UGUALE ] || diag "R3: confronta FIC_DRIVER=0 «$e0», predefinito «$e1»"
}
r4() {
  local d=$CX/rip-$1-$2-$3
  [ "$(prima_next "$d/1.out")" = "$(cat "$CX/ref-$1/N-$2")" ] || { diag "R4: «$(prima_next "$d/1.out")» atteso «$(cat "$CX/ref-$1/N-$2")»"; return 1; }
  cmp -s "$d/cs-B" "$d/cs-P" || diag "R4: cycle-state.sh diverso fra i motori:" "$(diff "$d/cs-B" "$d/cs-P" | head -6)"
}
r5() { cmp -s "$CX/rip-$1-$2-$3/FINE.foto" "$CX/ref-$1/FINE.foto" || diag "R5:" "$(diff "$CX/ref-$1/FINE.foto" "$CX/rip-$1-$2-$3/FINE.foto" | head -8)"; }
r6() { # $3 = Y
  local d=$CX/rip-$1-$2-$3 f
  for f in "$d"/*.out; do
    if [ "$3" = B ]; then grep -q '^driver: motore bash (FIC_DRIVER=0)' "$f" || { diag "R6: nessun «motore bash» in ${f##*/}"; return 1; }
    else ! grep -q '^driver: motore bash' "$f" || { diag "R6: «motore bash» con P in ${f##*/}"; return 1; }; fi
  done
  if [ "$3" = B ]; then [ ! -s "$d/spia" ] || diag "R6: la spia ha chiamate con B: $(sort "$d/spia" | uniq -c | tr '\n' ' ')"
  # P: the spy has calls (run-phase.sh valida, its readers) when the resume launches a phase; without launches (P5)
  # only the `next` inside run decides, which no spy sees: there R6 is the missing event
  elif grep -q '^driver: ▶ ' "$d"/*.out; then [ -s "$d/spia" ] || diag "R6: la spia non ha chiamate con P"; fi
}
tutte() { # $1 X, $2 point, $3 Y: R1-R6 of one resume, one check each
  local t="$2 $1→$3"
  check "$SCEN $t R1 nessuno STOP spurio (fine, exit, prima delle azioni umane; nessun exit 6, nessun harness cambiato)" "r1 $1 $2 $3"
  check "$SCEN $t R2 stesse run dir (.esito e .exit di R_$1)" "r2 $1 $2 $3"
  check "$SCEN $t R3 stesso harness.fp, confronta UGUALE con i due motori" "r3 $1 $2 $3"
  check "$SCEN $t R4 stesso Next alla ripresa, cycle-state.sh uguale con i due motori" "r4 $1 $2 $3"
  check "$SCEN $t R5 stessa foto finale di R_$1" "r5 $1 $2 $3"
  check "$SCEN $t R6 ha deciso davvero $3 (evento del motore, spia)" "r6 $1 $2 $3"
}
punti() { local -n pp=${SCEN}_PASSI; printf '%s\n' "${pp[@]}" | sed -n 's/.*@//p'; }

# --- a scenario: references, R0, the single run, the resumes in both directions ---------------------------------
scenario() { # $1 scenario, $2 context folder name
  SCEN=$1 CX=$T/$2 PR=$ROOT; mkdir -p "$CX"; nuovo_repo "$1"
  local X Y k n
  for X in P B; do riferimento $X; done
  n=$(ultimo_out "$CX/ref-P")
  check "$1 riferimenti: P e B finiscono DONE (exit 0)" '[ "$(cat "$CX/ref-P/$n.rc")" = 0 ] && [ "$(cat "$CX/ref-B/$n.rc")" = 0 ] && risultato "$CX/ref-P/$n.out" | grep -q "^driver: Driver result: DONE — "'
  [ "$1" = S1 ] && check "S1 R0 i due riferimenti uguali passo per passo (foto, righe Next, Driver result ed exit)" r0
  for X in P B; do   # the single run without --max-fasi ends like the sliced one (S4: with the same human actions)
    ripristina "$CX/C0"
    if [ "$1" = S1 ]; then inv $X "$CX/unica-$X.out"
    else inv $X "$CX/unica-$X.0.out"; inv $X "$CX/unica-$X.1.out"; azione visto; inv $X "$CX/unica-$X.out"; fi
    check "$1 corsa unica con $X: stesse etichette e stessa fine della corsa a fette" '[ "$(etichette)" = "$(ls "$CX/ref-$X/FINE/$RUN/log" | sed -n "s/\.esito\$//p" | tr "\n" " ")" ] && [ "$(risultato "$CX/unica-$X.out")" = "$(risultato "$CX/ref-$X/$n.out")" ]'
  done
  for k in $(punti); do
    for X in P B; do
      Y=P; [ $X = P ] && Y=B
      riprendi $X "$k" $Y; riprese=$((riprese + 1))
      tutte $X "$k" $Y
    done
  done
}

scenario S1 s1
[ "$RAPIDO" = 1 ] || scenario S4 s4
echo "rollback.test.sh: scenari finiti ($(( $(date +%s) - t0 )) s)"

# --- P17: S1, the driver fails on `next` at the end of 02-implement (P), then the resume with B -------------------
SCEN=S1 CX=$T/s1 PR=$ROOT
d=$CX/p17; mkdir -p "$d"; ripristina "$CX/ref-P/C-P1"; rm -f "$SPY"; echo 1 > "$T/contatore"
SPIA_CONTATORE="$T/contatore" inv P "$d/1.out"; echo "$irc" > "$d/1.rc"; cp "$SPY" "$d/spia-guasto"
salva "$d/C-P17"
check "P17 (i) l'invocazione guasta lancia la sola 02-implement e si ferma: «Driver result: STOP — PHASE RESULT implement: STOP — driver.py next …», exit 1" '[ "$(cat "$d/1.rc")" = 1 ] && grep -q "^driver: Driver result: STOP — PHASE RESULT implement: STOP — driver.py next non riuscito (exit 1): Traceback finto: next rotto" "$d/1.out" && [ "$(grep "^driver: ▶ " "$d/1.out" | sed "s/^driver: ▶ //; s/ .*//" | tr "\n" " ")" = "02-implement " ] && [ "$(grep -c "^next-guasto$" "$d/spia-guasto")" = 1 ]'
check "  l'.esito di 02-implement e' STOP con state= vuoto, il result.json c'e', nessun .gates" 'sed -n 1p "$W/$RUN/log/02-implement.esito" | grep -q "^PHASE RESULT implement: STOP — driver.py next non riuscito (exit 1): " && grep -qx "state=" "$W/$RUN/log/02-implement.esito" && [ -f "$W/$RUN/log/02-implement.result.json" ] && [ ! -f "$W/$RUN/log/02-implement.gates" ]'
rm -f "$SPY" "$T/contatore"
(cd "$W" && env FIC_DRIVER=0 FIC_REPO="$W" bash "$PR/scripts/cycle-state.sh" "$SP" > "$d/cs-B" 2>&1)
(cd "$W" && env -u FIC_DRIVER FIC_REPO="$W" FIC_DRIVER_ROOT="$PR" bash "$PR/scripts/cycle-state.sh" "$SP" > "$d/cs-P" 2>&1)
inv B "$d/2.out"; echo "$irc" > "$d/2.rc"; [ -f "$SPY" ] && cp "$SPY" "$d/spia" || : > "$d/spia"
salva "$d/FINE"; foto "$d/FINE" > "$d/FINE.foto"; riprese=$((riprese + 1))
check "P17 (ii) la ripresa con B parte da IMPLEMENT, non da PLAN; 01-plan resta l'unico plan" 'prima_next "$d/2.out" | grep -q "^driver: Next: IMPLEMENT" && [ "$(ls "$W/$RUN/log" | grep -c "plan\.esito$")" = 1 ] && [ -f "$W/$RUN/log/01-plan.esito" ] && cmp -s "$d/cs-B" "$d/cs-P"'
check "P17 (iii) si rilancia solo l'implement con l'esito STOP, una volta (03-implement di completamento), poi review, fix, review" '[ "$(etichette)" = "01-plan 02-implement 03-implement 04-review 05-fix 06-review " ] && sed -n 1p "$W/$RUN/log/03-implement.esito" | grep -q "^PHASE RESULT implement: OK"'
# (iv) the photo of R_B but for the phase in more: the faulty 02-implement out, the labels after it shifted down by
# one; out too the .pre-tree and the .cambiati-fase of the completion implement: it starts from the tree the first
# implement left (R_B's from the initial one) and so changes no path. By construction, not an engine difference
P17_FUORI=' \.claude/\.ai-workflow/spec-x\.run/log/02-implement\.\(pre-tree\|cambiati-fase\)$'
p17_foto() {
  awk '{ p = $2; if (p ~ /\/(log|prompts)\/02-implement\./) next
         if (match(p, /\/(log|prompts)\/0[3-9]-/)) { e = RSTART + RLENGTH; p = substr(p, 1, e - 3) (substr(p, e - 2, 1) - 1) substr(p, e - 1) }
         print $1, p }' "$1" | grep -v "$P17_FUORI" | sort -k2
}
p17_rb() { grep -v "$P17_FUORI" "$1" | sort -k2; }
check "P17 (iv) fine DONE come R_B, e la foto di R_B a meno della fase in piu'" '[ "$(cat "$d/2.rc")" = 0 ] && [ "$(risultato "$d/2.out")" = "$(risultato "$CX/ref-B/$(ultimo_out "$CX/ref-B").out")" ] && { [ "$(p17_foto "$d/FINE.foto")" = "$(p17_rb "$CX/ref-B/FINE.foto")" ] || diag "P17 foto:" "$(diff <(p17_rb "$CX/ref-B/FINE.foto") <(p17_foto "$d/FINE.foto") | head -8)"; }'
check "P17 (v) R3 stesso harness.fp, confronta UGUALE con i due motori" 'cmp -s "$d/FINE/$RUN/harness.fp" "$CX/ref-P/C-P1/$RUN/harness.fp" && [ "$(cd "$d/FINE" && FIC_DRIVER=0 bash "$PR/scripts/run-phase.sh" --harness-fp-confronta "$RUN/harness.fp" "$d/FINE" 2>/dev/null | cut -d" " -f1)" = UGUALE ] && [ "$(cd "$d/FINE" && bash "$PR/scripts/run-phase.sh" --harness-fp-confronta "$RUN/harness.fp" "$d/FINE" 2>/dev/null | cut -d" " -f1)" = UGUALE ]'
check "P17 (v) R6 ha deciso B (evento «motore bash», spia muta), nessun harness cambiato" 'grep -q "^driver: motore bash (FIC_DRIVER=0)" "$d/2.out" && [ ! -s "$d/spia" ] && ! grep -qi "harness cambiato" "$d/2.out"'

# --- counterproofs ------------------------------------------------------------------------------------------------
# a copy of the plugin with one change; the whole scenario S1 runs in the copy (its own fingerprint)
copia() { # $1 name, $2 file relative to the plugin, $3 literal line (or part) to replace, $4 the new one → PR
  PR=$T/plug-$1/maat; rm -rf "$T/plug-$1"; mkdir -p "$T/plug-$1"; cp -r "$ROOT" "$PR"
  find "$PR" -name __pycache__ -type d -prune -exec rm -rf {} +
  "$FIC_PY" - "$PR/$2" "$3" "$4" <<'EOF'
import sys
p, a, b = sys.argv[1:4]
t = open(p, encoding="utf-8", newline="").read()
if t.count(a) != 1:
    sys.exit("mutazione: %d occorrenze di %r in %s" % (t.count(a), a, p))
open(p, "w", encoding="utf-8", newline="").write(t.replace(a, b))
EOF
}
cp_refs() { # $1 context, then the engines of the references
  local c=$1 X; shift; SCEN=S1 CX=$T/$c; mkdir -p "$CX"; nuovo_repo S1
  for X in "$@"; do riferimento "$X"; done
}
DIAG=0
rossi() { # informative: the assertions of one resume that are red in a counterproof (R0 where there are two references)
  local r o=""; for r in r1 r2 r3 r4 r5 r6; do $r "${@:2}" || o="$o R${r#r}"; done
  [ -d "$CX/ref-B" ] && { r0 || o="$o R0"; }
  echo "rollback.test.sh: controprova $1, rosse:${o:- nessuna}"
}
# (d) the resume function that does not set FIC_DRIVER=0: a mutated copy of riprendi, on the main references
declare -f riprendi > "$T/riprendi.orig"
eval "$(sed 's/inv "\$Y" "\$d\/\$n.out";/inv P "$d\/$n.out";/' "$T/riprendi.orig")"
SCEN=S1 CX=$T/s1 PR=$ROOT
check "controprova (d): la mutazione e' applicata (la ripresa non imposta FIC_DRIVER=0)" 'declare -f riprendi | grep -q "inv P "'
riprendi P P2 B; rossi "(d)" P P2 B
check "controprova (d): ripresa P→B che non imposta FIC_DRIVER=0 → R6 rosso" '! r6 P P2 B'
eval "$(cat "$T/riprendi.orig")"
# (a) FIC_DRIVER in the harness fingerprint (D5): the resume with B finds the harness changed
copia a scripts/run-phase.sh '    righe += "lingua %s\n" % lingua' '    righe += "lingua %s motore %s\n" % (lingua, os.environ.get("FIC_DRIVER", ""))'
check "controprova (a): la mutazione e' applicata (FIC_DRIVER nell'impronta)" 'grep -q "motore %s" "$PR/scripts/run-phase.sh"'
cp_refs cp-a P; riprendi P P2 B; rossi "(a)" P P2 B
check "controprova (a): FIC_DRIVER nell'impronta → R1 rosso (harness cambiato)" '! r1 P P2 B && grep -qi "harness cambiato" "$CX/rip-P-P2-B/1.out"'
check "controprova (a): FIC_DRIVER nell'impronta → R3 rosso" '! r3 P P2 B'
if [ "$RAPIDO" != 1 ]; then
  # (b) one more line in the State hash of the driver: the state= written with P is not the one B computes
  copia b scripts/driver.py '    st = plan_raw + "\n" + basis_out + "\n"' '    st = plan_raw + "\n" + basis_out + "\n" + "controprova\n"'
  check "controprova (b): la mutazione e' applicata (State del driver diverso)" 'grep -qF "+ \"controprova" "$PR/scripts/driver.py"'
  cp_refs cp-b P B; riprendi P P2 B; rossi "(b)" P P2 B
  check "controprova (b): State diverso fra i motori → R4 rosso al punto P2" '! r4 P P2 B'
  check "controprova (b): State diverso fra i motori → R0 rosso" '! r0'
  # (c) valida adds a field after its own validation: the schema (additionalProperties false) rejects it in run
  copia c scripts/driver.py '        json.dump(obj, fh, ensure_ascii=False, indent=1)' '        json.dump(dict(obj, controprova=1), fh, ensure_ascii=False, indent=1)'
  check "controprova (c): la mutazione e' applicata (un campo in piu' nel result.json)" 'grep -q "controprova=1" "$PR/scripts/driver.py"'
  cp_refs cp-c P; riprendi P P1 B; rossi "(c)" P P1 B
  check "controprova (c): result.json con un campo in piu' → R1 rosso" '! r1 P P1 B && grep -q "^driver: Driver result: STOP — " "$CX/ref-P/$(ultimo_out "$CX/ref-P").out"'
  check "controprova (c): result.json con un campo in piu' → R5 rosso" '! r5 P P1 B'
  # (c′) the same object in another form (indent=2), valid for the schema: the photo sees the file, the end does not
  copia c2 scripts/driver.py '        json.dump(obj, fh, ensure_ascii=False, indent=1)' '        json.dump(obj, fh, ensure_ascii=False, indent=2)'
  check "controprova (c′): la mutazione e' applicata (result.json con indent=2)" 'grep -q "indent=2" "$PR/scripts/driver.py"'
  cp_refs cp-c2 P B; riprendi P P1 B; rossi "(c′)" P P1 B
  check "controprova (c′): result.json in un'altra forma → R5 rosso" '! r5 P P1 B'
  check "controprova (c′): result.json in un'altra forma → R1 verde" 'DIAG=1 r1 P P1 B'
  check "controprova (c′): result.json in un'altra forma → R0 rosso" '! r0'
fi
DIAG=1

cd /
echo "rollback.test.sh: $riprese riprese, $(( $(date +%s) - t0 )) s"
echo "rollback.test.sh: $pass passati, $fail falliti"
[ $fail -eq 0 ]
