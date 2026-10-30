# worktree-lib.sh — shared functions for the harness worktrees: the main tree's dependencies LINKED (never
# copied or installed), check that they match, safe unlinking, relative .git, WSL copy of the worktree.
# It is SOURCED with `.` by script/fic/corpus/replay.sh (replay of a phase) and by script/fic/ciclo-worktree.sh
# (cycle in a dedicated worktree): it is not executed, and has no effect until a function is called.
# Extracted from replay.sh without changing its behaviour (tests: script/fic/cycle-report.test.sh, corpus section;
# script/fic/ciclo-worktree.test.sh).
#
# The caller sets: MAIN (main tree, for deps_diff and for its maat.json) · FIC_PY (for fic_relgit, from
# python.sh; if missing, wt_conf loads it) · WT_TAG (message prefix, default «replay»).
# What to link and which files decide the dependencies is NOT written here: the main tree's maat.json declares it
# (MAAT_CONFIG, otherwise $MAIN/.claude/maat.json), per module: collega_nel_worktree (the linked folders),
# file_dipendenze (the files that decide them), preparati and preparazione (the prepared files copied into the
# worktree, in ciclo-worktree.sh), copia (the module of the WSL copy: fingerprint and seeding). Read once with
# maat-config.py imported (wt_conf_carica); project not configured: nothing to link or compare.
# Exit of the `.`: 1 if fic-mirror.sh is not found next to this file.
#
# ⚠️ A worktree folder with linked dependencies, deleted by FOLLOWING the links, empties the main tree's
# REAL dependencies. First unlink_deps (only the link, never recursive), then the check that no link is
# left, then the removal.

WTLIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
. "$WTLIB_DIR/lib/maat-paths.sh" || return 1   # fic-mirror.sh lives in MAAT_SCRIPTS, next to this file
WTLIB_TEST=$MAAT_SCRIPTS

winpath() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }
# Canonical form of an EXISTING path (C:/…): under MSYS the same place has several names (/tmp and
# C:/Users/…/Temp, /c/… and C:/…), so every path comparison goes through here. Empty → empty.
canon() { [ -n "${1:-}" ] && (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }

# --- main tree configuration (maat.json): lines «type<TAB>…», paths relative to the repository ---
#   link  <path>                                         an entry of collega_nel_worktree (may contain *)
#   dep   <glob>                                         an entry of file_dipendenze (git :(glob) pathspec)
#   prep  <root> <guide file> <preparazione> <glob>…     a module with preparati (guide: the first glob without wildcards)
#   copia <radice_pacchetti> <root> <guide file>         a module with copia (repo root = «.»)
# Empty guide and preparazione are written «-» (the reader converts them back): with IFS=$'\t' two tabs in a row
# are a single separator, and an empty field would shift the following ones.
WT_CONF_PY=$(cat <<'EOF'
import importlib.util, sys
import sys; sys.dont_write_bytecode = True   # no __pycache__ under MAAT_ROOT
s = importlib.util.spec_from_file_location("maat_config", sys.argv[1])
mc = importlib.util.module_from_spec(s)
s.loader.exec_module(mc)
try:
    cfg, _p = mc.carica(sys.argv[2])
except mc.Uscita as u:
    if u.codice == 4:   # project not configured: nothing to link or compare
        sys.exit(0)
    sys.stderr.write("maat.json: %s\n" % (u.messaggio or "configurazione non valida (uscita %d)" % u.codice))
    sys.exit(1)
r = mc.risolto(cfg)
def j(base, x):
    x = mc.norm(x)
    return base + "/" + x if base and x else (base or x)
for m in r["moduli"]:
    for v in m.get("collega_nel_worktree", []):
        v = {"percorso": v} if isinstance(v, str) else v
        print("link\t" + j(mc.cartella_di(m, v.get("cartella", "radice")), v["percorso"]))
    for v in m.get("file_dipendenze", []):
        v = {"glob": v} if isinstance(v, str) else v
        print("dep\t" + j(mc.cartella_di(m, v.get("cartella", "radice")), v["glob"]))
def v(x):   # empty field -> «-»: tab is IFS whitespace, so read would merge empty fields and shift the ones after them
    return x or "-"
for m in r["moduli"]:
    pr = [mc.norm(g) for g in m.get("preparati", [])]
    rad = mc.norm(m["radice"]) or "."
    guida = next((g for g in pr if not any(c in g for c in "*?[")), "")
    if pr:
        print("\t".join(["prep", rad, v(guida), v(m.get("preparazione", ""))] + pr))
    if m.get("copia"):
        print("\t".join(["copia", mc.norm(m["radice_pacchetti"]) or ".", rad, v(guida)]))
EOF
)
_WT_CONF="" _WT_CONF_OK=""
wt_conf_carica() { # reads the main tree's maat.json once (subshells inherit the cache): 1 if invalid
  local cfg out
  [ -n "${FIC_PY:-}" ] || . "$MAAT_SCRIPTS/python.sh" || { echo "${WT_TAG:-replay}: interprete Python non trovato (maat.json)" >&2; return 1; }
  cfg=${MAAT_CONFIG:-${MAIN:-${PROJECT_ROOT:-.}}/.claude/maat.json}
  out=$("$FIC_PY" -c "$WT_CONF_PY" "$(winpath "$MAAT_SCRIPTS/maat-config.py")" "$(winpath "$cfg")" 2>&1) ||
    { echo "${WT_TAG:-replay}: $(printf '%s' "$out" | tr -d '\r' | tail -1) ($cfg)" >&2; return 1; }
  _WT_CONF=$(printf '%s' "$out" | tr -d '\r') _WT_CONF_OK=1
}
wt_conf() { # the configuration lines (above), read on the first call
  [ -n "$_WT_CONF_OK" ] || wt_conf_carica || return 1
  [ -z "$_WT_CONF" ] || printf '%s\n' "$_WT_CONF"
}

# --- main tree dependencies in the worktree: linked, never copied or installed ---
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WIN=1 ;; *) WIN=0 ;; esac
# files that decide the linked dependencies (file_dipendenze): if they differ, the dependencies are not the code's
dep_ps() { local k g; while IFS=$'\t' read -r k g; do [ "$k" = dep ] && printf ':(glob)%s\n' "$g"; done < <(wt_conf); return 0; }
deps_diff() { # $1 tree-ish → the dependency files that differ from the main working tree (or exist only there)
  local ps=()
  mapfile -t ps < <(dep_ps)
  [ ${#ps[@]} -gt 0 ] || return 0   # no dependency file declared: nothing to compare
  { git -C "$MAIN" -c core.quotePath=false diff --name-only "$1" -- "${ps[@]}" || echo "(git diff fallito)"
    git -C "$MAIN" -c core.quotePath=false ls-files -o --exclude-standard -- "${ps[@]}"; } | LC_ALL=C sort -u
}
dep_links() { # $1 root → the relative paths of the installed dependencies (collega_nel_worktree) present under the root
  local r=$1 k g p
  while IFS=$'\t' read -r k g; do
    [ "$k" = link ] && [ -n "$g" ] || continue
    local IFS=   # pk08: niente divisione (no word splitting): a root or an entry with spaces stays one path
    for p in "$r"/$g; do   # $g unquoted: the entry's * expands
      { [ -e "$p" ] || [ -L "$p" ]; } && printf '%s\n' "${p#"$r"/}"
    done
  done < <(wt_conf)
  return 0
}
link_dep() { # $1 source (existing folder), $2 link to create (must not exist)
  [ -d "$1" ] || { echo "${WT_TAG:-replay}: sorgente del collegamento assente: $1" >&2; return 1; }
  { [ -e "$2" ] || [ -L "$2" ]; } && { echo "${WT_TAG:-replay}: $2 esiste gia': non lo sostituisco" >&2; return 1; }
  mkdir -p "$(dirname "$2")" || return 1
  if [ $WIN -eq 1 ]; then   # junction: no privileges needed; MSYS must not convert /c and /J
    MSYS2_ARG_CONV_EXCL='*' cmd.exe /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null || return 1
  else
    ln -s "$1" "$2" || return 1
  fi
  [ -L "$2" ]
}
unlink_deps() { # $1 worktree root: removes ONLY the links (never recursive: the source is not touched).
  # A real folder in the same place belongs to the worktree: it stays. 1 if a link cannot be removed.
  local r=$1 p left=0
  while IFS= read -r p; do
    [ -n "$p" ] && [ -L "$r/$p" ] || continue
    # rmdir without /s on a junction removes the junction, not the target's contents
    [ $WIN -eq 1 ] && MSYS2_ARG_CONV_EXCL='*' cmd.exe /c rmdir "$(cygpath -w "$r/$p")" >/dev/null 2>&1
    [ -L "$r/$p" ] && rm -f "$r/$p"   # symlink: unlink(), does not follow
    [ -L "$r/$p" ] && { echo "${WT_TAG:-replay}: collegamento non rimosso: $r/$p" >&2; left=1; }
  done < <(dep_links "$r")
  return $left
}
fic_relgit() { # $1 worktree: .git with a RELATIVE gitdir, readable by WSL's git too (vitest-fast.sh)
  local wt=$1 gd rel
  gd=$(git -C "$wt" rev-parse --absolute-git-dir) || return 1
  rel=$("$FIC_PY" -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]).replace(os.sep, "/"))' \
        "$gd" "$(canon "$wt")" 2>/dev/null | tr -d '\r')
  if [ -z "$rel" ]; then
    echo "${WT_TAG:-replay}: AVVISO — gitdir relativo non calcolabile (unita' diverse?): resta quello assoluto, che vitest-fast.sh traduce" >&2
    return 0
  fi
  printf 'gitdir: %s\n' "$rel" > "$wt/.git" &&
    [ "$(canon "$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)")" = "$(canon "$gd")" ] && return 0
  printf 'gitdir: %s\n' "$gd" > "$wt/.git"   # restore: the worktree must stay removable
  echo "${WT_TAG:-replay}: gitdir relativo non valido ($rel): ripristinato quello assoluto" >&2
  return 1
}
# Fingerprint of the copy's dependencies: the SAME as test-fast.sh and counterproof.sh (fic_deps_fp of fic-mirror.sh,
# content without CR) on the radice_pacchetti of the maat.json module with copia; no module with copia: empty. It is
# the condition for seeding the dependencies into the worktree's WSL copy.
[ -n "$WTLIB_TEST" ] && [ -f "$WTLIB_TEST/fic-mirror.sh" ] || { echo "worktree-lib: fic-mirror.sh non trovato: $WTLIB_TEST/fic-mirror.sh" >&2; return 1; }
. "$WTLIB_TEST/fic-mirror.sh" || return 1
deps_fp() { # $1 root → fingerprint as in test-fast.sh (which computes it on the radice_pacchetti of the module with copia)
  local rp
  rp=$(wt_conf | awk -F'\t' '$1 == "copia" { print $2; exit }')
  if [ -n "$rp" ] && [ -d "$1/$rp" ]; then fic_deps_fp "$1/$rp"; else printf '' | sha256sum | cut -c1-64; fi
}
FPWARN=""
deps_fp_check() { # $1 main tree, $2 worktree: different fingerprints → warning (log and report), never an error
  local a b
  a=$(deps_fp "$1") b=$(deps_fp "$2")
  [ "$a" = "$b" ] && { echo "${WT_TAG:-replay}: impronta delle dipendenze della copia uguale al tree principale (${a:0:12})"; return 0; }
  FPWARN="impronta delle dipendenze della copia diversa dal tree principale (${b:0:12} ≠ ${a:0:12}): la copia WSL del worktree non si semina, test-fast e counterproof usciranno BLOCKED (copia assente)"
  echo "${WT_TAG:-replay}: AVVISO — $FPWARN" >&2
  return 0
}
wslp() { # path C:/… → /mnt/c/… (for WSL's git); others stay as they are
  local p=$1 d
  case "$p" in [A-Za-z]:/*) d=$(printf '%s' "${p:0:1}" | tr '[:upper:]' '[:lower:]'); printf '/mnt/%s/%s' "$d" "${p:3}" ;; *) printf '%s' "$p" ;; esac
}
forget_mirror() { # $1 worktree: deletes the WSL copies of its lanes (~/fic-mirror-<hash>-1|2, harness-pt13) and
  # its copy ~/fic-mirror-<hash> (never ~/fic-mirror); never an error.
  # The script goes to bash on STDIN: with `wsl.exe -- bash -c "…"` $k and $r arrived already expanded (empty:
  # measured 2026-09-30), so the lanes were never deleted and the exit was always 0.
  local lib=$WTLIB_TEST/fic-mirror.sh wt=$1 l w out rc
  if [ $WIN -eq 1 ]; then l=$(wslp "$(winpath "$lib")") w=$(wslp "$(canon "$wt")"); else l=$lib w=$wt; fi
  out=$({ printf 'L=%q R=%q\n' "$l" "$w"
          printf '%s\n' '. "$L" || exit 1' \
            'r=0; for k in 1 2; do fic_lane_forget "$R" "$k" || r=1; done; fic_mirror_forget "$R" || r=1; exit $r'
        } | if [ $WIN -eq 1 ]; then MSYS_NO_PATHCONV=1 wsl.exe -- bash -s; else bash -s; fi 2>&1); rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  [ $rc -eq 0 ] || echo "${WT_TAG:-replay}: AVVISO — copia WSL del worktree non cancellata del tutto (in uso?); poi, da WSL: . $l && fic_lane_forget $w 1; fic_lane_forget $w 2; fic_mirror_forget $w" >&2
  return 0
}
