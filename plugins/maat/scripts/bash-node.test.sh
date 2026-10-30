#!/usr/bin/env bash
# bash-node.test.sh — gates.sh and finalize.sh on a synthetic «bash-node» repository (bash, JSON, Node without tests,
# no suite): the test gate is a declared NOT RUN, never PASS; the declared checks ({glob, comando,
# se_presente?}) are the only verification and run at every level; the signature is at most NEEDS_VERIFICATION; a
# red check turns the signature into FAIL. Three mutation counterproofs, run here on mutated copies of the scripts:
# NOT RUN turned into PASS, controlli-<modulo> removed from the gates required by finalize.sh, (premise) the entry with se_presente
# absent declared SALTATA and not PASS.
#   bash plugins/maat/scripts/bash-node.test.sh          (Git Bash or WSL)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)   # plugin root
GT=${GT:-$HERE/gates.sh}
FZ=${FZ:-$HERE/finalize.sh}
pass=0 fail=0
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
unset MAAT_CONFIG MAAT_MODULO FIC_GATES_HARNESS FIC_GATES_WSL PROJECT_ROOT FIC_REPO
# the mutants written in $W source the resolver next to themselves ($W/lib) and find the plugin from MAAT_ROOT
mkdir -p "$W/lib" && cp "$HERE/lib/maat-paths.sh" "$W/lib/"; export MAAT_ROOT=$ROOT
export HOME="$W/home"; mkdir -p "$HOME"
. "$HERE/python.sh" || { echo "interprete Python non trovato" >&2; exit 2; }
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$1]"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /'; }
chk() { if eval "$2"; then ok; else ko "$1" "${3:-}"; fi; }
jget() { "$FIC_PY" -c 'import json,sys; v=json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2]); print(json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else v)' "$1" "$2"; }

# --- PATH: fake node (node --check: red if the file contains SINTASSI_ROTTA), shellcheck ABSENT ---
FB="$W/bin"; mkdir -p "$FB"
printf '#!/usr/bin/env bash\n[ "$1" = --check ] && grep -q SINTASSI_ROTTA "$2" && { echo "SyntaxError"; exit 1; }\nexit 0\n' > "$FB/node"
chmod +x "$FB/node"
while d=$(command -v shellcheck 2>/dev/null) && [ -n "$d" ]; do
  PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$(dirname "$d")" | paste -sd: -)
done
export PATH="$FB:$PATH"
export FIC_GATES_VENV_PY=$FIC_PY   # {python} = the harness interpreter (no python3 looked up in the Windows PATH)

# --- synthetic repository: bash scripts, JSON, a Node server without tests ---
R="$W/repo"; mkdir -p "$R/.claude" "$R/script" "$R/server/console"
cat > "$R/.claude/maat.json" <<'EOF'
{
  "versione_schema": 1,
  "moduli": [
    {
      "nome": "script",
      "radice": ".",
      "regola_test": "nessuna",
      "controlli": [
        { "glob": "**/*.sh", "comando": "bash -n {file}" },
        { "glob": "**/*.json", "comando": "{python} -m json.tool {file}" },
        { "glob": "**/*.sh", "comando": "shellcheck {file}", "se_presente": "shellcheck" }
      ]
    },
    {
      "nome": "console",
      "radice": "server/console",
      "comandi": {
        "test": { "comando": "node --test {test}", "cartella": "radice", "se_presente": "**/*.test.js" }
      },
      "controlli": [
        { "glob": "**/*.js", "comando": "node --check {file}" }
      ]
    }
  ]
}
EOF
printf '#!/usr/bin/env bash\necho deploy\n' > "$R/script/deploy.sh"
printf '{"porta": 8080}\n' > "$R/config.json"
printf 'const x = 1\nmodule.exports = { x }\n' > "$R/server/console/app.js"
(cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git config core.autocrlf false &&
  git add -A && git commit -qm init)
export FIC_GATES_ROOT="$R" FIC_GATES="$GT"
TOUCHED=(script/deploy.sh config.json server/console/app.js)

WF="$W/wf"; mkdir -p "$WF"
spec() { # $1 = spec: review APPROVED + IMPLEMENTED, no counterproof
  printf '%s\n' "# X" "## Contesto" "Contesto." "## Requisiti funzionali" "1. Fare A." \
    "## Piano di implementazione" "Plan status: APPROVED" "Test level: std" "Superfici a rischio: nessuna" \
    "### Passi" "1. Modificare \`script/deploy.sh\`." \
    "## Review implementazione" "Review status: APPROVED" "Feature status: IMPLEMENTED" "Verification: VERIFIED" \
    "Reviewed snapshot: base aaaaaaaaaaaa · tree bbbbbbbbbbbb · fingerprint cccccccccccc · 3 paths" \
    "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" > "$1"
}
fstat() { tr -d '\r' < "$1" | sed -n 's/^Feature status: //p'; }
# caso <name> <level> [gates.sh] [finalize.sh]: gates then finalize on a new run dir; G_* and F_* the outcomes
caso() {
  local run="$WF/spec-$1.run" g=${3:-$GT} f=${4:-$FZ}
  SP="$WF/spec-$1.md"; RUN=$run; mkdir -p "$run"; printf '%s\n' "${TOUCHED[@]}" > "$run/touched.txt"; spec "$SP"
  G_OUT=$(bash "$g" --run-dir "$run" "$2" "${TOUCHED[@]}" 2>&1); G_RC=$?
  EV=$(printf '%s\n' "$G_OUT" | sed -n 's/^gates: .* evidence=\(.*\)$/\1/p' | tail -1)
  F_OUT=$(FIC_GATES="$g" bash "$f" --level "$2" "$run" 2>&1); F_RC=$?
}

for L in min full; do
  # --- 1. all healthy: test NOT RUN declared, checks PASS, signature NEEDS_VERIFICATION ---
  caso "sano-$L" "$L"
  chk "$L: gates.sh esce 0 (NOT RUN non e' un errore ne' un blocco)" '[ $G_RC -eq 0 ] && [ -n "$EV" ]' "$G_OUT"
  chk "$L:   tests-script NOT RUN, motivo «dichiarato: nessun test», mai PASS" '[ "$(jget "$EV/tests-script.json" esito)" = "NOT RUN" ] && [ "$(jget "$EV/tests-script.json" motivo)" = "dichiarato: nessun test" ] && [ "$(jget "$EV/tests-script.json" report)" = None ]' "$G_OUT"
  chk "$L:   la riga d'esito lo nomina" 'printf "%s\n" "$G_OUT" | grep -q "^tests-script: NOT RUN (eseguito) — dichiarato: nessun test$" && printf "%s\n" "$G_OUT" | tail -1 | grep -q "(NOT RUN dichiarato: tests-script)"' "$G_OUT"
  chk "$L:   controlli-script PASS col report (bash -n, json.tool)" '[ "$(jget "$EV/controlli-script.json" esito)" = PASS ] && [ -s "$EV/controlli-script.log" ] && grep -q "bash -n '"'"'script/deploy.sh'"'"'" "$EV/controlli-script.log" && grep -q "json.tool '"'"'config.json'"'"'" "$EV/controlli-script.log"' "$G_OUT"
  chk "$L:   shellcheck assente dal PATH: voce SALTATA e dichiarata, non PASS" 'jget "$EV/controlli-script.json" voci | grep -q "\"comando\": \"shellcheck {file}\", \"esito\": \"SALTATA\"" && ! grep -q "^== shellcheck" "$EV/controlli-script.log"' "$(jget "$EV/controlli-script.json" voci)"
  chk "$L:   modulo Node: tests-console SKIPPED (nessun test), controlli-console PASS" '[ "$(jget "$EV/tests-console.json" esito)" = SKIPPED ] && [ "$(jget "$EV/controlli-console.json" esito)" = PASS ]' "$G_OUT"
  chk "$L: firma NEEDS_VERIFICATION (uscita 1), mai IMPLEMENTED" '[ $F_RC -eq 1 ] && [ "$(fstat "$SP")" = NEEDS_VERIFICATION ]' "$F_OUT"
  chk "$L:   motivo «nessun test nel modulo script, controlli verdi»" 'grep -q "^Verification: PARTIAL (finalize.sh: tests-script: NOT RUN (dichiarato: nessun test) — nessun test nel modulo script, controlli verdi" "$SP"' "$(grep "^Verification" "$SP")"

  # --- 2. a red check (bash -n fails): controlli-script FAIL, signature FAIL ---
  printf 'if then\n' > "$R/script/deploy.sh"
  caso "rosso-$L" "$L"
  chk "$L: bash -n rosso: controlli-script FAIL, gates.sh esce 1" '[ "$(jget "$EV/controlli-script.json" esito)" = FAIL ] && [ $G_RC -eq 1 ]' "$G_OUT"
  chk "$L:   firma FAIL (uscita 3), non NEEDS_VERIFICATION" '[ $F_RC -eq 3 ] && [ "$(fstat "$SP")" = PLANNED ] && grep -q "^Finalize: FAIL — " "$SP"' "$F_OUT"
  printf '#!/usr/bin/env bash\necho deploy\n' > "$R/script/deploy.sh"
done

# --- counterproof 1: NOT RUN turned into PASS in gates.sh => the «all healthy» case fails, in the gates AND in the signature: also
#     finalize.sh runs on the mutant's evidence, and the signature's reason «nessun test nel modulo script» disappears ---
MG="$W/mut-notrun.sh"
sed 's/esito, rep, riep, mot, cmd, rc = "NOT RUN", None, "", why, None, None/esito, rep, riep, mot, cmd, rc = "PASS", None, "", why, None, None/' "$GT" > "$MG"
if cmp -s "$GT" "$MG"; then ko "controprova NOT RUN -> PASS: la mutazione non si applica"; else
  caso mut-notrun std "$MG"
  if [ "$(jget "$EV/tests-script.json" esito)" != "NOT RUN" ] &&
     ! grep -q "^Verification: PARTIAL (finalize.sh: tests-script: NOT RUN (dichiarato: nessun test) — nessun test nel modulo script" "$SP"; then
    ok   # expected red: both «NOT RUN, never PASS» and the signature reason fail (case 1 of gates and of finalize)
  else ko "controprova: sul mutante tests-script resta NOT RUN o la firma ne riporta ancora il motivo (il test non discrimina)" "$G_OUT $F_OUT $(grep "^Verification" "$SP")"; fi
fi

# --- counterproof 2: controlli-<modulo> removed from the gates required by finalize.sh => the red case signs NEEDS_VERIFICATION ---
MF="$W/mut-controlli.sh"
sed 's/^    \[ -n "\$g" \] && \[ "\$t" != build \] || continue$/    [ -n "$g" ] \&\& [ "$t" != build ] \&\& [ "$t" != controlli ] || continue/' "$FZ" > "$MF"
if cmp -s "$FZ" "$MF"; then ko "controprova controlli non richiesti: la mutazione non si applica"; else
  printf 'if then\n' > "$R/script/deploy.sh"
  caso mut-controlli std "$GT" "$MF"
  printf '#!/usr/bin/env bash\necho deploy\n' > "$R/script/deploy.sh"
  if [ $F_RC -eq 1 ] && [ "$(fstat "$SP")" = NEEDS_VERIFICATION ]; then ok   # expected red: the «signature FAIL» check fails
  else ko "controprova: sul mutante il controllo rosso porta ancora a FAIL (il test non discrimina)" "$F_OUT"; fi
fi

echo "bash-node.test.sh: $pass ok, $fail falliti"
[ $fail -eq 0 ]
