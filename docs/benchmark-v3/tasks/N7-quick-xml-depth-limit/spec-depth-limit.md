# Spec: deeply nested XML must not overflow the stack of the serde deserializer

## Context

The serde deserializer of this crate (`quick_xml::de::Deserializer` and the functions `quick_xml::de::from_str` and
`from_reader`, feature `serialize`) follows the nesting of the document by recursion: each nested element read into a
struct, a map or an enum adds frames to the native call stack. There is no limit, so the nesting of the input alone
decides how much stack is used.

Given a recursive type, a small hostile document ends the whole process:

```rust
#[derive(Deserialize)]
struct S { field: Option<Box<S>> }

// "<S>" + "<field>" × 100_000 + "</field>" × 100_000 + "</S>"
let r: Result<S, DeError> = quick_xml::de::from_str(&xml);
// thread has overflowed its stack: the process aborts, `r` never exists
```

A stack overflow cannot be caught, so a service that deserializes untrusted XML can be killed by one request. The same
happens for sequences (`Vec<S>`), for the special `$value` field, for maps, for self-describing targets (such as
`serde_value::Value`, through `deserialize_any`) and for enums. One enum case does not even need depth: for
`enum E { Wrap(Box<E>), Leaf }` the single element `<Wrap></Wrap>` already overflows, because a variant with a payload
reads its payload from the variant's own element, over and over. That way of reading variants is a known limitation and
stays out of scope here; what is in scope is that it must no longer abort the process.

Other parsers of the serde family protect against this with a recursion limit: `serde_json` uses 128 by default and
reports an error when it is exceeded. This crate should do the same.

**The traps of this change.** It is a **security** fix: it is only worth having if no path through the deserializer stays
unprotected, whatever the target type and however the deserializer was built. And it has **error paths**: serde visitors
and `Deserialize` implementations can leave in the middle through an error, and some user types go on after an inner error;
if nesting that has ended still counts after such an exit, valid documents fail later with a false error.

## Goal

Deserializing any document, however deep, returns a `Result`: documents nested beyond a configurable limit give a
dedicated error, and everything that works today within that limit works as before.

## Public API

These names and signatures are fixed:

```rust
impl<'de, R, E> quick_xml::de::Deserializer<'de, R, E> {
    /// Sets the maximum nesting accepted by this deserializer. Default: 128.
    pub fn recursion_limit(&mut self, limit: usize) -> &mut Self;
}

pub enum quick_xml::errors::serialize::DeError {   // also reachable as quick_xml::DeError and quick_xml::de::DeError
    // ... the existing variants ...
    /// The input is nested deeper than the limit, which is the value carried.
    TooDeeplyNested(usize),
}
```

## How nesting is counted

The root element is level 1. An element read as a **struct** or a **map**, or by a self-describing target, is one level
more than the element that contains it. `Option`, `Box`, sequences (`Vec<T>`: the items are the levels, the sequence adds
none) and newtype wrappers add no level of their own. For a self-describing target every element counts, including an
empty innermost one such as `<a></a>`. So with a limit of `N`, a chain of `N` such nested elements is
accepted and a chain of `N + 1` is refused, whichever element of the type is recursive.

Two things are deliberately **not** fixed, and any choice is valid: whether a leaf element read as a scalar (`<a>1</a>`
into a `u32`) counts as a level, and how much an enum adds, provided that each element read as an enum variant of any kind
counts at most two levels, and a struct variant at least one.

## Functional requirements

FR1. **Default limit.** A deserializer not configured otherwise accepts 128 levels and refuses 129 with
`DeError::TooDeeplyNested(128)`. This holds for `from_str`, `from_reader`, `Deserializer::from_str`,
`Deserializer::from_reader`, `Deserializer::from_str_with_resolver` and `Deserializer::with_resolver`.

FR2. **`recursion_limit`.** It replaces the limit of that deserializer, and returns the deserializer itself so that calls
can be chained; the last call wins. Edge cases:
- limit `0`: a struct cannot be read at all, even from the empty `<S/>`: `TooDeeplyNested(0)`;
- a limit above the default is honoured: 300 levels are accepted with `recursion_limit(300)` given enough stack, and 301
  are refused;
- `usize::MAX` means in practice no limit and must not overflow any arithmetic;
- it can be changed between two documents read from the same deserializer, and applies from then on.

FR3. **The error.** The depth check gives `DeError::TooDeeplyNested(n)`, where `n` is the limit in force, not the depth of
the document. Its `Display` message names that number. `DeError` keeps implementing `std::error::Error`.

FR4. **Every recursive shape is covered.** Edge cases, each with the counting above where it applies:
- struct fields: `Option<Box<S>>` and `Vec<S>`;
- the `$value` field: `Option<Box<S>>` and `Vec<S>`;
- maps (`struct N(HashMap<String, N>)`) and self-describing targets (`serde_value::Value`);
- enums with struct variants holding a `$value` field (`Wrap { #[serde(rename = "$value")] v: Box<E> }`, also `Vec<E>`):
  a chain of 20 elements ending in `<Leaf/>` is read normally with a limit of 64, and a chain of 200 gives
  `TooDeeplyNested(64)`;
- recursive enums whose variant carries a payload (`Wrap(Box<E>)`, `Wrap(Vec<E>)`, `Wrap(Box<E>, String)`,
  `Wrap(Vec<E>, String)`), with `<Wrap></Wrap>` or with a deep chain of `<Wrap>`: the call returns. Whether it returns a
  value or an error is not fixed; aborting is the failure.

FR5. **Hostile input.** With the default limit, a document of 100 000 levels returns an `Err` for every shape of FR4 (for
the variants with a payload: the call returns, as FR4 says) and every entry point of FR1, in a thread with an ordinary
2 MiB stack. Edge cases:
- the tags are never closed (`<field>` × 100 000, no closing tag): `TooDeeplyNested(128)`, reported before the reader
  gets to the end of the input;
- the deep document is the second of several concatenated ones read as `Vec<S>`;
- 128 levels, exactly at the default limit, are read successfully in that same 2 MiB thread.

FR6. **Depth, not size.** The limit measures nesting only. Edge cases:
- 1000 sibling elements under one parent are accepted with `recursion_limit(3)`;
- a branch that reaches the limit, followed by a sibling branch that reaches it too: the second branch starts from the
  level of its parent, not from where the first one ended;
- a balanced tree of height 7 (127 elements) is accepted with a limit of 7 and refused with a limit of 6;
- concatenated documents read as `Vec<S>`, or one after the other from the same deserializer, each start from level 1.

FR7. **Error paths.** A value that fails gives back the levels it took, whatever the error. Types can go on after an inner
error (for example a `Deserialize` implementation that stores the `Result` of its inner type), and the failures must not
add up. Edge cases:
- 50 failed sibling structs (a required field is missing) under one parent, followed by a sibling chain that reaches the
  limit exactly: every failure keeps its own error (`missing field`), and the chain is accepted; one level less is still
  refused;
- the same at a deeper level, with several parents in turn;
- failed scalar values (`<n>x</n>` into a `u32`);
- failed struct variants of a top-level enum, read as a sequence of documents, followed by a good one;
- several failed documents read one after the other from the same deserializer, followed by a good one.

FR8. **Compatibility.** Every document that deserializes today within the limit gives the same value. Edge cases:
- content the target type does not descend into is not limited: an unknown field, a field of type `()` and a field of type
  `serde::de::IgnoredAny` may hold 100 000 levels, and the document is still read successfully in the 2 MiB thread;
- ordinary documents with attributes, text, sequences and enums are unaffected, and so are very wide documents;
- no existing public name or signature changes, and no new dependency is added.

FR9. **Tests and documentation.** New tests cover FR1 to FR8. The new method and the new error variant are documented, and
the change is mentioned in `Changelog.md`.

## Acceptance criteria

AC1. Every example and edge case of FR1 to FR8 holds.

AC2. `cargo test --features serialize` passes, offline.

AC3. None of the hostile documents of FR4 and FR5 aborts the process.

## Out of scope

- Fixing how variants with a payload read their content (the known limitation of the Context).
- Limits in the low-level `Reader` or in the serializer.
- Any other limit (size of the input, number of attributes).

## Constraints

- The Rust version declared in `Cargo.toml`; no new dependencies. The dependencies are already available offline, and
  `Cargo.lock` is not tracked.
