#!/usr/bin/env bash
# vitest-fast.sh — DEPRECATO: involucro di test-fast.sh, per i comandi gia' documentati. Stessi argomenti, stessa uscita.
exec bash "$(dirname "$0")/test-fast.sh" "$@"
