---
name: pubky-pulse-android
description: >-
  Adds the Pubky Pulse Android SDK to a Kotlin or Compose app. Covers the Gradle dependency,
  Application.onCreate configuration, screens, and the error capture the SDK does not do — no
  automatic crash or network capture, so coroutine handlers, runCatching and an OkHttp
  interceptor carry it. Also events, metrics, funnels, identity, feedback, questionnaires and
  Play data safety. Use when adding analytics or error tracking to Android code. Not for Swift
  (see pubky-pulse-swift), crashes already collected (see pubky-pulse-investigate-issues), or
  planning what to track (see pubky-pulse-instrument).
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

- [ ] Get the ingest endpoint and a `pulse_client_*` key for an `android` app
- [ ] Add the Gradle dependency and sync
- [ ] Configure in `Application.onCreate()`
- [ ] Track screens — `Modifier.pulseScreen` on Compose, a lifecycle callback otherwise
- [ ] Work the **Catch every error** checklist, including the OkHttp interceptor
- [ ] Add outcome events, then metrics and funnel steps whose definitions exist server-side
- [ ] Assemble a debug build, then verify events arrive in development data mode

## Inputs

The app needs an ingest endpoint URL and a client key. If the app row does not exist
yet, create it with `pubky-pulse:create-app`: `platform: "android"`, `bundle_id` set
to the release `applicationId` (immutable afterwards), `name` as `<Project> Android`
— the platform suffix is required. The response's `client_secret` is the
`pulse_client_*` key.

The key is public and ships in the APK; it can only write events for its own app.
Still keep it out of source control — put it in `local.properties` or a CI secret and
surface it through `buildConfigField`, then read `BuildConfig.PULSE_CLIENT_KEY`.

## Install

Two artifacts. The core module is always needed; the Compose module only for the
drop-in UI and `Modifier.pulseScreen`.

Version catalog (`gradle/libs.versions.toml`) — preferred when the project has one:

```toml
[versions]
pulse = "0.1.0"

[libraries]
pulse-android = { module = "org.pubky.pulse:pulse-android", version.ref = "pulse" }
pulse-android-compose = { module = "org.pubky.pulse:pulse-android-compose", version.ref = "pulse" }
```

```kotlin
dependencies {
    implementation(libs.pulse.android)
    implementation(libs.pulse.android.compose)   // only for the Compose UI + pulseScreen
}
```

Direct coordinates, when the project declares dependencies inline:

```kotlin
dependencies {
    implementation("org.pubky.pulse:pulse-android:0.1.0")
    implementation("org.pubky.pulse:pulse-android-compose:0.1.0")
}
```

Requires Android 7.0 (API 24), Kotlin 2.0+, AGP 8.7+, JDK 17+, and `mavenCentral()`
in the repository list. The core module's only runtime dependency is
`kotlinx-coroutines`. It merges `INTERNET` and `ACCESS_NETWORK_STATE` into the
manifest — both install-time, neither prompts.

Verify with `./gradlew :app:assembleDebug`, or resolve only:
`./gradlew :app:dependencies --configuration debugRuntimeClasspath | grep pulse-android`.

## Configure

Configure in `Application.onCreate()`, before anything else runs. `_launch_ms` is
measured from process start to this call, and events emitted earlier are dropped.

```kotlin
import android.app.Application
import org.pubky.pulse.android.Pulse
import org.pubky.pulse.android.PulseConfigurationError

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            Pulse.configure(
                context = this,
                endpoint = "https://ingest.pulse.pubky.org",
                apiKey = BuildConfig.PULSE_CLIENT_KEY,
            )
        } catch (e: PulseConfigurationError) {
            // Analytics must never take the app down.
            android.util.Log.e("PubkyPulse", "configuration failed", e)
        }
    }
}
```

Register it: `<application android:name=".MyApp" …>`. `PulseConfigurationError` is a
sealed hierarchy — `InvalidEndpoint`, `InvalidApiKey`, `MissingBundleId`.

Other parameters, all defaulted: `flushOnBackground = true`,
`compressionEnabled = true`, `networkTrackingEnabled = true`, `consoleLogging = true`.
Set `consoleLogging = false` if Logcat noise is a problem.

## What the SDK already does

| Signal | How |
|---|---|
| `sdk:session_started` with `_launch_ms` | on `configure()` |
| `sdk:app_foregrounded` / `sdk:app_backgrounded` | process lifecycle observer |
| `sdk:screen_appeared` / `sdk:screen_disappeared` (+ `_duration_ms`) | `Modifier.pulseScreen` |
| Anonymous id (`pulse_anon_*`) | private `SharedPreferences` |
| Device model, OS version, locale, app version, connection type | every event |
| `is_dev` | the app's `FLAG_DEBUGGABLE` — release builds report as production |
| Offline queue on disk, batching, gzip, background flush | transport |
| `source_module` | resolved from the call stack, so log calls carry file, function and line |

What it does **not** do, and you must:

- **No crash or uncaught-exception capture.** Nothing reaches Pubky Pulse unless code
  calls `Pulse.error`. A default uncaught-exception handler helps a little and is
  covered below, but it is best-effort — it is not a crash reporter.
- **No HTTP instrumentation.** `networkTrackingEnabled` is reserved and does nothing
  today; there is no OkHttp or `HttpURLConnection` hook. Add the interceptor below.
- **No screen tracking outside Compose.** `Modifier.pulseScreen` lives in the Compose
  artifact and is the only screen API; View- and Fragment-based screens need the
  lifecycle-callback pattern in `references/screen-tracking.md`.

## Screen tracking

```kotlin
import org.pubky.pulse.android.compose.pulseScreen

@Composable
fun CheckoutScreen() {
    Column(modifier = Modifier.pulseScreen("Checkout")) { … }
}
```

One modifier per distinct screen, on the outermost composable — the root `Column`,
`Scaffold` content, `LazyColumn` or `Box`. PascalCase human names (`Checkout`,
`Order Detail`), consistent across the app. Do not add a `Pulse.info("screen viewed")`
alongside it.

Read `references/screen-tracking.md` when the app has Activities or Fragments rather
than composables, or a mixed stack — it has the `ActivityLifecycleCallbacks` and
Fragment variants that emit the same pair of events.

## Catch every error

This checklist decides whether the issue tracker is useful. Nothing is automatic.

- [ ] Every `try`/`catch` reports with the caught `Throwable`
- [ ] Every `runCatching { }.onFailure { }` branch
- [ ] Every root `CoroutineScope` has a `CoroutineExceptionHandler`
- [ ] Every `viewModelScope.launch` body that can throw
- [ ] Every `Flow.catch { }` operator
- [ ] Every `Result.failure` / sealed-result error branch in the repository layer
- [ ] Every `WorkManager` worker's failure path
- [ ] Every OkHttp or Retrofit failure — non-2xx responses and `IOException`
- [ ] Every `enqueue`-style callback's failure branch
- [ ] A default uncaught-exception handler as a backstop

```kotlin
try {
    uploadPhoto(bytes)
} catch (e: CancellationException) {
    throw e                    // the caller went away; not a failure
} catch (e: Exception) {
    // Pass the Throwable: the SDK extracts _error_type (the class name), the JVM
    // stack trace and the cause chain. _error_type is what keeps an IOException
    // and a JSONException with identical wording on separate issues.
    Pulse.error(e, "photo_upload_failed", screenName = "Gallery", attributes = mapOf(
        "size_kb" to "${bytes.size / 1024}", "retry_count" to "$attempt",
    ))
}
```

The `message` argument is the event message and therefore the **issue grouping key**:
keep it a fixed snake_case template, never interpolate an id or URL into it, and put
the variable parts in `attributes`.

Catch `Exception` rather than `Throwable`, and let `CancellationException` through:
it extends `Exception`, so a catch that reports and continues silently breaks
structured concurrency. Rethrow it in a branch ahead of the general one — coroutine
cancellation is ordinary navigation, not a defect worth an issue.

### OkHttp interceptor

Because nothing instruments HTTP, one interceptor covers every request and doubles as
the place to forward the session header:

```kotlin
class PulseInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val builder = chain.request().newBuilder()
        Pulse.sessionId?.let { builder.addHeader("X-Pulse-Session-Id", it) }
        val request = builder.build()
        val startedAt = SystemClock.uptimeMillis()
        try {
            val response = chain.proceed(request)
            if (!response.isSuccessful) {
                Pulse.warn("http_request_failed", attributes = mapOf(
                    "method" to request.method,
                    "path" to request.url.encodedPath,      // path only — no query string
                    "status" to "${response.code}",
                    "duration_ms" to "${SystemClock.uptimeMillis() - startedAt}",
                ))
            }
            return response
        } catch (e: IOException) {
            Pulse.error(e, "http_request_failed", attributes = mapOf(
                "method" to request.method,
                "path" to request.url.encodedPath,
                "duration_ms" to "${SystemClock.uptimeMillis() - startedAt}",
            ))
            throw e
        }
    }
}
```

Add it as an application interceptor (`OkHttpClient.Builder().addInterceptor(...)`)
so it sees the final outcome once, not once per redirect or retry. Send only the
path, never the query string or body — those carry personal data. The session header
belongs only on requests to your own backend; if the client also calls third parties,
add the header in a client scoped to your API instead.

### Uncaught-exception handler

Worth installing, with clear limits. `Pulse.error` hands the event to a background
coroutine and there is no synchronous flush, so delivery from a dying process is
best-effort: the bounded `runBlocking` below gives the event a chance to reach the
server, and anything that misses the window dies with the process. It cannot see
native crashes or "application not responding" kills at all. Per-catch reporting
stays the primary path; this only catches what nothing else did.

```kotlin
val previous = Thread.getDefaultUncaughtExceptionHandler()
Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
    try {
        Pulse.error(throwable, "uncaught_exception", attributes = mapOf("thread" to thread.name))
        runBlocking { withTimeoutOrNull(2_000) { Pulse.shutdown() } }
    } catch (_: Throwable) {
        // Never let reporting mask the original crash.
    }
    previous?.uncaughtException(thread, throwable)   // keep the platform behaviour
}
```

Install it at the end of `Application.onCreate()`, after `configure`. Always delegate
to the previous handler — dropping it suppresses the system's own crash handling and
any other reporter in the app.

Read `references/error-capture-patterns.md` when the call site is a coroutine scope,
a `Flow`, a ViewModel, `WorkManager`, or a callback API — it has those snippets plus
the report-or-skip judgement calls.

## Events

```kotlin
Pulse.info("checkout_completed", screenName = "Checkout", attributes = mapOf(
    "order_id" to order.id,
    "payment_method" to "google_pay",
    "amount_cents" to "${order.totalCents}",
    "coupon_code" to order.coupon,     // String? — null entries are dropped for you
))
```

Levels are exactly `info`, `debug`, `warn`, `error`: `info` for outcomes worth
recording, `debug` for development-only detail (filtered out of production views),
`warn` for a recovered anomaly, `error` for a real failure.

`screenName` belongs only on events that genuinely happen on a screen. Omit it in
repositories, use cases, services, background work and ViewModels detached from a
screen — a fabricated screen name pollutes screen analytics permanently.

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

On Android rule 3 bites hardest in `Flow` collectors, `RecyclerView` binds,
recomposition, sensor and location callbacks, and per-row loops in syncs — log the
batch outcome with counts instead.

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

Identity is opt-in. Events carry an anonymous id (`pulse_anon_*`) per device until `setUser`
runs, so unique-user counts and funnels already work without it. Write `setUser` only when the
developer has explicitly agreed to link analytics to real user ids — the answer is what the
Play data safety form declares. Use the answer the `pubky-pulse-instrument` step-4 gate
supplies, and when none was supplied, this skill having been invoked directly for the Android
surface, put the same question to the developer yourself — as selectable options in your
harness's structured question tool (`AskUserQuestion` in Claude Code, plain text if it has
none), staying anonymous recommended first. With no answer, write it commented out at the
callsite with a one-line `// TODO(pulse): ...` marker and nothing else. `clearUser` is never
gated: it is the call that removes a link rather than creating one, and the identifier it
clears otherwise persists across launches.

```kotlin
Pulse.setUser(user.id)                       // after login; claims the anonymous history
Pulse.setUserProperties(mapOf("plan" to "premium"))
Pulse.clearUser()                            // on logout
Pulse.clearUser(newAnonymousId = true)       // shared device: mint a fresh anonymous id
```

`setUser` is synchronous and safe before `configure`; the id is stashed and applied when
configuration runs. Never pass an email or another personal identifier — use an opaque id.

## Metrics

Create the definition first with `pubky-pulse:create-metric` (kebab-case slug) —
events for an unknown slug are stored but roll up nowhere. Then make sure **exactly
one** terminal call runs on every exit path:

```kotlin
val op = Pulse.startOperation("photo-upload", attributes = mapOf("format" to "heic"))
try {
    val result = upload(bytes)
    op.complete(attributes = mapOf("size_kb" to "${result.bytes / 1024}"))
} catch (e: CancellationException) {
    op.cancel()
    throw e                                    // never swallow cancellation
} catch (e: Exception) {
    op.fail(error = e::class.java.simpleName)   // fail takes a String, not a Throwable
    Pulse.error(e, "photo_upload_failed")
}
```

`duration_ms` and `tracking_id` are added for you. A value with no duration uses
`Pulse.recordMetric("cold-start")` instead.

## Funnels

Create the funnel first with `pubky-pulse:create-funnel`, then emit one
`Pulse.step("<step-name>")` at each point a user actually progresses. Step names must
match the funnel definition's `event_filter.step_name` verbatim — a mismatch is
silent, the step simply never converts.

```kotlin
Pulse.step("welcome-screen")
Pulse.step("create-account", attributes = mapOf("method" to "google"))
Pulse.step("first-post")
```

Android apps always carry a user id (anonymous or real), so steps count without extra
work.

## Feedback and questionnaires

The Compose artifact ships `PulseFeedbackView` and `PulseQuestionnaireGate` /
`PulseQuestionnaireView`; the core module has the suspending `Pulse.sendFeedback` and
questionnaire APIs for a hand-built UI. Read
`references/feedback-and-questionnaires.md` when adding either surface — it covers
placement, triggers, resume-from-draft, and the trap that a questionnaire's
`description` renders to end users.

## Play data safety

Read `references/privacy-play-data-safety.md` when completing the store's Data safety
form or answering a privacy question: it maps what the SDK sends onto the form's data
types and gives the security and deletion answers.

## Verify

1. Install a debug build and exercise a screen, an event, and a deliberate error path.
2. `pubky-pulse:query-events` with `data_mode: "development"` and `since: "15m"` —
   debuggable builds are development data, and the default production mode shows
   nothing.
3. Expect `sdk:session_started` first. If it is missing, the endpoint or key is wrong,
   or `configure` threw and was caught — check Logcat for the SDK's warning.
4. Errors: `query-events` with `level: "error"` shows them immediately;
   `pubky-pulse:list-issues` only after the hourly scan clusters them.
5. Metrics and funnels: `pubky-pulse:query-metric` / `pubky-pulse:query-funnel` in the
   same development data mode.

## Gotchas

- **No crash capture and no HTTP capture.** `networkTrackingEnabled` is a reserved
  no-op — the interceptor above is the coverage.
- **`Modifier.pulseScreen` is Compose-only** and lives in the separate
  `pulse-android-compose` artifact.
- **`shutdown()` is a suspend function**, and there is no synchronous flush. Ordinary
  lifecycles are covered by `flushOnBackground`.
- **`is_dev` follows `FLAG_DEBUGGABLE`.** An internal-testing release build is
  production data.
- **`op.fail` takes a `String`**, not a `Throwable` — report the throwable separately.
- **Metric and funnel slugs must exist server-side first.** Invalid characters are
  auto-corrected to kebab-case with a Logcat warning, so `Photo Upload` silently
  becomes `photo-upload` — create the definition and use its slug verbatim.
- **`app_version` drives regression detection.** It comes from the manifest's
  `versionName`; keep it semver and monotonic. Resolving an issue requires a real
  version, and a git SHA there breaks the comparison forever.
- **`CancellationException` is an `Exception`**, so any catch that reports and
  continues swallows cancellation and breaks structured concurrency — rethrow it
  first, and never report it as an error.
- **Calls before `configure` are dropped** with a single Logcat warning —
  `setUser` and `clearUser` are the exceptions, they are stashed and applied later.
- **Re-calling `configure` starts a new session** and replaces the transport.
- **Reserved names are the SDK's.** Do not emit `metric:*` or `step:*` messages by
  hand, keep `sdk:*` to the screen-tracking pattern in the reference, and do not
  invent `_`-prefixed attribute keys — the server treats them as SDK-owned.
- **Attribute values are truncated at ~200 characters** and messages at 2000. Long
  payloads belong in an attachment, and even then: never attach logs, stack traces,
  screenshots, or anything reconstructible from the event itself.
- **Feedback is not offline-queued.** `sendFeedback` throws so the UI can offer a
  retry; events, by contrast, queue to disk.
- **R8 obfuscates class names**, so `_error_type` and stack traces from release
  builds only stay readable if the mapping file is kept for that version.

## References

- `references/error-capture-patterns.md` — read when instrumenting coroutine scopes,
  `Flow`, ViewModels, `WorkManager`, Retrofit callbacks, or `runCatching`.
- `references/screen-tracking.md` — read when the app uses Activities or Fragments
  instead of, or alongside, Compose.
- `references/feedback-and-questionnaires.md` — read when adding the feedback view or
  an in-app questionnaire.
- `references/privacy-play-data-safety.md` — read when completing the store's Data
  safety form.
- `references/api-reference.md` — read when checking an exact signature, parameter
  default, or error type.
