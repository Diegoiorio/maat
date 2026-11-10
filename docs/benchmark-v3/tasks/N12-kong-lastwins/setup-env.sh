#!/bin/bash
# setup-env.sh <copy> <deps dir> — environment of a copy of the project, with the network open.
# Downloads the modules pinned by go.mod and go.sum (hashes checked by go) once into <deps dir>/gomod, the read-only
# module cache of the run (sandbox.env). Nothing is written in the copy.
set -eu
copy=$(cd "$1" && pwd)
mkdir -p "$2"
deps=$(cd "$2" && pwd)
cd "$copy"
export GOTOOLCHAIN=local GOMODCACHE="$deps/gomod" GOFLAGS=-modcacherw GOPATH="${TMPDIR:-/tmp}/n12-gopath" \
  GOCACHE="${TMPDIR:-/tmp}/n12-gocache"
go mod download all
git -C "$copy" diff --exit-code --quiet -- go.mod go.sum
