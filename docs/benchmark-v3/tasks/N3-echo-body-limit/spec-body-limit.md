# Spec: `BodyLimit` can be bypassed by one large read, and over-limit bodies are answered 400 when bound

## Problem

`middleware.BodyLimit` is documented as enforcing the limit «based on both `Content-Length` request header and actual
content read». When the length is not known in advance (a chunked request, `Content-Length` = -1), or when it is
understated, the check on the content read does not hold:

- The caller's buffer is passed on as it is and the count is checked afterwards. With `BodyLimit(5)`, a body of 50 bytes
  and one `c.Request().Body.Read` with a 64-byte buffer, the handler receives all 50 bytes, together with the 413 error.
- `io.Reader` tells a caller to process the `n > 0` bytes before looking at the error, so a well-behaved caller uses data
  over the limit. A `json.NewDecoder(c.Request().Body).Decode(&v)` can accept a whole document larger than the limit.
- After the limit has been passed, further reads keep returning data of the body.

Three related defects are part of this change:

- `Context.Bind` answers **400** when the body goes over the limit, for JSON, XML, forms and multipart forms: the client
  is told its request is malformed instead of too large.
- The request's body is not its own for the life of the request. After the middleware returns, a body kept by an outer
  middleware can start serving the data of a later request.
- A negative `LimitBytes` is accepted without any complaint.

**The trap of this task is security and its error paths:** the client is hostile, and chooses the size of the body, how it
is split, and when it ends. The limit must hold for every way of reading, the 413 must not get lost or turn into a 400 on
its way out, and errors that have nothing to do with the limit must stay what they are today.

## Public API concerned

These names are public and stay as they are: `middleware.BodyLimit`, `middleware.BodyLimitWithConfig`,
`middleware.BodyLimitConfig` (`Skipper`, `LimitBytes`, `ToMiddleware`), `middleware.Decompress`, `echo.Context.Bind`,
`echo.BindBody`, `echo.Echo.JSONSerializer`, `echo.JSONSerializer`, `echo.ErrStatusRequestEntityTooLarge`, `echo.StatusCode`.

Below, **the body** is what a handler reads from `c.Request().Body` once `BodyLimit` has run, **the source** is the body the
request had before it, **the limit** is `LimitBytes`, and **the 413 error** is an error `err` for which both
`errors.Is(err, echo.ErrStatusRequestEntityTooLarge)` and `echo.StatusCode(err) == 413` hold.

## Functional requirements

**FR1. Never more than the limit.** Whatever the size of the buffers of the caller and however the source splits its data,
a caller that reads the body until an error receives exactly the first `LimitBytes` bytes of a source that has more, and then
the 413 error. The allowed bytes may come in the same `Read` as the error or in earlier ones.
Edge cases, all with the length unknown or understated:
- one `Read` with a buffer larger than the limit, larger than the whole body, or equal to the limit;
- a body one byte over the limit, read in one `Read` or byte by byte;
- a source that returns short reads;
- limit 0: no byte is delivered from a source that has data;
- a `Content-Length` smaller than the real body (3 declared, 50 sent, limit 5): 5 bytes, then the 413 error.

Example: `BodyLimit(5)`, 50 bytes, 64-byte buffer: 5 bytes in total, then the 413 error. A handler that returns the error
gives the response status 413.

**FR2. The 413 error stays.** Once the 413 error has been returned, every later `Read` with a non-empty buffer returns 0 bytes
and the 413 error again, and does not read from the source any more.

**FR3. The source is not drained.** While the body is read to its end, at most `LimitBytes + 1` bytes in total are taken from
the source, whatever the buffers of the caller: the bytes over the limit are not read and thrown away.
Edge cases: a 100,000-byte source with a 65,536-byte buffer and limit 5 gives up 6 bytes at most; limit 0 gives up 1 at most.

**FR4. Bodies within the limit behave as before.** A source of at most `LimitBytes` bytes is delivered completely, followed by
`io.EOF`, with no 413 error.
Edge cases:
- a body of exactly the limit, with any buffer size, and also when the source returns its last bytes together with `io.EOF`;
- an empty body, also with limit 0;
- `LimitBytes` = `math.MaxInt64`: no arithmetic overflow and no panic, with any buffer size;
- a `Read` with a zero-length buffer returns 0 and a nil error, and does not count as going over the limit, also when the
  limit is 0 or is already reached (as long as the 413 error has not been returned yet).

**FR5. Errors of the source stay errors of the source.** Within the limit, an error of the source is returned as it is
(`errors.Is` finds it), together with the bytes that came with it. It is not remembered: the next `Read` asks the source again.
Edge cases:
- the source fails exactly after `LimitBytes` bytes: the caller gets the error of the source, not the 413 error;
- the source returns more bytes than allowed together with an error, `io.EOF` included: the 413 error wins, and the rule of FR1
  on the delivered bytes applies.

**FR6. Each request has its own body, for as long as the request lives.** The value set as `c.Request().Body` stays valid after the
middleware has returned. Read later, also after other requests have gone through the same middleware instance, it still
serves the data of its own request, under the limit and with its own count.
Edge cases: an outer middleware that reads the rest of the body after its `next` returned; the count starts from zero for each request,
for sequential and for concurrent requests; `Close` on the body reaches the source, also after the 413 error.

**FR7. Invalid configuration.** `BodyLimitConfig.ToMiddleware` returns a non-nil error when `LimitBytes` is negative;
`BodyLimit` and `BodyLimitWithConfig` panic in that case, as they do for any invalid configuration of a middleware.
Edge cases: 0 and `math.MaxInt64` are valid.

**FR8. Binding answers 413.** When the body goes over the limit while it is bound, `Context.Bind` and `echo.BindBody` return an
error with `echo.StatusCode(err) == 413`, and a handler that returns it gives the response status 413 with the default error
handler.
Edge cases:
- all of `application/json`, `application/xml`, `text/xml`, `application/x-www-form-urlencoded` and `multipart/form-data`,
  the last one also when the excess is in a file part;
- a body one byte over the limit, when the excess falls inside the document (for XML, before its root element ends);
- a custom `Echo.JSONSerializer` whose `Deserialize` decodes from the body in a streaming way and returns the decoder's error
  as it is.

**FR9. Other binding errors do not change.**
- A body of exactly the limit binds normally, for each of the media types of FR8.
- A malformed body within the limit is still 400, for JSON, XML, forms and multipart forms.
- An error of the source that is not an `echo` error with a status (a plain `errors.New`) is still 400, for the same four.
- An error with a status returned by a custom `Echo.JSONSerializer` keeps that status (a 422 stays 422).
- An unsupported media type is still 415.

**FR10. The rest of the middleware does not change.**
- A declared `Content-Length` over the limit still gives 413 before the handler runs, without reading the source; a declared
  length equal to the limit is accepted.
- A request for which `Skipper` returns true is not limited at all.
- `BodyLimit` placed after `Decompress` counts the decoded bytes, within the limit and over it.
- Exported names and signatures stay as they are, and the 413 of the middleware stays `echo.ErrStatusRequestEntityTooLarge`.

**FR11. Regression tests.** The project's tests cover FR1 to FR9. Existing tests may be adapted only where they rely on
unexported details of the middleware.

## Acceptance criteria

AC1. Every example and edge case of FR1 to FR10 holds.

AC2. `go test ./...` and `go vet ./...` pass; `gofmt -l .` prints nothing except the two files declared below.

## Failures already present at the starting commit

`gofmt -l .` lists two files, for a stray blank line in each: `echo.go` and `middleware/decompress.go`. This has nothing
to do with this task, is excluded from every check and count, and does not have to be fixed.

## Out of scope

- Whether the connection is closed after an over-limit read.
- Other limits of the framework, and the limit of `Decompress` itself.
- What `Bind` does with a document that is complete before the limit, when only data after its end goes over it (a streaming
  decoder may stop reading there).
- Other ways of parsing forms (`Context.FormValue` and similar).
- Version 4 of the framework, and changelog or release notes.

## Constraints

- The Go version declared in `go.mod`; standard library only, no change to `go.mod` or `go.sum`.
- `gofmt` formatting.
