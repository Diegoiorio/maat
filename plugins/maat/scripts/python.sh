# python.sh — to be sourced with `.`: sets FIC_PY to the ABSOLUTE path of a real Python.
# The same path serves run-phase.sh's self-test and the hook JSON: if they were two different
# commands, the self-test could pass while the real hook fails (and a failing hook LETS
# EVERYTHING THROUGH). The Store "python" stub is avoided (it opens the Store instead of running).
#   FIC_PYTHON  if set, it wins.
# Exit status: 0 only if FIC_PY runs `import json, shlex` with exit 0 (the verdict of the guard, as before 1.5.1; any
# version), otherwise 1. In the same call (no extra process, 1.5.1) it sets FIC_PY_VER=<major>.<minor> of that
# interpreter, empty when the status is not 0; fic_py_min_ok (below) says whether FIC_PY_VER is at least 3.10, the
# minimum of Maat (README, maat-doctor.sh, driver.py run). No pipe in the verdict, so it does not depend on pipefail
# (some includers do not set it), and FIC_PY_VER inherited from the environment never survives.
FIC_PY=${FIC_PYTHON:-}
if [ -z "$FIC_PY" ] && command -v py >/dev/null 2>&1; then
  FIC_PY=$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r')
fi
if [ -z "$FIC_PY" ]; then
  for c in python3 python; do
    p=$(command -v "$c" 2>/dev/null) || continue
    FIC_PY=$("$p" -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r') && [ -n "$FIC_PY" ] && break
    FIC_PY=""
  done
fi
FIC_PY=${FIC_PY//\\//}
fic_py_min_ok() { # 0 = FIC_PY_VER is <major>.<minor> and at least 3.10 (two integers compared)
  local ma mi
  case "${FIC_PY_VER:-}" in [0-9]*.[0-9]*) ;; *) return 1 ;; esac
  ma=${FIC_PY_VER%%.*} mi=${FIC_PY_VER#*.}
  case "$ma$mi" in *[!0-9]*) return 1 ;; esac
  [ "$ma" -gt 3 ] || { [ "$ma" -eq 3 ] && [ "$mi" -ge 10 ]; }
}
if [ -n "$FIC_PY" ] && FIC_PY_VER=$("$FIC_PY" -c 'import json, shlex, sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)
then FIC_PY_VER=${FIC_PY_VER//$'\r'/}; true
else FIC_PY_VER=""; false; fi
