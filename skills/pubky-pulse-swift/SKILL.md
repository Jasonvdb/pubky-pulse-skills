---
name: pubky-pulse-swift
description: >-
  Adds the Pubky Pulse Swift SDK to an iOS, iPadOS, macOS or watchOS app. Covers Swift
  Package Manager setup, configuration, screen tracking, and the error capture the SDK does
  not do for you — there is no automatic crash capture, so every catch, Result and Task
  boundary reports itself. Also events, metrics, funnels, identity, feedback, questionnaires
  and privacy manifests. Use when adding analytics or error tracking to Apple app code. Not
  for Kotlin (see pubky-pulse-android) or for planning what to track first (see
  pubky-pulse-instrument).
license: MIT
compatibility: >-
  The code changes need no MCP server. The pubky-pulse MCP server is needed only to create
  the app, read its client key, and check that events arrive. Any harness that reads
  SKILL.md.
metadata:
  version: "0.1.0"
  product: pubky-pulse
  docs: https://pulse.pubky.org/docs
---

## What is Pubky Pulse

Pubky Pulse is a self-hosted, agent-first observability product: events, metrics,
funnels, issues, feedback and questionnaires for web, backend, iOS and Android apps.
Resources nest Team → Project → App — a project is one product, an app is one
platform build of it. Four SDKs send data in: web, Node, Swift and Android.
Agents work through the Pubky Pulse MCP server, which is the only agent interface,
and no MCP tool ingests data — only SDKs do. Two key types: `pulse_client_*` is
ingest-scoped, public, and ships inside the app; `pulse_agent_*` is for MCP only and
never belongs in a browser bundle, a `NEXT_PUBLIC_*` variable, or a committed file.
Read the `pubky-pulse://guide` resource for the full tool surface.

MCP tools are written here as `pubky-pulse:<tool>` — `pubky-pulse:whoami`, for
example. Claude Code exposes the same tool as `mcp__pubky-pulse__whoami`; other
harnesses use their own prefix.

**If the MCP server is not connected.** Call `pubky-pulse:whoami` first. If the tool
is unavailable, say Pubky Pulse is not connected yet and print this prompt for the
user to paste into their agent, with their own key and instance URL substituted:

    Add the Pubky Pulse MCP server to my global (user-level) agent config, so it
    loads in every project:

    - Name: pubky-pulse
    - Transport: remote streamable HTTP
    - URL: https://api.pulse.pubky.org/mcp
    - Header: Authorization: Bearer pulse_agent_YOUR_KEY_HERE

    Use whatever mechanism this harness supports — its own `mcp add` command if it
    has one, otherwise the user-level config file. Do not write it into the project
    or commit the key anywhere; it is a secret. Then reload the MCP servers and call
    the `whoami` tool to confirm the connection works.

In Claude Code that is one command:

    claude mcp add --transport http --scope user pubky-pulse https://api.pulse.pubky.org/mcp \
      --header "Authorization: Bearer pulse_agent_YOUR_KEY_HERE"

Then carry on with every step that only touches code, and finish with a
`Pending Pubky Pulse steps` list naming each project, app, metric and funnel that
still has to be created once the server is connected.

## Workflow

- [ ] Get the ingest endpoint and a `pulse_client_*` key for an `apple` app
- [ ] Add the package and confirm `import PubkyPulse` builds
- [ ] Configure once at launch, with `attributionEnabled: false`
- [ ] Add `.pulseScreen("Name")` to every screen
- [ ] Work the **Catch every error** checklist — this is where most of the value is
- [ ] Add outcome events, then metrics and funnel steps whose definitions exist server-side
- [ ] Build, then verify events arrive in development data mode

## Inputs

The app needs an ingest endpoint URL and a client key. If the app row does not exist
yet, create it with `pubky-pulse:create-app`: `platform: "apple"`, `bundle_id` set to
the app's bundle identifier (immutable afterwards), `name` as `<Project> iOS`
(or `macOS` / `watchOS` — the platform suffix is required). The response's
`client_secret` is the `pulse_client_*` key. One `apple` app covers the iOS, iPadOS,
macOS and watchOS builds of the same product; `environment` separates them.

The key is public and ships in the binary — it can only write events for its own app.
Keep it out of source control anyway by reading it from the build configuration
(an `.xcconfig` value surfaced through `Info.plist`) rather than pasting a literal.

## Install

Xcode: **File → Add Package Dependencies…**, enter
`https://github.com/Jasonvdb/pubky-pulse-swift.git`, set the rule to **Branch** `main`,
and add the `PubkyPulse` library to the app target.

`Package.swift` projects:

```swift
dependencies: [
    .package(url: "https://github.com/Jasonvdb/pubky-pulse-swift.git", branch: "main"),
],
targets: [
    .target(name: "YourApp", dependencies: [.product(name: "PubkyPulse", package: "pubky-pulse-swift")]),
]
```

Minimums: iOS 16, iPadOS 16, macOS 13, watchOS 10. Zero external dependencies.
A "No such module 'PubkyPulse'" editor error before the first real build is a
SourceKit artefact — build with Xcode or `xcodebuild` before believing it.

## Configure

Configure once, as early as possible — `App.init` or
`application(_:didFinishLaunchingWithOptions:)`. `_launch_ms` is measured from
process start to this call, so a late `configure` reports a false cold-start time
and drops every event emitted before it.

```swift
import PubkyPulse

@main
struct MyApp: App {
    init() {
        do {
            try Pulse.configure(
                endpoint: "https://ingest.pulse.pubky.org",
                apiKey: Bundle.main.object(forInfoDictionaryKey: "PULSE_CLIENT_KEY") as? String ?? "",
                attributionEnabled: false
            )
        } catch {
            // Analytics must never take the app down. Log and continue.
            print("Pulse configuration failed: \(error)")
        }
    }

    var body: some Scene { WindowGroup { RootView() } }
}
```

`configure` throws `PulseConfigurationError` (`.invalidEndpoint`, `.invalidApiKey`,
`.missingBundleId`). Never force-try it — a typo in the endpoint would then crash the
app on launch. `attributionEnabled: false` is deliberate: the server has no use for what that
flag collects, so leaving it on only spends battery and network on every launch.

The other parameters are all defaulted: `flushOnBackground: true`,
`compressionEnabled: true`, `networkTrackingEnabled: true`, `consoleLogging: true`.

## What the SDK already does

Do not re-implement any of these.

| Signal | How |
|---|---|
| `sdk:session_started` with `_launch_ms` | on `configure()` |
| `sdk:app_foregrounded` / `sdk:app_backgrounded` | lifecycle notifications |
| `sdk:screen_appeared` / `sdk:screen_disappeared` (+ `_duration_ms`) | `.pulseScreen(_:)` |
| `sdk:network_request` | swizzled `URLSession` **completion-handler** requests |
| Anonymous id (`pulse_anon_*`) | Keychain — survives reinstall |
| Device model, OS version, locale, `app_version`, `build_number`, `_connection` | every event |
| `is_dev` | `#if DEBUG` — a TestFlight build reports as production |
| Offline queue, batching, gzip, background flush | transport |

What it does **not** do, and you must:

- **No crash or uncaught-exception capture.** Swift runtime traps (force unwrap,
  array bounds, `fatalError`) kill the process before any handler could run, and
  there is no reliable flush from a dying process. Every error that reaches Pubky
  Pulse got there because your code called `Pulse.error`. If crash coverage matters
  to the product, run a dedicated crash reporter alongside this SDK.
- **Async/await network calls are not tracked.** The instrumentation swizzles
  `dataTask(with:completionHandler:)`, so `URLSession.data(for:)`, `data(from:)`,
  upload, download and delegate-driven tasks emit nothing. Modern code is mostly
  async/await, so treat automatic network tracking as a bonus on legacy call sites,
  not as coverage — report HTTP failures yourself.
- **Non-2xx responses are not errors to `URLSession`.** Even on a tracked call site,
  a 500 does not throw. Check the status code and report it.

## Screen tracking

```swift
struct CheckoutView: View {
    var body: some View {
        VStack { … }
            .pulseScreen("Checkout")
    }
}
```

One modifier on the outermost view of each distinct screen. PascalCase human names
(`Checkout`, `Order Detail`), consistent across the app. UIKit has no modifier —
call `Pulse.debug("sdk:screen_appeared", screenName: "Checkout")` from
`viewDidAppear` and the matching `sdk:screen_disappeared` from `viewDidDisappear`
with a `_duration_ms` attribute, so both UI stacks land in the same dashboard views.

Do not add a `Pulse.info("screen viewed")` on top — that is double counting.

## Catch every error

This checklist decides whether the issue tracker is useful. Walk the codebase and
confirm each line; anything left uninstrumented is invisible in production.

- [ ] Every `catch` block reports with the caught error object
- [ ] Every `Result` `.failure` / `case .failure(let error)` branch
- [ ] Every unstructured `Task { }` — an error thrown inside is swallowed silently
- [ ] Every SwiftUI `.task { }` and `.refreshable { }` body
- [ ] Every Combine `.sink(receiveCompletion:)` `.failure(let error)`
- [ ] Every `JSONDecoder.decode` failure (the `DecodingError` type is the grouping key)
- [ ] Every non-2xx HTTP response, plus every thrown transport error
- [ ] Every delegate error callback (`…didFailWithError:`)
- [ ] Every `try?` that silently discards a failure — either report it or justify it
- [ ] Every `guard else { return }` hiding a precondition failure worth knowing about

```swift
do {
    try await uploadPhoto(data)
} catch {
    // Pass the error object: the SDK extracts _error_type, the NSError
    // domain/code, the cause chain and the call stack, and _error_type is
    // what keeps a URLError and a DecodingError on separate issues.
    Pulse.error(error, "photo_upload_failed", screenName: "Gallery",
                attributes: ["size_kb": String(data.count / 1024), "retry_count": "\(attempt)"])
}
```

The second argument is the event message and therefore the **issue grouping key**:
keep it a fixed snake_case template (`photo_upload_failed`), never interpolate an id
or a URL into it, and put the variable parts in `attributes`. Omit it only when the
error's own description is already stable.

`Pulse.error` has two overloads — `error(_ message: String, …)` and
`error(_ error: Error, _ message: String? = nil, …)`. Prefer the error overload
wherever an error value exists; reserve the string form for precondition failures
where there is nothing to pass.

Read `references/error-capture-patterns.md` when a call site is not a plain `catch` —
it has the `Result`, `Task`, `.task`, Combine, decoding, async/await URLSession and
UIKit delegate snippets, plus the report-or-skip judgement calls.

## Events

```swift
Pulse.info("checkout_completed", screenName: "Checkout", attributes: [
    "order_id": order.id, "payment_method": "apple_pay",
    "amount_cents": "\(order.totalCents)", "item_count": "\(order.items.count)",
    "coupon_code": order.coupon,   // String? — nil keys are dropped for you
])
```

Levels are exactly `info`, `debug`, `warn`, `error`: `info` for outcomes worth
recording, `debug` for development-only detail (filtered out of production views),
`warn` for a recovered anomaly, `error` for a real failure.

`screenName` belongs only on events that genuinely happen on a screen. Omit it in
services, repositories, managers and background work — a fabricated screen name
pollutes screen analytics permanently.

Never put personal data in a message or attribute value: no tokens, passwords,
recovery phrases, card numbers, or text the user typed. Values are truncated, not
redacted.

## Instrumentation Principles

1. **Log outcomes, not steps.** Emit one rich event per outcome — the thing the app
   or service did (request handled, checkout completed, job finished) — not one per
   line of code. Intermediate diagnostics (cache lookups, fallbacks) go to `debug`.
2. **Pack attributes wide, not events deep.** One event with 15 attributes beats 15
   events with one each. Think through who (`user_id`, `plan_tier`), what
   (`order_id`, `feature_flag`), where (route, screen, region), how (`auth_method`,
   `retry_count`) and how much (`duration_ms`, `status_code`, `amount_cents`).
   High-cardinality attribute *values* are a feature — they let a chart drill down to
   one failing request. Event *frequency* is the thing to control.
3. **Aggregate hot paths.** Never log inside a loop, a queue drain, a render pass, a
   scroll or timer callback, or per retry attempt. Log one summary event with counts,
   totals and `duration_ms`, or wrap the whole operation in a lifecycle metric.
4. **Log, metric, or funnel — pick by the question.** A log event answers "show me the
   individual records when this went wrong". A lifecycle metric (`startOperation` →
   exactly one of `complete` / `fail` / `cancel`) answers "what is the p95 latency and
   success rate of this operation". A single-shot `recordMetric` answers "what is this
   value, trended". A funnel step answers "where do users drop out of this journey".
   One flow often warrants all four. When in doubt, write one event with more
   attributes rather than several events with fewer.

On Apple platforms rule 3 bites hardest in `CADisplayLink` callbacks, scroll-offset
observers, Combine publishers that fire per keystroke, and per-row loops in imports
or syncs — log the batch outcome with counts instead.

## Naming rules

| Thing | Rule | Example |
|---|---|---|
| Project | bare product name, no platform suffix | `Lofi` |
| App | `<Project> <Platform>` | `Lofi Web`, `Lofi Backend`, `Lofi iOS`, `Lofi Android` |
| Event message | snake_case, outcome-oriented, never interpolated | `checkout_completed` |
| Metric slug | kebab-case, created on the server first | `process-payment` |
| Funnel slug and step | kebab-case, created on the server first | `onboarding`, `onboarding-email` |
| Questionnaire slug | kebab-case, immutable after creation | `nps-q3` |
| Screen name | native: PascalCase human name; web: URL path, tracked automatically | `Checkout`, `/checkout` |
| Web `bundle_id` | a site identifier name, not a URL | `app.acme.com` |

Rule of thumb: hyphens mean the name must exist on the server first; underscores
mean a free-form event message. The message is the issue-grouping key, so keep it a
stable template and put the variable data in attributes. If the project already has
a naming convention, stay consistent with it.

## Identity

```swift
Pulse.setUser(user.id)                    // after login; claims the anonymous history
Pulse.setUserProperties(["plan": "premium", "cohort": "2026-q1"])
Pulse.clearUser()                         // on logout
Pulse.clearUser(newAnonymousId: true)     // shared device: start a fresh anonymous id
```

`setUser` is synchronous and safe on the sign-in path — it persists the id, switches
future events, and fires the server-side claim in the background. Never pass an
email or any other personal identifier as the user id; use the app's own opaque id.

## Metrics

Create the definition first with `pubky-pulse:create-metric` (kebab-case slug) —
events for an unknown slug are stored but roll up nowhere. Then wrap the operation
so that **exactly one** terminal call runs on every exit path:

```swift
let op = Pulse.startOperation("photo-upload", attributes: ["format": "heic"])
do {
    let result = try await upload(data)
    op.complete(attributes: ["size_kb": "\(result.bytes / 1024)"])
} catch is CancellationError {
    op.cancel()
} catch {
    op.fail(error: "\(type(of: error))")   // fail takes a String, not an Error
    Pulse.error(error, "photo_upload_failed")
}
```

`op.fail(error:)` takes a `String`, so pass a short stable classifier and report the
error object separately with `Pulse.error` when the failure deserves an issue.
`duration_ms` and `tracking_id` are added for you. A value with no duration uses
`Pulse.recordMetric("cold-start")` instead.

## Funnels

Create the funnel first with `pubky-pulse:create-funnel`, then emit one
`Pulse.step("<step-name>")` at each point a user actually progresses. Step names
match the funnel definition's `event_filter.step_name` verbatim — a mismatch is
silent, the step simply never converts.

```swift
Pulse.step("welcome-screen")
Pulse.step("create-account", attributes: ["method": "apple"])
Pulse.step("first-post")
```

Native apps always carry a user id (anonymous or real), so steps count without any
extra work.

## Linking to a backend

```swift
var request = URLRequest(url: apiURL)
if let sessionId = Pulse.sessionId {
    request.setValue(sessionId, forHTTPHeaderField: "X-Pulse-Session-Id")
}
```

The backend reads that header and scopes its own events to the same session, so one
session view shows both sides of the request. Add it once in the app's shared
request builder, not per call site.

## Feedback and questionnaires

The SDK ships `PulseFeedbackView` (free-text feedback) and
`.pulseQuestionnaire(slug:trigger:)` / `PulseQuestionnaireView` (server-authored
surveys), plus the programmatic `Pulse.sendFeedback` and questionnaire APIs.
Read `references/feedback-and-questionnaires.md` when adding either surface — it
covers presentation modes, triggers, string overrides, resume-from-draft, and the
trap that a questionnaire's `description` renders to end users.

## watchOS

A watch app configures the SDK exactly like iOS; delivery falls back through
WatchConnectivity and an on-disk queue. Read `references/watchos.md` when the target
includes a watch app — the iPhone host needs one line in its `WCSessionDelegate`.

## Privacy and submission

Read `references/privacy-app-store.md` when the app is heading for submission: it
lists the App Privacy categories to declare, the conditional ones (user id, feedback
contact fields), and what the bundled `PrivacyInfo.xcprivacy` already covers.

## Verify

1. Build and run on a simulator or device; exercise a screen, an event, and a
   deliberate error path.
2. `pubky-pulse:query-events` with `data_mode: "development"` and `since: "15m"` —
   DEBUG builds are development data, and the default production mode shows nothing.
3. Expect `sdk:session_started` first. If it is missing, the endpoint or key is wrong,
   or `configure` threw and was swallowed — check the console for the SDK's warning.
4. Errors: `query-events` with `level: "error"` shows them immediately;
   `pubky-pulse:list-issues` only after the hourly scan clusters them.
5. Metrics and funnels: `pubky-pulse:query-metric` / `pubky-pulse:query-funnel` in
   the same development data mode.

## Gotchas

- **No crash capture.** Nothing is reported unless code calls `Pulse.error`.
- **Automatic network tracking misses async/await.** It swizzles the
  completion-handler `dataTask` overloads only.
- **A TestFlight build is production data.** `is_dev` follows `#if DEBUG`, so a
  release-configuration TestFlight build lands beside App Store users.
- **`op.fail` takes a `String` here**, unlike the web SDK's error object.
- **Metric and funnel slugs must exist server-side first.** Invalid characters are
  auto-corrected to kebab-case with a console warning, so `Photo Upload` silently
  becomes `photo-upload` — create the definition and use its slug verbatim.
- **`app_version` drives regression detection.** It comes from
  `CFBundleShortVersionString`; keep it semver and monotonic. Resolving an issue
  requires a real version, and a git SHA there breaks the comparison forever.
- **Calls before `configure` are dropped** with a single console warning.
- **Re-calling `configure` starts a new session** and shuts the old transport down.
- **Reserved names are the SDK's.** Do not emit `metric:*`, `step:*` or `sdk:*`
  messages by hand (the UIKit screen pattern above is the one exception), and do not
  invent `_`-prefixed attribute keys — the server treats them as SDK-owned.
- **Attribute values are truncated at ~200 characters** and messages at 2000. Long
  payloads belong in an attachment, and even then: never attach logs, stack traces,
  screenshots, or anything reconstructible from the event itself.
- **`screenName` from a service layer is worse than none.**
- **Feedback is not offline-queued.** `sendFeedback` throws on failure so the UI can
  offer a retry; events, by contrast, queue to disk.

## References

- `references/error-capture-patterns.md` — read when instrumenting anything other
  than a plain `catch`: `Result`, `Task`, `.task`, Combine, decoding, async/await
  URLSession, UIKit delegates.
- `references/feedback-and-questionnaires.md` — read when adding the feedback view
  or an in-app questionnaire.
- `references/watchos.md` — read when the app has a watchOS target.
- `references/privacy-app-store.md` — read when preparing a submission or answering
  privacy questions.
- `references/api-reference.md` — read when checking an exact signature, parameter
  default, or error type.
