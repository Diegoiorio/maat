# Spec: `event.url.pathname` decodes only the escapes that are safe to decode

## Context

h3 v2 gives every handler a parsed request URL as `event.url`, next to the original request as `event.req`. Route
matching, `use()` route filters and handlers all read `event.url.pathname`, so that a spelling such as `/%61dmin` cannot
slip past an `/admin` guard and still reach the `/admin` route. The guide («`H3Event.url`», «Pathname decoding») documents
the rule in force today: the path goes through one `decodeURI` pass, and the URL parser serializes the result again.

That rule is wrong in both directions.

It **decodes too little**: `decodeURI` keeps `; : @ & = + $ ,` encoded, although these characters mean nothing special
inside an already parsed path. So `/%40admin/x` is not caught by a guard on `/@admin/**` and falls through to a catch-all
handler, whose downstream consumer (a proxy, a filesystem, a handler calling `decodeURIComponent`) reads it as `/@admin/x`.
A route registered as `/@handle` is not reached by `/%40handle` at all.

It **changes too much**, because the result is parsed again:

| Request | `event.url.pathname` today | Problem |
|---|---|---|
| `/a%5Cb` | `/a/b` | an encoded backslash became a real separator: one segment turned into two |
| `/a%09b` | `/ab` | the character was deleted |
| `/caf%c3%a9` | `/caf%C3%A9` | the spelling of an escape nobody needed to touch was rewritten |

h3 is on a release candidate and accepts a breaking change here: the rule below replaces the old one.

## Goal

`event.url.pathname` is the path in its wire encoding, with exactly one exception: the escapes of a fixed set are decoded,
once, before anything matches on the path. Routes, middleware and handlers keep comparing one and the same string, and
the original URL stays as it arrived.

## Public API concerned

`H3`, with `get()`, `on()`, `all()`, `use()` (its route filter and its `match` option), `mount()`, `request()`, `config`;
`H3Event`, `event.url`, `event.path`, `event.req`, `event.runtime`; `mockEvent()`, `defineHandler()` and its `.fetch()`;
`getRequestURL()`, `getRouterParam()`, `getRouterParams()`, `removeRoute()`, `requestWithBaseURL()`, `withBase()`,
`fromNodeHandler()`, `serveStatic()` with `getMeta` and `getContents`; the `allowMalformedURL` option of `H3`.

## The trap

This is a security and compatibility change. **Security:** a path must not be decoded twice, a guard must not be
walkable past by a different spelling of its path, and an escape that used to be rewritten before it reached a consumer
must not open a traversal now that it arrives intact. **Compatibility:** apart from the changes this spec states, what
callers see from routing, mounts, static serving and malformed URLs stays as it is.

## Functional requirements

**FR1. The decoded set.** In `event.url.pathname`, an escape `%HH` is replaced by its character exactly when that
character is one of:

- a letter or a digit: `A`–`Z`, `a`–`z`, `0`–`9`;
- one of `-` `.` `_` `~`;
- one of `!` `$` `&` `'` `(` `)` `*` `+` `,` `:` `;` `=` `@` `[` `]` `|`.

The set is exactly this list, on every runtime; it does not follow what the URL parser of the running runtime happens to
keep literal.

Edge cases: both hex cases count (`%2a` and `%2A` give `*`). Decoded and untouched escapes can sit in the same path:
`/%61%2F%62` gives `/a%2Fb`, `/%40%20%41%c3%a9/%7Euser` gives `/@%20A%c3%a9/~user`. `/%61dmin` gives `/admin`, `/a%21b`
gives `/a!b`, `/users/me%3Adelete` gives `/users/me:delete`.

**FR2. Everything else stays byte for byte.** Every other escape remains exactly as it arrived, its hex case included.

Edge cases: `%2F` and `%2f` (a separator would change how many segments the path has); `%5C` and `%5c` (same, and no
longer turned into `/`); `%25` (decoding it would expose a nested escape); `%20 %22 %23 %3C %3E %3F %5E %60 %7B %7D %7F`;
the control characters `%00`–`%1F`, which must not be deleted (`/a%09b` stays `/a%09b`); and every escape from `%80` up:
`/caf%C3%A9` stays `/caf%C3%A9` and `/caf%c3%a9` stays `/caf%c3%a9`.

**FR3. One pass, never a second decode.** The rule applies once. What a decode produces is not looked at again, and
applying the rule to its own result changes nothing.

Edge cases: `/a%2541` and `/%2561dmin` are unchanged. `/a%25%32%46b` gives `/a%252Fb` (`%32` and `%46` decode, `%25` does
not, and the `%2F` this spells stays hidden behind `%25`); `/%25%36%31dmin` gives `/%2561dmin`; `/a%2541-%41` gives
`/a%2541-A`. A double-encoded path reaches neither the route nor the guard of the decoded path: `/%2561dmin/secret` is
not `/admin/secret`. Two events built on one request give the same result.

**FR4. Dot segments and leading slashes.** Dot segments are resolved as the URL parser already resolves them, every
`%2e` spelling included, and a decode never puts one back or creates a new one.

Edge cases: `/a/%2e%2e/b`, `/a/%2E%2E/b` and `/a/.%2e/b` give `/b`; `/a/%2e/b` gives `/a/b`; `/files/%2e%2e/%61dmin` gives
`/admin`, which an `/admin/**` guard catches. `/a/%2e%2ex/b` gives `/a/..x/b`, and `/a%2eb` gives `/a.b`: these are not
dot segments. A segment holding an encoded separator is not one either: `/%2e%2e%2fadmin` gives `/..%2fadmin` and
`/x/%2e%2e%5cadmin` gives `/x/..%5cadmin`. A leading run of slashes keeps its length: `//evil.com/%61` gives
`//evil.com/a`, `///evil.com/%61` gives `///evil.com/a`, `//%61` gives `//a`.

**FR5. The original URL is left alone.** `event.req.url` always keeps the wire encoding, and on Node so does the raw
`event.runtime.node.req.url`. A parsed URL that a runtime shares with h3 on the request is not mutated. The query is
never touched: for `/a/%61?x=%61&y=%2F`, `event.url.pathname` is `/a/a`, `event.url.search` is `?x=%61&y=%2F`,
`new URL(event.req.url).pathname` is `/a/%61`, and `event.path` is `/a/a?x=%61&y=%2F`. The rest of `event.url` describes
the same request: protocol, host and port are kept, and `href` shows the new path. `getRequestURL()` gives the same
pathname as `event.url`.

**FR6. Malformed encoding keeps its behaviour.** A path that `decodeURI` would reject (a truncated or non-hex escape, or
bytes that are not valid UTF-8) has nothing to decode to. It is rejected with `400` before any middleware or handler
runs, unless the `allowMalformedURL` option is set; then the handler gets the raw path.

Edge cases: `/foo%`, `/bar%2`, `/%ZZ`, `/%80`, `/%C3%28`, and `/%61dmin%ZZ`, where a valid escape sits next to the bad
one. With `allowMalformedURL`, **nothing** in such a path is decoded: `/%61dmin%ZZ` stays `/%61dmin%ZZ`, `/%40%80` stays
`/%40%80`. A directly built event does not throw and keeps the raw path.

**FR7. One string for routes, guards and handlers.** Route matching, `use()` route filters, `match` functions and
`event.url.pathname` in a handler all see the result of FR1 to FR4.

Edge cases: a spelling cannot walk past a guard: with `use("/@admin/**", …)` both `/@admin/x` and `/%40admin/x` are
caught; likewise `/admin` by `/%61dmin`, `/users/me:delete` by `/users/me%3Adelete`, `/a$b`, `/a&b`, `/a+b`, `/a,b`, `/a;b`,
`/a=b`, `/a!b`, `/a'b`, `/a|b`, `/~me` by their escapes. `/%40handle` reaches a route registered as `/@handle`. **A
behaviour change:** an encoded separator is part of one segment, so `/a%2Fb` and `/a%5Cb` match `/:id`, not `/a/:rest`, and
`getRouterParam(event, "id")` returns them as they arrived. `getRouterParams(event, { decode: true })` keeps its promise of
never producing a raw separator: `/files/a%2Fb%20c` gives `a%2Fb c`, `/files/a%5Cb%20c` gives `a%5Cb c`, `/files/a%252Fb`
gives `a%252Fb`, `/files/caf%C3%A9` gives `café`. Without `decode`, `/files/%40x%20y` gives `@x%20y`.

**FR8. Route strings follow the same rule.** A route string given to `get()`, `on()`, `all()` and the other route
methods, to `use()` as a route filter, or to `removeRoute()` is subject to FR1 as well, so that the two spellings are
one route.

Edge cases: a route registered as `/%40handle` is reached by both `/%40handle` and `/@handle`. `use("/%40admin/**", …)`
runs for both `/@admin/x` and `/%40admin/x`. A route registered as `/%40x` is removed by `removeRoute(app, "GET", "/@x")`,
and one registered as `/@x` by `removeRoute(app, "GET", "/%40x")`. Routes keep working when they hold an escape outside
the set, or characters the URL parser encodes: `/a%2Fb` stays one segment, distinct from `/a/b`; `/x y` matches `/x%20y`;
`/café` matches `/caf%C3%A9`.

**FR9. Mounts and base paths see the same path.** What a mount or a base strips, and what it passes on, is the path of
FR1 to FR4, never a path decoded by another rule.

Edge cases, with `app.mount("/api", fetchHandler)`, as the handler sees them in `req.url`: `/api/hello` gives `/hello`;
`/%61pi/%61dmin` gives `/admin`; `/api/%40me` gives `/@me`; `/api/a%2Fb%5Cc` gives `/a%2Fb%5Cc`; `/api/a%2fb%5cc` gives
`/a%2fb%5cc`; `/api/caf%c3%a9?q=%41` gives `/caf%c3%a9?q=%41`; `/api/a%20b` gives `/a%20b`; `/api/a%2541` gives `/a%2541`.
A guard written inside the mounted handler sees `/admin` for `/api/admin`, `/%61pi/admin`, `/api/%61dmin` and
`/%61pi/%61dmin`. A mounted `H3` app routes on the same path (`/%61pi/h%65llo` reaches its `/hello`; `/api/p/a%5Cb` gives
its `/p/:id` the param `a%5Cb`, `/api/p/%40x` the param `@x`). `withBase("/api", handler)` too: `/%61pi/%40x` gives `/@x`, `/api/a%5Cb` gives `/a%5Cb`. A
legacy handler under `withBase("/api", fromNodeHandler(…))` sees `req.url` as `/hello?q=1` for `/api/h%65llo?q=1`, as
`/a%5Cb` for `/api/a%5Cb` and as `/caf%c3%a9` for `/api/caf%c3%a9`, and the raw Node URL is back to the wire form afterwards.
`requestWithBaseURL(req, base)` strips the base and leaves the escapes of FR2 and
the query as they arrived: `http://h/api/a%2Fb%5Cc?x=%41` with `/api` gives path `/a%2Fb%5Cc` and search `?x=%41`;
`http://h/api/caf%c3%a9%2541` gives `/caf%c3%a9%2541`; `http://h/other/a%5Cb`, outside the base, gives `/other/a%5Cb`.

**FR10. `serveStatic` stays safe, and finds the same files.** `serveStatic` decodes the path once more for its backend,
and that must not open a traversal now that `%5C` is no longer rewritten earlier. No id passed to `getMeta` or
`getContents` may contain a backslash or a `..` segment (`..` between separators, `/` or `\`, or at either end). A request
may also simply find nothing; a backend must just never be asked for such an id.

Edge cases: `/..%5c..%5cwindows%5cwin.ini`, the same in uppercase hex, `/a/..%5c..%5csecret`, `/%5c..%5c..%5csecret`,
`/x%5c..%5c..%5cy`, `/.%5c..%5csecret`, `/a%5c..`, `/%2e%2e%5c%2e%2e%5csecret`, `/%252e%252e/secret`,
`/%252e%252e%255c%252e%252e%255csecret`; and with `allowMalformedURL`, `/a%ZZ/../..%5c..%5cwindows%5cwin.ini` and
`/%ZZ..%5c..%5csecret`. Ordinary lookups do not change: the backend finds `/a b.txt` for `/a%20b.txt`, `/café.txt` for both
`/caf%C3%A9.txt` and `/caf%c3%a9.txt`, `/a.txt` for `/%61.txt`, `/a@b.txt` for `/a%40b.txt`, `/100%.txt` for `/100%25.txt`,
and `/a%2Fb.txt` for `/a%2Fb.txt`. A guard in front of `serveStatic` cannot be walked past: with `use("/a!b/**", …)`,
`/a%21b/secret.txt` is blocked, and likewise `/%40b/…` by `/@b/**`, `/a%27b/…` by `/a'b/**`, `/a%7Cb/…` by `/a|b/**`,
`/%61dmin/…` by `/admin/**`.

**FR11. Events built without an app.** The rule holds for every event, not only for those dispatched by an app:
`mockEvent("/%61dmin").url.pathname` is `/admin` and `mockEvent("/a%2Fb%5Cc").url.pathname` is `/a%2Fb%5Cc`; a standalone
`defineHandler(…).fetch("http://h/%61dmin/%40x/%5C")` sees `/admin/@x/%5C`; `new H3Event(new Request("http://localhost/%40x/a%5Cb?y=%40"))`
has pathname `/@x/a%5Cb` and search `?y=%40`.

## Acceptance criteria

AC1. Every example of FR1 to FR11 holds, on the web target (`app.request()`) and through a real Node server wherever a
request goes through an app, except the leading-slash examples of FR4, which a Node client cannot send as they are.

AC2. `pnpm lint` (oxlint and oxfmt) and `pnpm typecheck` report nothing, and the project's test suite passes (see
«Failures already present»).

AC3. Tests cover FR1 to FR11, and the existing tests that pin the old rule are updated to the new one. The suite also
holds bundle-size budgets: if this change pushes a bundle over one, raise that budget by what is needed.

AC4. The guide's description of `event.url.pathname` and of `allowMalformedURL` states the new rule.

## Failures already present

Five tests of the project can fail at the starting commit, for reasons unrelated to this work, and are excluded from every
count. Do not fix them.

- `getRequestFingerprint … uses the request ip when no x-forwarded-for header set (node)` always fails here: it compares
  the client address it sees with a pattern, and in this environment the address is `::ffff:127.0.0.1`, which the pattern
  does not accept.
- Four tests of the `stream` group, on the Node target, fail now and then on a busy machine, because they race real
  sockets against short timers: `node response stream: client abort propagates to source stream (node)`, `node response
  stream: source error terminates response without crashing (node)`, `web response stream: client abort propagates to
  cancel (node)`, `web response stream: source error terminates response gracefully (node)`.

## Assumptions

- The router compares strings exactly, so after FR2 a request with lowercase hex in an escape outside the set
  (`/caf%c3%a9`) does not match a route whose string has it in uppercase (`/café`, stored as `/caf%C3%A9`). This limit is
  accepted.
- Dependencies are installed; there is no network. Tests run with `npx vitest run`, or `pnpm vitest run` where `pnpm` is
  available.

## Out of scope

- The query string, the host, request headers.
- A route string given as the base of `mount()` or `withBase()` in an escaped spelling.
- `resolveDotSegments()` and its options.
- New dependencies.

## Constraints

- No change to the runtime dependencies.
- The public names above keep working as they do; additions are allowed, removals are not.
