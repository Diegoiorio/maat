#!/bin/bash
# setup-env.sh <copy> <deps dir> — environment of a copy of pyenv. The suite is bash and bats and needs nothing from the
# network: no package, no download, nothing private to the copy. This only checks the pinned tools the sandbox provides.
set -eu
copy=$1
[ -d "$copy/plugins/pyenv-binary" ] || { echo "setup-env: $copy is not a pyenv copy" >&2; exit 1; }
for tool in bats parallel git tar xz sha256sum readelf; do
  command -v "$tool" >/dev/null || { echo "setup-env: $tool not found" >&2; exit 1; }
done
case $(bats --version) in *1.14.0*) ;; *) echo "setup-env: bats 1.14.0 expected, found $(bats --version)" >&2; exit 1 ;; esac
case $(parallel --will-cite --version | head -n 1) in *20261022*) ;; *) echo "setup-env: GNU parallel 20261022 expected" >&2; exit 1 ;; esac
echo "setup-env: nothing to prepare"
