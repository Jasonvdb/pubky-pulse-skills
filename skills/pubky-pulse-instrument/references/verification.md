## Contents

- [Query recipes](#query-recipes)
- [What a healthy result looks like](#what-a-healthy-result-looks-like)
- [Nothing arrives: the decision tree](#nothing-arrives-the-decision-tree)
- [Something arrives, but it is wrong](#something-arrives-but-it-is-wrong)

## Query recipes

Every recipe passes `data_mode: "development"`, because a locally run app is
development data on all four platforms and the default `production` mode returns an
empty list that looks exactly like a broken integration.

| Question | Call | Parameters |
|---|---|---|
| Did anything at all arrive from this app? | `pubky-pulse:query-events` | `{ app_id, data_mode: "development", since: "15m", limit: 50, order: "asc" }` |
| Did the planned events arrive? | `pubky-pulse:query-events` | same, then read the `message` column against the plan |
| Did the errors arrive? | `pubky-pulse:query-events` | `{ app_id, level: ["error"], data_mode: "development", since: "15m" }` |
| Is the browser session reaching the backend? | `pubky-pulse:query-events` | `{ project_id, session_id: "<the browser's session id>", data_mode: "development", compact: true, order: "asc" }` |
| Is the funnel converting? | `pubky-pulse:query-funnel` | `{ project_id, slug, mode: "open", since: "1h", data_mode: "development" }` |
| Is the metric recording? | `pubky-pulse:query-metric` | `{ project_id, slug, since: "1h", data_mode: "development" }` |
| Which raw metric phases fired? | `pubky-pulse:list-metric-events` | `{ project_id, slug, since: "1h", data_mode: "development" }` |
| Have the errors clustered yet? | `pubky-pulse:list-issues` | `{ project_id }` — only after the hourly scan |

Time values are relative (`30s`, `15m`, `1h`, `7d`, `1w`) or ISO 8601. `query-events`
defaults to the last 24 hours, `query-metric` to 24 hours, `query-funnel` to 30 days.
Add `compact: true` to any event query long enough to risk a token overflow.

## What a healthy result looks like

- **`sdk:session_started` per app.** It is emitted by `configure()`, so its absence
  means the SDK never configured, never had a key that worked, or never reached the
  endpoint. Nothing else is worth checking until it is there.
- **The planned events**, with their attributes populated and `screen_name` set on the
  client surfaces (a URL path on web, a PascalCase name on native).
- **One `start` and exactly one terminal phase per metric operation.** Two terminal
  phases means a code path finishes twice; none means an operation leaked.
- **Funnel steps with non-zero users at step 1.** Zero at every step, on a backend
  funnel, means the steps were emitted without `withUser`.
- **Errors at `level: "error"` immediately.** Issues follow within the hour: the issue
  scan is a scheduled system job, so there is nothing to trigger and an empty
  `list-issues` minutes after the error is expected.

## Nothing arrives: the decision tree

Work down in order — the earlier causes are far more common, and each one makes the
later checks meaningless.

1. **Allowed origins (web only).** Is the ingest request in the browser network tab
   answered with `403`, or refused at the CORS preflight? Then the app's
   `allowed_origins` does not contain this origin. A new web app has none, and
   `http://localhost:3000`, `http://localhost:5173` and `http://127.0.0.1:3000` are
   three different origins. Fix with `pubky-pulse:update-app`, resending the whole
   list.
2. **Data mode.** Re-run the query with `data_mode: "all"`. If the events appear, they
   were there all along and the query was asking about production.
3. **The key.** Does it start with `pulse_client_`? A `pulse_agent_` key cannot ingest
   at all. Does it belong to *this* app? A browser configured with the backend app's
   key sends successfully — `allowed_origins` does not apply to a backend app — and
   the data lands under the wrong app, which looks identical to nothing arriving.
4. **The endpoint.** It is a base URL. The SDK appends `/v1/ingest` itself, so an
   endpoint that already ends in `/v1/ingest` or `/mcp` produces a 404 per batch.
5. **Configure ordering.** Calls made before `configure()` are dropped with a single
   console line and then silence. Check that the configuring module is imported before
   anything that logs — on a backend, that the process imported it at all.
6. **Server rendering.** With a valid config and no `window`, `configure()` returns
   early and every call is a no-op; with an invalid config it throws during server
   rendering rather than in the browser. Confirm the configure call runs on the client
   — an effect, `onMount`, a client-only plugin.
7. **Flush.** A short-lived process exits with a full buffer: a one-shot script needs
   `await Pulse.flush()`, a serverless handler needs `wrapHandler`, and a container
   killed with `SIGTERM` needs a signal handler that awaits `shutdown()`. The
   `beforeExit` hook does not fire on `SIGTERM` or `SIGINT`.
8. **Buffer threshold.** The browser flushes every 5 seconds or every 20 events, so a
   single event on a page you closed immediately may never have been sent. Reload,
   wait, and re-query; a `pagehide` keepalive flush covers most of this, but not a
   crashed tab.

If `sdk:session_started` is present and only *your* events are missing, the SDK is
fine and the calls are not running — check the code path actually executes, and that
attribute values are not `undefined` in a way that made you expect a different event.

## Something arrives, but it is wrong

| Symptom | Cause |
|---|---|
| Events land under the wrong app | the two client keys were swapped between the surfaces |
| Funnel shows zero users everywhere | backend steps emitted from the global logger instead of `withUser(id)` |
| Funnel step never matches | the step filter is on `screen_name`, or the emitted name has a typo — step names are kept verbatim |
| Metric shows starts and no completions | a terminal call is missing on some exit path |
| Metric slug looks different from the plan | the SDK auto-corrected it to `^[a-z0-9-]+$` |
| One issue per occurrence | the message is interpolated; move the variable part into an attribute |
| Two unrelated failures in one issue | the error value was not passed, so there is no `_error_type` to discriminate |
| Doubled sessions in development | a second `configure()` call — React StrictMode runs effects twice |
| No version badge, no regression detection | `appVersion` is unset, or is a git SHA and therefore not monotonic |
| Browser and backend events on separate sessions | `propagateSessionTo` missing, or the backend never read `X-Pulse-Session-Id`; a non-UUID value is ignored silently |
