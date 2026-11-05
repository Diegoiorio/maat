#!/usr/bin/env bash
# Deterministic tests of test-fast.sh (and of its deprecated wrapper vitest-fast.sh), in a fake workspace
# (no real vitest, no /mnt/c). The module and the commands come from the .claude/maat.json of the fake repo, which is
# examples/nuxt-fastapi.maat.json: the copy of modules/app, the root modules/app/apps/admin, the `copia` commands.
# To run in WSL:  wsl -- bash -lc 'bash /mnt/c/<maat>/plugins/maat/scripts/test-fast.test.sh'
# Variant to try: TF=/path/variant.sh (it is copied in place of the script in the plugin copy).
set -u
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(dirname "$HERE")
TF=${TF:-$HERE/test-fast.sh}
FM=${FM:-$HERE/fic-mirror.sh}   # shared helper (also replaceable by a variant)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; fail=0
check() { n=$((n + 1)); if eval "$2"; then :; else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
unset MAAT_CONFIG MAAT_MODULO MAAT_ROOT PROJECT_ROOT FIC_REPO FIC_LANE FIC_ALLOW_MNT_C

# plugin copy: test-fast.sh + the files it uses (fic-mirror.sh, the reader, python.sh, the schema)
HP=$T/maat; mkdir -p "$HP/scripts" "$HP/schemas"
cp "$TF" "$HP/scripts/test-fast.sh"; cp "$FM" "$HP/scripts/fic-mirror.sh"; cp "$HERE/vitest-fast.sh" "$HP/scripts/vitest-fast.sh"
cp "$HERE/maat-config.py" "$HERE/python.sh" "$HP/scripts/"; cp "$PLUGIN/schemas/maat-config.schema.json" "$HP/schemas/"
# 1.4.0: the message catalog and its two readers (test-fast.sh and fic-mirror.sh find them next to themselves)
mkdir -p "$HP/scripts/lib"; cp "$HERE/lib/maat-msg.sh" "$HERE/lib/messages.tsv" "$HP/scripts/lib/"; cp "$HERE/maat_msg.py" "$HP/scripts/"

# fake repo: .claude/maat.json (the nuxt-fastapi example) + modules/app with two packages
R=$T/repo; A=$R/modules/app
mkdir -p "$R/.claude" "$A/apps/admin/tests" "$A/packages/ui" "$A/node_modules/dep" "$A/apps/admin/.nuxt"
cp "$PLUGIN/examples/nuxt-fastapi.maat.json" "$R/.claude/maat.json"
echo '{"name":"root"}' > "$A/package.json"; echo '{"lock":1}' > "$A/package-lock.json"
echo '{"name":"admin"}' > "$A/apps/admin/package.json"; echo '{"name":"ui"}' > "$A/packages/ui/package.json"
echo 'export const x = 1' > "$A/apps/admin/src.ts"
echo 'import { x } from "../src"' > "$A/apps/admin/tests/a.test.ts"
echo 'VAR=1' > "$A/apps/admin/.env"
echo 'dep' > "$A/node_modules/dep/index.js"
printf 'node_modules\n.nuxt\n.env\n' > "$R/.gitignore"
(cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init)

# fake npx: records cwd, arguments and CI; optionally writes (FAKE_WRITE) and exits with FAKE_RC
BIN=$T/bin; mkdir -p "$BIN"
# 1.6.0: the real rsync and cp found in the PATH, not /usr/bin/rsync and /bin/cp (on macOS those are openrsync and
# the BSD cp, without --remove-destination; the GNU ones are in the PATH from Homebrew). Same files on Linux.
export FAKE_RSYNC_VERO=$(command -v rsync) FAKE_CP_VERO=$(command -v cp)
cat > "$BIN/npx" <<'EOF'
#!/usr/bin/env bash
{ echo "cwd=$PWD"; echo "args=$*"; echo "CI=${CI:-}"; echo "src=$(cat ../../apps/admin/src.ts 2>/dev/null)"; } > "$FAKE_LOG"
echo "cwd=$PWD args=$*" >> "$FAKE_LOG.all"
# fake eslint, compact format: one error for each file that contains a BAD<SOMETHING> marker.
# This way the classification sees DIFFERENT messages between the current content and the base content.
rc=0
if [ "${1:-}" = eslint ]; then
  for f in "$@"; do
    [ -f "$f" ] || continue
    # CFGERR: eslint cannot run on this group (exit 2). KILLME: dies during the pass,
    # to prove that the trap restores the copy anyway.
    grep -q CFGERR "$f" && exit 2
    # exec 9>&-: the child inherits the flock descriptor on the copy, and by keeping it open while
    # sleeping it would leave the copy 'busy' even after the script dies.
    if grep -q KILLME "$f"; then exec 9>&- 2>/dev/null; pkill -TERM -f 'scripts/test-fast.sh --lint'; sleep 3; exit 0; fi
    m=$(grep -o 'BAD[A-Z]*' "$f" | head -1)
    [ -n "$m" ] || continue
    echo "$PWD/$f: line 1, col 3, Error - Cattivo: $m (no-bad)"
    rc=1
  done
fi
[ -n "${FAKE_WRITE:-}" ] && { mkdir -p "$(dirname "$FAKE_WRITE")"; echo scritto >> "$FAKE_WRITE"; }
# fake vitest whose result depends on the loaded CONTENT: red if src.ts contains ROSSO (equivalence
# guard: a file that is out of sync changes the result)
[ "${1:-}" = vitest ] && grep -q ROSSO ../../apps/admin/src.ts 2>/dev/null && rc=1
exit "${FAKE_RC:-$rc}"
EOF
# fake rsync only if FAKE_RSYNC_NOOP: simulates a sync that aligned nothing
# FAKE_RSYNC_NOOP_ONCE=<file>: a single empty sync (while the file exists), then the real rsync
# FAKE_RSYNC_FAIL: every rsync fails (exit 23), like an interrupted rsync
cat > "$BIN/rsync" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_RSYNC_FAIL:-}" ] && exit 23
[ -n "${FAKE_RSYNC_NOOP:-}" ] && exit 0
[ -n "${FAKE_RSYNC_NOOP_ONCE:-}" ] && [ -e "$FAKE_RSYNC_NOOP_ONCE" ] && { rm -f "$FAKE_RSYNC_NOOP_ONCE"; exit 0; }
exec "$FAKE_RSYNC_VERO" "$@"
EOF
# fake cp only if FAKE_CP_NOOP: the copy of the INCREMENTAL sync (the only one with --remove-destination)
# writes nothing, i.e. an incremental sync that did not align
cat > "$BIN/cp" <<'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_CP_NOOP:-}" ]; then for a in "$@"; do [ "$a" = --remove-destination ] && exit 0; done; fi
exec "$FAKE_CP_VERO" "$@"
EOF
# fake npm (first alternative of copia.lint, with lint-baseline.mjs): records like npx
cat > "$BIN/npm" <<'EOF'
#!/usr/bin/env bash
{ echo "cwd=$PWD"; echo "args=npm $*"; echo "CI=${CI:-}"; } > "$FAKE_LOG"
echo "cwd=$PWD args=npm $*" >> "$FAKE_LOG.all"
exit "${FAKE_RC:-0}"
EOF
chmod +x "$BIN/npx" "$BIN/npm" "$BIN/rsync" "$BIN/cp"
export PATH="$BIN:$PATH" HOME=$T/home FAKE_LOG=$T/npx.log
mkdir -p "$HOME"
M=$HOME/fic-mirror/modules/app
# As gates.sh launches it: tests from the module root, lint and --setup from the repo (directories of comandi.test and
# comandi.lint in the example). tfin <dir> launches from any directory; tfin_mut the mutated variant.
tfin() { local d=$1; shift; (cd "$d" && bash "$HP/scripts/test-fast.sh" "$@"); }
tfr() { case "${1:-}" in --lint|--setup) tfin "$R" "$@" ;; *) tfin "$A/apps/admin" "$@" ;; esac; }
tfin_mut() { (cd "$A/apps/admin" && bash "$HP/scripts/vf-mut.sh" "$@"); }
vf() { rm -f "$FAKE_LOG" "$FAKE_LOG.all"; tfr "$@" > "$T/out" 2>&1; echo $? > "$T/rc"; }
rc() { cat "$T/rc"; }

# 1. without a copy: BLOCKED exit 3, no silent fallback; with FIC_ALLOW_MNT_C=1 fallback to /mnt/c
#    (here: the source) declared, with CI=true
vf tests/a.test.ts
check "senza copia -> BLOCKED exit 3, nessun ripiego" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (copia non utilizzabile: copia assente" "$T/out" && [ ! -f "$FAKE_LOG" ]'
FIC_ALLOW_MNT_C=1 vf tests/a.test.ts
check "senza copia + FIC_ALLOW_MNT_C=1 -> ripiego" 'grep -q "luogo=mnt-c (ripiego: copia assente" "$T/out" && grep -qx "cwd=$A/apps/admin" "$FAKE_LOG"'
check "  anche il ripiego gira con CI=true" 'grep -qx "CI=true" "$FAKE_LOG" && [ "$(rc)" = 0 ]'
check "  la riga d esito dichiara il ripiego" '[ "$(tail -1 "$T/out")" = "vitest-fast: esito=PASS luogo=mnt-c (ripiego dichiarato: FIC_ALLOW_MNT_C=1)" ]'
check "uso errato senza argomenti -> 64" 'tfr >/dev/null 2>&1; [ $? -eq 64 ]'

# 2. setup, then normal path: vitest in the copy, same arguments, CI=true
tfr --setup > /dev/null 2>&1
check "setup: copia con node_modules e impronta" '[ -f "$M/node_modules/dep/index.js" ] && [ -s "$M/.fic-deps" ]'
vf tests/a.test.ts
check "percorso normale: gira nella copia" 'grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && grep -q "^vitest-fast: luogo=copia" "$T/out"'
check "  argomenti invariati, CI=true" 'grep -qx "args=vitest run tests/a.test.ts" "$FAKE_LOG" && grep -qx "CI=true" "$FAKE_LOG"'
check "  esito PASS, exit 0" '[ "$(rc)" = 0 ] && grep -q "esito=PASS luogo=copia" "$T/out"'
check "  .nuxt della copia ripulito" '[ ! -d "$M/apps/admin/.nuxt" ]'

# 3. imported file modified: synced before the run
echo 'export const x = 2' > "$A/apps/admin/src.ts"
vf tests/a.test.ts
check "file modificato: la copia lo vede" 'grep -qx "src=export const x = 2" "$FAKE_LOG" && grep -q "luogo=copia" "$T/out"'

# 4. sync that does not align (modified file not synced) -> resync, then BLOCKED
#    (from the second run the sync is incremental: what "does not align" is its copy, FAKE_CP_NOOP; the
#    resync is the full sync, FAKE_RSYNC_NOOP)
echo 'export const x = 3' > "$A/apps/admin/src.ts"
FAKE_CP_NOOP=1 vf tests/a.test.ts
check "copia disallineata una volta -> risincronizzata, gira nella copia" 'grep -q "risincronizzazione" "$T/out" && grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && grep -qx "src=export const x = 3" "$FAKE_LOG" && grep -q "esito=PASS luogo=copia" "$T/out"'
echo 'export const x = 4' > "$A/apps/admin/src.ts"
FAKE_CP_NOOP=1 FAKE_RSYNC_NOOP=1 vf tests/a.test.ts
check "copia non allineata anche dopo la risincronizzazione -> BLOCKED exit 3, nessun ripiego" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (copia non utilizzabile: copia non allineata dopo la risincronizzazione" "$T/out" && [ ! -f "$FAKE_LOG" ]'
FIC_ALLOW_MNT_C=1 FAKE_CP_NOOP=1 FAKE_RSYNC_NOOP=1 vf tests/a.test.ts
check "  con FIC_ALLOW_MNT_C=1 -> ripiego dichiarato" 'grep -q "ripiego: copia non allineata" "$T/out" && grep -qx "cwd=$A/apps/admin" "$FAKE_LOG" && grep -q "luogo=mnt-c (ripiego dichiarato: FIC_ALLOW_MNT_C=1)" "$T/out"'

# 5. .env different and not synced -> not aligned (the ignored .env* files are in the manifest)
vf tests/a.test.ts > /dev/null
echo 'VAR=2' > "$A/apps/admin/.env"
FAKE_CP_NOOP=1 FAKE_RSYNC_NOOP=1 vf tests/a.test.ts
check ".env diverso -> copia non allineata" 'grep -q "copia non allineata" "$T/out" && grep -q "apps/admin/.env" "$T/out" && [ "$(rc)" = 3 ]'

# 6. file deleted in the source: it disappears from the copy
echo 'y' > "$A/apps/admin/tests/b.test.ts"
vf tests/a.test.ts
check "file nuovo non tracciato: copiato" '[ -f "$M/apps/admin/tests/b.test.ts" ]'
rm "$A/apps/admin/tests/b.test.ts"
vf tests/a.test.ts
check "file cancellato: sparisce dalla copia" '[ ! -e "$M/apps/admin/tests/b.test.ts" ] && grep -q "luogo=copia" "$T/out"'
check "  node_modules della copia non cancellato" '[ -f "$M/node_modules/dep/index.js" ]'

# 7. stale dependencies: lockfile or any package.json changed -> the copy realigns itself from the source
#    (which has node_modules), inside the lock, and the run happens in the copy. Mutation counterproof: realignment
#    switched off -> this case turns red.
fp() { ( . "$HP/scripts/fic-mirror.sh"; fic_deps_fp "$1" ); }
old12=$(cut -c1-12 "$M/.fic-deps")
mkdir -p "$M/apps/admin/.nuxt"; echo g > "$M/apps/admin/.nuxt/marker"
echo '{"lock":2}' > "$A/package-lock.json"; echo 'nuovo' > "$A/node_modules/dep/nuovo.js"
new12=$(fp "$A" | cut -c1-12)
vf tests/a.test.ts
check "lockfile diverso -> riallineamento automatico, riga d avviso, gira nella copia" '[ "$(rc)" = 0 ] && grep -qx "vitest-fast: dipendenze cambiate (impronta $old12 -> $new12): copia riallineata dall'"'"'origine" "$T/out" && grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && grep -q "esito=PASS luogo=copia" "$T/out" && ! grep -q ripiego "$T/out"'
check "  .fic-deps aggiornato all'impronta dell'origine, node_modules copiati" '[ "$(cat "$M/.fic-deps")" = "$(fp "$A")" ] && [ -f "$M/node_modules/dep/nuovo.js" ] && grep -q "\"lock\":2" "$M/package-lock.json"'
check "  .nuxt e cache ripuliti dopo il riallineamento (.fic-sync-gen)" '[ ! -e "$M/apps/admin/.nuxt/marker" ] && grep -q "generati della copia ripuliti" "$T/out"'
vf tests/a.test.ts
check "  il run dopo non riallinea di nuovo" '[ "$(rc)" = 0 ] && ! grep -q "dipendenze cambiate" "$T/out"'
# 1.4.0, English (MAAT_LINGUA=en): the same realignment, the reason lines from the catalog (fic-mirror.sh included),
# the frozen «vitest-fast: esito=… luogo=…» line as it is; then lock 2 again, the state of the cases below
old12=$(cut -c1-12 "$M/.fic-deps"); echo '{"lock":4}' > "$A/package-lock.json"; new12=$(fp "$A" | cut -c1-12)
MAAT_LINGUA=en vf tests/a.test.ts
check "en: lockfile diverso -> riallineamento in inglese, stessa riga d esito, niente italiano" '[ "$(rc)" = 0 ] && grep -qx "vitest-fast: dependencies changed (fingerprint $old12 -> $new12): copy realigned from the source" "$T/out" && grep -q "^vitest-fast: generated files of the copy cleaned" "$T/out" && grep -q "esito=PASS luogo=copia" "$T/out" && ! grep -qE "dipendenze|impronta|riallineata|generati|ripuliti|allineati|completato" "$T/out"'
MAAT_LINGUA=en vf
check "en: senza argomenti -> uso in inglese, exit 64" '[ "$(rc)" = 64 ] && grep -q "^usage: test-fast.sh <test files" "$T/out" && ! grep -q "^uso:" "$T/out"'
echo '{"lock":2}' > "$A/package-lock.json"; vf tests/a.test.ts
rm -f "$A/node_modules/dep/nuovo.js"
# 7a. realignment with an rsync that fails -> BLOCKED with the reason, no fallback; the next run retries
echo '{"lock":3}' > "$A/package-lock.json"
FAKE_RSYNC_FAIL=1 vf tests/a.test.ts
check "riallineamento con rsync fallito -> BLOCKED exit 3, nessun ripiego" '[ "$(rc)" = 3 ] && grep -q "copia non utilizzabile: dipendenze stantie, riallineamento automatico non riuscito: rsync dall'"'"'origine fallito (uscita 23)" "$T/out" && [ ! -f "$FAKE_LOG" ] && ! grep -q "luogo=mnt-c" "$T/out"'
check "  .fic-deps non resta l'impronta vecchia (interrotto)" '[ "$(cat "$M/.fic-deps")" = interrotto ]'
vf tests/a.test.ts
check "  il run dopo riprova e riallinea" '[ "$(rc)" = 0 ] && grep -q "dipendenze cambiate (impronta interrotto -> " "$T/out" && [ "$(cat "$M/.fic-deps")" = "$(fp "$A")" ] && [ ! -e "$M/node_modules/dep/nuovo.js" ]'
# 7b. source without node_modules and no seed source (main tree) -> BLOCKED as before, with the reason
mv "$A/node_modules" "$T/nm.via"
echo '{"lock":4}' > "$A/package-lock.json"
vf tests/a.test.ts
check "origine senza node_modules, nessuna fonte -> BLOCKED exit 3 col motivo" '[ "$(rc)" = 3 ] && grep -q "copia non utilizzabile: dipendenze stantie, riallineamento automatico non riuscito: l'"'"'origine non ha node_modules" "$T/out" && [ ! -f "$FAKE_LOG" ]'
mv "$T/nm.via" "$A/node_modules"
# 7c. realignment that exits 0 but records a wrong fingerprint (fic_deps_fp faked at write time, in
#     a variant of fic-mirror.sh in the fake repo) -> the second deps_ok catches it: BLOCKED, no run
cp "$HP/scripts/fic-mirror.sh" "$T/fm.vero"
sed '0,/^  fic_deps_fp "\$src" > "\$dst\/.fic-deps"/s//  echo sbagliata > "$dst\/.fic-deps"/' "$T/fm.vero" > "$HP/scripts/fic-mirror.sh"
check "premessa: impronta finta nel riallineamento" 'grep -q "^  echo sbagliata" "$HP/scripts/fic-mirror.sh"'
echo '{"lock":5}' > "$A/package-lock.json"
vf tests/a.test.ts
check "riallineamento con impronta sbagliata -> BLOCKED exit 3 dal secondo controllo" '[ "$(rc)" = 3 ] && grep -q "copia non utilizzabile: dipendenze stantie anche dopo il riallineamento automatico" "$T/out" && [ ! -f "$FAKE_LOG" ]'
cp "$T/fm.vero" "$HP/scripts/fic-mirror.sh"
echo '{"lock":1}' > "$A/package-lock.json"
# 136: with FIC_ALLOW_MNT_C=1 and a different package.json there is no fallback any more: stale dependencies are realigned
# (it used to be "ripiego: dipendenze stantie"; the fallback stays for what cannot be realigned, see 7b and cases 1, 4, 8, 13)
echo '{"name":"ui","v":2}' > "$A/packages/ui/package.json"
FIC_ALLOW_MNT_C=1 vf tests/a.test.ts
check "package.json di un pacchetto diverso + FIC_ALLOW_MNT_C=1 -> riallineata, gira nella copia" '[ "$(rc)" = 0 ] && grep -q "dipendenze cambiate" "$T/out" && grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && ! grep -q ripiego "$T/out"'
echo '{"name":"ui"}' > "$A/packages/ui/package.json"

# 8. copy busy -> it WAITS for the lock and runs in the copy, it does not fall back (counterproof: flock -n -> red)
( flock 9; sleep 3 ) 9>"$M/.fic-lock" & holder=$!
sleep 1
t0=$SECONDS
vf tests/a.test.ts
el=$((SECONDS - t0))
check "copia occupata -> attende e gira nella copia" '[ "$(rc)" = 0 ] && grep -q "esito=PASS luogo=copia" "$T/out" && grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && ! grep -q ripiego "$T/out" && [ "$el" -ge 1 ]'
wait $holder
( flock 9; sleep 4 ) 9>"$M/.fic-lock" & holder=$!
sleep 1
FIC_LOCK_WAIT=1 vf tests/a.test.ts
check "copia occupata oltre FIC_LOCK_WAIT -> BLOCKED exit 3, nessun ripiego" '[ "$(rc)" = 3 ] && grep -q "esito=BLOCKED (copia non utilizzabile: copia occupata" "$T/out" && [ ! -f "$FAKE_LOG" ]'
FIC_ALLOW_MNT_C=1 FIC_LOCK_WAIT=1 vf tests/a.test.ts
check "  con FIC_ALLOW_MNT_C=1 -> ripiego dichiarato" 'grep -q "luogo=mnt-c (ripiego: copia occupata" "$T/out" && grep -qx "cwd=$A/apps/admin" "$FAKE_LOG" && grep -q "esito=PASS luogo=mnt-c (ripiego dichiarato: FIC_ALLOW_MNT_C=1)" "$T/out"'
wait $holder

# 9. snapshot written during the run -> BLOCKED, exit 4
FAKE_WRITE=$M/apps/admin/tests/__snapshots__/a.test.ts.snap vf tests/a.test.ts
check "snapshot nuova scritta -> BLOCKED exit 4" '[ "$(rc)" = 4 ] && grep -q "esito=BLOCKED (snapshot da generare su /mnt/c" "$T/out"'
check "  la snapshot non arriva nell'origine" '[ ! -e "$A/apps/admin/tests/__snapshots__" ]'
vf tests/a.test.ts
check "  il run dopo la ripulisce (--delete)" '[ ! -e "$M/apps/admin/tests/__snapshots__/a.test.ts.snap" ] && [ "$(rc)" = 0 ]'

# 10. inline snapshot (test file of the manifest rewritten) -> BLOCKED
FAKE_WRITE=$M/apps/admin/tests/a.test.ts vf tests/a.test.ts
check "snapshot inline in un .test.ts -> BLOCKED" '[ "$(rc)" = 4 ] && grep -q "apps/admin/tests/a.test.ts" "$T/out"'

# 11. vitest failure: exit code propagated, esito FAIL
FAKE_RC=1 vf tests/a.test.ts
check "test rosso -> FAIL, exit 1" '[ "$(rc)" = 1 ] && grep -q "esito=FAIL luogo=copia" "$T/out"'

# 12. the destination does not move with the arguments (now the option is rejected before running)
vf --dest /tmp/altro tests/a.test.ts
check "nessun argomento cambia la destinazione" '[ "$(rc)" = 64 ] && [ ! -e /tmp/altro ] && [ ! -f "$FAKE_LOG" ]'

# 13. git unusable (manifest not computable) -> fallback, not a reduced check
mv "$R/.git" "$R/.git.via"
vf tests/a.test.ts
check "senza git -> BLOCKED exit 3, non una verifica ridotta" '[ "$(rc)" = 3 ] && grep -q "copia non utilizzabile: manifest non calcolabile" "$T/out" && [ ! -f "$FAKE_LOG" ]'
FIC_ALLOW_MNT_C=1 vf tests/a.test.ts
check "  con FIC_ALLOW_MNT_C=1 -> ripiego dichiarato" 'grep -q "ripiego: manifest non calcolabile" "$T/out" && grep -qx "cwd=$A/apps/admin" "$FAKE_LOG"'
mv "$R/.git.via" "$R/.git"

# 14. lint: CI perimeter (apps/admin), extensions, cwd, opt-in cache, map of exit codes
mkdir -p "$A/packages/ui" "$A/packages/stores" "$A/apps/admin/utils" "$A/apps/admin/.nuxt"
echo '{"compilerOptions":{}}' > "$A/apps/admin/.nuxt/tsconfig.json"   # generated by nuxi: needed by lint
echo 'export const y = 1' > "$A/apps/admin/utils/x.ts"
echo 'export const z = 1' > "$A/packages/ui/i.ts"; echo 'export const w = 1' > "$A/packages/stores/s.ts"
echo '# doc' > "$A/apps/admin/docs.md"
(cd "$R" && git add -A && git commit -qm lint)
vf --lint modules/app/apps/admin/utils/x.ts
check "lint: gira nella copia, cwd del gruppo, path relativo al gruppo" 'grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && grep -qx "args=eslint --quiet utils/x.ts" "$FAKE_LOG"'
check "  esito PASS" '[ "$(rc)" = 0 ] && grep -q "esito=PASS luogo=copia" "$T/out"'
check "  il tsconfig generato da nuxi arriva nella copia" '[ -f "$M/apps/admin/.nuxt/tsconfig.json" ]'
vf --lint --cache modules/app/apps/admin/utils/x.ts
check "lint --cache: cache alla radice della copia" 'grep -q -- "--cache --cache-location $M/.fic-eslintcache-apps-admin" "$FAKE_LOG"'
vf --lint modules/app/apps/admin/utils/x.ts
check "lint senza --cache: nessun --cache a eslint" '! grep -q -- "--cache" "$FAKE_LOG"'
vf --lint modules/app/packages/ui/i.ts modules/app/packages/stores/s.ts modules/db/seeds/seed.ts modules/app/apps/admin/docs.md
check "fuori perimetro (ui, stores, altro modulo, .md) -> SKIPPED senza eseguire" '[ "$(rc)" = 0 ] && grep -q "esito=SKIPPED (fuori dalla radice del modulo" "$T/out" && [ ! -f "$FAKE_LOG" ]'
check "  i path fuori perimetro sono elencati" 'grep -q "packages/ui/i.ts" "$T/out" && grep -q "modules/db/seeds/seed.ts" "$T/out"'
vf --lint modules/app/apps/admin/utils/x.ts modules/app/packages/ui/i.ts
check "misto: linta admin e dichiara lo scarto" 'grep -qx "args=eslint --quiet utils/x.ts" "$FAKE_LOG" && grep -q "packages/ui/i.ts" "$T/out"'
vf --lint modules/app/apps/admin/utils/x.ts modules/app/apps/admin/utils/gone.ts
check "file eliminato: non arriva a eslint, dichiarato; l'esistente e' lintato -> PASS" '[ "$(rc)" = 0 ] && grep -qx "args=eslint --quiet utils/x.ts" "$FAKE_LOG" && ! grep -q "gone.ts" "$FAKE_LOG" && grep -q "eliminati nel working tree" "$T/out" && grep -q "apps/admin/utils/gone.ts" "$T/out"'
vf --lint modules/app/apps/admin/utils/gone.ts
check "solo file eliminati -> SKIPPED senza eseguire" '[ "$(rc)" = 0 ] && grep -q "esito=SKIPPED (solo file eliminati)" "$T/out" && [ ! -f "$FAKE_LOG" ]'
FAKE_RC=1 vf --lint modules/app/apps/admin/utils/x.ts
check "eslint esce 1 -> FAIL" '[ "$(rc)" = 1 ] && grep -q "esito=FAIL luogo=copia" "$T/out"'
FAKE_RC=2 vf --lint modules/app/apps/admin/utils/x.ts
check "eslint esce 2 (configurazione) -> BLOCKED, mai FAIL" '[ "$(rc)" = 2 ] && grep -q "esito=BLOCKED (eslint" "$T/out"'
FAKE_RC=2 vf tests/a.test.ts
check "  ma per vitest il 2 resta FAIL" 'grep -q "esito=FAIL luogo=copia" "$T/out"'
mv "$A/apps/admin/.nuxt/tsconfig.json" "$A/apps/admin/.nuxt/tsconfig.via"
vf --lint modules/app/apps/admin/utils/x.ts
check "senza il file guida dei preparati (tsconfig generato) -> BLOCKED col rimedio, non un ripiego (su /mnt/c mancherebbe uguale)" '[ "$(rc)" = 2 ] && grep -q "esito=BLOCKED (preparato assente: modules/app/apps/admin/.nuxt/tsconfig.json; eseguire .npx nuxi prepare. in modules/app/apps/admin" "$T/out" && [ ! -f "$FAKE_LOG" ]'
mv "$A/apps/admin/.nuxt/tsconfig.via" "$A/apps/admin/.nuxt/tsconfig.json"

# 15. robustness of the arguments and cache in the fallback
check "--lint senza path -> 64" 'tfr --lint >/dev/null 2>&1; [ $? -eq 64 ]'
check "--lint --cache senza path -> 64" 'tfr --lint --cache >/dev/null 2>&1; [ $? -eq 64 ]'
check "path non relativo al repository -> 64, non SKIPPED" 'tfr --lint /mnt/c/x/apps/admin/utils/x.ts >/dev/null 2>&1; [ $? -eq 64 ]'
echo 'export const y = 2' > "$A/apps/admin/utils/x.ts"   # real divergence: the fake sync does not bring it over
FIC_ALLOW_MNT_C=1 FAKE_CP_NOOP=1 FAKE_RSYNC_NOOP=1 vf --lint --cache modules/app/apps/admin/utils/x.ts
check "ripiego con --cache: nessuna cache scritta nel repository" 'grep -q "ripiego: copia non allineata" "$T/out" && ! ls "$A"/.fic-eslintcache-* >/dev/null 2>&1 && ! grep -q -- "--cache" "$FAKE_LOG"'
check "  e il ripiego linta i path relativi al gruppo" 'grep -qx "args=eslint --quiet utils/x.ts" "$FAKE_LOG" && grep -qx "cwd=$A/apps/admin" "$FAKE_LOG"'

# 16. paths only, never options: they would end up verbatim in the runner's command line
vf --passWithNoTests tests/a.test.ts
check "opzione di vitest come argomento -> 64" '[ "$(rc)" = 64 ] && grep -q "solo path, niente opzioni" "$T/out" && [ ! -f "$FAKE_LOG" ]'
vf --lint --fix modules/app/apps/admin/utils/x.ts
check "opzione di eslint come argomento -> 64" '[ "$(rc)" = 64 ] && [ ! -f "$FAKE_LOG" ]'
vf /etc/passwd
check "path assoluto -> 64" '[ "$(rc)" = 64 ] && grep -q "path assoluto" "$T/out"'
vf ../fuori/a.test.ts
check "segmento .. nel path -> 64" '[ "$(rc)" = 64 ] && grep -q "non ammesso nel path" "$T/out"'
vf --lint --base modules/app/apps/admin/utils/x.ts
check "--base senza riferimento -> 64" '[ "$(rc)" = 64 ]'

# 17. lint outside apps/admin: PREEXISTING / INTRODUCED / UNRESOLVED
echo 'module.exports = {}' > "$A/packages/ui/.eslintrc.js"     # ui is lintable, stores is not
echo 'export const nuovo = 1' > "$A/packages/ui/i.ts"
echo 'export const vecchio = 1 // BADOLD' > "$A/packages/ui/old.ts"
(cd "$R" && git add -A && git commit -qm base-extra)
B0=$(cd "$R" && git rev-parse HEAD)

vf --lint --base "$B0" modules/app/packages/stores/s.ts
check "pacchetto senza configurazione eslint -> SKIPPED, non UNRESOLVED" '[ "$(rc)" = 0 ] && grep -q "senza configurazione eslint" "$T/out" && grep -q "esito=SKIPPED" "$T/out"'
vf --lint modules/app/packages/ui/old.ts
check "fuori perimetro senza --base -> SKIPPED dichiarato, nessun eslint" '[ "$(rc)" = 0 ] && grep -q "manca --base" "$T/out" && [ ! -f "$FAKE_LOG" ]'
vf --lint --base "$B0" modules/app/packages/ui/old.ts
check "errore gia nella base -> PREEXISTING, non bloccante" '[ "$(rc)" = 0 ] && grep -q "PREEXISTING" "$T/out" && ! grep -q "INTRODUCED" "$T/out"'
check "  due passate di eslint: contenuto attuale e contenuto della base" '[ "$(grep -c "args=eslint" "$FAKE_LOG.all")" = 2 ]'
echo 'export const nuovo = 1 // BADNEW' > "$A/packages/ui/i.ts"
vf --lint --base "$B0" modules/app/packages/ui/i.ts
check "errore assente nella base -> INTRODUCED, exit 1" '[ "$(rc)" = 1 ] && grep -q "INTRODUCED" "$T/out" && grep -q "esito=FAIL" "$T/out"'
check "  la copia torna al contenuto attuale, non resta quello della base" 'grep -q BADNEW "$M/packages/ui/i.ts"'
check "  ripristino prima dello stamp: nessun BLOCKED da scrittura" '! grep -q "ha scritto nella copia" "$T/out"'
vf --lint --base "$B0" modules/app/packages/ui/old.ts
check "  il run successivo non ripiega: copia rimasta allineata" 'grep -q "luogo=copia" "$T/out"'
echo 'export const p = 1 // BADP' > "$A/packages/ui/nuovo.ts"
vf --lint --base "$B0" modules/app/packages/ui/nuovo.ts
check "file assente nella base -> tutto INTRODUCED" '[ "$(rc)" = 1 ] && grep -q "BADP" "$T/out"'
rm "$A/packages/ui/nuovo.ts"
vf --lint --base "$B0" modules/app/packages/ui/i.ts modules/app/packages/ui/old.ts
check "INTRODUCED + PREEXISTING insieme -> exit 1, entrambi dichiarati" '[ "$(rc)" = 1 ] && grep -q "PREEXISTING" "$T/out" && grep -q "INTRODUCED" "$T/out"'
vf --lint --base "$B0" modules/app/apps/admin/utils/x.ts modules/app/packages/ui/i.ts
check "gate admin verde + INTRODUCED fuori perimetro -> FAIL" '[ "$(rc)" = 1 ] && grep -qx "args=eslint --quiet utils/x.ts" "$FAKE_LOG"'
vf --lint --base deadbeef99deadbeef99 modules/app/packages/ui/old.ts
check "base non risolvibile -> UNRESOLVED exit 3, mai PASS" '[ "$(rc)" = 3 ] && grep -q "esito=UNRESOLVED" "$T/out"'
FAKE_RC=2 vf --lint --base "$B0" modules/app/packages/ui/old.ts
check "eslint uscita 2 fuori perimetro -> UNRESOLVED exit 3" '[ "$(rc)" = 3 ] && grep -q "UNRESOLVED" "$T/out"'
echo 'export const nuovo = 3 // BADNEW' > "$A/packages/ui/i.ts"   # real divergence from the fake sync
FIC_ALLOW_MNT_C=1 FAKE_CP_NOOP=1 FAKE_RSYNC_NOOP=1 vf --lint --base "$B0" modules/app/packages/ui/i.ts
check "ripiego -> UNRESOLVED exit 3, nessuna classificazione" '[ "$(rc)" = 3 ] && grep -q "NON classificati (ripiego" "$T/out"'
check "  nel ripiego non si scrive nel repository" 'grep -q "nuovo = 3" "$A/packages/ui/i.ts"'

# 18. the FILE NAME counts: the very same message, but in another file of the group
echo 'export const a = 1 // BADDUP' > "$A/packages/ui/dup_a.ts"
echo 'export const b = 1' > "$A/packages/ui/dup_b.ts"
(cd "$R" && git add -A && git commit -qm dup-base)
B1=$(cd "$R" && git rev-parse HEAD)
echo 'export const a = 1' > "$A/packages/ui/dup_a.ts"            # resolved here
echo 'export const b = 1 // BADDUP' > "$A/packages/ui/dup_b.ts"  # and introduced there
vf --lint --base "$B1" modules/app/packages/ui/dup_a.ts modules/app/packages/ui/dup_b.ts
check "stesso messaggio in un ALTRO file -> INTRODUCED, non PREEXISTING" '[ "$(rc)" = 1 ] && grep -q "INTRODUCED" "$T/out" && ! grep -q "PREEXISTING" "$T/out"'
check "  e la riga dice in quale file" 'grep -q "dup_b.ts" "$T/out"'

# 19. fallback WITHOUT --base: stays SKIPPED as on the copy path, not BLOCKED
echo 'export const b = 2 // BADDUP' > "$A/packages/ui/dup_b.ts"
FIC_ALLOW_MNT_C=1 FAKE_CP_NOOP=1 FAKE_RSYNC_NOOP=1 vf --lint modules/app/packages/ui/dup_b.ts
check "ripiego senza --base -> SKIPPED, non UNRESOLVED" '[ "$(rc)" = 0 ] && grep -q "manca --base" "$T/out" && ! grep -q UNRESOLVED "$T/out"'

# 20. two groups in a single invocation: reset between groups and precedence INTRODUCED > UNRESOLVED
mkdir -p "$A/packages/comp"
echo '{"name":"comp"}' > "$A/packages/comp/package.json"
echo 'module.exports = {}' > "$A/packages/comp/.eslintrc.js"
echo 'export const c = 1 // CFGERR' > "$A/packages/comp/c.ts"
(cd "$R" && git add -A && git commit -qm due-gruppi)
B2=$(cd "$R" && git rev-parse HEAD)
tfr --setup > /dev/null 2>&1   # new package.json = new fingerprint
echo 'export const b = 1 // BADDUE' > "$A/packages/ui/dup_b.ts"
vf --lint --base "$B2" modules/app/packages/ui/dup_b.ts modules/app/packages/comp/c.ts
check "due gruppi: INTRODUCED (exit 1) batte UNRESOLVED dell'altro gruppo" '[ "$(rc)" = 1 ] && grep -q INTRODUCED "$T/out" && grep -q UNRESOLVED "$T/out"'

# 21. eslint broken ONLY on the base pass (the branch after the swap)
echo 'export const d = 1 // CFGERR' > "$A/packages/ui/onlybase.ts"
(cd "$R" && git add -A && git commit -qm base-rotta)
B3=$(cd "$R" && git rev-parse HEAD)
echo 'export const d = 1' > "$A/packages/ui/onlybase.ts"
vf --lint --base "$B3" modules/app/packages/ui/onlybase.ts
check "eslint rotto solo sulla base -> UNRESOLVED exit 3" '[ "$(rc)" = 3 ] && grep -q "sulla base non eseguibile" "$T/out"'

# 22. death during the swap: the trap must restore the copy
echo 'export const k = 1 // KILLME' > "$A/packages/ui/killer.ts"
(cd "$R" && git add -A && git commit -qm killer)
B4=$(cd "$R" && git rev-parse HEAD)
echo 'export const k = 1' > "$A/packages/ui/killer.ts"
vf --lint --base "$B4" modules/app/packages/ui/killer.ts
check "morte durante lo scambio: il trap rimette il contenuto attuale" '! grep -q KILLME "$M/packages/ui/killer.ts"'
vf --lint --base "$B4" modules/app/packages/ui/onlybase.ts
check "  e il run successivo non ripiega" 'grep -q "luogo=copia" "$T/out"'

# 23. --setup and --base do not swallow a path
check "--setup insieme ad altri argomenti -> 64" 'tfr --lint --setup modules/app/apps/admin/utils/x.ts >/dev/null 2>&1; [ $? -eq 64 ]'
check "--base con un path al posto del riferimento -> 64" '(cd "$R" && tfr --lint --base modules/app/apps/admin/utils/x.ts modules/app/apps/admin/utils/x.ts) >/dev/null 2>&1; [ $? -eq 64 ]'

# 24. the count tells classified and skipped apart
vf --lint --base "$B4" modules/app/packages/ui/onlybase.ts modules/app/packages/stores/s.ts
check "conteggio: classificati su totale" 'grep -q "1 classificati su 2" "$T/out"'

# 25. destination derived from the root (pt03): main tree -> ~/fic-mirror, linked worktree ->
#     ~/fic-mirror-<12 hex of the sha256 of the root>, which does not touch the copy of the main tree.
#     Counterproof: fixed destination -> the worktree cases turn red.
vf tests/a.test.ts
check "tree principale -> ~/fic-mirror" '[ "$(rc)" = 0 ] && grep -qx "cwd=$HOME/fic-mirror/modules/app/apps/admin" "$FAKE_LOG"'
printf '*.sh text eol=lf\n' > "$R/.gitattributes"   # as in the real repository: the script stays LF in the worktree
(cd "$R" && git add -A && git commit -qm pre-worktree)
W=$T/wt
# autocrlf=true: the worktree is born with CRLF line endings, the main tree has LF (the measured case).
# No node_modules in the worktree, as in a freshly created worktree.
(cd "$R" && git -c core.autocrlf=true worktree add -q -b wt "$W") > /dev/null 2>&1
mhash() { printf '%s' "$1" | sha256sum | cut -c1-12; }
WM=$HOME/fic-mirror-$(mhash "$(git -C "$W" rev-parse --show-toplevel)")/modules/app
mainsum() { (cd "$HOME/fic-mirror" && find . -type f | LC_ALL=C sort | xargs -d '\n' sha256sum); }
mainsum > "$T/main-before"
vfw() { rm -f "$FAKE_LOG" "$FAKE_LOG.all"; tfin "$W/modules/app/apps/admin" "$@" > "$T/out" 2>&1; echo $? > "$T/rc"; }
ino() { stat -c %i "$1" 2>/dev/null; }
check "premessa: worktree con CRLF e senza node_modules, tree principale con LF" 'grep -q $'"'"'\r'"'"' "$W/modules/app/package.json" && ! grep -q $'"'"'\r'"'"' "$A/package.json" && [ ! -e "$W/modules/app/node_modules" ]'
vfw tests/a.test.ts
check "worktree al primo uso -> copia ~/fic-mirror-<hash> seminata da ~/fic-mirror, gira li'" '[ "$(rc)" = 0 ] && grep -q "seminata" "$T/out" && grep -qx "cwd=$WM/apps/admin" "$FAKE_LOG" && grep -q "esito=PASS luogo=copia" "$T/out"'
check "  node_modules in hardlink (stesso inode della copia principale)" '[ -n "$(ino "$WM/node_modules/dep/index.js")" ] && [ "$(ino "$WM/node_modules/dep/index.js")" = "$(ino "$HOME/fic-mirror/modules/app/node_modules/dep/index.js")" ]'
check "stessa impronta delle dipendenze con fine riga diverse (LF nel tree principale, CRLF nel worktree)" 'cmp -s "$HOME/fic-mirror/modules/app/.fic-deps" "$WM/.fic-deps"'
echo 'export const x = 99' > "$W/modules/app/apps/admin/src.ts"
vfw tests/a.test.ts
check "worktree -> gira in ~/fic-mirror-<hash>, col contenuto del worktree" '[ "$(rc)" = 0 ] && grep -qx "cwd=$WM/apps/admin" "$FAKE_LOG" && grep -qx "src=export const x = 99" "$FAKE_LOG" && grep -q "esito=PASS luogo=copia" "$T/out"'
vfw --dest /tmp/altro tests/a.test.ts
check "  dal worktree nessun argomento la cambia (--dest -> 64)" '[ "$(rc)" = 64 ] && [ ! -e /tmp/altro ] && [ ! -f "$FAKE_LOG" ]'
mainsum > "$T/main-after"
check "  la copia del tree principale non e' stata toccata" 'cmp -s "$T/main-before" "$T/main-after"'
# .fic-deps from before the rule (fingerprint of the bytes): stays valid as long as the bytes do not change
rawfp=$(cd "$W/modules/app" && find . \( -name node_modules -o -name .nuxt -o -name .output \) -prune -o \
  \( -name package.json -o -name package-lock.json \) -type f -print | LC_ALL=C sort |
  while IFS= read -r f; do printf '%s  %s\n' "$(sha256sum < "$f" | cut -c1-64)" "$f"; done | sha256sum | cut -c1-64)
check "premessa: impronta dei byte diversa da quella normalizzata" '[ "$rawfp" != "$(cat "$WM/.fic-deps")" ]'
echo "$rawfp" > "$WM/.fic-deps"
vfw tests/a.test.ts
check ".fic-deps legacy (byte) ancora accettato" '[ "$(rc)" = 0 ] && grep -q "esito=PASS luogo=copia" "$T/out"'

# 26. deletion of a worktree's copy (replay.sh at the end of a replay): never the one of the main tree
fo=$( . "$HP/scripts/fic-mirror.sh"; fic_mirror_forget "$W" )
check "fic_mirror_forget: copia del worktree cancellata" '[ ! -e "${WM%/modules/app}" ] && printf "%s" "$fo" | grep -q "copia cancellata"'
check "  la copia del tree principale (node_modules in hardlink compresi) e' intatta" 'mainsum > "$T/main-after2"; cmp -s "$T/main-before" "$T/main-after2"'
fo=$( . "$HP/scripts/fic-mirror.sh"; fic_mirror_forget "$R"; echo "rc=$?" )
check "  sul tree principale: rifiuto, niente cancellato" 'printf "%s" "$fo" | grep -q "rifiuto" && printf "%s" "$fo" | grep -q "rc=1" && [ -d "$HOME/fic-mirror/modules/app/node_modules" ]'
# 26b. lane copies (harness-pt13): fic_lane_forget deletes only <copy of the root>-<k>
WL=${WM%/modules/app}-1; mkdir -p "$WL/modules/app/node_modules" "$HOME/fic-mirror-2/modules/app"
fo=$( . "$HP/scripts/fic-mirror.sh"; fic_lane_forget "$W" 1; echo "rc=$?" )
check "fic_lane_forget: copia della corsia 1 del worktree cancellata" '[ ! -e "$WL" ] && printf "%s" "$fo" | grep -q "copia della corsia cancellata" && printf "%s" "$fo" | grep -q "rc=0"'
fo=$( . "$HP/scripts/fic-mirror.sh"; fic_lane_forget "$R" 2; echo "rc=$?" )
check "  corsia 2 del tree principale (~/fic-mirror-2) cancellata, ~/fic-mirror intatta" '[ ! -e "$HOME/fic-mirror-2" ] && printf "%s" "$fo" | grep -q "rc=0" && { mainsum > "$T/main-after3"; cmp -s "$T/main-before" "$T/main-after3"; }'
fo=$( . "$HP/scripts/fic-mirror.sh"; fic_lane_forget "$R" x; echo "rc=$?" )
check "  corsia non valida: rifiuto, niente cancellato" 'printf "%s" "$fo" | grep -q "rc=1" && [ -d "$HOME/fic-mirror/modules/app/node_modules" ]'

# 27. --setup of a worktree without node_modules: seeded (no installs)
tfin "$W/modules/app/apps/admin" --setup > "$T/out" 2>&1; echo $? > "$T/rc"
check "--setup dal worktree senza node_modules -> semina da ~/fic-mirror, exit 0" '[ "$(rc)" = 0 ] && [ -f "$WM/node_modules/dep/index.js" ] && [ -s "$WM/.fic-deps" ] && grep -q "hardlink" "$T/out"'
vfw tests/a.test.ts
check "  e poi gira nella copia del worktree" '[ "$(rc)" = 0 ] && grep -qx "cwd=$WM/apps/admin" "$FAKE_LOG"'

# 28. worktree dependencies different from those of the main tree: no seeding, BLOCKED with the reason
W2=$T/wt2
(cd "$R" && git worktree add -q -b wt2 "$W2") > /dev/null 2>&1
echo '{"lock":"altro"}' > "$W2/modules/app/package-lock.json"
WM2=$HOME/fic-mirror-$(mhash "$(git -C "$W2" rev-parse --show-toplevel)")/modules/app
rm -f "$FAKE_LOG"; tfin "$W2/modules/app/apps/admin" tests/a.test.ts > "$T/out" 2>&1; echo $? > "$T/rc"
check "dipendenze diverse -> nessuna semina, BLOCKED copia assente con il motivo" '[ "$(rc)" = 3 ] && grep -q "copia assente: eseguire --setup; semina da ~/fic-mirror non possibile: dipendenze del worktree diverse" "$T/out" && [ ! -e "$WM2/node_modules" ] && [ ! -f "$FAKE_LOG" ]'

# 29. worktree created by Git for Windows: the .git says "gitdir: C:/…", which the WSL git does not resolve. Simulated:
#     FIC_WSL_MNT=<drives root> with <root>/c -> /, and the .git rewritten with the path "C:/…".
W3=$T/wt3
(cd "$R" && git worktree add -q -b wt3 "$W3") > /dev/null 2>&1
g3=$(sed -n 's/^gitdir: //p' "$W3/.git")
mkdir -p "$T/mnt"; ln -s / "$T/mnt/c"
printf 'gitdir: C:%s\n' "$g3" > "$W3/.git"
check "premessa: git non legge il worktree col gitdir C:/…" '! git -C "$W3" rev-parse --show-toplevel >/dev/null 2>&1'
WM3=$HOME/fic-mirror-$(mhash "$W3")/modules/app
rm -f "$FAKE_LOG"; FIC_WSL_MNT=$T/mnt tfin "$W3/modules/app/apps/admin" tests/a.test.ts > "$T/out" 2>&1; echo $? > "$T/rc"
check "gitdir C:/… tradotto: copia ~/fic-mirror-<hash> del worktree, manifest calcolato, PASS" '[ "$(rc)" = 0 ] && grep -qx "cwd=$WM3/apps/admin" "$FAKE_LOG" && grep -q "esito=PASS luogo=copia" "$T/out"'
check "  e la copia del tree principale resta intatta" 'mainsum > "$T/main-after3"; cmp -s "$T/main-before" "$T/main-after3"'

# 29b. worktree WITHOUT node_modules, dependencies changed the same way in both trees: the copy of the main tree
#      realigns from the main tree (under ITS lock), then the worktree copy is seeded again as hardlinks
cp "$A/package-lock.json" "$T/lock.main"; cp "$W/modules/app/package-lock.json" "$T/lock.wt"
echo '{"lock":"c"}' > "$A/package-lock.json"; echo '{"lock":"c"}' > "$W/modules/app/package-lock.json"
echo 'c' > "$A/node_modules/dep/c.js"
vfw tests/a.test.ts
check "worktree senza node_modules: dipendenze cambiate -> riseminata, gira nella copia del worktree" '[ "$(rc)" = 0 ] && grep -q "^vitest-fast: dipendenze cambiate (impronta [0-9a-f]* -> [0-9a-f]*): copia riseminata da ~/fic-mirror (node_modules in hardlink)$" "$T/out" && grep -qx "cwd=$WM/apps/admin" "$FAKE_LOG" && grep -q "esito=PASS luogo=copia" "$T/out"'
check "  copia del tree principale riallineata prima, con avviso" 'grep -q "^fic-mirror: copia del tree principale ($M) stantia: copia riallineata dall" "$T/out" && [ "$(cat "$M/.fic-deps")" = "$(fp "$A")" ]'
check "  impronta del worktree registrata, node_modules nuovi in hardlink" '[ "$(cat "$WM/.fic-deps")" = "$(fp "$W/modules/app")" ] && [ -n "$(ino "$WM/node_modules/dep/c.js")" ] && [ "$(ino "$WM/node_modules/dep/c.js")" = "$(ino "$M/node_modules/dep/c.js")" ]'
# worktree with dependencies DIFFERENT from those of the main tree and without node_modules: no seed source -> BLOCKED
echo '{"lock":"solo-wt"}' > "$W/modules/app/package-lock.json"
vfw tests/a.test.ts
check "  dipendenze del worktree diverse, nessuna fonte -> BLOCKED exit 3 col motivo" '[ "$(rc)" = 3 ] && grep -q "dipendenze stantie, riallineamento automatico non riuscito: l'"'"'origine non ha node_modules e le sue dipendenze sono diverse" "$T/out" && [ ! -f "$FAKE_LOG" ]'
cp "$T/lock.main" "$A/package-lock.json"; cp "$T/lock.wt" "$W/modules/app/package-lock.json"; rm -f "$A/node_modules/dep/c.js"

# 29c. LANE copy (FIC_LANE): dependencies changed -> copy of the root realigned (under its lock), then
#      the lane is seeded again from it, as hardlinks
LM=$HOME/fic-mirror-1/modules/app
FIC_LANE=1 vf tests/a.test.ts
check "premessa: corsia 1 seminata al primo uso" '[ "$(rc)" = 0 ] && grep -qx "cwd=$LM/apps/admin" "$FAKE_LOG" && [ -s "$LM/.fic-deps" ]'
echo '{"lock":"corsia"}' > "$A/package-lock.json"; echo 'l' > "$A/node_modules/dep/l.js"
mkdir -p "$LM/packages/ui/node_modules/vecchio"; echo v > "$LM/packages/ui/node_modules/vecchio/i.js"   # orphan: it is not in the seed source
FIC_LANE=1 vf tests/a.test.ts
check "corsia: node_modules annidati assenti nella fonte cancellati, gli altri restano" '[ ! -e "$LM/packages/ui/node_modules" ] && [ -f "$LM/node_modules/dep/index.js" ]'
check "corsia: dipendenze cambiate -> radice riallineata, corsia riseminata, gira nella corsia" '[ "$(rc)" = 0 ] && grep -q "^vitest-fast: dipendenze cambiate (impronta [0-9a-f]* -> [0-9a-f]*): copia della corsia riseminata da $HOME/fic-mirror (node_modules in hardlink)$" "$T/out" && grep -qx "cwd=$LM/apps/admin" "$FAKE_LOG"'
check "  impronte aggiornate, node_modules nuovi in hardlink dalla copia della radice" '[ "$(cat "$M/.fic-deps")" = "$(fp "$A")" ] && [ "$(cat "$LM/.fic-deps")" = "$(fp "$A")" ] && [ -n "$(ino "$LM/node_modules/dep/l.js")" ] && [ "$(ino "$LM/node_modules/dep/l.js")" = "$(ino "$M/node_modules/dep/l.js")" ]'
cp "$T/lock.main" "$A/package-lock.json"; rm -f "$A/node_modules/dep/l.js"

# 30. INCREMENTAL sync (harness-pt06): state per copy, alignment on the manifest diff, generated files cleaned
#     only when needed, equivalence guard. Two mutation counterproofs, run here on a copy
#     of the script next to the original (same root): cache that ignores the stat -> the guard turns
#     red; ctime removed from the key -> a file rewritten with the same size and mtime is not realigned.
vf tests/a.test.ts
check "stato del sync nella copia, non nell'origine" '[ -s "$M/.fic-sync-src" ] && [ -s "$M/.fic-sync-gen" ] && [ ! -e "$A/.fic-sync-src" ]'
vf tests/a.test.ts
check "nessun cambiamento -> sync incrementale, 0 file allineati" '[ "$(rc)" = 0 ] && grep -q "sync=incrementale (0 file allineati)" "$T/out"'
echo 'export const x = 30' > "$A/apps/admin/src.ts"
vf tests/a.test.ts
check "file modificato -> 1 file allineato, il runner vede il contenuto nuovo" 'grep -q "sync=incrementale (1 file allineati)" "$T/out" && grep -qx "src=export const x = 30" "$FAKE_LOG"'
echo 'export const x = 666' > "$M/apps/admin/src.ts"
vf tests/a.test.ts
check "scrittura nella copia da fuori (counterproof, run interrotto) -> riallineata dal diff" 'grep -q "1 file allineati" "$T/out" && grep -qx "src=export const x = 30" "$FAKE_LOG"'
printf 'a\n' > "$A/apps/admin/tests/con spazio.ts"; printf 'b\n' > "$A/apps/admin/tests/back\\slash.ts"
vf tests/a.test.ts
check "path con spazio e con backslash: copiati, senza risincronizzazione" '[ "$(cat "$M/apps/admin/tests/con spazio.ts")" = a ] && [ "$(cat "$M/apps/admin/tests/back\\slash.ts")" = b ] && ! grep -q risincronizzazione "$T/out"'
vf tests/a.test.ts
check "  e al run dopo manifest identico: niente da allineare" 'grep -q "sync=incrementale (0 file allineati)" "$T/out"'
rm -f "$A/apps/admin/tests/con spazio.ts" "$A/apps/admin/tests/back\\slash.ts"
vf tests/a.test.ts
check "  cancellati nell'origine: spariscono dalla copia" '[ ! -e "$M/apps/admin/tests/con spazio.ts" ] && [ ! -e "$M/apps/admin/tests/back\\slash.ts" ] && grep -q "2 file allineati" "$T/out"'
k0=$(stat -c '%s %.9Y' "$A/apps/admin/src.ts"); touch -r "$A/apps/admin/src.ts" "$T/ref"
echo 'export const x = 31' > "$A/apps/admin/src.ts"; touch -r "$T/ref" "$A/apps/admin/src.ts"
check "premessa: riscritto con stessa dimensione e stesso mtime" '[ "$(stat -c "%s %.9Y" "$A/apps/admin/src.ts")" = "$k0" ]'
vf tests/a.test.ts
check "  -> riallineato comunque (ctime nella chiave)" 'grep -qx "src=export const x = 31" "$FAKE_LOG"'
mkdir -p "$M/apps/admin/.nuxt"; echo g > "$M/apps/admin/.nuxt/marker"
vf tests/a.test.ts
check ".nuxt della copia NON ripulito a ogni run" '[ "$(rc)" = 0 ] && [ -f "$M/apps/admin/.nuxt/marker" ] && ! grep -q "generati della copia ripuliti" "$T/out"'
echo '{"compilerOptions":{"strict":true}}' > "$A/apps/admin/.nuxt/tsconfig.json"
vf tests/a.test.ts
check "  ripulito quando cambia il tsconfig generato dell'origine" '[ ! -e "$M/apps/admin/.nuxt/marker" ] && grep -q "generati della copia ripuliti" "$T/out"'
mkdir -p "$M/apps/admin/.nuxt"; echo g > "$M/apps/admin/.nuxt/marker"
echo '{"name":"admin","v":30}' > "$A/apps/admin/package.json"
tfr --setup > /dev/null 2>&1
vf tests/a.test.ts
check "  e quando cambia l'impronta delle dipendenze (--setup)" '[ "$(rc)" = 0 ] && [ ! -e "$M/apps/admin/.nuxt/marker" ]'
echo 'export const x = "ROSSO"' > "$A/apps/admin/src.ts"
FIC_SYNC_EQUIV=1 vf tests/a.test.ts
check "guardia di equivalenza: incrementale e completo, stesso manifest e stessa uscita" 'grep -q "equivalenza=OK" "$T/out" && [ "$(rc)" = 1 ] && grep -q "esito=FAIL luogo=copia" "$T/out"'
# Counterproofs 1 and 2 isolate the cache: the audit (section 31) would catch them first, so here it is off.
vfm() { rm -f "$FAKE_LOG"; FIC_SYNC_AUDIT_RUNS=${FIC_SYNC_AUDIT_RUNS:-100000} FIC_SYNC_AUDIT_SECS=${FIC_SYNC_AUDIT_SECS:-999999} \
  tfin_mut "$@" > "$T/out" 2>&1; echo $? > "$T/rc"; }
# counterproof 1: the cache reuses the recorded sha without looking at the stat
sed 's/(\$0 in ck) \&\& ck\[\$0\] == s\[\$0\]/($0 in ck)/' "$HP/scripts/test-fast.sh" > "$HP/scripts/vf-mut.sh"
check "premessa: mutazione 1 applicata" '! cmp -s "$HP/scripts/test-fast.sh" "$HP/scripts/vf-mut.sh"'
echo 'export const x = "verde"' > "$A/apps/admin/src.ts"; vf tests/a.test.ts
echo 'export const x = "ROSSO!"' > "$A/apps/admin/src.ts"
FIC_SYNC_EQUIV=1 vfm tests/a.test.ts
check "controprova 1: file cambiato non riallineato -> equivalenza=DIFF, BLOCKED exit 3" '[ "$(rc)" = 3 ] && grep -q "equivalenza=DIFF" "$T/out" && grep -q "esito=BLOCKED (equivalenza violata" "$T/out"'
# counterproof 2: without ctime in the key, the rewrite with the same size and mtime goes unnoticed
sed 's/%\.9Y %\.9Z %i/%.9Y %i/' "$HP/scripts/test-fast.sh" > "$HP/scripts/vf-mut.sh"
check "premessa: mutazione 2 applicata" '! cmp -s "$HP/scripts/test-fast.sh" "$HP/scripts/vf-mut.sh"'
echo 'export const x = 40' > "$A/apps/admin/src.ts"; vfm tests/a.test.ts
k0=$(stat -c '%s %.9Y' "$A/apps/admin/src.ts"); touch -r "$A/apps/admin/src.ts" "$T/ref"
echo 'export const x = 41' > "$A/apps/admin/src.ts"; touch -r "$T/ref" "$A/apps/admin/src.ts"
vfm tests/a.test.ts
check "controprova 2: senza ctime il contenuto vecchio resta nella copia" 'grep -qx "src=export const x = 40" "$FAKE_LOG"'
rm -f "$HP/scripts/vf-mut.sh"
vf tests/a.test.ts
check "  e lo script vero lo riallinea" 'grep -qx "src=export const x = 41" "$FAKE_LOG"'

# 31. safety net of the cache (full audit every FIC_SYNC_AUDIT_RUNS runs or FIC_SYNC_AUDIT_SECS seconds):
#     POISONED cache — the current stat of the changed file with the old sha, i.e. the premise that does not hold.
#     Without the audit the run uses the old content (the hole); with the audit it finds it, warns and resyncs.
#     Mutation counterproof (here): audit never due -> even with the thresholds at zero the content stays old.
export FIC_SYNC_AUDIT_RUNS=1000 FIC_SYNC_AUDIT_SECS=999999
echo 'export const x = 50' > "$A/apps/admin/src.ts"; vf tests/a.test.ts
check "premessa: stato dell'audit nella copia" '[ -s "$M/.fic-sync-audit" ] && grep -qx "src=export const x = 50" "$FAKE_LOG"'
avvelena() {  # <new content>: writes the source, then caches the NEW stat with the OLD sha
  local old; old=$(awk -F'\t' '$3 == "apps/admin/src.ts" { print $2 }' "$M/.fic-sync-src")
  echo "$1" > "$A/apps/admin/src.ts"
  local k; k=$(cd "$A" && stat -L --printf '%s %.9Y %.9Z %i' apps/admin/src.ts)
  awk -F'\t' -v OFS='\t' -v k="$k" -v h="$old" '$3 == "apps/admin/src.ts" { $1 = k; $2 = h } { print }' "$M/.fic-sync-src" > "$T/cache" &&
    cp "$T/cache" "$M/.fic-sync-src"
}
avvelena 'export const x = 51'
vf tests/a.test.ts
check "cache avvelenata senza audit -> contenuto vecchio, in silenzio (la falla che l'audit copre)" 'grep -qx "src=export const x = 50" "$FAKE_LOG" && [ "$(rc)" = 0 ]'
avvelena 'export const x = 52'
FIC_SYNC_AUDIT_RUNS=1 vf tests/a.test.ts
check "audit per numero di run -> scoperta, avviso, resync completo, contenuto nuovo" 'grep -q "vitest-fast: cache stat incompleta, resync completo" "$T/out" && grep -q "sync=completo" "$T/out" && grep -qx "src=export const x = 52" "$FAKE_LOG" && [ "$(rc)" = 0 ]'
check "  e la cache ricostruita ha lo sha vero" '[ "$(awk -F"\t" "\$3 == \"apps/admin/src.ts\" { print \$2 }" "$M/.fic-sync-src")" = "$(sha256sum < "$A/apps/admin/src.ts" | cut -c1-64)" ]'
avvelena 'export const x = 53'
FIC_SYNC_AUDIT_SECS=0 vf tests/a.test.ts
check "audit per eta' (FIC_SYNC_AUDIT_SECS) -> scoperta anche cosi'" 'grep -q "cache stat incompleta" "$T/out" && grep -qx "src=export const x = 53" "$FAKE_LOG"'
vf tests/a.test.ts; vf tests/a.test.ts
check "senza soglie raggiunte nessun audit: il contatore sale" '[ "$(cut -d" " -f2 "$M/.fic-sync-audit")" = 2 ] && ! grep -q "cache stat incompleta" "$T/out"'
FIC_SYNC_AUDIT_RUNS=1 vf tests/a.test.ts
check "audit che non trova differenze: nessun avviso, contatore azzerato, sync incrementale" '! grep -q "cache stat incompleta" "$T/out" && grep -q "sync=incrementale" "$T/out" && [ "$(cut -d" " -f2 "$M/.fic-sync-audit")" = 0 ]'
sed 's/^audit_dovuto() {$/audit_dovuto() { return 1/' "$HP/scripts/test-fast.sh" > "$HP/scripts/vf-mut.sh"
check "premessa: mutazione 3 applicata" '! cmp -s "$HP/scripts/test-fast.sh" "$HP/scripts/vf-mut.sh"'
avvelena 'export const x = 54'
FIC_SYNC_AUDIT_RUNS=1 FIC_SYNC_AUDIT_SECS=0 vfm tests/a.test.ts
check "controprova 3: senza audit la cache avvelenata passa inosservata" 'grep -qx "src=export const x = 53" "$FAKE_LOG" && ! grep -q "cache stat incompleta" "$T/out"'
rm -f "$HP/scripts/vf-mut.sh"
# CORRUPTED audit state (thresholds still far): it counts as "audit due", never a death without outcome
statovalido() { grep -Eqx '[0-9]+ [0-9]+' "$M/.fic-sync-audit"; }
for bad in 'abc def' '1.5 2'; do
  vf tests/a.test.ts                                  # start from a valid state and from aligned content
  printf '%s\n' "$bad" > "$M/.fic-sync-audit"; avvelena "export const x = 6${#bad}"
  vf tests/a.test.ts
  check "stato audit '$bad' + cache avvelenata -> audit: avviso, contenuto nuovo, riga esito=, stato riscritto valido" \
    'grep -q "cache stat incompleta, resync completo" "$T/out" && grep -qx "src=export const x = 6${#bad}" "$FAKE_LOG" && grep -q "^vitest-fast: esito=PASS luogo=copia" "$T/out" && [ "$(rc)" = 0 ] && statovalido'
done
avvelena 'export const x = 70'; rm -f "$M/.fic-sync-audit"
vf tests/a.test.ts
check "stato audit cancellato con la cache presente -> audit" 'grep -q "cache stat incompleta" "$T/out" && grep -qx "src=export const x = 70" "$FAKE_LOG" && statovalido'
FIC_SYNC_AUDIT_RUNS=venti FIC_SYNC_AUDIT_SECS=x vf tests/a.test.ts
check "soglie non numeriche -> default, nessuna morte" '[ "$(rc)" = 0 ] && grep -q "^vitest-fast: esito=PASS" "$T/out" && statovalido'
# counterproof 4: without the validation the state 'abc def' kills the script without an outcome line
sed 's/^  if \[\[ \$ep =~ .*$/  AUD_EP=${ep:-0}; AUD_NR=${nr:-0}/' "$HP/scripts/test-fast.sh" > "$HP/scripts/vf-mut.sh"
check "premessa: mutazione 4 applicata" '! cmp -s "$HP/scripts/test-fast.sh" "$HP/scripts/vf-mut.sh"'
printf 'abc def\n' > "$M/.fic-sync-audit"; avvelena 'export const x = 71'
FIC_SYNC_AUDIT_RUNS=1000 FIC_SYNC_AUDIT_SECS=999999 vfm tests/a.test.ts
check "controprova 4: senza validazione 'abc def' -> nessuna riga esito=, contenuto nuovo mai visto" '! grep -q "^vitest-fast: esito=" "$T/out" && ! grep -qx "src=export const x = 71" "$FAKE_LOG" 2>/dev/null'
rm -f "$HP/scripts/vf-mut.sh" "$M/.fic-sync-audit"
unset FIC_SYNC_AUDIT_RUNS FIC_SYNC_AUDIT_SECS

# 33. maat.json (pk04b-1): deprecated wrapper, no self-invocation, alternatives of copia.lint, module choice,
#     lint_base, packages directory of fic-mirror.sh from the caller.
vf tests/a.test.ts; cp "$T/out" "$T/out.tf"
rm -f "$FAKE_LOG" "$FAKE_LOG.all"; (cd "$A/apps/admin" && bash "$HP/scripts/vitest-fast.sh" tests/a.test.ts) > "$T/out" 2>&1; echo $? > "$T/rc"
check "involucro vitest-fast.sh -> test-fast.sh: stesso comando nella copia, stesso esito" '[ "$(rc)" = 0 ] && grep -qx "args=vitest run tests/a.test.ts" "$FAKE_LOG" && grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && [ "$(tail -1 "$T/out")" = "$(tail -1 "$T/out.tf")" ]'
check "niente autorichiamo: dentro la copia un solo comando, il runner di copia.test" '[ "$(wc -l < "$FAKE_LOG.all")" = 1 ] && grep -q "args=vitest run tests/a.test.ts" "$FAKE_LOG.all" && [ "$(grep -c "^vitest-fast: luogo=" "$T/out")" = 1 ]'
vf --lint altro/apps/admin/utils/x.ts
check "path che contiene la radice senza esservi ancorato -> 64, non SKIPPED" '[ "$(rc)" = 64 ] && grep -q "path non relativo al repository" "$T/out"'
echo 'export default 1' > "$A/apps/admin/lint-baseline.mjs"; (cd "$R" && git add -A && git commit -qm baseline)
vf --lint modules/app/apps/admin/utils/x.ts
check "copia.lint, lint-baseline.mjs nella copia -> prima alternativa: npm run -s lint dalla radice, CI=true" '[ "$(rc)" = 0 ] && grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && grep -qx "args=npm run -s lint -- utils/x.ts" "$FAKE_LOG" && grep -qx "CI=true" "$FAKE_LOG"'
vf --lint --cache modules/app/apps/admin/utils/x.ts
check "  con --cache: {cache?…} alla radice della copia" 'grep -qx "args=npm run -s lint -- --cache --cache-location $M/.fic-eslintcache-apps-admin utils/x.ts" "$FAKE_LOG"'
rm "$A/apps/admin/lint-baseline.mjs"; (cd "$R" && git add -A && git commit -qm via-baseline)
vf --lint modules/app/apps/admin/utils/x.ts
check "  senza lint-baseline.mjs -> seconda alternativa: npx eslint --quiet" '[ "$(rc)" = 0 ] && grep -qx "args=eslint --quiet utils/x.ts" "$FAKE_LOG"'
. "$HP/scripts/python.sh" 2>/dev/null || true
varia() { "$FIC_PY" -c "import json, sys
c = json.load(open(sys.argv[1], encoding='utf-8'))
$1
json.dump(c, open(sys.argv[2], 'w', encoding='utf-8'))" "$R/.claude/maat.json" "$2"; }
varia 'm = dict(c["moduli"][0]); m["nome"] = "fe2"; m["radice"] = "modules/app/packages/ui"; c["moduli"].append(m)' "$T/due.json"
MAAT_CONFIG=$T/due.json vf tests/a.test.ts
check "due moduli con copia, senza MAAT_MODULO -> exit 64, nessun runner" '[ "$(rc)" = 64 ] && grep -q "moduli con copia: imposta MAAT_MODULO" "$T/out" && [ ! -f "$FAKE_LOG" ]'
MAAT_CONFIG=$T/due.json MAAT_MODULO=fe vf tests/a.test.ts
check "  con MAAT_MODULO=fe -> il modulo fe, PASS nella copia" '[ "$(rc)" = 0 ] && grep -qx "cwd=$M/apps/admin" "$FAKE_LOG" && grep -q "esito=PASS luogo=copia" "$T/out"'
MAAT_CONFIG=$T/due.json MAAT_MODULO=be vf tests/a.test.ts
check "  MAAT_MODULO di un modulo senza copia -> exit 64" '[ "$(rc)" = 64 ] && [ ! -f "$FAKE_LOG" ]'
varia 'm = c["moduli"][0]; m["lint_base"] = False; m["comandi"]["lint"]["comando"] = "bash {maat}/scripts/test-fast.sh --lint {file}"' "$T/nobase.json"
MAAT_CONFIG=$T/nobase.json vf --lint --base "$B4" modules/app/packages/ui/onlybase.ts
check "lint_base false: fuori dalla radice SKIPPED anche con --base, nessuna classificazione" '[ "$(rc)" = 0 ] && grep -q "esito=SKIPPED" "$T/out" && ! grep -q "PREEXISTING\|INTRODUCED\|classificati" "$T/out" && [ ! -f "$FAKE_LOG" ]'
# the guide file requirement comes from the module's `preparati` (pk04b-2), not from a hard-coded .nuxt/tsconfig.json: a
# module that does not declare them lints even without that file. Counterproof: the old hard-coded check => BLOCKED.
varia 'm = c["moduli"][0]; m.pop("preparati", None)' "$T/noprep.json"
mv "$A/apps/admin/.nuxt/tsconfig.json" "$A/apps/admin/.nuxt/tsconfig.via"
MAAT_CONFIG=$T/noprep.json vf --lint modules/app/apps/admin/utils/x.ts
check "modulo senza preparati: il lint gira senza file guida (nessun requisito cablato)" '[ "$(rc)" = 0 ] && grep -q "esito=PASS luogo=copia" "$T/out" && grep -qx "args=eslint --quiet utils/x.ts" "$FAKE_LOG"'
sed 's|^    if \[ -n "\$GUIDA" \] && \[ ! -f "\$SRC\$G/\$GUIDA" \]; then$|    if [ ! -f "$SRC$G/.nuxt/tsconfig.json" ]; then|' "$HP/scripts/test-fast.sh" > "$HP/scripts/vf-mut-prep.sh"
if cmp -s "$HP/scripts/test-fast.sh" "$HP/scripts/vf-mut-prep.sh"; then check "controprova preparati: la mutazione non si applica" false
else
  rm -f "$FAKE_LOG"; (cd "$R" && MAAT_CONFIG=$T/noprep.json bash "$HP/scripts/vf-mut-prep.sh" --lint modules/app/apps/admin/utils/x.ts) > "$T/out" 2>&1; echo $? > "$T/rc"
  check "  controprova: col controllo cablato il modulo senza preparati esce BLOCKED (il caso sopra discrimina)" '[ "$(rc)" = 2 ] && grep -q "esito=BLOCKED (preparato assente" "$T/out"'
fi
rm -f "$HP/scripts/vf-mut-prep.sh"; mv "$A/apps/admin/.nuxt/tsconfig.via" "$A/apps/admin/.nuxt/tsconfig.json"
fo=$( . "$HP/scripts/fic-mirror.sh"; fic_mirror_init "$W" && fic_seed_node_modules "$W/modules/app" "$T/altrove/modules/app"; echo "rc=$?" )
check "fic-mirror: copia fuori da \$FIC_MIRROR -> rifiuto col motivo, nessuna cartella indovinata" 'printf "%s" "$fo" | grep -q "rc=1" && printf "%s" "$fo" | grep -q "copia fuori da" && [ ! -e "$T/altrove" ]'

# 32. DRVFS PROBE: the cache premise on the real /mnt/c filesystem (not on the temporary ext4 of the cases
#     above). Scratch file in the root of the REAL repository (not in the copy, outside modules/app, hence
#     outside the manifest), deleted at the end. (1) rewrite from WSL with the same size and the mtime restored;
#     (2) write from WINDOWS (powershell.exe) with the same size and the mtime restored by Windows itself. In
#     both cases the stat read from WSL must change, otherwise the cache can lie: red.
#     WHAT IT PROVES: in the scenario "rewrite with the same size and restore the mtime" the cache key
#     (size, mtime, ctime, inode) changes, on this machine. WHAT IT DOES NOT PROVE: that writing the data alone
#     updates the ctime — here restoring the mtime touches it too, and the two effects cannot be separated. The defence
#     against a write that does not change the key stays the full audit (section 31), not this probe.
REPO=$(cd "$HERE/../.." && pwd)
case "$REPO" in
  /mnt/?/*)
    P=$REPO/.fic-drvfs-probe.$$; trap 'rm -rf "$T"; rm -f "$P"' EXIT
    key() { stat -L --printf '%s %.9Y %.9Z %i' "$P"; }
    sm() { stat -L --printf '%s %.9Y' "$P"; }
    # mtime on a whole second: on drvfs `touch` does not keep the nanoseconds (measured: .610972600 -> .000000000),
    # and the "same mtime" premise must be true, not approximate
    printf 'aaaa' > "$P"; touch -d "@$(date +%s)" "$P"; touch -r "$P" "$T/ref"; k0=$(key); s0=$(sm)
    sleep 1.1; printf 'bbbb' > "$P"; touch -r "$T/ref" "$P"
    check "drvfs (1): riscrittura da WSL, stessa dimensione e mtime -> premessa rispettata" '[ "$(sm)" = "$s0" ]'
    check "drvfs (1): la stat (ctime) cambia" '[ "$(key)" != "$k0" ]'
    echo "test-fast.test.sh: sonda drvfs (1) prima=[$k0] dopo=[$(key)]"
    if command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
      WP=$(wslpath -w "$P"); k1=$(key); s1=$(sm)
      sleep 1.1
      powershell.exe -NoProfile -Command "\$p='$WP'; \$t=[IO.File]::GetLastWriteTimeUtc(\$p); [IO.File]::WriteAllText(\$p,'cccc'); [IO.File]::SetLastWriteTimeUtc(\$p,\$t)" > /dev/null 2>&1
      check "drvfs (2): scritto da Windows" '[ "$(cat "$P")" = cccc ]'
      check "drvfs (2): stessa dimensione e mtime (rimesso da Windows)" '[ "$(sm)" = "$s1" ]'
      check "drvfs (2): la stat letta da WSL cambia" '[ "$(key)" != "$k1" ]'
      echo "test-fast.test.sh: sonda drvfs (2) prima=[$k1] dopo=[$(key)]"
    else
      echo "test-fast.test.sh: SKIP sonda drvfs (2): powershell.exe o wslpath assenti"
    fi
    rm -f "$P" ;;
  *) echo "test-fast.test.sh: SKIP sonda drvfs: il repository non sta su /mnt/<unita'> ($REPO)" ;;
esac

echo "test-fast.test.sh: $((n - fail))/$n ok"
[ $fail -eq 0 ]
