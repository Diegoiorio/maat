# Example: format 2, tests to prove red

## Context
The plan is in format 2; the acceptance tests come first.

## Functional requirements
1. FR1 — a() returns 20.

## Implementation plan
Plan format: 2
Plan status: APPROVED
Test level: std
Risk surfaces: none
Approved basis: {{basis}}
### Touched files
- `src/a.py`
- `src/test_a.py` (new)

### Steps
#### Block B1 — return value
writes: `src/a.py`, `src/test_a.py`
after: none

| id | file | change | test |
|---|---|---|---|
| P1 | `src/a.py` | a() returns 20 | T1 |

### Requirement traceability
| Req | Plan steps | Verification |
|---|---|---|
| FR1 | P1 | T1 |

### Test plan
| ID | requirement | file | assertion | mutation |
|---|---|---|---|---|
| T1 | FR1 | `src/test_a.py::test_a` (new) | red if: `assert a() == 20` | — |

### Plan review changelog
- round 1: ok
