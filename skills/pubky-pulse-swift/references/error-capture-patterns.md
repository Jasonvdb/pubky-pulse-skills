## Contents

- Why every pattern here exists
- Plain `catch`
- `Result` and completion handlers
- Unstructured `Task` and SwiftUI `.task` / `.refreshable`
- `async let` and `TaskGroup`
- Combine
- Decoding failures
- URLSession with async/await
- UIKit and delegate callbacks
- `try?`, `guard`, and the sites worth skipping
- Actors, `deinit`, and other places errors vanish
- Wrapping it up: one helper per app

## Why every pattern here exists

The Swift SDK captures no crashes and no uncaught exceptions. An error appears in
Pubky Pulse only because code called `Pulse.error`. Swift also has an unusual number
of places where a failure is *legal to ignore* — `try?`, an unstructured `Task`, a
Combine completion, a delegate callback — so a codebase can look thoroughly
error-handled and still report nothing.

Two rules apply to every snippet below:

1. **Pass the error object.** `Pulse.error(error, "…")` extracts `_error_type`, the
   `NSError` domain and code, the cause chain and the call stack. `_error_type` is
   the issue fingerprint's discriminator, which is what keeps a `URLError` and a
   `DecodingError` with identical wording on separate issues.
2. **Keep the message a fixed template.** The message is the grouping key. Variable
   data — ids, URLs, counts — goes in `attributes`, never interpolated into the
   message, or every occurrence becomes its own issue.

## Plain `catch`

```swift
do {
    let order = try await api.submit(cart)
    Pulse.info("checkout_completed", screenName: "Checkout",
               attributes: ["order_id": order.id, "amount_cents": "\(order.totalCents)"])
} catch {
    Pulse.error(error, "checkout_failed", screenName: "Checkout",
                attributes: ["item_count": "\(cart.items.count)", "payment_method": method.rawValue])
}
```

Report once, at the layer that decides what the failure means. A retry loop reports
the final outcome with a `retry_count` attribute, not each attempt.

## `Result` and completion handlers

```swift
service.load { result in
    switch result {
    case .success(let feed):
        Pulse.info("feed_loaded", attributes: ["item_count": "\(feed.count)"])
    case .failure(let error):
        Pulse.error(error, "feed_load_failed", attributes: ["source": "remote"])
    }
}
```

`try result.get()` inside a `do`/`catch` works equally well. What is not acceptable
is `if case .success = result` with no `else` — that is a silent failure path.

## Unstructured `Task` and SwiftUI `.task` / `.refreshable`

An error thrown inside `Task { }` goes nowhere: the task's result is discarded unless
someone awaits its `value`. Wrap the body.

```swift
Task {
    do {
        try await sync()
    } catch {
        Pulse.error(error, "background_sync_failed")
    }
}
```

```swift
.task {
    do {
        items = try await repository.fetch()
    } catch is CancellationError {
        // The view went away — not a failure, do not report it.
    } catch {
        Pulse.error(error, "items_fetch_failed", screenName: "Feed")
    }
}
.refreshable {
    do { try await repository.refresh() }
    catch { Pulse.error(error, "feed_refresh_failed", screenName: "Feed") }
}
```

`CancellationError` is the one error class worth filtering out everywhere: SwiftUI
cancels `.task` on every disappearance, and reporting it would drown the issue list
in noise from ordinary navigation.

## `async let` and `TaskGroup`

`async let` rethrows at the `await`, so the surrounding `do`/`catch` covers it. A
`TaskGroup` does not: a child's error surfaces only when the group is awaited with
`try`, and `addTask` bodies that catch internally report nothing.

```swift
try await withThrowingTaskGroup(of: Void.self) { group in
    for id in ids { group.addTask { try await self.refresh(id) } }
    do {
        try await group.waitForAll()
    } catch {
        Pulse.error(error, "batch_refresh_failed", attributes: ["batch_size": "\(ids.count)"])
        throw error
    }
}
```

One event for the batch, with counts — not one per child (Instrumentation Principle 3).

## Combine

```swift
publisher
    .sink(receiveCompletion: { completion in
        if case .failure(let error) = completion {
            Pulse.error(error, "profile_stream_failed", attributes: ["stage": "decode"])
        }
    }, receiveValue: { profile in … })
    .store(in: &cancellables)
```

`assign(to:on:)` and `sink(receiveValue:)` require a `Never` failure type, so the
error was already swallowed upstream — usually by `replaceError(with:)` or
`catch { Just(…) }`. Report inside that operator instead:

```swift
.catch { error -> Just<[Item]> in
    Pulse.error(error, "items_stream_failed")
    return Just([])
}
```

## Decoding failures

```swift
do {
    return try JSONDecoder().decode(Profile.self, from: data)
} catch {
    // DecodingError carries the coding path; the SDK records the type and the
    // localized description. Add the shape, never the payload.
    Pulse.error(error, "profile_decode_failed",
                attributes: ["byte_count": "\(data.count)", "endpoint": "/v1/profile"])
    throw error
}
```

Never attach the raw response body — it usually contains personal data, and the
event caps truncate rather than redact.

## URLSession with async/await

Automatic network tracking only sees the completion-handler `dataTask` overloads, so
async/await requests report nothing at all. Give the app one wrapper and route every
request through it:

```swift
func send(_ request: URLRequest) async throws -> Data {
    let started = ContinuousClock.now
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let durationMs = Int((ContinuousClock.now - started).components.seconds * 1000)
        if !(200..<300).contains(status) {
            Pulse.warn("http_request_failed", attributes: [
                "method": request.httpMethod ?? "GET",
                "path": request.url?.path ?? "",     // path only — no query string
                "status": "\(status)",
                "duration_ms": "\(durationMs)",
            ])
        }
        return data
    } catch {
        Pulse.error(error, "http_request_failed", attributes: [
            "method": request.httpMethod ?? "GET",
            "path": request.url?.path ?? "",
        ])
        throw error
    }
}
```

Keep the path templated (`/users/<id>`, not `/users/8123`) if the app builds paths
by interpolation — the attribute value is fine either way, but a templated path
keeps dashboards readable.

## UIKit and delegate callbacks

```swift
func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error { Pulse.error(error, "upload_task_failed") }
}

func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    Pulse.error(error, "webview_navigation_failed", screenName: "Article")
}
```

Every framework delegate with an `Error` parameter is a reporting site: `CLLocation`,
`AVFoundation`, `StoreKit`, `WCSession`, `NSPersistentContainer` load handlers.

## `try?`, `guard`, and the sites worth skipping

`try?` is where errors go to die. Convert it, or state why not:

```swift
// Before
let cached = try? decoder.decode(Feed.self, from: cachedData)

// After
let cached: Feed?
do { cached = try decoder.decode(Feed.self, from: cachedData) }
catch { Pulse.warn("cache_decode_failed", attributes: ["error_kind": "\(type(of: error))"]); cached = nil }
```

That one is `warn`, not `error`: a stale cache is recoverable. Match the level to
the consequence.

Skip reporting when the failure is an expected outcome rather than a defect:

- A `guard` that rejects invalid user input the UI already reports (`warn` at most).
- `CancellationError` from navigating away.
- Keychain "item not found" on a first launch.
- An optional feature that is legitimately absent (no camera on this device).

Everything else gets an event. When unsure, use `warn` — it is queryable but does
not create an issue the way `error` does.

## Actors, `deinit`, and other places errors vanish

- **Actor-isolated work started with `Task { }`** has the same swallowing problem as
  any unstructured task.
- **`deinit`** cannot be `async` and runs at unpredictable times; do not put
  reporting there.
- **`@MainActor` hops** do not lose errors, but a `Task { @MainActor in … }` used
  purely to update UI still needs the `do`/`catch`.
- **`NotificationCenter` observers and target/action selectors** are ordinary
  synchronous code — errors thrown inside `do` blocks there are easy to leave
  uncaught during a refactor.

## Wrapping it up: one helper per app

Once the same three attributes appear on every call, wrap them:

```swift
extension Pulse {
    static func report(_ error: Error, _ message: String, screen: String? = nil,
                       _ attributes: [String: String?] = [:]) {
        var attrs = attributes
        attrs["build_channel"] = AppEnvironment.channel   // whatever the app already knows
        Pulse.error(error, message, screenName: screen, attributes: attrs)
    }
}
```

Keep the wrapper thin. It must not swallow, rate-limit or rewrite the message —
those are the properties the issue tracker depends on.
