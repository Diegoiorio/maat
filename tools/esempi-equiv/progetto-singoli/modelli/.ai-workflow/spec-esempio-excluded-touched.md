# Example: review excluded a touched file

## Context
The implement touched src/b.py; the review put it among the excluded ones.

## Functional requirements
1. FR1 — a() returns 20.

## Implementation plan
Plan status: APPROVED
Test level: std
Risk surfaces: none
Approved basis: {{basis}}

### Steps
1. Change `src/a.py`.

### Plan review changelog
- round 1: ok

## Implementation review
Review status: APPROVED
Feature status: IMPLEMENTED
Reviewed snapshot: {{snapshot:2}}
Reviewed contract: spec {{basis-spec}} · plan {{basis-plan}}
Verification: VERIFIED
Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1

<details><summary>Manifest (1 paths)</summary>

Scope:
src/a.py

Excluded:
src/b.py

</details>
