# Spec: parsing a `Span` with a time unit over its limit loses part of the value

## Context

Each time unit of a `jiff::Span` has its own limit (for example 175 307 616 hours and 10 518 456 960 minutes). When a
parsed value is over the limit of its unit, the parser does not fail: it keeps the unit at its limit and carries the excess
into smaller units, so that `"175307617h".parse::<Span>()` gives 175 307 616 hours and 60 minutes, which adds up to the
value written.

This goes wrong when the input also gives one of those smaller units:

```rust
let span: Span = "175307617h 1m".parse()?;
// total: 175307616 hours and 1 minute. One hour has disappeared.
```

The value is silently wrong: no error, and the same input parsed as a `SignedDuration` gives the right total. The
same happens in the ISO 8601 format (`PT175307617H1M`) and in the `HH:MM:SS` form of the friendly format
(`200000000:30:00`).

## Goal

Whenever a span parses successfully, its time units add up exactly to the value written.

## Functional requirements

In all these requirements the total is what counts, as given by `SignedDuration::try_from(span)`. How the excess is shared
among the smaller units is not fixed, as long as the total is exact; the examples say how much the units must add up to.

FR1. Friendly format (`str::parse::<Span>()` and `jiff::fmt::friendly::SpanParser::parse_span`): a unit over its limit and
any smaller unit given in the input are both kept. Examples, with their total:
- `175307617h 1m` = 175307617 hours and 1 minute; `175307617h 1m ago` is its negation;
- `200000000h 30m` and `200000000:30:00` = 200000000 hours and 30 minutes; `200000000:30:07` = 200000000 hours,
  30 minutes and 7 seconds;
- `10518456961m 1s` = 10518456961 minutes and 1 second;
- `631107417601s 1ms`, `631107417600001ms 1us` and `631107417600000001us 1ns`: the same, one unit further down;
- `175307617h 10518456960m 1s`: the minutes are exactly at their limit, and nothing is lost.

FR2. A fraction on the smallest unit is kept too: `200000000h 30.5m` = 200000000 hours, 30 minutes and 30 seconds;
`10518456961m 1.5s`; `175307617.5h`; `175307617h 10518456961m 1.5s`.

FR3. ISO 8601 format (`str::parse::<Span>()` and `jiff::fmt::temporal::SpanParser::parse_span`), in upper or lower case:
`PT175307617H1M`, `-PT175307617H1M`, `PT175307617H1.5M`, `PT10518456961M1S`, `PT10518456961M1.5S`.

FR4. A value that is truly too big stays an error, never a panic or a wrong total:
`10518456961m 9223372036854775807s` does not parse.

FR5. Everything else is unchanged: spans whose units are within their limits keep exactly the units written; a unit over its
limit with nothing to collide with is carried as today (`175307617h` gives 175307616 hours and 60 minutes); calendar units
(`1y 2mo 3w 4d`) are not touched, also next to a time unit over its limit: `1y 175307617h 1m` keeps 1 year, and its
time units alone (the span with its years set to 0) total 175307617 hours and 1 minute; `str::parse::<SignedDuration>()` gives the same results as before, and the total of the
span agrees with it. A span printed and parsed again keeps its total.

FR6. New tests cover the examples above.

## Acceptance criteria

AC1. Every example above holds. AC2. `cargo test -p jiff` passes, offline. No new dependency, no change of a public name.
