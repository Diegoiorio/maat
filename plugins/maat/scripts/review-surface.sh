#!/usr/bin/env bash
# review-surface.sh — superficie di review DETERMINISTICA per /implementation-review-cycle.
#
# Perche' esiste: `git diff` da solo NON e' l'implementazione. Esclude lo staged, gli untracked
# (file nuovi), e dopo un commit e' vuoto. E un'approvazione non legata a uno snapshot resta
# "valida" anche se il codice cambia dopo. Questo script risponde a tre domande senza LLM:
#   1. che cosa e' cambiato davvero rispetto alla base?        → snapshot
#   2. quello che era stato approvato e' ancora quello che c'e'? → check
#   3. i test cambiati sono stati indeboliti?                   → test-signals
#
# Sola lettura sul working tree e sull'indice reale. Scrive soltanto oggetti git non referenziati
# (blob/tree) tramite un indice TEMPORANEO: nessun effetto visibile, `git gc` li potera' fra ~2
# settimane (per questo `check` ha un ripiego sull'impronta).
#
# Sottocomandi:
#   snapshot [--base <ref>]
#       Base:  <sha>   (default HEAD; con --base <ref> → merge-base <ref> HEAD)
#       Tree:  <sha>   tree del working tree COMPLETO (tracked + staged + untracked non ignorati)
#       Changes:       name-status base..tree (A/M/D/R/T), rinomine comprese
#       Origin:        git status --porcelain (chi e' staged, chi unstaged, chi untracked)
#   fingerprint --tree <tree> --paths-file <f>
#       sha256 (12 car.) del contenuto dei path elencati nel tree: path + blob, oppure ABSENT.
#   check --base <sha> --tree <old-tree> --paths-file <f> [--fingerprint <fp>] [--exclude-file <f>]
#       --paths-file = SCOPE approvato; --exclude-file = path esclusi dallo scope (altro flusso).
#       Ricalcola lo snapshot sulla base REGISTRATA (mai HEAD: un commit dopo l'approvazione non
#       e' una modifica) e dice FRESH | STALE | UNKNOWN, il delta, e se il delta e' "solo test,
#       senza infrastruttura di test e senza segnali di indebolimento; nei test gia' esistenti solo
#       aggiunte pure, senza setup condiviso ne' flusso di controllo" (Gate-only eligible: yes, oppure
#       no — <motivo>).
#       Un file escluso che cambia NON rende stale, ma viene riportato come EXCLUDED-CHANGED:
#       chi orchestra deve guardarlo (un file misto puo' portare codice della feature).
#   test-signals --from <tree-ish> --to <tree-ish> [--paths-file <f>]
#       Segnali di test indeboliti fra due tree-ish, eventualmente limitati ai path del file.
#   tree
#       Solo lo sha del tree del working tree completo (come "Tree" di snapshot). Lo usa run-phase.sh
#       prima e dopo le fasi implement/fix per sapere quali path ha cambiato la fase (touched.txt).
#   diff --from <tree-ish> --to <tree-ish> --paths-file <f> --out <file>
#       Scrive in <file> il diff dei path elencati (file nuovi non tracciati compresi, perche' --to e' un
#       tree) e stampa l'indice "<path><TAB>offset=N limit=M" per leggerlo a pezzi con Read. E' il modo in
#       cui l'implementation-reviewer vede la superficie senza avere Bash. Una rinomina appare come tale
#       solo se entrambi i path sono nell'elenco; altrimenti come A + D.
#
# I path sono stampati SENZA quoting di git (core.quotePath=false): un nome non ASCII tra
# virgolette ottali non combacerebbe piu' con se stesso fra manifest, pathspec e confronti.
#
# Exit: 0 ok · 2 uso errato · 3 check UNKNOWN (tree potato e nessuna impronta per il ripiego).

set -uo pipefail
set -f

die() { echo "review-surface: $*" >&2; exit 2; }
g() { git -c core.quotePath=false "$@"; }

g rev-parse --git-dir >/dev/null 2>&1 || die "non e' un repository git"
TOP=$(g rev-parse --show-toplevel)
cd "$TOP" || die "impossibile entrare in $TOP"

# File di test: il perimetro dei "test-signals" e del percorso gate-only. `script/` escluso di
# proposito: script/e2e/ e' infrastruttura dello stack, non un test.
TEST_RE='(^|/)(tests?|__tests__|e2e)/|\.(test|spec)\.[cm]?[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$|(^|/)conftest\.py$|__snapshots__/|\.snap$'
NOT_TEST_RE='^script/'
# Infrastruttura di test: cambiarla puo' far passare tutto senza toccare una sola asserzione.
# Ammessa nel diff, mai nel percorso gate-only (richiede sempre un giro di review).
TEST_INFRA_RE='(^|/)conftest\.py$|(^|/)(fixtures?|mocks?|__mocks__|fakes?|helpers?|support|utils?)/|(^|/)(setup|global-setup|vitest\.setup)[^/]*\.[cm]?[jt]s$|\.(fixture|mock|fake)s?\.[cm]?[jt]sx?$'
# Il percorso gate-only ammette SOLO file di test veri e propri. Tutto il resto sotto tests/,
# __tests__/, e2e/ (un fake, un helper, una factory: tests/goals_fakes.py) e' infrastruttura.
TEST_FILE_RE='\.(test|spec)\.[cm]?[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$'
# Asserzioni: `expect(` e i matcher anche quando prettier li manda a capo senza `expect(` sulla
# riga (`).toStrictEqual(`), `expect.soft(`, unittest (`self.assertEqual(`), mock (`.assert_called_with(`).
ASSERT_RE='expect\(|expect\.[A-Za-z_]+\(|\bassert\b|pytest\.raises|\.to(Be|Equal|StrictEqual|Have|Contain|Match|Throw|Satisfy)[A-Za-z_]*\(|\.(resolves|rejects)\b|\.assert(_[A-Za-z_]+|[A-Z][A-Za-z_]*)\('
SKIP_RE='\b(it|test|describe)\.(skip|only|todo|fixme|skipIf|runIf)\b|\bx(it|describe|test)\(|pytest\.mark\.(skip|skipif|xfail)|pytest\.skip\(|@unittest\.skip|test\.fail\('
SNAP_RE='__snapshots__/|\.snap$|(^|/)(golden|snapshots?)/'
# Percorso gate-only, file di test GIA' esistenti nel tree approvato: solo aggiunte pure. Una riga
# tolta o cambiata (il valore atteso su una riga di continuazione, un input, il ruolo usato) cambia la
# forza di un test che un revisore ha gia' visto; e alcune aggiunte cambiano i test esistenti senza
# una sola riga `-`: setup condiviso (vi.mock e' hoisted su tutto il file, un beforeEach, un autouse)
# e flusso di controllo (un `return` in testa, un `if`/`try` attorno ad asserzioni esistenti).
# Ai file NUOVI non si applica: non hanno test preesistenti da alterare.
SHARED_SETUP_RE='\b(vi|jest)\.(mock|doMock|stubGlobal|stubEnv)\(|\b(before|after)(Each|All)\(|autouse[[:space:]]*=[[:space:]]*True'
CONTROL_RE='^\+[[:space:]]*(return[[:space:]]*;?[[:space:]]*$|if\b|for\b|while\b|with\b|try\b|except\b|catch\b|continue\b|break\b|else\b|pass[[:space:]]*$)'

is_test() { printf '%s\n' "$1" | grep -Ev "$NOT_TEST_RE" | grep -Eq "$TEST_RE"; }

# Tree del working tree completo. L'indice temporaneo e' SEMINATO con una copia di quello reale:
# con core.autocrlf=true un indice vuoto farebbe ri-hashare ogni file e produrrebbe centinaia di
# cambi fittizi (misurato: 392 su questo repo, piu' la perdita del bit eseguibile).
# `cp -p` conserva l'mtime dell'indice: con un mtime nuovo git perderebbe la rilevazione dei file
# "racy" (modificati nello stesso secondo dell'ultimo add) e ometterebbe un cambio vero.
snapshot_tree() {
  local tmp idx tree
  idx=$(g rev-parse --git-path index)
  tmp=$(mktemp) || die "mktemp fallito"
  if [ -f "$idx" ]; then cp -p "$idx" "$tmp"; else rm -f "$tmp"; fi
  GIT_INDEX_FILE="$tmp" g add -A >/dev/null 2>&1 || { rm -f "$tmp"; die "git add -A (indice temporaneo) fallito"; }
  tree=$(GIT_INDEX_FILE="$tmp" g write-tree) || { rm -f "$tmp"; die "git write-tree fallito"; }
  rm -f "$tmp"
  echo "$tree"
}

resolve_base() {
  local ref=${1:-}
  if [ -z "$ref" ]; then g rev-parse HEAD; return; fi
  g rev-parse --verify -q "$ref^{commit}" >/dev/null || die "base '$ref' non risolvibile"
  g merge-base "$ref" HEAD 2>/dev/null || g rev-parse "$ref^{commit}"
}

read_paths() { # stampa i path del file, senza righe vuote, ordinati e unici
  [ -f "$1" ] || die "paths-file '$1' inesistente"
  tr -d '\r' < "$1" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u
}

pathspecs() { # $1 paths-file → array globale SPECS di pathspec letterali
  SPECS=()
  [ -n "${1:-}" ] || return 0
  mapfile -t SPECS < <(read_paths "$1" | sed 's/^/:(literal)/')
}

fingerprint_of() { # $1 tree, $2 paths-file
  local tree=$1 pf=$2 p line
  {
    while IFS= read -r p; do
      line=$(g ls-tree "$tree" -- ":(literal)$p" 2>/dev/null)
      if [ -n "$line" ]; then printf '%s\n' "$line"; else printf 'ABSENT\t%s\n' "$p"; fi
    done < <(read_paths "$pf")
  } | sha256sum | cut -c1-12
}

signals() { # $1 from, $2 to, [$3 paths-file]
  local from=$1 to=$2 pf=${3:-} out="" f st old keep
  keep=""
  [ -n "$pf" ] && keep=$(read_paths "$pf")
  # Rinomine: si confronta il contenuto VECCHIO col NUOVO (`from:old` vs `to:new`). Con il solo
  # path nuovo un test rinominato e svuotato nello stesso passo non darebbe alcun segnale; con
  # --no-renames una rinomina pura darebbe un falso DELETED-TEST.
  while IFS=$'\t' read -r st old f; do
    [ -z "${f:-}" ] && f=$old
    if [ -n "$pf" ]; then
      printf '%s\n' "$keep" | grep -qxF -- "$f" || printf '%s\n' "$keep" | grep -qxF -- "$old" || continue
    fi
    is_test "$f" || is_test "$old" || continue
    case "$st" in D*) out+="DELETED-TEST ${f}"$'\n'; continue ;; esac
    if printf '%s\n' "$f" | grep -Eq "$SNAP_RE"; then out+="SNAPSHOT-CHANGED ${f}"$'\n'; fi
    local diff rem add skips
    case "$st" in
      R*) diff=$(g diff --no-color --no-ext-diff -U0 "$from:$old" "$to:$f" | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---) ') ;;
      *)  diff=$(g diff --no-color --no-ext-diff -U0 "$from" "$to" -- ":(literal)$f" | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---) ') ;;
    esac
    rem=$(printf '%s\n' "$diff" | grep -E '^-' | grep -cE "$ASSERT_RE")
    add=$(printf '%s\n' "$diff" | grep -E '^\+' | grep -cE "$ASSERT_RE")
    [ "${rem:-0}" -gt 0 ] && out+="REMOVED-ASSERTIONS ${f}: -${rem} +${add:-0}"$'\n'
    skips=$(printf '%s\n' "$diff" | grep -E '^\+' | grep -E "$SKIP_RE" | head -3 | sed 's/^+[[:space:]]*/    /')
    [ -n "$skips" ] && out+="ADDED-SKIP ${f}"$'\n'"${skips}"$'\n'
  done < <(g diff --no-color --name-status -M "$from" "$to")
  if [ -z "$out" ]; then echo "Test signals: none"; else printf 'Test signals:\n%s' "$out"; fi
}

cmd=${1:-}; shift || true
BASE="" TREE="" FROM="" TO="" PF="" FP="" XF="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE=${2:-}; shift 2 ;;
    --tree) TREE=${2:-}; shift 2 ;;
    --from) FROM=${2:-}; shift 2 ;;
    --to) TO=${2:-}; shift 2 ;;
    --paths-file) PF=${2:-}; shift 2 ;;
    --fingerprint) FP=${2:-}; shift 2 ;;
    --exclude-file) XF=${2:-}; shift 2 ;;
    --out) OUT=${2:-}; shift 2 ;;
    *) die "argomento sconosciuto: $1" ;;
  esac
done

case "$cmd" in
  snapshot)
    base=$(resolve_base "$BASE") || exit 2
    tree=$(snapshot_tree) || exit 2
    echo "Base: $base"
    echo "Tree: $tree"
    echo "Changes (base..tree):"
    changes=$(g diff --no-color --name-status -M "$base" "$tree")
    if [ -z "$changes" ]; then echo "  (none)"; else printf '%s\n' "$changes" | sed 's/^/  /'; fi
    echo "Origin (git status --porcelain):"
    st=$(g status --porcelain=v1 -uall)
    if [ -z "$st" ]; then echo "  (clean)"; else printf '%s\n' "$st" | sed 's/^/  /'; fi
    ;;
  fingerprint)
    [ -n "$TREE" ] && [ -n "$PF" ] || die "uso: fingerprint --tree <tree> --paths-file <f>"
    g cat-file -e "$TREE^{tree}" 2>/dev/null || die "tree $TREE non presente"
    echo "Fingerprint: $(fingerprint_of "$TREE" "$PF")"
    ;;
  check)
    [ -n "$BASE" ] && [ -n "$TREE" ] && [ -n "$PF" ] || die "uso: check --base <sha> --tree <tree> --paths-file <f> [--fingerprint <fp>] [--exclude-file <f>]"
    g rev-parse --verify -q "$BASE^{commit}" >/dev/null || die "base $BASE non presente"
    new=$(snapshot_tree) || exit 2
    echo "Current tree: $new"
    # Path nuovi rispetto alla base REGISTRATA che non erano nel manifest approvato.
    known=$( { read_paths "$PF"; [ -n "$XF" ] && read_paths "$XF"; } | LC_ALL=C sort -u)
    added=$(comm -13 <(printf '%s\n' "$known") <(g diff --name-only --no-renames "$BASE" "$new" | LC_ALL=C sort -u) | grep -v '^$')
    if g cat-file -e "$TREE^{tree}" 2>/dev/null; then
      pathspecs "$PF"
      delta=""
      [ ${#SPECS[@]} -gt 0 ] && delta=$(g diff --no-color --name-status --no-renames "$TREE" "$new" -- "${SPECS[@]}")
      excl=""
      if [ -n "$XF" ]; then
        pathspecs "$XF"
        [ ${#SPECS[@]} -gt 0 ] && excl=$(g diff --no-color --name-only --no-renames "$TREE" "$new" -- "${SPECS[@]}")
      fi
      if [ -z "$delta" ] && [ -z "$added" ]; then
        echo "Status: FRESH"
        [ -n "$excl" ] && printf '%s\n' "$excl" | sed 's/^/  EXCLUDED-CHANGED\t/'
        exit 0
      fi
      echo "Status: STALE"
      echo "Delta (approved tree → current, manifest paths):"
      [ -n "$delta" ] && printf '%s\n' "$delta" | sed 's/^/  /'
      [ -n "$added" ] && printf '%s\n' "$added" | sed 's/^/  NEW-SURFACE\t/'
      [ -n "$excl" ] && printf '%s\n' "$excl" | sed 's/^/  EXCLUDED-CHANGED\t/'
      # Percorso gate-only: TUTTI i path del delta sono test (non infrastruttura di test), e i
      # test del delta non mostrano segnali di indebolimento.
      all=$( { printf '%s\n' "$delta" | cut -f2-; printf '%s\n' "$added"; } | grep -v '^$')
      dfile=$(mktemp) || die "mktemp fallito"
      printf '%s\n' "$all" > "$dfile"
      sig=$(signals "$TREE" "$new" "$dfile")
      rm -f "$dfile"
      printf '%s\n' "$sig"
      # Lo stato A/M di ogni path si decide contro il tree APPROVATO, non da `$delta`: i NEW-SURFACE
      # (fuori manifest) non hanno uno stato, e un test preesistente fuori manifest a cui si aggiunge
      # un vi.mock e' un file MODIFICATO. Senza `-w`: in Python l'indentazione e' semantica.
      eligible=yes why=""
      while IFS= read -r p; do
        [ -z "$p" ] && continue
        if ! is_test "$p" || ! printf '%s\n' "$p" | grep -Eq "$TEST_FILE_RE"; then eligible=no; why="non e' un file di test: $p"; break; fi
        if printf '%s\n' "$p" | grep -Eq "$TEST_INFRA_RE"; then eligible=no; why="infrastruttura di test: $p"; break; fi
        g cat-file -e "$TREE:$p" 2>/dev/null || continue   # file nuovo: nessun test preesistente
        d=$(g diff --no-color --no-ext-diff -U0 --ignore-blank-lines --ignore-space-at-eol "$TREE" "$new" -- ":(literal)$p" | grep -Ev '^(\+\+\+|---) ')
        if printf '%s\n' "$d" | grep -Eq '^-.*[^[:space:]]'; then eligible=no; why="righe tolte o modificate in un test esistente: $p"; break; fi
        if printf '%s\n' "$d" | grep -E '^\+' | grep -Eq "$SHARED_SETUP_RE"; then eligible=no; why="setup condiviso aggiunto a un test esistente: $p"; break; fi
        if printf '%s\n' "$d" | grep -Eq "$CONTROL_RE"; then eligible=no; why="flusso di controllo aggiunto a un test esistente: $p"; break; fi
      done <<< "$all"
      if [ "$sig" != "Test signals: none" ]; then eligible=no; why="segnali di indebolimento"; fi
      if [ "$eligible" = yes ]; then echo "Gate-only eligible: yes"; else echo "Gate-only eligible: no — $why"; fi
    else
      [ -n "$FP" ] || { echo "Status: UNKNOWN (tree $TREE potato da gc, nessuna impronta registrata)"; exit 3; }
      cur=$(fingerprint_of "$new" "$PF")
      if [ "$cur" = "$FP" ] && [ -z "$added" ]; then echo "Status: FRESH (via fingerprint)"; exit 0; fi
      echo "Status: STALE (via fingerprint; delta non ricostruibile → giro a scope pieno)"
      [ -n "$added" ] && printf '%s\n' "$added" | sed 's/^/  NEW-SURFACE\t/'
      echo "Gate-only eligible: no — delta non ricostruibile"
    fi
    ;;
  test-signals)
    [ -n "$FROM" ] && [ -n "$TO" ] || die "uso: test-signals --from <tree-ish> --to <tree-ish> [--paths-file <f>]"
    signals "$FROM" "$TO" "$PF"
    ;;
  tree)
    snapshot_tree
    ;;
  diff)
    [ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$PF" ] && [ -n "$OUT" ] || die "uso: diff --from <tree-ish> --to <tree-ish> --paths-file <f> --out <file>"
    pathspecs "$PF"
    [ ${#SPECS[@]} -gt 0 ] || die "paths-file vuoto: nessun path da mostrare"
    g diff --no-color --no-ext-diff -M "$FROM" "$TO" -- "${SPECS[@]}" > "$OUT" || die "git diff fallito"
    [ -s "$OUT" ] || { echo "(nessuna differenza)"; exit 0; }
    # "diff --git a/P b/P": P = meta' di cio' che segue "a/", tolto " b/"; le rinomine lo dicono esplicito.
    awk '
      function emit(e) { if (s) printf "%s\toffset=%d limit=%d\n", name, s, e - s + 1 }
      /^diff --git a\// { emit(NR - 1); s = NR; r = substr($0, 12); name = substr(r, 3, (length(r) - 5) / 2); old = ""; next }
      s && /^rename from / { old = substr($0, 13); next }
      s && /^rename to / { name = old " → " substr($0, 11); next }
      END { emit(NR) }' "$OUT"
    ;;
  *) die "sottocomando: snapshot | fingerprint | check | test-signals | tree | diff" ;;
esac
