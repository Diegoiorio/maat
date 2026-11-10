#!/bin/bash
# setup-env.sh <copy> <deps dir>: downloads the Go modules pinned by go.mod and go.sum, once, into <deps dir>/gomod.
# Nothing is written in the copy. Run with the network open; after it the suite runs with GOPROXY=off.
set -eu
copy=$(cd "$1" && pwd)
mkdir -p "$2"
deps=$(cd "$2" && pwd)
command -v go >/dev/null || { echo "setup-env: go not found" >&2; exit 2; }
export GOMODCACHE=$deps/gomod GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPROXY=https://proxy.golang.org,direct
cd "$copy"
go mod download
go mod verify
git -C "$copy" diff --quiet -- go.mod go.sum || { echo "setup-env: go.mod or go.sum changed" >&2; exit 1; }
