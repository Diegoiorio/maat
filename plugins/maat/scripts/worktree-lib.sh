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
# messages (1.4.0): the catalog next to this file, unless the caller already loaded it (msg loads it on first use)
declare -F msg >/dev/null || . "$WTLIB_DIR/lib/maat-msg.sh"

winpath() { maat_cygm "$1" 2>/dev/null || printf '%s' "$1"; }
# Canonical form of an EXISTING path (C:/…): under MSYS the same place has several names (/tmp and
# C:/Users/…/Temp, /c/… and C:/…), so every path comparison goes through here. Empty → empty.
canon() { [ -n "${1:-}" ] && (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }

# --- main tree configuration (maat.json): lines «type<TAB>…», paths relative to the repository ---
#   link  <path>                                         an entry of collega_nel_worktree (may contain *)
#   dep   <glob>                                         an entry of file_dipendenze (git :(glob) pathspec)
#   prep  <root> <guide file> <preparazione> <glob>…     a module with preparati (guide: the first glob without wildcards)
#   prepamb <root> <ambiente> <name>                     the same module: where its preparazione runs (1.9.0, K3)
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
    if not u.messaggio:   # the message catalog (1.4.0) next to this file: argv[3] is its maat_msg.py
        s = importlib.util.spec_from_file_location("maat_msg", sys.argv[3])
        mm = importlib.util.module_from_spec(s)
        s.loader.exec_module(mm)
    sys.stderr.write("maat.json: %s\n" % (u.messaggio or mm.T("worktree-lib.config_invalid", rc=u.codice)))
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
        # 1.9.0 (K3): where wt_prova_crea runs the preparazione, as the module's gates (gates.sh esegui)
        print("\t".join(["prepamb", rad, m.get("ambiente") or "nativo", m["nome"]]))
    if m.get("copia"):
        print("\t".join(["copia", mc.norm(m["radice_pacchetti"]) or ".", rad, v(guida)]))
EOF
)
_WT_CONF="" _WT_CONF_OK=""
wt_conf_carica() { # reads the main tree's maat.json once (subshells inherit the cache): 1 if invalid
  local cfg out
  [ -n "${FIC_PY:-}" ] || . "$MAAT_SCRIPTS/python.sh" || { echo "${WT_TAG:-replay}: $(msg worktree-lib.no_python)" >&2; return 1; }
  cfg=${MAAT_CONFIG:-${MAIN:-${PROJECT_ROOT:-.}}/.claude/maat.json}
  out=$("$FIC_PY" -c "$WT_CONF_PY" "$(winpath "$MAAT_SCRIPTS/maat-config.py")" "$(winpath "$cfg")" \
         "$(winpath "$MAAT_SCRIPTS/maat_msg.py")" 2>&1) ||
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
  [ -d "$1" ] || { echo "${WT_TAG:-replay}: $(msg worktree-lib.link_src_missing src="$1")" >&2; return 1; }
  { [ -e "$2" ] || [ -L "$2" ]; } && { echo "${WT_TAG:-replay}: $(msg worktree-lib.link_exists dst="$2")" >&2; return 1; }
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
    [ -L "$r/$p" ] && { echo "${WT_TAG:-replay}: $(msg worktree-lib.link_left r="$r" p="$p")" >&2; left=1; }
  done < <(dep_links "$r")
  return $left
}
fic_relgit() { # $1 worktree: .git with a RELATIVE gitdir, readable by WSL's git too (vitest-fast.sh)
  local wt=$1 gd rel
  gd=$(git -C "$wt" rev-parse --absolute-git-dir) || return 1
  rel=$("$FIC_PY" -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]).replace(os.sep, "/"))' \
        "$gd" "$(canon "$wt")" 2>/dev/null | tr -d '\r')
  if [ -z "$rel" ]; then
    echo "${WT_TAG:-replay}: $(msg worktree-lib.relgit_none)" >&2
    return 0
  fi
  printf 'gitdir: %s\n' "$rel" > "$wt/.git" &&
    [ "$(canon "$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)")" = "$(canon "$gd")" ] && return 0
  printf 'gitdir: %s\n' "$gd" > "$wt/.git"   # restore: the worktree must stay removable
  echo "${WT_TAG:-replay}: $(msg worktree-lib.relgit_bad rel="$rel")" >&2
  return 1
}
# Fingerprint of the copy's dependencies: the SAME as test-fast.sh and counterproof.sh (fic_deps_fp of fic-mirror.sh,
# content without CR) on the radice_pacchetti of the maat.json module with copia; no module with copia: empty. It is
# the condition for seeding the dependencies into the worktree's WSL copy.
[ -n "$WTLIB_TEST" ] && [ -f "$WTLIB_TEST/fic-mirror.sh" ] || { echo "worktree-lib: $(msg worktree-lib.no_mirror f="$WTLIB_TEST")" >&2; return 1; }
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
  [ "$a" = "$b" ] && { echo "${WT_TAG:-replay}: $(msg worktree-lib.fp_same a="${a:0:12}")"; return 0; }
  FPWARN="$(msg worktree-lib.fp_diff b="${b:0:12}" a="${a:0:12}")"
  echo "${WT_TAG:-replay}: $(msg worktree-lib.fp_warn w="$FPWARN")" >&2
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
  # MAAT_LINGUA resolved, as in ciclo-worktree.sh: wsl.exe does not pass the environment, and the reasons of
  # fic-mirror.sh (catalog loaded by itself in WSL) follow it
  out=$({ printf 'L=%q R=%q\n' "$l" "$w"
          printf 'export MAAT_LINGUA=%q\n' "$(maat_lingua)"
          printf '%s\n' '. "$L" || exit 1' \
            'r=0; for k in 1 2; do fic_lane_forget "$R" "$k" || r=1; done; fic_mirror_forget "$R" || r=1; exit $r'
        } | if [ $WIN -eq 1 ]; then MSYS_NO_PATHCONV=1 wsl.exe -- bash -s; else bash -s; fi 2>&1); rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  [ $rc -eq 0 ] || echo "${WT_TAG:-replay}: $(msg worktree-lib.forget_left l="$l" w="$w" w="$w" w="$w")" >&2
  return 0
}

# --- throwaway proof worktrees (1.9.0, K3) ---------------------------------------------------------------------------
# Created as corpus/replay.sh always created its own, now here so that replay.sh (fic-replay-*) and run-phase.sh (the
# proof trees of a defective-test deviation, fic-prova-<label>-<AAAAMMGG-hhmmss>) share the code. The caller sets MAIN
# (main tree) and FIC_PY (loaded from python.sh if missing); PROJECT_ROOT and MAAT_ROOT are the project and the plugin
# that the ownership check refuses. Errors: one line on stderr.
#   wt_prova_crea <label> <base>   → $(dirname MAIN)/fic-prova-<label>-<time>: worktree add --detach at <base>, the marker
#        <git dir of the wt>/fic-prova («fic-prova», «path=<wt>», «created=<time>»), relative .git, one link_dep per
#        dep_links of MAIN (linked, never copied). No project file copied by a fixed path: for each module with
#        `preparati`, as ciclo-worktree.sh, the preparati COPIED from the main tree when its guide file (the first glob
#        without wildcards; a module whose globs all have wildcards: any of its files) is there (same dependencies:
#        wt_prova_albero checks them with deps_diff); only if missing there, the module's `preparazione` run in the
#        worktree (its radice, the environment of its gates: WSL for `ambiente: wsl`); then the guide file must exist in
#        the worktree. Stdout: one line, the absolute path. Exit 0 created · 1 not creatable (path exists, worktree add,
#        marker or links failed: what was created is removed with wt_prova_rimuovi first) · 2 usage (<label> outside
#        [A-Za-z0-9._-]+, empty <base>) · 4 preparati missing in the main tree and preparazione failed or absent, or the
#        guide file missing afterwards (the worktree stays and its path is printed: the caller removes it).
#   wt_prova_albero <wt> <tree>   → deps_diff <tree> not empty: exit 2, the files on stderr one per line; then the
#        ownership check and `read-tree -u --reset <tree>` + `read-tree HEAD` (uncommitted changes). Stdout empty. Exit
#        0 applied · 1 not ours or read-tree failed · 2 different dependencies.
#   wt_prova_rimuovi <wt>   → the checks of wt_ours (prefix and marker fic-prova), then forget_mirror, unlink_deps
#        (never recursive), `git worktree remove --force`. Stdout empty. Exit 0 removed, or <wt> missing and not listed
#        (idempotent, for a trap) · 1 refused (not a proof worktree, or a link left: nothing deleted beyond the links)
#        or git failed.
# The pieces shared with replay.sh, parametric on the prefix (fic-replay / fic-prova), their commands through WT_ESEGUI
# (a function that takes the command line; default _wt_esegui: eval): replay.sh sets its `act`, which prints the line
# and runs it unless --dry-run, so its commands and its --dry-run stay byte for byte those of 1.8.
#   wt_ours <path> <prefix>   0 if the path is a worktree created with that prefix: it exists; not the main tree, the
#        project or the plugin, nor inside them; name «<prefix>-…»; root of a git worktree; the marker <prefix> in its git
#        dir with its path; listed by `git worktree list` of MAIN. Otherwise 1, the reason on stderr.
#   _wt_crea <wt> <base> <stamp> <prefix>  ·  _wt_applica <wt> <tree>  ·  _wt_rimuovi <wt> <prefix> (WT_PROVA_ESITO:
#        nostro = check failed, collegamenti = a link left, git = git failed, empty = removed)
_wt_esegui() { eval "$1"; }
_wtq() { printf '%q' "$1"; }
# the two texts that name the creator: replay.sh keeps its own (they name replay.sh), fic-prova the generic ones
_wt_nome_errato() { if [ "$1" = fic-replay ]; then msg replay.bad_name c="$2"; else msg worktree-lib-190.bad_name pfx="$1" c="$2"; fi; }
_wt_senza_marcatore() { if [ "$1" = fic-replay ]; then msg replay.no_marker mk="$2"; else msg worktree-lib-190.no_marker pfx="$1" mk="$2"; fi; }
wt_ours() {
  local p=$1 mk=$2 c gd f w found=0 mainc rootc maatc
  [ -d "$p" ] || { echo "$(msg replay.not_exists p="$p")" >&2; return 1; }
  c=$(canon "$p") mainc=$(canon "$MAIN") rootc=$(canon "${PROJECT_ROOT:-$MAIN}") maatc=$(canon "$MAAT_ROOT")
  case "$c" in "$mainc"|"$mainc"/*) echo "$(msg replay.is_main c="$c")" >&2; return 1 ;; esac
  case "$c" in "$rootc"|"$rootc"/*) echo "$(msg replay.is_project c="$c")" >&2; return 1 ;; esac
  case "$c" in "$maatc"|"$maatc"/*) echo "$(msg replay.is_plugin c="$c")" >&2; return 1 ;; esac
  case "$(basename "$c")" in "$mk"-*) ;; *) echo "$(_wt_nome_errato "$mk" "$c")" >&2; return 1 ;; esac
  [ "$(canon "$(git -C "$c" rev-parse --show-toplevel 2>/dev/null)")" = "$c" ] ||
    { echo "$(msg replay.not_wt_root c="$c")" >&2; return 1; }
  gd=$(git -C "$c" rev-parse --absolute-git-dir 2>/dev/null)
  f="$gd/$mk"
  [ -f "$f" ] || { echo "$(_wt_senza_marcatore "$mk" "$f")" >&2; return 1; }
  [ "$(canon "$(sed -n 's/^path=//p' "$f")")" = "$c" ] || { echo "$(msg replay.marker_other path="$(sed -n 's/^path=//p' "$f")")" >&2; return 1; }
  while IFS= read -r w; do [ "$(canon "$w")" = "$c" ] && found=1; done < <(git -C "$MAIN" worktree list --porcelain | sed -n 's/^worktree //p')
  [ $found -eq 1 ] || { echo "$(msg replay.not_listed c="$c")" >&2; return 1; }
  return 0
}
_wt_crea() { # <wt> <base> <stamp> <prefix>: the commands of replay.sh 1.8 (worktree add, marker, relative .git, links)
  local wt=$1 base=$2 stamp=$3 mk=$4 ex=${WT_ESEGUI:-_wt_esegui} p
  $ex "git -C $(_wtq "$MAIN") worktree add --detach $(_wtq "$wt") $base" || return 1
  $ex "printf '$mk\npath=%s\ncreated=%s\n' $(_wtq "$wt") $stamp > \"\$(git -C $(_wtq "$wt") rev-parse --absolute-git-dir)/$mk\"" || return 1
  $ex "fic_relgit $(_wtq "$wt")" || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    $ex "link_dep $(_wtq "$MAIN/$p") $(_wtq "$wt/$p")" || return 1
  done < <(dep_links "$MAIN")
  return 0
}
_wt_applica() { # <wt> <tree>: the tree as uncommitted changes
  local ex=${WT_ESEGUI:-_wt_esegui}
  $ex "git -C $(_wtq "$1") read-tree -u --reset $2 && git -C $(_wtq "$1") read-tree HEAD"
}
WT_PROVA_ESITO=""
_wt_rimuovi() { # <wt> <prefix>: check, WSL copies, the links first (the removal must never follow them), then git
  local wt=$1 mk=$2 rc
  WT_PROVA_ESITO=""
  wt_ours "$wt" "$mk" || { WT_PROVA_ESITO=nostro; return 1; }
  forget_mirror "$wt"
  unlink_deps "$wt" || { WT_PROVA_ESITO=collegamenti; return 1; }
  git -C "$MAIN" worktree remove --force "$wt"; rc=$?
  [ $rc -eq 0 ] || WT_PROVA_ESITO=git
  return $rc
}
_wt_elencato() { # <path>: 0 if `git worktree list` of MAIN lists it (by canonical form, or by name when it is gone)
  local c w cw
  c=$(canon "$1"); [ -n "$c" ] || c=$1
  while IFS= read -r w; do
    [ "$w" = "$1" ] || [ "$w" = "$c" ] && return 0
    cw=$(canon "$w"); [ -n "$cw" ] && [ "$cw" = "$c" ] && return 0
  done < <(git -C "$MAIN" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  return 1
}
_wt_prep_ha() { # <dir> <glob>…: 0 if at least one glob matches a file under <dir>
  local d=$1 g f fs oifs; shift
  for g in "$@"; do
    oifs=$IFS; IFS=; fs=("$d"/$g); IFS=$oifs   # pk08: empty IFS, an entry with spaces is not split; $g unquoted: * expands
    for f in "${fs[@]}"; do [ -f "$f" ] && return 0; done
  done
  return 1
}
_wt_prepara() { # <wt>: the preparati of every module (above); 0 ok, 4 otherwise (reason on stderr)
  local wt=$1 k rad guida prepcmd globs pre g f rel oifs amb nome wd c tag=${WT_TAG:-worktree-lib}
  local -a gl fs
  local -A amb_di nome_di
  while IFS=$'\t' read -r k rad amb nome; do
    [ "$k" = prepamb ] && { amb_di[$rad]=$amb; nome_di[$rad]=$nome; }
  done < <(wt_conf)
  while IFS=$'\t' read -r k rad guida prepcmd globs; do
    [ "$k" = prep ] || continue
    [ "$guida" = - ] && guida=""; [ "$prepcmd" = - ] && prepcmd=""   # empty fields (wt_conf placeholder)
    IFS=$'\t' read -ra gl <<< "$globs"
    pre=""; [ "$rad" = . ] || pre="$rad/"
    if { [ -n "$guida" ] && [ -f "$MAIN/$pre$guida" ]; } || { [ -z "$guida" ] && _wt_prep_ha "$MAIN/$pre" "${gl[@]}"; }; then
      for g in "${gl[@]}"; do   # copied from the main tree, as ciclo-worktree.sh (a file already in the worktree stays)
        oifs=$IFS; IFS=; fs=("$MAIN/$pre"$g); IFS=$oifs
        for f in "${fs[@]}"; do
          [ -f "$f" ] || continue
          rel=${f#"$MAIN/"}
          [ -f "$wt/$rel" ] && continue
          mkdir -p "$(dirname "$wt/$rel")" && cp "$f" "$wt/$rel" ||
            { echo "$tag: $(msg worktree-lib-190.prep_copy rel="$rel")" >&2; return 4; }
        done
      done
    elif [ -z "$prepcmd" ]; then
      echo "$tag: $(msg worktree-lib-190.prep_none rad="$rad")" >&2; return 4
    else   # missing in the main tree: the module's preparazione in the worktree, where its gates run
      amb=${amb_di[$rad]:-nativo} nome=${nome_di[$rad]:-}
      if [ "$amb" = wsl ]; then
        wd=$(canon "$wt/$pre"); wd=$(wslp "${wd:-$wt/$pre}")
        c="{ export MAAT_MODULO=$(_wtq "$nome"); cd $(_wtq "$wd") && $prepcmd; } 2>&1"
        if [ -n "${FIC_GATES_WSL:-}" ]; then "$FIC_GATES_WSL" "$c" >&2 </dev/null
        elif command -v wsl >/dev/null 2>&1 || command -v wsl.exe >/dev/null 2>&1; then MSYS_NO_PATHCONV=1 wsl -- bash -lc "$c" >&2 </dev/null
        else false
        fi
      else
        (cd "$wt/$pre" && MAAT_MODULO=$nome bash -c "$prepcmd") >&2 </dev/null
      fi || { echo "$tag: $(msg worktree-lib-190.prep_failed rad="$rad" cmd="$prepcmd")" >&2; return 4; }
    fi
    if { [ -n "$guida" ] && [ ! -f "$wt/$pre$guida" ]; } || { [ -z "$guida" ] && ! _wt_prep_ha "$wt/$pre" "${gl[@]}"; }; then
      echo "$tag: $(msg worktree-lib-190.prep_guide rad="$rad" guida="${guida:-${gl[*]}}")" >&2; return 4
    fi
  done < <(wt_conf)
  return 0
}
wt_prova_crea() {
  local label=${1:-} base=${2:-} pd wt rc
  [ $# -eq 2 ] && [ -n "$base" ] && [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] ||
    { echo "${WT_TAG:-worktree-lib}: $(msg worktree-lib-190.usage_crea)" >&2; return 2; }
  [ -n "${FIC_PY:-}" ] || . "$MAAT_SCRIPTS/python.sh" >&2 ||
    { echo "${WT_TAG:-worktree-lib}: $(msg worktree-lib.no_python)" >&2; return 1; }
  wt_conf > /dev/null || return 1   # maat.json not readable: nothing to link or prepare would be a silent half tree
  pd=$(canon "$(dirname "$MAIN")") && [ -n "$pd" ] ||
    { echo "${WT_TAG:-worktree-lib}: $(msg replay.not_exists p="$(dirname "$MAIN")")" >&2; return 1; }
  wt="$pd/fic-prova-$label-$(date +%Y%m%d-%H%M%S)"
  { [ -e "$wt" ] || [ -L "$wt" ]; } && { echo "${WT_TAG:-worktree-lib}: $(msg worktree-lib.link_exists dst="$wt")" >&2; return 1; }
  if ! WT_ESEGUI=_wt_esegui _wt_crea "$wt" "$base" "$(date +%Y%m%d-%H%M%S)" fic-prova >&2; then
    { [ -e "$wt" ] || _wt_elencato "$wt"; } && wt_prova_rimuovi "$wt" >&2
    return 1
  fi
  _wt_prepara "$wt"; rc=$?
  printf '%s\n' "$wt"
  return $rc
}
wt_prova_albero() {
  local wt=${1:-} tr=${2:-} dd
  [ $# -eq 2 ] && [ -n "$wt" ] && [ -n "$tr" ] || { echo "${WT_TAG:-worktree-lib}: $(msg worktree-lib-190.usage_albero)" >&2; return 1; }
  dd=$(deps_diff "$tr")
  [ -z "$dd" ] || { printf '%s\n' "$dd" >&2; return 2; }
  wt_ours "$wt" fic-prova || return 1
  WT_ESEGUI=_wt_esegui _wt_applica "$wt" "$tr" >&2 || return 1
  return 0
}
wt_prova_rimuovi() {
  local wt=${1:-}
  [ -n "$wt" ] || { echo "${WT_TAG:-worktree-lib}: $(msg worktree-lib-190.usage_rimuovi)" >&2; return 1; }
  { [ -e "$wt" ] || [ -L "$wt" ] || _wt_elencato "$wt"; } || return 0   # already gone and not listed: nothing to do
  _wt_rimuovi "$wt" fic-prova >&2 || return 1
  return 0
}
