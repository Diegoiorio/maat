The byte formatters now move to the next unit when rounding carries the number up to the base, for example `Bytes(999_999)` returns `"1.0 MB"`. `go test ./...` and `go vet ./...` pass and `gofmt -l .` prints nothing. Nothing was committed, pushed or installed.

## What changed
- **`bytes.go`, `humanateBytes`:** if the rounded number reaches the base and a larger unit exists, it prints exactly one of that unit, with the digit count that value normally gets.
- **`bigbytes.go`, `humanateBigBytes`:** same rule, using `math.RoundToEven` because that matches how `%.0f` rounds. `oomm` is untouched, and the function still works on a copy of the input.
- **Doc comments:** I added one correct example to each of the five functions. `README.markdown` showed no wrong outputs, so it is unchanged.
- **`bytes_test.go`, `bigbytes_test.go`:** I corrected the 12 expectations that encoded the wrong outputs, and added new tests:
    - exact boundaries for every unit, for all five functions
    - unchanged outputs
    - the last units, `QB` and `QiB`
    - the input not being modified
    - outputs parsing back within tolerance

## What I verified
| Check | Result |
|---|---|
| `go test -count=1 ./...` | both packages pass |
| `go vet ./...` | clean |
| `gofmt -l .` | prints nothing |
| Old code vs new code, in a scratch program outside the repo | 146,377,672 comparisons, 318,479 outputs changed, 0 illegal |
| Deliberately breaking the fix in a scratch copy, 8 ways | 6 caught by the tests, 2 not (below) |

- **Old vs new comparison:** it covered every value below 3,000,000, 3 million random values, and values around each boundary up to the `QB` range. An output could only change if the old number had reached the base and the new output equals the one-unit output.
- **The two breakages not caught:**
    - Removing the last-unit check in `humanateBytes` changes nothing, because a `uint64` can't reach 1000 EB. That check is only a safeguard.
    - The other attempt didn't compile, so it tested nothing. Removing the Big promotion entirely was caught.
- **API:** I didn't change any exported names or signatures.

## Choices where the spec was unclear
- **`IBytesN` is also fixed:** the spec lists five functions but its goal says "no byte formatter". `IBytesN` shares `humanateBytes`, so it gets the fix too, and I added a few test cases for it.
- **Very large `n` is left as it is:** at `BytesN(500_000, 309)` the rounding overflows and prints `"+Inf kB"` today. Infinity counts as "≥ base", so a plain check would have turned that into a false `1.000… MB`. I added a guard so the output stays the same, plus a test.

## Open points
- **AC4 can't hold literally for two cases, both already there before this change.** Parsing is out of scope, so I left the parsers alone, and the parse-back test allows for both:
    - `ParseBytes` truncates to whole bytes through a float, so `BytesN(1003, 6)` gives `"1.00300 kB"`, which reads back as 1002. The test's tolerance is therefore at least one byte.
    - Outputs above the `uint64` range, like `"16 EiB"`, are rejected by `ParseBytes`, and `TestByteErrors` requires that. The test skips these.
- **The top boundaries of `Bytes` and `IBytes` aren't at "boundary − 1".** Inputs pass through a `float64`, which is spaced 128 apart there, so anything within 64 of 999.5 PB (or 1023.5 PiB) already rounds onto it. The largest value not promoted is the boundary − 65, and the tests pin this.
- **Other platforms:** I only ran this on linux/amd64. These boundary tests depend on floating-point behaviour, and I didn't run them on any other architecture.

<!-- total_cost_usd=1.0665094 duration_ms=463444 num_turns=7 -->
<!-- usage_from_transcript={"claude-opus-5-5": {"cache_creation_input_tokens": 57127, "cache_read_input_tokens": 281187, "calls": 7, "input_tokens": 14, "output_tokens": 74}} -->
