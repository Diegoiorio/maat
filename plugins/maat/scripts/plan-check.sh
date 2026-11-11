#!/usr/bin/env bash
# plan-check.sh — DETERMINISTIC checks of the /plan-review-cycle loop.
#
# Turns into a mechanical check what the skill would otherwise leave to the orchestrator judgment
# (the same orchestrator that has just written the plan). It does not judge the plan content: only
# structure, boundaries and differences.
#
#   plan-check.sh delta        <baseline> <corrente>      changed ranges + xref, for the delta round
#   plan-check.sh lint         <spec> [--baseline <copia>] structure of the plan section
#   plan-check.sh contract     <spec>                      verification contract, for /implementation-review-cycle
#   plan-check.sh basis        <spec>                      is the approval still the one of this spec and this plan?
#   plan-check.sh lint2        <spec>                      structure of a FORMAT 2 plan (Plan format: 2)
#   plan-check.sh gen          <spec> [--run-dir <dir>]    procedure generated from a format 2 plan (commands, mutations.json)
#   plan-check.sh route        <spec> [--diff <file>]      L5: surfaces detected from the files, light or full path
#   plan-check.sh s2           <spec> --delta <f> --gate <f> [--respinti <n>]   S2: delta and fresh eyes clean?
#   plan-check.sh skeleton     <spec>                      skeleton (steps, files, surfaces, lines) below or above the cap
#   plan-check.sh split        <madre> [<figlia>…]         partition of the requirements among the children of a chain
#   plan-check.sh closed       <spec>                      is the ring closed? (fresh Finalize: IMPLEMENTED) · exit 0|1
#   plan-check.sh basis        <spec> --write-tests        (format 2) records "tests <fp>" in the Approved basis
#   plan-check.sh accept|tests|stubs|rossi|l2 <spec> …     test-red phase and L2 (harness-pt11, below: cmd_f2x)
#   plan-check.sh taglia       <spec> [--diff <file>] [--override full|light]   1.7.0: the size of the cycle
#   plan-check.sh e1           <reply>                     1.7.0: the round of the small plan review escalates?
#
# THE SIZE OF THE CYCLE (1.7.0). `taglia` measures facts of the plan, of the spec and of maat.json (with --diff also
#   of the code written: a unified git diff, review-surface.sh diff) and prints one fact per line, then
#   "Fatti: F1=<n>/<cap> …" and last "Taglia: piccola|piena — <motivi>"; exit 0 (it is an answer). piccola only if
#   EVERY fact is under its threshold: F1 source files (Touched files minus the test files of the test table) <= 3,
#   F2 new source files <= 1, F3 steps <= 6, F4 requirements (the MAXIMUM of the traceability ids and of the ids in
#   the spec above the plan) <= 12, F5 rows of the test table <= 10, F6 plan lines (as skeleton) <= 250, F7 no
#   critical surface declared or detected (piano.superfici_critiche), F8 no api-contract declared or detected, F9 no
#   migration, F10 no destructive word (DESTR, plan and diff), F11 no security word (SIZE_SEC plus
#   piano.taglia.parole_sicurezza; spec, plan and diff), F12 no deleted file (diff), F13 <= 2 new public symbols
#   (diff; Python def/class, JS/TS export, Go capitalised names; a language without a rule is not measurable),
#   F14 no "Size request: full" line; with --diff also no path outside the plan. A fact that cannot be measured
#   (format 1, missing section, maat.json invalid, diff unreadable) is piena (fail-closed). --override full: piena;
#   --override light: the numeric facts (F1-F6, F13) do not count, the barriers do. piano.taglia.automatica false:
#   piena unless --override light. Thresholds in piano.taglia.soglie. Read by the plan skill (T1) and by driver.py
#   (T2 after the plan, T3 after implement/fix). The words Taglia:, Fatti:, piccola, piena and the F-ids are the
#   same in every language; the explanation follows the language.
# lint (1.7.0): "Size request: <v>" (Italian "Taglia richiesta:") is optional, at most one, and <v> must be full
#   (piena): the plan author may only ask for MORE weight (R3).
# e1 (1.7.0): reads the reply of the ONE round of spec-plan-reviewer-light of the small size and prints
#   "E1: STOP | piena | piccola — <motivo>": STOP for STOP_HUMAN_DECISION_REQUIRED, piena for a blocker, more than
#   2 major, a partial reply (Blocked on: <reason>) or no Decision: line; exit 0.
# lint2 (1.7.0, T3): a file the plan declares new (`path` (new) in Touched files) may be in a folder that does not
#   exist yet (path_ok); a path not declared new still needs its first segment in the repo.
#
# Exit: 0 = ok · 1 = VIOLAZIONE (or, for delta, ERRORE DURO) · 2 = usage error.
# AVVISO lines are printed but do not change the exit code.
#
# FORMAT 2 — line "Plan format: 2" under "## Piano di implementazione" (defined in SKILL.md, "Plan format 2").
# Without that line the plan is in format 1: lint, delta, contract and basis behave as before, byte for byte;
# lint2 and gen answer "non si applica" with exit 0. lint2, gen and route read the tables with Python
# (python.sh of the full cycle), on the annotate lines: same plan boundary, same fences.
#   lint2  VIOLAZIONE: traceability requirement without a test · test outside a step · file of a step not
#          in "### File toccati" · block without scrive: · malformed test table or mutation · open risk
#          without a test · string/data-test removed but still asserted by a test the plan does not touch · test
#          plan row with a "resta verde" assertion (existing non-regression test: it goes in the note under the
#          table, and the traceability says "non verificabile a test (invarianza, ...)").
#   gen    writes <run-dir>/gen/procedura.txt ("key: value" lines: Plan format, Impronta piano, Test level,
#          vitest, pytest, altri, cmd vitest|pytest|lint|counterproof, mutazioni, "blocco <id>: scrive=… · dopo=…")
#          and <run-dir>/counterproof/mutations.json in the format of script/test/counterproof.sh (removed if no
#          row has a mutation). Default <run-dir>: <spec without .md>.run. Exit 1 on a malformed row.
#   route  prints the detected surfaces (paths + destructive keywords in the plan and in --diff), the declared
#          ones and "Percorso: leggero|pieno — <motivo>"; exit 0 (it is an answer).
#   s2     reads the two responses (first line "Impronta piano: <fp12>", then the reviewer contract) and prints
#          "S2: APPROVA | CORREGGI | RILANCIA | IMPRONTA DIVERSA | STOP — <motivo>"; exit 0.
#
# SPLITTING AND CHAINS (harness-pt12, L6):
#   skeleton  (format 2; format 1: "non si applica", exit 0) counts the steps of "### Passi", the files (File
#          toccati + files of the steps), the declared surfaces and the plan lines; prints "Scheletro: SOTTO IL
#          TETTO" (exit 0) or "Scheletro: SOPRA IL TETTO — <cosa>" (exit 1: a split proposal, no waiver).
#          Caps: <=15 steps, <=40 files (the skeleton) and <=400 lines (the full plan, same command).
#          The user decision NOT to split lives in the spec, above the plan: "Taglio: rifiutato — <data>";
#          with that line a skeleton above the cap says so and reports it, but exits 0 (single plan, no stop).
#   split     every ID (RF<n>, CA<n>, also dotted: RF5.4) DEFINED by the parent in the "Requisiti funzionali"
#          and "Criteri di accettazione" sections (at the start of a heading, a list item or a table row) is in
#          ONE and only one child; no child has IDs the parent lacks; every child has "Dipende da:" and
#          "Interfaccia per:" (above the plan, at line start). Children: from the arguments, in chain order, or
#          from the parent "Figlie:" line. Exit 1 = VIOLAZIONE (STOP).
#   basis of a CHILD (a spec in the same folder lists it in its "Figlie:" line): the Basis adds
#          "madre <fp>" (the parent sections above the plan), for ring k>1 "prec <fp>" (spec and plan
#          of ring k-1) and, once k-1 is closed (plan-check.sh closed), "interfaccia
#          <fp>" (the backticked files of its "Interfaccia per:" line in its last .post-tree; closed = as in
#          `closed`: fresh Finalize: IMPLEMENTED, no legacy fallback). STALE if one of the
#          recorded fields has changed; STALE (madre|prec) if the current Basis has the field and the recorded one does not;
#          with k-1 closed and no "interfaccia" recorded (plan approved while k-1 was implementing: L6), STALE
#          (touched: <file>) if ANY file cited by the plan (in backticks, :line and ::name stripped) is in
#          the touched.txt of k-1: a delta round is done with k-1 closed. A spec outside a chain: Basis unchanged.
# Repository root: PLAN_CHECK_ROOT, otherwise git of the spec folder, otherwise the current folder.
#
# Invariants (see SKILL.md and the memory on the traps of markdown gates):
# - spec files are CRLF: every read strips the \r, and diff uses --strip-trailing-cr;
# - the plan section runs from "## Piano di implementazione" to "## Review implementazione" or to the end of
#   the file: an H2 inside the plan does NOT close it (it happens, e.g. spec-restyling-ui-soft);
# - everything inside a code block (``` or ~~~) does not count as structure.
#
# Languages (Maat 1.3.0): every heading and keyword the plan author WRITES is read in both forms, the
# Italian one (existing specs, approved plans) and the English one (written from 1.3.0 on): "## Implementation
# plan", "## Implementation review", "### Plan review changelog", the H3 sections, "Risk surfaces:", "[floor: …]",
# "⚠️ Surface", "static sufficient:", "⚠️ Open risk", "Children:", "Depends on:", "Interface for:", "Split:",
# FR/AC ids, the English table headers and cell words. The comparison stays exact, with the English alternative
# (no fuzzy matching). Surface tokens are mapped to the Italian canonical token at read time (surf_canon,
# CANON in the Python): every output, mutations.json included, carries the Italian token. The lines printed
# for other scripts (Recorded:, Catena:, Impronta piano:, blocco …, L2 …, rossi:, S2:, Percorso:, Scheletro:)
# do not change. For an Italian spec every output is byte for byte the one of 1.2.1. A section present in
# BOTH languages (same H2 zone, same H3, Figlie: and Children:) is a VIOLAZIONE of lint.
# Messages (Maat 1.4.0): the text for a person comes from the catalog lib/messages.tsv (msg in bash, _msg.T in
# PY2), English by default, Italian with "lingua": "it" or MAAT_LINGUA=it. The keywords VIOLAZIONE, AVVISO,
# ERRORE DURO, Percorso: leggero|pieno, Scheletro: SOPRA|SOTTO IL TETTO and S2: <word> stay Italian (the skills
# read them); only the explanation after them follows the language. NEVER through the catalog: the whole stdout of
# basis and contract (basis enters State), the keys of gen/procedura.txt, the tokens of accept, tests, rossi.json
# (esito) and the prefixes "L2 <id>: OK|NO — " and "rossi: esito=" (frozen in lib/protocol-strings.list).
#
# Tests: plan-check.test.sh (every check has its red counterproof).

set -uo pipefail
set -f

# Single vocabulary of the risk surfaces (defined in SKILL.md, Step 0). CRITICHE = those that
# trigger the verification floor and, if round 1 approves right away, the fresh-eyes gate.
SURFACES="permessi dati contratto-api import logica-condivisa distruttiva"
CRITICAL="permessi dati distruttiva"
# Backticked tokens too generic to serve as a cross-reference.
XREF_STOP=" std full min true false none null APPROVED DRAFT legacy TODO nessuna "
XREF_MAX_LINES=8
XREF_MAX_HITS=15   # a token that appears in more lines than this is noise, not a reference

# English surface token = Italian canonical token (Maat 1.3.0); "import" is the same word in both.
# The same pairs are in CANON of the Python below.
SURF_PAIRS="permissions=permessi data=dati destructive=distruttiva api-contract=contratto-api shared-logic=logica-condivisa none=nessuna"
# surf_canon <token>: the canonical (Italian) token; anything else unchanged.
surf_canon() { local p; for p in $SURF_PAIRS; do [ "${p%%=*}" = "$1" ] && { printf '%s\n' "${p#*=}"; return; }; done; printf '%s\n' "$1"; }
# surf_en <canonical token>: its English form (for the "⚠️ Surface <token>" line); anything else unchanged.
surf_en() { local p; for p in $SURF_PAIRS; do [ "${p#*=}" = "$1" ] && { printf '%s\n' "${p%%=*}"; return; }; done; printf '%s\n' "$1"; }
# Headings that exist in two languages: "<Italian>|<English>" (H2 = zone of the file, H3 = plan sections), for
# the both-languages check of lint. The readers spell the alternatives in their own regexes.
H2_PAIRS="Piano di implementazione|Implementation plan
Review implementazione|Implementation review"
H3_PAIRS="Piano di test|Test plan
Tracciabilità requisiti|Requirement traceability
File toccati|Touched files
Passi|Steps
Decisioni|Decisions
Stringhe e data-test|Strings and data-test
Changelog revisione piano|Plan review changelog"

die_usage() { echo "$(msg plan-check.usage script="$0")" >&2; exit 2; }

# annotate FILE → lines "NR<TAB>zona<TAB>infence<TAB>testo"
# zona: above | plan | changelog | review. infence=1 also on the fence lines themselves.
annotate() {
  tr -d '\r' < "$1" | awk '
    BEGIN { zone = "above"; infence = 0 }
    {
      line = $0
      isfence = (line ~ /^[ \t]*(```|~~~)/)
      if (!infence && !isfence) {
        if (zone == "above" && line ~ /^## (Piano di implementazione|Implementation plan)/) zone = "plan"
        else if ((zone == "plan" || zone == "changelog") && line ~ /^## (Review implementazione|Implementation review)/) zone = "review"
        else if (zone == "plan" && line ~ /^###[ \t]+([0-9]+\.[ \t]*)?(Changelog revisione piano|Plan review changelog)/) zone = "changelog"
        else if (zone == "changelog" && line ~ /^##?#?[ \t]/) zone = "plan"
      }
      fl = infence
      if (isfence) { infence = !infence; fl = 1 }
      printf "%d\t%s\t%d\t%s\n", NR, zone, fl, line
    }'
}

# above_norm: strips trailing spaces and trailing blank lines (stdin → stdout).
above_norm() { sed 's/[[:space:]]*$//' | awk 'NF { for (i = 0; i < b; i++) print ""; b = 0; print; next } { b++ }'; }

# test_zone: prints "NR<TAB>testo" of the lines of "### Piano di test" (outside fences), from the annotate on stdin.
test_zone() {
  awk -F'\t' '
    $2 != "plan" { if (in_t) exit; next }
    $3 == 0 && $4 ~ /^###[ \t]+([0-9]+\.[ \t]*)?(Piano di test|Test plan)/ { in_t = 1; next }
    in_t && $3 == 0 && $4 ~ /^##?#?[ \t]/ { exit }
    in_t { print $1 "\t" $4 }'
}
# A floor line is a LIST ITEM inside "### Piano di test": a mention in prose
# elsewhere ("coperto dal [pavimento: permessi] sotto") is not a second floor line.
PAV_RE='^[ \t]*([-*]|[0-9]+\.)[ \t]+\[(pavimento|floor):'
# pav_toks: "NR<TAB>token" for every "[pavimento: <s>]" / "[floor: <s>]" of the floor lines ("NR<TAB>testo" on
# stdin; every occurrence of the line, as grep -o did), token stripped and mapped to the canonical one.
pav_toks() {
  PAV="$PAV_RE" awk -v pairs="$SURF_PAIRS" '
    BEGIN { n = split(pairs, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); cm[kv[1]] = kv[2] } }
    { nr = $0; sub(/\t.*$/, "", nr); t = $0; sub(/^[^\t]*\t/, "", t)
      if (t !~ ENVIRON["PAV"]) next
      while (match(t, /\[(pavimento|floor):/)) {
        x = substr(t, RSTART + RLENGTH); e = index(x, "]")
        if (!e) break
        t = substr(x, e + 1); x = substr(x, 1, e - 1)
        sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x)
        print nr "\t" ((x in cm) ? cm[x] : x)
      } }'
}
# An [e2e-locator: <spec>] line is the targeted e2e that the plan prescribes AT EVERY LEVEL when an e2e
# spec changes or a string/class/attribute used by its locators changes: outside the caps like the floor.
E2E_RE='^[ \t]*([-*]|[0-9]+\.)[ \t]+\[e2e-locator:'

# warn_line <token>: "NR<TAB>testo" of the first "⚠️ Superficie <token>" line of the plan, outside the
# fences (annotate on stdin). The token must follow "⚠️ Superficie" (markdown `, * and _ tolerated):
# a ⚠️ line on ANOTHER surface does not cover this one.
# English form (1.3.0): "⚠️ Surface <token>", the token in either language.
warn_line() {
  local en; en=$(surf_en "$1")
  awk -F'\t' '$2 == "plan" && $3 == 0 && (index($4, "⚠️ Superficie") || index($4, "⚠️ Surface")) { print $1 "\t" $4 }' \
    | grep -E "⚠️ (Superficie|Surface)[[:space:]*_\`]+($1|$en)([^[:alnum:]_-]|\$)" | head -1 || true
}
# waiver_of <text of the ⚠️ line>: the reason of the "statica sufficiente: <motivo>" (or "static sufficient:
# <reason>") waiver, or empty.
waiver_of() { printf '%s\n' "$1" | sed -En 's/.*(statica sufficiente|static sufficient):[[:space:]]*//p' | sed 's/[[:space:]]*$//'; }
# decl_of: the value of the first "Superfici a rischio:" / "Risk surfaces:" line of the plan (annotate on stdin).
decl_of() {
  awk -F'\t' '$2 == "plan" && $3 == 0 && (index($4, "Superfici a rischio:") == 1 || index($4, "Risk surfaces:") == 1) {
    sub(/^(Superfici a rischio|Risk surfaces):[ \t]*/, "", $4); print $4; exit }'
}
# declared_surfaces: the valid tokens of the declaration (annotate on stdin), canonical, space separated.
declared_surfaces() {
  local d s out=""
  d=$(decl_of)
  for s in $(printf '%s' "$d" | tr -d '`' | tr ',·;' '   ' | tr -s ' '); do
    s=$(surf_canon "$s")
    case " $SURFACES " in *" $s "*) out="$out $s" ;; esac
  done
  printf '%s\n' "$out"
}
# section_range <H3 name>: "offset=N limit=M" of the plan subsection (annotate on stdin).
section_range() {
  awk -F'\t' -v name="$1" '
    $2 != "plan" { if (s) exit; next }
    !s && $3 == 0 && $4 ~ ("^###[ \t]+([0-9]+\\.[ \t]*)?" name) { s = $1; last = $1; next }
    s && $3 == 0 && $4 ~ /^##?#?[ \t]/ { exit }
    s { last = $1 }
    END { if (s) printf "offset=%d limit=%d\n", s, last - s + 1 }'
}
# fmt2_of: 1 if the plan (annotate on stdin) has the "Plan format: 2" line outside fences, otherwise 0.
fmt2_of() { awk -F'\t' '$2 == "plan" && $3 == 0 && $4 ~ /^Plan format:[ \t]*2[ \t]*$/ { f = 1 } END { print f ? 1 : 0 }'; }

# ─────────────────────────────────────────────────────────────────────────── delta
cmd_delta() {
  [ $# -eq 2 ] || die_usage
  local base="$1" cur="$2"
  if [ ! -s "$base" ]; then echo "ERRORE DURO: $(msg plan-check.delta_no_base base="$base")"; return 1; fi
  [ -f "$cur" ] || { echo "$(msg plan-check.delta_no_cur cur="$cur")" >&2; return 2; }

  local d; d=$(diff --strip-trailing-cr "$base" "$cur")
  if [ -z "$d" ]; then echo "ERRORE DURO: $(msg plan-check.delta_empty)"; return 1; fi

  local ann; ann=$(annotate "$cur")
  local total_new total_old
  total_new=$(printf '%s\n' "$ann" | wc -l)
  total_old=$(tr -d '\r' < "$base" | wc -l)

  # Hunk → range on the current file (1-based). A pure deletion becomes the line after which it fell.
  # the text of the message reaches awk through the environment (ENVIRON: no escape processing, unlike -v)
  printf '%s\n' "$d" | PC_WHOLE="$(msg plan-check.delta_whole)" awk -v tn="$total_new" -v to="$total_old" '
    /^[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$/ {
      match($0, /[acd]/); op = substr($0, RSTART, 1)
      split(substr($0, 1, RSTART - 1), o, ","); split(substr($0, RSTART + 1), n, ",")
      os = o[1]; oe = (2 in o) ? o[2] : o[1]
      ns = n[1]; ne = (2 in n) ? n[2] : n[1]
      if (op == "d") { chold += oe - os + 1; s = (ns < 1 ? 1 : ns); e = s + 1 }
      else { if (op == "c") chold += oe - os + 1; chnew += ne - ns + 1; s = ns; e = ne }
      s -= 2; e += 2; if (s < 1) s = 1; if (e > tn) e = tn
      rs[++k] = s; re[k] = e
    }
    END {
      if ((tn > 20 && chnew > 0.9 * tn) || (to > 20 && chold > 0.9 * to)) {
        print "ERRORE DURO: " ENVIRON["PC_WHOLE"]
        exit 1
      }
      # merges nearby ranges (distance <= 3) so as not to spend reviewer calls
      for (i = 1; i <= k; i++) {
        if (m && rs[i] <= me + 3) { if (re[i] > me) me = re[i]; continue }
        if (m) printf "range: offset=%d limit=%d\n", ms, me - ms + 1
        ms = rs[i]; me = re[i]; m = 1
      }
      if (m) printf "range: offset=%d limit=%d\n", ms, me - ms + 1
    }' > "$TMPD/ranges" || { cat "$TMPD/ranges"; return 1; }
  cat "$TMPD/ranges"

  # xref: backticked tokens of the changed lines, searched in the OTHER lines of the plan.
  awk '{ split($2, a, "="); split($3, b, "="); for (i = a[2]; i < a[2] + b[2]; i++) print i }' "$TMPD/ranges" | sort -un > "$TMPD/inrange"
  printf '%s\n' "$ann" | awk -F'\t' 'NR==FNR { r[$1] = 1; next } ($1 in r) { print $4 }' "$TMPD/inrange" - \
    | grep -o '`[^`]*`' | tr -d '`' | sort -u > "$TMPD/tokens" || true

  : > "$TMPD/cand"
  local tok hits
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    [ ${#tok} -le 60 ] || continue
    case "$XREF_STOP" in *" $tok "*) continue ;; esac
    if ! printf '%s' "$tok" | grep -q '[/._(:]' && ! printf '%s' "$tok" | grep -q '[a-z][A-Z]' && [ ${#tok} -lt 6 ]; then continue; fi
    printf '%s\n' "$ann" | awk -F'\t' -v t="$tok" 'NR==FNR { r[$1] = 1; next }
      $2 == "plan" && !($1 in r) && index($4, t) { print $1 }' "$TMPD/inrange" - > "$TMPD/hits"
    hits=$(wc -l < "$TMPD/hits")
    [ "$hits" -gt 0 ] && [ "$hits" -le "$XREF_MAX_HITS" ] || continue
    while IFS= read -r ln; do printf '%d\t%d\t%s\n' "$hits" "$ln" "$tok" >> "$TMPD/cand"; done < "$TMPD/hits"
  done < "$TMPD/tokens"
  # rarest first; a single line per line number; cap XREF_MAX_LINES
  sort -t$'\t' -k1,1n -k2,2n "$TMPD/cand" | PC_LINE="$(msg plan-check.xref_line)" awk -F'\t' -v max="$XREF_MAX_LINES" '!seen[$2]++ { print "xref: " ENVIRON["PC_LINE"] " " $2 " (" $3 ")"; if (++n >= max) exit }'
  return 0
}

# ─────────────────────────────────────────────────────────────────────────── lint
cmd_lint() {
  local spec="" base=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --baseline) [ $# -ge 2 ] || die_usage; base="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  local rc=0 ann; ann=$(annotate "$spec")
  viol() { echo "VIOLAZIONE: $*"; rc=1; }
  warn() { echo "AVVISO: $*"; }

  if ! printf '%s\n' "$ann" | awk -F'\t' '$2 != "above" { f = 1 } END { exit !f }'; then
    viol "$(msg plan-check.no_plan)"; return 1
  fi

  # Status lines: a single anchored occurrence in the plan (changelog included), outside fences.
  local lit l2 n ln prev=""
  for lit in "Plan status:" "Test level:" "Superfici a rischio:"; do
    # l2: the English form of the literal (the same literal when it is already English)
    l2=$lit; [ "$lit" = "Superfici a rischio:" ] && l2="Risk surfaces:"
    n=$(printf '%s\n' "$ann" | awk -F'\t' -v l="$lit" -v l2="$l2" '($2 == "plan" || $2 == "changelog") && $3 == 0 && (index($4, l) == 1 || index($4, l2) == 1)' | wc -l)
    if [ "$n" -gt 1 ]; then viol "$(msg plan-check.lit_dup lit="$lit" n="$n")"
    elif [ "$n" -eq 0 ]; then warn "$(msg plan-check.lit_missing lit="$lit")"
    fi
    ln=$(printf '%s\n' "$ann" | awk -F'\t' -v l="$lit" -v l2="$l2" '$2 == "plan" && $3 == 0 && (index($4, l) == 1 || index($4, l2) == 1) { print $1; exit }')
    if [ -n "$prev" ] && [ -n "$ln" ] && [ "$ln" -ne $((prev + 1)) ]; then warn "$(msg plan-check.lit_not_next lit="$lit")"; fi
    [ -n "$ln" ] && prev="$ln"
    # In the changelog the literal must not be quoted even mid-line: that is where the duplicate comes from.
    if printf '%s\n' "$ann" | awk -F'\t' -v l="$lit" -v l2="$l2" '$2 == "changelog" && (index($4, l) > 1 || index($4, l2) > 1) { f = 1 } END { exit !f }'; then
      warn "$(msg plan-check.lit_changelog lit="$lit")"
    fi
  done

  # Approved basis: written at approval (written by the skill, never by hand); only one.
  n=$(printf '%s
' "$ann" | awk -F'	' '($2 == "plan" || $2 == "changelog") && $3 == 0 && index($4, "Approved basis:") == 1' | wc -l)
  if [ "$n" -gt 1 ]; then viol "$(msg plan-check.basis_dup n="$n")"
  elif [ "$n" -eq 0 ] && printf '%s
' "$ann" | awk -F'	' '$2 == "plan" && $3 == 0 && $4 ~ /^Plan status:[ 	]*APPROVED/ { f = 1 } END { exit !f }'; then
    warn "$(msg plan-check.basis_legacy)"
  fi

  # Declared surfaces: vocabulary tokens only (backticks are tolerated, notes are not).
  # English tokens (Risk surfaces: permissions, none…) are mapped to the canonical ones (surf_canon).
  local decl; decl=$(printf '%s\n' "$ann" | decl_of)
  local declared="" s sc nnone=0 ntok=0
  if [ -n "$decl" ]; then
    for s in $(printf '%s' "$decl" | tr -d '`' | tr ',·;' '   ' | tr -s ' '); do
      ntok=$((ntok + 1))
      sc=$(surf_canon "$s")
      case " $SURFACES " in
        *" $sc "*) declared="$declared $sc" ;;
        *) if [ "$sc" = "nessuna" ]; then nnone=1
           else viol "$(msg plan-check.surf_unknown s="$s" surfaces="$SURFACES")"; fi ;;
      esac
    done
    [ "$nnone" -eq 1 ] && [ "$ntok" -gt 1 ] && viol "$(msg plan-check.surf_none_mixed)"
  fi

  # Floor: list item in "### Piano di test", on a CRITICAL and DECLARED surface, one per surface.
  local tz; tz=$(printf '%s\n' "$ann" | test_zone)
  local pav; pav=$(printf '%s\n' "$tz" | pav_toks | cut -f2)
  if [ -n "$pav" ]; then
    while IFS= read -r s; do
      case " $CRITICAL " in *" $s "*) ;; *) viol "$(msg plan-check.floor_not_critical s="$s" critical="$CRITICAL")" ;; esac
      case " $declared " in *" $s "*) ;; *) viol "$(msg plan-check.floor_undeclared s="$s")" ;; esac
    done <<< "$pav"
    printf '%s\n' "$pav" | sort | uniq -d | while IFS= read -r s; do echo "VIOLAZIONE: $(msg plan-check.floor_dup s="$s")"; done
    printf '%s\n' "$pav" | sort | uniq -d | grep -q . && rc=1
  fi
  # Declared critical surface with neither a floor nor a ⚠️ line that NAMES it: AVVISO (L3 judges it).
  # A ⚠️ line on another surface does not cover it. Waiver ("statica sufficiente:") without a reason or
  # broken across lines: AVVISO — downstream `contract` would read it as an obligation.
  local wl wn wt nxt
  for s in $declared; do
    case " $CRITICAL " in *" $s "*) ;; *) continue ;; esac
    printf '%s\n' "$pav" | grep -qx "$s" && continue
    wl=$(printf '%s\n' "$ann" | warn_line "$s")
    if [ -z "$wl" ]; then
      warn "$(msg plan-check.critical_uncovered s="$s" s="$s" s="$s")"
      continue
    fi
    wn=${wl%%$'\t'*}; wt=${wl#*$'\t'}
    if printf '%s\n' "$wt" | grep -Eq '(statica sufficiente|static sufficient):' && [ -z "$(waiver_of "$wt")" ]; then
      warn "$(msg plan-check.waiver_no_reason wn="$wn")"
    fi
    nxt=$(printf '%s\n' "$ann" | awk -F'\t' -v n=$((wn + 1)) '$1 == n { print $4; exit }')
    if printf '%s\n' "$nxt" | grep -Eq '^[[:space:]]*(—|-)?[[:space:]]*(statica|sufficiente|static[[:space:]]+sufficient)'; then
      warn "$(msg plan-check.waiver_wrapped wn="$wn" s="$s")"
    fi
  done

  # targeted e2e by locator: at most 2 (beyond that, a ⚠️ line and the regression-watch).
  local ne2e; ne2e=$(printf '%s\n' "$tz" | cut -f2- | grep -cE "$E2E_RE" || true)
  [ "${ne2e:-0}" -le 2 ] || warn "$(msg plan-check.e2e_cap n="$ne2e")"

  # Length of "### Piano di test" relative to the level (AVVISO: L3 judges it, here it is measured).
  # Not counted: blank lines, floor lines, [e2e-locator: lines and ⚠️ lines: outside the cap.
  local lvl; lvl=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Test level:") == 1 { sub(/^Test level:[ \t]*/, "", $4); sub(/[ \t].*$/, "", $4); print $4; exit }')
  if printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && $4 ~ /^###[ \t]+([0-9]+\.[ \t]*)?(Piano di test|Test plan)/ { f = 1 } END { exit !f }'; then
    # Format 2: header and separator of the test table and the "⚠️ Rischio aperto" lines do not count.
    local f2; f2=$(printf '%s\n' "$ann" | fmt2_of)
    local tlen; tlen=$(printf '%s\n' "$tz" | cut -f2- | grep -vE "$PAV_RE" | grep -vE "$E2E_RE" | grep -vE '⚠️ (Superficie|Surface)' \
      | { if [ "$f2" = 1 ]; then grep -vE '^[[:space:]]*\|[[:space:]]*(ID[[:space:]]*\||:?-)' | grep -vE '⚠️ (Rischio aperto|Open risk)'; else cat; fi; } \
      | grep -c '[^[:space:]]' || true)
    case "$lvl" in
      min) [ "$tlen" -le 1 ] || warn "$(msg plan-check.testplan_min n="$tlen")" ;;
      std) [ "$tlen" -le 15 ] || warn "$(msg plan-check.testplan_std n="$tlen")" ;;
    esac
  fi

  # The same section in BOTH languages (1.3.0): e.g. an author who added the English heading next to the
  # existing Italian one. The readers would take only one of the two: VIOLAZIONE. H2 zones of the file and H3
  # sections of the plan, outside fences; "Figlie:" and "Children:" above the plan.
  local dup
  dup=$(printf '%s\n' "$ann" | H2P="$H2_PAIRS" H3P="$H3_PAIRS" PC_IN="$(msg plan-check.dup_in_plan)" PC_ABOVE="$(msg plan-check.dup_above_plan)" awk -F'\t' '
    BEGIN { n2 = split(ENVIRON["H2P"], h2, "\n"); n3 = split(ENVIRON["H3P"], h3, "\n") }
    $3 != 0 { next }
    { for (i = 1; i <= n2; i++) { split(h2[i], p, "|"); if (index($4, "## " p[1]) == 1) a2[i]++; if (index($4, "## " p[2]) == 1) b2[i]++ } }
    ($2 == "plan" || $2 == "changelog") && $4 ~ /^###[ \t]/ { t = $4; sub(/^###[ \t]+([0-9]+\.[ \t]*)?/, "", t)
      for (i = 1; i <= n3; i++) { split(h3[i], p, "|"); if (index(t, p[1]) == 1) a3[i]++; if (index(t, p[2]) == 1) b3[i]++ } }
    $2 == "above" && index($4, "Figlie:") == 1 { fi++ }
    $2 == "above" && index($4, "Children:") == 1 { ch++ }
    END {
      for (i = 1; i <= n2; i++) if (a2[i] && b2[i]) { split(h2[i], p, "|"); print "## " p[1] "\t## " p[2] "\t" }
      for (i = 1; i <= n3; i++) if (a3[i] && b3[i]) { split(h3[i], p, "|"); print "### " p[1] "\t### " p[2] "\t " ENVIRON["PC_IN"] }
      if (fi && ch) print "Figlie:\tChildren:\t " ENVIRON["PC_ABOVE"]
    }')
  local it en where
  while IFS=$'\t' read -r it en where; do
    [ -n "$it" ] && viol "$(msg plan-check.dup_lang it="$it" en="$en" where="$where")"
  done <<< "$dup"

  # Size request (1.7.0, fact F14 of `taglia`): optional, at most one, and only full (piena): the plan author may
  # ask for MORE weight, never less (R3), so any other value is a VIOLAZIONE.
  local sr nsr srv
  sr=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && (index($4, "Size request:") == 1 || index($4, "Taglia richiesta:") == 1) { print $4 }')
  nsr=$(printf '%s' "$sr" | grep -c . || true)
  if [ "${nsr:-0}" -gt 1 ]; then viol "$(msg plan-check-170.size_request_dup n="$nsr")"
  elif [ "${nsr:-0}" -eq 1 ]; then
    srv=$(printf '%s\n' "$sr" | sed -E 's/^(Size request|Taglia richiesta):[[:space:]]*//; s/[^A-Za-z].*$//' | tr 'A-Z' 'a-z')
    case $srv in full|piena) ;; *) viol "$(msg plan-check-170.size_request_bad v="$srv")" ;; esac  # TAGLIA-RICHIESTA
  fi

  # With baseline: the spec above the plan and the implementation review must not be touched.
  if [ -n "$base" ]; then
    [ -f "$base" ] || { echo "$(msg plan-check.lint_no_base base="$base")" >&2; return 2; }
    local bann; bann=$(annotate "$base")
    local b_above c_above b_rev c_rev
    # Trailing spaces and blank lines at the END of the part above the plan do not count: the blank line before
    # "## Piano di implementazione" is added by whoever writes the plan, not by whoever wrote the spec.
    b_above=$(printf '%s\n' "$bann" | awk -F'\t' '$2 == "above" { print $4 }' | above_norm | sha256sum)
    c_above=$(printf '%s\n' "$ann"  | awk -F'\t' '$2 == "above" { print $4 }' | above_norm | sha256sum)
    [ "$b_above" = "$c_above" ] || viol "$(msg plan-check.above_changed)"
    b_rev=$(printf '%s\n' "$bann" | awk -F'\t' '$2 == "review" { print $4 }' | sha256sum)
    c_rev=$(printf '%s\n' "$ann"  | awk -F'\t' '$2 == "review" { print $4 }' | sha256sum)
    [ "$b_rev" = "$c_rev" ] || viol "$(msg plan-check.review_changed)"
  fi

  [ $rc -eq 0 ] && echo "lint: OK"
  return $rc
}

# ─────────────────────────────────────────────────────────────────────────── contract
# The verification contract of the plan, as /implementation-review-cycle consumes it: a single parser for
# both sides, so that level, surfaces and obligations are not re-derived by hand downstream.
cmd_contract() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local ann; ann=$(annotate "$1")
  if ! printf '%s\n' "$ann" | awk -F'\t' '$2 != "above" { f = 1 } END { exit !f }'; then
    echo "nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1
  fi
  local st n lvl decl s pl wl wn wt why r
  st=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Plan status:") == 1 { print $4; exit }')
  echo "${st:-Plan status: (assente)}"
  n=$(printf '%s\n' "$ann" | awk -F'\t' '($2 == "plan" || $2 == "changelog") && $3 == 0 && index($4, "Test level:") == 1' | wc -l)
  lvl=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Test level:") == 1 { sub(/^Test level:[ \t]*/, "", $4); sub(/[ \t].*$/, "", $4); print $4; exit }')
  # n also counts the changelog (where the literal is a duplicate), lvl only the plan: a line that
  # lives only in the changelog is not a level.
  if [ "$n" -eq 0 ] || { [ "$n" -eq 1 ] && [ -z "$lvl" ]; }; then echo "Test level: legacy (assente)"
  elif [ "$n" -gt 1 ]; then echo "Test level: legacy (duplicata: $n)"
  else echo "Test level: $lvl"; fi
  # The declaration as written (an English one too: the consumer is a model); the checks below use the
  # canonical tokens.
  decl=$(printf '%s\n' "$ann" | decl_of)
  echo "Superfici a rischio: ${decl:-(assente)}"
  local tz; tz=$(printf '%s\n' "$ann" | test_zone)
  for s in $(printf '%s\n' "$ann" | declared_surfaces); do
    case " $CRITICAL " in *" $s "*) ;; *) continue ;; esac
    # the text up to the first TAB, as awk $2 read it before pav_toks
    pl=$(printf '%s\n' "$tz" | cut -f1,2 | pav_toks | awk -F'\t' -v s="$s" '$2 == s { print $1; exit }')
    if [ -n "$pl" ]; then echo "Pavimento: $s (riga $pl)"; continue; fi
    wl=$(printf '%s\n' "$ann" | warn_line "$s")
    if [ -z "$wl" ]; then echo "Obbligo: $s — né pavimento né ⚠️"; continue; fi
    wn=${wl%%$'\t'*}; wt=${wl#*$'\t'}
    why=$(waiver_of "$wt")
    if [ -n "$why" ]; then echo "Statica sufficiente: $s — $why (riga $wn)"
    else echo "Obbligo: $s — ⚠️ senza deroga (riga $wn)"; fi
  done
  # Format 2: the "⚠️ Rischio aperto" lines (defect found late, with an assigned test) are risk focuses too.
  local f2; f2=$(printf '%s\n' "$ann" | fmt2_of)
  printf '%s\n' "$ann" | awk -F'\t' -v f2="$f2" '$2 == "plan" && $3 == 0 && (index($4, "⚠️ Superficie") || index($4, "⚠️ Surface") || (f2 == 1 && (index($4, "⚠️ Rischio aperto") || index($4, "⚠️ Open risk")))) {
    t = $4; sub(/^[ \t]*([-*][ \t]+)?/, "", t); print "Rischio: riga " $1 " — " t }'
  # the output keys stay Italian (read by the skills); the headings are read in both languages
  r=$(printf '%s\n' "$ann" | section_range "(Piano di test|Test plan)"); echo "Piano di test: ${r:-assente}"
  r=$(printf '%s\n' "$ann" | section_range "(Tracciabilità requisiti|Requirement traceability)"); echo "Tracciabilità requisiti: ${r:-assente}"
  [ "$f2" = 1 ] && echo "Plan format: 2"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────── basis
# The plan approval bound to what it approved. Two fingerprints (sha256, 12 characters):
#   spec = the sections above "## Piano di implementazione" (as in lint --baseline: trailing spaces and
#          blank lines do not count);
#   plan = the plan BODY: without the changelog (notes and metric line are written after approval)
#          and without the "Approved basis:" line itself. Code blocks count.
# CRs stripped, trailing spaces stripped. The implementation review does not count: it is written later, by someone else.
# At approval the skill writes "Approved basis: spec <fp> · plan <fp>"; /implementation-review-cycle
# records the same two fingerprints as "Reviewed contract:". Missing line → LEGACY (no check).
# Declared limits: an indented or deleted "Approved basis:" line makes the plan LEGACY (lint warns
# on APPROVED without the line); text under a #### heading after the changelog counts as changelog; the
# changelog notes (optional) are not in the fingerprint.
full_line() { sed 's/^[^\t]*\t[^\t]*\t[^\t]*\t//'; }   # the whole line: $4 would stop at the first TAB
basis_of() {
  local s p
  s=$(printf '%s\n' "$1" | awk -F'\t' '$2 == "above"' | full_line | above_norm | sha256sum | cut -c1-12)
  p=$(printf '%s\n' "$1" | awk -F'\t' '$2 == "plan" && !($3 == 0 && index($4, "Approved basis:") == 1)' | full_line | above_norm | sha256sum | cut -c1-12)
  printf 'spec %s · plan %s\n' "$s" "$p"
}
# ─────────────────────────────────────────────────────────────────────────── chains (harness-pt12)
# head_val <file> <letterale> [<English letterale>]: the value of the first "<letterale> …" line above the plan,
# outside fences; with two literals the first line that has either wins (Figlie:/Children:, 1.3.0).
head_val() { annotate "$1" | awk -F'\t' -v l="$2" -v l2="${3:-$2}" '$2 != "above" { exit }
  $3 == 0 && (index($4, l) == 1 || index($4, l2) == 1) { k = (index($4, l) == 1) ? l : l2; v = substr($4, length(k) + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }'; }
# figlie_of <madre>: the names (without .md) of the "Figlie:" (or "Children:") line, in chain order, one per line.
figlie_of() { head_val "$1" "Figlie:" "Children:" | grep -o 'spec-[A-Za-z0-9._-]*' | sed 's/\.md$//; s/\.$//' || true; }
# req_ids <file>: the IDs (RF<n>, CA<n>, and since 1.3.0 FR<n>, AC<n>; also dotted) DEFINED in "Requisiti
# funzionali" / "Functional requirements" and "Criteri di accettazione" / "Acceptance criteria" above the plan,
# outside fences: at the start of a heading, a list item or a table row (the first one on the line). Unique, in
# order. RF1 and FR1 are DISTINCT ids (no alias): a child uses the id family of its mother.
req_ids() {
  annotate "$1" | awk -F'\t' '
    $2 != "above" { exit }
    $3 == 1 { next }
    $4 ~ /^##[ \t]/ { s = $4; sub(/^##[ \t]+([0-9]+\.[ \t]*)?/, "", s); s = tolower(s)
      on = (index(s, "requisiti funzionali") == 1 || index(s, "criteri di accettazione") == 1 ||
        index(s, "functional requirements") == 1 || index(s, "acceptance criteria") == 1); next }
    on && match($4, /^(###+[ \t]+|[ \t]*([-*]|[0-9]+\.)[ \t]+|[ \t]*\|[ \t]*)?[*_`]*(RF|CA|FR|AC)[0-9]+(\.[0-9]+)*/) {
      x = substr($4, RSTART, RLENGTH); match(x, /(RF|CA|FR|AC)[0-9]+(\.[0-9]+)*$/); id = substr(x, RSTART)
      if (!(id in seen)) { seen[id] = 1; print id } }'
}
# madre_of <spec>: "<madre><TAB><k><TAB><n><TAB><precedente|->" if a spec in the same folder lists this one
# in its "Figlie:" (or "Children:") line (the first one, in name order); otherwise nothing.
madre_of() {
  local d b m k
  d=$(dirname "$1"); b=$(basename "$1" .md)
  while IFS= read -r m; do
    [ -n "$m" ] && [ "$(basename "$m" .md)" != "$b" ] || continue
    figlie_of "$m" > "$TMPD/figlie"
    k=$(grep -nxF -- "$b" "$TMPD/figlie" | head -1 | cut -d: -f1)
    [ -n "$k" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$m" "$k" "$(grep -c . "$TMPD/figlie")" \
      "$(if [ "$k" -gt 1 ]; then printf '%s/%s.md' "$d" "$(sed -n "$((k - 1))p" "$TMPD/figlie")"; else printf -- -; fi)"
    return 0
  done < <(find "$d" -maxdepth 1 -type f -name 'spec-*.md' -exec grep -lE '^(Figlie|Children):' {} + 2>/dev/null | LC_ALL=C sort)
}
# closed_why <spec>: prints why the ring is NOT closed (nothing = closed). A single criterion, also used by
# cycle-state.sh (plan-check.sh closed): Review status APPROVED, Feature status IMPLEMENTED and a FRESH
# "Finalize: IMPLEMENTED — snapshot <x12> — … · <ora UTC>" line, with the finalize_gap rules of cycle-state.sh:
# <x12> = fingerprint of the current "Reviewed snapshot:" and a time not older than the last launched review
# (<run-dir>/log/<n>-*review*.jsonl). No legacy fallback: without Finalize the ring is open.
closed_why() {
  local sec rs fs fz snap fs12 now ts rl rt run="${1%.md}.run"
  sec=$(tr -d '\r' < "$1" | awk '{ isf = ($0 ~ /^[ \t]*(```|~~~)/) } isf { inf = !inf; next } inf { next }
    !r && /^## (Review implementazione|Implementation review)/ { r = 1; next } r { print }')
  rs=$(printf '%s\n' "$sec" | sed -n 's/^Review status:[[:space:]]*//p' | head -1)
  fs=$(printf '%s\n' "$sec" | sed -n 's/^Feature status:[[:space:]]*//p' | head -1)
  fz=$(printf '%s\n' "$sec" | sed -n 's/^Finalize:[[:space:]]*//p' | head -1)
  snap=$(printf '%s\n' "$sec" | sed -n 's/^Reviewed snapshot:[[:space:]]*//p' | head -1)
  case "$rs" in APPROVED*) ;; *) echo "Review status ${rs:-(assente)}"; return ;; esac
  case "$fs" in IMPLEMENTED*) ;; *) echo "Feature status ${fs:-(assente)}"; return ;; esac
  case "$fz" in IMPLEMENTED*) ;; "") echo "$(msg plan-check.closed_no_finalize)"; return ;; *) echo "Finalize: $fz"; return ;; esac
  fs12=$(printf '%s\n' "$fz" | sed -n 's/.*snapshot \([0-9a-f]\{12\}\).*/\1/p' | head -1)
  now=$(printf '%s' "$snap" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//' | tr -d '\n' | sha256sum | cut -c1-12)
  [ -n "$fs12" ] && [ "$fs12" = "$now" ] || { echo "$(msg plan-check.closed_other_snap fs="${fs12:-$(msg plan-check.closed_no_fp)}")"; return; }
  ts=$(printf '%s\n' "$fz" | grep -o '[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z' | tail -1)
  ts=$( [ -n "$ts" ] && date -u -d "$ts" +%s 2>/dev/null )
  [ -n "$ts" ] || { echo "$(msg plan-check.closed_no_time)"; return; }
  rl=$(ls "$run/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*review[^.]*\)\.jsonl$/\1/p' | sort -t- -k1,1n | tail -1)
  [ -n "$rl" ] || return 0
  rt=$(date -r "$run/log/$rl.jsonl" +%s 2>/dev/null)
  [ -n "$rt" ] && [ "$ts" -ge "$rt" ] || echo "$(msg plan-check.closed_older rl="$rl")"
}
closed_of() { [ -z "$(closed_why "$1")" ]; }
cmd_closed() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local w; w=$(closed_why "$1")
  if [ -z "$w" ]; then echo "$(msg plan-check.closed_yes)"; return 0; fi
  echo "$(msg plan-check.closed_no w="$w")"; return 1
}
# last_post_tree <run-dir>: the tree of the last .post-tree (highest number label), or nothing.
last_post_tree() {
  local l; l=$(ls "$1/log" 2>/dev/null | sed -n 's/^\([0-9][0-9]*-[^.]*\)\.post-tree$/\1/p' | sort -t- -k1,1n | tail -1)
  [ -n "$l" ] && tr -d '\r\n ' < "$1/log/$l.post-tree"
}
# code_paths: the backticked paths of the lines on stdin (with a /), without ::name and :line.
code_paths() { grep -o '`[^`]*`' | tr -d '`' | grep '/' | sed -E 's/::.*//; s/:[0-9]+(-[0-9]+)?$//; s/[[:space:]].*$//' | grep . | LC_ALL=C sort -u || true; }
# iface_fp <previous spec> <tree> <root>: fingerprint of the files of its "Interfaccia per:" (or "Interface
# for:") line in that tree
# (path + blob, or ABSENT); nothing if the line names no files.
iface_fp() {
  local l p out=""
  l=$(head_val "$1" "Interfaccia per:" "Interface for:" | code_paths)
  [ -n "$l" ] || return 0
  while IFS= read -r p; do
    out="$out$p $(git -C "$3" rev-parse -q --verify "$2:$p" 2>/dev/null || echo ABSENT)
"
  done <<< "$l"
  printf '%s' "$out" | sha256sum | cut -c1-12
}

# TESTS (harness-pt11, format 2 only): the test-red phase, closed OK, appends " · tests <fp>" to the line
# (basis --write-tests): <fp> = sha256 (12) of the lines "<sha256 without CR>  <path>" of the acceptance test
# files (test plan table; `tests` prints them). Compared ONLY when present: different ->
# "Status: STALE (tests)" (an acceptance test changed after test-red is a deviation). In format 2 also
# "Tests: <current fp>" and "Tests status: FRESH | STALE | ASSENTE". Format 1: output unchanged, byte for byte.
cmd_basis() {
  local spec="" wt=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --write-tests) wt=1; shift ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  set -- "$spec"
  local ann cur rec rs rp cs cp what="" f2 tl tcur="" trec="" tst="" nr
  ann=$(annotate "$1")
  if ! printf '%s\n' "$ann" | awk -F'\t' '$2 != "above" { f = 1 } END { exit !f }'; then
    echo "nessuna sezione '## Piano di implementazione' (fuori dai blocchi di codice)"; return 1
  fi
  cur=$(basis_of "$ann")
  # Chain (harness-pt12): the madre / prec / interfaccia fields, only for a child.
  local ch madre="" k="" nk="" prev="" pclosed=0 ptree="" f
  ch=$(madre_of "$1")
  if [ -n "$ch" ]; then
    IFS=$'\t' read -r madre k nk prev <<< "$ch"
    cur="$cur · madre $(annotate "$madre" | awk -F'\t' '$2 == "above"' | full_line | above_norm | sha256sum | cut -c1-12)"
    if [ "$prev" != - ] && [ -f "$prev" ]; then
      cur="$cur · prec $(basis_of "$(annotate "$prev")" | sha256sum | cut -c1-12)"
      if closed_of "$prev"; then
        pclosed=1
        ptree=$(last_post_tree "${prev%.md}.run")
        if [ -n "$ptree" ]; then f=$(iface_fp "$prev" "$ptree" "$(repo_root "$1")"); [ -n "$f" ] && cur="$cur · interfaccia $f"; fi
      fi
    fi
    echo "Catena: anello $k/$nk di $(basename "$madre" .md)$([ "$prev" != - ] && printf ' · precedente %s (%s)' "$(basename "$prev" .md)" "$([ $pclosed -eq 1 ] && echo chiuso || echo aperto)")"
  fi
  rec=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Approved basis:") == 1 { sub(/^Approved basis:[ \t]*/, "", $4); sub(/[ \t]+$/, "", $4); print $4; exit }')
  f2=$(printf '%s\n' "$ann" | fmt2_of)
  if [ "$f2" = 1 ]; then
    need_py || return 2
    tl=$(printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" tests "$(repo_root "$1")") || return 2
    tcur=$(printf '%s\n' "$tl" | sha256sum | cut -c1-12)
    trec=$(printf '%s\n' "$rec" | sed -n 's/.*tests[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p')
    if [ -z "$trec" ]; then tst=ASSENTE; elif [ "$trec" = "$tcur" ]; then tst=FRESH; else tst=STALE; fi
  fi
  rs=$(printf '%s\n' "$rec" | sed -n 's/.*spec[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p')
  rp=$(printf '%s\n' "$rec" | sed -n 's/.*plan[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p')
  cs=$(printf '%s\n' "$cur" | sed -n 's/.*spec \([0-9a-f]*\).*/\1/p')
  cp=$(printf '%s\n' "$cur" | sed -n 's/.*plan \([0-9a-f]*\).*/\1/p')
  if [ $wt -eq 1 ]; then   # test-red closed OK: records the test fingerprint in the line
    [ "$f2" = 1 ] || { echo "basis --write-tests: solo per i piani in formato 2"; return 1; }
    [ -n "$rec" ] || { echo "basis --write-tests: nessuna riga Approved basis (piano non approvato)"; return 1; }
    [ "$rs" = "$cs" ] && [ "$rp" = "$cp" ] || { echo "basis --write-tests: approvazione STALE (spec o piano cambiati): non si registra"; return 1; }
    nr=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan" && $3 == 0 && index($4, "Approved basis:") == 1 { print $1; exit }')
    "$FIC_PY" "$TMPD/plan_check_f2.py" wbasis "$1" "$nr" "$tcur" || { echo "basis --write-tests: riga Approved basis non scritta"; return 1; }
    echo "Tests: $tcur registrata in Approved basis"
    return 0
  fi
  echo "Basis: $cur"
  echo "Recorded: ${rec:-assente}"
  if [ -z "$rec" ]; then
    echo "Status: LEGACY"
    [ "$f2" = 1 ] && { echo "Tests: $tcur"; echo "Tests status: $tst"; }
    return 0
  fi
  [ "$rs" = "$cs" ] || what="spec"
  [ "$rp" = "$cp" ] || what="${what:+$what, }plan"
  local fld r c hit cited
  for fld in madre prec interfaccia; do
    r=$(printf '%s\n' "$rec" | sed -n "s/.*$fld[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p")
    c=$(printf '%s\n' "$cur" | sed -n "s/.*$fld \([0-9a-f]*\).*/\1/p")
    if [ -n "$r" ]; then [ "$r" = "$c" ] || what="${what:+$what, }$fld"
    elif [ -n "$c" ] && [ "$fld" != interfaccia ]; then what="${what:+$what, }$fld"; fi
  done
  # L6: plan approved while the previous ring was implementing (no "interfaccia" recorded), now closed:
  # ANY file cited by the plan and touched by the previous ring → STALE, delta round with k-1 closed.
  if [ $pclosed -eq 1 ] && [ -z "$(printf '%s\n' "$rec" | sed -n 's/.*interfaccia[[:space:]]\{1,\}\([0-9a-f]\{12\}\).*/\1/p')" ]; then
    cited=$(printf '%s\n' "$ann" | awk -F'\t' '$2 == "plan"' | full_line | code_paths)
    hit=""
    [ -n "$cited" ] && hit=$([ -f "${prev%.md}.run/touched.txt" ] && tr -d '\r' < "${prev%.md}.run/touched.txt" | grep -xF -f <(printf '%s\n' "$cited") | head -1)   # CONTROLLO-L6-TOUCHED
    [ -n "$hit" ] && what="${what:+$what, }touched: $hit"
  fi
  [ "$tst" = STALE ] && what="${what:+$what, }tests"   # CONFRONTO-TESTS
  if [ -z "$what" ]; then echo "Status: FRESH"; else echo "Status: STALE ($what)"; fi
  [ "$f2" = 1 ] && { echo "Tests: $tcur"; echo "Tests status: $tst"; }
  return 0
}

# ─────────────────────────────────────────────────────────────────────────── format 2
# Parser of the format 2 tables, in Python (stdin = annotate lines). No single quote in here,
# and ASCII only (non-ASCII characters as \u escapes). need_py writes it to a file in $TMPD (too long for `-c`).
PY2='
import importlib.util, json, os, re, sys

sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
# the message catalog (1.4.0): maat_msg.py from MAAT_MSG_PY (need_py), the same keys as msg in the bash above
_s = importlib.util.spec_from_file_location("maat_msg", os.environ["MAAT_MSG_PY"])
_msg = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_msg)

sys.stdin.reconfigure(encoding="utf-8", errors="replace")
sys.stdout.reconfigure(encoding="utf-8", newline="\n")

SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
H3 = re.compile(r"^###[ \t]+(?:[0-9]+\.[ \t]*)?(.*?)[ \t]*$")
HEAD = re.compile(r"^#{1,3}[ \t]")
# Maat 1.3.0: every heading, keyword and table word is read in Italian AND in English (the canonical name in
# the program stays the Italian one: KEYS, SEC, STR_AZ, STR_TP and CANON map the English forms onto it).
BLOCK = re.compile(r"^####[ \t]+(?:Blocco|Block)[ \t]+([A-Za-z0-9._-]+)")
KV = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(scrive|dopo|writes|after):[ \t]*(.*)$")
KEYS = {"scrive": "scrive", "dopo": "dopo", "writes": "scrive", "after": "dopo"}
SEP = re.compile(r"^:?-+:?$")
LIST = re.compile(r"[,;\u00b7]")
PAV = re.compile(r"^[ \t]*(?:[-*]|[0-9]+\.)[ \t]+\[(?:pavimento|floor):[ \t]*([^\]]*?)[ \t]*\]")
E2E = re.compile(r"^[ \t]*(?:[-*]|[0-9]+\.)[ \t]+\[e2e-locator:[ \t]*([^\]]*?)[ \t]*\]")
RISK = re.compile(r"\u26a0\ufe0f?[ \t]*(?:Rischio aperto|Open risk)")
# assertion of an existing non-regression test (harness-pt15, D): "resta verde", "rimane verde",
# "restano verdi", "continua a passare"... at the start of the cell (after any * _ \u00ab " formatting); in English
# "stays/stay green", "remains/remain green", "keeps/keep passing"
INVARIANZA = re.compile(r"^[\s*_\u00ab\"]*(?:rest(?:a|ano)\s+verd[ei]|riman(?:e|gono)\s+verd[ei]|continu(?:a|ano)\s+a\s+passare"
                        r"|stays?\s+green|remains?\s+green|keeps?\s+passing)\b", re.I)
DESTR = re.compile(r"\bDELETE\b|\.delete\(|\bDROP\b|\bTRUNCATE\b|(?<![A-Za-z0-9_])rm ")
TEST_HDR = ["id", "requisito", "file", "asserzione", "mutazione"]
TEST_HDRS = (TEST_HDR, ["id", "requirement", "file", "assertion", "mutation"])
STEP_HDR = ["id", "file", "modifica", "test"]
STEP_HDRS = (STEP_HDR, ["id", "file", "change", "test"])
STR_HDR = ["azione", "tipo", "valore"]
STR_HDRS = [h + v for h in (STR_HDR, ["action", "type", "value"]) for v in ([], ["verificato"], ["verified"])]
STR_AZ = {"aggiunge": "aggiunge", "toglie": "toglie", "adds": "aggiunge", "removes": "toglie"}
STR_TP = {"stringa": "stringa", "data-test": "data-test", "string": "stringa"}
NONE = ("", "-", "\u2014", "nessuna", "nessuno", "none")
SEC = {"decisioni": "Decisioni", "file toccati": "File toccati", "passi": "Passi",
       "tracciabilit\u00e0 requisiti": "Tracciabilit\u00e0 requisiti", "piano di test": "Piano di test",
       "stringhe e data-test": "Stringhe e data-test",
       "decisions": "Decisioni", "touched files": "File toccati", "steps": "Passi",
       "requirement traceability": "Tracciabilit\u00e0 requisiti", "test plan": "Piano di test",
       "strings and data-test": "Stringhe e data-test"}
VOCAB = ["permessi", "dati", "distruttiva", "contratto-api", "import", "logica-condivisa"]
# English surface token -> canonical (Italian) token: the same pairs as SURF_PAIRS of the bash
CANON = {"permissions": "permessi", "data": "dati", "destructive": "distruttiva", "api-contract": "contratto-api",
         "shared-logic": "logica-condivisa", "none": "nessuna"}
RED_IF = ("rosso se:", "red if:")
NEW = ("(nuovo)", "(new)")


def canon(t):
    return CANON.get(t, t)
MUT_FORM = "`file` \u00b7 `simbolo` \u00b7 `cerca` \u2192 `sostituisci` \u00b7 rosso se: `testo`"
SKIP = {"node_modules", ".nuxt", ".output", ".venv", "__pycache__", ".turbo", "coverage", "dist", ".git", ".pytest_cache"}


def load():
    rows = []
    for raw in sys.stdin.read().split("\n"):
        if not raw:
            continue
        p = raw.split("\t", 3)
        while len(p) < 4:
            p.append("")
        rows.append((int(p[0]), p[1], p[2] == "1", p[3]))
    return rows


def toks(s):
    """testo e code span (anche con piu backtick), come li legge il markdown"""
    out, buf, i, n = [], "", 0, len(s)
    while i < n:
        if s[i] == "`":
            j = i
            while j < n and s[j] == "`":
                j += 1
            m = re.compile("(?<!`)" + s[i:j] + "(?!`)").search(s, j)
            if m:
                if buf:
                    out.append(("t", buf))
                    buf = ""
                c = s[j:m.start()]
                if len(c) >= 2 and c[0] == " " and c[-1] == " " and c.strip():
                    c = c[1:-1]
                out.append(("c", c))
                i = m.end()
                continue
            buf += s[i:j]
            i = j
            continue
        buf += s[i]
        i += 1
    if buf:
        out.append(("t", buf))
    return out


def codes(s):
    return [v for k, v in toks(s) if k == "c"]


def cells(t):
    s = t.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", s)]


def is_sep(c):
    return bool(c) and all(SEP.match(x.replace(" ", "")) for x in c)


def hnorm(c):
    return [x.lower().replace("*", "").replace("`", "").strip() for x in c]


def bare(s):
    return s.strip().strip("`*").strip()


def items(s):
    return [bare(x) for x in LIST.split(s) if bare(x).lower() not in NONE]


def tables(lines):
    out, cur = [], None
    for n, t in lines:
        if t.lstrip().startswith("|"):
            c = cells(t)
            if cur is None:
                cur = {"hdr": hnorm(c), "n": n, "rows": []}
                out.append(cur)
            elif not is_sep(c):
                cur["rows"].append((n, c))
        else:
            cur = None
    return out


def rel_ok(p):
    return (isinstance(p, str) and p != "" and not p.startswith("/") and "\\" not in p
            and ".." not in p.split("/") and not re.match(r"^[A-Za-z]:", p) and " " not in p)


def in_repo(root, p):
    return rel_ok(p) and os.path.exists(os.path.join(root, p.split("/")[0]))


def path_ok(root, p, M):
    """1.7.0 (T3): in_repo, or a file the plan declares new ((new) in Touched files) in a folder that may not exist
    yet: the plan phase writes only the spec, so it cannot create the folder. A path not declared new still needs
    its first segment in the repo (a typo), and rel_ok always holds (no absolute path, .., backslash or space)."""
    return in_repo(root, p) or (rel_ok(p) and p in M["new_files"])  # ECCEZIONE-NUOVI


_CONF = {}


def conf():
    """maat.json del progetto, risolta, letta IMPORTANDO maat-config.py (MAAT_CONFIG_PY, esportata da need_py): le
    stesse funzioni dei comandi modulo-di e comando, nessuna copia delle regole. Il file: MAAT_CONFIG, altrimenti
    <radice>/.claude/maat.json. Progetto non configurato: nessun modulo, nessuna superficie, nessuna migrazione.
    Configurazione non valida o lettore assente: uscita 2."""
    if "r" in _CONF:
        return _CONF["r"]
    import importlib.util
    p = os.environ.get("MAAT_CONFIG_PY") or ""
    try:
        import sys; sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
        sp = importlib.util.spec_from_file_location("maat_config", p)
        mc = importlib.util.module_from_spec(sp)
        sp.loader.exec_module(mc)
    except Exception as e:
        sys.stderr.write("plan-check: " + _msg.T("plan-check.conf_reader", p=p, e=e) + "\n")
        sys.exit(2)
    f = os.environ.get("MAAT_CONFIG") or os.path.join(_CONF.get("root", "."), ".claude", "maat.json")
    try:
        cfg, _p = mc.carica(f)
        r = mc.risolto(cfg)
    except mc.Uscita as u:
        if u.codice != 4:
            sys.stderr.write("plan-check: maat.json: %s\n" % (u.messaggio or _msg.T("plan-check.conf_invalid", code=u.codice)))
            sys.exit(2)
        cfg, r = {"moduli": []}, {"moduli": []}
    _CONF["cfg"] = cfg
    piano = r.get("piano") or {}
    try:
        _CONF["sup"] = [(canon(x["superficie"]), re.compile(x["regex"])) for x in piano.get("superfici_critiche", [])]
        _CONF["mig"] = [re.compile(x) for x in piano.get("migrazioni", [])]
    except re.error as e:
        sys.stderr.write("plan-check: maat.json: " + _msg.T("plan-check.conf_regex", e=e) + "\n")
        sys.exit(2)
    _CONF.update(mc=mc, r=r)
    return r


def modulo(p):
    """(modulo, "radice" | "pacchetti") del percorso (relativo al repo) secondo maat.json, (None, None) fuori"""
    r = conf()
    d = _CONF["mc"].modulo_di(r, p)
    if d is None:
        return None, None
    return next(m for m in r["moduli"] if m["nome"] == d[0]), d[1]


def radice(m):
    return _CONF["mc"].norm(m["radice"])


def rel_radice(m, p):
    rad = radice(m)
    return p[len(rad) + 1:] if rad else p


def runner(f, tp):
    """il modulo che esegue la controprova del file f osservata dal test tp, o None: la regola di counterproof.sh
    (file e test nello stesso modulo di maat.json, il test sotto la radice del modulo)"""
    mf, _kf = modulo(f)
    mt, kt = modulo(tp)
    if mf is None or mt is None or mf["nome"] != mt["nome"] or kt != "radice":
        return None
    return mf["nome"]


def parse_mut(cell):
    if cell.strip().lower() in NONE:
        return None, None
    parts, cur = [], []
    for k, v in toks(cell):
        if k == "c":
            cur.append((k, v))
            continue
        for i, sg in enumerate(v.split("\u00b7")):
            if i:
                parts.append(cur)
                cur = []
            if sg.strip():
                cur.append(("t", sg.strip()))
    parts.append(cur)
    bad = _msg.T("plan-check.mut_bad") + ": " + MUT_FORM + " " + _msg.T("plan-check.mut_bad_empty")
    if len(parts) != 4:
        return None, bad
    f, sym, cs, rs = parts
    if [k for k, v in f] != ["c"] or [k for k, v in sym] != ["c"]:
        return None, bad
    kinds = [k for k, v in cs]
    if kinds == ["c", "t", "c"] and re.match(r"^(\u2192|->)$", cs[1][1]):
        if cs[2][1].strip() in ("(vuoto)", "(empty)"):
            # `x` -> `(vuoto)` would insert the literal text: forbidden, the form is `x` -> (vuoto) (1.6.1)
            return None, _msg.T("plan-check-161.mut_empty_quoted")
        sost = cs[2][1]
    elif kinds == ["c", "t"] and re.match(r"^(\u2192|->)[ \t]*\((?:vuoto|empty)\)$", cs[1][1]):
        sost = ""
    else:
        return None, bad
    if [k for k, v in rs] != ["t", "c"] or rs[0][1].lower() not in RED_IF:
        return None, bad
    m = {"file": f[0][1].strip(), "simbolo": sym[0][1].strip(), "cerca": cs[0][1],
         "sostituisci": sost, "asserzione": rs[1][1]}
    if not m["simbolo"] or not m["asserzione"].strip():
        return None, _msg.T("plan-check.mut_empty_fields")
    if m["cerca"] == m["sostituisci"]:
        return None, _msg.T("plan-check.mut_noop")
    return m, None


def sections(plan):
    sec, dup, cur = {}, [], None
    for n, t in plan:
        m = H3.match(t)
        if m:
            name = m.group(1).lower().replace("*", "")
            cur = None
            for k, v in SEC.items():
                if name == k or name.startswith(k + " ") or name.startswith(k + ":"):
                    cur = v
            if cur in sec:
                dup.append((n, cur))
                cur = None
            elif cur:
                sec[cur] = []
            continue
        if HEAD.match(t):
            cur = None
            continue
        if cur:
            sec[cur].append((n, t))
    return sec, dup


def build(rows, root):
    M = {"E": [], "W": [], "G": []}
    E, W, G = M["E"], M["W"], M["G"]
    plan = [(n, t) for n, z, f, t in rows if z == "plan" and not f]
    M["plan"] = plan
    M["plan_all"] = [(n, t) for n, z, f, t in rows if z == "plan"]
    # 1.7.0 (taglia): the spec above the plan, outside the fences (F4) and whole (F11)
    M["above"] = [(n, t) for n, z, f, t in rows if z == "above" and not f]
    M["above_all"] = [(n, t) for n, z, f, t in rows if z == "above"]
    tg = [t for n, z, f, t in rows if z == "above" and not f and (t.startswith("Taglio:") or t.startswith("Split:"))]
    M["taglio"] = tg[0].split(":", 1)[1].strip() if tg else ""
    M["is2"] = any(re.match(r"^Plan format:[ \t]*2[ \t]*$", t) for n, t in plan)
    fmt = [n for n, t in plan if t.startswith("Plan format:")]
    if len(fmt) > 1:
        E.append(_msg.T("plan-check.fmt_dup", n=fmt[1], k=len(fmt)))
    lvl = [t for n, t in plan if t.startswith("Test level:")]
    M["level"] = (lvl[0][len("Test level:"):].split() or ["legacy"])[0] if lvl else "legacy"
    dl = [t for n, t in plan if t.startswith("Superfici a rischio:") or t.startswith("Risk surfaces:")]
    M["declared"] = None
    if dl:
        M["declared"] = [canon(x) for x in re.split(r"[,;\u00b7\s]+", dl[0].split(":", 1)[1].replace("`", "")) if x]
    sec, dup = sections(plan)
    M["sec"] = sec
    for n, name in dup:
        E.append(_msg.T("plan-check.sec_dup", n=n, name=name))
    for name in ("File toccati", "Passi", "Tracciabilit\u00e0 requisiti", "Piano di test"):
        if name not in sec:
            E.append(_msg.T("plan-check.sec_missing", name=name))

    files, newf = [], []
    for n, t in sec.get("File toccati", []):
        tk = toks(t)
        for i, (k, c) in enumerate(tk):
            if k != "c":
                continue
            c = c.strip()
            if ("/" in c or "." in c) and c not in files:
                files.append(c)
            # harness-pt11: `path` (new) = file the plan creates (scope of the test-red phase, stub, L2)
            if ("/" in c or "." in c) and i + 1 < len(tk) and tk[i + 1][0] == "t" \
                    and tk[i + 1][1].strip().lower().startswith(NEW) and c not in newf:
                newf.append(c)
    M["files"], M["new_files"] = files, newf

    tests, order = {}, []
    tbls = [tb for tb in tables(sec.get("Piano di test", [])) if tb["hdr"] in TEST_HDRS]
    if "Piano di test" in sec and not tbls:
        G.append(_msg.T("plan-check.tp_no_table"))
    for tb in tbls:
        for n, c in tb["rows"]:
            if len(c) != 5:
                G.append(_msg.T("plan-check.tp_cols", n=n, k=len(c)))
                continue
            tid = bare(c[0])
            if not SAFE_ID.match(tid):
                G.append(_msg.T("plan-check.tp_bad_id", n=n, id=tid))
                continue
            if tid in tests:
                G.append(_msg.T("plan-check.tp_dup_id", n=n, id=tid))
                continue
            cs = codes(c[2])
            ref = cs[0].strip() if cs else ""
            path, name = (ref.split("::", 1) + [""])[:2]
            T = {"id": tid, "n": n, "reqs": items(c[1]), "path": path.strip(), "name": name.strip(), "mut": None,
                 "asserzione": c[3].strip(), "texts": [x for x in codes(c[3]) if x.strip()]}
            if not ref:
                G.append(_msg.T("plan-check.tp_no_backtick", n=n, id=tid))
            elif not path_ok(root, T["path"], M):
                G.append(_msg.T("plan-check.tp_path", n=n, id=tid, path=T["path"]))
            if not c[3].strip():
                G.append(_msg.T("plan-check.tp_no_assert", n=n, id=tid))
            m, why = parse_mut(c[4])
            if why:
                G.append(_msg.T("plan-check.tp_why", n=n, id=tid, why=why))
            elif m:
                if not path_ok(root, m["file"], M):
                    G.append(_msg.T("plan-check.tp_mut_path", n=n, id=tid, path=m["file"]))
                elif not T["name"]:
                    G.append(_msg.T("plan-check.tp_mut_noname", n=n, id=tid))
                elif not runner(m["file"], T["path"]):
                    G.append(_msg.T("plan-check.tp_mut_module", n=n, id=tid))
                else:
                    T["mut"] = m
            tests[tid] = T
            order.append(tid)
    M["tests"], M["order"] = tests, order

    blocks, steps, bids = [], [], set()
    cur, hdr = None, None
    for n, t in sec.get("Passi", []):
        m = BLOCK.match(t)
        if m:
            cur = {"id": m.group(1), "n": n, "scrive": None, "dopo": None}
            if cur["id"] in bids:
                E.append(_msg.T("plan-check.blk_dup", n=n, id=cur["id"]))
            bids.add(cur["id"])
            blocks.append(cur)
            hdr = None
            continue
        if t.lstrip().startswith("|"):
            c = cells(t)
            if hdr is None:
                hdr = hnorm(c)
                continue
            if is_sep(c) or hdr not in STEP_HDRS:
                continue
            if len(c) != 4:
                E.append(_msg.T("plan-check.step_cols", n=n, k=len(c)))
                continue
            S = {"id": bare(c[0]), "n": n, "files": [x.strip() for x in codes(c[1]) if x.strip()],
                 "tests": items(c[3]), "block": cur["id"] if cur else None}
            if cur is None:
                E.append(_msg.T("plan-check.step_no_block", n=n, id=S["id"]))
            steps.append(S)
            continue
        hdr = None
        m = KV.match(t)
        if m and cur is not None and cur[KEYS[m.group(1)]] is None:
            cur[KEYS[m.group(1)]] = m.group(2).strip()
    if "Passi" in sec and not steps:
        E.append(_msg.T("plan-check.steps_no_table"))
    if "Passi" in sec and not blocks:
        E.append(_msg.T("plan-check.steps_no_blocks"))
    for b in blocks:
        s = b["scrive"] or ""
        b["files"] = [x.strip() for x in codes(s) if x.strip()] or items(s)
        b["deps"] = [x for x in re.split(r"[,;\u00b7\s]+", (b["dopo"] or "").replace("`", "")) if x and x.lower() not in NONE]
        if not b["files"]:
            E.append(_msg.T("plan-check.blk_no_writes", n=b["n"], id=b["id"]))
        if b["dopo"] is None:
            W.append(_msg.T("plan-check.blk_no_after", n=b["n"], id=b["id"]))
        for d in b["deps"]:
            if d not in bids:
                W.append(_msg.T("plan-check.blk_bad_dep", n=b["n"], id=b["id"], dep=d))
    M["blocks"], M["steps"] = blocks, steps

    reqs = []
    for tb in tables(sec.get("Tracciabilit\u00e0 requisiti", []))[:1]:
        for n, c in tb["rows"]:
            r = bare(c[0])
            if r:
                reqs.append((n, r, c[2].strip() if len(c) > 2 else ""))
    if "Tracciabilit\u00e0 requisiti" in sec and not reqs:
        E.append(_msg.T("plan-check.trace_no_rows"))
    M["reqs"] = reqs
    return M


def test_files(root):
    for d, subs, fs in os.walk(os.path.join(root, "modules")):
        subs[:] = sorted(s for s in subs if s not in SKIP)
        for f in sorted(fs):
            if ".test." in f or ".spec." in f or (f.startswith("test_") and f.endswith(".py")) or f.endswith("_test.py"):
                yield os.path.join(d, f)


# A value counts only INSIDE a literal of the test (single quotes, double quotes, backticks) and WHOLE: never as part of
# a longer word. A line that asserts its ABSENCE stays green when the value disappears: it is an
# AVVISO, not a violation. The decision is PER LITERAL, by position; the line is an absence line only if ALL the
# literals of the value are. A literal is in absence position only if:
#   it is immediately followed by "not in" (python: assert ... "X" not in body);
#   it is INSIDE the argument of .not.toContain( / .not.toHaveText( / .not.toMatch(;
#   it is the argument of a find/get/query... to which .exists()).toBe(false) applies DIRECTLY, or
#   .toBeNull() / .toBeFalsy() without .not. in front: a chained access before the matcher (.attributes(
#   .text() .classes() .element ...) requires the element to exist, and the literal stays positive.
LITERAL = re.compile(r"\x27(?:[^\x27\\]|\\.)*\x27|\x22(?:[^\x22\\]|\\.)*\x22|`(?:[^`\\]|\\.)*`")
NEG_CALL = re.compile(r"\.not\.(?:toContain|toHaveText|toMatch)\(")
NULLISH = re.compile(r"(?<!\.not)\.(?:toBeNull|toBeFalsy)\(\)")  # REGOLA-NULLISH
NOT_EXISTS = re.compile(r"\.exists\(\)\)\.toBe\(false\)")
PY_NOT_IN = re.compile(r"^\s*not\s+in\b")
QUERY = re.compile(r"\b(?:find|findAll|get|querySelector|querySelectorAll|query\w*|findBy\w+|findAllBy\w+|getBy\w+|getAllBy\w+)\(\s*$")
# Not assertions: comment lines and the TITLE of it/test/describe (their first literal);
# nor /re/.test( or x.it( : there must be no dot or letter before the name.
COMMENT = re.compile(r"^\s*(//|/\*|\*|#)")
TITLE = re.compile(r"(?<![.\w])(?:it|test|describe)(?:\.\w+)*\(\s*(" + LITERAL.pattern + ")")


def close_of(l, i, lits):
    """indice della parentesi che chiude quella aperta in l[i], saltando i letterali; len(l) se manca"""
    d, j = 0, i
    while j < len(l):
        inl = [b for a, b in lits if a <= j < b]
        if inl:
            j = inl[0]
            continue
        if l[j] == "(":
            d += 1
        elif l[j] == ")":
            d -= 1
            if d == 0:
                return j
        j += 1
    return len(l)


def lit_absent(l, m, lits):
    """True se il letterale m sta in una posizione di assenza"""
    if PY_NOT_IN.match(l[m.end():]):  # REGOLA-PY-POSIZIONE
        return True
    for c in NEG_CALL.finditer(l):
        if c.end() <= m.start() and m.end() <= close_of(l, c.end() - 1, lits):
            return True
    if QUERY.search(l[:m.start()]):
        k = close_of(l, l.rfind("(", 0, m.start()), lits)
        for t in NOT_EXISTS.finditer(l, k + 1):
            if not l[k + 1:t.start()].strip():
                return True
        for t in NULLISH.finditer(l, k + 1):
            if re.fullmatch(r"[\s)]*", l[k + 1:t.start()]):  # NULLISH-DIRETTO
                return True
    return False


def absent(l, tp, spans):
    """True se la riga l asserisce l ASSENZA del valore: tutti i suoi letterali (spans) in posizione di assenza"""
    lits = [(x.start(), x.end()) for x in LITERAL.finditer(l)]
    return all(lit_absent(l, m, lits) for m in spans)  # TUTTI-I-LETTERALI


def find_hits(root, vals):
    """valore -> [(file, riga, assenza)]: ogni riga di test che lo cita in un letterale"""
    pats, pats_tp = {}, {}
    for tp, val in vals:
        pats_tp[val] = tp
        if tp == "data-test":
            pats[val] = re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(val) + r"(?![A-Za-z0-9_-])")
        else:
            pats[val] = re.compile(r"(?<!\w)" + re.escape(val) + r"(?!\w)")
    hits = {}
    for p in test_files(root):
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                lines = fh.read().split("\n")
        except OSError:
            continue
        rel = os.path.relpath(p, root).replace(os.sep, "/")
        for val, rx in pats.items():
            for i, l in enumerate(lines):
                if COMMENT.match(l):
                    continue
                l = TITLE.sub("(", l)
                spans = [m for m in LITERAL.finditer(l) if rx.search(m.group(0)[1:-1])]
                if spans:  # CRITERIO-LETTERALE
                    hits.setdefault(val, []).append((rel, i + 1, absent(l, pats_tp[val], spans)))  # CLASSIFICA-ASSENZA
    return hits


def doctest_py(path, nm):
    """True when `nm` is the name pytest gives to a doctest of the .py file `path` (--doctest-modules): the dotted name
    of the module (its stem, or the folder for __init__.py, with the packages before it) followed by the object, as in
    `mod.py::mod.func`, `src/pkg/mod.py::pkg.mod.Class.method`, `pkg/__init__.py::pkg.func`. The package prefix of
    the module depends on rootdir and import mode, so it is not compared with the folders of the path."""
    parts = path.replace("\\", "/").split("/")
    stem = parts[-1][:-3]
    mod = parts[-2] if stem == "__init__" and len(parts) > 1 else stem
    comps = nm.split(".")
    if not all(c.isidentifier() for c in comps):
        return False
    return mod in comps[:-1] or (comps[-1] == mod and len(comps) > 1)


def id_py(M):
    """D-C (1.6.0): a Python test named in the unittest form `file.py::Class.method` never matches the report (the JUnit
    case is read as file::Class::method) and the test-red phase stops with a misleading conflict with the existing
    suite. A dot in the name (outside the [parameters]) of a .py test: VIOLAZIONE with the pytest form. A doctest id
    (`mod.py::mod.func`, the dots of the module path included) is a valid pytest id: never refused (CONTROLLO-DOCTEST)."""
    out = []
    for tid in M["order"]:
        T = M["tests"][tid]
        nm, par = (T["name"].split("[", 1) + [None])[:2]
        if T["path"].endswith(".py") and "." in nm and not doctest_py(T["path"], nm):  # CONTROLLO-DOCTEST
            want = T["path"] + "::" + "::".join(x for x in nm.split(".") if x) + ("[" + par if par is not None else "")
            out.append(_msg.T("plan-check-z.id_py", n=T["n"], id=tid, got=T["path"] + "::" + T["name"], want=want))
    return out


# a red text that already names the TypeError of a call with a wrong signature (D-A)
TYPE_RED = re.compile(r"TypeError|unexpected keyword argument|positional argument")


def py_sigs(root, p):
    """top-level functions (not decorated) of a Python file: name -> (n. positional, keyword names, *args, **kw);
    None if the file cannot be read or parsed"""
    import ast
    try:
        with open(os.path.join(root, p), encoding="utf-8", errors="replace") as fh:
            tree = ast.parse(fh.read())
    except (OSError, SyntaxError, ValueError):
        return None
    out = {}
    for n in tree.body:
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and not n.decorator_list:
            a = n.args
            out[n.name] = (len(a.posonlyargs) + len(a.args), set(x.arg for x in a.args + a.kwonlyargs),
                           a.vararg is not None, a.kwarg is not None)
        elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            out.pop(n.name, None)   # a decorated function may have any signature: never judged
    return out


def firma_base(M, root):
    """D-A (1.6.0): the test-red phase writes stubs only in the files the plan declares new. An acceptance test that
    calls an EXISTING function (top level, in a .py file of ### Touched files that is neither new nor a test file) with
    a parameter it does not have yet fails on the base with the TypeError of the call, before its assertion: a row
    whose texts do not name that TypeError asks for a signature stub that nobody writes, and the cycle would stop at
    test-red. VIOLAZIONE, with the red of the base to write. Only the calls written as Python in the backticked texts
    of the assertion; a name defined in several files is judged only if the call is wrong for all of them."""
    import ast
    newf, acc = set(M["new_files"]), set(acc_paths(M))
    sigs = {}
    for f in M["files"]:
        if f.endswith(".py") and f not in newf and f not in acc:
            for name, v in (py_sigs(root, f) or {}).items():
                sigs.setdefault(name, []).append((f, v))
    out = []
    for tid in (M["order"] if sigs else []):
        T = M["tests"][tid]
        if not (T["path"] or "").endswith(".py"):   # SOLO-TEST-PY: a .ts row is not Python, even if a name coincides
            continue
        if any(TYPE_RED.search(x) for x in T["texts"]):
            continue
        why = None
        for x in T["texts"]:
            try:
                tree = ast.parse(x.strip(), mode="eval")
            except (SyntaxError, ValueError):
                continue
            for c in ast.walk(tree):
                if not isinstance(c, ast.Call):
                    continue
                if isinstance(c.func, ast.Name):
                    name, qual = c.func.id, None
                elif isinstance(c.func, ast.Attribute) and isinstance(c.func.value, ast.Name):
                    name, qual = c.func.attr, c.func.value.id
                else:
                    continue
                cand = [(f, v) for f, v in sigs.get(name, [])
                        if qual is None or qual == os.path.splitext(os.path.basename(f))[0]]
                errs = []
                for f, (npos, kws, va, vk) in cand:
                    bad = [k.arg for k in c.keywords if k.arg is not None and k.arg not in kws]
                    npass = len(c.args)
                    if bad and not vk:
                        errs.append(_msg.T("plan-check-z.sig_kw", n=T["n"], id=tid, fn=name, f=f, p=bad[0],
                                           texts=" | ".join(T["texts"])))
                    elif not va and not any(isinstance(a, ast.Starred) for a in c.args) and npass > npos:
                        errs.append(_msg.T("plan-check-z.sig_pos", n=T["n"], id=tid, fn=name, f=f, k=npos, m=npass,
                                           texts=" | ".join(T["texts"])))
                if cand and len(errs) == len(cand):
                    why = errs[0]
                    break
            if why:
                break
        if why:
            out.append(why)
    return out


def report_nessuno(M):
    """D-B (1.6.0): a test row in a module with `report: nessuno`: the test-red phase cannot read the outcome of the
    single tests and stops BLOCKED. A configuration problem, not a plan one: AVVISO, once per module."""
    out, seen = [], set()
    for tid in M["order"]:
        T = M["tests"][tid]
        mt, kt = modulo(T["path"]) if T["path"] else (None, None)
        if mt is None or kt != "radice" or mt["nome"] in seen or (mt.get("report") or "nessuno") != "nessuno":
            continue
        seen.add(mt["nome"])
        out.append(_msg.T("plan-check-z.report_none", id=tid, nome=mt["nome"], path=T["path"]))
    return out


def lint2(M, root):
    E, W = M["E"], M["W"]
    tests, steps = M["tests"], M["steps"]
    E.extend(M["G"])
    covered = set(r for T in tests.values() for r in T["reqs"])
    known = set(r for n, r, v in M["reqs"])
    for n, r, ver in M["reqs"]:
        if r not in covered and not ver.lower().startswith(("non verificabile", "not verifiable")):  # CONTROLLO-REQUISITO-SENZA-TEST
            E.append(_msg.T("plan-check.req_no_test", n=n, r=r))
    for tid in M["order"]:
        for r in tests[tid]["reqs"]:
            if known and r not in known:
                W.append(_msg.T("plan-check.test_bad_req", n=tests[tid]["n"], id=tid, r=r))
    in_steps = set(x for S in steps for x in S["tests"])
    for tid in M["order"]:
        if tid not in in_steps:
            E.append(_msg.T("plan-check.test_no_step", n=tests[tid]["n"], id=tid))
        # harness-pt11: the test-red phase verifies the red on a text of the assertion (ID + position)
        if not tests[tid]["texts"] and not tests[tid]["mut"]:  # CONTROLLO-ASSERZIONE-LINT2
            E.append(_msg.T("plan-check.test_no_text", n=tests[tid]["n"], id=tid))
        # harness-pt15 (D): an EXISTING non-regression test cannot be shown red on the stubbed base; in the
        # table it stops the cycle at test-red. It goes in a note under the table.
        if INVARIANZA.match(tests[tid]["asserzione"]):  # CONTROLLO-NON-REGRESSIONE-LINT2
            E.append(_msg.T("plan-check.test_invariance", n=tests[tid]["n"], id=tid))
    E.extend(id_py(M))  # CONTROLLO-ID-PY-LINT2
    E.extend(firma_base(M, root))  # CONTROLLO-FIRMA-LINT2
    W.extend(report_nessuno(M))
    files = set(M["files"])
    for S in steps:
        for x in S["tests"]:
            if x not in tests:
                W.append(_msg.T("plan-check.step_bad_test", n=S["n"], id=S["id"], t=x))
        for f in S["files"]:
            if f not in files:
                E.append(_msg.T("plan-check.step_not_touched", n=S["n"], id=S["id"], f=f))
            if not path_ok(root, f, M):
                E.append(_msg.T("plan-check.step_path", n=S["n"], id=S["id"], f=f))
    for n, t in M["plan"]:
        if RISK.search(t) and not any(re.search(r"(?<![A-Za-z0-9._-])" + re.escape(tid) + r"(?![A-Za-z0-9._-])", t) for tid in tests):
            E.append(_msg.T("plan-check.risk_no_test", n=n))
    rows = []
    for tb in tables(M["sec"].get("Stringhe e data-test", [])):
        if tb["hdr"] not in STR_HDRS:
            E.append(_msg.T("plan-check.str_table", n=tb["n"]))
            continue
        for n, c in tb["rows"]:
            ver = None   # waiver: verificato column = `file` - reason (long or short dash)
            if len(tb["hdr"]) == 4 and len(c) == 4:
                v, c = c[3].strip(), c[:3]
                if v.lower() not in NONE:
                    vs = re.split(r"\s+(?:" + chr(0x2014) + r"|-)\s+", v, maxsplit=1)
                    vc = codes(vs[0])
                    vf = (vc[0] if vc else vs[0]).strip()
                    why = vs[1].strip() if len(vs) > 1 else ""
                    if not rel_ok(vf) or not why:
                        E.append(_msg.T("plan-check.str_verified", n=n))
                    else:
                        ver = (vf, why)
            az, tp = (c[0].strip().lower(), c[1].strip().lower()) if len(c) == 3 else ("", "")
            az, tp = STR_AZ.get(az, az), STR_TP.get(tp, tp)
            cs = codes(c[2]) if len(c) == 3 else []
            val = cs[0] if cs else (c[2].strip().strip("\u00ab\u00bb\"") if len(c) == 3 else "")
            if az not in ("aggiunge", "toglie") or tp not in ("stringa", "data-test") or not val:
                E.append(_msg.T("plan-check.str_row", n=n))
                continue
            rows.append((n, az, tp, val, ver))
    if rows:
        hits = find_hits(root, [(tp, val) for n, az, tp, val, ver in rows])
        touched = set(M["files"]) | set(f for S in steps for f in S["files"]) | set(T["path"] for T in tests.values())
        e2e = set(x.group(1) for n, t in M["sec"].get("Piano di test", []) for x in [E2E.match(t)] if x)
        for n, az, tp, val, ver in rows:
            byfile = {}
            for rel, ln, neg in hits.get(val, []):
                byfile.setdefault(rel, []).append((ln, neg))
            if ver and ver[0] not in byfile:
                W.append(_msg.T("plan-check.str_unused_waiver", n=n, f=ver[0], tp=tp, val=val))
            for rel, occ in byfile.items():
                pos = [ln for ln, neg in occ if not neg]
                if az == "aggiunge":
                    W.append(_msg.T("plan-check.str_already", n=n, tp=tp, val=val, rel=rel, ln=occ[0][0]))
                elif rel in touched:
                    continue
                elif "/e2e/" in "/" + rel and os.path.basename(rel) in e2e:
                    continue
                elif not pos:
                    W.append(_msg.T("plan-check.str_absence", n=n, tp=tp, val=val, rel=rel, ln=occ[0][0]))
                elif ver and ver[0] == rel:
                    W.append(_msg.T("plan-check.str_waived", n=n, tp=tp, val=val, rel=rel, ln=pos[0], why=ver[1]))
                else:
                    E.append(_msg.T("plan-check.str_asserted", n=n, tp=tp, val=val, rel=rel, ln=pos[0]))
    for w in W:
        print("AVVISO: " + w)
    for e in E:
        print("VIOLAZIONE: " + e)
    if E:
        return 1
    print("lint2: OK")
    return 0


def to_mnt(p):
    p = p.replace("\\", "/")
    if p.startswith("//?/"):   # prefix of Windows long paths, stripped like maat_cygm
        p = p[4:]
    m = re.match(r"^([A-Za-z]):/(.*)$", p) or re.match(r"^/([A-Za-z])/(.*)$", p)
    return "/mnt/" + m.group(1).lower() + "/" + m.group(2) if m else p


def su_windows():
    """le righe vanno in WSL solo su Windows (come run_cp di run-phase.sh): altrove si eseguono dirette"""
    return os.name == "nt" or sys.platform.startswith(("cygwin", "msys"))


def maat_dir(wsl):
    p = (os.environ.get("MAAT_ROOT") or _CONF["mc"].PLUGIN).replace("\\", "/").rstrip("/")
    return to_mnt(p) if wsl else p


def py_wsl(m, root):
    """{python} di un modulo wsl, con la ricerca di gates.sh: i candidati del modulo (relativi alla radice), poi
    piattaforma.python (relativo al repo), poi python3; vince il primo che esiste (il file del repo e lo stesso visto
    da WSL), in forma /mnt. Un nome senza / vale com e ma NON e verificato: gates.sh lo cerca nel PATH di WSL (e se
    manca passa al candidato dopo), qui non si chiama WSL; la riga lo dichiara (riga_cmd). Ritorna (interprete,
    verificato); nessuno: (None, True) (python WSL assente)."""
    if os.environ.get("FIC_GATES_VENV_PY"):
        return os.environ["FIC_GATES_VENV_PY"], True
    mc = _CONF["mc"]
    v, base = m.get("python"), mc.norm(m["radice"])
    if not v:
        v, base = (_CONF["cfg"].get("piattaforma") or {}).get("python") or "python3", ""
    for c in (v if isinstance(v, list) else [v]):
        c = c.replace("\\", "/")
        if "/" not in c:
            return c, False
        if c.startswith("/") or re.match(r"^[A-Za-z]:/", c):
            p = c
        else:
            p = "/".join(x for x in (root.replace("\\", "/").rstrip("/"), base, mc.norm(c)) if x)
        if os.path.lexists(p):
            return to_mnt(p), True
    return None, True


def avvolgi(wsl, inner):
    """la riga in WSL (wsl -- bash -lc <riga quotata per bash: gli apici di espandi diventano \x27\\\x27\x27>) o diretta"""
    return "wsl -- bash -lc " + _CONF["mc"].sq(inner) if wsl else inner


def riga_cmd(m, tipo, root, run, file=(), test=()):
    """la riga di shell di comandi.<tipo> del modulo, da comando() di maat-config.py (stessa espansione di gates.sh):
    cd nella cartella del comando, poi il comando. Modulo ambiente wsl su Windows: dentro WSL, con {maat}, {python} e
    {report} in forma /mnt. {report}: <run>/gen/tests-<modulo>.junit.xml (o .report). Dentro WSL anche MAAT_CONFIG,
    se impostata, in forma /mnt (come in_wsl di gates.sh). {python} preso per nome (non verificato in WSL): un
    commento in coda lo dichiara. Comando non risolvibile: NON DISPONIBILE e il motivo."""
    mc = _CONF["mc"]
    wsl = m.get("ambiente") == "wsl" and su_windows()
    root = root.replace("\\", "/").rstrip("/")
    rep = os.path.abspath(os.path.join(run, "gen", "tests-%s.%s" % (
        m["nome"], "junit.xml" if m.get("report") == "junit" else "report"))).replace("\\", "/")
    env = {"MAAT_ROOT": maat_dir(wsl)}
    nota = ""
    if wsl and "{python}" in mc.testo(m.get("comandi", {}).get(tipo)):
        py, verificato = py_wsl(m, root)
        if py is None:
            return "NON DISPONIBILE \u2014 " + _msg.T("plan-check.gen_no_wsl_py", m=m["nome"])
        if not verificato:
            nota = "  # " + _msg.T("plan-check.gen_unverified", py=py)
        env["FIC_GATES_VENV_PY"] = py
    prima = {k: os.environ.get(k) for k in env}
    os.environ.update(env)
    try:
        cart, riga = mc.comando(_CONF["cfg"], m["nome"], tipo, file=list(file), test=list(test),
                                report=to_mnt(rep) if wsl else rep, root=root)[0]
    except mc.Uscita as u:
        return "NON DISPONIBILE — " + (u.messaggio or _msg.T("plan-check.gen_no_cmd", tipo=tipo, m=m["nome"], code=u.codice))
    finally:
        for k, v in prima.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    d = to_mnt(root + ("/" + cart if cart else "")) if wsl else cart
    pre = ""
    if wsl and os.environ.get("MAAT_CONFIG"):   # outside WSL the line inherits the environment: nothing to add
        pre = "export MAAT_CONFIG=" + mc.sq_se_serve(to_mnt(os.environ["MAAT_CONFIG"].replace("\\", "/"))) + "; "
    return avvolgi(wsl, pre + ("cd " + mc.sq_se_serve(d) + " && " if d else "") + riga) + nota


def riga_cp(muts, root, run):
    """la riga delle controprove: counterproof.sh del plugin su <run>/counterproof/mutations.json, con PROJECT_ROOT
    (e MAAT_CONFIG se impostata); dentro WSL solo su Windows e con un modulo delle mutazioni ambiente wsl (run_cp)"""
    mc = _CONF["mc"]
    wsl = su_windows() and any((modulo(e["file"])[0] or {}).get("ambiente") == "wsl" for e in muts)
    tr = to_mnt if wsl else (lambda x: x)
    mj = os.path.abspath(os.path.join(run, "counterproof", "mutations.json")).replace("\\", "/")
    env = "PROJECT_ROOT=" + mc.sq_se_serve(tr(root.replace("\\", "/").rstrip("/")))
    if os.environ.get("MAAT_CONFIG"):
        env += " MAAT_CONFIG=" + mc.sq_se_serve(tr(os.environ["MAAT_CONFIG"].replace("\\", "/")))
    return avvolgi(wsl, env + " bash " + mc.sq_se_serve(maat_dir(wsl) + "/scripts/counterproof.sh") + " " + mc.sq_se_serve(tr(mj)))


def gen(M, root, run, fp):
    for w in M["W"]:
        print("AVVISO: " + w)
    if M["G"]:
        for e in M["G"]:
            print("VIOLAZIONE: " + e)
        return 1
    tests = M["tests"]
    # vitest:/pytest: lists by DECLARED RUNNER of the test module (controprova.runner, like runner() and
    # counterproof.sh), paths relative to the module root; the other tests (outside the modules, under the packages,
    # comando runner or none) in altri:, with the repo path. per_mod: the tests of each module, for the commands.
    vit, pyt, other = [], [], []
    per_mod = {"vitest": [], "pytest": []}   # [(module, [repo paths])] in order of first appearance
    for tid in M["order"]:
        p = tests[tid]["path"]
        mt, kt = modulo(p)
        rn = (mt.get("controprova") or {}).get("runner") if mt is not None and kt == "radice" else None
        if rn in per_mod:
            x, lst = rel_radice(mt, p), (vit if rn == "vitest" else pyt)
            g = next((v for k, v in per_mod[rn] if k["nome"] == mt["nome"]), None)
            if g is None:
                g = []
                per_mod[rn].append((mt, g))
            if p not in g:
                g.append(p)
        else:
            x, lst = p, other
        if x not in lst:
            lst.append(x)
    pav = [(canon(PAV.match(t).group(1)), t) for n, t in M["sec"].get("Piano di test", []) if PAV.match(t)]
    # L2 (harness-pt11): after the test-red phase (test-red/rossi.json) the mutations of NEW files with the red on
    # the stubbed base proven are marked absorbed; counterproof.sh skips them, finalize.sh rechecks them (l2).
    # Finalize criterion (final=True: stub = symbols exported NOW): when test-red closes the code is the
    # stubs just recorded, so nothing changes; regenerated after the implementation (cp_from_gen of run-phase.sh,
    # L2 promotion of the driver) it does not absorb what finalize would reject.
    l2 = l2_eval(M, root, run, True) if os.path.isfile(os.path.join(run, "test-red", "rossi.json")) else {}
    muts, absorbed = [], []
    for tid in M["order"]:
        T = tests[tid]
        m = T["mut"]
        if not m:
            continue
        mt, _kt = modulo(T["path"])
        # the pytest runner of the counterproofs wants the node id (<file>::<nome>), the others the test name
        pyid = mt is not None and (mt.get("controprova") or {}).get("runner") == "pytest"
        e = {"id": tid, "file": m["file"], "simbolo": m["simbolo"],
             "mutazione": {"cerca": m["cerca"], "sostituisci": m["sostituisci"]},
             "test": {"percorso": T["path"]},
             "rosso_se": {"test_id": T["path"] + "::" + T["name"] if pyid else T["name"],
                          "asserzione": m["asserzione"]}}
        for s, t in pav:
            if re.search(r"(?<![A-Za-z0-9._-])" + re.escape(tid) + r"(?![A-Za-z0-9._-])", t):
                e["superficie"] = s
                break
        if l2.get(tid) == "":
            e["assorbita"] = True
            e["motivo"] = "L2: " + _msg.T("plan-check.gen_l2_reason")
            absorbed.append(tid)
        muts.append(e)
        fpath = os.path.join(root, m["file"])
        if not os.path.isfile(fpath):
            print("AVVISO: " + _msg.T("plan-check.gen_mut_missing", id=tid, f=m["file"]))
        else:
            with open(fpath, "rb") as fh:
                data = fh.read()
            c = m["cerca"].encode("utf-8")
            k = data.count(c)
            if k == 0 and b"\r\n" in data and b"\n" in c:
                k = data.count(c.replace(b"\n", b"\r\n"))
            if k != 1:
                print("AVVISO: " + _msg.T("plan-check.gen_mut_count", id=tid, k=k, f=m["file"]))
    lines = ["Plan format: 2", "Impronta piano: " + fp, "Test level: " + M["level"],
             "vitest: " + (" ".join(vit) or "(nessuno)"), "pytest: " + (" ".join(pyt) or "(nessuno)"),
             "altri: " + (" ".join(other) or "(nessuno)")]
    # the commands: comandi.test and comandi.lint of the module, expanded by comando() of maat-config.py (riga_cmd)
    for rn in ("vitest", "pytest"):
        for mt, g in per_mod[rn]:
            lines.append("cmd %s: %s" % (rn, riga_cmd(mt, "test", root, run, test=g)))
    if M["level"] == "full":   # lint: every file of the plan for the module (root or packages), like gates.sh
        for mt in conf()["moduli"]:
            if "lint" not in mt.get("comandi", {}):
                continue
            fl = [f for f in M["files"] if (modulo(f)[0] or {}).get("nome") == mt["nome"]]
            if fl:
                lines.append("cmd lint: " + riga_cmd(mt, "lint", root, run, file=fl))
    if muts:
        lines.append("cmd counterproof: " + riga_cp(muts, root, run))
    lines.append("mutazioni: %d" % len(muts))
    for b in M["blocks"]:
        lines.append("blocco %s: scrive=%s \u00b7 dopo=%s" % (b["id"], ",".join(b["files"]) or "(nessuno)", ",".join(b["deps"]) or "nessuno"))
    os.makedirs(os.path.join(run, "gen"), exist_ok=True)
    with open(os.path.join(run, "gen", "procedura.txt"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    mj = os.path.join(run, "counterproof", "mutations.json")
    if muts:
        os.makedirs(os.path.dirname(mj), exist_ok=True)
        with open(mj, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(muts, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    elif os.path.isfile(mj):
        os.unlink(mj)
    for l in lines:
        print(l)
    for tid in absorbed:
        print("gen: " + _msg.T("plan-check.gen_absorbed", id=tid))
    print("gen: " + _msg.T("plan-check.gen_written", path=os.path.join(run, "gen", "procedura.txt").replace(os.sep, "/"), extra=(" " + _msg.T("plan-check.gen_and_mut")) if muts else ""))
    return 0


def surf_of(p):
    """superfici del percorso (relativo al repo): ogni regola {superficie, regex} di piano.superfici_critiche di
    maat.json la cui regex si trova nel percorso (re.search); nessuna regola = nessuna superficie"""
    conf()
    return {s for s, rx in _CONF["sup"] if rx.search(p)}


def is_mig(p):
    """il percorso e un file di migrazione: una regex di piano.migrazioni di maat.json si trova nel percorso"""
    conf()
    return any(rx.search(p) for rx in _CONF["mig"])


def route(M, diff):
    paths = []
    def add(p, where):
        p = re.sub(r":[0-9]+(-[0-9]+)?$", "", p.split("::")[0].strip())
        if p and "/" in p and " " not in p and (p, where) not in paths:
            paths.append((p, where))
    if M["is2"]:
        for f in M["files"]:
            add(f, "piano")
        for S in M["steps"]:
            for f in S["files"]:
                add(f, "piano")
        for b in M["blocks"]:
            for f in b["files"]:
                add(f, "piano")
        for T in M["tests"].values():
            add(T["path"], "piano")
    else:
        for n, t in M["plan"]:
            for c in codes(t):
                add(c, "piano")
    text = [(_msg.T("plan-check.route_plan_line", n=n), t) for n, t in M["plan_all"]]
    if diff:
        with open(diff, encoding="utf-8", errors="replace") as fh:
            for i, l in enumerate(fh.read().split("\n")):
                m = re.match(r"^diff --git a/(\S+) b/(\S+)", l)
                if m:
                    add(m.group(1), "diff")
                    add(m.group(2), "diff")
                elif l[:1] in "+-" and not l.startswith("+++") and not l.startswith("---"):
                    text.append((_msg.T("plan-check.route_diff_line", n=i + 1), l[1:]))
    ev = {}
    mig = []
    for p, where in paths:
        for s in surf_of(p):
            ev.setdefault(s, []).append(p)
        if is_mig(p) and p not in mig:
            mig.append(p)
    for where, t in text:
        m = DESTR.search(t)
        if m:
            ev.setdefault("distruttiva", []).append(_msg.T("plan-check.route_keyword", k=m.group(0).strip(), where=where))
    decl = M["declared"]
    dset = set(x for x in (decl or []) if x in VOCAB)
    if "distruttiva" in dset and "distruttiva" not in ev:
        ev["distruttiva"] = [_msg.T("plan-check.route_declared")]
    det = [s for s in VOCAB if s in ev]
    nl = len(M["plan_all"])
    print(_msg.T("plan-check.route_lines", n=nl))
    print(_msg.T("plan-check.route_migration") + ": " + (", ".join(mig) if mig else "no"))
    for s in det:
        print(_msg.T("plan-check.route_surface", s=s, ev=", ".join(ev[s][:3]) + (" (+%d)" % (len(ev[s]) - 3) if len(ev[s]) > 3 else "")))
    print(_msg.T("plan-check.route_detected") + ": " + (", ".join(det) or "nessuna"))
    print(_msg.T("plan-check.route_declared_label") + ": " + ("(assente)" if decl is None else (", ".join(decl) or "(vuota)")))
    why = []
    if nl > 150:
        why.append(_msg.T("plan-check.route_why_lines", n=nl))
    if mig:
        why.append(_msg.T("plan-check.route_why_mig"))
    if det:
        why.append(_msg.T("plan-check.route_why_det") + ": " + ", ".join(det))
    if decl is None:
        why.append(_msg.T("plan-check.route_why_nodecl"))
    elif decl != ["nessuna"]:
        why.append(_msg.T("plan-check.route_why_decl") + ": " + (", ".join(decl) or "(vuota)"))
    a = [s for s in det if s not in dset]
    b = [s for s in VOCAB if s in dset and s not in det]
    if a or b:
        d = []
        if a:
            d.append(_msg.T("plan-check.route_det_undecl") + ": " + ", ".join(a))
        if b:
            d.append(_msg.T("plan-check.route_decl_undet") + ": " + ", ".join(b))
        print(_msg.T("plan-check.route_mismatch") + ": " + " \u00b7 ".join(d))
        why.append(_msg.T("plan-check.route_why_mismatch"))
    if why:
        print("Percorso: pieno \u2014 " + " \u00b7 ".join(why))
    else:
        print("Percorso: leggero \u2014 " + _msg.T("plan-check.route_light"))
    return 0


SKEL_STEPS, SKEL_FILES, PLAN_LINES = 15, 40, 400


def skeleton(M):
    """harness-pt12: scheletro sotto o sopra il tetto (passi, file) e piano completo entro le righe"""
    files = list(M["files"])
    for S in M["steps"]:
        for f in S["files"]:
            if f not in files:
                files.append(f)
    ns, nf, nl = len(M["steps"]), len(files), len(M["plan_all"])
    if not ns:
        print("AVVISO: " + _msg.T("plan-check.skel_no_steps"))
    decl = M["declared"]
    print(_msg.T("plan-check.skel_steps", n=ns, cap=SKEL_STEPS))
    print(_msg.T("plan-check.skel_files", n=nf, cap=SKEL_FILES))
    print(_msg.T("plan-check.skel_surfaces") + ": " + ("(assente)" if decl is None else (", ".join(decl) or "(vuota)")))
    print(_msg.T("plan-check.skel_lines", n=nl, cap=PLAN_LINES))
    over = []
    if ns > SKEL_STEPS:  # TETTO-PASSI
        over.append(_msg.T("plan-check.skel_over_steps", n=ns, cap=SKEL_STEPS))
    if nf > SKEL_FILES:
        over.append(_msg.T("plan-check.skel_over_files", n=nf, cap=SKEL_FILES))
    if nl > PLAN_LINES:
        over.append(_msg.T("plan-check.skel_over_lines", n=nl, cap=PLAN_LINES))
    if M["taglio"]:
        print("Taglio: " + M["taglio"])
    if over and M["taglio"].lower().startswith(("rifiutato", "rejected")):  # DECISIONE-TAGLIO
        print("Scheletro: SOPRA IL TETTO — " + " · ".join(over)
              + ": " + _msg.T("plan-check.skel_cut_refused"))
        return 0
    if over:
        print("Scheletro: SOPRA IL TETTO — " + " · ".join(over)
              + ": " + _msg.T("plan-check.skel_cut_proposal"))
        return 1
    print("Scheletro: SOTTO IL TETTO \u2014 " + _msg.T("plan-check.skel_under"))
    return 0


# ---- 1.7.0: the size of the cycle (taglia), from verifiable facts only (header of this file) ----
SIZE_CAPS = (("file_sorgente", 3), ("file_nuovi", 1), ("passi", 6), ("requisiti", 12), ("test", 10),
             ("righe", 250), ("simboli_pubblici", 2))
SIZE_CRIT = ("permessi", "dati", "distruttiva")
# F11, at word boundaries, case-insensitive (D6: a false positive costs only the full flow); a project may ADD words
# (piano.taglia.parole_sicurezza), never remove these
SIZE_SEC = (r"(?!author(?:s|ed|ing|ship)?\b)auth\w*", r"passwords?", r"passwd", r"secrets?", r"credential\w*",
            r"(?:access|auth|api)[ _-]?tokens?", r"(?:en|de)?crypt\w*", r"permission\w*", r"privilege\w*", r"sudo",
            r"chmod", r"eval\(", r"exec\(", r"shell\s*=\s*True", r"sql", r"inject\w*", r"sanitiz\w*", r"csrf",
            r"xss", r"cookies?", r"sessions?")
# F4: the id families always counted in the spec, plus those of the traceability table
SIZE_REQ = ("RF", "RNF", "NFR", "FR", "CA", "AC", "REQ", "R")
SIZE_REQUEST = re.compile(r"^(?:Size request|Taglia richiesta):[ \t]*(.*)$")
# F13: files that define no public symbol (documents, data, styles, images) count 0; a language not listed here and
# not ruled below (shell, for example) is not measurable (D9): piena
SIZE_NOCODE = (".md", ".markdown", ".txt", ".rst", ".json", ".yml", ".yaml", ".toml", ".ini", ".cfg", ".csv", ".tsv",
               ".lock", ".css", ".scss", ".sass", ".less", ".html", ".htm", ".svg", ".png", ".jpg", ".jpeg", ".gif",
               ".ico", ".xml")
SIZE_JS = (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts", ".vue", ".svelte")
GO_SYM = re.compile(r"^(?:func[ \t]+(?:\([^)]*\)[ \t]*)?|type[ \t]+|var[ \t]+|const[ \t]+)([A-Z]\w*)")
JS_CJS = re.compile(r"^[ \t]*(?:module\.)?exports(?:\.(\w+))?[ \t]*=(?!=)")
# the catalog keys of each fact: (label of its line, short label of the Taglia: line)
SIZE_LAB = {
    "F1": (lambda: _msg.T("plan-check-170.l_f1"), lambda: _msg.T("plan-check-170.s_f1")),
    "F2": (lambda: _msg.T("plan-check-170.l_f2"), lambda: _msg.T("plan-check-170.s_f2")),
    "F3": (lambda: _msg.T("plan-check-170.l_f3"), lambda: _msg.T("plan-check-170.s_f3")),
    "F4": (lambda: _msg.T("plan-check-170.l_f4"), lambda: _msg.T("plan-check-170.s_f4")),
    "F5": (lambda: _msg.T("plan-check-170.l_f5"), lambda: _msg.T("plan-check-170.s_f5")),
    "F6": (lambda: _msg.T("plan-check-170.l_f6"), lambda: _msg.T("plan-check-170.s_f6")),
    "F7": (lambda: _msg.T("plan-check-170.l_f7"), lambda: _msg.T("plan-check-170.s_f7")),
    "F8": (lambda: _msg.T("plan-check-170.l_f8"), lambda: _msg.T("plan-check-170.s_f8")),
    "F9": (lambda: _msg.T("plan-check-170.l_f9"), lambda: _msg.T("plan-check-170.s_f9")),
    "F10": (lambda: _msg.T("plan-check-170.l_f10"), lambda: _msg.T("plan-check-170.s_f10")),
    "F11": (lambda: _msg.T("plan-check-170.l_f11"), lambda: _msg.T("plan-check-170.s_f11")),
    "F12": (lambda: _msg.T("plan-check-170.l_f12"), lambda: _msg.T("plan-check-170.s_f12")),
    "F13": (lambda: _msg.T("plan-check-170.l_f13"), lambda: _msg.T("plan-check-170.s_f13")),
    "F14": (lambda: _msg.T("plan-check-170.l_f14"), lambda: _msg.T("plan-check-170.s_f14")),
}


def size_clean(p):
    return re.sub(r":[0-9]+(-[0-9]+)?$", "", p.split("::")[0].strip())


def size_names(ext, lines):
    out = []
    for l in lines:
        if ext == ".py":
            m = PY_DEF.match(l)   # F13-PY: top level only, a method or a nested function is not public API
            if m:
                out.append(m.group(1))
        elif ext in SIZE_JS:
            m = TS_EXP.match(l)  # F13-JS
            if m:
                out.append(m.group(1))
                continue
            m = TS_EXP_LIST.match(l)
            if m:
                out += [x.strip().split(" as ")[-1].strip() for x in m.group(1).split(",") if x.strip()]
                continue
            if TS_EXP_ANON.match(l):
                out.append("default")
                continue
            m = JS_CJS.match(l)
            if m:
                out.append(m.group(1) or "module.exports")
        elif ext == ".go":
            m = GO_SYM.match(l)  # F13-GO
            if m:
                out.append(m.group(1))
    return out


def size_sym(path, added, removed):
    """F13 for one file: the public names on the added lines minus those on the removed lines (a changed signature
    is not a new symbol); 0 for a file that defines none (SIZE_NOCODE); None = no rule for the language (D9)."""
    ext = os.path.splitext(path)[1].lower()
    if ext in SIZE_NOCODE:
        return 0
    if ext != ".py" and ext != ".go" and ext not in SIZE_JS:  # SIMBOLI-NON-MISURABILI
        return None
    rm = set(size_names(ext, removed))
    return len([x for x in size_names(ext, added) if x not in rm])


def size_diff(diff):
    """(paths, {path: (added, removed)}, deleted, changed lines) of a unified git diff; None if unreadable"""
    try:
        with open(diff, encoding="utf-8", errors="replace") as fh:
            t = fh.read().replace("\r", "")
    except OSError:
        return None
    # 1.7.0 review: the paths come from the "--- a/" and "+++ b/" lines (to the end of the line: a path with spaces
    # too), the "diff --git" header only when it is unambiguous; a file whose path cannot be read makes the whole
    # diff not measurable (None). "rename from" is a deletion of the old path (F12), "new file mode" a new file (F2).
    paths, files, deleted, text, new = [], {}, [], [], []
    st = {}

    def chiudi():   # the file of the header just read; False if its path is unknown
        if not st:
            return True
        cur = st.get("b") or st.get("rto") or st.get("hb")
        if not cur:
            return False
        for p in (st.get("a"), st.get("ha"), st.get("rfrom"), st.get("rto"), cur):
            if p and p not in paths:
                paths.append(p)
        files.setdefault(cur, ([], []))
        if st.get("del"):
            deleted.append(cur)
        if st.get("rfrom"):  # RINOMINA-ELIMINA
            deleted.append(st["rfrom"])
        if st.get("new"):
            new.append(cur)
        st["cur"] = cur
        return True

    cur, hdr = None, False
    for i, l in enumerate(t.split("\n")):
        if l.startswith("diff --git "):
            if hdr and not chiudi():
                return None
            m = re.match(r"^diff --git a/(\S+) b/(\S+)$", l)
            st.clear()
            st.update({"ha": m.group(1), "hb": m.group(2)} if m else {"unreadable": True})
            cur, hdr = None, True
        elif hdr and l.startswith("--- "):
            p = l[4:].rstrip("\t")
            if p.startswith("a/"):
                st["a"] = p[2:]
            elif p != "/dev/null":
                return None
        elif hdr and l.startswith("+++ "):
            p = l[4:].rstrip("\t")
            if p.startswith("b/"):
                st["b"] = p[2:]
            elif p == "/dev/null" and st.get("a"):
                st["b"] = st["a"]
            else:
                return None
            if not chiudi():
                return None
            cur, hdr = st["cur"], False
        elif hdr and l.startswith("new file mode"):
            st["new"] = True
        elif hdr and l.startswith("deleted file mode"):
            st["del"] = True
        elif hdr and l.startswith("rename from "):
            st["rfrom"] = l[len("rename from "):]
        elif hdr and l.startswith("rename to "):
            st["rto"] = l[len("rename to "):]
        elif hdr and l.startswith("@@"):
            return None
        elif cur is None:
            continue
        elif l.startswith("+"):
            files[cur][0].append(l[1:])
            text.append((i + 1, l[1:]))
        elif l.startswith("-"):
            files[cur][1].append(l[1:])
            text.append((i + 1, l[1:]))
    if hdr and not chiudi():
        return None
    return paths, files, deleted, text, new


SIZE_TEST = re.compile(r"\.(test|spec)\.[cm]?[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.(py|go)$|(^|/)conftest\.py$")


def size_is_test(p, cfg):
    """a test file by the project convention: the name (SIZE_TEST) or the specchio.a glob of a module of maat.json.
    A path in the file column of the test table that is neither counts as a source file (1.7.0 review)."""
    import fnmatch
    if SIZE_TEST.search(p):  # CONVENZIONE-TEST
        return True
    for m in (cfg or {}).get("moduli", []) or []:
        g = ((m.get("specchio") or {}).get("a") or "").replace("{m}", "*")
        if g and (fnmatch.fnmatch(p, g) or fnmatch.fnmatch(p, g.lstrip("*/"))):
            return True
    return False


def taglia(M, root, diff, ovr, touched=""):
    if os.environ.get("FIC_TAGLIA") == "off":   # a cycle started before 1.7: no size, the flow of 1.6 (driver.py)
        print("Taglia: piena — " + _msg.T("plan-check-170.why_off"))
        return 0
    nm = lambda why: _msg.T("plan-check-170.unmeasurable", why=why)
    sec = M["sec"]
    conf_ok = True
    try:
        r = conf()
    except SystemExit:   # maat.json invalid: conf has said why on stderr; every fact from it is not measurable
        conf_ok, r = False, {}
    tg = ((r.get("piano") or {}).get("taglia") or {}) if conf_ok else {}
    caps, badcap = dict(SIZE_CAPS), []
    for k, v in (tg.get("soglie") or {}).items():
        if k in caps and isinstance(v, int) and not isinstance(v, bool) and v >= 0:
            caps[k] = v
        else:
            badcap.append(str(k))
    words = list(SIZE_SEC) + [w if isinstance(w, str) and w else "(" for w in (tg.get("parole_sicurezza") or [])]
    try:
        sec_rx = re.compile("|".join(r"\b(?:%s)%s" % (w, "" if w.endswith(r"\(") else r"\b") for w in words), re.I)
    except re.error:
        sec_rx = None
    auto = tg.get("automatica", True)
    fmt1 = not M["is2"]
    decl_tests = set(T["path"] for T in M["tests"].values() if T["path"])   # the file column of the test table
    tpaths = set(p for p in decl_tests if size_is_test(p, r if conf_ok else {}))   # only real test files
    plan_paths = []
    for f in list(M["files"]) + [x for S in M["steps"] for x in S["files"]] + [x for b in M["blocks"] for x in b.get("files", [])]:
        p = size_clean(f)
        if p and p not in plan_paths:
            plan_paths.append(p)
    for p in sorted(decl_tests - tpaths):   # a "test" that does not follow the convention is a source file
        if p not in plan_paths:
            plan_paths.append(p)
    src = [p for p in plan_paths if p not in tpaths]
    dd = size_diff(diff) if diff else None
    # new: declared (new), or not in the repo yet, or "new file mode" in the diff (1.7.0 review: (new) is optional)
    newf = set(size_clean(x) for x in M["new_files"]) | set(dd[4] if dd else [])
    newf |= set(p for p in src if rel_ok(p) and not os.path.exists(os.path.join(root, p)))  # NUOVI-DAL-DISCO

    def why_sec(name):   # the reason a fact of a plan section is not measurable, or ""
        if fmt1:
            return _msg.T("plan-check-170.why_fmt1")
        return "" if name in sec else _msg.T("plan-check-170.why_sec", name=name)

    facts = []   # (id, kind num|bar, value, cap, items, unmeasurable reason, extra text)

    def num(fid, key, v, why, extra=""):
        facts.append((fid, "num", v, caps[key], [], why, extra))

    def bar(fid, items, why=""):
        facts.append((fid, "bar", None, None, items, why, ""))

    w = why_sec("File toccati") or ("" if M["files"] else _msg.T("plan-check-170.why_nopaths"))  # NESSUN-PERCORSO
    num("F1", "file_sorgente", len(src), w)
    num("F2", "file_nuovi", len([p for p in src if p in newf]), w)
    w = why_sec("Passi") or ("" if M["steps"] else _msg.T("plan-check-170.why_nosteps"))
    num("F3", "passi", len(M["steps"]), w)
    w = why_sec("Tracciabilit\u00e0 requisiti")
    tr = set(x for n, x, v in M["reqs"])
    pref = set(SIZE_REQ)
    for x in tr:
        mm = re.match(r"^([A-Za-z]+)-?[0-9]", x)
        if mm:
            pref.add(mm.group(1))
    idrx = re.compile(r"(?<![A-Za-z0-9_.-])((?:%s)-?[0-9]+(?:\.[0-9]+)*)(?![A-Za-z0-9_-])"
                      % "|".join(sorted((re.escape(x) for x in pref), key=len, reverse=True)))
    ids = set()
    for n, t in M["above"]:
        ids.update(idrx.findall(t))
    num("F4", "requisiti", max(len(tr), len(ids)), w or ("" if tr else _msg.T("plan-check.trace_no_rows")),
        _msg.T("plan-check-170.f4_detail", a=len(tr), b=len(ids)))  # F4-CONTA-LA-SPEC
    tbls = [tb for tb in tables(sec.get("Piano di test", [])) if tb["hdr"] in TEST_HDRS]
    w = why_sec("Piano di test") or ("" if tbls else _msg.T("plan-check.tp_no_table"))
    num("F5", "test", sum(len(tb["rows"]) for tb in tbls), w)
    num("F6", "righe", len(M["plan_all"]), "")

    dwhy = _msg.T("plan-check-170.why_diff", p=diff) if diff and dd is None else ""
    dpaths = dd[0] if dd else []
    tlines = []   # the touched.txt lines (--touched): the paths of the code written, spaces included
    if touched:
        try:
            with open(touched, encoding="utf-8", errors="replace") as fh:
                tlines = [x.strip("\r") for x in fh.read().split("\n") if x.strip()]
        except OSError:
            dwhy = dwhy or _msg.T("plan-check-170.why_diff", p=touched)
    every = plan_paths + [p for p in sorted(tpaths) if p not in plan_paths]
    every += [p for p in dpaths + tlines if p not in every]
    decl = M["declared"]
    dwhy7 = _msg.T("plan-check-170.why_nodecl") if decl is None else ""
    cwhy = "" if conf_ok else _msg.T("plan-check-170.why_conf")
    f7 = [s + " (" + _msg.T("plan-check-170.v_declared") + ")" for s in SIZE_CRIT if s in (decl or [])]
    f8 = [_msg.T("plan-check-170.v_declared")] if "contratto-api" in (decl or []) else []
    f9 = []
    if conf_ok:
        for p in every:
            ss = surf_of(p)
            f7 += [s + " (" + p + ")" for s in SIZE_CRIT if s in ss]  # F7-RILEVATA
            if "contratto-api" in ss:
                f8.append(p)
            if is_mig(p) and p not in f9:
                f9.append(p)
    bar("F7", f7, dwhy7 or cwhy or dwhy)
    bar("F8", f8, dwhy7 or cwhy or dwhy)
    bar("F9", f9, cwhy or dwhy)
    text = [(_msg.T("plan-check.route_plan_line", n=n), t) for n, t in M["plan_all"]]
    dtext = [(_msg.T("plan-check.route_diff_line", n=n), t) for n, t in (dd[3] if dd else [])]
    f10 = []
    for where, t in text + dtext:
        m = DESTR.search(t)  # F10-DESTR
        if m:
            f10.append(_msg.T("plan-check.route_keyword", k=m.group(0).strip(), where=where))
    bar("F10", f10, dwhy)
    f11, seen = [], set()
    # the Risk surfaces: line is the declaration itself (F7, F8), not a word of the change
    stext = [(w_, t) for w_, t in text if not (t.startswith("Risk surfaces:") or t.startswith("Superfici a rischio:"))]
    for where, t in [(_msg.T("plan-check-170.spec_line", n=n), t) for n, t in M["above_all"]] + stext + dtext:
        for m in (sec_rx.finditer(t) if sec_rx else []):  # F11-SICUREZZA
            k = m.group(0).lower()
            if k not in seen:
                seen.add(k)
                f11.append("%s (%s)" % (m.group(0), where))
    bar("F11", f11, dwhy or ("" if sec_rx else _msg.T("plan-check-170.why_words")))
    if not diff:   # F12 and F13 are facts of the code written: only with --diff
        facts.append(("F12", "na", None, None, [], "", ""))
        facts.append(("F13", "na", None, None, [], "", ""))
    else:
        bar("F12", list(dd[2]) if dd else [], dwhy)
        sym, nosym = 0, []
        for p, (a, rm) in (dd[1].items() if dd else []):
            if p in tpaths or not a:
                continue
            k = size_sym(p, a, rm)
            if k is None:
                nosym.append(p)
            else:
                sym += k
        num("F13", "simboli_pubblici", sym, dwhy or (_msg.T("plan-check-170.why_sym", p=", ".join(nosym)) if nosym else ""))
    f14, f14bad = [], []
    for n, t in M["plan"]:
        m = SIZE_REQUEST.match(t)
        if m:
            v = m.group(1).strip()
            w0 = re.split(r"[^A-Za-z]", v, 1)[0].lower() if v else ""
            if w0 in ("full", "piena"):
                f14.append(v)
            else:
                f14bad.append(_msg.T("plan-check-170.v_invalid", v=v or "-"))
    bar("F14", f14 + f14bad, "")
    oop = []   # a path of the diff or of touched.txt the plan does not name (E3)
    for p in dpaths + tlines:
        if p not in plan_paths and p not in tpaths and p not in oop:
            oop.append(p)
    # 1.7.0 review: a plan that lint2 refuses is not measurable (a malformed table can hide files, steps, tests)
    import contextlib, io
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc2 = 0 if fmt1 else lint2(M, root)
    except SystemExit:
        rc2 = 1
    if rc2:  # LINT2-NON-MISURABILE
        v1 = [x[len("VIOLAZIONE: "):] for x in buf.getvalue().splitlines() if x.startswith("VIOLAZIONE: ")]
        facts.append(("FL", "bar", None, None, [], _msg.T("plan-check-170.why_lint2", n=len(v1), first=(v1 or ["-"])[0]), ""))

    light = ovr == "light"
    if badcap:
        facts.append(("F0", "bar", None, None, [], _msg.T("plan-check-170.why_caps", keys=", ".join(badcap)), ""))
    if not isinstance(auto, bool):
        facts.append(("F0", "bar", None, None, [], _msg.T("plan-check-170.why_auto_bad"), ""))
    none_ = _msg.T("plan-check-170.v_none")
    piena, tutti, fatti = [], [], []
    for fid, kind, v, cap, items, why, extra in facts:
        lab = SIZE_LAB[fid][1]() if fid in SIZE_LAB else {"F0": "piano.taglia", "FL": "lint2"}[fid]
        if kind == "na":
            print("%s %s: %s" % (fid, SIZE_LAB[fid][0](), _msg.T("plan-check-170.v_na")))
            fatti.append(fid + "=-")
            continue
        if why:
            val, fv = nm(why), "?"
        elif kind == "num":
            val, fv = "%d/%d" % (v, cap), "%d/%d" % (v, cap)
        else:
            val = ", ".join(items[:3]) + (" (+%d)" % (len(items) - 3) if len(items) > 3 else "") if items else none_
            fv = str(len(items))
        short = lab + " " + val if kind == "num" and not why else lab + ": " + val
        if fid in SIZE_LAB:
            print("%s %s: %s%s" % (fid, SIZE_LAB[fid][0](), val, (" " + extra) if extra and not why else ""))
            fatti.append("%s=%s" % (fid, fv))
        tutti.append(short)
        if why or (kind == "bar" and items) or (kind == "num" and v > cap and not light):  # SOGLIE-NUMERICHE
            piena.append(short)
    if diff or touched:
        print("%s: %s" % (_msg.T("plan-check-170.l_oop"), ", ".join(oop) if oop else none_))
        if oop:
            piena.append(_msg.T("plan-check-170.l_oop") + ": " + ", ".join(oop[:3]) + (" (+%d)" % (len(oop) - 3) if len(oop) > 3 else ""))
    if ovr == "full":
        ov = "override: --full"
        piena.insert(0, ov)
    elif light:
        ov = "override: --light"
    elif auto is False:
        ov = "override: " + _msg.T("plan-check-170.why_auto")
        piena.insert(0, ov)
    else:
        ov = "override: " + _msg.T("plan-check-170.ovr_none")
    print(ov)
    print("Fatti: " + " ".join(fatti))
    if piena:
        print("Taglia: piena \u2014 " + " \u00b7 ".join(piena))
    else:
        print("Taglia: piccola \u2014 " + " \u00b7 ".join(tutti + [ov]))
    return 0


# ---- harness-pt11: test-red phase (acceptance tests, stubs, verification of the reds) and L2 ----
IMPORT_JS = re.compile(r"Failed to load url|Failed to resolve import|Cannot find module|Cannot find package|does not provide an export named|is not exported by|Failed to parse source|Transform failed|SyntaxError|ERR_MODULE_NOT_FOUND")
IMPORT_PY = re.compile(r"ImportError|ModuleNotFoundError|SyntaxError|IndentationError|cannot import name")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
TS_EXP = re.compile(r"^[ \t]*export[ \t]+(?:declare[ \t]+)?(?:default[ \t]+)?(?:async[ \t]+)?(?:abstract[ \t]+)?(?:function\*?|const|let|var|class|interface|type|enum)[ \t]+([A-Za-z_$][\w$]*)", re.M)
TS_EXP_LIST = re.compile(r"^[ \t]*export[ \t]*(?:type[ \t]*)?\{([^}]*)\}", re.M)
TS_EXP_ANON = re.compile(r"^[ \t]*export[ \t]+default[ \t]+(?!(?:async[ \t]+)?(?:function|class)[ \t]+[A-Za-z_$])", re.M)
PY_DEF = re.compile(r"^(?:async[ \t]+)?(?:def|class)[ \t]+([A-Za-z]\w*)", re.M)
PY_ASSIGN = re.compile(r"^([A-Za-z]\w*)[ \t]*(?::[^=\n]*)?=(?!=)", re.M)
FAILH = re.compile(r"^\s*FAIL\s+(?:\|[^|]*\|\s+)?(\S+)(.*)$")
RANL = re.compile(r"^\s*(?:\u2713|\u276f|\u00d7|\u2193|FAIL)\s+(?:\|[^|]*\|\s+)?(\S+)")
SEPL = re.compile(r"\u23af{3,}")


def nrm(s):
    return " ".join(ANSI.sub("", s or "").split())


def jload(p):
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def jsave(p, d):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".tmp", "w", encoding="utf-8", newline="\n") as fh:
        json.dump(d, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(p + ".tmp", p)


def acc_paths(M):
    """i file dei test di accettazione (tabella del piano di test), in ordine"""
    out = []
    for tid in M["order"]:
        p = M["tests"][tid]["path"]
        if p and p not in out:
            out.append(p)
    return out


def stub_files(M):
    """i file che il piano dichiara nuovi e che non sono test di accettazione: vi vanno gli stub"""
    tp = set(acc_paths(M))
    return [f for f in M["new_files"] if f not in tp]


def cmd_accept(M):
    """scope della fase test-red: test <path> (i file di test del piano) e nuovo <path> (i file nuovi)"""
    for p in acc_paths(M):
        print("test " + p)
    for p in stub_files(M):
        print("nuovo " + p)
    return 0


def cmd_tests(M, root):
    """le righe dell impronta dei test di accettazione: sha256 del contenuto senza CR, due spazi, path"""
    import hashlib
    for p in sorted(acc_paths(M)):
        fp = os.path.join(root, p)
        if os.path.isfile(fp):
            with open(fp, "rb") as fh:
                h = hashlib.sha256(fh.read().replace(b"\r", b"")).hexdigest()
        else:
            h = "ABSENT"
        print(h + "  " + p)
    return 0


def exports(root, p):
    """simboli esportati di un file (None se assente): TS/JS export, Python def/class/nomi pubblici di modulo,
    .vue il componente (nome del file). Un export default anonimo vale il nome del file."""
    try:
        with open(os.path.join(root, p), encoding="utf-8", errors="replace") as fh:
            s = fh.read()
    except OSError:
        return None
    out = []

    def add(x):
        if x and x not in out:
            out.append(x)
    base_name = os.path.splitext(os.path.basename(p))[0]
    if p.endswith(".py"):
        for m in PY_DEF.finditer(s):
            add(m.group(1))
        for m in PY_ASSIGN.finditer(s):
            add(m.group(1))
    elif p.endswith(".vue"):
        add(base_name)
    else:
        for m in TS_EXP.finditer(s):
            add(m.group(1))
        for m in TS_EXP_LIST.finditer(s):
            for x in m.group(1).split(","):
                w = x.split()
                if w:
                    add(w[-1])
        if TS_EXP_ANON.search(s):
            add(base_name)
    return sorted(out)


def mentioned(root, paths, sym):
    rx = re.compile(r"(?<![\w$])" + re.escape(sym) + r"(?![\w$])")
    for p in paths:
        try:
            with open(os.path.join(root, p), encoding="utf-8", errors="replace") as fh:
                if rx.search(fh.read()):
                    return True
        except OSError:
            continue
    return False


def cmd_stubs(M, root, run):
    """alla chiusura OK di test-red: i simboli degli stub di ogni file nuovo -> <run>/test-red/stubs.json"""
    d = {}
    for f in stub_files(M):
        ex = exports(root, f)
        d[f] = {"simboli": ex}
        print("stub %s: %s" % (f, _msg.T("plan-check.stub_absent") if ex is None else (", ".join(ex) or ("(" + _msg.T("plan-check.stub_none") + ")"))))
    jsave(os.path.join(run, "test-red", "stubs.json"), d)
    return 0


def l2_why(T, m, stubs, rossi, root, acc, final):
    """perche la controprova di T NON e assorbita (vuoto = assorbita). final: codice implementato."""
    st = stubs.get(m["file"])
    if not isinstance(st, dict) or not isinstance(st.get("simboli"), list):
        return _msg.T("plan-check.l2_no_stubs")
    r = rossi.get(T["id"]) if isinstance(rossi, dict) else None
    if not isinstance(r, dict) or r.get("esito") != "dimostrato":
        return _msg.T("plan-check.l2_not_proven")
    if not r.get("posizione"):
        return _msg.T("plan-check.l2_no_pos")
    if nrm(m["asserzione"]) not in nrm(r.get("messaggio")):
        return _msg.T("plan-check.l2_other_assert", a=m["asserzione"])
    sy = st["simboli"]
    if final:
        cur = exports(root, m["file"])
        if cur is None:
            return _msg.T("plan-check.l2_file_missing")
        if sorted(cur) != sorted(sy):
            return _msg.T("plan-check.l2_symbols", cur=", ".join(cur) or "-", sy=", ".join(sy) or "-")
        sy = cur
    miss = [s for s in sy if not mentioned(root, acc, s)]  # SIMBOLI-TESTATI
    if miss:
        return _msg.T("plan-check.l2_untested") + ": " + ", ".join(miss)
    return ""


def l2_eval(M, root, run, final):
    """tid -> motivo ("" = assorbibile), per le sole mutazioni su file NUOVI (non di test)"""
    stubs = jload(os.path.join(run, "test-red", "stubs.json")) or {}
    rossi = (jload(os.path.join(run, "test-red", "rossi.json")) or {}).get("test") or {}
    acc = acc_paths(M)
    newf = set(stub_files(M))
    res = {}
    for tid in M["order"]:
        T = M["tests"][tid]
        m = T["mut"]
        if m and m["file"] in newf:
            res[tid] = l2_why(T, m, stubs, rossi, root, acc, final)
    return res


def cmd_l2(M, root, run, tests_state):
    """per finalize.sh: una riga per mutazione su un file nuovo, L2 <id>: OK | NO - <motivo>"""
    for tid, why in l2_eval(M, root, run, True).items():
        if tests_state != "FRESH":
            why = _msg.T("plan-check.l2_tests_changed", state=tests_state)
        print("L2 %s: %s" % (tid, "OK" if not why else "NO \u2014 " + why))
    return 0


def junit_cases(p):
    import xml.etree.ElementTree as ET
    try:
        root = ET.parse(p).getroot()
    except Exception:
        return None
    out = []
    for c in root.iter("testcase"):
        kids = list(c)
        out.append({"cn": c.get("classname") or "", "nm": c.get("name") or "",
                    "bad": [(e.get("message") or "") + "\n" + (e.text or "") for e in kids if e.tag in ("failure", "error")],
                    "skip": any(e.tag == "skipped" for e in kids), "own": None})
    return out


_NOMI = []


def nomi():
    """1.8.0 (D1-bis): nomi_test.py next to this script (NOMI_TEST_PY, exported by need_py), imported: the same
    relation of the test names as counterproof.sh"""
    if not _NOMI:
        import importlib.util
        sp = importlib.util.spec_from_file_location("nomi_test", os.environ["NOMI_TEST_PY"])
        mo = importlib.util.module_from_spec(sp)
        sp.loader.exec_module(mo)
        _NOMI.append(mo)
    return _NOMI[0]


def py_claim(T, c, trel, seps=None):
    """come un caso JUnit riguarda il test T (trel: il suo percorso relativo alla radice del modulo): target | antenato
    | file | suite | None. 1.8.0 (D1-bis): la relazione dei nomi di nomi_test.py coi separatori del linguaggio
    (seps): uguale e discendente -> target (un sottotest Go, un parametro pytest, i metodi di una classe nominata),
    antenato -> reclamato (un adattatore che piega i sottotest nel padre)"""
    mod = trel[:-3].replace("/", ".") if trel.endswith(".py") else trel.replace("/", ".")
    cn, nm = c["cn"], c["nm"]
    if not cn:
        return "suite" if nm in (mod, trel, T["path"]) or nm.endswith("." + mod) else None
    if cn == mod:
        rest = ""
    elif cn.startswith(mod + "."):
        rest = "::" + cn[len(mod) + 1:].replace(".", "::")
    else:
        return None
    if not T["name"]:
        return "target"
    nt = nomi()
    rel = nt.relazione(T["name"], trel + rest + "::" + nm, seps or nt.separatori(trel))
    return {"uguale": "target", "discendente": "target", "antenato": "antenato"}.get(rel, "file")


def vitest_blocks(text):
    """blocchi FAIL del reporter di default: file (relativo alla radice del modulo), segmenti del nome o None (suite), testo"""
    lines = ANSI.sub("", text).split("\n")
    blocks, cur, ran = [], None, set()
    for l in lines:
        s = re.match(r"^\s*Tests\s+([0-9]+)\s+failed", l)  # runner summary: how many tests are red
        if s:
            ran.add("#failed=" + s.group(1))
        r = RANL.match(l)
        if r:
            ran.add(r.group(1).lstrip("./"))
        m = FAILH.match(l)
        if m:
            rest = m.group(2).strip()
            segs = [x.strip() for x in rest[1:].split(" > ")] if rest.startswith(">") else None
            cur = {"file": m.group(1).lstrip("./"), "segs": segs, "body": [], "own": None}
            blocks.append(cur)
            continue
        if SEPL.search(l):
            cur = None
            continue
        if cur is not None:
            cur["body"].append(l)
    return blocks, ran


def vt_claim(T, b, trel):
    if b["file"] != trel:
        return None
    if b["segs"] is None:
        return "suite"
    if not T["name"]:
        return "target"
    # the plan may name the test as vitest prints it ("describe > it") or with the full -t name ("describe it");
    # 1.8.0 (D1-bis): a `describe` named by the plan claims its tests (the structured chain, never a prefix with a space)
    nt = nomi()
    rel = nt.relazione(T["name"], None, nt.SEP_VITEST, segmenti=b["segs"])
    return {"uguale": "target", "discendente": "target", "antenato": "antenato"}.get(rel, "file")


# D-D (1.6.0): the frame of a Python traceback, as a JUnit of a runner other than pytest (unittest) carries it
TRACEBACK_POS = re.compile(r"File \"([^\"]+)\", line ([0-9]+)")


def posizione(T, raw, trel):
    r = raw.replace("\\", "/")
    m = re.search(re.escape(trel) + r":([0-9]+)", r)
    if m:
        return "%s:%s" % (T["path"], m.group(1))
    # no pytest «file:line:» line: the deepest frame of the traceback in the test file (the path ends with it)
    m = TRACEBACK_POS.findall(r)  # POSIZIONE-TRACEBACK
    hit = [ln for f, ln in m if f == trel or f.endswith("/" + trel)]
    return "%s:%s" % (T["path"], hit[-1]) if hit else None


def verdict(T, failed, suite, ran, passed, imp, trel):
    """(esito, motivo, messaggio, posizione) di un test di accettazione sulla base con stub"""
    texts = T["texts"] or ([T["mut"]["asserzione"]] if T["mut"] else [])
    if failed:
        raw = "\n".join(failed)
        msg = nrm(raw)
        pos = posizione(T, raw, trel)
        if imp.search(msg):  # CLASSIFICAZIONE-IMPORT
            return "rosso_import", _msg.T("plan-check.red_import"), msg, pos
        if not texts:  # CONTROLLO-ASSERZIONE: without an assertion text no red is proven
            return "rosso_senza_asserzione", _msg.T("plan-check.red_no_text"), msg, pos
        if texts and not any(nrm(x) in msg for x in texts):
            return "rosso_diverso", _msg.T("plan-check.red_other", texts=" | ".join(texts)), msg, pos
        if not pos:  # CONTROLLO-POSIZIONE: ID + position in the test file
            return "rosso_senza_asserzione", _msg.T("plan-check.red_no_pos"), msg, pos
        return "dimostrato", _msg.T("plan-check.red_proven"), msg, pos
    if suite:
        msg = nrm("\n".join(suite))
        if imp.search(msg):
            return "rosso_import", _msg.T("plan-check.red_suite_import"), msg, None
        return "rosso_raccolta", _msg.T("plan-check.red_collection"), msg, None
    if not ran:
        return "rosso_raccolta", _msg.T("plan-check.red_not_collected"), "", None
    if passed:
        return "verde", _msg.T("plan-check.red_green"), "", None
    return "rosso_raccolta", _msg.T("plan-check.red_not_run"), "", None


def cmd_rossi(M, root, run, ev):
    """Verifica del driver sulla base con stub (evidenza di gates.sh in <ev>): ogni test di accettazione rosso
    sulla sua asserzione, nessuna suite esistente in conflitto. Scrive <run>/test-red/rossi.json.
    Uscita 0 OK (tutti dimostrati) - 1 STOP - 3 BLOCKED (evidenza assente o gate BLOCKED)."""
    tests = M["tests"]
    # one tests-<modulo> gate per module of maat.json; the report is read via the report field of the module
    mods = conf()["moduli"]
    gates = {"tests-" + m["nome"]: jload(os.path.join(ev, "tests-" + m["nome"] + ".json")) for m in mods}
    fmt = {"tests-" + m["nome"]: m.get("report", "nessuno") for m in mods}
    rad = {"tests-" + m["nome"]: radice(m) for m in mods}
    rep = {}
    for g, d in gates.items():
        # NOT RUN (with the space, phase-result.schema.json) as SKIPPED: tests not run, never blocked;
        # any other outcome (BLOCKED, NOT_RUN...) stays out of rep, that is blocked
        if not isinstance(d, dict) or d.get("esito") not in ("PASS", "FAIL", "SKIPPED", "NOT RUN"):
            continue
        p = os.path.join(ev, d.get("report") or "-")
        if d.get("esito") in ("SKIPPED", "NOT RUN"):
            rep[g] = None
        elif fmt[g] == "junit":
            rep[g] = junit_cases(p)
            if rep[g] is None:
                rep[g] = False
        elif fmt[g] == "vitest":
            try:
                with open(p, encoding="utf-8", errors="replace") as fh:
                    rep[g] = vitest_blocks(fh.read())
            except OSError:
                rep[g] = False
        else:
            rep[g] = False   # report none: the outcomes of the single tests cannot be read
    out, blocked = {}, []
    if not M["order"]:
        print("AVVISO: " + _msg.T("plan-check.red_no_rows"))
    for tid in M["order"]:
        T = tests[tid]
        mt, kt = modulo(T["path"])
        g = "tests-" + mt["nome"] if mt is not None and kt == "radice" else None
        if g is None:
            out[tid] = ("non_eseguito", _msg.T("plan-check.red_outside"), "", None)
            continue
        d = gates[g]
        if not isinstance(d, dict) or g not in rep or rep[g] is False:
            why = _msg.T("plan-check.red_no_ev") if not isinstance(d, dict) else (
                _msg.T("plan-check.red_gate_esito", esito=d.get("esito"), motivo=d.get("motivo") or "") if g not in rep else
                _msg.T("plan-check.red_report_bad") if fmt[g] != "nessuno" else
                _msg.T("plan-check.red_report_none") + " (" + _msg.T("plan-check-z.red_report_none_fix") + ")")
            if "%s: %s" % (g, why) not in blocked:
                blocked.append("%s: %s" % (g, why))
            continue
        if rep[g] is None:
            out[tid] = ("non_eseguito", "gate %s %s: %s" % (g, d.get("esito"), d.get("motivo") or ""), "", None)
            continue
        trel = rel_radice(mt, T["path"])
        # 1.8.0 (D1-bis): an ancestor case (antenato) is claimed, never a conflict; its text counts only without a case
        # uguale/discendente and if it holds the leaf of the plan name (the adapter that folds the subtests)
        seps = nomi().separatori(trel, mt.get("separatori_test"))
        leaf = nomi().foglia(T["name"], seps)
        anc_bad, anc_pass, has_t = [], False, False
        if fmt[g] == "junit":
            failed, suite, ran, passed = [], [], False, False
            for c in rep[g]:
                k = py_claim(T, c, trel, seps)
                if k is None:
                    continue
                if k == "suite":
                    ran = True
                    if c["bad"]:
                        suite += c["bad"]
                        c["own"] = tid
                    continue
                ran = True
                if k == "antenato":   # ANTENATO-RECLAMATO
                    if c["bad"]:
                        anc_bad += c["bad"]
                        c["own"] = c["own"] or tid
                    elif not c["skip"]:
                        anc_pass = True
                    continue
                if k == "target":
                    has_t = True
                    if c["bad"]:
                        failed += c["bad"]
                        c["own"] = tid
                    elif not c["skip"]:
                        passed = True
            if not has_t:
                failed = [x for x in anc_bad if leaf and leaf in x]
                passed = anc_pass and not anc_bad
            out[tid] = verdict(T, failed, suite, ran, passed, IMPORT_PY, trel)
        else:
            blocks, ran_files = rep[g]
            failed, suite = [], []
            for b in blocks:
                k = vt_claim(T, b, trel)
                if k == "target":
                    failed.append("\n".join(b["body"]))
                    b["own"] = tid
                elif k == "antenato":
                    anc_bad.append("\n".join(b["body"]))
                    b["own"] = b["own"] or tid
                elif k == "suite":
                    suite.append("\n".join(b["body"]))
                    b["own"] = tid
            if not failed:
                failed = [x for x in anc_bad if leaf and leaf in x]
            ran = trel in ran_files or any(b["file"] == trel for b in blocks)
            out[tid] = verdict(T, failed, suite, ran, ran and not failed and not suite, IMPORT_JS, trel)
    # conflicts: an EXISTING suite red on the stubbed base (a case no acceptance test claims),
    # or an existing test asserting the ABSENCE of a value the plan adds (### Stringhe e data-test)
    def related(f):
        ids = [t for t in M["order"] if tests[t]["path"] == f] or M["order"]
        return "; ".join("%s: %s" % (t, tests[t]["asserzione"][:100]) for t in ids)
    confl = []
    def sotto_rad(g, x):
        return (rad[g] + "/" if rad[g] else "") + x
    for g in [x for x in gates if fmt[x] == "junit"]:   # JUnit first, then vitest: the previous order
        for c in (rep.get(g) or []):
            if c["bad"] and c["own"] is None:
                f = sotto_rad(g, c["cn"].replace(".", "/") + ".py") if c["cn"] else c["nm"]
                confl.append("%s::%s \u2014 %s <-> %s" % (c["cn"] or ("(" + _msg.T("plan-check.red_collection_case") + ")"), c["nm"], nrm("\n".join(c["bad"]))[:200], related(f)))
    for g in [x for x in gates if fmt[x] == "vitest"]:
        fe = rep.get(g)
        if fe:  # the vitest summary and the blocks read must add up: otherwise the parser has lost some reds
            nsum = [int(x.split("=")[1]) for x in fe[1] if x.startswith("#failed=")]
            nblk = len([b for b in fe[0] if b["segs"] is not None])
            if nsum and nsum[-1] != nblk:
                confl.append(_msg.T("plan-check.red_vitest_sum", n=nsum[-1], k=nblk))
        for b in (fe[0] if fe else []):
            if b["own"] is None:
                confl.append("%s%s \u2014 %s <-> %s" % (b["file"], " > " + " > ".join(b["segs"]) if b["segs"] else " (file)",
                                                       nrm("\n".join(b["body"]))[:200], related(sotto_rad(g, b["file"]))))
    adds = []
    for tb in tables(M["sec"].get("Stringhe e data-test", [])):
        for n, c in tb["rows"]:
            if len(c) >= 3 and STR_AZ.get(c[0].strip().lower()) == "aggiunge" and c[1].strip().lower() in STR_TP:
                cs = codes(c[2])
                v = cs[0] if cs else c[2].strip().strip("\u00ab\u00bb\"")
                if v:
                    adds.append((STR_TP[c[1].strip().lower()], v))
    if adds:
        for val, hs in find_hits(root, adds).items():
            for rel, ln, neg in hs:
                if neg:  # CONFLITTO-STATICO
                    near = [t for t in M["order"] if val in tests[t]["asserzione"]] or M["order"]
                    confl.append(_msg.T("plan-check.red_absence", rel=rel, ln=ln, val=val,
                                        near="; ".join("%s: %s" % (t, tests[t]["asserzione"][:100]) for t in near)))
    for tid in M["order"]:
        es, why, msg, pos = out.get(tid, ("bloccato", _msg.T("plan-check.red_gate_unusable"), "", None))
        print("rosso %s: %s%s \u2014 %s%s" % (tid, es, (" " + pos) if pos else "", why, (" \u2014 " + msg[:200]) if msg else ""))
    for c in confl:
        print("conflitto: " + c)
    bad = [t for t in M["order"] if t in out and out[t][0] != "dimostrato"]
    if blocked:
        esito, riass = "BLOCKED", _msg.T("plan-check.red_sum_blocked") + ": " + "; ".join(blocked)
    elif bad or confl:
        parts = [_msg.T("plan-check.red_sum_bad") + ": " + ", ".join("%s %s" % (t, out[t][0]) for t in bad)] if bad else []
        if confl:
            parts.append(_msg.T("plan-check.red_sum_conflict") + ": " + confl[0])
        esito, riass = "STOP", "; ".join(parts)
    else:
        esito, riass = "OK", _msg.T("plan-check.red_sum_ok", n=len(out), k=len(M["order"]))
    jsave(os.path.join(run, "test-red", "rossi.json"), {
        "esito": esito, "riassunto": riass, "evidence": ev, "conflitti": confl,
        "test": {t: {"esito": v[0], "motivo": v[1], "messaggio": v[2][:4000], "posizione": v[3],
                     "file": tests[t]["path"], "nome": tests[t]["name"]} for t, v in out.items()}})
    print("rossi: esito=%s \u2014 %s" % (esito, riass))
    return {"OK": 0, "STOP": 1}.get(esito, 3)


def cmd_wbasis(spec, nr, fp):
    """scrive (o sostituisce) \u00b7 tests <fp> in coda alla riga Approved basis (riga nr), fine riga conservata"""
    with open(spec, encoding="utf-8", newline="") as fh:
        lines = fh.read().splitlines(keepends=True)
    i = int(nr) - 1
    if i < 0 or i >= len(lines):
        return 1
    body = lines[i].rstrip("\r\n")
    eol = lines[i][len(body):]
    if not body.startswith("Approved basis:"):
        return 1
    body = re.sub(r"[ \t]*\u00b7[ \t]*tests[ \t]+[0-9a-f]+", "", body).rstrip()
    lines[i] = body + " \u00b7 tests " + fp + eol
    with open(spec + ".tests.tmp", "w", encoding="utf-8", newline="") as fh:
        fh.write("".join(lines))
    os.replace(spec + ".tests.tmp", spec)
    return 0


cmd = sys.argv[1]
if cmd == "wbasis":
    sys.exit(cmd_wbasis(*sys.argv[2:5]))
_CONF["root"] = sys.argv[2]   # the repository root: maat.json by default, read at the first question (conf)
M = build(load(), sys.argv[2])
if not M["is2"] and cmd in ("lint2", "gen", "skeleton"):
    print(_msg.T("plan-check.not_applicable", cmd=cmd))
    sys.exit(0)
if not M["is2"] and cmd in ("accept", "tests", "stubs", "rossi", "l2"):
    print(_msg.T("plan-check.not_applicable", cmd=cmd))
    sys.exit(2)
if cmd == "accept":
    sys.exit(cmd_accept(M))
elif cmd == "tests":
    sys.exit(cmd_tests(M, sys.argv[2]))
elif cmd == "stubs":
    sys.exit(cmd_stubs(M, sys.argv[2], sys.argv[3]))
elif cmd == "rossi":
    sys.exit(cmd_rossi(M, sys.argv[2], sys.argv[3], sys.argv[4]))
elif cmd == "l2":
    sys.exit(cmd_l2(M, sys.argv[2], sys.argv[3], sys.argv[4]))
if cmd == "lint2":
    sys.exit(lint2(M, sys.argv[2]))
elif cmd == "gen":
    sys.exit(gen(M, sys.argv[2], sys.argv[3], sys.argv[4]))
elif cmd == "route":
    sys.exit(route(M, sys.argv[3] if len(sys.argv) > 3 else ""))
elif cmd == "skeleton":
    sys.exit(skeleton(M))
elif cmd == "taglia":
    sys.exit(taglia(M, sys.argv[2], "" if sys.argv[3] == "-" else sys.argv[3], "" if sys.argv[4] == "-" else sys.argv[4],
                    "" if sys.argv[5] == "-" else sys.argv[5]))
sys.exit(2)
'

need_py() {
  # The program goes into a file in $TMPD, never into `-c`: beyond ~32k characters Windows rejects the command line.
  printf '%s' "$PY2" > "$TMPD/plan_check_f2.py" || return 2
  # PY2 imports the message catalog: maat_msg.py next to THIS script (a copy of the plugin uses its own), in the
  # form native Python reads
  MAAT_MSG_PY=$(maat_cygm "$PC_HERE/maat_msg.py" 2>/dev/null || printf '%s' "$PC_HERE/maat_msg.py"); export MAAT_MSG_PY
  # 1.8.0 (D1-bis): the relation of the test names (shared with counterproof.sh): NOMI_TEST_PY if set, otherwise
  # nomi_test.py next to THIS script, otherwise the plugin's (a copy of plan-check.sh alone, in the tests)
  if [ -z "${NOMI_TEST_PY:-}" ]; then
    NOMI_TEST_PY=$PC_HERE/nomi_test.py; [ -f "$NOMI_TEST_PY" ] || NOMI_TEST_PY=$MAAT_SCRIPTS/nomi_test.py
    NOMI_TEST_PY=$(maat_cygm "$NOMI_TEST_PY" 2>/dev/null || printf '%s' "$NOMI_TEST_PY")
  fi
  export NOMI_TEST_PY
  export MAAT_CONFIG_PY="${MAAT_CONFIG_PY:-$MAAT_SCRIPTS/maat-config.py}"   # the Python imports the single reader (conf)
  [ -n "${FIC_PY:-}" ] && return 0
  . "$MAAT_SCRIPTS/python.sh" && [ -n "${FIC_PY:-}" ] && return 0
  echo "plan-check: $(msg plan-check.no_python)" >&2; return 2
}
repo_root() {
  if [ -n "${PLAN_CHECK_ROOT:-}" ]; then printf '%s\n' "$PLAN_CHECK_ROOT"; return; fi
  git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null || pwd
}
has_plan_section() { printf '%s\n' "$1" | awk -F'\t' '$2 != "above" { f = 1 } END { exit !f }'; }

cmd_lint2() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local ann; ann=$(annotate "$1")
  has_plan_section "$ann" || { echo "VIOLAZIONE: $(msg plan-check.no_plan)"; return 1; }
  need_py || return 2
  printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" lint2 "$(repo_root "$1")"
}

cmd_gen() {
  local spec="" run=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-dir) [ $# -ge 2 ] || die_usage; run="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  [ -n "$run" ] || run="${spec%.md}.run"
  local ann fp; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "VIOLAZIONE: $(msg plan-check.no_plan)"; return 1; }
  need_py || return 2
  fp=$(basis_of "$ann" | sed -n 's/.*plan \([0-9a-f]*\).*/\1/p')
  printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" gen "$(repo_root "$spec")" "$run" "$fp"
}

# test-red phase (harness-pt11), format 2 only (format 1: "non si applica", exit 2):
#   accept <spec>                          scope of the phase: "test <path>" (test file of the plan), "nuovo <path>"
#   tests  <spec>                          lines of the acceptance test fingerprint ("<sha256>  <path>")
#   stubs  <spec> [--run-dir <d>]          stub symbols of the new files -> <d>/test-red/stubs.json
#   rossi  <spec> --evidence <ev> [--run-dir <d>]   verification of the reds on the stubbed base, from the evidence of
#          gates.sh (tests-be JUnit, tests-fe reporter output): every test red on its assertion (backticked texts
#          of the asserzione column, otherwise the rosso_se of the mutation), import/collection = not
#          proven, green = STOP, existing suite red or test asserting the absence of a value added by the
#          plan = conflict. Writes <d>/test-red/rossi.json. Exit 0 OK · 1 STOP · 3 BLOCKED.
#   l2     <spec> [--run-dir <d>]          for finalize.sh: "L2 <id>: OK | NO — <motivo>" of the mutations on new
#          files, on the current code (stub = exported symbols, every symbol in a test, tests fingerprint FRESH)
cmd_f2x() {
  local sub=$1 spec="" run="" ev=""; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-dir) [ $# -ge 2 ] || die_usage; run="$2"; shift 2 ;;
      --evidence) [ "$sub" = rossi ] && [ $# -ge 2 ] || die_usage; ev="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  [ "$sub" != rossi ] || [ -n "$ev" ] || die_usage
  [ -n "$run" ] || run="${spec%.md}.run"
  local ann root ts; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "VIOLAZIONE: $(msg plan-check.no_plan)"; return 1; }
  need_py || return 2
  root=$(repo_root "$spec")
  case $sub in
    accept|tests) printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" "$sub" "$root" ;;
    stubs) printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" stubs "$root" "$run" ;;
    rossi) printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" rossi "$root" "$run" "$ev" ;;
    l2)
      ts=$(cmd_basis "$spec" | sed -n 's/^Tests status: //p')
      printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" l2 "$root" "$run" "${ts:-ASSENTE}" ;;
  esac
}

cmd_route() {
  local spec="" diff=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --diff) [ $# -ge 2 ] && [ -f "$2" ] || die_usage; diff="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  local ann; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "$(msg plan-check.no_plan)"; return 1; }
  need_py || return 2
  if [ -n "$diff" ]; then printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" route "$(repo_root "$spec")" "$diff"
  else printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" route "$(repo_root "$spec")"; fi
}

# S2 · delta ∥ fresh eyes. Each response is a file: first line "Impronta piano: <fp12>" (the "plan" value
# of `basis` at launch, written by the orchestrator), then the reviewer contract (Decision:, Severity: …).
# APPROVA only if both are on the current fingerprint and clean: no blocker/major, NOT EVEN a rejected one.
review_info() {   # <file> → "<impronta|-> <decisione|-> <n. blocker/major> <parziale 0|1>"
  local t fp d nb p=0
  t=$(tr -d '\r' < "$1")
  fp=$(printf '%s\n' "$t" | sed -n 's/^Impronta piano:[[:space:]]*\([0-9a-f]\{12\}\).*/\1/p' | head -1)
  d=$(printf '%s\n' "$t" | sed -n 's/^Decision:[[:space:]]*\([A-Z_]*\).*/\1/p' | head -1)
  nb=$(printf '%s\n' "$t" | grep -cE '^[[:space:]]*([0-9]+\.[[:space:]]*)?Severity:[[:space:]]*(blocker|major)' || true)
  # partial only if the "Blocked on:" line gives a reason: "none" / "nessuno" is not a block
  printf '%s\n' "$t" | grep -E 'Blocked on:' | grep -qviE 'Blocked on:[[:space:]]*(none|nessuno)[[:space:].]*$' && p=1
  echo "${fp:--} ${d:--} ${nb:-0} $p"
}
cmd_s2() {
  local spec="" fd="" fg="" nr=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --delta) [ $# -ge 2 ] || die_usage; fd="$2"; shift 2 ;;
      --gate) [ $# -ge 2 ] || die_usage; fg="$2"; shift 2 ;;
      --respinti) [ $# -ge 2 ] || die_usage; nr="$2"; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] && [ -f "$fd" ] && [ -f "$fg" ] || die_usage
  case "$nr" in ''|*[!0-9]*) die_usage ;; esac
  local ann cur; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "$(msg plan-check.no_plan)"; return 1; }
  cur=$(basis_of "$ann" | sed -n 's/.*plan \([0-9a-f]*\).*/\1/p')
  local dfp dd dnb dp gfp gd gnb gp
  read -r dfp dd dnb dp <<< "$(review_info "$fd")"
  read -r gfp gd gnb gp <<< "$(review_info "$fg")"
  local tot=$((dnb + gnb))
  [ "$nr" -le "$tot" ] || { echo "$(msg plan-check.s2_rejected_over nr="$nr" tot="$tot")" >&2; return 2; }
  case "$dd $gd" in *STOP_HUMAN*) echo "S2: STOP — $(msg plan-check.s2_stop dd="$dd" gd="$gd")"; return 0 ;; esac
  if [ "$dfp" != "$cur" ] || [ "$gfp" != "$cur" ]; then
    echo "S2: IMPRONTA DIVERSA — $(msg plan-check.s2_fp dfp="$dfp" gfp="$gfp" cur="$cur")"; return 0
  fi
  if [ "$dp" = 1 ] || [ "$gp" = 1 ]; then echo "S2: RILANCIA — $(msg plan-check.s2_partial)"; return 0; fi
  if [ $((tot - nr)) -gt 0 ]; then echo "S2: CORREGGI — $(msg plan-check.s2_fix n="$((tot - nr))" dnb="$dnb" gnb="$gnb" nr="$nr")"; return 0; fi
  [ "$nr" -gt 0 ] && { echo "S2: RILANCIA — $(msg plan-check.s2_rejected nr="$nr")"; return 0; }  # REGOLA-RESPINTI
  if { [ "$dnb" -eq 0 ] && [ "$dd" != APPROVED ]; } || { [ "$gnb" -eq 0 ] && [ "$gd" != APPROVED ]; }; then
    echo "S2: RILANCIA — $(msg plan-check.s2_not_approved dd="$dd" gd="$gd")"; return 0
  fi
  echo "S2: APPROVA — $(msg plan-check.s2_ok cur="$cur")"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────── size of the cycle (1.7.0)
# taglia: the facts and the size (header of this file). Always exit 0 with a last line "Taglia: …": what cannot be
# measured (no plan, no Python) is piena, said in the line.
cmd_taglia() {
  local spec="" diff="" ovr="" touched=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --diff) [ $# -ge 2 ] || die_usage; diff="$2"; shift 2 ;;
      --touched) [ $# -ge 2 ] || die_usage; touched="$2"; shift 2 ;;
      --override) [ $# -ge 2 ] || die_usage; case $2 in full|light) ovr="$2" ;; *) die_usage ;; esac; shift 2 ;;
      -*) die_usage ;;
      *) [ -z "$spec" ] || die_usage; spec="$1"; shift ;;
    esac
  done
  [ -n "$spec" ] && [ -f "$spec" ] || die_usage
  local ann; ann=$(annotate "$spec")
  has_plan_section "$ann" || { echo "Taglia: piena — $(msg plan-check-170.no_plan)"; return 0; }
  need_py 2>/dev/null || { echo "Taglia: piena — $(msg plan-check-170.no_python)"; return 0; }
  printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" taglia "$(repo_root "$spec")" "${diff:--}" "${ovr:--}" "${touched:--}"
}
# e1 <reply>: the ONE round of spec-plan-reviewer-light of the small size (D3-A, D4). Counted on the reply as it is,
# rejected findings included: the plan author cannot stay small by rejecting.
E1_MAJOR=2
cmd_e1() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local t d nb nm p=0
  t=$(tr -d '\r' < "$1")
  d=$(printf '%s\n' "$t" | sed -n 's/^[[:space:]*]*Decision:[[:space:]*]*\([A-Z_]*\).*/\1/p' | head -1)
  # anywhere on the line, any markdown around it (1.7.0 review: «1. **Severity:** major», «- Severity: major»,
  # «### 1. Severity: major»)
  nb=$(printf '%s\n' "$t" | grep -ciE 'Severity[*]*:[*[:space:]]*blocker' || true)  # SEVERITA-OVUNQUE
  nm=$(printf '%s\n' "$t" | grep -ciE 'Severity[*]*:[*[:space:]]*major' || true)
  printf '%s\n' "$t" | grep -E 'Blocked on:' | grep -qviE 'Blocked on:[[:space:]]*(none|nessuno)[[:space:].]*$' && p=1
  case $d in STOP_HUMAN*) echo "E1: STOP — $(msg plan-check-170.e1_stop)"; return 0 ;; esac
  if [ -z "$d" ]; then echo "E1: piena — $(msg plan-check-170.e1_no_decision)"; return 0; fi
  if [ "$p" = 1 ]; then echo "E1: piena — $(msg plan-check-170.e1_partial)"; return 0; fi
  if [ "${nb:-0}" -gt 0 ] || [ "${nm:-0}" -gt "$E1_MAJOR" ]; then  # SOGLIA-E1
    echo "E1: piena — $(msg plan-check-170.e1_over nb="${nb:-0}" nm="${nm:-0}")"; return 0
  fi
  # NEEDS_CHANGES with no blocker or major counted: the reply and the count disagree → fail-closed
  if [ "$d" = NEEDS_CHANGES ] && [ "${nb:-0}" -eq 0 ] && [ "${nm:-0}" -eq 0 ]; then  # E1-INCOERENTE
    echo "E1: piena — $(msg plan-check-170.e1_inconsistent)"; return 0
  fi
  echo "E1: piccola — $(msg plan-check-170.e1_ok nb="${nb:-0}" nm="${nm:-0}")"
}

# ─────────────────────────────────────────────────────────────────────────── skeleton, split (harness-pt12)
cmd_skeleton() {
  [ $# -eq 1 ] && [ -f "$1" ] || die_usage
  local ann; ann=$(annotate "$1")
  has_plan_section "$ann" || { echo "VIOLAZIONE: $(msg plan-check.no_plan)"; return 1; }
  need_py || return 2
  printf '%s\n' "$ann" | "$FIC_PY" "$TMPD/plan_check_f2.py" skeleton "$(repo_root "$1")"
}

cmd_split() {
  [ $# -ge 1 ] && [ -f "$1" ] || die_usage
  local madre=$1 d rc=0 id who n f lit; shift
  local kids=("$@")
  d=$(dirname "$madre")
  if [ ${#kids[@]} -eq 0 ]; then
    while IFS= read -r n; do [ -n "$n" ] && kids+=("$d/$n.md"); done < <(figlie_of "$madre")
  fi
  sviol() { echo "VIOLAZIONE: $*"; rc=1; }
  # both forms of the children line (1.3.0): the first one is read, but the mother is ambiguous
  if [ -n "$(head_val "$madre" "Figlie:")" ] && [ -n "$(head_val "$madre" "Children:")" ]; then
    sviol "$(msg plan-check.split_both)"
  fi
  [ ${#kids[@]} -ge 2 ] || { sviol "$(msg plan-check.split_few)"; return 1; }
  for f in "${kids[@]}"; do [ -f "$f" ] || { sviol "$(msg plan-check.split_kid_missing f="$f")"; return 1; }; done
  n=$(for f in "${kids[@]}"; do basename "$f" .md; done | LC_ALL=C sort | uniq -d | tr '\n' ' ' | sed 's/ $//')
  [ -z "$n" ] || { sviol "$(msg plan-check.split_kid_dup n="$n")"; return 1; }
  req_ids "$madre" > "$TMPD/split.madre"
  if [ ! -s "$TMPD/split.madre" ]; then
    sviol "$(msg plan-check.split_no_ids)"; return 1
  fi
  : > "$TMPD/split.figlie"
  for f in "${kids[@]}"; do
    req_ids "$f" | awk -v k="$(basename "$f" .md)" '{ print $0 "\t" k }' >> "$TMPD/split.figlie"
  done
  # CONTROLLO-PARTIZIONE: every ID of the parent in one and only one child (lost or duplicated = STOP)
  while IFS= read -r id; do
    who=$(awk -F'\t' -v i="$id" '$1 == i { print $2 }' "$TMPD/split.figlie" | LC_ALL=C sort -u)
    n=$(printf '%s' "$who" | grep -c . || true)
    if [ "$n" -eq 0 ]; then sviol "$(msg plan-check.split_lost id="$id")"
    elif [ "$n" -gt 1 ]; then sviol "$(msg plan-check.split_twice id="$id" n="$n" who="$(printf '%s' "$who" | tr '\n' ' ' | sed 's/ $//')")"; fi
  done < "$TMPD/split.madre"
  # the children add no requirements: each of their IDs belongs to the parent
  while IFS=$'\t' read -r id who; do
    grep -qxF -- "$id" "$TMPD/split.madre" || sviol "$(msg plan-check.split_foreign who="$who" id="$id")"
  done < "$TMPD/split.figlie"
  for f in "${kids[@]}"; do
    for lit in "Dipende da:" "Interfaccia per:"; do
      [ -n "$(head_val "$f" "$lit" "$([ "$lit" = "Dipende da:" ] && echo "Depends on:" || echo "Interface for:")")" ] || sviol "$(msg plan-check.split_no_line spec="$(basename "$f" .md)" lit="$lit")"
    done
  done
  [ $rc -eq 0 ] && echo "split: OK — $(msg plan-check.split_ok n="$(grep -c . "$TMPD/split.madre")" k="${#kids[@]}")"
  return $rc
}

PC_HERE=$(cd "$(dirname "$0")" && pwd)
. "$PC_HERE/lib/maat-paths.sh" || exit 4   # MAAT_SCRIPTS (plugin)
# Messages (1.4.0): the catalog next to this script; the language is resolved once and exported (PY2 and the
# children read the same one). The stdout of basis and contract does not go through it: it enters State.
. "$PC_HERE/lib/maat-msg.sh"; maat_msg_carica
maat_lingua -v MAAT_LINGUA; export MAAT_LINGUA
# relative MAAT_CONFIG (to the working directory, even with spaces) made absolute HERE, in bash, like run-phase.sh: the
# gen cmd/cp lines run after a cd or inside WSL, and os.path.abspath of Windows Python on a /c/… would give C:\c\….
# C:/… form where cygpath exists (maat_cygm), otherwise that of `pwd`.
if [ -n "${MAAT_CONFIG:-}" ]; then
  case $MAAT_CONFIG in
    /*|[A-Za-z]:[/\\]*) ;;
    *) # Windows form even without cygpath (pwd -W); folder not reachable -> relative to the current folder
       if _d=$(cd "$(dirname "$MAAT_CONFIG")" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); then
         MAAT_CONFIG=$_d/$(basename "$MAAT_CONFIG")
       else MAAT_CONFIG=$PWD/$MAAT_CONFIG; fi; unset _d ;;
  esac
  MAAT_CONFIG=$(maat_cygm "$MAAT_CONFIG" 2>/dev/null || printf '%s' "$MAAT_CONFIG"); export MAAT_CONFIG
fi
TMPD=$(mktemp -d) || exit 2
trap 'rm -rf "$TMPD"' EXIT

[ $# -ge 1 ] || die_usage
sub="$1"; shift
case "$sub" in
  delta) cmd_delta "$@" ;;
  lint) cmd_lint "$@" ;;
  contract) cmd_contract "$@" ;;
  basis) cmd_basis "$@" ;;
  lint2) cmd_lint2 "$@" ;;
  gen) cmd_gen "$@" ;;
  route) cmd_route "$@" ;;
  s2) cmd_s2 "$@" ;;
  skeleton) cmd_skeleton "$@" ;;
  split) cmd_split "$@" ;;
  closed) cmd_closed "$@" ;;
  taglia) cmd_taglia "$@" ;;
  e1) cmd_e1 "$@" ;;
  accept|tests|stubs|rossi|l2) cmd_f2x "$sub" "$@" ;;
  *) die_usage ;;
esac
exit $?
