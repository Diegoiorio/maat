# Spec: `lastwins` flag groups

## Context

This library maps command-line flags to struct fields. A program that offers several mutually exclusive flags can
declare them in an `xor` group today, but `xor` only knows how to refuse: `--once --drain` fails with an error.

Many command-line tools behave differently: among options that exclude each other, the one given last is the one that
counts (the POSIX utility guidelines allow it, and `gcc -O0 -O2` and the sort options of `ls` work like this). It lets a
user append an option to an alias or a wrapper script and override what is already there. Because each flag here is tied
to its own field, a program cannot get this behaviour from the library today.

This change adds a new struct tag for such groups:

```go
var cli struct {
	Once  bool `lastwins:"poll-exit"`
	Drain bool `lastwins:"poll-exit"`
}
```

- `--once --drain` selects `Drain`: `Once == false`, `Drain == true`.
- `--drain --once` selects `Once`: `Once == true`, `Drain == false`.

The tag name `lastwins` is public API and is fixed. The feature is additive: a program that does not use the tag behaves
exactly as before.

## Goal

Flags can be declared in a last-wins group. Each command-line occurrence of a member overrides the occurrences of the
other members given before it, as if those had never been typed.

**The trap of this change is compatibility with what the library already does.** `xor` and `and` groups, negatable flags,
defaults, environment variables, resolvers, `required`, hooks and validation all exist already and must keep working, on
their own and in combination with the new tag. The requirements below say how they meet.

## Functional requirements

FR1. **Declaration.** A flag joins a group with the bare tag `lastwins:"name"` or inside a `kong` tag,
`kong:"lastwins='name'"`. A flag belongs to at most one group: a flag declaring two different groups
(`lastwins:"one,two"`) makes `kong.New` return an error (the text of the error is free). Different groups do not interact
with each other. A group with a single member behaves like an ordinary flag.

FR2. **The last occurrence selects the member**, whatever form it is written in. Edge cases:
- short names and clusters count in the order they are written: with `-o` for `Once` and `-d` for `Drain`, `-o -d` and
  `-od` select `Drain`, `-do` selects `Once`;
- aliases are occurrences of their flag;
- a negated form is an occurrence of its flag, also with a custom negation name. With
  `Once bool` `lastwins:"mode" negatable:"" default:"true"` and `Drain bool` `lastwins:"mode"`: `--drain --no-once` gives
  `Once == false, Drain == false`; `--no-once --drain` gives `Once == true, Drain == true`;
- an explicit value does not change who is selected: `--once --drain=false` overrides `--once` and gives
  `Once == false, Drain == false`;
- what follows `--` is not an occurrence;
- occurrences on either side of a positional argument or of a command name count in the same way (see FR7 for commands).

FR3. **An overridden member is as if it had not been on the command line.** It takes the value it would have taken had it
been omitted: the zero value, its `default:`, its environment variable (which comes before the default, as usual) or the
value of a resolver. Edge cases: `--one=first --two=last` with `One string` `lastwins:"g" default:"d"` gives
`One == "d"`; a slice with `default:"x,y"` gives `[x y]`; a pointer stays nil; a resolver is asked about the overridden
flag as it is about any flag not given.

FR4. **Repeated occurrences and cumulative flags.** Repeated occurrences of one member with no other member in between
accumulate as usual; an occurrence of another member discards everything accumulated so far by the first. So only the
trailing run of the last member survives. Edge cases, with `One []string` and `Two []string` in one group:
- `--one=a --two=b --one=c` gives `One == [c]` and `Two` empty (not `One == [a c]`);
- `--two=x --one=a --one=b` gives `One == [a b]`, `Two` empty;
- `--one=a --one=b --two=c --two=d` gives `One` empty, `Two == [c d]`.
The same holds for maps and for `type:"counter"` flags: with `Verbose int` `type:"counter" short:"v"` and `Quiet bool` in
one group, `-v -v --quiet -v` gives `Verbose == 1, Quiet == false`.

FR5. **Only command-line occurrences are arbitrated.** Defaults, environment variables and resolvers apply to every
member the command line left untouched, exactly as for flags outside any group; several members may hold values from
these sources at the same time, with no error. Edge cases: with two members each with an environment variable and no
arguments, both hold their variable's value; with `--a=x --b=y`, `A` falls back to its own variable and `B` is `y`.

FR6. **`required`.** When the members of a group are declared `required`, at least one of them must be on the command
line, as with `xor`. With none, the error text is `missing flags: --one or --two` (members in declaration order, joined by
` or `). An overridden member does not make the command fail: `--one --two` is valid and `Two` wins.

FR7. **Scope.** A group is restricted to the command that declares its flags, like `xor`:
- flags with the same group name on a parent and on a command are two groups: `--one cmd --two`, with `one` on the
  application and `two` on the command, keeps both;
- two members declared on the application override each other wherever they are written:
  `--one cmd --two` with both on the application gives `Two`;
- flags brought in with `embed` belong to the command that embeds them;
- `xorprefix:"X"` also prefixes `lastwins` group names, so that one embedded struct used twice with different
  `xorprefix` values gives two separate groups.

FR8. **`xor` and `and`.** Existing `xor` and `and` groups keep their strict behaviour and messages. Edge cases:
- `xor` and `lastwins` group names are separate: an `xor` group and a `lastwins` group both named `g` have nothing to do
  with each other, also for `required` (with fields `X1`, `X2` in a required `xor:"g"` and `L1`, `L2` in a required
  `lastwins:"g"`, `--x-1` alone fails with `missing flags: --l-1 or --l-2`);
- a flag may be in a `lastwins` group and in an `xor` or `and` group at once;
- an overridden occurrence does not count for `xor` or `and`, since it is as if never given. With `A` in `xor:"x"` and
  `lastwins:"m"`, `B` in `xor:"x"`, `C` in `lastwins:"m"`: `--a --b --c` and `--a --c --b` are valid (`A` was overridden);
  `--c --a --b` and `--a --b` fail with `--a and --b can't be used together`. If `A` and `B` are in `and:"p"` and `A` and
  `C` in `lastwins:"m"`, `--a --b --c` fails with `--a and --b must be used together`.
  Two flags in both the same `xor` group and the same `lastwins` group never conflict: `--a --b` gives `B`.

FR9. **Hooks and validation.** No hook runs for an overridden occurrence and it is not validated; the program sees what it
would see without that occurrence. Edge cases:
- with `--a=x --b=y`, a value type's `BeforeApply` and `AfterApply` on `A` do not run, unless `A` has a default or an
  environment variable: such a flag gets the hooks that a flag left to its default gets today, with its fallback value;
- a value rejected by a `Validate()` method, or outside an `enum`, is not an error when its occurrence is overridden
  (`--mode=gamma --other=x`); it stays an error for a surviving occurrence.

FR10. **Documentation.** The table of tags in `README.md` documents `lastwins`, and the entry for `xorprefix` says it
applies to these groups too.

FR11. **Tests.** The project's test suite covers the new behaviour.

## Acceptance criteria

AC1. Every example above holds.

AC2. `go test ./...` and `go vet -structtag=false ./...` pass; `gofmt -l .` prints nothing. (The `structtag` analyser is
off because the bare struct tags this library supports, such as `` `required` ``, are not in the form it accepts: plain
`go vet` already reports them, in the existing tests, before this change. The project's CI does not run it.)

AC3. A program that does not use the tag behaves as before: the existing tests pass unchanged.

## Out of scope

- Whether an overridden occurrence whose value cannot be decoded at all by its flag's type (`--num=abc --other=x` on an
  `int` flag) is an error. Either is acceptable.
- A flag that repeats the same group name (`lastwins:"a,a"`).
- `required` on only some members of a group.
- Changes to the help output. New dependencies.

## Constraints

- The Go version declared in `go.mod`; no new dependency.
- `gofmt` formatting.
