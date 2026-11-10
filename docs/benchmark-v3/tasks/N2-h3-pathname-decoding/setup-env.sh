#!/bin/bash
# Prepares one copy of the task, with the network open: bash setup-env.sh <copy> <deps dir>
# Pinned: pnpm by version and checksum, the packages by the project's pnpm-lock.yaml (--frozen-lockfile).
# Downloads go once into <deps dir>; node_modules is private to the copy and already excluded.
#   <deps dir>/pnpm/          pnpm itself (read-only during the run, on PATH through sandbox.env)
#   <deps dir>/pnpm-store/    the package store
#   <deps dir>/pristine/      node_modules at the starting commit, untouched by the run
set -eu
copy=$(cd "$1" && pwd)
mkdir -p "$2"
deps=$(cd "$2" && pwd)

PNPM_VERSION=11.15.1
PNPM_SHA512=gTULB+U8lTigLx8jA7QpD6LXvgTlbiqXDEzEtBfcdh3hlu2r1J1Vx9yVgNuBAHxEFD5OPX5GKzAA0jwlUSLQZQ==

command -v node >/dev/null || { echo "node not found" >&2; exit 1; }
case "$(node -v)" in v22.*) ;; *) echo "Node 22 required, found $(node -v)" >&2; exit 1 ;; esac

pnpm_js=$deps/pnpm/package/bin/pnpm.mjs
if [ ! -f "$pnpm_js" ]; then
  mkdir -p "$deps/pnpm"
  tgz=$deps/pnpm/pnpm-$PNPM_VERSION.tgz
  curl -fsSL -o "$tgz" "https://registry.npmjs.org/pnpm/-/pnpm-$PNPM_VERSION.tgz"
  have=$(openssl dgst -sha512 -binary "$tgz" | base64 -w0)
  [ "$have" = "$PNPM_SHA512" ] || { echo "pnpm checksum mismatch: $have" >&2; exit 1; }
  tar -xzf "$tgz" -C "$deps/pnpm"
  mkdir -p "$deps/pnpm/bin"
  printf '#!/bin/sh\nexec node "%s" "$@"\n' "$pnpm_js" > "$deps/pnpm/bin/pnpm"
  chmod +x "$deps/pnpm/bin/pnpm"
fi

cd "$copy"
# A real copy of each package, never a hard link: a run must not be able to touch the shared store.
"$deps/pnpm/bin/pnpm" install --frozen-lockfile --ignore-scripts \
  --store-dir "$deps/pnpm-store" --package-import-method=copy --config.confirmModulesPurge=false

if [ ! -d "$deps/pristine/node_modules" ]; then
  mkdir -p "$deps/pristine"
  cp -a "$copy/node_modules" "$deps/pristine/node_modules.tmp"
  mv "$deps/pristine/node_modules.tmp" "$deps/pristine/node_modules"
fi

# pnpm, run during a copy's life with the store out of reach, opens one of its own there.
printf '%s\n' .pnpm-store/ >> "$copy/.git/info/exclude"
