# Spec: byte sizes that round up to 1000 (or 1024) must move to the next unit

## Context

The byte-size formatters of this Go module choose the unit from the exact value and then round the number they
print. Close below a unit boundary the rounding carries the number up to the base, and the output shows a number
that should have been written with the next unit:

- `Bytes(999_999)` returns `"1000 kB"` instead of `"1.0 MB"`;
- `IBytes(1_048_575)` (1 MiB − 1) returns `"1024 KiB"` instead of `"1.0 MiB"`;
- `BigBytes(big.NewInt(999_999))` returns `"1000 kB"`, `BigIBytes` of 1 MiB − 1 returns `"1024 KiB"`;
- `BytesN(999_999, 3)` returns `"1000 kB"` instead of `"1.00 MB"`.

The formatters are in `bytes.go` (`Bytes`, `IBytes`, `BytesN`, helper `humanateBytes`) and `bigbytes.go`
(`BigBytes`, `BigIBytes`, helper `humanateBigBytes`). Tests are next to them (`bytes_test.go`, `bigbytes_test.go`);
some existing test cases currently expect the wrong outputs above (for example `"1000 kB"` for `MByte - Byte`).

## Goal

No byte formatter prints a number equal to or larger than its base when a larger unit exists; such values are
printed exactly as the value of one unit of the next size is printed.

## Functional requirements

FR1. For `Bytes`, `IBytes`, `BytesN` (any `n`), `BigBytes` and `BigIBytes`: when the number that the function would
print, after its own rounding, is greater than or equal to the base (1000 for SI, 1024 for IEC) and the function's
unit list has a larger unit, the result is the string that the same function returns for exactly one of that
larger unit. Examples: `Bytes(999_999) == Bytes(1_000_000) == "1.0 MB"`; `Bytes(999_500) == "1.0 MB"`;
`IBytes(1_048_575) == "1.0 MiB"`; `BytesN(999_999, 3) == "1.00 MB"`; `BytesN(999_999, 0) == BytesN(1_000_000, 0)`;
`BigBytes` of 10⁹ − 1 `== "1.0 GB"`; `BigIBytes` of 1 GiB − 1 `== "1.0 GiB"`.

FR2. Every other output is unchanged. In particular values whose rounded number stays below the base keep their
current output: `Bytes(999_499) == "999 kB"`, `IBytes(1000 * 1024) == "1000 KiB"`, `IBytes(1023 * 1024) == "1023 KiB"`,
and all outputs for values below 10 bytes.

FR3. There is no unit after the last one: for the largest unit of a function (`QB` and `QiB` for the `Big`
functions) the number is printed as today, even when it is 1000 (or 1024) or more.

FR4. `BigBytes` and `BigIBytes` still do not modify the `*big.Int` they receive.

FR5. The existing test cases that encode the wrong outputs of the Context are corrected to the new outputs, and new
test cases cover FR1 to FR4 for each of the five functions, including the exact boundary values (the smallest input
that is promoted and the largest one that is not).

FR6. The doc comments of the five functions stay correct; if an example in a doc comment or in `README.markdown`
shows one of the wrong outputs, it is corrected.

## Codebase areas involved (indicative)

- `bytes.go`: `humanateBytes`, `Bytes`, `IBytes`, `BytesN`.
- `bigbytes.go`: `humanateBigBytes`, `oomm`, `BigBytes`, `BigIBytes`.
- `bytes_test.go`, `bigbytes_test.go`.

## Acceptance criteria

AC1. Every example in FR1, FR2 and FR3 holds.

AC2. For every SI and IEC unit boundary reachable by each function, the smallest promoted input and the largest
input that is not promoted give the outputs required by FR1 and FR2.

AC3. `go test ./...` and `go vet ./...` pass; `gofmt -l .` prints nothing.

AC4. The public API (exported names and signatures) is unchanged, and `ParseBytes` / `ParseBigBytes` still read
back every output of the five formatters to a value within one unit of the last printed digit.

## Assumptions

- "The number the function would print" is the number after the rounding each function already does: `Bytes`,
  `IBytes` and `BytesN` round half up to their number of digits, `BigBytes` and `BigIBytes` use Go's `%.0f` /
  `%.1f` formatting.

## Out of scope

- Any other change to formatting (number of digits, spacing, unit names) or to parsing.
- The other formatters of the module (`Comma`, `SI`, `Ftoa`, times, ordinals).
- New dependencies.

## Constraints

- The Go version declared in `go.mod`; standard library only.
- `gofmt` formatting.

## Implementation plan
Plan format: 2
Plan status: APPROVED
Test level: std
Risk surfaces: shared-logic
Approved basis: spec 4591679fe956 · plan d5afb10c3bb9 · tests 5abfb3443bcb

### Decisions
**D1 — where the check goes.** Promotion is decided inside the two helpers, after the rounding each one already does, so all callers get it. `humanateBytes` (`bytes.go`) moves its existing rounding lines, unchanged, into an unexported `roundBytesValue(val float64, minDigits int) (float64, int)` returning the rounded value and the decimals; then:

```go
val, digits := roundBytesValue(float64(s)/math.Pow(base, e), minDigits)
if val >= base && int(e)+1 < len(sizes) {
	e++
	val, digits = roundBytesValue(1, minDigits)
}
suffix := sizes[int(e)]
```

The second call runs the same code on the value an exact unit produces (measured: `float64(u)/math.Pow(base, k)` is exactly 1 and `logn` gives exactly k for every SI and IEC unit up to k=6), so the promoted string is the one of one larger unit for any `n`, negative included.

**D2 — the Big helper.** `humanateBigBytes` (`bigbytes.go`), right after `oomm` and before `suffix`:

```go
if mag+1 < len(sizes) && math.RoundToEven(val) >= float64(base.Int64()) {
	val, mag = 1, mag+1
}
```

`math.RoundToEven` is what `%.0f` does to a float64 (ties to even: 999.5 → 1000, 1023.5 → 1024). Only `%.0f` matters: below 10 the value cannot reach the base. `val = 1` falls into the existing `%.1f` branch, giving `1.0 <unit>`. `oomm` is not changed (`TestOommLimit` pins it, `big.go` is untouched) and it still works on the copy `c`, so the input stays unmodified (FR4). At the last unit `mag+1 < len(sizes)` is false, so the number prints as today (FR3). `bigbytes.go` gains the `math` import.

**D3 — `IBytesN` follows the helper.** FR1 lists five functions, without `IBytesN`; the Goal says «no byte formatter», and Out of scope does not name it. `IBytesN` calls `humanateBytes`, so it is promoted too: `IBytesN(1_048_575, 3) == "1.00 MiB"`. Keeping the bug for it alone would need a flag on the helper against the Goal. T2 pins this.

**D4 — boundaries are measured, not derived.** At the top uint64 boundary the input is above 2^53 and `float64(s)` rounds, so the threshold is not exactly x.5 units: `999_499_999_999_999_936` is the smallest promoted to EB, `1_152_358_554_653_425_600` to EiB. The Big functions use integer arithmetic and have exact thresholds (999.5 and 1023.5 units).

**D5 — where the reds are reported.** `testList.validate` calls `t.Errorf` in `common_test.go`, a position outside the test files of the rows, and test-red writes only those files. So `bytes_test.go` adds the method `func (tl testList) check(t *testing.T)`: `t.Helper()`, then the same comparison and the same message of `validate`. `TestBytes` and `TestBigBytes` end with `}.check(t)` instead of `}.validate(t)`; `common_test.go` does not change.

Examples (all measured on the base except the promoted outputs):

| input | output |
|---|---|
| `Bytes(999_500)` / `Bytes(999_499)` | `1.0 MB` / `999 kB` |
| `Bytes(999_499_999_999_999_936)` / `Bytes(999_499_999_999_999_935)` | `1.0 EB` / `999 PB` |
| `IBytes(1_048_064)` / `IBytes(1_048_063)` | `1.0 MiB` / `1023 KiB` |
| `IBytes(1_152_358_554_653_425_600)` / `IBytes(1_152_358_554_653_425_599)` | `1.0 EiB` / `1023 PiB` |
| `BytesN(999_500, 3)` / `BytesN(999_499, 3)` | `1.00 MB` / `999 kB` |
| `BytesN(999_950, 4)` / `BytesN(999_949, 4)` | `1.000 MB` / `999.9 kB` |
| `BytesN(999_500, 0)` / `BytesN(999_500, -1)` | `1 MB` / `1 MB` |
| `BytesN(999_999, 8)` | `999.99900 kB` (not promoted) |
| `BigBytes` of 999.5 RB / of that − 1 | `1.0 QB` / `999 RB` |
| `BigBytes` of 999.5 QB / 1000 QB / 5000 QB | `1000 QB` / `1000 QB` / `5000 QB` |
| `BigIBytes` of 1023.5 RiB / of that − 1 | `1.0 QiB` / `1023 RiB` |
| `BigIBytes` of 1023.5 QiB / 1024 QiB | `1024 QiB` / `1024 QiB` |

Implications: data flow, UI, backend, validation, permissions, migration and persistence: no implication (a pure function of a Go library, no state). Parsing: no implication, `ParseBytes` and `ParseBigBytes` are untouched. Rollback: revert the working-tree files. Risk: callers comparing the old `1000 kB` strings get the new ones; that is the request. Out of scope as in the spec.

### Touched files
- `bytes.go`
- `bigbytes.go`
- `bytes_test.go`
- `bigbytes_test.go`

### Steps
#### Block B1 — code
writes: `bytes.go`, `bigbytes.go`
after: none

| id | file | change | test |
|---|---|---|---|
| P1 | `bytes.go` | `humanateBytes`: extract `roundBytesValue`, promote per D1 | T1, T2, T3, T6 |
| P2 | `bigbytes.go` | `humanateBigBytes`: promote per D2, add the `math` import | T4, T5, T7 |

#### Block B2 — tests
writes: `bytes_test.go`, `bigbytes_test.go`
after: none

| id | file | change | test |
|---|---|---|---|
| P3 | `bytes_test.go` | `check` method (D5); round-trip helper; correct the 6 wrong cases of `TestBytes` (`MByte - Byte`, `GByte - KByte`, `TByte - MByte`, `MiByte - IByte`, `GiByte - KiByte`, `TiByte - MiByte`) to `1.0 MB`, `1.0 GB`, `1.0 TB`, `1.0 MiB`, `1.0 GiB`, `1.0 TiB`; add T1, T2, T3 | T1, T2, T3, T6 |
| P4 | `bigbytes_test.go` | same 6 corrections in `TestBigBytes`; add T4, T5 | T4, T5, T7 |

### Requirement traceability
| Req | Plan steps | Verification |
|---|---|---|
| FR1 | P1, P2, P3, P4 | T1, T2, T3, T4, T5 |
| FR2 | P1, P2, P3, P4 | T1, T2, T3, T4, T5 |
| FR3 | P2, P4 | T4, T5 |
| FR4 | P2, P4 | T4, T5 |
| FR5 | P3, P4 | T6, T7 |
| FR6 | — | not verifiable by a test: no doc comment or `README.markdown` line shows a wrong output (`1000 kB` and `1024 KiB` forms searched in `*.go` and `*.markdown`: hits only in the two test files), so nothing changes |
| AC1 | P1, P2, P3, P4 | T1, T2, T3, T4, T5 |
| AC2 | P1, P2, P3, P4 | T1, T2, T3, T4, T5 |
| AC3 | P1, P2, P3, P4 | not verifiable by a test: the gates of the module (`go test ./...`, `go vet ./...`, `gofmt`) |
| AC4 | P1, P2, P3, P4 | T1, T2, T3, T4, T5 (round trip); exported names: not verifiable by a test, `roundBytesValue` is unexported and no signature changes |

### Strings and data-test
| action | type | value |
|---|---|---|
| removes | string | `1000 kB` |
| removes | string | `1000 MB` |
| removes | string | `1000 GB` |
| removes | string | `1024 KiB` |
| removes | string | `1024 MiB` |
| removes | string | `1024 GiB` |

### Test plan
Each new test is table-driven, reports with `t.Errorf` in its own body in the form `got <output>, want <expected>`, and runs on every case the round trip: the parser (`ParseBytes` for the uint64 functions, `ParseBigBytes` for the Big ones) reads the output back to within one unit of the last printed digit of the input (AC4). The not-promoted and FR3 cases sit in the same table as the promoted ones, so each test is red on the base through its promoted cases.

| ID | requirement | file | assertion | mutation |
|---|---|---|---|---|
| T1 | FR1, FR2, AC1, AC2, AC4 | `bytes_test.go::TestBytesUnitPromotion` (new) | smallest promoted and largest not promoted at kB→MB up to PB→EB (D4), plus 9, 999, 1000, 999_999, 1_000_000; red if: `got 1000 kB` | `bytes.go` · `humanateBytes` · `val >= base && int(e)+1 < len(sizes)` → `false` · red if: `got 1000 kB` |
| T2 | FR1, FR2, AC1, AC2, AC4 | `bytes_test.go::TestIBytesUnitPromotion` (new) | same boundaries for KiB→MiB up to PiB→EiB, plus 1023, 1024, 1_048_575, `1000 * 1024`, `1023 * 1024`, IBytes(9) == "9 B", and `IBytesN(1_048_575, 3)` (D3); red if: `got 1024 KiB` | — |
| T3 | FR1, FR2, AC1, AC2, AC4 | `bytes_test.go::TestBytesNUnitPromotion` (new) | the same boundaries for `n` = 3 and `n` = 4 (thresholds 999.5 and 999.95 units), plus `n` = 0, 1, 2, -1 at 999_500 and `BytesN(999_999, 8)`, plus BytesN(999_999, 3) == "1.00 MB", BytesN(999_999, 0) == BytesN(1_000_000, 0), BytesN(9, 3) == "9 B"; each promoted output also equals `BytesN` of one larger unit with the same `n`; red if: `got 1000 kB` | — |
| T4 | FR1, FR2, FR3, FR4, AC1, AC2, AC4 | `bigbytes_test.go::TestBigBytesUnitPromotion` (new) | 999.5 units and that − 1 from kB→MB up to RB→QB, 10⁹ − 1, the QB row of Decisions, values below 10; each call leaves its `*big.Int` equal to a copy taken before; red if: `got 1000 kB` | `bigbytes.go` · `humanateBigBytes` · `math.RoundToEven(val) >= float64(base.Int64())` → `math.RoundToEven(val) > float64(base.Int64())` · red if: `got 1000 kB` |
| T5 | FR1, FR2, FR3, FR4, AC1, AC2, AC4 | `bigbytes_test.go::TestBigIBytesUnitPromotion` (new) | 1023.5 units and that − 1 from KiB→MiB up to RiB→QiB, 1 GiB − 1, the QiB row of Decisions, values below 10; each call leaves its `*big.Int` equal to a copy taken before; red if: `got 1024 KiB` | — |
| T6 | FR5 | `bytes_test.go::TestBytes` | the 6 corrected cases; red if: `but got '1000 kB'` | — |
| T7 | FR5 | `bigbytes_test.go::TestBigBytes` | the 6 corrected cases; red if: `but got '1000 kB'` | — |

EXISTING non-regression tests (not rows of the Test plan: they cannot be proven red on the base with stubs):
- `bigbytes_test.go::TestOommLimit`: `oomm` keeps its result at the limit (FR3), inside the gate of the module.

### Plan review changelog
- round 1, L3 major: T4 mutation broke the build, `math` left unused → mutation now changes `>=` to `>`.
- round 1, L1 and L3 major: T3 lacked two FR1 examples and a below-10 case → added.
- round 1, L1 major: T2 lacked a below-10 case → added.
- note (minor, not applied, L2 and L3): at PB→EB with n = 4 the float threshold is measured, smallest promoted 999_949_999_999_999_936 → 1.000 EB, largest not promoted 999_949_999_999_999_935 → 999.9 PB; 999.95 PB − 1 is promoted.
- note (minor, not applied, L1): D3 does not name FR2 as the competing line.
- note (minor, not applied, L1): 16 EiB is rejected by `ParseBytes` on the base, so it stays out of round-trip tables.
- note (minor, not applied, L1): FR3 cannot be reached by the uint64 functions (at most 18 EB, 16 EiB).
- note (nit, not applied, L1, L3): FR5 row could cite T1-T5; P4 could name `check`; round-trip wording means the output's last digit.
- note (minor, not applied, L2): `check` duplicates `validate`, kept for the position of the red (D5).
- note (minor, not applied, delta and fresh eyes): T3's thresholds in units are not exact at PB→EB with n = 4; use the measured pair of the note above.
- note (minor, not applied, fresh eyes): T1 and T4 carry one mutation each, one per independent helper.
- note (nit, not applied, fresh eyes): P4 does not name the round-trip helper with `ParseBigBytes`.
Metrica ciclo: giri=2 · R1=3/3 · delta=0/1 · gate=0/1 · rifiutati=0 · ricorrenze=0 · reintrodotti=0 · esito=approvato · livello=std · superfici=logica-condivisa · formato=2

## Implementation review
Review status: APPROVED
Feature status: NEEDS_VERIFICATION
Finalize: NEEDS_VERIFICATION — snapshot ad5a9e95fe08 — counterproof T1: NOT RUN (declared): module humanize declares no counterproof; counterproof T4: NOT RUN (declared): module humanize declares no counterproof · 2026-11-06T10:37:35Z
Requirement evidence (finalize.sh: requirement → test ID → result of VERIFY, evidence/bbe845a10d97)
| Requirement | Test IDs | Evidence |
|---|---|---|
| FR1 | bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion; T1; T4 | not covered (no result: bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion) |
| FR2 | bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion; bytes_test.go::TestBytes; bigbytes_test.go::TestBigBytes | not covered (no result: bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion; bytes_test.go::TestBytes; bigbytes_test.go::TestBigBytes) |
| FR3 | bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion; T4 | not covered (no result: bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion) |
| FR4 | bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion | not covered (no result: bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion) |
| FR5 | bytes_test.go::TestBytes; bigbytes_test.go::TestBigBytes; bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion | not covered (no result: bytes_test.go::TestBytes; bigbytes_test.go::TestBigBytes; bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion) |
| FR6 | — | not covered (no test ID) |
| AC1 | bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion; T1; T4 | not covered (no result: bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion) |
| AC2 | bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion; T1; T4 | not covered (no result: bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion) |
| AC3 | — | not covered (no test ID) |
| AC4 | bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion | not covered (no result: bytes_test.go::TestBytesUnitPromotion; bytes_test.go::TestIBytesUnitPromotion; bytes_test.go::TestBytesNUnitPromotion; bigbytes_test.go::TestBigBytesUnitPromotion; bigbytes_test.go::TestBigIBytesUnitPromotion) |
Verification: PARTIAL (finalize.sh: counterproof T1: NOT RUN (declared): module humanize declares no counterproof; counterproof T4: NOT RUN (declared): module humanize declares no counterproof)
Review basis: SPEC+PLAN
Reviewed snapshot: base 37bea5e96b1a0bfe7a8b6e1e26b39e73b9e17469 · tree 05a4f8bc5e877130b859c6e78c062c0c1b7f0995 · fingerprint fc56ca3e7d8b · 4 paths
<details><summary>Manifest (4 paths)</summary>

Scope:
bigbytes.go
bigbytes_test.go
bytes.go
bytes_test.go

Excluded:

</details>

Reviewed contract: spec 4591679fe956 · plan d5afb10c3bb9
Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1

### Evidence
| Gate | Req. | Command / check | Result | Evidence |
|---|---|---|---|---|
| tests and vet (humanize, touched) | yes | gates.sh tests (driver) | VERIFY (driver, in parallelo) | composed by finalize.sh |
| gofmt (touched) | yes | gates.sh controlli (driver) | VERIFY (driver, in parallelo) | composed by finalize.sh |
| plan: counterproof T1 on `bytes.go` | yes | counterproof T1 (driver) | VERIFY (driver, in parallelo) | counterproof/T1.json |
| plan: counterproof T4 on `bigbytes.go` | yes | counterproof T4 (driver) | VERIFY (driver, in parallelo) | counterproof/T4.json |

### Findings
| Key | Severity | State |
|---|---|---|

No blocker or major findings. Reviewer classes 1 to 4 (blast radius, forgotten surfaces, interactions, test integrity): nothing. Static review only: nothing was executed in this phase.

For the user's check (recorded in the plan, not a finding): D3 also promotes `IBytesN`, which FR1 does not list; it follows the Goal and is pinned by `TestIBytesUnitPromotion`.
