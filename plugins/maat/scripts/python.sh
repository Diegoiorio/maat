# python.sh — da includere con `.`: imposta FIC_PY al percorso ASSOLUTO di un Python vero.
# Lo stesso percorso serve all'autotest di run-phase.sh e al JSON dell'hook: se fossero due comandi
# diversi, l'autotest potrebbe passare mentre l'hook vero fallisce (e un hook che fallisce LASCIA
# PASSARE). Si evita lo stub "python" dello Store (apre lo Store invece di eseguire).
#   FIC_PYTHON  se impostata, vince.
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
