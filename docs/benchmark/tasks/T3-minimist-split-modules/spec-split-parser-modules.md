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
