## Contents

- [Pick the tool by the question](#pick-the-tool-by-the-question)
- [Time and data mode](#time-and-data-mode)
- [Did the instrumentation work?](#did-the-instrumentation-work)
- [What is this user doing?](#what-is-this-user-doing)
- [Which release broke it?](#which-release-broke-it)
- [Where do users drop out?](#where-do-users-drop-out)
- [How has this changed over time?](#how-has-this-changed-over-time)
- [Who is affected and where are they?](#who-is-affected-and-where-are-they)
- [Pagination and response size](#pagination-and-response-size)
- [Nothing came back](#nothing-came-back)

## Pick the tool by the question

| Question | Tool |
|---|---|
| Show me the individual records | `pubky-pulse:query-events` |
| What happened around this one event | `pubky-pulse:investigate-event` |
| What is the p95 and success rate of this operation | `pubky-pulse:query-metric` |
| Why did this single operation fail | `pubky-pulse:list-metric-events` |
| Where in this journey do people stop | `pubky-pulse:query-funnel` |
| How has this number moved over weeks or months | `pubky-pulse:query-stats-bucketed` |
| Which users exist and which are anonymous | `pubky-pulse:list-app-users` |
| Which language should we ship next | `pubky-pulse:list-user-locales` |

## Time and data mode

`since` and `until` take `30s`, `30m`, `1h`, `7d`, `1w` — counted backwards from now —
or an ISO 8601 timestamp. Defaults: events 24h, metrics 24h, funnels 30d,
`query-stats-bucketed` 30 days or 24 hours by grain.

`data_mode` defaults to `production`. Set it to `development` for anything a developer
just ran locally, and `all` when you are not sure which side the data landed on.
Development is auto-detected: `localhost` / `127.0.0.1` / `file:` in a browser,
`NODE_ENV !== "production"` on Node, DEBUG builds on Apple, debuggable builds on
Android. TestFlight and release builds are production.

## Did the instrumentation work?

Right after wiring an SDK, against a locally running app:

```json
// query-events
{ "app_id": "<app>", "data_mode": "development", "since": "15m", "order": "asc",
  "compact": true, "limit": 100 }
```

Expect `sdk:session_started` first, then the plan's own event messages. Then check
each definition landed:

```json
// query-metric
{ "project_id": "<p>", "slug": "process-payment", "since": "1h", "data_mode": "development" }
// query-funnel
{ "project_id": "<p>", "slug": "onboarding", "since": "1h", "data_mode": "development",
  "mode": "open" }
```

Open mode first: closed mode needs the steps in order and will read zero on a partial
manual test even when every step is firing.

To confirm error capture, throw something deliberately and look for it:

```json
{ "app_id": "<app>", "level": ["error"], "data_mode": "development", "since": "15m" }
```

The error *event* is queryable immediately. The *issue* is not — `issue_scan` runs
hourly and cannot be triggered.

## What is this user doing?

Start from any event of theirs and let the breadcrumb builder do the work:

```json
// investigate-event
{ "event_id": "<event>", "compact": true, "data_mode": "production" }
```

That returns the whole session plus cross-app events for the same user in the same
project — so a browser click and the backend request it caused appear in one list,
sorted ascending, even when the two apps never shared a session id.

Walking a session by hand is the fallback:

```json
// query-events
{ "session_id": "<session>", "order": "asc", "compact": true, "limit": 200 }
```

Filtering by `user_id` across a window shows every session instead of one:

```json
{ "project_id": "<p>", "user_id": "user_123", "since": "7d", "order": "asc", "compact": true }
```

## Which release broke it?

Group the metric by version and compare success rate and p95:

```json
// query-metric
{ "project_id": "<p>", "slug": "process-payment", "since": "14d", "group_by": "app_version" }
```

The same grouping works on a funnel:

```json
// query-funnel
{ "project_id": "<p>", "slug": "checkout", "since": "14d", "group_by": "app_version" }
```

For errors, filter events to the level and compare counts either side of the release:

```json
{ "project_id": "<p>", "level": ["error"], "since": "2026-03-01T00:00:00Z",
  "until": "2026-03-08T00:00:00Z", "compact": true }
```

`pubky-pulse:get-app` carries `latest_app_version`, computed hourly from production
events — the number to compare an issue's `last_seen_app_version` against.

## Where do users drop out?

```json
// query-funnel
{ "project_id": "<p>", "slug": "onboarding", "since": "30d", "mode": "closed" }
```

Each step returns `unique_users`, `percentage`, `drop_off_count` and
`drop_off_percentage`.

- **Open** counts each step independently — right for non-linear flows, and the mode
  to try first when a funnel looks empty.
- **Closed** requires the steps in order per user with strict timestamp ordering —
  right for a linear checkout, and unforgiving of a step that fires out of order.
- Both exclude events with no `user_id`. A backend funnel needs
  `Pulse.withUser(id).step(...)`; a bare `Pulse.step` from a Node process is silently
  dropped from the analytics.
- `group_by` is `environment` or `app_version` only — no device or country breakdown.

## How has this changed over time?

Raw event scans get slower and eventually hit retention. The rollups do not:

```json
// query-stats-bucketed
{ "kind": "events", "grain": "daily", "project_id": "<p>", "days": 90 }
{ "kind": "users",  "grain": "daily", "project_id": "<p>", "days": 365 }
{ "kind": "funnel_completions", "grain": "daily", "project_id": "<p>",
  "slug": "checkout", "days": 90 }
{ "kind": "events", "grain": "hourly", "project_id": "<p>", "hours": 48,
  "excluding_current": false }
```

Read the results carefully: buckets are UTC, the in-progress one is dropped unless you
ask for it, and `users` / `sessions` are per-bucket distinct counts that cannot be
added together across buckets. Use `app_id` to narrow to one app; leave it out for the
project rollup, whose distincts are project-level (a user on two apps counts once).

## Who is affected and where are they?

```json
// list-app-users
{ "app_id": "<app>", "is_anonymous": "false", "data_mode": "production", "limit": 50 }
// list-user-locales
{ "project_id": "<p>", "data_mode": "production" }
```

`list-user-locales` returns `by_locale` — users grouped by the language their device
asks for, each with a `shipped` flag — and `by_country`. Narrow to one project or app
or the flags come back `null`. The country breakdown works for every user today; the
language breakdown fills in as users move to an SDK version that reports it.

## Pagination and response size

- Every list tool returns `cursor` and `has_more`. Pass the cursor back unchanged and
  keep every other parameter identical — the cursor encodes the query, including
  `order`.
- Default page size is 50. Raising `limit` is rarely the fix for a truncated response;
  `compact: true` is.
- `compact` drops `custom_attributes` and device metadata from `query-events` and
  `investigate-event`. When you then need the stack trace for one event, fetch that
  event alone with `pubky-pulse:get-event`.
- `get-issue` paginates its occurrences separately, with `occurrence_cursor` and
  `occurrence_has_more`.

## Nothing came back

Work down this list before concluding the data is missing:

1. `data_mode` — the default is `production` and the test run was almost certainly
   development.
2. Time window — the default is 24 hours for events and the event may be older, or the
   device clock may have put it slightly in the future.
3. Scope — `app_id` overrides `project_id`; a wrong app id silently returns an empty
   list rather than an error.
4. Web ingest — a web app with empty `allowed_origins` returns 403 to the browser, so
   nothing was ever stored. Check `pubky-pulse:get-app`.
5. Slug — `query-metric` and `query-funnel` fail closed on a slug that does not exist
   or was never emitted. Confirm with `pubky-pulse:list-metrics` /
   `pubky-pulse:list-funnels`.
6. Funnel `user_id` — anonymous events are excluded from funnel analytics entirely.
7. Retention — events default to 120 days. Older questions belong to
   `pubky-pulse:query-stats-bucketed`, which is exempt from pruning.
8. Issues specifically — the hourly scan has not run yet. The underlying error events
   are already queryable.
