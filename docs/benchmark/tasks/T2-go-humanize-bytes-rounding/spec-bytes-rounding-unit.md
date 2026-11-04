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
