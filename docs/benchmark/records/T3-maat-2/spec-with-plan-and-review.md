# Spec: split the argument parser into small internal modules, with no change of behaviour

## Context

The whole package is one file, `index.js`: a single exported function of about 250 lines that contains, as inner
or top-level helpers, the number test (`isNumber`), the nested-key lookup (`hasKey`), the nested-key assignment with
its prototype-pollution protections (`setKey`) and the normalisation of the options into flags and aliases. These
pieces cannot be read or tested on their own.

The package supports very old Node versions (`"engines": { "node": ">= 0.4" }` in `package.json`), so its code is
written in ES5 (`var`, function expressions, no arrow functions, no `let`/`const`, no template literals, no
spread). Its tests use `tape` and live in `test/*.js` (`npx tape 'test/**/*.js'`); the lint is
`npx eslint --ext=js,mjs .` with the configuration in `.eslintrc` (a strict shared configuration: for example it
allows at most three parameters per function and requires sorted object keys).

## Goal

The same package, with the same behaviour for every input, whose helpers live in separate modules under `lib/`
with their own unit tests.

## Functional requirements

FR1. Behaviour does not change: for every `args` array and every `opts` object, `require('minimist')(args, opts)`
returns a result deeply equal to the one returned before the change (same keys, same values, same types, same
order of the `_` and `--` arrays), and calls `opts.unknown` with the same arguments, in the same order, the same
number of times. This includes the existing protections against prototype pollution (`__proto__`, `constructor`,
the built-in prototypes).

FR2. New CommonJS modules, each exporting a single function as `module.exports`, in strict mode:
- FR2.1 `lib/is-number.js` exports `isNumber(x)`, with exactly the semantics of today's `isNumber` in `index.js`.
- FR2.2 `lib/has-key.js` exports `hasKey(obj, keys)`, with exactly the semantics of today's `hasKey`.
- FR2.3 `lib/set-key.js` exports `createSetKey(isBooleanKey)`, which returns a function
  `setKey(obj, keys, value)` with exactly the semantics of today's `setKey`, where the boolean-key test it uses
  is the `isBooleanKey` function given to `createSetKey` (`isBooleanKey(key)` returns a boolean). It keeps every
  prototype-pollution protection of today's code.
- FR2.4 `lib/build-flags.js` exports `buildFlags(opts)`, which returns a new object with these properties,
  computed from `opts` exactly as `index.js` computes them today: `bools` (object: key → `true`), `strings`
  (object: key → `true`, aliases included), `allBools` (`true` when `opts.boolean === true`, `false` otherwise),
  `unknownFn` (the `opts.unknown` function, or `null`), `aliases` (object: each name → array of its other names).
  `buildFlags(undefined)` behaves as `buildFlags({})`.

FR3. `index.js` keeps exporting the parser function as `module.exports` and uses the four modules of FR2: it no
longer defines its own `isNumber`, `hasKey`, `setKey` or the code that builds flags and aliases. The argument loop
stays in `index.js`.

FR4. Each module of FR2 has unit tests in a new file `test/lib-<module name>.js` (for example
`test/lib-set-key.js`), written with `tape` like the existing tests. The existing files in `test/` are not modified.

FR5. All JavaScript files of the package, new and changed, are ES5 and pass the project's lint.

FR6. The new modules are part of the published package: `npm pack --dry-run` lists `lib/is-number.js`,
`lib/has-key.js`, `lib/set-key.js` and `lib/build-flags.js`.

## Codebase areas involved (indicative)

- `index.js`.
- `test/` (existing tests, unchanged; new `test/lib-*.js`).
- `package.json`, `.eslintrc` (read; change only if needed for FR6 or the lint).

## Acceptance criteria

AC1. The existing test suite passes unchanged: `npx tape 'test/**/*.js'`.

AC2. The output and the `opts.unknown` calls of the new `index.js` are identical to those of the old one over a
large generated set of argument lists and option objects (booleans, strings, aliases, defaults, dotted keys,
`--`, `stopEarly`, `unknown`, numbers, negations, short-option groups).

AC3. Each module of FR2 can be `require`d on its own and behaves as described in FR2.

AC4. `npx eslint --ext=js,mjs .` passes; every `.js` file of the package parses as ECMAScript 5.

AC5. `npm pack --dry-run` lists the four modules.

## Assumptions

- "Exactly the semantics of today's code" includes its quirks: a quirk is preserved, not fixed.

## Out of scope

- Any change of behaviour, including fixing bugs found along the way (report them instead).
- Performance work, new options, TypeScript types, a changelog entry (the changelog is generated at release).
- New runtime dependencies. New development dependencies are not needed either.

## Constraints

- ES5 syntax and CommonJS, as the rest of the package (`engines.node >= 0.4`).
- The project's lint configuration is not relaxed to make the new code pass.

## Implementation plan
Plan format: 2
Plan status: NEEDS HUMAN DECISION
Test level: std
Risk surfaces: api-contract, shared-logic

### Decisions
**Objective.** Move the helpers out of `index.js:3-21`, `index.js:26-74` and `index.js:87-121` into four CommonJS modules; the argument loop stays. No behaviour changes: quirks are moved verbatim, never fixed.

**Move, do not rewrite.** Each module keeps the statements of today's code, in the same order, so the read order of `opts` properties (including getters) is preserved: `unknown`, `boolean`, `alias`, `string`. `isConstructorOrProto` (`index.js:19-21`) becomes a private function of `lib/set-key.js`. Each module starts with `'use strict';`, declares `function <name>` and ends with `module.exports = <name>;` (`func-style` is `declaration`, `no-use-before-define` is on).

**`lib/set-key.js`.** `createSetKey(isBooleanKey)` returns the function `setKey(obj, keys, value)`, body as `index.js:88-120`. `isBooleanKey` is still called only when `o[lastKey]` is defined (the short-circuit of `index.js:114`).

**`lib/build-flags.js`.** `buildFlags(opts)` takes the code of `index.js:26-44` and `index.js:58-74`. A falsy `opts` is treated as `{}`, as `index.js:24` does. The returned keys are sorted (`sort-keys`): `aliases`, `allBools`, `bools`, `strings`, `unknownFn`. `allBools` starts `false` where today it is missing: its only readers (`index.js:81`, `index.js:179`) test truthiness, so the parser does not change.

**`index.js`.** Keeps `if (!opts)`, because `opts.default`, `opts.stopEarly` and `opts['--']` are still read there. Then `var flags = buildFlags(opts);` and `var aliases = flags.aliases;`. `isBooleanKey` stays, in its current form, as a function declaration closing over both, and `argDefined`, `setArg` and the loop are unchanged. `var setKey = createSetKey(isBooleanKey);` goes after `isBooleanKey` and before `setArg` (`no-use-before-define`).

**AC2 as one committed test.** `test/fixtures/parser-before-split.js` is a byte-for-byte copy of the base `index.js`, written in the test-red phase while `index.js` is still the base one: it is a frozen reference, not a stub. It sits below `test/` so `test/*.js` does not select it; `npx tape 'test/**/*.js'` loads it harmlessly because it declares no test. `test/equivalence.js` first asserts the wiring of FR3 by reading the text of `index.js`: this is its red on the base, where the rest of the test is green by construction. It then runs at least 10000 cases from a seeded generator through both parsers with separately built `opts`, and compares results (deep equality and `JSON.stringify`, so key order counts), thrown error messages and the logged `opts.unknown` calls. The generator covers the dimensions of AC2 (booleans, strings, aliases, defaults, dotted keys, `--`, `stopEarly`, `unknown` both returning and not returning `false`, numbers, negations, short-option groups), repeated keys, and `__proto__` and `constructor` paths; it uses only ES5.

**Stubs (test-red).** Bodies that return a value and never throw, so each test is red on an assertion and not on a crash: `isNumber` → `false`, `hasKey` → `false`, `createSetKey` → a function that does nothing, `buildFlags` → `{}`.

**Each new test file holds one tape test**, with its assertions covering the tables below (level cap: 5 new cases).

| `isNumber` input | output |
|---|---|
| `5`, `NaN`, `'0x1F'`, `'0X1f'`, `'1e5'`, `'1.'`, `'.5'`, `'+1'`, `[1]` (quirk: coerced to a string) | `true` |
| `''`, `' 1'`, `'.'`, `'-0x1'`, `'abc'`, `null` | `false` |

| `hasKey` call | output |
|---|---|
| `hasKey({ a: { b: 1 } }, ['a', 'b'])` | `true` |
| `hasKey({ a: 0 }, ['a', 'b'])` (quirk: falsy step becomes `{}`) | `false` |
| `hasKey({ a: 1 }, ['a', 'b'])` (quirk: `in` on a number) | throws `TypeError` |

| `setKey` from `createSetKey(isBooleanKey)` | result |
|---|---|
| `{}`, `['a', 'b']`, `1` | `{ a: { b: 1 } }` |
| `{ a: 1 }`, `['a']`, `2`; `isBooleanKey` false | `{ a: [1, 2] }` |
| `{ a: [1] }`, `['a']`, `2`; `isBooleanKey` false | `{ a: [1, 2] }` |
| `{ a: 1 }`, `['a']`, `2`; `isBooleanKey` true | `{ a: 2 }` |
| `{ a: true }`, `['a']`, `2`; `isBooleanKey` false | `{ a: 2 }` |
| `{}`, `['__proto__', 'x']`, `1` | `obj` unchanged, prototype still `Object.prototype` |
| `{}`, `['a', 'constructor']`, `1` | `{ a: {} }` |

| `buildFlags` input | output |
|---|---|
| `undefined` | `{ aliases: {}, allBools: false, bools: {}, strings: {}, unknownFn: null }` |
| `{ boolean: true }` | `allBools: true`, `bools: {}` |
| `{ boolean: ['x', 'y'] }` | `allBools: false`, `bools: { x: true, y: true }` |
| `{ boolean: 'x', alias: { x: 'y' } }` | `bools: { x: true }`, `aliases: { x: ['y'], y: ['x'] }` |
| `{ alias: { a: ['b', 'c'] } }` | `aliases: { a: ['b', 'c'], b: ['a', 'c'], c: ['a', 'b'] }` |
| `{ string: 'a', alias: { a: 'b' } }` | `strings: { a: true, b: true }` |
| `{ unknown: 'not a function' }` | `unknownFn: null` |

**FR6 needs no change.** `package.json` has no `files` field and neither `.gitignore` nor `publishConfig.ignore` excludes `lib/`. Measured on a throwaway copy with a `lib/is-number.js`: `npm pack --dry-run` listed it, and the generated `.npmignore` has no rule for `lib/`.

Data flow, persistence, migrations, UI, permissions: no implication. Rollback: discard the working-tree changes. Out of scope as in the spec: `package.json`, `.eslintrc`, `CHANGELOG.md` and the existing test files are not edited.

### Touched files
- `lib/is-number.js` (new)
- `lib/has-key.js` (new)
- `lib/set-key.js` (new)
- `lib/build-flags.js` (new)
- `index.js`
- `test/lib-is-number.js` (new)
- `test/lib-has-key.js` (new)
- `test/lib-set-key.js` (new)
- `test/lib-build-flags.js` (new)
- `test/equivalence.js` (new)
- `test/fixtures/parser-before-split.js` (new)

### Steps
#### Block B1 — modules
writes: `lib/is-number.js`, `lib/has-key.js`, `lib/set-key.js`, `lib/build-flags.js`
after: none

| id | file | change | test |
|---|---|---|---|
| P1 | `lib/is-number.js` | move `isNumber` (`index.js:13-17`) | T1 |
| P2 | `lib/has-key.js` | move `hasKey` (`index.js:3-11`) | T2 |
| P3 | `lib/set-key.js` | move `isConstructorOrProto` and `setKey` behind `createSetKey` | T3 |
| P4 | `lib/build-flags.js` | move flag and alias building, returning the five properties | T4 |

#### Block B2 — parser
writes: `index.js`
after: B1

| id | file | change | test |
|---|---|---|---|
| P5 | `index.js` | require the four modules; remove `hasKey`, `isNumber`, `isConstructorOrProto`, `setKey` and the flag and alias building | T5 |

### Requirement traceability
| Req | Plan steps | Verification |
|---|---|---|
| FR1 | P1, P2, P3, P4, P5 | T5 |
| FR2.1 | P1 | T1 |
| FR2.2 | P2 | T2 |
| FR2.3 | P3 | T3 |
| FR2.4 | P4 | T4 |
| FR3 | P5 | T5 |
| FR4 | P1, P2, P3, P4 | T1, T2, T3, T4 |
| FR5 | P1, P2, P3, P4, P5 | not verifiable by a test: the lint gate, whose parser is set to `ecmaVersion` 5, so any non-ES5 syntax is a lint error |
| FR6 | P1, P2, P3, P4 | not verifiable by a test (stubs already put the files in the package, so it cannot be proven red): measured, see Decisions |
| AC1 | P5 | not verifiable by a test (invariance, cannot be proven red): covered by the existing tests in `test/` |
| AC2 | P5 | T5 |
| AC3 | P1, P2, P3, P4 | T1, T2, T3, T4 |
| AC4 | P1, P2, P3, P4, P5 | not verifiable by a test: the lint gate, as FR5 |
| AC5 | P1, P2, P3, P4 | not verifiable by a test: as FR6 |

### Strings and data-test
| action | type | value |
|---|---|---|

### Test plan
| ID | requirement | file | assertion | mutation |
|---|---|---|---|---|
| T1 | FR2.1, FR4, AC3 | `test/lib-is-number.js::isNumber keeps the semantics of the parser` (new) | red if: `isNumber accepts a hex string` | — |
| T2 | FR2.2, FR4, AC3 | `test/lib-has-key.js::hasKey keeps the semantics of the parser` (new) | red if: `hasKey finds a nested key` | — |
| T3 | FR2.3, FR4, AC3 | `test/lib-set-key.js::createSetKey keeps the semantics of the parser` (new) | red if: `setKey creates nested objects` | `lib/set-key.js` · `isConstructorOrProto` · `key === '__proto__'` → `false` · red if: `setKey leaves the prototype of obj untouched` |
| T4 | FR2.4, FR4, AC3 | `test/lib-build-flags.js::buildFlags computes flags and aliases` (new) | red if: `buildFlags(undefined) equals buildFlags({})` | — |
| T5 | FR1, FR3, AC2 | `test/equivalence.js::index.js uses lib and matches the parser before the split` (new) | red if: `index.js requires lib/is-number` | `lib/set-key.js` · `createSetKey` · `typeof o[lastKey] === 'boolean'` → `false` · red if: `parser output matches the parser before the split` |

EXISTING non-regression tests (not rows of the Test plan: they cannot be proven red on the base with stubs):
- `test/proto.js`: the prototype-pollution protections still hold through the parser (FR1, AC1).
- The other existing files of `test/*.js`: unchanged and green (FR1, AC1).

### Plan review changelog
Open decision: plan-check lint2 rejects every step and mutation path under `lib/`, because the first segment of the path must already exist at the repository root (`in_repo`, plan-check.sh:839-840) and FR2 places the modules in a folder that does not exist yet; new files get no exemption. The six violations are at the rows P1, P2, P3, P4, T3, T5. The cycle may write only this spec, so the folder was not created, and the paths were not disguised (a `./lib/` form) nor moved to other files. On a scratch copy with an empty `lib/`, lint2 exits 0 with no other violation. No reviewer has seen this plan: a violation must be fixed first.
Options for the human: (A, recommended) create the empty folder `lib/` in the working tree and re-run the cycle, which then starts the review rounds on this plan; (B) fix plan-check so that a path declared new in the touched files list may have a first segment that does not exist yet, then re-run.
Metrica ciclo: giri=0 · R1=0/0 · delta=0/0 · gate=0/0 · rifiutati=0 · ricorrenze=0 · reintrodotti=0 · esito=decisione-umana · livello=std · superfici=contratto-api,logica-condivisa · formato=2
