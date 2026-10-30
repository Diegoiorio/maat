# fic-mirror.sh — funzioni condivise della copia WSL (harness-pt03): destinazione, impronta delle dipendenze,
# semina di node_modules, cancellazione della copia di un worktree. Si INCLUDE con `.` da test-fast.sh,
# counterproof.sh e (via WSL) corpus/replay.sh: non si esegue, e non ha effetti finche' non si chiama una funzione.
# Scrive solo sotto $HOME/fic-mirror-<hash> (mai in $HOME/fic-mirror, mai nel repository).
#
# CARTELLA DEI PACCHETTI: la decide il CHIAMANTE, nessun default. E' la radice dei pacchetti del modulo
# (`radice_pacchetti` di maat.json), relativa al repository; la copia la tiene allo stesso percorso relativo,
# <copia> = $FIC_MIRROR/<cartella>. Il chiamante la passa nei due argomenti <origine> = <radice>/<cartella> e
# <copia> = $FIC_MIRROR/<cartella>; le funzioni ne ricavano <cartella> (fic__pkg) per trovare le copie collegate
# (quella del tree principale, quella della radice di una corsia) allo stesso percorso. Una <copia> fuori da
# $FIC_MIRROR e' un errore del chiamante: motivo e uscita 1, mai una cartella indovinata.
#
# DESTINAZIONE (fic_mirror_init <radice>): $HOME/fic-mirror dal tree principale, $HOME/fic-mirror-<primi 12
# caratteri dello sha256 della radice> da un worktree collegato (git-dir diverso da git-common-dir).
# Worktree creato da Git per Windows: il suo file .git dice "gitdir: C:/…", che il git di WSL non risolve; qui
# si traduce in /mnt/c/… ed e' esportato come GIT_DIR (con GIT_WORK_TREE = radice), cosi' valgono sia la
# destinazione sia il manifest. FIC_WSL_MNT cambia la radice delle unita' (default /mnt; serve ai test).
#
# IMPRONTA DELLE DIPENDENZE (fic_deps_fp): tutti i package.json fuori da node_modules/.nuxt/.output e i
# package-lock.json, sul contenuto SENZA CR: due checkout con fine riga diverse danno la stessa impronta.
# fic_deps_ok accetta anche un .fic-deps scritto prima di questa regola (impronta dei byte).
#
# SEMINA (fic_seed_node_modules): la copia di un worktree senza node_modules li prende dalla copia del tree
# principale con hardlink (rsync --link-dest: niente installazioni, niente spazio), SOLO se quella copia e'
# valida per il tree principale e le dipendenze del worktree coincidono (impronta normalizzata) con quelle del
# tree principale. Le cache (.cache, .vite, .vitest) non si seminano: le scrive il run, come file nuovi.
# Una fonte della semina stantia (copia del tree principale o della radice) si riallinea prima, sotto il SUO lock.
#
# RIALLINEAMENTO AUTOMATICO (fic_deps_autorefresh, dentro il lock della copia; lo chiamano test-fast.sh e
# counterproof.sh quando fic_deps_ok e' falso): mai un'installazione, mai la rete, solo copie locali.
# - origine con node_modules -> fic_deps_refresh, la stessa operazione del --setup (rsync dall'origine, node_modules
#   compresi, stesse esclusioni, poi l'impronta);
# - worktree senza node_modules -> copia del tree principale riallineata se stantia (dal tree principale, che
#   deve avere node_modules; sotto il lock di quella copia), poi semina di nuovo, se le dipendenze coincidono;
# - copia di corsia -> copia della radice riallineata come sopra (sotto il suo lock), poi semina di nuovo da quella;
# - nessuna fonte con node_modules, o dipendenze del worktree diverse da quelle del tree principale -> motivo, e il
#   chiamante esce BLOCKED. Durante il rsync .fic-deps vale "interrotto": un rsync fallito lascia la copia stantia.
# Ordine dei lock: dalla copia derivata (corsia, worktree) verso la copia della radice e quella del tree principale,
# mai il contrario: nessun ciclo.
# Limite dichiarato: un hardlink condivide l'inode; un processo che riscrivesse SUL POSTO un file di
# node_modules della copia del worktree cambierebbe anche quello della copia principale. vitest/eslint non
# lo fanno (le cache escluse sopra); un --setup del worktree riscrive i file con rsync, che sostituisce.
#
# CANCELLAZIONE (fic_mirror_forget <radice di un worktree>): la copia di QUEL worktree, mai quella del tree
# principale; se un run la tiene (uno qualunque dei suoi lock <cartella>/.fic-lock), resta. La chiama replay.sh
# alla fine di un rigioco. I lock si cercano nella copia (fic__locks): la cancellazione non dipende dalla cartella.
#
# ESCLUSIONI DEL SYNC (FIC_MIRROR_EXCL, l'unica variabile che l'inclusione definisce): un elenco solo del nucleo,
# usato da test-fast.sh e counterproof.sh per ogni modulo — dipendenze installate, file generati e cache dei runner
# (node_modules, .nuxt, .output, coverage, .turbo, .venv, __pycache__, .pytest_cache) e lo stato della copia
# (/.fic-*). Una cartella che in un modulo non c'e' non cambia nulla; counterproof.sh ci aggiunge le cartelle di
# `collega_nel_worktree` del modulo.
#
# PULIZIA (fic_mirror_pulisci <copia> <radice relativa> [<runner> [glob dei preparati…]]): toglie dalla copia le
# cartelle che contengono i `preparati` del modulo (glob relativi alla radice; una voce senza cartella toglie i suoi
# file) e, se il runner delle controprove e' vitest, le cache di vite/vitest (adattatore vitest del nucleo, come
# FIC_VITE_CACHE_DIR). Modulo senza preparati e senza runner vitest: niente da ripulire. Quando: lo decide il
# chiamante (counterproof.sh a ogni sync, test-fast.sh quando cambiano dipendenze o tsconfig generato).
#
# CORSIE (harness-pt13): fic_lane_init <k> (k = 1..9, dopo fic_mirror_init) sposta FIC_MIRROR sulla copia della
# corsia, <copia della radice>-<k>, col suo <cartella>/.fic-lock e le sue cache vite/vitest; FIC_LANE_BASE resta
# la copia della radice. La semina della copia di corsia prende node_modules in hardlink da QUELLA copia (valida
# per le dipendenze attuali), non da ~/fic-mirror. fic_lane_forget <radice> <k> cancella la sola copia di corsia
# (~/fic-mirror-<k> o ~/fic-mirror-<12 hex>-<k>), mai una copia della radice; se un run la tiene, resta.
#
# COPIA CON RIPIEGO (pk08, fic_sync [--delete] [--checksum] [--exclude=<p>…] <origine>/ <copia>/): `rsync -a` con gli
# stessi argomenti se rsync c'e'; altrimenti (Git Bash su Windows senza WSL) fic__sync_ripiego, con lo stesso risultato
# osservabile, piu' lento:
# - esclusioni come rsync: un nome senza / a ogni profondita', /x ancorato alla radice del trasferimento, a/b in coda
#   al percorso; nella copia i percorsi esclusi non si cancellano (come rsync senza --delete-excluded);
# - --delete: cio' che nella copia non c'e' nell'origine (fuori dalle esclusioni) si cancella; una cartella che
#   contiene percorsi esclusi (es. node_modules) resta, con quelli, e perde solo il resto, come rsync (review di pk08);
# - differenze note da rsync, non corrette (nessun pattern del harness le tocca): in un pattern con / il `*` di find
#   -path attraversa anche le /, quello di rsync no; la / finale di un pattern (rsync: solo cartelle) si toglie e il
#   pattern vale anche per i file;
# - un file si riscrive (unlink, poi tar) se manca, se cambia tipo, se il bit x o l'impronta sha256 differiscono:
#   sempre il confronto del contenuto, come --checksum; cartelle e link simbolici come rsync -a.
# Uscita: 0 · 23 copia non riuscita (come rsync) · 2 opzione che il ripiego non gestisce. Lo usa counterproof.sh;
# test-fast.sh e le funzioni qui sopra (semina, riallineamento) restano su rsync: la copia veloce vuole WSL.
#
# LOCK SENZA flock (pk08, fic_lock_dir <cartella> [<attesa in s>, vuota = senza tetto] · fic_unlock_dir <cartella>):
# mkdir atomico di <cartella>, con dentro il pid di chi la tiene. Un lock il cui pid non vive piu' (KILL, morte della
# shell) e' orfano: chi attende lo riprende, uno alla volta (<cartella>.rec, anch'esso un mkdir) e dopo aver riletto
# il pid; e' l'equivalente di flock, che si libera da se' quando muore chi lo tiene. Anche un lock SENZA pid (morte fra
# il mkdir e la scrittura del pid) e' orfano, se la sua cartella ha piu' di 10 s (mtime): si riprende allo stesso modo
# (review di pk08). Non si riprende un .rec orfano: l'attesa scade, e il chiamante da' il percorso.
# Chi ha fatto il mkdir scrive il pid senza sovrascrivere (noclobber) e lo rilegge: se il file c'era gia' o il pid
# riletto non e' il suo (un processo fermo oltre 10 s fra mkdir e scrittura, nel frattempo ripreso da un altro), il
# lock non e' suo e riprova come in attesa (review giro 2 di pk08). Limiti dichiarati: la soglia dei 10 s confronta
# l'orologio locale (`date +%s`) con la mtime scritta dal file system, che su drvfs (/mnt/<lettera>/) o su una cartella
# di rete puo' avere un orologio diverso: uno scarto di qualche secondo anticipa o ritarda la ripresa di un lock senza
# pid; e resta una finestra stretta (il processo fermo scrive il pid proprio fra il controllo di chi riprende e il suo
# rm) che solo un lock del sistema operativo chiuderebbe.
# Il rilascio e' del chiamante (trap EXIT): fic_unlock_dir toglie la cartella solo se il pid e' il suo.

FIC_MIRROR_EXCL=(--exclude=node_modules --exclude=.nuxt --exclude=.output --exclude=coverage --exclude=.turbo
  --exclude=.venv --exclude=__pycache__ --exclude=.pytest_cache --exclude='/.fic-*')

fic_mirror_pulisci() { # <copia> <radice relativa ("" = la copia stessa)> [<runner> [glob dei preparati…]] → 0 · 1 rm fallito
  local dst=$1 base=$1${2:+/$2} run=${3:-} g v IFS=   # pk08: IFS vuoto, una voce con spazi non si divide nel rm
  shift 2; [ $# -gt 0 ] && shift
  for g in "$@"; do
    case "$g" in */*) v=${g%/*} ;; *) v=$g ;; esac
    case "/$v/" in *"/../"*|//*) continue ;; esac   # mai fuori dalla radice
    [ -n "$v" ] && [ "$v" != . ] || continue
    rm -rf -- "$base"/$v || return 1   # $v senza virgolette: una cartella col * si espande nella copia
  done
  if [ "$run" = vitest ]; then
    rm -rf -- "$base/node_modules/.vite" "$dst/node_modules/.vite" "$dst/node_modules/.vitest" || return 1
  fi
}

fic_sync() { # [--delete] [--checksum] [--exclude=<p>…] <origine>/ <copia>/ → rsync -a, o il ripiego senza rsync
  if command -v rsync >/dev/null 2>&1; then rsync -a "$@"; else fic__sync_ripiego "$@"; fi
}

fic__escludi() { # <pattern…> → FIC__FX: le esclusioni come espressione di find, con la semantica di rsync
  local p
  FIC__FX=()
  for p in "$@"; do
    p=${p%/}
    [ -n "$p" ] || continue
    case "$p" in
      /*) FIC__FX+=(-o -path "./${p#/}") ;;
      */*) FIC__FX+=(-o -path "./$p" -o -path "*/$p") ;;
      *) FIC__FX+=(-o -name "$p") ;;
    esac
  done
  if [ ${#FIC__FX[@]} -gt 0 ]; then FIC__FX=("${FIC__FX[@]:1}"); else FIC__FX=(-false); fi
}

fic__sync_ripiego() { # gli argomenti di fic_sync, senza rsync: find + sha256sum + tar
  local del=0 src dst p s d i ts td
  local -a ex=() nuovi=() comuni=() cartelle=() hs=() hd=()
  while [ $# -gt 2 ]; do
    case "$1" in
      --delete) del=1 ;;
      --checksum) ;;   # il ripiego confronta sempre il contenuto
      --exclude=*) ex+=("${1#--exclude=}") ;;
      *) echo "fic_sync: opzione non gestita dal ripiego senza rsync: $1" >&2; return 2 ;;
    esac
    shift
  done
  [ $# -eq 2 ] || { echo "fic_sync: servono <origine>/ <copia>/" >&2; return 2; }
  src=${1%/} dst=${2%/}
  [ -d "$src" ] && mkdir -p "$dst" || return 23
  fic__escludi ${ex[@]+"${ex[@]}"}
  if [ "$del" = 1 ]; then   # nella copia, fuori dalle esclusioni, cio' che nell'origine non c'e'
    while IFS= read -r -d '' p; do
      [ -e "$dst/$p" ] || [ -L "$dst/$p" ] || continue   # gia' tolto con la cartella che lo conteneva
      [ -e "$src/$p" ] || [ -L "$src/$p" ] && continue
      if [ -d "$dst/$p" ] && [ ! -L "$dst/$p" ] &&   # con dentro degli esclusi: resta, il resto lo toglie questo giro
         [ -n "$(cd "$dst" && find "$p" -mindepth 1 \( "${FIC__FX[@]}" \) -print -quit)" ]; then continue; fi
      rm -rf -- "${dst:?}/$p" || return 23
    done < <(cd "$dst" && find . -mindepth 1 \( "${FIC__FX[@]}" \) -prune -o -print0)
  fi
  while IFS= read -r -d '' p; do   # dall'origine, cartelle prima del contenuto
    s=$src/$p d=$dst/$p
    if [ -L "$s" ]; then
      [ -L "$d" ] && [ "$(readlink "$s")" = "$(readlink "$d")" ] && continue
      rm -rf -- "$d" || return 23
      nuovi+=("$p")
    elif [ -d "$s" ]; then
      if [ -L "$d" ] || { [ -e "$d" ] && [ ! -d "$d" ]; }; then rm -f -- "$d" || return 23; fi
      [ -d "$d" ] || cartelle+=("$p")
    else
      if [ -L "$d" ] || [ -d "$d" ]; then rm -rf -- "$d" || return 23; fi
      if [ -e "$d" ] && { [ -x "$s" ] && [ -x "$d" ] || { [ ! -x "$s" ] && [ ! -x "$d" ]; }; }; then comuni+=("$p")
      else nuovi+=("$p"); fi
    fi
  done < <(cd "$src" && find . -mindepth 1 \( "${FIC__FX[@]}" \) -prune -o -print0)
  if [ ${#comuni[@]} -gt 0 ]; then   # impronte dei file a comune, in blocco: una riga per file, nello stesso ordine
    ts=$(mktemp) && td=$(mktemp) || return 23
    if (cd "$src" && printf '%s\0' "${comuni[@]}" | xargs -0 sha256sum) > "$ts" &&
       (cd "$dst" && printf '%s\0' "${comuni[@]}" | xargs -0 sha256sum) > "$td"; then
      mapfile -t hs < "$ts"; mapfile -t hd < "$td"
    fi
    rm -f "$ts" "$td"
    [ ${#hs[@]} -eq ${#comuni[@]} ] && [ ${#hd[@]} -eq ${#comuni[@]} ] || return 23
    for i in "${!comuni[@]}"; do [ "${hs[i]}" = "${hd[i]}" ] || nuovi+=("${comuni[i]}"); done
  fi
  if [ ${#cartelle[@]} -gt 0 ]; then
    (cd "$dst" && printf '%s\0' "${cartelle[@]}" | xargs -0 mkdir -p --) || return 23
  fi
  if [ ${#nuovi[@]} -gt 0 ]; then   # unlink + scrittura nuova, come rsync (mai sul posto: un hardlink resta intatto)
    (cd "$dst" && printf '%s\0' "${nuovi[@]}" | xargs -0 rm -f --) || return 23
    (cd "$src" && printf '%s\0' "${nuovi[@]}" | tar --null --no-recursion -T - -cf -) | (cd "$dst" && tar -xpf -)
    [ "${PIPESTATUS[0]}${PIPESTATUS[1]}" = 00 ] || return 23
  fi
}

fic_lock_dir() { # <cartella di lock> [<attesa in s>, vuota = senza tetto] → 0 preso · 1 oltre l'attesa
  local d=$1 wait=${2:-} me=${BASHPID:-$$} t0=$SECONDS p
  while :; do
    until mkdir "$d" 2>/dev/null; do
      p=$(cat "$d/pid" 2>/dev/null)
      if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null && mkdir "$d.rec" 2>/dev/null; then
        p=$(cat "$d/pid" 2>/dev/null)   # riletto sotto .rec: nel frattempo un altro puo' averlo ripreso e preso
        if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then rm -rf -- "$d"; fi
        rmdir "$d.rec" 2>/dev/null
        continue
      fi
      if [ -z "$p" ] && fic__lock_vecchio "$d" && mkdir "$d.rec" 2>/dev/null; then   # senza pid da oltre 10 s: orfano
        [ -z "$(cat "$d/pid" 2>/dev/null)" ] && fic__lock_vecchio "$d" && rm -rf -- "$d"   # riletto sotto .rec
        rmdir "$d.rec" 2>/dev/null
        continue
      fi
      [ -z "$wait" ] || [ $((SECONDS - t0)) -lt "$wait" ] || return 1
      sleep 0.2
    done
    if ! (set -C; echo "$me" > "$d/pid") 2>/dev/null; then   # noclobber: un pid gia' scritto e' di un altro
      p=$(cat "$d/pid" 2>/dev/null)
      if [ -d "$d" ] && [ -z "$p" ]; then rm -rf -- "$d"; return 1; fi   # cartella nostra, pid non scrivibile
    fi
    [ "$(cat "$d/pid" 2>/dev/null)" = "$me" ] && return 0   # riletto: solo il proprio pid vuol dire lock preso
    [ -z "$wait" ] || [ $((SECONDS - t0)) -lt "$wait" ] || return 1   # ripreso da un altro: non e' nostro, si riprova
    sleep 0.2
  done
}

fic__lock_vecchio() { # <cartella>: 0 se c'e' e la sua mtime ha piu' di 10 s (stat GNU, poi BSD); ignota -> 1
  local m
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null) || return 1
  case $m in ''|*[!0-9]*) return 1 ;; esac
  [ $(( $(date +%s) - m )) -ge 10 ]
}

fic_unlock_dir() { # <cartella di lock> [<pid>, default il proprio]: la toglie solo se il lock e' di <pid>
  local d=$1 me=${2:-${BASHPID:-$$}}
  [ "$(cat "$d/pid" 2>/dev/null)" = "$me" ] && rm -rf -- "$d"
}

fic_git_env() { # $1 radice: .git FILE con "gitdir: X:/…" → GIT_DIR tradotto in <FIC_WSL_MNT>/x/… e GIT_WORK_TREE
  local g d
  [ -f "$1/.git" ] || return 0
  g=$(sed -n '1s/^gitdir:[[:space:]]*//p' "$1/.git" | tr -d '\r')
  g=${g//\\//}
  case "$g" in [A-Za-z]:/*) ;; *) return 0 ;; esac
  d=$(printf '%s' "${g:0:1}" | tr '[:upper:]' '[:lower:]')
  GIT_DIR="${FIC_WSL_MNT:-/mnt}/$d/${g:3}"; GIT_WORK_TREE=$1
  export GIT_DIR GIT_WORK_TREE
}

fic_mirror_init() { # $1 radice → FIC_TOP, FIC_MAIN (tree principale), FIC_MIRROR; 1 se git non li determina
  local gd gcd g
  FIC_TOP="" FIC_MAIN="" FIC_MIRROR="" FIC_LANE_BASE=""
  fic_git_env "$1"
  g=(git -c safe.directory='*' -C "$1" rev-parse)
  FIC_TOP=$("${g[@]}" --show-toplevel 2>/dev/null) && [ -n "$FIC_TOP" ] || return 1
  gd=$("${g[@]}" --path-format=absolute --git-dir 2>/dev/null) && [ -n "$gd" ] || return 1
  gcd=$("${g[@]}" --path-format=absolute --git-common-dir 2>/dev/null) && [ -n "$gcd" ] || return 1
  FIC_MAIN=$(cd "$gcd/.." 2>/dev/null && pwd) || return 1
  if [ "$gd" = "$gcd" ]; then FIC_MIRROR=$HOME/fic-mirror
  else FIC_MIRROR=$HOME/fic-mirror-$(printf '%s' "$FIC_TOP" | sha256sum | cut -c1-12); fi
}

fic__pkg() { # <copia> → <cartella> (stdout), se <copia> = $FIC_MIRROR/<cartella>; altrimenti motivo e 1
  case "$1" in
    "$FIC_MIRROR"/?*) printf '%s\n' "${1#"$FIC_MIRROR"/}" ;;
    *) echo "copia fuori da ${FIC_MIRROR:-<copia non inizializzata>}: $1 (il chiamante passa \$FIC_MIRROR/<cartella>)"; return 1 ;;
  esac
}

fic__locks() { # <copia della radice> → i suoi .fic-lock (uno per cartella dei pacchetti), node_modules esclusi
  find "$1" -name node_modules -prune -o -name .fic-lock -type f -print 2>/dev/null
}

fic_deps_fp() { # <origine: cartella dei pacchetti> [raw] → impronta; `raw` = i byte (la regola di prima)
  local raw=${2:-} f h
  (cd "$1" && find . \( -name node_modules -o -name .nuxt -o -name .output \) -prune -o \
      \( -name package.json -o -name package-lock.json \) -type f -print | LC_ALL=C sort |
    while IFS= read -r f; do
      if [ "$raw" = raw ]; then h=$(sha256sum < "$f" | cut -c1-64); else h=$(tr -d '\r' < "$f" | sha256sum | cut -c1-64); fi
      printf '%s  %s\n' "$h" "$f"
    done) | sha256sum | cut -c1-64
}

fic_deps_ok() { # <origine> <copia>: le dipendenze sono quelle registrate dal --setup
  local rec; rec=$(cat "$2/.fic-deps" 2>/dev/null) && [ -n "$rec" ] || return 1
  [ "$(fic_deps_fp "$1")" = "$rec" ] || [ "$(fic_deps_fp "$1" raw)" = "$rec" ]
}

fic_deps_refresh() { # <origine con node_modules> <copia> → 0 fatto · 1 no, motivo su stdout
  # L'operazione del --setup: rsync dall'origine, node_modules compresi, poi l'impronta. Il lock e' del chiamante.
  # Durante il rsync .fic-deps vale "interrotto": un rsync fallito lascia la copia stantia (la riprova il run dopo),
  # mai con l'impronta vecchia su node_modules a meta'.
  local src=$1 dst=$2 rc
  [ -d "$src/node_modules" ] || { echo "l'origine non ha node_modules ($src)"; return 1; }
  mkdir -p "$dst" && echo interrotto > "$dst/.fic-deps" || { echo "copia non scrivibile: $dst"; return 1; }
  rsync -a --delete --exclude=.nuxt --exclude=.output --exclude=coverage --exclude=.turbo --exclude='/.fic-*' "$src/" "$dst/"
  rc=$?; [ "$rc" -eq 0 ] || { echo "rsync dall'origine fallito (uscita $rc)"; return 1; }
  fic_deps_fp "$src" > "$dst/.fic-deps" || { echo "impronta non scrivibile: $dst/.fic-deps"; return 1; }
}

fic__seed_copy() { # <fonte> <origine> <copia>: node_modules in hardlink, poi l'impronta
  # Senza lock (lo tiene il chiamante). Su una copia gia' seminata: .fic-deps "interrotto" durante la semina, e le
  # cartelle node_modules della copia che nella fonte non ci sono piu' (pacchetto tolto) si cancellano: sono
  # hardlink, la fonte non si tocca.
  local mm=$1 src=$2 dst=$3 nms
  if [ -f "$dst/.fic-deps" ]; then echo interrotto > "$dst/.fic-deps" || { echo "impronta non scrivibile: $dst/.fic-deps"; return 1; }; fi
  nms=$(cd "$mm" && find . -name node_modules -type d -prune -print | sed 's|^\./||') || { echo "fonte non leggibile: $mm"; return 1; }
  printf '%s\n' "$nms" | while IFS= read -r nm; do
    [ -n "$nm" ] || continue
    mkdir -p "$dst/$nm" &&
      rsync -a --delete --link-dest="$mm/$nm/" --exclude=.cache --exclude=.vite --exclude=.vitest "$mm/$nm/" "$dst/$nm/" || exit 1
  done || { echo "semina fallita (rsync --link-dest)"; return 1; }
  (cd "$dst" && find . -name node_modules -type d -prune -print | sed 's|^\./||') | while IFS= read -r nm; do
    printf '%s\n' "$nms" | grep -qxF -- "$nm" || rm -rf "${dst:?}/$nm" || exit 1
  done || { echo "node_modules orfani della copia non cancellabili"; return 1; }
  fic_deps_fp "$src" > "$dst/.fic-deps" || { echo "impronta non scrivibile: $dst/.fic-deps"; return 1; }
}

fic__source_fresh() { # <origine della fonte> <fonte> <nome> <cartella>: la fonte della semina vale per la sua origine
  # Se e' stantia la riallinea, sotto il SUO lock (fd 8), come la copia di una radice (fic__refresh_root).
  # 0 valida · 1 no, motivo su stdout. Una riga su stderr quando riallinea.
  local o=$1 mm=$2 nome=$3 pkg=$4 out
  [ -d "$mm/node_modules" ] && [ -f "$mm/.fic-deps" ] || { echo "manca la $nome ($mm)"; return 1; }
  fic_deps_ok "$o" "$mm" && return 0
  out=$(
    exec 8>"$mm/.fic-lock" || { echo "lock della $nome non apribile"; exit 1; }
    flock -w "${FIC_LOCK_WAIT:-900}" 8 || { echo "$nome occupata oltre ${FIC_LOCK_WAIT:-900}s"; exit 1; }
    fic_deps_ok "$o" "$mm" && exit 0   # riallineata nel frattempo da un altro run
    fic__refresh_root "$o" "$mm" "$pkg" || exit 1
    fic_deps_ok "$o" "$mm" || { echo "$nome ancora stantia dopo il riallineamento"; exit 1; }
  ) || { echo "$nome stantia, riallineamento non riuscito: ${out//$'\n'/; }"; return 1; }
  [ -z "$out" ] || echo "fic-mirror: $nome ($mm) stantia: ${out//$'\n'/; }" >&2
}

fic__refresh_root() { # <origine> <copia della radice> <cartella>, lock della copia gia' preso
  # Origine con node_modules: fic_deps_refresh. Senza (worktree): semina di nuovo dalla copia del tree principale,
  # riallineata prima se stantia. Stdout: cosa ha fatto, o il motivo (uscita 1).
  local src=$1 dst=$2 pkg=$3 mm main
  mm=$HOME/fic-mirror/$pkg
  if [ -d "$src/node_modules" ]; then fic_deps_refresh "$src" "$dst" && echo "copia riallineata dall'origine"; return; fi
  [ "$dst" != "$mm" ] || { echo "l'origine non ha node_modules da cui riallineare la copia ($src): rieseguire --setup dove ci sono"; return 1; }
  main=$FIC_MAIN/$pkg
  [ -d "$mm/node_modules" ] && [ -f "$mm/.fic-deps" ] || { echo "l'origine non ha node_modules e manca la copia del tree principale ($mm)"; return 1; }
  [ -d "$main" ] && [ "$(fic_deps_fp "$src")" = "$(fic_deps_fp "$main")" ] ||
    { echo "l'origine non ha node_modules e le sue dipendenze sono diverse da quelle del tree principale"; return 1; }
  fic__source_fresh "$main" "$mm" "copia del tree principale" "$pkg" || return 1
  fic__seed_copy "$mm" "$src" "$dst" && echo "copia riseminata da ~/fic-mirror (node_modules in hardlink)"
}

fic_deps_autorefresh() { # <origine> <copia = $FIC_MIRROR/<cartella>>: riallinea una copia con le dipendenze stantie
  # Il chiamante tiene il lock della copia e ricontrolla fic_deps_ok dopo. Mai un'installazione: solo copie locali.
  # Copia di corsia: la copia della radice riallineata (sotto il suo lock), poi semina di nuovo da quella.
  # 0 fatto, una riga su stdout · 1 no, motivo su stdout.
  local src=$1 dst=$2 old new out pkg
  pkg=$(fic__pkg "$dst") || { echo "$pkg"; return 1; }
  old=$(cut -c1-12 "$dst/.fic-deps" 2>/dev/null); new=$(fic_deps_fp "$src" | cut -c1-12)
  if [ -n "${FIC_LANE_BASE:-}" ]; then
    out=$(fic__source_fresh "$src" "$FIC_LANE_BASE/$pkg" "copia della radice" "$pkg") &&
      out=$(fic__seed_copy "$FIC_LANE_BASE/$pkg" "$src" "$dst") &&
      out="copia della corsia riseminata da $FIC_LANE_BASE (node_modules in hardlink)"
  else
    out=$(fic__refresh_root "$src" "$dst" "$pkg")
  fi || { echo "${out//$'\n'/; }"; return 1; }
  echo "dipendenze cambiate (impronta ${old:-assente} -> $new): $out"
}

fic_seed_node_modules() { # <origine> <copia = $FIC_MIRROR/<cartella>> → 0 seminata · 1 no, motivo su stdout
  # Richiede fic_mirror_init gia' chiamata sulla radice dell'origine. La fonte stantia si riallinea (fic__source_fresh).
  local src=$1 dst=$2 mm pkg
  [ -n "$FIC_MIRROR" ] && [ "$FIC_MIRROR" != "$HOME/fic-mirror" ] || { echo "non e' la copia di un worktree"; return 1; }
  pkg=$(fic__pkg "$dst") || { echo "$pkg"; return 1; }
  mm=$HOME/fic-mirror/$pkg
  if [ -n "${FIC_LANE_BASE:-}" ]; then   # copia di corsia: dalla copia della SUA radice (fic_lane_init)
    mm=$FIC_LANE_BASE/$pkg
    [ -d "$mm/node_modules" ] && [ -f "$mm/.fic-deps" ] || { echo "manca la copia della radice ($mm): un run senza FIC_LANE o --setup"; return 1; }
    fic__source_fresh "$src" "$mm" "copia della radice" "$pkg" || return 1
  else
  [ -d "$mm/node_modules" ] && [ -f "$mm/.fic-deps" ] || { echo "manca la copia del tree principale ($mm)"; return 1; }
  [ -d "$FIC_MAIN/$pkg" ] && [ "$(fic_deps_fp "$src")" = "$(fic_deps_fp "$FIC_MAIN/$pkg")" ] ||
    { echo "dipendenze del worktree diverse da quelle del tree principale"; return 1; }
  fic__source_fresh "$FIC_MAIN/$pkg" "$mm" "copia del tree principale" "$pkg" || return 1
  fi
  mkdir -p "$dst" || { echo "copia non creabile: $dst"; return 1; }
  (
    flock -w "${FIC_LOCK_WAIT:-900}" 9 || { echo "copia del worktree occupata"; exit 1; }
    [ -d "$dst/node_modules" ] && [ -f "$dst/.fic-deps" ] && exit 0   # seminata nel frattempo da un altro run
    fic__seed_copy "$mm" "$src" "$dst" || exit 1
  ) 9>"$dst/.fic-lock"
}

fic_mirror_forget() { # <radice di un worktree>: cancella la SUA copia · 0 fatto o niente da fare · 1 rifiuto o in uso
  local lk
  fic_mirror_init "$1" || { echo "fic-mirror: radice non determinabile (git): $1"; return 1; }
  case "$FIC_MIRROR" in "$HOME"/fic-mirror-????????????) ;; *) echo "fic-mirror: rifiuto, non e' la copia di un worktree: $FIC_MIRROR"; return 1 ;; esac
  [ -d "$FIC_MIRROR" ] || { echo "fic-mirror: nessuna copia per $1"; return 0; }
  fic__forget_dir "$FIC_MIRROR" || return 1
  echo "fic-mirror: copia cancellata: $FIC_MIRROR"
}

fic__forget_dir() { # <copia della radice>: cancellata se nessuno dei suoi lock e' tenuto · 1 in uso, lasciata
  # Tutti i lock presi (flock -n) prima di cancellare e tenuti fino alla fine, nella stessa subshell.
  ( local lk fd
    while IFS= read -r lk; do
      [ -n "$lk" ] || continue
      exec {fd}>"$lk" && flock -n "$fd" || { echo "fic-mirror: copia in uso, lasciata: $1"; exit 1; }
    done < <(fic__locks "$1")
    rm -rf "$1" )
}

fic_lane_init() { # <k>: dopo fic_mirror_init, FIC_MIRROR = copia della corsia k · 1 se k non e' 1..9 o manca la radice
  case "${1:-}" in [1-9]) ;; *) return 1 ;; esac
  [ -n "$FIC_MIRROR" ] || return 1
  FIC_LANE_BASE=$FIC_MIRROR FIC_MIRROR=$FIC_MIRROR-$1
}

fic_lane_forget() { # <radice> <k>: cancella la copia della corsia k · 0 fatto o niente da fare · 1 rifiuto o in uso
  fic_mirror_init "$1" && fic_lane_init "${2:-}" || { echo "fic-mirror: corsia o radice non determinabile: $1 ${2:-}"; return 1; }
  case "$FIC_MIRROR" in "$HOME"/fic-mirror-[1-9]|"$HOME"/fic-mirror-????????????-[1-9]) ;;
    *) echo "fic-mirror: rifiuto, non e' la copia di una corsia: $FIC_MIRROR"; return 1 ;; esac
  [ -d "$FIC_MIRROR" ] || { echo "fic-mirror: nessuna copia della corsia $2 per $1"; return 0; }
  fic__forget_dir "$FIC_MIRROR" || return 1
  echo "fic-mirror: copia della corsia cancellata: $FIC_MIRROR"
}
