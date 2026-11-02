#!/usr/bin/env bash
# costruisci.sh — builds the public equivalence corpus of the driver (Maat 1.5.0) from the models next to this script.
#   bash tools/esempi-equiv/costruisci.sh <folder> [<mini-repo>…]
# <folder> must not exist or be empty. Without <mini-repo> every one in the order of MINI_REPO below. Prints one line
# per mini-repo, then «esempi-equiv: <r> mini-repo · spec=<s> · jsonl=<j>» and, last, «impronta <64 hex>»: the
# fingerprint of `driver.py equiv --impronta` on the .claude/.ai-workflow folders of the mini-repos built, in that order.
# Exit 0 · 1 a step failed (git, a script of the plugin) · 2 usage, a model with a placeholder outside the list below,
# or a «{{» left after the build.
#
# A mini-repo <m> is tools/esempi-equiv/<m>/:
#   stati/<n>/   the code trees, in successive states (full trees, .gitignore included). stati/0 is the base commit;
#                every later state is laid over the working tree and written with `review-surface.sh tree` (the objects
#                exist, the trees are not committed); the last state stays as the working tree.
#   modelli/     the content of the mini-repo's .claude/ (specs and run dirs under .ai-workflow/): data, copied as is,
#                then the placeholders are filled. Every spec gets its run dir, empty if the models have none (equiv
#                sees only the specs with a run dir).
# casi.tsv (next to this script) declares the expected word of every spec and the branches of every jsonl; the builder
# reads from it only the options: «harness-fixture» (the harness.fp of that spec is a fixture: listed in
# .claude/oracolo-conserva) and «mtime=<UTC>» (the mtime of that file instead of the fixed epoch).
#
# PLACEHOLDERS — the closed list (anything else after «{{» is an error, exit 2). Filled in this order:
#   {{review:<Review status>|<Feature status>[|<line>[|<line>]]}}   a whole line: the Italian review section printed by
#        `review` (lib/fixture-cicli.sh), the extra lines (e.g. a Reviewed snapshot line) as its 3rd and 4th arguments
#   {{rjson:<phase>|<esito>|<deviazioni as JSON>|<bloccato_su>}}   the whole content of a log/<label>.result.json:
#        replaced by the file `rjson` (lib/fixture-cicli.sh) writes for that label
#   {{base}} {{base12}}            sha of the base commit (stati/0), 40 or 12 digits
#   {{tree:<n>}} {{tree12:<n>}}    sha of the tree of stati/<n>, 40 or 12 digits
#   {{snapshot:<n>}}               the value of a «Reviewed snapshot:» line on stati/<n>: «base <b12> · tree <t12> ·
#        fingerprint <fp> · <k> paths», fingerprint of `review-surface.sh fingerprint` on the Scope: of the spec
#   {{finalize}}                   the 12 digits finalize.sh signs: the fingerprint of the spec's current Reviewed
#        snapshot (the formula of snap_fp in cycle-state.sh)
#   Approved basis: {{basis}}      a whole line, right after «Superfici a rischio:» (Italian specs: `with_basis` of the
#        library) or «Risk surfaces:» (English specs: the same two lines with the English key)
#   {{basis-spec}} {{basis-plan}}  the two fingerprints of the current Basis (plan-check.sh basis): for the lines that
#        record a contract (Reviewed contract:) or a basis made STALE on purpose
#   {{state}}                      the State of the spec of that run dir (cycle-state.sh, FIC_DRIVER=0), last
# The mtimes count from the basis on (plan-check.sh closed reads the time of the last review): every file under
# .claude/ gets EPOCA (or its mtime= option) before the basis, before the states and at the end. Last,
# .claude/oracolo-conserva and .claude/esempi-equiv.sorgente (sha256 of the models and of stati/ of that mini-repo).
#
# DETERMINISM (constraint 3 of the 1.5.0 plan): no git configuration of the machine (GIT_CONFIG_GLOBAL=/dev/null,
# GIT_CONFIG_NOSYSTEM=1, an empty XDG_CONFIG_HOME), fixed identity and dates for the base commit, core.autocrlf=false,
# core.filemode=false, commit.gpgsign=false, chmod 644 on every file before the commit. The same models give the same
# fingerprint on Windows (Git Bash) and on Linux.
# MAAT_ESEMPI_PLUGIN: the plugin whose scripts compute the placeholders (default: plugins/maat of this repo).
set -uo pipefail
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "${MAAT_ESEMPI_PLUGIN:-$HERE/../../plugins/maat}" 2>/dev/null && pwd) || { echo "costruisci.sh: plugin not found" >&2; exit 2; }
SCR=$PLUGIN/scripts
MINI_REPO="progetto-singoli progetto-storico progetto-catene-chiuse progetto-catena-codice-cambiato progetto-catena-aperta progetto-catena-albero-cambiato progetto-impronta-nc"
EPOCA=2026-01-01T00:00:00Z            # mtime of every file of .claude/ (casi.tsv may declare another one)
DATA_COMMIT=2026-01-01T00:00:00Z      # author and committer date of the base commit

usage() { echo "usage: bash tools/esempi-equiv/costruisci.sh <folder> [<mini-repo>…]   (mini-repo: $MINI_REPO)" >&2; exit 2; }
die() { echo "costruisci.sh: $1" >&2; exit "${2:-1}"; }
[ $# -ge 1 ] || usage
OUT=$1; shift
SCELTI=${*:-$MINI_REPO}
for m in $SCELTI; do case " $MINI_REPO " in *" $m "*) [ -d "$HERE/$m" ] || die "mini-repo $m: no models in $HERE/$m" 2 ;; *) usage ;; esac; done
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then die "$OUT exists and is not empty" 2; fi
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd) || die "cannot create $OUT"

# no configuration of the machine: the same environment as _impronta_corpus of driver.py
VUOTA=$(mktemp -d) || die "mktemp"
trap 'rm -rf "$VUOTA"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG GIT_CONFIG_PARAMETERS
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME=$VUOTA
export GIT_AUTHOR_NAME="Maat esempi" GIT_AUTHOR_EMAIL=esempi@example.invalid
export GIT_COMMITTER_NAME="Maat esempi" GIT_COMMITTER_EMAIL=esempi@example.invalid
export GIT_AUTHOR_DATE=$DATA_COMMIT GIT_COMMITTER_DATE=$DATA_COMMIT   # DATE-FISSE
export MAAT_LINGUA=it FIC_DRIVER=0   # State does not depend on the language; the standalone table, never the driver
unset FIC_REPO MAAT_ROOT FIC_DRIVER_ROOT
FIC_PY=""; . "$SCR/python.sh" >/dev/null 2>&1
[ -n "$FIC_PY" ] || die "no Python (python.sh)"
PC=$SCR/plan-check.sh
RS=$SCR/review-surface.sh
CS=$SCR/cycle-state.sh
. "$SCR/lib/fixture-cicli.sh" || die "lib/fixture-cicli.sh"
EPOCA_S=$(date -u -d "$EPOCA" +%s)
CASI=$HERE/casi.tsv
[ -f "$CASI" ] || die "casi.tsv missing" 2

# placeholders: the closed list (the line directive review and the file directive rjson are unwrapped first). Only «{{»
# is looked for: «}}» is ordinary JSON in the jsonl models.
SEGNAPOSTO='\{\{(base|base12|tree:[0-9]+|tree12:[0-9]+|snapshot:[0-9]+|finalize|basis|basis-spec|basis-plan|state)\}\}'
controlla_modelli() { # $1 models dir → exit 2 on a placeholder outside the list
  local f l resto
  while IFS= read -r f; do
    while IFS= read -r l || [ -n "$l" ]; do
      case "$l" in "{{review:"*"}}") l=${l#"{{review:"}; l=${l%"}}"} ;; "{{rjson:"*"}}") l=${l#"{{rjson:"}; l=${l%"}}"} ;; esac
      resto=$(printf '%s\n' "$l" | sed -E "s/$SEGNAPOSTO//g")
      case "$resto" in *"{{"*) die "${f#"$1/"}: placeholder outside the list: $(printf '%s\n' "$resto" | grep -o '{{[^}]*}*' | head -1)" 2 ;; esac
    done < <(tr -d '\r' < "$f")
  done < <(find "$1" -type f | sort)
}
# the review section of a spec, outside the fences (as cycle-state.sh reads it)
sezione_review() { tr -d '\r' < "$1" | awk '{ isf = ($0 ~ /^[ \t]*(```|~~~)/) } isf { inf = !inf; next } inf { next }
  !r && /^## (Review implementazione|Implementation review)/ { r = 1 } r { print }'; }
scope_di() { sezione_review "$1" | awk '$0 == "Scope:" { on = 1; next } on && (/^[ \t]*$/ || /^Excluded:/ || /^Scope:/ || /^<\/details>/) { exit } on { print }'; }
# snap_fp of cycle-state.sh: the fingerprint finalize.sh writes in «snapshot <x12>». A copy of that formula: the
# «snap_fp» case of tools/esempi-equiv.test.sh checks that the two give the same result
snap_fp() { printf '%s' "$1" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//' | tr -d '\n' | sha256sum | cut -c1-12; }
sostituisci() { # $1 file, then pairs <literal> <value>: every occurrence (values: hex digits, spaces and «·»)
  local f=$1 e=(); shift
  while [ $# -ge 2 ]; do e+=(-e "s|$1|$2|g"); shift 2; done
  sed -i "${e[@]}" "$f" || die "cannot write $f"
}
fissa_mtime() { # $1 repo, $2 mini-repo name: the fixed epoch on .claude/, then the declared exceptions
  local r=$1 m=$2 tipo mr nome par et opz t
  find "$r/.claude" -exec touch -d "@$EPOCA_S" {} + || die "touch"
  while IFS=$'\t' read -r tipo mr nome par et opz; do
    [ "$mr" = "$m" ] || continue
    t=$(printf '%s\n' "${opz:-}" | tr ',' '\n' | sed -n 's/^mtime=//p')
    [ -n "$t" ] || continue
    [ -e "$r/.claude/.ai-workflow/$nome" ] || die "casi.tsv: $m/$nome does not exist" 2
    touch -d "$t" "$r/.claude/.ai-workflow/$nome" || die "touch $nome"
  done < <(tr -d '\r' < "$CASI" | grep -v '^#' | grep .)
}

nspec=0 njsonl=0
TARGETS=()
for m in $SCELTI; do
  M=$HERE/$m
  R=$OUT/$m
  [ -d "$M/stati/0" ] && [ -d "$M/modelli/.ai-workflow" ] || die "$m: stati/0 or modelli/.ai-workflow missing" 2
  controlla_modelli "$M/modelli"
  mkdir -p "$R" && cd "$R" || die "cd $R"
  git init -q -b main . || die "git init"
  git config core.autocrlf false; git config core.filemode false; git config commit.gpgsign false
  git config user.name "$GIT_AUTHOR_NAME"; git config user.email "$GIT_AUTHOR_EMAIL"
  # --- 1. the states of the code: stati/0 committed, the others written as trees, the last one stays ---
  unset TREE; declare -A TREE=()
  for n in $(ls "$M/stati" | grep -E '^[0-9]+$' | sort -n); do
    find . -mindepth 1 -maxdepth 1 ! -name .git ! -name .claude -exec rm -rf {} +
    cp -r "$M/stati/$n/." . || die "$m: copy of stati/$n"
    find . -path ./.git -prune -o -type f -exec chmod 644 {} +
    if [ "$n" = 0 ]; then
      git add -A && git commit -q -m "base" || die "$m: base commit"
      BASE=$(git rev-parse HEAD); TREE[0]=$(git rev-parse 'HEAD^{tree}')
    else
      TREE[$n]=$(bash "$RS" tree) || die "$m: review-surface.sh tree on stati/$n"
    fi
  done
  # --- 2. the models, then the directives of the library (review, rjson) ---
  mkdir -p .claude && cp -r "$M/modelli/." .claude/ || die "$m: copy of the models"
  for s in .claude/.ai-workflow/spec-*.md; do mkdir -p "${s%.md}.run"; done
  while IFS= read -r f; do
    grep -q '^{{review:.*}}$' "$f" || continue
    : > "$f.nuovo"
    while IFS= read -r l || [ -n "$l" ]; do
      case "$l" in
        "{{review:"*"}}") a=${l#"{{review:"}; a=${a%"}}"}; IFS='|' read -r -a ra <<< "$a"
          review "${ra[@]}" >> "$f.nuovo" || die "$m: review directive in $f" ;;
        *) printf '%s\n' "$l" >> "$f.nuovo" ;;
      esac
    done < <(tr -d '\r' < "$f")
    mv "$f.nuovo" "$f"
  done < <(find .claude -type f -name 'spec-*.md' | sort)
  while IFS= read -r f; do
    l=$(tr -d '\r\n' < "$f")
    case "$l" in "{{rjson:"*"}}") ;; *) continue ;; esac
    case "$f" in */log/*.result.json) ;; *) die "$m: rjson outside a log/<label>.result.json: $f" 2 ;; esac
    a=${l#"{{rjson:"}; a=${a%"}}"}; IFS='|' read -r a1 a2 a3 a4 <<< "$a"
    RUN=${f%/log/*}; lab=$(basename "$f" .result.json)
    rjson "$lab" "$a1" "$a2" "$a3" "$a4" || die "$m: rjson $f"
  done < <(find .claude -type f -name '*.result.json' | sort)
  # --- 3. commit and trees ---
  while IFS= read -r f; do
    sostituisci "$f" "{{base}}" "$BASE" "{{base12}}" "${BASE:0:12}"
    for n in $(grep -oE '\{\{tree(12)?:[0-9]+\}\}' "$f" | sed -E 's/.*:([0-9]+)\}\}/\1/' | sort -u); do
      [ -n "${TREE[$n]:-}" ] || die "$m: $f names stati/$n, which does not exist" 2
      sostituisci "$f" "{{tree:$n}}" "${TREE[$n]}" "{{tree12:$n}}" "${TREE[$n]:0:12}"
    done
  done < <(grep -rlE '\{\{(base|base12|tree:[0-9]+|tree12:[0-9]+)\}\}' .claude | sort)
  # --- 4. snapshot, then Finalize (on the snapshot just written) ---
  for s in .claude/.ai-workflow/spec-*.md; do
    for n in $(grep -oE '\{\{snapshot:[0-9]+\}\}' "$s" | sed -E 's/.*:([0-9]+)\}\}/\1/' | sort -u); do
      [ -n "${TREE[$n]:-}" ] || die "$m: $s names stati/$n, which does not exist" 2
      scope_di "$s" > "$VUOTA/scope"
      [ -s "$VUOTA/scope" ] || die "$m: $s: {{snapshot:$n}} without a Scope:" 2
      fp=$(bash "$RS" fingerprint --tree "${TREE[$n]}" --paths-file "$VUOTA/scope" | sed -n 's/^Fingerprint: //p')
      [ -n "$fp" ] || die "$m: fingerprint of $s"
      sostituisci "$s" "{{snapshot:$n}}" "base ${BASE:0:12} · tree ${TREE[$n]:0:12} · fingerprint $fp · $(grep -c . "$VUOTA/scope") paths"
    done
    if grep -q '{{finalize}}' "$s"; then
      sostituisci "$s" "{{finalize}}" "$(snap_fp "$(sezione_review "$s" | sed -n 's/^Reviewed snapshot:[[:space:]]*//p' | head -1)")"
    fi
  done
  fissa_mtime "$R" "$m"
  # --- 5. Approved basis (with_basis of the library), then the fingerprints of the Basis ---
  for SP in .claude/.ai-workflow/spec-*.md; do
    if grep -qx 'Approved basis: {{basis}}' "$SP"; then
      prev=$(tr -d '\r' < "$SP" | grep -B1 -x 'Approved basis: {{basis}}' | head -1)
      sed -i '/^Approved basis: {{basis}}$/d' "$SP"
      case "$prev" in
        "Superfici a rischio: "*) with_basis ;;
        "Risk surfaces: "*) cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
          sed -i "s/^Risk surfaces: .*/&\nApproved basis: $cur/" "$SP" ;;
        *) die "$m: $SP: «Approved basis: {{basis}}» not right after «Superfici a rischio:» or «Risk surfaces:»" 2 ;;
      esac
      grep -q '^Approved basis: spec [0-9a-f]\{12\} · plan [0-9a-f]\{12\}' "$SP" || die "$m: $SP: Approved basis not written"
    fi
    if grep -qE '\{\{basis-(spec|plan)\}\}' "$SP"; then
      cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
      bs=$(printf '%s\n' "$cur" | sed -n 's/^spec \([0-9a-f]\{12\}\) · plan \([0-9a-f]\{12\}\).*/\1/p')
      bp=$(printf '%s\n' "$cur" | sed -n 's/^spec \([0-9a-f]\{12\}\) · plan \([0-9a-f]\{12\}\).*/\2/p')
      [ -n "$bs" ] && [ -n "$bp" ] || die "$m: $SP: no Basis to fill {{basis-spec}}/{{basis-plan}}"
      sostituisci "$SP" "{{basis-spec}}" "$bs" "{{basis-plan}}" "$bp"
    fi
  done
  fissa_mtime "$R" "$m"
  # --- 6. state= : the State of the spec, now final (cycle-state.sh, the standalone table) ---
  for s in .claude/.ai-workflow/spec-*.md; do
    run=${s%.md}.run
    grep -rlF '{{state}}' "$run" >/dev/null 2>&1 || continue
    st=$(bash "$CS" "$s" 2>/dev/null | tr -d '\r' | sed -n 's/^State: //p')
    [ -n "$st" ] || die "$m: no State for $s"
    while IFS= read -r f; do sostituisci "$f" "{{state}}" "$st"; done < <(grep -rlF '{{state}}' "$run" | sort)
  done
  # --- 7. nothing left, the two files of the corpus, the mtimes ---
  rimasti=$(grep -rlF '{{' .claude 2>/dev/null)
  [ -z "$rimasti" ] || die "$m: placeholders left in: $(printf '%s ' $rimasti)" 2
  tr -d '\r' < "$CASI" | grep -v '^#' | awk -F'\t' -v m="$m" '$1 == "spec" && $2 == m && ("," $6 ",") ~ /,harness-fixture,/ {
    print ".claude/.ai-workflow/" $3 ".run/harness.fp" }' | sort > .claude/oracolo-conserva
  while IFS= read -r f; do [ -f "$f" ] || die "casi.tsv: harness-fixture $m/$f does not exist" 2; done < .claude/oracolo-conserva
  (cd "$M" && find modelli stati -type f | sort | while IFS= read -r f; do
     printf '%s %s/%s\n' "$(tr -d '\r' < "$f" | sha256sum | cut -c1-64)" "$m" "$f"; done) > .claude/esempi-equiv.sorgente
  fissa_mtime "$R" "$m"
  ns=$(ls .claude/.ai-workflow | grep -c '^spec-.*\.md$')
  # the jsonl that equiv counts: log/<n>-<label>.jsonl, no dot in the label, not of the phase chiusura (_phase_of of
  # driver.py: «chiusura» anywhere in the file name, never in the path above it)
  nj=$(find .claude/.ai-workflow -path '*.run/log/*' -type f -name '[0-9]*-*.jsonl' | grep -E '/log/[0-9]+-[^./]*\.jsonl$' |
    grep -cvE '/log/[0-9]+-[^./]*chiusura[^./]*\.jsonl$')
  nspec=$((nspec + ns)) njsonl=$((njsonl + nj))
  echo "esempi-equiv: $m · spec=$ns · jsonl=$nj"
  TARGETS+=("$R/.claude/.ai-workflow")
  cd "$OUT" || exit 1
done
imp=$("$FIC_PY" "$SCR/driver.py" equiv --impronta "${TARGETS[@]}" 2>/dev/null | tr -d '\r')
[[ $imp =~ ^[0-9a-f]{64}$ ]] || die "driver.py equiv --impronta: $imp"
echo "esempi-equiv: $(printf '%s\n' $SCELTI | grep -c .) mini-repo · spec=$nspec · jsonl=$njsonl"
echo "impronta $imp"
