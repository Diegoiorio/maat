#!/usr/bin/env bash
# maat-doctor.test.sh — tests of maat-doctor.sh (pk06) on a synthetic project in a temporary folder.
#   bash plugins/maat/scripts/maat-doctor.test.sh          (Git Bash or WSL)
# The synthetic project: piattaforma.copia_wsl no (no WSL checks on the test machine), a nativo module with
# tests and checks, a guard with a production regex and its probe, the plugin enabled in enabledPlugins, the
# working folder; temporary HOME and USERPROFILE (on Windows the real VS Code extension does not beat the stub) and a
# `claude` stub on PATH that prints the pk01 version. Code review (round 1): claude lookup like
# run-phase.sh; {python} missing; se_presente; schema_db_comando, verifica_remota, guardia.suite missing; cd … && and
# env -u; python -I against the project files; and, loading the Python part as a module («unità»), the probes of the
# WSL copy and of the absolute path of a wsl module.
# Plan cases: complete => exit 0 · no maat.json => MANCA «lancia /maat:setup» · nonexistent test command =>
# MANCA · fake Python 3.8 => MANCA · duplicate hook => ATTENZIONE · tampered guard => MANCA · neither plugin nor hook =>
# MANCA «guardia non agganciata». Notes from the targeted review: nonexistent copia_anche => MANCA; copia_wsl auto, nativo
# modules, PATH without wsl => exit 0 «WSL assente» (Windows only); wsl module without WSL => MANCA; uncovered probe =>
# MANCA; invalid configuration => the guard is MANCA «configurazione non valida»; read-only (hash of the project
# and of the plugin before and after, without --prova-test). pk08: counterproof tools (rsync/flock missing => OK
# «di ripiego»; sha256sum, timeout, rsync and tar together => ATTENZIONE BLOCKED). Mutation counterproofs at the end: the doctor is copied with the plugin
# into a temporary folder, a sed mutates it, and the case the mutation must break turns red.
# 1.6.0 block F (D9): the Python threshold is fic_py_min_ok of python.sh (fake 3.9 MANCA, 3.10 OK; a python.sh with
# another threshold moves the doctor too); FIC_DRIVER not empty => ATTENZIONE (empty or unset: no line); on macOS (a fake
# uname in PATH) GNU sed, grep and stat, sha256sum, timeout and flock, a BSD sed or grep or a missing flock => MANCA with
# the brew command; outside macOS no line about them.
set -uo pipefail
export MAAT_LINGUA=it   # 1.4.0: the suite asserts the Italian text ("lingua": "it")
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(dirname "$HERE")
DOC=$HERE/maat-doctor.sh
. "$HERE/python.sh" || true
[ -n "${FIC_PY:-}" ] || { echo "maat-doctor.test.sh: nessun Python utilizzabile" >&2; exit 2; }
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8
unset FIC_DRIVER MAAT_CONFIG FIC_REPO PROJECT_ROOT MAAT_ROOT CLAUDE_BIN FIC_PHASE FIC_GATES_VENV_PY FIC_SESSION_GUARD CLAUDE_PROJECT_DIR
export FIC_PYTHON=$FIC_PY   # the same interpreter even with the reduced PATH
pass=0 fail=0
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; sed 's/^/    /' "$T/out" 2>/dev/null; fi; }
cygm() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
WIN=0; case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in *msys*|*cygwin*|*:MINGW*|*:MSYS*|*:CYGWIN*) WIN=1 ;; esac
# 1.6.0: a folder is left out also when its listing has a wsl entry that `-e` does not see (an app execution alias of
# WindowsApps is a reparse point: Git Bash does not stat it, Python's shutil.which finds it; on some CI runners)
PATH_SENZA_WSL=$(out=""; IFS=:; for d in $PATH; do { [ -e "$d/wsl.exe" ] || [ -e "$d/wsl" ] || ls -A "$d" 2>/dev/null | grep -qixE 'wsl(\.exe)?'; } && continue; out+="${out:+:}$d"; done; printf '%s' "$out")

mkdir -p "$T/bin" "$T/home/.claude" "$T/py38"
printf '#!/bin/sh\necho "2.1.285 (Claude Code)"\n' > "$T/bin/claude"
printf '#!/bin/sh\necho 3.8.10\n' > "$T/py38/python"
chmod +x "$T/bin/claude" "$T/py38/python"

# --- synthetic project ------------------------------------------------------------------------------------------------
P=$T/p
mkdir -p "$P/.claude/.ai-workflow" "$P/dati"
cat > "$P/.claude/maat.json" <<'EOF'
{"versione_schema": 1, "piattaforma": {"copia_wsl": "no"},
 "moduli": [{"nome": "m", "radice": ".", "comandi": {"test": "bash run-test.sh {report} {test}"}, "report": "junit",
             "controlli": [{"glob": "**/*.sh", "comando": "bash -n {file}"}]}],
 "guardia": {"produzione": ["prod[.]esempio[.]it"], "sonde": ["prod.esempio.it"]}}
EOF
echo '{"enabledPlugins": {"maat@prova": true}}' > "$P/.claude/settings.json"
printf '#!/bin/sh\nexit 0\n' > "$P/run-test.sh"
: > "$P/run-test.py"
: > "$P/a.test.js"
: > "$P/dati/x"
(cd "$P" && git init -q && git -c core.autocrlf=false add -A && git -c user.email=t@t -c user.name=t commit -qm init) || { echo "repo sintetico non creato" >&2; exit 2; }
CFG=$P/.claude/maat.json

variante() { # <name> <Python code on c> -> varied maat.json file (outside the project)
  "$FIC_PY" -c 'import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
exec(sys.argv[3])
json.dump(c, open(sys.argv[2], "w", encoding="utf-8"))' "$(cygm "$CFG")" "$(cygm "$T/$1.json")" "$2"
  printf '%s' "$(cygm "$T/$1.json")"
}
doc() { # [VAR=value…] -- [arguments]: the doctor from project $DP (default $P), output in $T/out, exit code in rc
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  (cd "${DP:-$P}" && env HOME="$T/home" USERPROFILE="$T/home" PATH="$T/bin:${DPATH:-$PATH}" ${envs[@]+"${envs[@]}"} bash "${DOCX:-$DOC}" "$@") > "$T/out" 2>&1
  rc=$?
}
ha() { grep -qE -- "$1" "$T/out"; }

# --- 1. complete ---------------------------------------------------------------------------------------------------------
caso_completo() { DOCX=${1:-} doc; [ "$rc" = 0 ] && ! ha '^MANCA' && ha '^OK Claude Code 2\.1\.285' && ha '^OK guardia: «git push --force origin prova» negato in fase e chiesto in sessione' && ha '^OK guardia: sonda di produzione «curl -s https://prod\.esempio\.it/»'; }
check "progetto sintetico completo -> exit 0, nessun MANCA, guardia provata" 'caso_completo'

# --- 2. without maat.json ------------------------------------------------------------------------------------------------
cp -r "$P" "$T/p0"; rm "$T/p0/.claude/maat.json"
DP=$T/p0 doc
check "senza maat.json -> MANCA «lancia /maat:setup», exit 1" '[ "$rc" = 1 ] && ha "^MANCA maat\.json assente .* — lancia /maat:setup"'

# --- 3. nonexistent test command -------------------------------------------------------------------------------------------
V=$(variante test-assente 'c["moduli"][0]["comandi"]["test"] = "comando-inesistente-maat {test}"')
doc MAAT_CONFIG="$V"
check "comando di test inesistente -> MANCA, exit 1" '[ "$rc" = 1 ] && ha "^MANCA comando test del modulo m: comando-inesistente-maat non trovato"'

# --- 3b. 1.6.0 block Z, D-B: tests without a readable report -> ATTENZIONE with the remedy (exit unchanged) -----------
VR=$(variante senza-report 'del c["moduli"][0]["report"]')
doc MAAT_CONFIG="$VR"
check "D-B: comando di test senza report -> ATTENZIONE «report nessuno» con il rimedio, exit 0" '[ "$rc" = 0 ] && ha "^ATTENZIONE modulo m: test senza un report leggibile \(report nessuno\): .*BLOCKED a test-red — metti \"report\": \"junit\" nel modulo"'
doc MAAT_CONFIG="$VR" MAAT_LINGUA=en
check "D-B en: WARNING «report none» in inglese" 'ha "^WARNING module m: tests without a readable report \(report none\): .*BLOCKED at test-red — set \"report\": \"junit\" on the module"'
VR2=$(variante report-vitest 'c["moduli"][0]["report"] = "vitest"')
doc MAAT_CONFIG="$VR2"
check "D-B: con report vitest nessuna ATTENZIONE sul report" '[ "$rc" = 0 ] && ! ha "report nessuno"'
VR3=$(variante senza-test 'del c["moduli"][0]["report"]; del c["moduli"][0]["comandi"]["test"]')
doc MAAT_CONFIG="$VR3"
check "D-B: modulo senza comando di test -> nessuna ATTENZIONE sul report" '! ha "report nessuno"'

# --- 4. fake Python 3.8 --------------------------------------------------------------------------------------------------
doc FIC_PYTHON="$(cygm "$T/py38/python")"
check "Python finto 3.8 -> MANCA, exit 1" '[ "$rc" = 1 ] && ha "^MANCA Python 3\.8\.10 sotto la 3\.10"'

# --- 4b. 1.6.0 block F (D9 a): the Python threshold is fic_py_min_ok of python.sh (3.9 no, 3.10 yes) -------------------
# A fake Python: the two version questions (python.sh <major>.<minor>, the doctor <major>.<minor>.<micro>) get
# PY_FINTO, every other call goes to the real interpreter (config, guard, units).
mkdir -p "$T/pyf"
{ printf '#!/bin/sh\n'
  printf 'case "$*" in *version_info*) case "$*" in *%%d.%%d.%%d*) echo "$PY_FINTO.0" ;; *) echo "$PY_FINTO" ;; esac; exit 0 ;; esac\n'
  printf 'exec %s "$@"\n' "'$FIC_PY'"; } > "$T/pyf/python"
chmod +x "$T/pyf/python"
caso_py39() { DOCX=${1:-} doc FIC_PYTHON="$(cygm "$T/pyf/python")" PY_FINTO=3.9; [ "$rc" = 1 ] && ha "^MANCA Python 3\.9\.0 sotto la 3\.10"; }
caso_py310() { DOCX=${1:-} doc FIC_PYTHON="$(cygm "$T/pyf/python")" PY_FINTO=3.10; [ "$rc" = 0 ] && ha "^OK Python 3\.10\.0 " && ! ha '^MANCA'; }
check "1.6.0: Python finto 3.9 -> MANCA «sotto la 3.10», exit 1 (soglia di python.sh)" 'caso_py39'
check "1.6.0: Python finto 3.10 (il confine) -> OK, exit 0" 'caso_py310'

# --- 4c. 1.6.0 block F (D9 b): FIC_DRIVER set (not empty, the rule of driver.py run) -> ATTENZIONE ------------------------
caso_fic_driver() { DOCX=${1:-} doc FIC_DRIVER=0; [ "$rc" = 0 ] && ha "^ATTENZIONE FIC_DRIVER=0 è impostata ma dalla Maat 1\.6\.0 non ha più effetto: decide il driver Python — toglila dall'ambiente; per il motore bash reinstalla la Maat 1\.5\.1"; }
check "1.6.0: FIC_DRIVER=0 -> ATTENZIONE «non ha più effetto … reinstalla la Maat 1.5.1», exit 0" 'caso_fic_driver'
doc FIC_DRIVER=1 MAAT_LINGUA=en
check "1.6.0 en: FIC_DRIVER=1 -> WARNING in inglese" '[ "$rc" = 0 ] && ha "^WARNING FIC_DRIVER=1 is set but has no effect since Maat 1\.6\.0: the Python driver decides — remove it from the environment; for the bash engine reinstall Maat 1\.5\.1"'
doc FIC_DRIVER=
check "1.6.0: FIC_DRIVER vuota (il predefinito della 1.5.1) -> nessuna riga" '[ "$rc" = 0 ] && ! ha "FIC_DRIVER"'
doc
check "1.6.0: FIC_DRIVER non impostata -> nessuna riga" '[ "$rc" = 0 ] && ! ha "FIC_DRIVER"'

# --- 4d. 1.6.0 block F (D9 c): macOS (uname -s = Darwin from a fake in PATH): the GNU tools from Homebrew -------------------
mkdir -p "$T/darwin" "$T/bsdsed" "$T/bsdgrep" "$T/gnufinti"
printf '#!/bin/sh\n[ "$1" = -s ] && { echo Darwin; exit 0; }\nexec %s "$@"\n' "'$(command -v uname)'" > "$T/darwin/uname"
# BSD sed refuses --version; BSD grep says «BSD grep, GNU compatible» (not «(GNU »); both run the real one otherwise
printf '#!/bin/sh\n[ "$1" = --version ] && { echo "sed: illegal option -- -" >&2; exit 1; }\nexec %s "$@"\n' "'$(command -v sed)'" > "$T/bsdsed/sed"
printf '#!/bin/sh\n[ "$1" = --version ] && { echo "grep (BSD grep, GNU compatible) 2.6.0-FreeBSD"; exit 0; }\nexec %s "$@"\n' "'$(command -v grep)'" > "$T/bsdgrep/grep"
chmod +x "$T/darwin/uname" "$T/bsdsed/sed" "$T/bsdgrep/grep"
# a host whose sed, grep or stat is not GNU (Ubuntu 26.04 of the CI: the uutils coreutils, «stat (uutils coreutils)»):
# on the fake macOS that tool answers --version as GNU, and runs the real one otherwise (the premise of the cases below)
for s in sed grep stat; do
  "$s" --version 2>/dev/null </dev/null | head -1 | grep -qF '(GNU ' && continue
  printf '#!/bin/sh\n[ "$1" = --version ] && { echo "%s (GNU coreutils) 9.4"; exit 0; }\nexec %s "$@"\n' "$s" "'$(command -v "$s")'" > "$T/gnufinti/$s"
  chmod +x "$T/gnufinti/$s"
done
MAC_VIA=""   # the presence-only tools missing on this machine: on the fake macOS they are MANCA
for s in sha256sum timeout flock; do command -v "$s" >/dev/null 2>&1 || MAC_VIA+=" $s"; done
caso_mac() { # [doctor]: every tool in the OK line or in a MANCA with brew; the GNU three in the OK line
  local s
  DOCX=${1:-} DPATH="$T/darwin:$T/gnufinti:$PATH" doc
  ha '^OK strumenti GNU per macOS: sed, grep, stat' || return 1
  for s in $MAC_VIA; do ha "^MANCA $s non trovato .* — brew install " || return 1; done
  [ -n "$MAC_VIA" ] || [ "$rc" = 0 ]
}
caso_mac_sed() { DOCX=${1:-} DPATH="$T/darwin:$T/bsdsed:$T/gnufinti:$PATH" doc; [ "$rc" = 1 ] && ha '^MANCA sed GNU non trovato \(macOS: Maat usa le opzioni GNU\) — brew install gnu-sed, poi metti "\$\(brew --prefix\)/opt/gnu-sed/libexec/gnubin" in testa al PATH$' && ! ha '^OK strumenti GNU per macOS: sed'; }
caso_mac_grep() { DOCX=${1:-} DPATH="$T/darwin:$T/bsdgrep:$T/gnufinti:$PATH" doc; [ "$rc" = 1 ] && ha '^MANCA grep GNU non trovato .* — brew install grep, poi metti' && ha '^OK strumenti GNU per macOS: sed, stat'; }
check "1.6.0 macOS (uname finto): sed, grep e stat GNU nella riga OK; gli strumenti assenti qui ($MAC_VIA) MANCA con brew" 'caso_mac'
check "1.6.0 macOS: sed BSD (rifiuta --version) -> MANCA con «brew install gnu-sed» e la cartella gnubin, exit 1" 'caso_mac_sed'
check "1.6.0 macOS: grep BSD («BSD grep, GNU compatible») -> MANCA con «brew install grep»" 'caso_mac_grep'
DPATH="$T/darwin:$T/bsdsed:$T/gnufinti:$PATH" doc MAAT_LINGUA=en
check "1.6.0 macOS en: MISSING in inglese" '[ "$rc" = 1 ] && ha "^MISSING GNU sed not found \(macOS: Maat uses the GNU options\) — brew install gnu-sed, then put"'
senza() { # <tool> -> PATH where each folder holding <tool> is replaced by a folder of symlinks to all its files but <tool>
  local out="" d n f IFS=:
  for d in $PATH; do
    if [ -e "$d/$1" ]; then
      n="$T/senza-$1/$(printf '%s' "$d" | tr '/:' '__')"; mkdir -p "$n"
      for f in "$d"/* "$d"/.[!.]*; do [ -e "$f" ] && [ "${f##*/}" != "$1" ] && ln -s "$f" "$n/" 2>/dev/null; done
      d=$n
    fi
    out+="${out:+:}$d"
  done
  printf '%s' "$out"
}
caso_mac_flock() { DOCX=${1:-} DPATH="$T/darwin:$PATH_SENZA_FLOCK" doc; [ "$rc" = 1 ] && ha '^MANCA flock non trovato \(macOS\) — brew install flock$'; }
if [ "$WIN" = 1 ]; then
  echo "SALTATO [macOS: flock assente]: su Windows i collegamenti simbolici di Git Bash sono copie (cartelle di sistema intere)"
else
  PATH_SENZA_FLOCK=$(senza flock)
  check "1.6.0 macOS: flock assente dal PATH -> MANCA «brew install flock», exit 1" 'caso_mac_flock'
fi
if [ "$(uname -s 2>/dev/null)" = Darwin ]; then
  doc
  check "1.6.0 macOS vero: la riga degli strumenti GNU c'è" 'ha "^OK strumenti GNU per macOS: "'
else
  doc
  check "1.6.0 fuori da macOS (Linux, Windows): nessuna riga sugli strumenti GNU" '[ "$rc" = 0 ] && ! ha "macOS"'
fi

# --- 5. duplicate hook ---------------------------------------------------------------------------------------------------
cp -r "$P" "$T/p5"
cat > "$T/p5/.claude/settings.json" <<'EOF'
{"enabledPlugins": {"maat@prova": true},
 "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "python scripts/guard.py --universal"}]}]}}
EOF
DP=$T/p5 doc
check "plugin abilitato e hook di progetto -> ATTENZIONE hook doppio" 'ha "^ATTENZIONE hook di guardia doppio"'

# --- 6. tampered guard ---------------------------------------------------------------------------------------------------
cp -r "$PLUGIN" "$T/plug6"
printf 'import sys\nsys.exit(0)\n' > "$T/plug6/scripts/guard.py"
DOCX=$T/plug6/scripts/maat-doctor.sh doc
check "guardia che non nega il comando di prova -> MANCA, exit 1" '[ "$rc" = 1 ] && ha "^MANCA guardia: «git push --force origin prova» in fase non negato"'

# --- 7. neither plugin nor hook ------------------------------------------------------------------------------------------
cp -r "$P" "$T/p7"; echo '{}' > "$T/p7/.claude/settings.json"
DP=$T/p7 doc
check "né plugin abilitato né hook di progetto -> MANCA «guardia non agganciata»" '[ "$rc" = 1 ] && ha "^MANCA guardia non agganciata"'

# --- 8. copia_anche ------------------------------------------------------------------------------------------------------
V8=$(variante copia-anche 'c["moduli"][0]["copia_anche"] = ["dati", "non-esiste"]')
caso_copia_anche() { DOCX=${1:-} doc MAAT_CONFIG="$V8"; [ "$rc" = 1 ] && ha "^MANCA copia_anche del modulo m: non-esiste non esiste" && ha "^OK copia_anche del modulo m: dati"; }
check "copia_anche verso una cartella inesistente -> MANCA (e la cartella vera OK)" 'caso_copia_anche'

# --- 9. Windows without WSL: copia_wsl auto, nativo modules --------------------------------------------------------------
V9=$(variante wsl-auto 'c["piattaforma"]["copia_wsl"] = "auto"')
caso_wsl_assente() { DOCX=${1:-} DPATH=$PATH_SENZA_WSL doc MAAT_CONFIG="$V9"; [ "$rc" = 0 ] && ha "^OK WSL assente: copia veloce dei test non disponibile \(wsl\.exe fuori dal PATH\)"; }
caso_piattaforma() { DOCX=${1:-} DPATH=$PATH_SENZA_WSL doc -- --piattaforma; [ "$rc" = 0 ] && [ "$(tr -d '\r' < "$T/out")" = windows-senza-wsl ]; }
if [ "$WIN" = 1 ]; then
  check "copia_wsl auto, moduli nativi, PATH senza wsl -> exit 0 con «WSL assente»" 'caso_wsl_assente'
  caso_wsl_assente || {   # detail of a red: which wsl the Python of the doctor finds on that PATH, and from which folder
    . "$HERE/python.sh" >/dev/null 2>&1
    echo "    wsl per shutil.which con il PATH senza wsl: $(PATH="$T/bin:$PATH_SENZA_WSL" "$FIC_PY" -c 'import shutil; print(shutil.which("wsl"), shutil.which("wsl.exe"))' 2>&1)"; }
  check "--piattaforma con PATH senza wsl -> windows-senza-wsl" 'caso_piattaforma'
else
  echo "SALTATO [WSL assente, --piattaforma windows-senza-wsl]: la piattaforma non è Windows (uname/OSTYPE)"
  DPATH=$PATH doc -- --piattaforma
  check "--piattaforma fuori da Windows -> altro" '[ "$rc" = 0 ] && [ "$(tr -d "\r" < "$T/out")" = altro ]'
fi

# --- 10. wsl module without WSL (or outside Windows) -----------------------------------------------------------------------
V10=$(variante modulo-wsl 'c["moduli"][0]["ambiente"] = "wsl"')
caso_modulo_wsl() {
  DOCX=${1:-} DPATH=$PATH_SENZA_WSL doc MAAT_CONFIG="$V10"
  [ "$rc" = 1 ] || return 1
  if [ "$WIN" = 1 ]; then ha "^MANCA modulo m ambiente: wsl ma WSL assente: i suoi gate saranno BLOCKED — metti \`ambiente: nativo\` o installa WSL"
  else ha "^MANCA modulo m ambiente: wsl fuori da Windows"; fi
}
check "modulo ambiente: wsl senza WSL -> MANCA, exit 1" 'caso_modulo_wsl'

# --- 11. uncovered probe -------------------------------------------------------------------------------------------------
V11=$(variante sonda 'c["guardia"]["sonde"] = ["altro.esempio.org"]')
caso_sonda() { DOCX=${1:-} doc MAAT_CONFIG="$V11"; [ "$rc" = 1 ] && ha "^MANCA sonda non coperta dalla guardia: altro\.esempio\.org" && ha "^ATTENZIONE regola di produzione non provata: prod"; }
check "sonda che nessuna regex di produzione copre -> MANCA" 'caso_sonda'

# --- 12. invalid configuration: the guard is not probed ---------------------------------------------------------------------
V12=$(variante non-valida 'c["versione_schema"] = 99')
doc MAAT_CONFIG="$V12"
check "configurazione non valida -> MANCA maat.json e MANCA guardia «configurazione non valida»" \
  '[ "$rc" = 1 ] && ha "^MANCA maat\.json non valido" && ha "^MANCA guardia non provata: configurazione non valida"'

# --- 13. marketplace from a folder -----------------------------------------------------------------------------------------
mkdir -p "$T/home/.claude/plugins"
echo '{"prova": {"source": {"source": "directory", "path": "x"}}}' > "$T/home/.claude/plugins/known_marketplaces.json"
doc
check "plugin da un marketplace da cartella -> ATTENZIONE «installa da git con un ref»" 'ha "^ATTENZIONE plugin installato da un marketplace da cartella .* — installa da git con un ref"'
rm "$T/home/.claude/plugins/known_marketplaces.json"

# --- 14. --prova-test and --help -------------------------------------------------------------------------------------------
doc -- --prova-test
check "--prova-test: riga dichiarata e test di un file scelto dalla regola" \
  '[ "$rc" = 0 ] && ha "^--prova-test: il comando di test può scrivere cache e coverage" && ha "^OK prova test del modulo m: a\.test\.js, uscita 0"'
doc -- --help
check "--help dichiara che --prova-test esce dalla sola lettura" '[ "$rc" = 0 ] && ha "prova-test" && ha "cache e coverage"'
doc -- --boh
check "opzione sconosciuta -> exit 64" '[ "$rc" = 64 ]'

# --- 15. read-only ---------------------------------------------------------------------------------------------------------
albero() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) | sha256sum | cut -c1-64; }
sola_lettura() { # [doctor]: project and plugin hashes equal before and after, no __pycache__ in the plugin
  local pp pl dir
  dir=$(dirname "$(dirname "${1:-$DOC}")")
  pp=$(albero "$P") pl=$(albero "$dir")
  DOCX=${1:-} doc
  [ "$(albero "$P")" = "$pp" ] && [ "$(albero "$dir")" = "$pl" ] && [ -z "$(find "$dir/scripts" -name __pycache__ 2>/dev/null)" ]
}
check "il doctor senza --prova-test non modifica né il progetto né il plugin" 'sola_lettura'

# --- 16. Claude Code: the order of run-phase.sh (CLAUDE_BIN, VS Code extension, PATH) ------------------------------------
EXT=$T/home-ext/.vscode/extensions/anthropic.claude-code-9.9.9-win32-x64/resources/native-binary
mkdir -p "$EXT"; printf '#!/bin/sh\necho "2.1.100 (Claude Code)"\n' > "$EXT/claude.exe"; chmod +x "$EXT/claude.exe"
caso_claude_ext() { DOCX=${1:-} doc USERPROFILE="$T/home-ext"; ha '^ATTENZIONE Claude Code 2\.1\.100 sotto la 2\.1\.285' && ! ha '^OK Claude Code'; }
check "estensione di VS Code e claude nel PATH -> si verifica l'estensione, come run-phase.sh" 'caso_claude_ext'
blocco_claude() { sed -n '/^CL=\${CLAUDE_BIN:-}$/,/^\[ -n "\$CL" \] || CL=\$(command -v claude/p' "$1"; }
check "la ricerca di claude del doctor è la stessa di run-phase.sh, riga per riga" \
  '[ -n "$(blocco_claude "$DOC")" ] && [ "$(blocco_claude "$DOC")" = "$(blocco_claude "$HERE/run-phase.sh")" ]'

# --- 17. {python} missing, script present: MANCA for the interpreter, no OK line for the command -----------------------------
V17=$(variante python-assente 'c["moduli"][0]["comandi"]["test"] = "{python} run-test.py {test}"; c["moduli"][0]["python"] = "venv-maat-assente/bin/python"')
caso_python_assente() { DOCX=${1:-} doc MAAT_CONFIG="$V17"; [ "$rc" = 1 ] && ha '^MANCA python assente per il modulo m \(' && ! ha '^OK comando test del modulo m'; }
check "{python} assente -> MANCA python, e il comando non risulta OK" 'caso_python_assente'

# --- 18. check with se_presente and the executable missing -> «controllo saltato» -----------------------------------------
V18=$(variante se-presente 'c["moduli"][0]["controlli"] = [{"glob": "**/*.sh", "comando": "shellcheck-maat-assente {file}", "se_presente": "shellcheck-maat-assente"}]')
caso_se_presente() { DOCX=${1:-} doc MAAT_CONFIG="$V18"; [ "$rc" = 0 ] && ha '^ATTENZIONE controllo 0 del modulo m \(\*\*/\*\.sh\): controllo saltato, shellcheck-maat-assente assente'; }
check "controllo con se_presente assente -> ATTENZIONE «controllo saltato», exit 0" 'caso_se_presente'

# --- 19-21. project commands missing ------------------------------------------------------------------------------------------
V19=$(variante schema-db 'c["contesto"] = {"schema_db_comando": "comando-db-maat-assente --schema"}')
caso_schema_db() { DOCX=${1:-} doc MAAT_CONFIG="$V19"; [ "$rc" = 1 ] && ha '^MANCA contesto\.schema_db_comando: comando-db-maat-assente non trovato'; }
check "contesto.schema_db_comando assente -> MANCA" 'caso_schema_db'
V20=$(variante verifica 'c["verifica_remota"] = {"comando": "bash script/verifica-maat-assente.sh"}')
caso_verifica() { DOCX=${1:-} doc MAAT_CONFIG="$V20"; [ "$rc" = 1 ] && ha '^MANCA verifica_remota: script/verifica-maat-assente\.sh non trovato'; }
check "verifica_remota con lo script assente -> MANCA" 'caso_verifica'
V21=$(variante suite 'c["guardia"]["suite"] = [{"script": "suite-maat-assente.sh", "selettori": "pytest"}]')
caso_suite() { DOCX=${1:-} doc MAAT_CONFIG="$V21"; ha '^ATTENZIONE guardia\.suite: script suite-maat-assente\.sh non trovato nel repo'; }
check "guardia.suite con lo script assente -> ATTENZIONE" 'caso_suite'

# --- 22. first executable after a builtin command (cd … &&) and after the env options -----------------------------------------
V22=$(variante catena 'c["moduli"][0]["comandi"]["test"] = "cd dati && FOO=1 env -u BAR ./manca-maat.sh {test}"')
caso_catena() { DOCX=${1:-} doc MAAT_CONFIG="$V22"; [ "$rc" = 1 ] && ha '^MANCA comando test del modulo m: \./manca-maat\.sh non trovato'; }
check "cd dati && env -u BAR ./manca-maat.sh -> MANCA ./manca-maat.sh" 'caso_catena'
V22b=$(variante catena-cd 'c["moduli"][0]["comandi"]["test"] = "cd dati && ../run-test.sh {test}"')
caso_catena_cd() { DOCX=${1:-} doc MAAT_CONFIG="$V22b"; [ "$rc" = 0 ] && ha '^OK comando test del modulo m: \.\./run-test\.sh'; }
check "cd dati && ../run-test.sh -> cercato da dati, OK" 'caso_catena_cd'
V22c=$(variante assegna-sost 'c["moduli"][0]["comandi"]["test"] = "FOO=$(pwd) comando-assente-maat {test}"')
caso_assegna_sost() { DOCX=${1:-} doc MAAT_CONFIG="$V22c"; [ "$rc" = 1 ] && ha '^MANCA comando test del modulo m: comando-assente-maat non trovato'; }
check "FOO=\$(pwd) comando-assente-maat -> l'assegnazione resta intera, MANCA" 'caso_assegna_sost'
V22d=$(variante sottoshell 'c["moduli"][0]["comandi"]["test"] = "( cd dati && ../run-test.sh {test} )"')
caso_sottoshell() { DOCX=${1:-} doc MAAT_CONFIG="$V22d"; [ "$rc" = 0 ] && ha '^OK comando test del modulo m: \.\./run-test\.sh'; }
check "( cd dati && ../run-test.sh ) -> il cd della sottoshell si segue, OK" 'caso_sottoshell'

# --- 23. project files named like a standard library module -------------------------------------------------------------------
cp -r "$P" "$T/p23"
printf 'raise SystemExit("glob.py del progetto")\n' > "$T/p23/glob.py"
printf 'raise SystemExit("contextlib.py del progetto")\n' > "$T/p23/contextlib.py"
caso_stdlib() { DOCX=${1:-} DP=$T/p23 doc; [ "$rc" = 0 ] && ha '^OK maat\.json valido' && ! ha 'del progetto'; }
check "glob.py e contextlib.py nel progetto non sostituiscono la libreria standard (python -I)" 'caso_stdlib'

# --- unità (units): the Python part of the doctor loaded as a module (without running the modes) ------------------------------
unita() { # <doctor> <Python code with ns = the doctor's names> [arguments]
  local d=$1 code=$2; shift 2
  MAAT_ROOT=$(cygm "$(dirname "$(dirname "$d")")") DR_ROOT=$(cygm "$P") DR_WIN=1 MAAT_CONFIG_PY=$(cygm "$PLUGIN/scripts/maat-config.py") \
    "$FIC_PY" -I -B -c 'import re, sys
src = re.split(r"(?m)^#__PYTHON__\r?$", open(sys.argv[1], encoding="utf-8").read(), maxsplit=1)[1]
ns = {"__name__": "maat_doctor_unita"}
exec(compile(src, "maat-doctor.sh", "exec"), ns)
exec(sys.argv[2])' "$(cygm "$d")" "$code" "$@"
}

# 24. WSL copy (the probes run here in bash, with a fake HOME: they are the same ones the doctor sends into WSL)
WH=$T/wh R=$T/wr
mkdir -p "$R" && (cd "$R" && git init -q && : > x && git -c core.autocrlf=false add -A && git -c user.email=t@t -c user.name=t commit -qm init && git worktree add -q "$T/wr-wt" -b wt) >/dev/null 2>&1
# relative gitdir: both Windows git and Linux git can read it (fic_git_env translates only the "C:/…" ones)
g=$(sed -n 's/^gitdir: //p' "$T/wr-wt/.git" | tr -d '\r'); printf 'gitdir: ../wr/.git/worktrees/%s\n' "${g##*/}" > "$T/wr-wt/.git"
stato_copia() { # <doctor> <root>: «<ready> <will-be-seeded>» (si|no)
  local ok sem a b
  { read -r ok; read -r sem; } < <(unita "$1" 'print(ns["prove_copia"](sys.argv[3], sys.argv[4], "pkg")[0]); print(ns["prove_copia"](sys.argv[3], sys.argv[4], "pkg")[1])' "$(cygm "$HERE/fic-mirror.sh")" "$(cygm "$2")" | tr -d '\r')
  a=$(HOME=$WH bash -c "if $ok; then echo si; else echo no; fi" 2>/dev/null)
  b=$(HOME=$WH bash -c "if $sem; then echo si; else echo no; fi" 2>/dev/null)
  printf '%s %s' "$a" "$b"
}
caso_copia() { # [doctor]
  local d=${1:-$DOC} s1 s2 s3 s4
  rm -rf "$WH"; mkdir -p "$WH/fic-mirror/pkg"; : > "$WH/fic-mirror/pkg/.fic-deps"
  s1=$(stato_copia "$d" "$R")                       # only .fic-deps: not ready (test-fast.sh also wants node_modules)
  mkdir -p "$WH/fic-mirror/pkg/node_modules"
  s2=$(stato_copia "$d" "$R")                       # ready
  s3=$(stato_copia "$d" "$T/wr-wt")                 # worktree without its own copy, main one ready: will be seeded
  rm -rf "$WH/fic-mirror"
  s4=$(stato_copia "$d" "$T/wr-wt")                 # nothing to seed from
  [ "$s1 | $s2 | $s3 | $s4" = "no no | si no | no si | no no" ] || { echo "stati: $s1 | $s2 | $s3 | $s4" > "$T/out"; return 1; }
}
check "copia WSL: pronta solo con node_modules e .fic-deps; worktree senza copia e principale pronta -> si seminerà" 'caso_copia'

# 25. wsl module: an absolute path outside /mnt/ is probed with [ -x ] inside WSL, not on the Windows side
V25=$(variante wsl-assoluto 'c["moduli"][0]["ambiente"] = "wsl"; c["moduli"][0]["comandi"]["test"] = "/opt/maat-prova/run {test}"')
caso_wsl_assoluto() { # [doctor]: with the WSL probe true -> OK, false -> MANCA, and the probe is [ -x '/opt/maat-prova/run' ]
  unita "${1:-$DOC}" '
import io, contextlib
os = ns["os"]; os.environ["MAAT_CONFIG"] = sys.argv[3]; os.environ["PROJECT_ROOT"] = ns["ROOT"]
mc = ns["carica_lettore"](); cfg, _p = mc.carica(); r = mc.risolto(cfg); m = r["moduli"][0]
class F:
    def __init__(s, si): s.prove, s.si = [], si
    def prova(s, t): s.prove.append(t); return len(s.prove) - 1
    def __getitem__(s, i): return s.si and s.prove[i].startswith("[ -x ")
for si, atteso in ((True, "OK comando test del modulo m: /opt/maat-prova/run"),
                   (False, "MANCA comando test del modulo m: /opt/maat-prova/run non trovato")):
    w = F(si); buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        for f in ns["controlli_modulo"](mc, cfg, r, m, True, F(True), w, 0):
            f()
    righe = buf.getvalue().splitlines()
    assert "[ -x '"'"'/opt/maat-prova/run'"'"' ]" in w.prove, w.prove
    assert any(l.startswith(atteso) for l in righe), righe
' "$V25" > "$T/out" 2>&1
}
check "modulo wsl con /opt/…: [ -x ] dentro WSL decide OK o MANCA" 'caso_wsl_assoluto'

# 25b. 1.4.0: --prova-test of a wsl module: the program given to wsl on stdin exports MAAT_LINGUA, resolved (wsl.exe does
#      not pass the environment; the last line of the trial, a message of test-fast.sh, goes into trial_ko). Fake
#      shutil.which and subprocess.run: the program is captured, nothing is run.
V25B=$(variante wsl-prova 'c["moduli"][0]["ambiente"] = "wsl"')
caso_prova_wsl() { # [doctor]
  unita "${1:-$DOC}" '
import io, contextlib
os = ns["os"]; os.environ["MAAT_CONFIG"] = sys.argv[3]; os.environ["PROJECT_ROOT"] = ns["ROOT"]
mc = ns["carica_lettore"](); cfg, _p = mc.carica(); r = mc.risolto(cfg); m = r["moduli"][0]
preso = []
class R:
    returncode, stdout = 0, b"ok\n"
def run(argv, input=None, **kw):
    preso.append((argv, input))
    return R()
ns["shutil"].which = lambda x: "/fake/" + x
ns["subprocess"].run = run
for lg in ("it", "en"):
    os.environ["MAAT_LINGUA"] = lg; preso.clear()
    with contextlib.redirect_stdout(io.StringIO()):
        ns["prova_test"](mc, cfg, m, {})
    assert preso and preso[0][0][1:] == ["--", "bash", "-l", "-s"], preso
    prog = preso[0][1].decode("utf-8")
    assert ("MAAT_LINGUA=%s\n" % ns["sq"](lg)) in prog, prog
' "$V25B" > "$T/out" 2>&1
}
check "--prova-test, modulo wsl: il programma per wsl esporta MAAT_LINGUA (it e en)" 'caso_prova_wsl'

# 26. counterproof tools (pk08): rsync/flock missing -> OK «di ripiego, più lenti»; sha256sum, timeout, rsync and
#     tar together -> ATTENZIONE BLOCKED. With fake probes (missing by name), then a real run with this machine's PATH.
V26=$(variante controprova 'c["moduli"][0]["controprova"] = {"runner": "comando", "comando": "bash run-test.sh {test}"}')
caso_strumenti() { # [doctor]
  unita "${1:-$DOC}" '
import io, contextlib
os = ns["os"]; os.environ["MAAT_CONFIG"] = sys.argv[3]; os.environ["PROJECT_ROOT"] = ns["ROOT"]
mc = ns["carica_lettore"](); cfg, _p = mc.carica(); r = mc.risolto(cfg); m = r["moduli"][0]
class F:
    def __init__(s, via): s.prove, s.via = [], via
    def prova(s, t): s.prove.append(t); return len(s.prove) - 1
    def __getitem__(s, i): return not any(("command -v %s " % ns["sq"](x)) in s.prove[i] for x in s.via)
B = "ATTENZIONE controprove del modulo m non disponibili (BLOCKED): manca "
casi = (((), "OK controprove del modulo m: rsync e flock presenti"),
        (("rsync", "flock"), "OK controprove del modulo m: rsync/flock assenti: copia e lock di ripiego, più lenti"),
        (("rsync",), "OK controprove del modulo m: rsync assente: copia di ripiego, più lenta"),
        (("flock",), "OK controprove del modulo m: flock assente: lock di ripiego, più lento"),
        (("rsync", "flock", "sha256sum"), B + "sha256sum"),
        (("timeout",), B + "timeout"),
        (("rsync", "tar"), B + "rsync e tar"))
for via, atteso in casi:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        for f in ns["controlli_modulo"](mc, cfg, r, m, True, F(via), F(()), 0):
            f()
    righe = [l for l in buf.getvalue().splitlines() if "controprove del modulo" in l]
    assert len(righe) == 1 and righe[0].startswith(atteso), (via, righe)
' "$V26" > "$T/out" 2>&1
}
check "strumenti delle controprove: ripiego per rsync/flock (OK), BLOCKED per sha256sum, timeout, rsync e tar" 'caso_strumenti'
if command -v rsync >/dev/null 2>&1 && command -v flock >/dev/null 2>&1; then ATT26='^OK controprove del modulo m: rsync e flock presenti'
elif ! command -v rsync >/dev/null 2>&1 && ! command -v flock >/dev/null 2>&1; then ATT26='^OK controprove del modulo m: rsync/flock assenti: copia e lock di ripiego, più lenti'
else ATT26='^OK controprove del modulo m: (rsync|flock) assente: (copia|lock) di ripiego'; fi
doc MAAT_CONFIG="$V26"
check "  giro vero su questa macchina: $ATT26" '[ "$rc" = 0 ] && ha "$ATT26" && ! ha "^ATTENZIONE controprove"'

# --- en (1.4.0): MAAT_LINGUA=en, the levels printed as OK|WARNING|MISSING (D3), the text from the catalog, no Italian ---
IT_DOC='ATTENZIONE|MANCA|guardia:|guardia (di|non)|cartella|modulo|negat|sonda|agganciat|versione|richiesto|scrivibile|assente|valido| del | non '
doc MAAT_LINGUA=en
check "en: progetto completo -> exit 0, guardia provata, riepilogo OK/WARNING/MISSING, niente italiano" '[ "$rc" = 0 ] && ha "^OK guard: «git push --force origin prova» denied in a phase and asked in the session$" && ha "^OK guard: production probe «curl -s https://prod\.esempio\.it/» denied in a phase and asked in the session$" && ha "^OK valid maat\.json \(" && ha "^maat-doctor: [0-9]+ OK, 0 WARNING, 0 MISSING$" && ! ha "$IT_DOC"'
DP=$T/p0 doc MAAT_LINGUA=en
check "en: senza maat.json -> MISSING «run /maat:setup», exit 1, niente italiano" '[ "$rc" = 1 ] && ha "^MISSING maat\.json missing \(.*\) — run /maat:setup$" && ha "^maat-doctor: [0-9]+ OK, 0 WARNING, 2 MISSING$" && ! ha "$IT_DOC"'
DP=$T/p5 doc MAAT_LINGUA=en
check "en: hook doppio -> WARNING (il token interno ATTENZIONE non si vede)" 'ha "^WARNING duplicate guard hook: plugin maat enabled \(.claude/settings\.json\) and project PreToolUse hook" && ha "^maat-doctor: [0-9]+ OK, 1 WARNING, 0 MISSING$" && ! ha "$IT_DOC"'
doc MAAT_LINGUA=en -- --piattaforma
check "en: --piattaforma stampa gli stessi valori di sempre" '[ "$rc" = 0 ] && grep -qxE "windows-wsl|windows-senza-wsl|altro" <(tr -d "\r" < "$T/out")'
doc MAAT_LINGUA=en -- --nonsense
check "en: opzione sconosciuta -> 64, in inglese" '[ "$rc" = 64 ] && ha "^maat-doctor: unknown option: --nonsense" && ! ha "$IT_DOC"'

# --- mutation counterproofs -------------------------------------------------------------------------------------------------
mutante() { # <name> <sed expression> -> path of the mutated doctor (with the plugin next to it); empty if the sed changes nothing
  local d="$T/mut/$1"
  mkdir -p "$T/mut"; cp -r "$PLUGIN" "$d"
  sed -e "$2" "$DOC" > "$d/scripts/maat-doctor.sh"
  cmp -s "$DOC" "$d/scripts/maat-doctor.sh" || printf '%s' "$d/scripts/maat-doctor.sh"
}
m=$(mutante copia-anche 's/ok = os.path.isdir(posixpath.join(ROOT, mc.norm(d)))/ok = True/')
check "controprova: copia_anche senza controllo -> la cartella inesistente passa, rosso" '[ -n "$m" ] && ! caso_copia_anche "$m"'
m=$(mutante modulo-wsl 's/elif amb == "wsl" and not wsl:/elif False:/; s/if amb == "wsl" and not WIN:/if False:/')
check "controprova: modulo wsl senza la riga MANCA -> rosso" '[ -n "$m" ] && ! caso_modulo_wsl "$m"'
m=$(mutante sonda 's/ok = any(x.search(cmd) for _p, x in rx)/ok = True/')
check "controprova: sonda non confrontata con le regex -> rosso" '[ -n "$m" ] && ! caso_sonda "$m"'
m=$(mutante scrive 's/^set -uo pipefail$/set -uo pipefail; : > "$PWD\/scritto-dal-doctor"/')
check "controprova: un doctor che scrive un file -> sola lettura rossa" '[ -n "$m" ] && ! sola_lettura "$m"'
rm -f "$P/scritto-dal-doctor"
m=$(mutante completo 's/\[ "$rc" = 2 \] || { GMOT=/[ "$rc" = 0 ] || { GMOT=/')
check "controprova: guardia attesa ammettere in fase -> il caso completo è rosso" '[ -n "$m" ] && ! caso_completo "$m"'
m=$(mutante claude-path 's/^CL=\${CLAUDE_BIN:-}$/CL=${CLAUDE_BIN:-}; [ -n "$CL" ] || CL=$(command -v claude 2>\/dev\/null || true)/')
check "controprova: claude cercato nel PATH prima dell'estensione -> rosso" '[ -n "$m" ] && ! caso_claude_ext "$m"'
m=$(mutante python-assente 's/            ok = p is not None and (os.path.isfile(p)/            ok = p is not None or (os.path.isfile(p)/; s/            if ok:   # an interpreter/            if False:   # an interpreter/')
check "controprova: interprete assente preso per presente -> niente MANCA python, rosso" '[ -n "$m" ] && ! caso_python_assente "$m"'
m=$(mutante python-ok 's/            if exe == "{python}" and not py\["ok"\] and not mancanti:/            if False:/')
check "controprova: {python} assente con lo script presente stampa OK del comando -> rosso" '[ -n "$m" ] && ! caso_python_assente "$m"'
m=$(mutante se-presente 's/^            elif se_presente:$/            elif False:/')
check "controprova: se_presente ignorato -> MANCA invece di «controllo saltato», rosso" '[ -n "$m" ] && ! caso_se_presente "$m"'
m=$(mutante schema-db 's/^            if i is not None and not locale\[i\]:$/            if False:/')
check "controprova: comando del progetto non cercato nel PATH -> schema_db_comando OK, rosso" '[ -n "$m" ] && ! caso_schema_db "$m"'
m=$(mutante verifica 's/^            if script and not os.path.isfile(assoluto(script, base)):$/            if False:/')
check "controprova: script di verifica_remota non cercato -> OK, rosso" '[ -n "$m" ] && ! caso_verifica "$m"'
m=$(mutante suite 's/ok = any(t == nome or t.endswith("\/" + nome) for t in tracciati) or os.path.isfile(assoluto(nome, ROOT))/ok = True/')
check "controprova: guardia.suite non cercata -> nessuna ATTENZIONE, rosso" '[ -n "$m" ] && ! caso_suite "$m"'
m=$(mutante catena 's/^        if x in SEPARA:$/        if False:/')
check "controprova: dopo cd non si segue && -> «comando della shell» OK, rosso" '[ -n "$m" ] && ! caso_catena "$m"'
m=$(mutante env-opzioni 's/^                while tok and tok\[0\]\.startswith("-"):$/                while False:/')
check "controprova: opzioni di env non saltate -> l'eseguibile diventa -u, rosso" '[ -n "$m" ] && ! caso_catena "$m"'
m=$(mutante cd 's/^                cart = posixpath\.normpath(posixpath\.join(cart, tok\[1\].*$/                pass/')
check "controprova: cd non seguito -> ../run-test.sh cercato dalla radice, rosso" '[ -n "$m" ] && ! caso_catena_cd "$m"'
m=$(mutante parentesi-punt 's/punctuation_chars=";&|<>")/punctuation_chars=";\&|<>()")/')
check "controprova: ( ) come punteggiatura -> FOO=\$(pwd) spezzato, «comando della shell» OK, rosso" '[ -n "$m" ] && ! caso_assegna_sost "$m"'
m=$(mutante sottoshell 's/^        tok = senza_parentesi(tok)$/        tok = list(tok)/')
check "controprova: parentesi della sottoshell non tolte -> il cd si perde, MANCA, rosso" '[ -n "$m" ] && ! caso_sottoshell "$m"'
m=$(mutante isolato 's/"\$FIC_PY" -I -B -X utf8 - "\$@"/"$FIC_PY" - "$@"/')
check "controprova: Python del doctor senza -I -> glob.py del progetto vince, rosso" '[ -n "$m" ] && ! caso_stdlib "$m"'
m=$(mutante copia-nm "s/'\\[ -d \"%s\\/node_modules\" \\]' % d, //")
check "controprova: copia pronta col solo .fic-deps -> rosso" '[ -n "$m" ] && ! caso_copia "$m"'
m=$(mutante copia-semina 's/^    questa, principale = pronta("$FIC_MIRROR\/" + p), pronta("$HOME\/fic-mirror\/" + p)$/    questa, principale = pronta("$FIC_MIRROR\/" + p), pronta("$FIC_MIRROR\/" + p)/')
check "controprova: semina cercata nella copia del worktree invece che in quella principale -> rosso" '[ -n "$m" ] && ! caso_copia "$m"'
m=$(mutante wsl-assoluto 's/^                    if a.startswith("\/") and not a.startswith("\/mnt\/"):$/                    if False:/')
check "controprova: /opt/… di un modulo wsl guardato lato Windows -> rosso" '[ -n "$m" ] && ! caso_wsl_assoluto "$m"'
m=$(mutante prova-lingua 's/ MAAT_LINGUA=%s\\ncd %s \&\& %s\\n" % (/\\ncd %s \&\& %s\\n" % (/; s/sq(_m.lingua()), sq(wslp(cart_abs))/sq(wslp(cart_abs))/')
check "controprova: prova in WSL senza MAAT_LINGUA -> rosso" '[ -n "$m" ] && ! caso_prova_wsl "$m"'
m=$(mutante strumenti-ripiego 's/^                elif assenti:$/                elif False:/')
check "controprova: rsync/flock assenti senza la riga di ripiego -> «presenti», rosso" '[ -n "$m" ] && ! caso_strumenti "$m"'
m=$(mutante strumenti-sha 's/manca = \[s for s in ("sha256sum", "timeout") if not ha\[s\]\]/manca = []/')
check "controprova: sha256sum e timeout non controllati -> nessun BLOCKED, rosso" '[ -n "$m" ] && ! caso_strumenti "$m"'
m=$(mutante py-soglia 's/^elif ! fic_py_min_ok; then/elif false; then/')
check "controprova: doctor senza la soglia di Python -> il 3.9 finto passa, rosso" '[ -n "$m" ] && ! caso_py39 "$m"'
mkdir -p "$T/mut"; cp -r "$PLUGIN" "$T/mut/py-311"
sed 's/\[ "\$mi" -ge 10 \]/[ "$mi" -ge 11 ]/' "$HERE/python.sh" > "$T/mut/py-311/scripts/python.sh"
check "controprova: python.sh con la soglia 3.11 -> il doctor la segue, il 3.10 finto MANCA, rosso" '! cmp -s "$HERE/python.sh" "$T/mut/py-311/scripts/python.sh" && ! caso_py310 "$T/mut/py-311/scripts/maat-doctor.sh"'
m=$(mutante fic-driver 's/^if \[ -n "\${FIC_DRIVER:-}" \]; then riga/if false; then riga/')
check "controprova: un doctor che non guarda FIC_DRIVER -> il caso ATTENZIONE è rosso" '[ -n "$m" ] && ! caso_fic_driver "$m"'
m=$(mutante mac-spento 's/" = Darwin \]; then$/" = NonDarwin ]; then/')
check "controprova: controllo macOS spento -> il sed BSD non si vede, rosso" '[ -n "$m" ] && ! caso_mac_sed "$m"'
m=$(mutante mac-gnu "s/grep -qF '(GNU '/grep -qF 'GNU'/")
check "controprova: «GNU» invece di «(GNU » -> il grep BSD passa, rosso" '[ -n "$m" ] && ! caso_mac_grep "$m"'
if [ "$WIN" = 1 ]; then
  m=$(mutante wsl-livello 's/riga("OK", T("maat-doctor.wsl_missing_ok"/riga("MANCA", T("maat-doctor.wsl_missing_ok"/')
  check "controprova: WSL assente come MANCA -> exit 1, rosso" '[ -n "$m" ] && ! caso_wsl_assente "$m"'
  if [ -e /c/Windows/System32/wsl.exe ] || [ -e "${SYSTEMROOT:-C:/Windows}/System32/wsl.exe" ]; then
    # wsl.exe exists in System32: a doctor that ignores PATH finds it anyway (CreateProcess also searches there)
    m=$(mutante wsl-path 's/    w = shutil.which("wsl") or shutil.which("wsl.exe")/    w = "wsl"/')
    check "controprova: WSL cercato senza il PATH -> «WSL assente» sparisce, rosso" '[ -n "$m" ] && ! caso_wsl_assente "$m"'
    # 1.6.0: only where that wsl.exe runs a distribution; the Windows runner of the CI has wsl.exe with none, so the
    # mutant still answers windows-senza-wsl and the counterproof has nothing to show
    wx=/c/Windows/System32/wsl.exe; [ -e "$wx" ] || wx=$(cygpath -u "${SYSTEMROOT:-C:/Windows}/System32/wsl.exe")
    if timeout 60 "$wx" -e true >/dev/null 2>&1; then
      check "controprova: --piattaforma senza il PATH -> non windows-senza-wsl, rosso" '[ -n "$m" ] && ! caso_piattaforma "$m"'
    else
      echo "SALTATO [controprova --piattaforma senza PATH]: wsl.exe c'e' ma non avvia nessuna distribuzione"
    fi
  else
    echo "SALTATO [controprova WSL senza PATH]: wsl.exe non installato su questa macchina"
  fi
fi

echo "maat-doctor.test.sh: $pass ok, $fail falliti"
[ "$fail" = 0 ]
