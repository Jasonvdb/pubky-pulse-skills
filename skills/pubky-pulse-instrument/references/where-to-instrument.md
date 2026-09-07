## Contents

- [How to read this](#how-to-read-this)
- [Client app areas](#client-app-areas)
- [Backend service areas](#backend-service-areas)
- [Where the call goes, per platform](#where-the-call-goes-per-platform)
- [The skip list](#the-skip-list)

## How to read this

Each row is one app area, the events worth emitting there, and whether it also
deserves a metric or a funnel step. The names are examples in the family convention —
snake_case for event messages, kebab-case for metric slugs and funnel steps — and are
meant to be renamed into the product's own vocabulary. A photo app has
`photo_exported`, not `item_exported`.

Pick a metric when the question is "how long does this take and how often does it
fail". Pick a funnel step when the question is "where do people drop out". Pick an
event for everything else, and give it enough attributes that the answer to the next
question is already in the row.

## Client app areas

| Area | Events | Also |
|---|---|---|
| Launch, foreground, background | none — the SDK emits `sdk:session_started`, `sdk:app_foregrounded`, `sdk:app_backgrounded` | — |
| Screens and navigation | none on web (History API is automatic); the screen modifier on Swift and Android | — |
| Sign-up | `signed_up` (`method`, `referrer`), `sign_up_failed` (`reason`) | funnel `onboarding` |
| Sign-in / sign-out | `signed_in` (`method`), `sign_in_failed` (`reason`), `signed_out` | metric `sign-in` if it calls out |
| Email or phone verification | `verification_sent`, `verification_completed`, `verification_failed` | funnel step `onboarding-verify` |
| Onboarding stages | `onboarding_completed` at the end only | one funnel step per stage |
| The core action of the product | `<noun>_created`, `<noun>_saved`, `<noun>_deleted` with the ids and sizes that describe it | metric if it can take over ~300 ms |
| Content editing | `<noun>_edited` once per save, never per keystroke | — |
| Search | `search_performed` (`query_length`, `result_count`, `filters_used`), `search_failed` | metric `search` when it hits the network |
| Filtering and sorting | `filter_applied` (`filter`, `value`) — one event per applied filter, debounced | — |
| Upload / import | `upload_completed` (`bytes`, `content_type`), `upload_failed` | metric `upload` |
| Export / share | `export_completed` (`format`, `item_count`), `export_failed` | metric `export`; funnel if multi-step |
| Checkout / subscription | `checkout_started`, `checkout_completed` (`plan`, `total_cents`, `payment_method`), `checkout_failed` (`stage`, `code`) | funnel `checkout`; metric `process-payment` |
| Paywall and trials | `paywall_viewed` (`source`), `trial_started`, `plan_changed` | funnel step |
| Permissions | `permission_granted` (`permission`), `permission_denied` (`permission`) | — |
| Settings | `setting_changed` (`setting`, `value`) — one event, the setting in an attribute | — |
| Feature flags and experiments | attach `feature_flag` as an attribute to the events the flag affects, rather than emitting an event of its own | — |
| Offline and connectivity | `sync_completed` (`pending_count`, `duration_ms`), `sync_failed` | metric `sync` |
| Background refresh | one summary event per run, never one per item | metric |
| In-app help and feedback | `Pulse.sendFeedback` on web, the SDK's feedback view on Swift and Android | — |
| Errors anywhere | `Pulse.error(err, "<action>_failed", { … })` | — |

## Backend service areas

| Area | Events | Also |
|---|---|---|
| Request handling | one `request_handled` per response (`method`, `route`, `status_code`, `duration_ms`); `warn` at 5xx so a bad deploy stands out without becoming an issue | — |
| Request failure | `request_failed` from the framework error handler, with the error object | — |
| Authentication | `auth_succeeded` (`method`), `auth_failed` (`reason`) — never the credential | metric when an identity provider is called |
| Business transactions | `order_placed`, `subscription_renewed`, `refund_issued` with ids and amounts | funnel step, always from `withUser` |
| Outbound calls | `upstream_call_failed` (`service`, `status_code`, `attempt`) — one event per operation, not per retry | metric per upstream |
| Webhooks received | `webhook_received` (`source`, `type`), `webhook_rejected` (`reason`) | — |
| Queue and job workers | `job_completed` (`job`, `processed`, `failed`, `duration_ms`), `job_failed` | metric named for the job |
| Scheduled jobs | one summary event per run — a nightly job over 10,000 rows is one event | metric |
| Database | `query_slow` (`query`, `duration_ms`) above a threshold; pool `error` events | — |
| Migrations and deploys | `migration_applied` (`version`) | — |
| Rate limiting and abuse | `rate_limited` (`route`, `subject_type`) — subject type, never the subject | — |
| Cache | `debug` level only, and only when a miss is interesting | — |
| Startup and shutdown | `service_started` (`version`), `service_stopping` (`reason`) | — |

## Where the call goes, per platform

| Concern | Web | Node | Swift | Android |
|---|---|---|---|---|
| Configure | root component effect, root layout provider, or `onMount` | one module every entry point imports | `App.init` or `didFinishLaunchingWithOptions` | `Application.onCreate()` |
| Screens | automatic; `trackScreen` for modals and wizard steps | n/a | `.pulseScreen("Name")` on each screen's outermost view | `Modifier.pulseScreen("Name")` on each screen's root composable |
| Outcome events | the success branch of the handler that did the work | after the work, before the response is sent | the success branch, on the main actor or off it | the success branch, inside the coroutine |
| Errors | `catch`, error boundary, router error element | framework error handler, worker body | `catch`, `Result` failure, `Task` body | `catch`, `onFailure`, `CoroutineExceptionHandler` |
| Metrics | around the async call, terminal call on every exit | on the scoped logger, so phases carry the user | around the `async` function body | around the suspend function body |
| Funnel steps | at the UI progression point | from `withUser(id)`, never the global logger | at the UI progression point | at the UI progression point |
| Identity | `void Pulse.setUser(id)` after sign-in | `withUser(id)` per request, from the auth layer | `Pulse.setUser(id)` after sign-in | `Pulse.setUser(id)` after sign-in |

## The skip list

Instrumenting these produces cost and noise without answering a question:

- Loops, batch iterations, queue drains, per-item callbacks. One summary event.
- Render passes, `requestAnimationFrame`, `scroll`, `resize`, `mousemove`, and any
  effect that runs on every keystroke. Debounce to an outcome.
- Individual retry attempts. One event carrying `retry_count`.
- Health checks, heartbeats, readiness probes, keep-alives.
- Cache hits and other no-ops. Never open a metric operation you will close in
  microseconds; if it is worth anything at all it is a `debug` event.
- Getters, mappers, pure functions, and anything with no failure mode.
- Screen views on top of automatic screen tracking. That is double counting.
- Third-party library internals you do not control.
- Anything whose value is a secret, a credential, a full request or response body, a
  card or account number, an `Authorization` or `Cookie` value, or a raw IP address.
- Free-text a user typed, unless the product is about that text and the user knows.
- Attachments of logs, stack traces, screenshots, or anything reconstructible from the
  attributes already on the event.
