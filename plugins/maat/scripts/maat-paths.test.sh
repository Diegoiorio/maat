#!/usr/bin/env bash
# maat-paths.test.sh — the two roots (pk04a-1): the harness finds itself (MAAT_ROOT, the plugin) and the project
# (PROJECT_ROOT, the working directory). Everything on synthetic repos and on COPIES of the plugin in folders with spaces; every
# counterproof runs on a MUTATED copy, never on the real plugin.
#
#   bash plugins/maat/scripts/maat-paths.test.sh
#
# Sections: 1 bash and Python resolver (spaces, subfolder, outside git exit 4, invalid MAAT_ROOT, MAAT_WORK
# from maat.json) · 2 project default in the scripts with an override (context-pack.sh, gates.sh, driver.py) ·
# 3 FIC_DRIVER_ROOT stays the harness root · 4 layout G (worktree-lib.sh finds fic-mirror.sh in scripts/) ·
# 5 lock in the repo's .git · 6 lock of the worktree, not of FIC_REPO (run-phase.sh --lock-status and ciclo-worktree.sh
# rimuovi, with the two counterproofs) · 7 mutual exclusion with the internal harness (lock with the same name) · 8 snapshot of
# MAAT_ROOT · 9 anti-layout search.
# The «internal» harness of section 7 is run-phase.sh of the faithful pk02 copy (commit $INTERNO_REF of this
# repo): the lock from the script location (git -C "$HERE").
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
INTERNO_REF=8143e8b
unset FIC_LOCK FIC_PHASE FIC_REPO MAAT_ROOT MAAT_CONFIG PROJECT_ROOT CONTEXT_PACK_ROOT CONTEXT_PACK_HARNESS \
      FIC_GATES_ROOT FIC_GATES_HARNESS FIC_DRIVER_ROOT FIC_DRIVER FIC_RUN_PHASE FIC_CONTEXT_PACK MSYS_NO_PATHCONV
T=$(mktemp -d) || exit 2
BG=""
cleanup() { [ -n "$BG" ] && kill "$BG" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export FIC_WT_WSL=0
. "$HERE/python.sh" || { echo "interprete Python non trovato" >&2; exit 2; }
fail=0 n=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${3:-}" ] && printf '%s\n' "$3" | head -20 | sed 's/^/    /'; fi; }
canon() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
newrepo() { # $1 folder → git repo with one commit; spec-* gitignored as in real projects
  mkdir -p "$1" && (cd "$1" && git init -q . && git config user.email t@t && git config user.name t &&
    git config core.autocrlf false && mkdir -p .claude/.ai-workflow && printf 'spec-*\n' > .claude/.ai-workflow/.gitignore &&
    printf 'x\n' > a.txt && git add -A && git commit -qm init)
}
copia() { mkdir -p "$(dirname "$2")" && cp -r "$1" "$2" && find "$2" -name __pycache__ -type d -prune -exec rm -rf {} +; }
snap() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }
muta() { # $1 file, $2 exact line to replace, $3 new line → 0 if applied (a single occurrence)
  local f=$1; [ "$(grep -cxF -- "$2" "$f")" = 1 ] || return 1
  "$FIC_PY" -c 'import sys
p, a, b = sys.argv[1:4]
t = open(p, encoding="utf-8", newline="").read()
open(p, "w", encoding="utf-8", newline="").write(t.replace(a + "\n", b + "\n", 1))' "$f" "$2" "$3"
}

P="$T/plugin con spazi/maat"; copia "$PLUGIN" "$P"
S0=$(snap "$P")
R="$T/progetto con spazi/repo"; newrepo "$R" >/dev/null 2>&1; mkdir -p "$R/sub/dir"
F="$T/fuori da git"; mkdir -p "$F"
CEIL=$(canon "$T")

# ---------------------------------------------------------------- 1. bash and Python resolver
ob=$(cd "$R" && bash "$P/scripts/lib/maat-paths.sh" 2>&1); rb=$?
check "bash: plugin e progetto in cartelle con spazi, giusti e diversi" \
  '[ $rb -eq 0 ] && [ "$(val "$ob" MAAT_ROOT)" = "$(canon "$P")" ] && [ "$(val "$ob" PROJECT_ROOT)" = "$(canon "$R")" ] && [ "$(val "$ob" MAAT_ROOT)" != "$(val "$ob" PROJECT_ROOT)" ]' "$ob"
check "  MAAT_SCRIPTS/SKILLS/AGENTS/SCHEMAS sotto il plugin, MAAT_WORK nel progetto (default .claude/.ai-workflow)" \
  '[ "$(val "$ob" MAAT_SCRIPTS)" = "$(canon "$P")/scripts" ] && [ "$(val "$ob" MAAT_SKILLS)" = "$(canon "$P")/skills" ] && [ "$(val "$ob" MAAT_AGENTS)" = "$(canon "$P")/agents" ] && [ "$(val "$ob" MAAT_SCHEMAS)" = "$(canon "$P")/schemas" ] && [ "$(val "$ob" MAAT_WORK)" = "$(canon "$R")/.claude/.ai-workflow" ]' "$ob"
os=$(cd "$R/sub/dir" && bash "$P/scripts/lib/maat-paths.sh" 2>&1); rs=$?
check "bash: da una sottocartella PROJECT_ROOT e' la radice del progetto" '[ $rs -eq 0 ] && [ "$(val "$os" PROJECT_ROOT)" = "$(canon "$R")" ]' "$os"
of=$(cd "$F" && GIT_CEILING_DIRECTORIES=$CEIL bash "$P/scripts/lib/maat-paths.sh" 2>&1); rf=$?
check "bash: fuori da un repo git → exit 4 con errore chiaro" '[ $rf -eq 4 ] && printf "%s" "$of" | grep -q "non e'"'"' in un repository git: PROJECT_ROOT non risolta"' "rc=$rf $of"
py() { local r; "$FIC_PY" "$P/scripts/maat_paths.py" > "$T/py.out"; r=$?; tr -d '\r' < "$T/py.out"; return $r; }   # Windows stdout: CRLF
pb=$(cd "$R" && py 2>&1); prb=$?
ps_=$(cd "$R/sub/dir" && py 2>&1); prs=$?
pf=$(cd "$F" && GIT_CEILING_DIRECTORIES=$CEIL py 2>&1); prf=$?
check "maat_paths.py: stessi valori del bash nel progetto e nella sottocartella" '[ $prb -eq 0 ] && [ "$pb" = "$ob" ] && [ $prs -eq 0 ] && [ "$ps_" = "$os" ]' "$(printf 'bash:\n%s\npython:\n%s' "$ob" "$pb")"
check "maat_paths.py: fuori da git exit 4 con lo stesso errore" '[ $prf -eq 4 ] && printf "%s" "$pf" | grep -q "non e'"'"' in un repository git: PROJECT_ROOT non risolta"' "rc=$prf $pf"
om=$(cd "$R" && MAAT_ROOT="$F" bash "$P/scripts/lib/maat-paths.sh" 2>&1); rm_=$?
pm=$(cd "$R" && MAAT_ROOT="$F" py 2>&1); prm=$?
check "MAAT_ROOT senza .claude-plugin/plugin.json → exit 4, bash e Python" '[ $rm_ -eq 4 ] && [ $prm -eq 4 ] && printf "%s" "$om" | grep -q "plugin.json" && printf "%s" "$pm" | grep -q "plugin.json"' "$om / $pm"
# 1.4.0 (Revisione 1 §9): the errors from the catalog next to the resolver in the current language; a copy without the
# catalog prints the Italian of 1.3.0 in every language
oe=$(cd "$F" && GIT_CEILING_DIRECTORIES=$CEIL MAAT_LINGUA=en bash "$P/scripts/lib/maat-paths.sh" 2>&1); re_=$?
pe=$(cd "$F" && GIT_CEILING_DIRECTORIES=$CEIL MAAT_LINGUA=en py 2>&1); pre=$?
EN_NOGIT="is not in a git repository: PROJECT_ROOT not resolved (run it from the folder of the project, or set FIC_REPO)"
check "en: fuori da git, bash e Python in inglese (exit 4), nessun italiano" '[ $re_ -eq 4 ] && [ $pre -eq 4 ] && printf "%s" "$oe" | grep -qF "$EN_NOGIT" && printf "%s" "$pe" | grep -qF "$EN_NOGIT" && ! printf "%s\n%s" "$oe" "$pe" | grep -qE "cartella|non e.|lancia"' "$oe / $pe"
oe=$(cd "$R" && MAAT_ROOT="$F" MAAT_LINGUA=en bash "$P/scripts/lib/maat-paths.sh" 2>&1); re_=$?
pe=$(cd "$R" && MAAT_ROOT="$F" MAAT_LINGUA=en py 2>&1); pre=$?
check "en: MAAT_ROOT non valida, il catalogo accanto al resolver, bash e Python in inglese" '[ $re_ -eq 4 ] && [ $pre -eq 4 ] && printf "%s" "$oe" | grep -q "is not the root of a maat plugin (.claude-plugin/plugin.json missing)" && printf "%s" "$pe" | grep -q "is not the root of a maat plugin" && ! printf "%s\n%s" "$oe" "$pe" | grep -q "non e"' "$oe / $pe"
PN="$T/senza catalogo/maat"; copia "$P" "$PN"; rm -f "$PN/scripts/lib/messages.tsv"
oe=$(cd "$F" && GIT_CEILING_DIRECTORIES=$CEIL MAAT_LINGUA=en bash "$PN/scripts/lib/maat-paths.sh" 2>&1); re_=$?
pe=$(cd "$F" && GIT_CEILING_DIRECTORIES=$CEIL MAAT_LINGUA=en "$FIC_PY" "$PN/scripts/maat_paths.py" 2>&1 | tr -d '\r'); pre=${PIPESTATUS[0]}
check "senza catalogo: l'italiano di 1.3.0 anche con MAAT_LINGUA=en, bash e Python" '[ $re_ -eq 4 ] && [ $pre -eq 4 ] && printf "%s" "$oe" | grep -q "non e'"'"' in un repository git: PROJECT_ROOT non risolta (lancia dalla cartella del progetto, o imposta FIC_REPO)" && printf "%s" "$pe" | grep -q "non e'"'"' in un repository git: PROJECT_ROOT non risolta (lancia dalla cartella del progetto, o imposta FIC_REPO)"' "$oe / $pe"
oe=$(cd "$R" && MAAT_ROOT="$F" MAAT_LINGUA=en bash "$PN/scripts/lib/maat-paths.sh" 2>&1); re_=$?
check "  e con MAAT_ROOT non valida" '[ $re_ -eq 4 ] && printf "%s" "$oe" | grep -q "non e'"'"' la radice di un plugin maat (manca .claude-plugin/plugin.json)"' "$oe"
rm -rf "$T/senza catalogo"
ov=$(cd "$R" && MAAT_ROOT="$P" FIC_REPO="$(canon "$R")" bash "$P/scripts/lib/maat-paths.sh" 2>&1)
check "MAAT_ROOT e FIC_REPO dall'ambiente vincono" '[ "$(val "$ov" MAAT_ROOT)" = "$P" ] && [ "$(val "$ov" PROJECT_ROOT)" = "$(canon "$R")" ]' "$ov"
RC="$T/progetto con spazi/configurato"; newrepo "$RC" >/dev/null 2>&1
printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}], "cartelle": {"lavoro": "lavoro/cicli"}}\n' > "$RC/.claude/maat.json"
oc=$(cd "$RC" && bash "$P/scripts/lib/maat-paths.sh" 2>&1); pc=$(cd "$RC" && py 2>&1)
check "MAAT_WORK da cartelle.lavoro di maat.json, bash e Python" '[ "$(val "$oc" MAAT_WORK)" = "$(canon "$RC")/lavoro/cicli" ] && [ "$pc" = "$oc" ]' "$oc / $pc"

# ---------------------------------------------------------------- 2. project default, not the harness's
SP="$R/.claude/.ai-workflow"
printf '# Prova\n\nRequisito: `a.txt`\n' > "$SP/spec-cp.md"; cp "$SP/spec-cp.md" "$SP/spec-cp2.md"
o=$(cd "$R/sub/dir" && bash "$P/scripts/context-pack.sh" .claude/.ai-workflow/spec-cp.md 2>&1); r=$?
check "context-pack.sh dal plugin, senza CONTEXT_PACK_ROOT, da una sottocartella: legge la spec del progetto" '[ $r -eq 0 ] && [ -f "$SP/spec-cp.run/context-pack.md" ]' "rc=$r $o"
PM1="$T/mut cp/maat"; copia "$PLUGIN" "$PM1"
check "  premessa: mutazione ROOT=\${CONTEXT_PACK_ROOT:-\$HROOT} applicata" 'muta "$PM1/scripts/context-pack.sh" "ROOT=\${CONTEXT_PACK_ROOT:-\$PROJECT_ROOT}" "ROOT=\${CONTEXT_PACK_ROOT:-\$HROOT}"'
o=$(cd "$R/sub/dir" && bash "$PM1/scripts/context-pack.sh" .claude/.ai-workflow/spec-cp2.md 2>&1); r=$?
check "  controprova: col default di prima la spec non si trova (cercata nel plugin)" '[ $r -ne 0 ] && [ ! -e "$SP/spec-cp2.run/context-pack.md" ] && printf "%s" "$o" | grep -q "spec non trovato"' "rc=$r $o"

gk() { printf '%s\n' "$1" | sed -n 's/^gates: .* chiave=\([0-9a-f]*\) .*/\1/p'; }
# gates.sh reads moduli and comandi from maat.json (pk04b-1): a minimal module, with no gate at this level and no files
printf '{"versione_schema": 1, "moduli": [{"nome": "tutto", "radice": ".", "regola_test": "nessuna"}]}\n' > "$R/.claude/maat.json"
g1=$(cd "$R/sub/dir" && bash "$P/scripts/gates.sh" --run-dir "$T/g1.run" min 2>&1)
g2=$(cd "$F" && FIC_GATES_ROOT="$R" bash "$P/scripts/gates.sh" --run-dir "$T/g2.run" min 2>&1)
check "gates.sh dal plugin, senza FIC_GATES_ROOT: legge il progetto della cartella di lavoro (stessa chiave di FIC_GATES_ROOT=<repo>)" '[ -n "$(gk "$g1")" ] && [ "$(gk "$g1")" = "$(gk "$g2")" ]' "$g1 / $g2"
PM2="$T/mut gates/maat"; copia "$PLUGIN" "$PM2"
check "  premessa: mutazione ROOT=\${FIC_GATES_ROOT:-\$HROOT} applicata" 'muta "$PM2/scripts/gates.sh" "ROOT=\${FIC_GATES_ROOT:-\$PROJECT_ROOT}" "ROOT=\${FIC_GATES_ROOT:-\$HROOT}"'
g3=$(cd "$R/sub/dir" && bash "$PM2/scripts/gates.sh" --run-dir "$T/g3.run" min 2>&1)
check "  controprova: col default di prima la chiave non e' quella del progetto" '[ "$(gk "$g3")" != "$(gk "$g2")" ]' "$g3"

cat > "$T/rp-spia" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "${SPIA_TAG:-finto}" "$(pwd -W 2>/dev/null || pwd)" "$1" >> "$SPYF"
exit 0
EOF
chmod +x "$T/rp-spia"
printf '# Prova driver\n\nRequisito: `a.txt`\n' > "$SP/spec-dr.md"
o=$(cd "$R/sub/dir" && SPYF="$T/dr.spia" FIC_RUN_PHASE="$T/rp-spia" "$FIC_PY" "$P/scripts/driver.py" run "$SP/spec-dr.md" --max-fasi 1 2>&1); r=$?
check "driver.py run senza CONTEXT_PACK_ROOT: context-pack: exit 0, pacchetto nella run dir del progetto" 'grep -q "context-pack: exit 0" "$SP/spec-dr.run/driver.log" && [ -f "$SP/spec-dr.run/context-pack.md" ] && grep -q "|$(canon "$R")|.claude/.ai-workflow/spec-dr.run$" "$T/dr.spia"' "rc=$r $o"

# ---------------------------------------------------------------- 3. FIC_DRIVER_ROOT = harness root
PC="$T/copia driver/maat"; copia "$PLUGIN" "$PC"
cp "$T/rp-spia" "$PC/scripts/run-phase.sh"
printf '# Prova FIC_DRIVER_ROOT\n\nRequisito: `a.txt`\n' > "$SP/spec-fd.md"; cp "$SP/spec-fd.md" "$SP/spec-fd2.md"
o=$(cd "$F" && SPIA_TAG=copia SPYF="$T/fd.spia" FIC_DRIVER_ROOT="$PC" FIC_CONTEXT_PACK=- "$FIC_PY" "$P/scripts/driver.py" run "$SP/spec-fd.md" --max-fasi 1 2>&1); r=$?
check "FIC_DRIVER_ROOT su una copia: run-phase.sh della copia, run dir e cwd del progetto della spec" 'grep -qx "copia|$(canon "$R")|.claude/.ai-workflow/spec-fd.run" "$T/fd.spia" && [ -f "$SP/spec-fd.run/driver.log" ]' "rc=$r $o $(cat "$T/fd.spia" 2>/dev/null)"
cp "$PC/scripts/driver.py" "$PC/scripts/driver-mut.py"
check "  premessa: mutazione «run dir da FIC_DRIVER_ROOT» applicata" 'muta "$PC/scripts/driver-mut.py" "        run_fs = spec_fs[:-3] + \".run\" if spec_fs.endswith(\".md\") else spec_fs + \".run\"" "        run_fs = os.path.join(ROOT, os.path.basename(spec_fs)[:-3] + \".run\")"'
o=$(cd "$F" && SPIA_TAG=copia SPYF="$T/fd2.spia" FIC_DRIVER_ROOT="$PC" FIC_CONTEXT_PACK=- "$FIC_PY" "$PC/scripts/driver-mut.py" run "$SP/spec-fd2.md" --max-fasi 1 2>&1)
check "  controprova: con le run dir lette da FIC_DRIVER_ROOT il caso con la spec in un altro repo fallisce" '! { grep -qx "copia|$(canon "$R")|.claude/.ai-workflow/spec-fd2.run" "$T/fd2.spia" 2>/dev/null && [ -f "$SP/spec-fd2.run/driver.log" ]; }' "$o"

# ---------------------------------------------------------------- 4. layout G
o=$(cd "$R" && bash -c '. "$1/scripts/worktree-lib.sh" && declare -F fic_deps_fp' _ "$P" 2>&1); r=$?
check "worktree-lib.sh incluso dal plugin trova fic-mirror.sh in scripts/" '[ $r -eq 0 ] && printf "%s" "$o" | grep -qx fic_deps_fp' "rc=$r $o"
PG="$T/mut g/maat"; copia "$PLUGIN" "$PG"
check "  premessa: mutazione WTLIB_TEST=\$WTLIB_DIR/../test applicata" 'muta "$PG/scripts/worktree-lib.sh" "WTLIB_TEST=\$MAAT_SCRIPTS" "WTLIB_TEST=\$(cd \"\$WTLIB_DIR/../test\" 2>/dev/null && pwd)"'
o=$(cd "$R" && bash -c '. "$1/scripts/worktree-lib.sh"' _ "$PG" 2>&1); r=$?
check "  controprova: con \$WTLIB_DIR/../test l'inclusione esce con 1" '[ $r -eq 1 ] && printf "%s" "$o" | grep -q "fic-mirror.sh non trovato"' "rc=$r $o"

# ---------------------------------------------------------------- 5. lock in the .git of the project repo
OKJ='{"type":"result","result":"ESITO FASE implement: OK — finto","structured_output":{"fase":"implement","esito":"OK","motivo":"m","deviazioni":[],"bloccato_su":"nessuno","file":[],"gate_interni":[],"finding":[]}}'
cat > "$T/claude" <<EOF
#!/usr/bin/env bash
cat > /dev/null
[ -n "\${LOCK_ATTESO:-}" ] && [ -d "\$LOCK_ATTESO" ] && echo si >> "\$SPYL"
echo '$OKJ'
EOF
cat > "$T/claude-attende" <<EOF
#!/usr/bin/env bash
cat > /dev/null
echo preso > "\$PRESO"
i=0; while [ ! -f "\$RILASCIO" ] && [ \$i -lt 1200 ]; do sleep 0.1; i=\$((i + 1)); done
echo '$OKJ'
EOF
printf '#!/usr/bin/env bash\necho "gates: esito=PASS chiave=k0 evidence=-"\n' > "$T/gates"
chmod +x "$T/claude" "$T/claude-attende" "$T/gates"
echo "/maat:full-implementation-cycle --worker=implement x" > "$T/prompt.md"
fase() { # $1 plugin (or scripts folder), $2 repo (cwd), $3 run dir, $4 label; fake claude from CLAUDE_BIN
  (cd "$2" && env -u FIC_REPO -u FIC_LOCK -u FIC_PHASE CLAUDE_BIN="${CL_FINTO:-$T/claude}" FIC_GATES="$T/gates" \
    FIC_FINALIZE="$T/non-esiste" FIC_LANES=0 FIC_DRIVER=0 bash "$1" "$3" "$4" "$T/prompt.md" </dev/null)
}
GD=$(cd "$R" && git rev-parse --absolute-git-dir)
LOCK_ATTESO="$GD/full-implementation-cycle.lock" SPYL="$T/lk.spia" fase "$P/scripts/run-phase.sh" "$R" "$SP/spec-lk.run" 01-implement >/dev/null 2>"$T/lk.err"
check "plugin fuori dal repo: la fase prende il lock nel .git del repo del progetto" 'grep -qx si "$T/lk.spia" 2>/dev/null' "$(tail -5 "$T/lk.err")"
PM3="$T/mut lock/maat"; copia "$PLUGIN" "$PM3"
check "  premessa: mutazione git -C \"\$HERE\" applicata" 'muta "$PM3/scripts/run-phase.sh" "  gd=\$(git rev-parse --absolute-git-dir 2>/dev/null) && [ -n \"\$gd\" ] || {" "  gd=\$(git -C \"\$HERE\" rev-parse --absolute-git-dir 2>/dev/null) && [ -n \"\$gd\" ] || {"'
LOCK_ATTESO="$GD/full-implementation-cycle.lock" SPYL="$T/lk2.spia" fase "$PM3/scripts/run-phase.sh" "$R" "$SP/spec-lk2.run" 01-implement >/dev/null 2>&1
check "  controprova: col lock da git -C \"\$HERE\" il lock non e' nel .git del repo" '! grep -qx si "$T/lk2.spia" 2>/dev/null'

# ---------------------------------------------------------------- 6. lock of the worktree, not of FIC_REPO
RW="$T/wt/principale"; newrepo "$RW" >/dev/null 2>&1
WT="$T/wt/collegato"; git -C "$RW" worktree add -q -b collegato "$WT" >/dev/null 2>&1
MG=$(cd "$RW" && git rev-parse --absolute-git-dir)
mkdir -p "$MG/full-implementation-cycle.lock" && printf 'run=altro\nlabel=01-implement\npid=%s\n' "$$" > "$MG/full-implementation-cycle.lock/owner"
o=$(cd "$RW" && bash "$P/scripts/run-phase.sh" --lock-status 2>&1); r=$?
check "premessa: il lock del tree principale e' occupato da un pid vivo" '[ $r -eq 1 ] && printf "%s" "$o" | grep -q "^occupato"' "rc=$r $o"
o=$(cd "$WT" && FIC_REPO="$RW" bash "$P/scripts/run-phase.sh" --lock-status 2>&1); r=$?
check "--lock-status dal worktree con FIC_REPO del principale: riporta il lock del worktree (libero)" '[ $r -eq 0 ] && printf "%s" "$o" | grep -q "^libero"' "rc=$r $o"
PM4="$T/mut lock progetto/maat"; copia "$PLUGIN" "$PM4"
LOCKLINE='  gd=$(git rev-parse --absolute-git-dir 2>/dev/null) && [ -n "$gd" ] || {'
LOCKMUT='  gd=$(git -C "$PROJECT_ROOT" rev-parse --absolute-git-dir 2>/dev/null) && [ -n "$gd" ] || {'
check "  premessa: mutazione «lock da PROJECT_ROOT» applicata" 'muta "$PM4/scripts/run-phase.sh" "$LOCKLINE" "$LOCKMUT"'
o=$(cd "$WT" && FIC_REPO="$RW" bash "$PM4/scripts/run-phase.sh" --lock-status 2>&1); r=$?
check "  controprova della correzione: col lock da PROJECT_ROOT riporta occupato" '[ $r -eq 1 ] && printf "%s" "$o" | grep -q "^occupato"' "rc=$r $o"
rm -rf "$MG/full-implementation-cycle.lock"

PM5="$T/mut lock e difesa/maat"; copia "$PM4" "$PM5"
check "  premessa: mutazione «senza -u FIC_REPO» in ciclo-worktree.sh applicata (2 righe)" '[ "$(grep -c "env -u FIC_LOCK -u FIC_PHASE -u FIC_REPO bash" "$PM5/scripts/ciclo-worktree.sh")" = 2 ] && sed -i "s/env -u FIC_LOCK -u FIC_PHASE -u FIC_REPO bash/env -u FIC_LOCK -u FIC_PHASE bash/" "$PM5/scripts/ciclo-worktree.sh" && [ "$(grep -c "env -u FIC_LOCK -u FIC_PHASE bash" "$PM5/scripts/ciclo-worktree.sh")" = 2 ]'
rimuovi_occupato() { # $1 plugin, $2 repo → «rc presente|assente»: rimuovi with the main tree's FIC_REPO and the worktree lock held
  local pl=$1 rb=$2 w gd o rc
  newrepo "$rb" >/dev/null 2>&1
  # ciclo-worktree.sh asks the PLUGIN's run-phase.sh for --lock-status (MAAT_ROOT=$pl, layout H): the variant is there
  printf '# Uno\n' > "$rb/.claude/.ai-workflow/spec-uno.md"
  w=$(cd "$rb" && MAAT_ROOT="$pl" bash "$pl/scripts/ciclo-worktree.sh" crea .claude/.ai-workflow/spec-uno.md 2>/dev/null | tail -1)
  [ -d "$w" ] || { echo "crea fallito"; return; }
  gd=$(cd "$w" && git rev-parse --absolute-git-dir)
  mkdir -p "$gd/full-implementation-cycle.lock" && printf 'run=x\nlabel=01-implement\npid=%s\n' "$$" > "$gd/full-implementation-cycle.lock/owner"
  o=$(cd "$rb" && FIC_REPO=$(canon "$rb") MAAT_ROOT="$pl" bash "$pl/scripts/ciclo-worktree.sh" rimuovi uno 2>&1); rc=$?
  rm -rf "$gd/full-implementation-cycle.lock" 2>/dev/null
  if [ -d "$w" ]; then echo "$rc presente"; else echo "$rc assente"; fi
  printf '%s\n' "$o" > "$T/rimuovi.$(basename "$(dirname "$rb")").out"
}
x=$(rimuovi_occupato "$P" "$T/b1/proj")
check "ciclo-worktree.sh rimuovi con FIC_REPO del principale: il worktree col proprio lock occupato NON si rimuove" '[ "$x" = "3 presente" ]' "$x $(cat "$T/rimuovi.b1.out" 2>/dev/null)"
x=$(rimuovi_occupato "$PM4" "$T/b2/proj")
check "  con la sola mutazione del lock resta verde: -u FIC_REPO difende da solo" '[ "$x" = "3 presente" ]' "$x $(cat "$T/rimuovi.b2.out" 2>/dev/null)"
x=$(rimuovi_occupato "$PM5" "$T/b3/proj")
check "  controprova della difesa: lock da PROJECT_ROOT e senza -u FIC_REPO ⇒ il worktree si rimuove" '[ "${x#* }" = assente ]' "$x $(cat "$T/rimuovi.b3.out" 2>/dev/null)"

# ---------------------------------------------------------------- 7. mutual exclusion with the internal harness
# The reference internal harness is read from history ($INTERNO_REF): in a repo without that commit (the public
# repo starts from a single commit) the section is SKIPPED with a reason; the exclusion was verified where it existed.
if ! git -c safe.directory='*' -C "$PLUGIN" cat-file -e "$INTERNO_REF:plugins/maat/scripts/run-phase.sh" 2>/dev/null; then
  echo "SKIP [7. esclusione col harness interno — la storia non ha $INTERNO_REF]"
else
RX="$T/esclusione/repo"; newrepo "$RX" >/dev/null 2>&1
I="$RX/.claude/skills/full-implementation-cycle"
mkdir -p "$I" "$RX/.claude/skills/implementation-review-cycle" "$RX/.claude/skills/plan-review-cycle" "$RX/script/fic/schemas"
interno() { git -C "$PLUGIN" show "$INTERNO_REF:plugins/maat/$1" > "$2" 2>/dev/null; }
interno scripts/run-phase.sh "$I/run-phase.sh" && interno scripts/python.sh "$I/python.sh" && interno scripts/guard.py "$I/guard.py" &&
  interno scripts/cycle-state.sh "$I/cycle-state.sh" && interno skills/full-implementation-cycle/child-rules.md "$I/child-rules.md" &&
  interno scripts/review-surface.sh "$RX/.claude/skills/implementation-review-cycle/review-surface.sh" &&
  interno scripts/plan-check.sh "$RX/.claude/skills/plan-review-cycle/plan-check.sh" &&
  interno scripts/stop-hook.py "$RX/script/fic/stop-hook.py" &&
  interno schemas/phase-result.schema.json "$RX/script/fic/schemas/phase-result.schema.json"; ri=$?
check "premessa: harness interno di $INTERNO_REF, lock da git -C \"\$HERE\" con lo stesso nome" '[ $ri -eq 0 ] && grep -qF "gd=\$(git -C \"\$HERE\" rev-parse --absolute-git-dir" "$I/run-phase.sh" && grep -qF "LOCK=\$gd/full-implementation-cycle.lock" "$I/run-phase.sh"'
rm -f "$T/preso" "$T/rilascio"
(cd "$RX" && env -u FIC_REPO -u FIC_LOCK -u FIC_PHASE CLAUDE_BIN="$T/claude-attende" PRESO="$T/preso" RILASCIO="$T/rilascio" FIC_GATES="$T/gates" \
  FIC_FINALIZE="$T/non-esiste" FIC_LANES=0 FIC_DRIVER=0 bash "$I/run-phase.sh" "$RX/.claude/.ai-workflow/spec-int.run" 01-implement "$T/prompt.md" \
  </dev/null > "$T/int.out" 2>&1) &
BG=$!
i=0; while [ ! -f "$T/preso" ] && [ $i -lt 600 ] && kill -0 "$BG" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
GX=$(cd "$RX" && git rev-parse --absolute-git-dir)
check "premessa: la fase del harness interno gira e tiene il lock nel .git del repo" '[ -f "$T/preso" ] && [ -d "$GX/full-implementation-cycle.lock" ]' "$(tail -5 "$T/int.out")"
fase "$P/scripts/run-phase.sh" "$RX" "$RX/.claude/.ai-workflow/spec-plg.run" 01-implement >/dev/null 2>"$T/plg.err"; r=$?
check "il plugin, stesso repo, col lock del harness interno occupato: rifiuta (exit 4, lock occupato)" '[ $r -eq 4 ] && grep -q "lock occupato" "$T/plg.err"' "rc=$r $(tail -3 "$T/plg.err")"
PL="$T/mut nome lock/maat"; copia "$PLUGIN" "$PL"
check "  premessa: mutazione full-implementation-cycle.lock → maat.lock applicata" 'muta "$PL/scripts/run-phase.sh" "  LOCK=\$gd/full-implementation-cycle.lock" "  LOCK=\$gd/maat.lock"'
fase "$PL/scripts/run-phase.sh" "$RX" "$RX/.claude/.ai-workflow/spec-plg2.run" 01-implement >/dev/null 2>"$T/plg2.err"; r=$?
check "  controprova: col lock rinominato il plugin non aspetta e parte nonostante il lock interno" '[ $r -ne 4 ] && [ -f "$RX/.claude/.ai-workflow/spec-plg2.run/log/01-implement.exit" ]' "rc=$r $(tail -3 "$T/plg2.err")"
touch "$T/rilascio"; wait "$BG" 2>/dev/null; BG=""
fi

# ---------------------------------------------------------------- 8. snapshot of MAAT_ROOT
S1=$(snap "$P")
check "istantanea: nessun file creato, cambiato o cancellato sotto MAAT_ROOT (copia del plugin usata dalle sezioni 1-7)" '[ "$S0" = "$S1" ]' "$(diff <(printf '%s\n' "$S0") <(printf '%s\n' "$S1") | head -10)"
PS="$T/istantanea/maat"; copia "$PLUGIN" "$PS"; s0=$(snap "$PS")
touch "$PS/scripts/nuovo.txt"; s1=$(snap "$PS"); rm -f "$PS/scripts/nuovo.txt"
echo "# cambiato" >> "$PS/scripts/python.sh"; s2=$(snap "$PS")
check "  controprova: un file creato sotto MAAT_ROOT ⇒ rosso; uno modificato ⇒ rosso" '[ "$s0" != "$s1" ] && [ "$s0" != "$s2" ]'

# ---------------------------------------------------------------- 8b. ${CLAUDE_PLUGIN_ROOT} in texts read without substitution
# Claude Code substitutes it only in SKILL.md and in the agents (pk01 D3). (1) every other .md of a skill containing it
# is in a skill whose SKILL.md declares the root; (2) child-rules.md reaches the sub-session already substituted,
# and the sub-session receives CLAUDE_PLUGIN_ROOT=MAAT_ROOT. Counterproofs on mutated copies.
RIGA_RADICE='Radice del plugin: `${CLAUDE_PLUGIN_ROOT}`. Nei file di questa skill che leggi con Read, `${CLAUDE_PLUGIN_ROOT}` vale questo percorso: sostituiscilo prima di eseguire un comando.'
senza_radice() { # $1 plugin → the .md files with the literal form whose skill does not declare the root (empty = ok)
  local f s
  (cd "$1/skills" && grep -rlF '${CLAUDE_PLUGIN_ROOT}' --include='*.md' . | grep -v '/SKILL\.md$') | while IFS= read -r f; do
    s=${f#./}; s=${s%%/*}
    grep -qxF "$RIGA_RADICE" "$1/skills/$s/SKILL.md" 2>/dev/null || echo "$f"
  done
}
nr=$(cd "$PLUGIN/skills" && grep -rlF '${CLAUDE_PLUGIN_ROOT}' --include='*.md' . | grep -vc '/SKILL\.md$')
sr=$(senza_radice "$PLUGIN")
check "ogni .md di skill con \${CLAUDE_PLUGIN_ROOT} (non SKILL.md) sta in una skill che dichiara la radice ($nr file)" '[ "$nr" -gt 0 ] && [ -z "$sr" ]' "$sr"
PR="$T/mut radice/maat"; copia "$PLUGIN" "$PR"
check "  premessa: riga della radice tolta da full-implementation-cycle/SKILL.md" 'muta "$PR/skills/full-implementation-cycle/SKILL.md" "$RIGA_RADICE" ""'
check "  controprova: senza la riga i file della skill risultano scoperti" '[ -n "$(senza_radice "$PR")" ]'
cat > "$T/claude-cr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "\$SPYR.args"; printf '%s\n' "\${CLAUDE_PLUGIN_ROOT:-}" > "\$SPYR.env"; cat > /dev/null
echo '$OKJ'
EOF
chmod +x "$T/claude-cr"
SPYR="$T/cr1" CL_FINTO="$T/claude-cr" fase "$P/scripts/run-phase.sh" "$R" "$SP/spec-cr.run" 01-implement >/dev/null 2>&1
check "child-rules.md alla sotto-sessione senza la forma letterale, con il percorso del plugin" '[ -s "$T/cr1.args" ] && ! grep -qF "\${CLAUDE_PLUGIN_ROOT}" "$T/cr1.args" && grep -qF "$(canon "$P")/skills/full-implementation-cycle/SKILL.md" "$T/cr1.args"' "$(grep -n 'SKILL.md' "$T/cr1.args" 2>/dev/null | head -3)"
check "  la sotto-sessione riceve CLAUDE_PLUGIN_ROOT=MAAT_ROOT" '[ "$(cat "$T/cr1.env" 2>/dev/null)" = "$(canon "$P")" ]' "$(cat "$T/cr1.env" 2>/dev/null)"
PCR="$T/mut child-rules/maat"; copia "$PLUGIN" "$PCR"
check "  premessa: sostituzione di child-rules.md tolta da run-phase.sh" 'muta "$PCR/scripts/run-phase.sh" "CHILD_RULES_TXT=\${CHILD_RULES_TXT//'"'"'\${CLAUDE_PLUGIN_ROOT}'"'"'/\$MAAT_ROOT}" ":"'
SPYR="$T/cr2" CL_FINTO="$T/claude-cr" fase "$PCR/scripts/run-phase.sh" "$R" "$SP/spec-cr2.run" 01-implement >/dev/null 2>&1
check "  controprova: senza la sostituzione la forma letterale arriva alla sotto-sessione" '[ -s "$T/cr2.args" ] && grep -qF "\${CLAUDE_PLUGIN_ROOT}" "$T/cr2.args"'

# ---------------------------------------------------------------- 9. anti-layout search
# Outside comments and tests; examples/ excluded: they are project configurations (project paths, not harness paths).
# DECLARED exclusions (they are not the harness looking for itself; each has its own part that closes it):
#   PK04B    the project commands of the WSL wrappers: `script/test/vitest-fast.sh` and `script/test/counterproof.sh` in the texts,
#            in the commands emitted by plan-check.sh, in WRAPPER_SCRIPTS of guard.py and in the corpus inject; the two wrappers
#            themselves (scripts/vitest-fast.sh, scripts/counterproof.sh: root from the reference project layout) → pk04b-1/pk04b-2;
#   CR-RX    cycle-report.py: the regex that classifies the transcript commands (historical cycles too) as
#            git/harness; it is not a path used to find files.
PK04B='script/test/(vitest-fast|counterproof)\.sh|^\./scripts/(vitest-fast|counterproof)\.sh:'
CRRX='^\./scripts/cycle-report\.py:[0-9]+:[[:space:]]*\("git/harness"'
antistruttura() {
  (cd "$1" && grep -rnE '/\.\./\.\./\.\./script/|\.claude/skills/|script/fic|script/test|HERE/\.\./\.\.|/\.\./test' \
     --include='*.sh' --include='*.py' --include='*.md' --include='*.json' . 2>/dev/null |
   grep -vE '^\./examples/|\.test\.sh:|/test-review-surface\.sh:' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' |
   grep -vE "$PK04B" | grep -vE "$CRRX")
}
A0=$(antistruttura "$PLUGIN"); c0=$(printf '%s' "$A0" | grep -c .)
check "anti-struttura: zero righe nel plugin (fuori da commenti e test)" '[ "$c0" -eq 0 ]' "$c0 righe; le prime: $(printf '%s\n' "$A0" | head -15)"
PA="$T/mut antistruttura/maat"; copia "$PLUGIN" "$PA"
muta "$PA/scripts/worktree-lib.sh" 'WTLIB_TEST=$MAAT_SCRIPTS' 'WTLIB_TEST=$(cd "$WTLIB_DIR/../test" 2>/dev/null && pwd)'
c1=$(antistruttura "$PA" | grep -c .)
check "  controprova: rimettere \$WTLIB_DIR/../test in worktree-lib.sh ⇒ una riga in piu'" '[ "$c1" -eq $((c0 + 1)) ]' "prima $c0, dopo $c1"

echo "maat-paths.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
