## Contents

- Why every pattern here exists
- Plain `try`/`catch`
- `runCatching` and `Result`
- Coroutine scopes and `CoroutineExceptionHandler`
- ViewModels and `viewModelScope`
- `Flow`
- Retrofit and callback APIs
- WorkManager and background jobs
- Room, DataStore, and other framework failures
- Cancellation: the one thing not to report
- What to skip
- Wrapping it up: one helper per app

## Why every pattern here exists

The Android SDK captures no crashes and no HTTP failures. An error appears in Pubky
Pulse only because code called `Pulse.error`. Kotlin also has several places where a
failure is legal to ignore — `runCatching` with no `onFailure`, a `launch` on a scope
with no handler, a `Flow.catch` that only emits a fallback — so a codebase can look
thoroughly error-handled and report nothing.

Two rules apply to every snippet below:

1. **Pass the `Throwable`.** `Pulse.error(e, "…")` extracts `_error_type` (the class
   name), the JVM stack trace and the cause chain up to five levels. `_error_type` is
   the issue fingerprint's discriminator, which keeps an `IOException` and a
   `JSONException` with identical wording on separate issues.
2. **Keep the message a fixed template.** The message is the grouping key. Variable
   data — ids, URLs, counts — goes in `attributes`, never interpolated into the
   message, or every occurrence becomes its own issue.

## Plain `try`/`catch`

```kotlin
try {
    val order = api.submit(cart)
    Pulse.info("checkout_completed", screenName = "Checkout", attributes = mapOf(
        "order_id" to order.id, "amount_cents" to "${order.totalCents}",
    ))
} catch (e: Exception) {
    Pulse.error(e, "checkout_failed", screenName = "Checkout", attributes = mapOf(
        "item_count" to "${cart.items.size}", "payment_method" to method.name,
    ))
}
```

Report once, at the layer that decides what the failure means. A retry loop reports
the final outcome with a `retry_count` attribute, not each attempt. On a suspending
call site, add a `catch (e: CancellationException) { throw e }` branch first — see
*Cancellation* below.

## `runCatching` and `Result`

```kotlin
runCatching { repository.load() }
    .onSuccess { feed -> Pulse.info("feed_loaded", attributes = mapOf("item_count" to "${feed.size}")) }
    .onFailure { e -> Pulse.error(e, "feed_load_failed", attributes = mapOf("source" to "remote")) }
```

`runCatching` catches `Throwable` — cancellation, `OutOfMemoryError` and all. On
suspending code, rethrow cancellation before reporting:

```kotlin
.onFailure { e ->
    if (e is CancellationException) throw e
    Pulse.error(e, "feed_load_failed")
}
```

An explicit `try`/`catch (e: Exception)` narrows the blast radius, but
`CancellationException` extends `Exception` too, so that branch still needs the
rethrow.

A `getOrNull()` or `getOrDefault(...)` with no `onFailure` is a silent failure path —
add the report before the fallback.

For a domain `Result`-style sealed class, report in the error branch of the `when`
that consumes it, not at every layer it passes through.

## Coroutine scopes and `CoroutineExceptionHandler`

Every scope the app creates itself — a repository's `CoroutineScope`, a service's,
an application-level one — should carry a handler, or a thrown exception reaches the
JVM's default handler and takes the process with it.

```kotlin
private val handler = CoroutineExceptionHandler { _, throwable ->
    Pulse.error(throwable, "sync_scope_failed")
}
private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + handler)
```

`SupervisorJob` keeps one failed child from cancelling its siblings; the handler is
what makes the failure visible. A handler on a child coroutine is ignored — install
it on the scope.

`async` is different: its exception is stored and rethrown at `await()`, so wrap the
`await`, not the `async`.

## ViewModels and `viewModelScope`

```kotlin
fun refresh() {
    viewModelScope.launch {
        try {
            _state.value = UiState.Content(repository.load())
        } catch (e: Exception) {
            _state.value = UiState.Error
            Pulse.error(e, "profile_refresh_failed")   // no screenName — a ViewModel is not a screen
        }
    }
}
```

Report where the UI state flips to an error, so the event and what the user saw stay
in sync. Do not also report inside the repository — one failure, one event.

## `Flow`

```kotlin
repository.observeFeed()
    .catch { e ->
        Pulse.error(e, "feed_stream_failed")
        emit(emptyList())
    }
    .collect { items -> … }
```

`catch` only sees upstream failures; anything thrown inside `collect` propagates to
the collecting coroutine and needs its own `try`/`catch`. Never report inside the
collector body per emission — that is a hot path (Instrumentation Principle 3).

`stateIn` / `shareIn` swallow upstream errors into the fallback value, so put the
`catch` before them.

## Retrofit and callback APIs

Prefer the OkHttp interceptor in the skill body — it covers every call site at once.
Where a callback API is used directly, both branches need reporting:

```kotlin
call.enqueue(object : Callback<Feed> {
    override fun onResponse(call: Call<Feed>, response: Response<Feed>) {
        if (!response.isSuccessful) {
            Pulse.warn("feed_request_failed", attributes = mapOf("status" to "${response.code()}"))
        }
    }
    override fun onFailure(call: Call<Feed>, t: Throwable) {
        Pulse.error(t, "feed_request_failed")
    }
})
```

A suspending Retrofit call that returns `Response<T>` does not throw on a non-2xx —
check `isSuccessful` explicitly, as above.

## WorkManager and background jobs

```kotlin
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        val synced = sync()
        Pulse.info("sync_completed", attributes = mapOf(
            "item_count" to "$synced", "run_attempt" to "$runAttemptCount",
        ))
        Result.success()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Pulse.error(e, "sync_failed", attributes = mapOf("run_attempt" to "$runAttemptCount"))
        if (runAttemptCount < 3) Result.retry() else Result.failure()
    }
}
```

Include `runAttemptCount` so a retried job is distinguishable from a first failure.
`Result.failure()` returned without an event is invisible — WorkManager tells nobody.

Background work runs while the process may be about to die, so let
`flushOnBackground` do its job and do not call `shutdown()` from a worker.

## Room, DataStore, and other framework failures

Framework calls throw where it is easy to forget: `Room` migrations
(`IllegalStateException` on a missing migration), `DataStore` (`IOException` from
the `catch` operator on its `data` flow), `SharedPreferences` commits, file I/O,
`PackageManager.NameNotFoundException`. Each is a plain `try`/`catch` site.

Database corruption and migration failures deserve `error`; a missing optional
preference does not.

## Cancellation: the one thing not to report

`CancellationException` means a coroutine's scope went away — a screen closed, a
search query was superseded, a job was replaced. It is normal, it is frequent, and
reporting it drowns the issue list.

- It extends `Exception`, so narrowing the catch from `Throwable` does not exclude
  it. Every reporting catch on suspending code needs an explicit
  `catch (e: CancellationException) { throw e }` branch ahead of the general one.
- `Pulse.error` inside a `finally` block will fire on cancellation too — check first.

## What to skip

- Validation the UI already surfaces (`warn` at most).
- An optional capability that is legitimately absent (no camera, no biometrics).
- A cache miss or a first-launch "not found".
- Retry attempts before the last one.

Everything else gets an event. When unsure, use `warn` — queryable, but it does not
create an issue the way `error` does.

## Wrapping it up: one helper per app

Once the same attributes appear on every call, wrap them:

```kotlin
fun reportError(e: Throwable, message: String, screen: String? = null,
                attributes: Map<String, String?> = emptyMap()) {
    if (e is CancellationException) throw e
    Pulse.error(e, message, screenName = screen,
                attributes = attributes + ("build_channel" to BuildConfig.CHANNEL))
}
```

Keep the wrapper thin. It must not swallow, rate-limit or rewrite the message —
those are exactly the properties the issue tracker depends on.
