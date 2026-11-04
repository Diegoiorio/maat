#!/usr/bin/env bash
# fixture-cicli.sh — the cycle fixtures shared by cycle-state.test.sh and tools/esempi-equiv/costruisci.sh (Maat 1.5.0).
#   . "$HERE/lib/fixture-cicli.sh"
# To be sourced, not run. The functions are the ones cycle-state.test.sh always had, moved here unchanged: they read
# the globals of the caller, set before every call — SP (the spec), RUN (its run dir), PC (plan-check.sh).
#   with_basis                     writes the Approved basis line into $SP, after "Superfici a rischio:"
#   review <rs> <fs> [<l3>] [<l4>] prints an Italian review section (manifest: Scope src/a.py, Excluded src/b.py)
#   esito <label> <line> <state>   like run-phase: empty .jsonl, .esito and, for implement/fix, fake pre/post-tree
#   esito_inline <label> <line> <state>   like --inline: .esito and fake pre/post-tree, no .jsonl
#   rjson <label> <phase> <esito> <deviazioni> <bloccato_su>   a valid $RUN/log/<label>.result.json
with_basis() { # writes the Approved basis line into the current spec
  local cur; cur=$(bash "$PC" basis "$SP" | sed -n 's/^Basis: //p')
  sed -i "s/^Superfici a rischio: .*/&\nApproved basis: $cur/" "$SP"
}
review() { # $1 Review status, $2 Feature status, [$3 snapshot line], [$4 contract line]
  printf '%s\n' "## Review implementazione" "Review status: $1" "Feature status: $2" "Verification: VERIFIED"
  [ -n "${3:-}" ] && printf '%s\n' "$3"
  [ -n "${4:-}" ] && printf '%s\n' "$4"
  printf '%s\n' "Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1" "" "<details><summary>Manifest (1 paths)</summary>" "" \
    "Scope:" "src/a.py" "" "Excluded:" "src/b.py" "" "</details>"
}
esito() { # $1 label, $2 ESITO line, $3 state — like run-phase: .jsonl, .esito and, if attribution is measured, pre/post-tree
  mkdir -p "$RUN/log"; : > "$RUN/log/$1.jsonl"; printf '%s\nstate=%s\n' "$2" "$3" > "$RUN/log/$1.esito"
  case "$1" in *implement*|*fix*) echo x > "$RUN/log/$1.pre-tree"; echo y > "$RUN/log/$1.post-tree" ;; esac
}
esito_inline() { # like the --inline mode: no .jsonl
  mkdir -p "$RUN/log"; printf '%s\nstate=%s\n' "$2" "$3" > "$RUN/log/$1.esito"
  echo x > "$RUN/log/$1.pre-tree"; echo y > "$RUN/log/$1.post-tree"
}
rjson() { # $1 label, $2 phase, $3 esito, $4 deviazioni (JSON list), $5 bloccato_su — like run-phase: valid result.json
  printf '{"fase":"%s","esito":"%s","motivo":"m","deviazioni":%s,"bloccato_su":"%s","file":[],"gate_interni":[],"finding":[]}\n' \
    "$2" "$3" "$4" "$5" > "$RUN/log/$1.result.json"
}
