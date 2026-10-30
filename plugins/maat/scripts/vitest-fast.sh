#!/usr/bin/env bash
# vitest-fast.sh — DEPRECATED: wrapper of test-fast.sh, for the commands already documented. Same arguments, same output.
exec bash "$(dirname "$0")/test-fast.sh" "$@"
