# Spec: the decoder's nesting limit must also cover arrays

## Context

This Go module decodes TOML. `Decoder` has a limit against documents nested too deeply, set with
`Decoder.MaxTableNesting(l int)`: the default is 128, and a value `<= 0` disables it. It covers tables only. Arrays can
be nested without any limit:

```go
depth := 200_000
var v any
_, err := toml.Decode("a = "+strings.Repeat("[", depth)+"1"+strings.Repeat("]", depth), &v)
```

This returns no error. With a few million levels (fewer under a lower `debug.SetMaxStack`) the process dies with
`fatal error: stack overflow`, which a caller cannot recover from. So a program that decodes a document it did not write
can be brought down by a file of a few megabytes.

`MaxTableNesting` was added after the last release (v1.6.0): it is in no released version, and its name no longer fits.

## Goal

One limit, `Decoder.MaxDepth`, covers both tables and arrays. A document over it gets an ordinary parse error.

## Functional requirements

FR1. `func (dec *Decoder) MaxDepth(l int)` replaces `MaxTableNesting`, which no longer exists: no alias, no deprecated
method. The default stays 128, and `l <= 0` disables the limit for both tables and arrays. Its doc comment says so.

FR2. The depth of an array is the number of arrays open at its innermost point: `a = [1]` is 1, `a = [[1]]` and
`a = [[]]` are 2. With a limit `N`, a depth of `N` decodes as it did before and a depth of `N + 1` is an error. With the
default: 128 levels decode, 129 do not.

FR3. Only nesting counts.

- Neighbours add nothing: `a = [[1], [2], [3]]` has depth 2 however long it is, and each key is measured on its own.
- An inline table between two arrays does not restart the count: `a = [[{b = [[1]]}]]` has depth 4, so limit 3 rejects it
  and limit 4 accepts it.
- `[` inside a string or a comment is not an array.
- An array-of-tables header (`[[x]]`) is a table for this limit, as it is today, and does not add to the depth of the
  arrays under it: with limit 2, `[[x]]` followed by `a = [[1]]` is accepted.

FR4. Going over the limit returns an error from the decoding call, never a panic. It is a `toml.ParseError` (found with
`errors.As`). When the array that is too deep is written on one line, its `Position.Line` is that line; across several
lines, any line of that value will do. The text of `Error()` contains the limit as a decimal number. The rest of the
wording is free.

FR5. The limit on tables accepts and rejects exactly the documents it accepts and rejects today at the same value (dotted
keys, `[table]` and `[[array of tables]]` headers, inline tables), and its error follows FR4. For a table over the limit,
`Position.Line` is the line of the key or header that goes over it. Tables and arrays are
measured separately: a document within the limit for each is accepted, for example a key of 100 dotted parts whose value
is 100 nested arrays, with the default limit.

FR6. The default limit applies wherever a document is decoded: `Decoder.Decode`, `Decode`, `DecodeFile`, `DecodeFS` and
`Unmarshal`.

FR7. The project's own tests that use the old name are updated, and new tests cover FR2 to FR5.

## Acceptance criteria

AC1. Every example above holds, and the program of the Context returns a `toml.ParseError`.

AC2. `go test ./...` and `go vet ./...` pass; `gofmt -l .` prints nothing.

## Out of scope

- Any other change to how documents are decoded or encoded, or to the accepted TOML syntax.
- New dependencies. The Go version declared in `go.mod` stays as it is.
