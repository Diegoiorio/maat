#!/bin/bash
# setup-env.sh <copy> <deps dir> — environment of a copy of this task.
# The module requires nothing (go.mod has no require line and there is no go.sum): nothing is downloaded, nothing goes
# into <deps dir>, nothing private is added to the copy, and the run needs no sandbox.env. The only check is that the
# module has really stayed that way and that every package lists with the module proxy off.
set -eu
copy=$1
cd "$copy"
if grep -q '^require' go.mod || [ -e go.sum ]; then
  echo "setup-env: this module was expected to have no dependencies" >&2
  exit 1
fi
GOPROXY=off GOTOOLCHAIN=local go list ./... > /dev/null
