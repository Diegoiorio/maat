#!/usr/bin/env bash
# guardia-plugin.sh — shared by tools/suite.sh and tools/giro-completo.sh (Maat 1.5.0: the suite.list entries and the
# guard of the run).
#   . tools/lib/guardia-plugin.sh                 the functions below
#   bash tools/lib/guardia-plugin.sh <plugin dir>   prints the plugin fingerprint (giro-completo.sh, inside WSL)
#
# suite_file <entry>: the file of a tools/suite.list entry, relative to the repo root. An entry with a / is already
#   a path from the repo root (tools/x.test.sh, the tests that make sense only in the repo); test-review-surface is
#   plugins/maat/scripts/test-review-surface.sh; any other name is plugins/maat/scripts/<name>.test.sh.
# suite_log <entry>: the name of its log in the results dir (the / become -).
# guardia_impronta <plugin dir>: the fingerprint of the plugin files, the same list as `run-phase.sh --harness-paths`
#   (the harness fingerprint of the cycles, without the project's .claude/maat.json), content without CR: sha256 of
#   the lines "<sha256 of the content without CR> <path>". A file added, removed or changed changes it. Not
#   computable (run-phase.sh or Python missing, a file unreadable) → NON-CALCOLABILE, exit 1: the callers treat it
#   as a changed plugin.
suite_file() {
  case "$1" in
    */*) printf '%s\n' "$1" ;;
    test-review-surface) echo plugins/maat/scripts/test-review-surface.sh ;;
    *) printf 'plugins/maat/scripts/%s.test.sh\n' "$1" ;;
  esac
}
suite_log() { printf '%s\n' "${1//\//-}"; }

GUARDIA_PY='
import hashlib, sys
righe = []
for rel in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\n"):
    if rel:
        with open(rel, "rb") as fh:
            righe.append("%s %s\n" % (hashlib.sha256(fh.read().replace(b"\r", b"")).hexdigest(), rel))
sys.stdout.write(hashlib.sha256("".join(righe).encode("utf-8", "surrogateescape")).hexdigest())
'
guardia_impronta() {
  local o
  o=$(
    cd "$1" 2>/dev/null || exit 1
    unset MAAT_ROOT   # the plugin of this folder, not one from the environment
    l=$(bash scripts/run-phase.sh --harness-paths 2>/dev/null) || exit 1
    . scripts/python.sh >/dev/null 2>&1 || exit 1
    printf '%s\n' "$l" | tr -d '\r' | grep -vxF .claude/maat.json |
      PYTHONDONTWRITEBYTECODE=1 "$FIC_PY" -c "$GUARDIA_PY" 2>/dev/null
  ) || o=
  if [[ $o =~ ^[0-9a-f]{64}$ ]]; then printf '%s\n' "$o"; else echo NON-CALCOLABILE; return 1; fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ $# -eq 1 ] || { echo "usage: bash tools/lib/guardia-plugin.sh <plugin dir>" >&2; exit 2; }
  guardia_impronta "$1"
fi
