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
Approved basis: spec 4591679fe956 · plan 5e5148a77923 · tests 400d2f9919ff

### Decisions
**D1 — `IBytesN` keeps its current output.** `humanateBytes` also serves `IBytesN` (`bytes.go:150-153`), which the spec never names. FR1 lists five functions, FR5, FR6 and AC4 say five, and FR2 says every other output is unchanged, so `IBytesN` is not promoted, even though the Goal's wording («no byte formatter») would reach it. The requirements are the checkable text and this is the narrower reading: extending it later is one changed argument (`false` → `true`). The helper therefore gets an explicit parameter `promote bool`: `true` from `Bytes`, `BytesN`, `IBytes`; `false` from `IBytesN`. `humanateBytes` has no other caller (`bytes.go:115,128,138,152`) and no test calls it directly.

| input | output |
|---|---|
| `IBytesN(1_048_575, 2)` | `1024 KiB` (unchanged) |
| `IBytesN(1_048_064, 2)` | `1024 KiB` (unchanged) |
| `IBytesN(1_048_063, 2)` | `1023 KiB` (unchanged) |

**D2 — `humanateBytes`: promote after the rounding, without recursion.** Right after `val = math.Floor(val*rounding+0.5) / rounding` and before the carry adjustment of `digits`:

```go
if promote && val >= base && int(e)+1 < len(sizes) {
	suffix = sizes[int(e)+1]
	val, intDigits = 1, 1
	digits = max(minDigits-intDigits, 0)
}
```

These are the values `humanateBytes` computes for exactly one larger unit, so the string is the one FR1 requires for any `n` (`n` ≤ 1 gives no decimals). The comparison uses `base`, never a fixed 1000: `IBytes(1000 * 1024)` stays `1000 KiB`. `int(e)+1 < len(sizes)` is the FR3 guard: `Bytes` and `IBytes` cannot reach it (at most `18 EB` and `16 EiB`), it only protects the index.

**D3 — `humanateBigBytes`: same rule, with the rounding of `%.0f`.** Right after the `oomm` call, before `suffix := sizes[mag]`:

```go
if math.RoundToEven(val) >= float64(base.Int64()) && mag+1 < len(sizes) {
	val, mag = 1, mag+1
}
```

`%.0f` rounds half to even, as `math.RoundToEven` does: both 999.5 and 1023.5 reach the base. `val = 1` selects the existing `%.1f` format, hence `1.0 <unit>`. At the last unit `mag+1 == len(sizes)`: `1000 QB` and `1024 QiB` stay (FR3). `oomm` does not change, and the function still works on its copy `c`, so the `*big.Int` received is untouched (FR4).

**D4 — the boundaries are measured on the base, not derived.** Run on a copy of the base at commit 37bea5e. Above 2^53 `float64(s)` loses precision, so the two highest boundaries of `Bytes` and `IBytes` are not the exact half. The «not promoted» column is the output today and stays; the «promoted» input prints `1000 <unit>` or `1024 <unit>` today.

| function | largest not promoted | output | smallest promoted | output |
|---|---|---|---|---|
| `Bytes` | 999_499 | `999 kB` | 999_500 | `1.0 MB` |
| `Bytes` | 999_499_999 | `999 MB` | 999_500_000 | `1.0 GB` |
| `Bytes` | 999_499_999_999 | `999 GB` | 999_500_000_000 | `1.0 TB` |
| `Bytes` | 999_499_999_999_999 | `999 TB` | 999_500_000_000_000 | `1.0 PB` |
| `Bytes` | 999_499_999_999_999_935 | `999 PB` | 999_499_999_999_999_936 | `1.0 EB` |
| `IBytes` | 1_048_063 | `1023 KiB` | 1_048_064 | `1.0 MiB` |
| `IBytes` | 1_073_217_535 | `1023 MiB` | 1_073_217_536 | `1.0 GiB` |
| `IBytes` | 1_098_974_756_863 | `1023 GiB` | 1_098_974_756_864 | `1.0 TiB` |
| `IBytes` | 1_125_350_151_028_735 | `1023 TiB` | 1_125_350_151_028_736 | `1.0 PiB` |
| `IBytes` | 1_152_358_554_653_425_599 | `1023 PiB` | 1_152_358_554_653_425_600 | `1.0 EiB` |

`BigBytes`, for each unit `U` from `kB` to `RB`: 999.5 `U` is the smallest promoted (`1.0` next unit) and 999.5 `U` − 1 the largest not promoted (`999 U`). `BigIBytes`, from `KiB` to `RiB`: 1023.5 `U` and 1023.5 `U` − 1 (`1023 U`). `BytesN` depends on `n`:

| `n` | largest not promoted | output | smallest promoted | output |
|---|---|---|---|---|
| -1, 0, 1 | 999_499 | `999 kB` | 999_500 | `1 MB` |
| 2 | 999_499 | `999 kB` | 999_500 | `1.0 MB` |
| 3 | 999_499 | `999 kB` | 999_500 | `1.00 MB` |
| 4 | 999_949 | `999.9 kB` | 999_950 | `1.000 MB` |
| 5 | 999_994 | `999.99 kB` | 999_995 | `1.0000 MB` |
| 7 | 999_999 | `999.9990 kB` | none in that unit | — |

Higher units of `BytesN`: at `n` = 3 the boundaries are the `Bytes` inputs of the table above, at `n` = 6 and 7 the promoted input moves closer to the unit. The «not promoted» column is the output today and stays; the «promoted» input prints `1000 <unit>`, `1000.00 <unit>` or `1000.000 <unit>` today.

| `n` | largest not promoted | output | smallest promoted | output |
|---|---|---|---|---|
| 3 | 999_499_999 | `999 MB` | 999_500_000 | `1.00 GB` |
| 3 | 999_499_999_999 | `999 GB` | 999_500_000_000 | `1.00 TB` |
| 3 | 999_499_999_999_999 | `999 TB` | 999_500_000_000_000 | `1.00 PB` |
| 3 | 999_499_999_999_999_935 | `999 PB` | 999_499_999_999_999_936 | `1.00 EB` |
| 6 | 999_999_499 | `999.999 MB` | 999_999_500 | `1.00000 GB` |
| 7 | 999_999_949 | `999.9999 MB` | 999_999_950 | `1.000000 GB` |

Other unchanged outputs and FR3:

| input | output |
|---|---|
| `Bytes(9)`, `IBytes(9)`, `BytesN(9, 3)` | `9 B` |
| `Bytes(999)` / `IBytes(1023)` | `999 B` / `1023 B` |
| `IBytes(1000 * 1024)` / `IBytes(1023 * 1024)` | `1000 KiB` / `1023 KiB` |
| `Bytes(math.MaxUint64)` / `IBytes(math.MaxUint64)` | `18 EB` / `16 EiB` |
| `BytesN(math.MaxUint64, 3)` | `18.4 EB` |
| `BigBytes` of 1000 QB − 1, of 1000 QB, of 5000 QB | `1000 QB`, `1000 QB`, `5000 QB` |
| `BigIBytes` of 1024 QiB − 1, of 1024 QiB | `1024 QiB`, `1024 QiB` |

**D5 — a position in the test file.** `testList.validate` reports its errors from `common_test.go`, so a failing row of `TestBytes` carries no position in the test that declares it, and the test-red phase needs that position. `common_test.go` is outside the write scope of that phase (it holds no row of the test table), so it stays untouched: `bytes_test.go` gets the helper `func (tl testList) validateHere(t *testing.T)`, with `t.Helper()` as first line and the same comparison and the same message as `validate`. `TestBytes`, `TestBigBytes` and T3 to T7 call it; every other test keeps `validate`. No change to what any test asserts.

**D6 — the parse-back of AC4.** Each promoted case of T3 to T7 also parses its output back (`ParseBytes` or `ParseBigBytes`) and requires exactly one larger unit. AC4 is read as no regression: non-promoted outputs and the parser do not change, so whatever parses today still parses. `IBytes` values printing `16 EiB` (`IBytes(math.MaxUint64)` included) already fail in `ParseBytes` with `too large` on the base (`bytes.go:191-196`, required by `bytes_test.go:72`) and keep failing: parsing is out of scope. The promoted outputs are all accepted, the largest being `1.0 EiB`.

Other implications: API, data, persistence, permissions, UI, migration: no implication (AC4: exported names and signatures unchanged; both helpers are unexported). Rollback: revert the working-tree changes, nothing is persisted. Docs (FR6): no wrong example exists: the doc comments of `bytes.go` and `bigbytes.go` and `README.markdown:22` show 83 MB, 82.9 MB, 82.85 MB, 79 MiB; searched for `1000 ` and `1024 ` in `README.markdown`, only the `Comma` example at line 63 matches.

### Touched files
- `bytes.go`
- `bigbytes.go`
- `bytes_test.go`
- `bigbytes_test.go`

### Steps
#### Block B1 — fixed-width formatters
writes: `bytes.go`, `bytes_test.go`
after: none

| id | file | change | test |
|---|---|---|---|
| P1 | `bytes.go` | `humanateBytes`: parameter `promote bool` and the promotion of D2; `Bytes`, `BytesN`, `IBytes` pass `true`, `IBytesN` passes `false` (D1), with a one-line comment saying why | T1, T3, T4, T5 |
| P2 | `bytes_test.go` | new helper `validateHere` (D5); `TestBytes` calls it instead of `validate` | T1, T2 |
| P3 | `bytes_test.go` | `TestBytes`: the 6 expected values `1000 kB`, `1000 MB`, `1000 GB`, `1024 KiB`, `1024 MiB`, `1024 GiB` become `1.0 MB`, `1.0 GB`, `1.0 TB`, `1.0 MiB`, `1.0 GiB`, `1.0 TiB`; new `TestBytesPromotion`, `TestIBytesPromotion`, `TestBytesNPromotion` with the cases of D1, D4, D6 | T1, T3, T4, T5 |

#### Block B2 — big formatters
writes: `bigbytes.go`, `bigbytes_test.go`
after: B1

| id | file | change | test |
|---|---|---|---|
| P4 | `bigbytes.go` | `humanateBigBytes`: the promotion of D3; import `math` | T2, T6, T7 |
| P5 | `bigbytes_test.go` | `TestBigBytes`: calls `validateHere` (D5), the same 6 expected values as P3; new `TestBigBytesPromotion`, `TestBigIBytesPromotion` with the cases of D4, D6 and FR4 | T2, T6, T7 |

### Requirement traceability
| Req | Plan steps | Verification |
|---|---|---|
| FR1 | P1, P3, P4, P5 | T3, T4, T5, T6, T7 |
| FR2 | P1, P3, P4, P5 | T3, T4, T5, T6, T7 |
| FR3 | P1, P3, P4, P5 | T3, T4, T5, T6, T7 |
| FR4 | P4, P5 | T6, T7 |
| FR5 | P2, P3, P5 | T1, T2, T3, T4, T5, T6, T7 |
| FR6 | — | not verifiable by a test: documentation; no wrong example exists (D4 paragraph «Other implications»), so no step changes it |
| AC2 | P1, P3, P4, P5 | T3, T4, T5, T6, T7 |
| AC1 | P1, P3, P4, P5 | T3, T4, T5, T6, T7 |
| AC3 | P1, P2, P3, P4, P5 | not verifiable by a test: the gate of the module (go test, go vet, gofmt), run by the driver on the whole module |
| AC4 | P3, P5 | T3, T4, T5, T6, T7 (the parse-back of D6); the API half is static: exported names and signatures unchanged |

### Strings and data-test
No literal string is added or removed: the formatters build their outputs at run time, and the unit names do not change.

### Test plan
| ID | requirement | file | assertion | mutation |
|---|---|---|---|---|
| T1 | FR5 | `bytes_test.go::TestBytes` | red if: a corrected row keeps the old output: `expected '1.0 MB', but got '1000 kB'` | — |
| T2 | FR5 | `bigbytes_test.go::TestBigBytes` | red if: a corrected row keeps the old output: `expected '1.0 MB', but got '1000 kB'` | — |
| T3 | FR1, FR2, FR3, FR5, AC2, AC1, AC4 | `bytes_test.go::TestBytesPromotion` (new) | the `Bytes` rows of D4, `Bytes(999_999)`, `Bytes(1_000_000)` and the unchanged `Bytes` rows; each promoted output parsed back to exactly one larger unit; red if: `expected '1.0 MB', but got '1000 kB'` | `bytes.go` · `humanateBytes` · `if promote && val >= base && int(e)+1 < len(sizes) {` → `if false {` · red if: `expected '1.0 MB', but got '1000 kB'` |
| T4 | FR1, FR2, FR3, FR5, AC2, AC1, AC4 | `bytes_test.go::TestIBytesPromotion` (new) | the `IBytes` rows of D4, `IBytes(1_048_575)`, the unchanged `IBytes` rows and the `IBytesN` rows of D1; each promoted output parsed back to exactly one larger unit; red if: `expected '1.0 MiB', but got '1024 KiB'` | — |
| T5 | FR1, FR2, FR3, FR5, AC2, AC1, AC4 | `bytes_test.go::TestBytesNPromotion` (new) | the `BytesN` tables of D4, `BytesN(math.MaxUint64, 3)`, `BytesN(999_999, 3)`, `BytesN(999_999, n) == BytesN(1_000_000, n)` for `n` in -1, 0, 1, 2, 3, 4, 5, and `BytesN(999_999_999, n) == BytesN(1_000_000_000, n)` for `n` = 6, 7; each promoted output parsed back to exactly one larger unit; red if: `expected '1.00 MB', but got '1000 kB'` | — |
| T6 | FR1, FR2, FR3, FR4, FR5, AC2, AC1, AC4 | `bigbytes_test.go::TestBigBytesPromotion` (new) | the boundaries of D4 from `kB` to `RB`, 10⁹ − 1, the `QB` rows, and each input equal to a copy of itself after the call; each promoted output parsed back to exactly one larger unit; red if: `expected '1.0 MB', but got '1000 kB'` | `bigbytes.go` · `humanateBigBytes` · `if math.RoundToEven(val) >= float64(base.Int64()) && mag+1 < len(sizes) {` → `if math.RoundToEven(val) < 0 {` · red if: `expected '1.0 MB', but got '1000 kB'` |
| T7 | FR1, FR2, FR3, FR4, FR5, AC2, AC1, AC4 | `bigbytes_test.go::TestBigIBytesPromotion` (new) | the boundaries of D4 from `KiB` to `RiB`, 1 GiB − 1, the `QiB` rows, and each input equal to a copy of itself after the call; each promoted output parsed back to exactly one larger unit; red if: `expected '1.0 MiB', but got '1024 KiB'` | — |

EXISTING non-regression tests (not rows of the Test plan: they cannot be proven red on the base with stubs):
- `bigbytes_test.go::TestOommLimit` — `oomm` still returns 1000 at the magnitude limit (D3), FR2.
- `bigbytes_test.go::TestVeryBigBytes`, `bigbytes_test.go::TestVeryVeryBigBytes` — outputs far from a boundary, FR2.

### Plan review changelog
major tests/bytesn-boundaries-only-kb-covered (L1, L3) → BytesN boundaries of every unit and n ≥ 6 added to D4 and T5, FR3 on T5, AC2 row in the traceability.
major traceability/ac4-untraced-d6-narrows-silently (fresh eyes) → AC1, AC3, AC4 rows in the traceability, AC1 and AC4 on T3 to T7, D6 states the no-regression reading and the 16 EiB exception.
note for the spec owner: D1 takes the narrow reading (Goal against FR2) and T4 pins IBytesN(1_048_575, 2) to 1024 KiB, the output the Goal calls wrong; a human should confirm it.
note (minor, not applied): P3 does not name the `math` import that bytes_test.go needs for math.MaxUint64.
note (minor, not applied): P4 names the `math` import of bigbytes.go, D3 does not.
note (minor, not applied): the BytesN boundaries are a sample of the n × unit matrix: no n = 6 row at kB, n = 4 to 7 up to MB to GB at most.
note (minor, not applied): D6 names only 16 EiB; BytesN(math.MaxUint64, 4) prints 18.45 EB, which ParseBytes rejects too on the base (same no-regression reading).
note (minor, not applied): BytesN(9, 3) in D4 has no explicit owner among T3 to T7.
note (minor, not applied): D5 leaves two near-identical helpers side by side.
note (minor, not applied): the parse-backs of T3 to T7 have no red of their own: they guard AC4 as no regression.
note (nit, not applied): the FR6 row cites D4 for a paragraph that follows D6; the two highest boundaries sentence of D4 means the highest of each function; P2 lists T2, whose file is in the writes of B2; AC2 precedes AC1 in the traceability; spec line 51 places oomm in bigbytes.go, it is in big.go:8; D6 largest output 1.0 EiB holds for ParseBytes only; BytesN(5000, 309) overflows to +Inf and is promoted, both outputs are garbage.
Metrica ciclo: giri=3 · R1=2/3 · delta=0/2 · gate=1/2 · rifiutati=0 · ricorrenze=0 · reintrodotti=0 · esito=approvato · livello=std · superfici=logica-condivisa · formato=2

## Implementation review
Review status: APPROVED
Feature status: NEEDS_VERIFICATION
Finalize: NEEDS_VERIFICATION — snapshot 2ab4d1c6e7c0 — counterproof T3: NOT RUN (declared): module humanize declares no counterproof; counterproof T6: NOT RUN (declared): module humanize declares no counterproof · 2026-11-06T13:48:14Z
Requirement evidence (finalize.sh: requirement → test ID → result of VERIFY, evidence/d86fc4e31339)
| Requirement | Test IDs | Evidence |
|---|---|---|
| FR1 | bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion; T3; T6 | not covered (no result: bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion) |
| FR2 | bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion; T3; T6 | not covered (no result: bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion) |
| FR3 | bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion; T3; T6 | not covered (no result: bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion) |
| FR4 | bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion; T6 | not covered (no result: bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion) |
| FR5 | bytes_test.go::TestBytes; bigbytes_test.go::TestBigBytes; bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion; T3; T6 | not covered (no result: bytes_test.go::TestBytes; bigbytes_test.go::TestBigBytes; bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion) |
| FR6 | — | not covered (no test ID) |
| AC2 | bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion; T3; T6 | not covered (no result: bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion) |
| AC1 | bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion; T3; T6 | not covered (no result: bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion) |
| AC3 | — | not covered (no test ID) |
| AC4 | bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion; T3; T6 | not covered (no result: bytes_test.go::TestBytesPromotion; bytes_test.go::TestIBytesPromotion; bytes_test.go::TestBytesNPromotion; bigbytes_test.go::TestBigBytesPromotion; bigbytes_test.go::TestBigIBytesPromotion) |
Verification: PARTIAL (finalize.sh: counterproof T3: NOT RUN (declared): module humanize declares no counterproof; counterproof T6: NOT RUN (declared): module humanize declares no counterproof)
Review basis: SPEC+PLAN
Reviewed snapshot: base 37bea5e96b1a0bfe7a8b6e1e26b39e73b9e17469 · tree bb38b1a032fed76382d87136ec8dc09f7ed0397f · fingerprint e6cc95240781 · 4 paths
Reviewed contract: spec 4591679fe956 · plan 5e5148a77923
Review rounds: 1/3 · post-approval NEEDS_CHANGES: 0/1

<details><summary>Manifest (4 paths)</summary>

Scope:
bigbytes.go
bigbytes_test.go
bytes.go
bytes_test.go

Excluded:

</details>

### Evidence
| Gate | Req. | Command / check | Result | Evidence |
|---|---|---|---|---|
| tests and go vet (touched module) | yes | gates.sh tests-humanize (driver) | VERIFY (driver, in parallelo) | composed by finalize.sh |
| gofmt (touched) | yes | gates.sh controlli (driver) | VERIFY (driver, in parallelo) | composed by finalize.sh |
| plan: T1, T2, T4, T5, T7 (Test plan rows) | yes | module tests (driver) | VERIFY (driver, in parallelo) | composed by finalize.sh |
| plan: counterproof T3 on bytes.go | yes | counterproof T3 (driver) | VERIFY (driver, in parallelo) | counterproof/T3.json |
| plan: counterproof T6 on bigbytes.go | yes | counterproof T6 (driver) | VERIFY (driver, in parallelo) | counterproof/T6.json |

Level in force: std (from the plan). Risk surfaces: shared-logic. No obligation rows.

### Findings
| Key | Severity | State |
|---|---|---|
| scope/ibytesn-narrow-reading@IBytesN | minor | OPEN |
| docs/ibytesn-comment-says-what-not-why@IBytesN | nit | OPEN |

Blocking findings: none.

Suggestions (not applied):
- minor, `bytes.go:159`, `bytes_test.go:247-248`: `IBytesN` still prints `1024 KiB`, which the Goal's wording ("no byte formatter") calls wrong. It conforms to D1, to the five functions FR1 lists and to FR2. The spec owner should confirm D1; the wider reading means passing `true` and updating those two test rows.
- nit, `bytes.go:158`: P1 asks for a comment saying why `IBytesN` passes `false`; this one restates what happens.

Not verified statically: the D4 rows that depend on float64 precision (`999_499_999_999_999_935/936`, `1_152_358_554_653_425_599/600`, `BytesN(999_995, 5)`) rest on the plan's measurement and the driver's gates.
