# python.sh — to be sourced with `.`: sets FIC_PY to the ABSOLUTE path of a real Python.
# The same path serves run-phase.sh's self-test and the hook JSON: if they were two different
# commands, the self-test could pass while the real hook fails (and a failing hook LETS
# EVERYTHING THROUGH). The Store "python" stub is avoided (it opens the Store instead of running).
#   FIC_PYTHON  if set, it wins.
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
[ -n "$FIC_PY" ] && "$FIC_PY" -c 'import json, shlex' >/dev/null 2>&1
