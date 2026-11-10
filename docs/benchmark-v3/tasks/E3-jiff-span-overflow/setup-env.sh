#!/bin/bash
# setup-env.sh <copy> <deps dir>: prepares a copy of the project, with the network open. Crates go once into
# <deps dir>/cargo, at the versions of the Cargo.lock next to this file (the project does not track one); the run sees
# them read-only (sandbox.env). The build is prepared once in the copy, so the first test gate does not pay for it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
copy=$(cd "$1" && pwd)
mkdir -p "$2"
deps=$(cd "$2" && pwd)
export CARGO_HOME=$deps/cargo
cp "$here/Cargo.lock" "$copy/Cargo.lock"
while IFS= read -r p; do
  [ -z "$p" ] || grep -qxF "$p" "$copy/.git/info/exclude" || printf '%s\n' "$p" >> "$copy/.git/info/exclude"
done < "$here/exclude.txt"
cd "$copy"
cargo fetch --locked
CARGO_NET_OFFLINE=true cargo test --locked -p jiff --no-run
