## Contents

- Configuration options
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

`Pulse.configure(configuration)` — call once. Invalid values throw, so a typo surfaces on
the first page load rather than silently dropping data.

| Option | Type | Default | What it does |
|---|---|---|---|
| `endpoint` | `string` | required | Pulse server URL; a trailing slash is stripped |
| `apiKey` | `string` | required | client key; must start with `pulse_client_` |
| `bundleId` | `string` | required | the app's `bundle_id` — a site identifier name, not a URL |
| `appVersion` | `string` | unset | reported on every event; must increase between releases |
| `isDev` | `boolean` | true on `localhost`, `127.0.0.1`, `file:` | marks events as development traffic |
| `debug` | `boolean` | `false` | print the SDK's own diagnostics |
| `consoleLogging` | `boolean` | `true` | mirror logged events to the console |
| `compressionEnabled` | `boolean` | `true` | gzip bodies where `CompressionStream` exists |
| `captureUnhandled` | `boolean` | `true` | listen for `error` and `unhandledrejection` |
| `trackPageViews` | `boolean` | `true` | emit screen events for History API navigations |
| `networkTracking` | `boolean` | `false` | emit `sdk:network_request` per `fetch` call |
| `propagateSessionTo` | `string[]` | `[]` | URL prefixes that receive `X-Pulse-Session-Id` |
| `flushIntervalMs` | `number` | `5000` | milliseconds between automatic flushes |
| `flushThreshold` | `number` | `20` | buffered events that trigger an immediate flush |
| `maxBufferSize` | `number` | `10000` | buffered events kept before the oldest are dropped |
| `sessionTimeoutMs` | `number` | `1800000` | idle time after which a new session starts |
| `supportedLanguages` | `string[]` | not sent | the locales the app ships; written through to the app record |

Every numeric option must be a positive integer and `flushThreshold` must not exceed
`maxBufferSize`. `supportedLanguages` overwrites what the server holds for the app, so set
it only to the locales actually shipped, or leave it out.

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
```

Sets the current screen and the default `screen_name` for later events. Repeating the
current name is a no-op.

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

The anonymous id is `pulse_anon_<uuid>` in `localStorage`, created on the first
`configure()`. `setUser` flushes, claims the anonymous history server-side, then switches
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
Pulse.shutdown(): Promise<void>   // flush, then remove every page hook the SDK installed
```

## Read-only properties

| Property | Value |
|---|---|
| `Pulse.sessionId` | current session UUID, or `undefined` before `configure()` |
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
| `_page_url`, `_referrer` | browser page context, capped at 2048 each — set these yourself when the path alone is not enough |
| `_launch_ms`, `_duration_ms` | timings the SDK measures |

## Delivery behaviour

Batches flush every `flushIntervalMs` or once `flushThreshold` events are buffered. Bodies
over 512 bytes are gzipped where `CompressionStream` exists. On page hide the SDK flushes
with a `keepalive` request and parks the remainder in a `localStorage` offline queue drained
on the next load; that queue is shared across tabs and serialised with the Web Locks API.
Failed requests retry with exponential backoff from one second to thirty, honouring a
`Retry-After` up to a minute, and a batch still undelivered after six attempts is parked.
Ingest deduplicates on the event id, so a batch both parked and sent is counted once.
