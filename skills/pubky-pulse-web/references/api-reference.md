## Contents

- Configuration options
- Exception capture and filtering
- Logging
- Screens
- Metrics and operations
- Funnels
- Identity and user properties
- Feedback and questionnaires
- Lifecycle
- Read-only properties
- Events the SDK emits by itself
- Reserved attribute keys
- Delivery behaviour

## Configuration options

These APIs require Web SDK 0.6.0 or newer. Prefer `Pulse.init(options)` for app startup:

```ts
Pulse.init(options: PulseInitOptions): PulseInitResult
// status: "enabled" | "disabled" | "error"
// reason: "initialized" | "unchanged" | "configuration-ignored" | "disabled" |
//         "missing-key" | "ssr" | "invalid-configuration" | "initialization-failed"
```

`apiKey` may be absent/null/blank to disable; `enabled: false` also disables. Disabled
initialization installs no collectors and sends nothing; SSR is a no-op. First successful
configuration wins. Equivalent options return `unchanged` (callback identity matters), changed
valid options return `configuration-ignored`, and invalid reinitialization preserves the
running client. Diagnostics expose no user values. `Pulse.configure(configuration)` remains
strict: its key is required, invalid values throw even during SSR, and valid calls replace
an existing configuration.

| Option | Type | Default | What it does |
|---|---|---|---|
| `endpoint` | `string` | `https://ingest.pubkypulse.com` | Pulse server URL; explicitly set for self-hosting |
| `apiKey` | `string \| null` | disabled when absent | client key; a supplied nonblank key must start with `pulse_client_` |
| `enabled` | `boolean` | `true` | `init` only; false disables and discards pending memory |
| `bundleId` | `string` | unset | optional legacy identifier; client key identifies the web app |
| `appVersion` | `string` | unset | reported on every event; must increase between releases |
| `isDev` | `boolean` | true on `localhost`, `127.0.0.1`, `file:` | marks events as development traffic |
| `debug` | `boolean` | `false` | print the SDK's own diagnostics |
| `consoleLogging` | `boolean` | `true` | mirror logged events to the console |
| `compressionEnabled` | `boolean` | `true` | gzip bodies where `CompressionStream` exists |
| `captureUnhandled` | `boolean` | `true` | listen for `error` and `unhandledrejection` |
| `trackPageViews` | `boolean` | `true` | emit screen events for History API navigations |
| `screenNameForPath` | `(pathname: string) => string` | raw pathname | map automatic screens to app-owned safe labels |
| `ignoreErrors` | `(string \| RegExp)[]` | `[]` | filter error-level events before hooks/output |
| `beforeSend` | `(event: LogEvent, hint: PulseEventHint) => LogEvent \| null` | unset | synchronous transform/drop before output and buffering |
| `networkTracking` | `boolean \| { urlMode?: "path" \| "origin" }` | `false` | emit `sdk:network_request` per `fetch` call |
| `propagateSessionTo` | `string[]` | `[]` | URL prefixes that receive `X-Pulse-Session-Id` |
| `flushIntervalMs` | `number` | `5000` | milliseconds between automatic flushes |
| `flushThreshold` | `number` | `20` | buffered events that trigger an immediate flush |
| `maxBufferSize` | `number` | `10000` | buffered events kept before the oldest are dropped |
| `sessionTimeoutMs` | `number` | `1800000` | idle time after which a new session starts |
| `supportedLanguages` | `string[]` | not sent | the locales the app ships; written through to the app record |

Every numeric option must be a positive integer and `flushThreshold` must not exceed
`maxBufferSize`. `supportedLanguages` overwrites what the server holds for the app, so set
it only to the locales actually shipped, or leave it out.

## Exception capture and filtering

```ts
Pulse.captureException(error: unknown, options?: {
  message?: string;
  attributes?: Record<string, unknown>;
}): void
```

Pass the original thrown value; arbitrary exception properties are not automatically copied.
Capture extracts type, stack and up to five causes. It is quiet before setup, while disabled
and during SSR. The same `Error` object is attempted once per client lifetime, even if a
filter or hook drops it. Different objects and repeated primitives remain reportable.

`ignoreErrors` strings match substrings of the complete message and `Type: message`;
regexes test both without modifying their caller's `lastIndex`. This runs before
`beforeSend`, truncation, console, buffering, persistence and attachment scheduling.
It applies to error-level events, including logger, metric and network errors.

`beforeSend` receives the enriched event and complete strings. Return a valid event or
`null`; exceptions, invalid results and async callbacks drop silently. Do not log from the
hook. `hint.originalException` contains the original thrown value for captures, including
automatic errors; other events receive an empty hint. Hints are transient: never copy the
object wholesale into the event. Put redaction, an explicit metadata allowlist and expected
failure policy in one app-owned module. For example, adapt the app's existing helpers:

```ts
Pulse.init({
  endpoint: PULSE_ENDPOINT,
  apiKey: PULSE_KEY,
  ignoreErrors: IGNORED_BROWSER_ERRORS,
  beforeSend(event, hint) {
    if (shouldIgnoreAppError(hint.originalException)) return null;
    event.custom_attributes = {
      ...event.custom_attributes,
      ...allowlistedErrorAttributes(hint.originalException),
    };
    return redactEvent(event);
  },
});
```

The helpers and constants above are app-owned, not SDK exports. The hook runs once at
capture, including startup lifecycle events. Retries, old offline events and attachment
bytes are not reprocessed. Install policy on the initial `init` call.

## Logging

```ts
Pulse.info(message: string, attributes?, options?): void
Pulse.debug(message: string, attributes?, options?): void
Pulse.warn(message: string, attributes?, options?): void
Pulse.error(message: string, attributes?, options?): void
Pulse.error(error: unknown, message?: string, attributes?, options?): void
```

`attributes` is `Record<string, unknown>`; values are stringified and capped at 200
characters, and `undefined` / `null` entries are dropped. `options` is
`{ screenName?: string; attachments?: PulseAttachment[] }`.

The Error overload is selected only when the first argument is **not** a string. It
extracts `_error_type`, `_error_stack` and up to five levels of `cause`; those SDK keys win
over caller keys of the same name so fingerprinting stays stable.

## Screens

```ts
Pulse.trackScreen(name: string): void
createScreenNameMapper(templates: readonly string[], options?: {
  fallback?: string;
}): (pathname: string) => string
```

Sets the current screen and the default `screen_name` for later events. Repeating the
current name is a no-op. Manual names bypass `screenNameForPath`.

Pass `createScreenNameMapper`'s result as `screenNameForPath`. The helper emits only supplied
template text or a fallback (default `/unknown`). Whole-segment `[name]` matches one segment;
static routes take precedence. Catch-all, optional and partial-segment syntax are unsupported;
invalid or equally specific overlapping templates throw during helper creation. Keep its
constants app-owned and safe. Invalid paths return fallback; query/fragment and trailing
slashes are excluded, decoded parameter values never appear in output.

A custom mapper is synchronous. A throw or invalid/blank result clears default attribution
until a valid screen is entered, without falling back to the raw path.

Network URLs are separate: `true`, `{}` and `{ urlMode: "path" }` retain sanitized paths;
`{ urlMode: "origin" }` emits only scheme/host/port, stripping credentials, path, query and
fragment. Unparseable URLs omit `_http_url`. The mode applies to automatic fetch events
before hooks/output, including failures; it does not sanitize manual attributes.

## Metrics and operations

```ts
Pulse.startOperation(metric: string, attributes?): PulseOperation
Pulse.recordMetric(metric: string, attributes?): void
```

`PulseOperation`:

| Member | Signature | Emits |
|---|---|---|
| `complete` | `(attributes?) => void` | `metric:<slug>:complete`, info, with `duration_ms` |
| `fail` | `(error: unknown, attributes?) => void` | `metric:<slug>:fail`, error, with `duration_ms` and an `error` attribute |
| `cancel` | `(attributes?) => void` | `metric:<slug>:cancel`, info, with `duration_ms` |
| `trackingId` | `string` | the UUID shared by start and terminal events |

`fail` takes the error **value** on web (`unknown`) and describes it into the `error`
attribute. The Node SDK's `fail` takes a `string` — the two are not interchangeable.
Finishing is idempotent: the first terminal call wins.

Slugs are coerced to `^[a-z0-9-]+$` — lowercased, other characters become hyphens, runs
collapse, edges trimmed — with one console warning per page however many bad slugs are
passed. A slug of nothing but invalid characters normalises to the empty string.

## Funnels

```ts
Pulse.step(name: string, attributes?): void
```

Emits `step:<name>` at info level. Names are kept verbatim — nothing is normalised, so a
typo becomes its own step.

## Identity and user properties

`setUser` is opt-in — write it only when the developer has agreed to link analytics to real
user ids, as the Identity section of this skill's `SKILL.md` sets out. `clearUser` is never
gated, because it creates no link — but it removes none either: a bare `clearUser()` returns
to the previous anonymous id, which the server still resolves to the account that claimed it,
so only `{ newAnonymousId: true }` separates future activity, and events already claimed stay
claimed. Everything below works on the anonymous id.

```ts
Pulse.setUser(identifier: string): Promise<void>
Pulse.clearUser(options?: { newAnonymousId?: boolean }): void
Pulse.setUserProperties(properties: Record<string, string>): Promise<void>
```

The anonymous id is `pulse_anon_<uuid>` in `localStorage`, created on successful browser
initialization. `setUser` flushes, claims the anonymous history server-side, then switches
the id; an empty identifier throws and a repeat with the same id is a no-op. Both promises
wait for request attempts that retry with backoff, so neither belongs on an awaited path.
Properties merge server-side: 50 keys, 50-character keys, 200-character values, and an empty
string deletes a key.

## Feedback and questionnaires

```ts
Pulse.sendFeedback(message: string, options?: { name?, email? }): Promise<PulseFeedbackReceipt>
Pulse.fetchQuestionnaire(slug: string, options?: { force?: boolean }): Promise<PulseQuestionnaireFetchResult>
Pulse.saveQuestionnaireResponse(slug: string, answers, isComplete: boolean): Promise<PulseQuestionnaireReceipt>
Pulse.dismissQuestionnaires(): Promise<Date>
```

Exported answer helpers: `createAnswerStore`, `setAnswer`, `isAnswered`, `hasAllRequired`,
`collected`, `firstUnansweredIndex`. Details in
`feedback-questionnaires-attachments.md`.

## Lifecycle

```ts
Pulse.flush(): Promise<void>      // send everything buffered, including attachments
Pulse.shutdown(): Promise<void>   // drain telemetry and stop the client
Pulse.init({ enabled: false })     // stop and discard pending memory, without flushing
```

Disable leaves pre-existing browser storage intact; a later initialization may replay its
old queue. Neither disable nor shutdown can recall data already transmitted.

## Read-only properties

| Property | Value |
|---|---|
| `Pulse.sessionId` | current session UUID, or `undefined` while inactive |
| `Pulse.currentUserId` | the id stamped on events — the identified user, else the anonymous id |

## Events the SDK emits by itself

| Message | Level | When |
|---|---|---|
| `sdk:session_started` | info | a new session begins; carries `_launch_ms` on the first of a page load |
| `sdk:session_ended` | info | a session this page started expires |
| `sdk:screen_appeared` | debug | a screen becomes current |
| `sdk:screen_disappeared` | debug | the previous screen is left; carries `_duration_ms` |
| `sdk:network_request` | debug/warn/error | one per `fetch` while `networkTracking` is on |
| `sdk:feedback_submitted` | info | after a successful `sendFeedback` |

Sessions live in `sessionStorage`, so a reload in the same tab keeps the session and emits
nothing. An inherited session ends silently — another tab may still be using it.

## Reserved attribute keys

Underscore-prefixed keys belong to the SDK and the server. Do not invent your own.

| Key | Holds |
|---|---|
| `_error_type`, `_error_stack`, `_error_code`, `_error_cause_<n>_*` | extracted from an error value; `_error_stack` is capped at 16000 |
| `_unhandled` | `uncaught_exception` or `unhandled_rejection` |
| `_http_url`, `_http_method`, `_http_status`, `_http_duration_ms` | network requests; status `"0"` when the request never completed |
| `_page_url`, `_referrer` | optional browser context, capped at 2048 each; avoid raw URLs/referrers containing identifiers or secrets |
| `_launch_ms`, `_duration_ms` | timings the SDK measures |

## Delivery behaviour

Batches flush every `flushIntervalMs` or once `flushThreshold` events are buffered. Bodies
over 512 bytes are gzipped where `CompressionStream` exists. On page hide the SDK flushes
with a `keepalive` request and parks the remainder in a `localStorage` offline queue drained
on the next load; that queue is shared across tabs and serialised with the Web Locks API.
Failed requests retry with exponential backoff from one second to thirty, honouring a
`Retry-After` up to a minute, and a batch still undelivered after six attempts is parked.
Ingest deduplicates on the event id, so a batch both parked and sent is counted once.
