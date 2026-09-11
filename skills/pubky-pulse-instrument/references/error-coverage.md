## Contents

- [The doctrine](#the-doctrine)
- [Web boundaries](#web-boundaries)
- [Node boundaries](#node-boundaries)
- [Swift boundaries](#swift-boundaries)
- [Android boundaries](#android-boundaries)
- [Report or skip](#report-or-skip)

## The doctrine

Every failure the product can have should reach the issue tracker exactly once, under
a stable name, carrying the error object. That gives three obligations at each
boundary:

1. **Report the error value, not a string built from it.** The SDK extracts
   `_error_type`, the stack, and the cause chain from the object. Without
   `_error_type`, a decoding failure and a transport failure with the same wording
   become one issue.
2. **Name the event for the action that failed**, in snake_case, with no interpolated
   values: `photo_upload_failed`, never `` `upload of ${id} failed` ``. The message is
   the grouping key.
3. **Report at the handling layer.** If an inner function reports and rethrows and the
   outer handler reports again, one failure produces two issues.

The snippets below are the shapes; the sibling SDK skills carry the full versions with
imports and framework detail.

## Web boundaries

Automatic: `window`'s `error` and `unhandledrejection` events only.

- [ ] **Error boundary** — React's `componentDidCatch`, Vue's `onErrorCaptured`,
      Svelte's `<svelte:boundary>`. A boundary that renders a fallback and reports
      nothing is a silent failure.
- [ ] **Router error element** — `errorElement`, `+error.svelte`, `error.tsx`.
- [ ] **Every `catch` on an async path** — loading, mutations, uploads, parsing.
- [ ] **Non-2xx `fetch`** — a `404` resolves; it never rejects.
- [ ] **Data-layer hooks** — TanStack Query, SWR, Apollo, RTK Query error callbacks.
- [ ] **`XMLHttpRequest` and axios** — the SDK wraps `fetch` only.
- [ ] **Web workers** — a worker's failures never reach the page's handlers.
- [ ] **`console.error` sites** — convert the ones that mean a real failure.

```ts
try {
  await pay(order);
} catch (err) {
  Pulse.captureException(err, {
    message: "checkout_failed",
    attributes: { stage: "payment" },
  });
}
```

`captureException` accepts any thrown value, including strings and objects. It
preserves the original value in the transient `beforeSend(event, hint)` hint for
app-owned filtering or an allowlist of safe metadata fields. Do not serialize or
spread `hint.originalException` into attributes. Put shared expected-error patterns
in `ignoreErrors`; use `beforeSend` for application-specific policy.

Report once at the existing shared query callback, boundary or final handling layer.
The SDK deduplicates the same `Error` object, but that is a backstop: newly wrapped
errors and primitive throws are not deduplicated. The coverage scanner cannot follow
helper calls, so record centralized coverage as a justified site instead of adding a
second report merely to make the scanner pass.

```ts
const res = await fetch(url);
if (!res.ok) {
  Pulse.captureException(new Error(`HTTP ${res.status}`), {
    message: "api_request_failed",
    attributes: { route: "/orders/[id]", status_code: String(res.status) },
  });
}
```

Keep route labels app-owned and free of identifiers. For automatic screen tracking,
pass `screenNameForPath: createScreenNameMapper([...])` with the app’s supported
route templates; unknown paths use `/unknown`. If fetch telemetry is useful,
`networkTracking: { urlMode: "origin" }` omits paths as well as query and fragment.
These options do not sanitize custom attributes, error text or manually supplied
screen names; choose safe values there too.

## Node boundaries

Automatic: `uncaughtException` and `unhandledRejection`, tagged `_unhandled`. The
process still dies afterwards, so the supervisor still has to restart it.

- [ ] **Framework error handler** — Express's four-argument handler registered last,
      or Fastify's `setErrorHandler`. One handler covers every route's 500 path.
- [ ] **Queue workers** — BullMQ or pg-boss marks the job failed and no process
      handler ever sees it.
- [ ] **Scheduled jobs** — a `node-cron` callback that throws is swallowed.
- [ ] **WebSocket and Socket.IO** — connection, message and close handlers.
- [ ] **Streams** — an `error` event on a pipeline is not an exception anywhere.
- [ ] **Database pools and outbound HTTP** — pool `error` events, and non-2xx
      responses, which resolve rather than reject.

```ts
worker.on("failed", (job, err) => {
  Pulse.error(err, "job_failed", { job: job?.name ?? "unknown", attempt: String(job?.attemptsMade ?? 0) });
});
```

```ts
cron.schedule("0 3 * * *", async () => {
  try {
    const result = await runRoyalties();
    Pulse.info("nightly_royalties_completed", { processed: String(result.processed) });
  } catch (err) {
    Pulse.error(err, "royalties_job_failed");
  }
});
```

## Swift boundaries

Automatic: nothing. Runtime traps — force unwrap, array bounds, `fatalError` — kill
the process before any handler could run, so there is no crash coverage to configure.
Every error in the issue tracker got there because code called `Pulse.error`.

- [ ] Every `catch` block
- [ ] Every `Result` `.failure` / `case .failure(let error)`
- [ ] Every unstructured `Task { }` — a thrown error inside is swallowed silently
- [ ] Every SwiftUI `.task { }` and `.refreshable { }`
- [ ] Every Combine `.sink(receiveCompletion:)` failure
- [ ] Every `JSONDecoder.decode` failure — the `DecodingError` type is the key
- [ ] Every non-2xx HTTP response, and every thrown transport error
- [ ] Every delegate error callback
- [ ] Every `try?` that discards a failure — report it or justify it

```swift
do {
    try await uploadPhoto(data)
} catch {
    Pulse.error(error, "photo_upload_failed", screenName: "Gallery",
                attributes: ["size_kb": String(data.count / 1024)])
}
```

```swift
Task {
    do { try await refresh() }
    catch { Pulse.error(error, "refresh_failed") }
}
```

## Android boundaries

Automatic: nothing — no crash capture, and `networkTrackingEnabled` is reserved and
instruments no HTTP client, so an OkHttp interceptor is part of the baseline rather
than an extra.

- [ ] Every `try`/`catch`
- [ ] Every `runCatching { }.onFailure { }`
- [ ] A `CoroutineExceptionHandler` on every root scope
- [ ] Every `viewModelScope.launch` body that can throw
- [ ] Every `Flow.catch { }`
- [ ] Every repository-layer `Result.failure` branch
- [ ] Every WorkManager failure path
- [ ] Every OkHttp or Retrofit failure — non-2xx and `IOException`
- [ ] Every `enqueue`-style callback's failure branch

```kotlin
try {
    uploadPhoto(bytes)
} catch (e: CancellationException) {
    throw e                    // the caller went away; not a failure
} catch (e: Exception) {
    Pulse.error(e, "photo_upload_failed", attributes = mapOf("size_kb" to "${bytes.size / 1024}"))
}
```

`CancellationException` is an `Exception`, so a bare `catch (e: Exception)` that
reports and swallows both hides a real cancellation and files noise as an issue.
Rethrow it first, every time.

## Report or skip

A handling site may stay silent only when one of these is true, and the reason belongs
in the final report:

| Situation | Why it is fine |
|---|---|
| The `catch` rethrows immediately to a layer that reports | reporting twice makes two issues from one failure |
| Failure is the expected control flow — a cache miss, an optional parse, a feature probe | it is not a failure, and at most a `debug` event |
| A `CancellationException` or task-cancellation rethrow | the user navigated away |
| A cleanup path in a `finally` whose own failure changes nothing | nobody can act on it |

Everything else reports. In particular, a `catch` that shows the user an error message
and reports nothing is the exact case the issue tracker exists for.
