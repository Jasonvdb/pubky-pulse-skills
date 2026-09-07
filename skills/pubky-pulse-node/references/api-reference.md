## Contents

- Configuration options
- Logging
- Scoping
- Metrics and operations
- Funnels
- User properties
- Feedback
- Attachments
- Lifecycle
- What `configure()` does
- Error attributes
- Events the SDK emits by itself
- Delivery behaviour

## Configuration options

`Pulse.configure(options)` — call once per process, at module scope in a module every
handler imports. Calling it again shuts the previous transport down cleanly and starts a new
session.

| Option | Type | Default | What it does |
|---|---|---|---|
| `endpoint` | `string` | required | Pulse server URL; a trailing slash is stripped |
| `apiKey` | `string` | required | client key for a `backend` app; must start with `pulse_client_` |
| `serviceName` | `string` | `"unknown"` | labels which service emitted an event; not a `bundle_id` |
| `appVersion` | `string` | unset | reported on every event; must increase between releases |
| `isDev` | `boolean` | `process.env.NODE_ENV !== "production"` | marks events as development traffic |
| `debug` | `boolean` | `false` | SDK diagnostics to `console.error` — failed sends, slug corrections, rejected session ids |
| `consoleLogging` | `boolean` | `true` | echo events to the console |
| `captureUnhandled` | `boolean` | `true` | install the `uncaughtException` / `unhandledRejection` listeners |
| `flushIntervalMs` | `number` | `5000` | milliseconds between automatic flushes |
| `flushThreshold` | `number` | `20` | buffered events that trigger an immediate flush |
| `maxBufferSize` | `number` | `10000` | buffered events kept before the oldest are dropped |

Requires Node 20+ for global `fetch` and `AbortSignal.timeout`. Zero runtime dependencies;
ESM and CommonJS builds both ship.

## Logging

```ts
Pulse.info(message: string, attrs?, options?): void
Pulse.debug(message: string, attrs?, options?): void
Pulse.warn(message: string, attrs?, options?): void
Pulse.error(message: string, attrs?, options?): void
Pulse.error(error: unknown, message?: string, attrs?, options?): void
```

`attrs` is `Record<string, unknown>`; values become `String(value)` and are capped at 200
characters (`_error_stack` at 16000). `options` is
`{ attachments?: PulseAttachment[]; sessionId?: string }`. The message is capped at 2000.

The Error overload is chosen when the first argument is not a string, and accepts `unknown`
— a thrown string or number surfaces as `_error_type=string` / `number`. `source_module`
(`routes/orders.ts:123`) is derived from the call stack on every event.

`ScopedPulse` exposes the same four methods with the same signatures.

## Scoping

```ts
Pulse.withUser(userId: string): ScopedPulse
Pulse.withSession(sessionId: string): ScopedPulse
```

`withUser` is opt-in — write it only once the developer has agreed to link analytics to real
user ids (the `pubky-pulse-instrument` step-4 gate asks). `withSession` needs no such consent.

Scopes are immutable and chain in either order:
`Pulse.withUser(u).withSession(s)` equals `Pulse.withSession(s).withUser(u)`. Session
precedence is per-call `options.sessionId` > `withSession(...)` > the session `configure()`
generated. A `sessionId` that is not a UUID is dropped silently and the scope falls back to
the process session — visible only with `debug: true`. Every event without a `user_id` is
excluded from funnel analytics.

`ScopedPulse` carries `info`, `debug`, `warn`, `error`, `step`, `track`, `startOperation`,
`recordMetric`, `setUserProperties`, `sendFeedback`, `withUser` and `withSession`. It has no
`flush` or `shutdown` — those are process-level and live on `Pulse`.

## Metrics and operations

```ts
Pulse.startOperation(metric: string, attrs?): PulseOperation
Pulse.recordMetric(metric: string, attrs?): void
```

`PulseOperation`:

| Member | Signature | Emits |
|---|---|---|
| `complete` | `(attrs?) => void` | `metric:<slug>:complete`, info, with `duration_ms` |
| `fail` | `(error: string, attrs?) => void` | `metric:<slug>:fail`, error, with `duration_ms` and `error` |
| `cancel` | `(attrs?) => void` | `metric:<slug>:cancel`, info, with `duration_ms` |
| `trackingId` | `string` | the UUID shared by start and terminal events |

`fail` takes a **string**. Attributes are stringified with `String(value)`, so an `Error`
passed here becomes `"Error: boom"` and a thrown plain object becomes `"[object Object]"` —
use `err instanceof Error ? err.message : String(err)`, and report the error itself with
`pulse.error(err, …)` when you want the stack and type. Finishing is **not** idempotent in
this SDK: two terminal calls emit two events. Keep exactly one per exit path.

An operation started from a scope carries that scope's user and session through every phase.
Slugs are coerced to `^[a-z0-9-]+$`, warned about only with `debug: true`.

## Funnels

```ts
Pulse.step(stepName: string, attributes?: Record<string, string>): void
Pulse.track(stepName: string, attributes?): void   // legacy alias
```

Attribute values here must already be strings. Emit steps from a `withUser` scope — steps
without a `user_id` are excluded from every funnel.

## User properties

```ts
Pulse.setUserProperties(userId: string, properties: Record<string, string>): void
scope.setUserProperties(properties: Record<string, string>): void
```

Fire-and-forget: it returns `void`, retries in the background and never throws. Properties
merge server-side — 50 keys, 50-character keys, 200-character values, and an empty string
deletes a key.

## Feedback

```ts
Pulse.sendFeedback(message: string, options?: SendFeedbackOptions): Promise<{ id, createdAt }>
```

Awaits the server and throws on failure — wrap it. The message is trimmed and capped at 4000
characters.

| Option | Default | Notes |
|---|---|---|
| `name` | — | submitter name, 255 characters server-side |
| `email` | — | validated server-side |
| `userId` | the scope's user | attaches the feedback to a project user |
| `sessionId` | the scope's session | UUID; non-UUIDs ignored |
| `bundleId` | — | only when forwarding for a frontend whose app has one |
| `environment` | `"backend"` | must be allowed for the key's app platform |
| `appVersion`, `deviceModel`, `osVersion`, `isDev` | from config | pass-through when forwarding |

## Attachments

```ts
Pulse.error("import_failed", { file: name }, {
  attachments: [
    { path: "/tmp/import.csv" },
    { buffer: report, name: "report.json", contentType: "application/json" },
  ],
});
```

`path` and `buffer` are mutually exclusive; `name` is required for a buffer and defaults to
the basename of a path. Uploads run on a serial queue and are awaited by `flush()` and
`shutdown()`, so `wrapHandler` delivers them before a runtime freezes. They are never
queued offline: a process killed before flushing loses the file but not the event. Quotas
are 250 MB per user and 5 GB per project; over either, the event still posts and the
attachment does not.

## Lifecycle

```ts
Pulse.flush(): Promise<void>                      // send buffered events and attachments
Pulse.shutdown(): Promise<void>                   // remove listeners, emit sdk:session_ended, flush, tear down
Pulse.wrapHandler(fn): (...args) => Promise<T>    // flush in a finally around fn
```

## What `configure()` does

1. Validates the endpoint and the key format.
2. Generates the process session id.
3. Starts the flush timer, `unref()`'d so it never holds the process open.
4. Registers a `beforeExit` flush — a graceful-exit safety net only, not a signal handler.
5. Installs the unhandled-error listeners when `captureUnhandled` is on.
6. Prepares the session bracket: `sdk:session_started` is emitted lazily, just before the
   first non-`sdk:` event, so a cold process that never logs produces nothing at all.

## Error attributes

Extracted when an error value is passed to `error()`:

| Attribute | When |
|---|---|
| `_error_type` | always — `error.name`, or `typeof` for a non-Error |
| `_error_stack` | when a stack exists; capped at 16000 |
| `_error_code`, `_error_errno`, `_error_syscall`, `_error_path` | Node `ErrnoException` shape |
| `_error_cause_<n>_type`, `_error_cause_<n>_message` | `cause` walked five levels, cycle-safe |
| `_error_aggregate_count`, `_error_aggregate_first_*` | an `AggregateError` |
| `_unhandled` | `uncaught_exception` or `unhandled_rejection` |

`_error_type` is the issue fingerprint discriminator, which is why passing the error rather
than its message matters.

## Events the SDK emits by itself

| Message | When |
|---|---|
| `sdk:session_started` | lazily, before the first non-`sdk:` event of the process |
| `sdk:session_ended` | on `shutdown()`, only if a session ever started |
| `sdk:feedback_submitted` | after a successful `sendFeedback`, recording only whether a name and email were given |

Backend events always carry `environment: "backend"` and never a `country_code` — the
request reaches Pulse from your datacenter, not from a user. There is no screen tracking,
no `setUser` and no questionnaire API in this SDK.

## Delivery behaviour

Batches flush every `flushIntervalMs` or once `flushThreshold` events are buffered; bodies
over 512 bytes are gzipped. Failed sends retry with exponential backoff up to six attempts,
honouring a `Retry-After` on a `429` or `503` whenever it asks for longer than the backoff
would wait, capped at 60 seconds. `flush()` and `shutdown()` wait for a send already in
flight — including one sleeping between retries — and then drain anything buffered
meanwhile, so a clean exit does not drop a batch. Ingest deduplicates on the client event
id, so a retried batch counts once.
