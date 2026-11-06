The parser is split into the four `lib/` modules and I found no behaviour differences, but AC4 isn't fully met. `example/parse.js` uses `const`, so it doesn't parse as ES5. Nothing is committed.

## What changed
- **`lib/is-number.js`, `lib/has-key.js`, `lib/set-key.js`, `lib/build-flags.js` (new):** the code is moved as it was, including its quirks. Each file is strict mode and exports one function. `isConstructorOrProto` is now a private helper in `set-key.js`.
- **`index.js`:** it now uses the four modules. The argument loop, `argDefined`, `setArg` and `isBooleanKey` stay here, and `isBooleanKey` is passed to `createSetKey`.
- **`test/lib-is-number.js`, `test/lib-has-key.js`, `test/lib-set-key.js`, `test/lib-build-flags.js` (new):** unit tests for each module.
- **Not changed:** existing tests, `.eslintrc` and `package.json`. `lib/` was already included in the published package.

## What I verified

| Check | Command | Result |
|---|---|---|
| AC1 and FR4 tests | `npx tape 'test/**/*.js'` | 297 of 297 pass (171 before); `git diff` shows existing tests unchanged |
| Coverage | `npm run tests-only` (run before the last small test edits) | 100% lines; all `lib/` files 100% |
| AC2 old vs new | throwaway script in `/tmp` comparing against `git show HEAD:index.js` | 1,000,000 generated cases, 0 differences |
| AC3 | `require` of each module on its own, plus the unit tests | all load and behave as described |
| AC4 lint | `npx eslint --ext=js,mjs .` | exit 0, 0 errors, 54 warnings (same count as before) |
| AC4 ES5 parse | acorn with `ecmaVersion: 5` | 25 of 26 tracked and new `.js` files parse; `example/parse.js` fails |
| AC5 | `npm pack --dry-run` | lists all four modules |

- **What the comparison covers:** it checks the output (key order, types and prototypes), thrown errors, `opts.unknown` arguments and order, and the order options are read in. It also confirms built-in prototypes stay unpolluted. The cases include awkward names like `__proto__` and `constructor`, and falsy `opts`.
- **Whether the comparison can catch a change:** I broke the new code on purpose in 9 different ways (for example removing the `__proto__` guard), and it flagged all 9.
- **Harness bug fixed:** the first version reported false differences because the parser changes array and object defaults in place, and runs shared them. Each run now gets its own copy of the options.

## Open points
1. **AC4 and `example/parse.js`:** the `const` was already there and I left it. The spec doesn't list this file, FR5 only covers new and changed files, and switching to `var` makes the lint fail under the example's own config. All package code outside `example/` parses as ES5. Decide whether AC4 should exclude examples.
2. **One small difference FR1 doesn't list:** `opts.unknown` is still called as `flags.unknownFn(arg)`, so `this` inside it is still the flags object. That object now also has `aliases`, and `allBools` is `false` rather than missing. FR2.4 requires this shape, and a callback would only notice if it inspected its undocumented `this`. I saw this by reading the code; the comparison doesn't check `this`.
3. **Not run on old Node:** everything ran on Node 20.20.2, not on the old versions in `engines`. For those I only have the ES5 parse and the fact that the code was moved unchanged.

## Quirks kept, not fixed
- `hasKey` and `setKey` throw a `TypeError` when the parent of the last key is a truthy primitive. For example, `--a 1 --a.b 2` should hit this in `setKey`. Both module-level cases are pinned in the unit tests.
- The `bools`, `strings` and `aliases` objects inherit from `Object.prototype`, so `flags.bools.constructor` is truthy. From reading the code, `--constructor` should then throw a `TypeError` in `setArg`, because `aliases.constructor` is a function with no `forEach`. I didn't run that exact input.

## Cleanup
I removed the generated `.npmignore` that `npm pack` creates, plus any coverage output. The comparison script is in `/tmp/split-diff/`, outside the repo. It's easy to add as a test if you want to keep it, but it would need the old `index.js` as a reference copy.

<!-- total_cost_usd=0.8466118000000001 duration_ms=296933 num_turns=6 -->
<!-- usage_from_transcript={"claude-opus-5-5": {"cache_creation_input_tokens": 44591, "cache_read_input_tokens": 182179, "calls": 6, "input_tokens": 12, "output_tokens": 48}} -->
