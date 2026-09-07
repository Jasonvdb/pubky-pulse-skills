## Contents

- [New product, end to end](#new-product-end-to-end)
- [Reuse before you create](#reuse-before-you-create)
- [Projects](#projects)
- [Apps](#apps)
- [Allowed origins](#allowed-origins)
- [Metric definitions](#metric-definitions)
- [Funnel definitions](#funnel-definitions)
- [Questionnaires](#questionnaires)
- [Import keys and historical data](#import-keys-and-historical-data)
- [Rollup backfills](#rollup-backfills)

## New product, end to end

The order matters: definitions must exist before an SDK emits their slug, and an app
must exist before anyone can configure a key.

- [ ] `pubky-pulse:whoami` → team id, permissions.
- [ ] `pubky-pulse:list-projects` → does this product already have a project? Reuse it.
- [ ] `pubky-pulse:create-project` with the bare product name.
- [ ] `pubky-pulse:create-app` once per platform the product ships on, noting each
      `client_secret`.
- [ ] `pubky-pulse:create-metric` for each operation whose duration and success rate
      matter.
- [ ] `pubky-pulse:create-funnel` for each journey worth measuring drop-off on.
- [ ] Hand the client keys and slugs to whoever is instrumenting the code.
- [ ] Verify with `pubky-pulse:query-events` at `data_mode: "development"`,
      `since: "15m"` once the app has run once.

Only proceed past a create when the response carried an `id` (or a `slug`). A 403
means stop and read it — see `references/access-model.md`.

## Reuse before you create

A second project for a product that already has one splits its data permanently, and
deleting a project is human-only. Before creating anything:

- `pubky-pulse:list-projects` and compare names and slugs, not just exact matches —
  "Lofi", "lofi-app" and "Lofi Mobile" are probably one product.
- `pubky-pulse:list-apps` and compare `bundle_id` against the repository's own bundle
  identifier or applicationId. A match means the app already exists.
- When two candidates look equally plausible, ask the user rather than picking.

## Projects

```json
{
  "team_id": "<team>",
  "name": "Lofi",
  "slug": "lofi",
  "retention_days_events": 120
}
```

| Field | Notes |
|---|---|
| `name` | The bare product name. No platform suffix, ever — the suffix belongs on app names. |
| `slug` | Lowercase and hyphens; the URL-facing identifier. |
| `retention_days_events` | Default 120. Range is enforced server-side. |
| `retention_days_metrics` / `retention_days_funnels` | Default 365 each. |

`pubky-pulse:update-project` also takes `color` (`#RRGGBB`),
`attachment_user_quota_bytes` and `attachment_project_quota_bytes`; `null` on any of
them resets to the default. It needs ownership, which `create-project` has just
granted the key's creator.

## Apps

One app per platform build. Names are strictly `<Project> <Platform>`.

```json
{ "name": "Lofi iOS",     "platform": "apple",   "project_id": "<p>", "bundle_id": "com.acme.lofi" }
{ "name": "Lofi Android", "platform": "android", "project_id": "<p>", "bundle_id": "com.acme.lofi" }
{ "name": "Lofi Backend", "platform": "backend", "project_id": "<p>" }
{ "name": "Lofi Web",     "platform": "web",     "project_id": "<p>",
  "bundle_id": "app.acme.com",
  "allowed_origins": ["https://app.acme.com", "http://localhost:5173"] }
```

`platform` also drives the `environment` values that arrive later: `apple` produces
`ios`, `ipados`, `macos` or `watchos`; `android` produces `android`; `web` produces
`web`; `backend` produces `backend`.

`bundle_id` is immutable after creation. On `apple` it is the bundle identifier, on
`android` the applicationId, on `web` a site identifier *name* that is never compared
against the page origin, and on `backend` it must be omitted entirely.

The response's `client_secret` is the `pulse_client_*` key the SDK configures with. It
is ingest-scoped and public by design — it ships inside the app — but it is still not
something to paste into a chat log or a commit unprompted.

## Allowed origins

Web apps only; sending the field for any other platform is a 400.

- Full origins: scheme, host, optional port. No path, no trailing slash, no wildcard.
- At most 50. Lowercased and de-duplicated on write.
- Include every origin the site is served from **and** the dev server's
  (`http://localhost:5173` for Vite, `http://localhost:3000` for Next.js).
- An empty list refuses every request carrying an `Origin` header, which is every
  request a browser makes. This is the most common cause of "the SDK is configured but
  nothing arrives".
- Unrelated to the server's `CORS_ORIGINS`, which is the dashboard's own origin.

`pubky-pulse:update-app` replaces the list. To add one origin:

```text
get-app → read allowed_origins → update-app with the old list plus the new entry
```

## Metric definitions

Create the definition first; the SDK's `startOperation(slug)` / `recordMetric(slug)`
calls reference it.

```json
{
  "project_id": "<p>",
  "name": "Process payment",
  "slug": "process-payment",
  "description": "Checkout charge, from submit to settled"
}
```

Slugs are `^[a-z0-9-]+$`. The server rejects anything else outright; the SDKs silently
correct an invalid slug and log a warning, so data lands under a slug nobody planned —
which is why the definition should be created deliberately, before instrumentation.

Two shapes, no flag to distinguish them — the SDK decides at the call site:

- **Lifecycle** — `startOperation(slug)` then exactly one of `complete()`, `fail()`,
  `cancel()`. `duration_ms` and a `tracking_id` are added automatically.
- **Single-shot** — `recordMetric(slug)`, one `record` phase, for point-in-time values
  like queue depth or cold-start time.

`schema_definition` and `aggregation_rules` are optional free-form JSON; leave them out
unless the user has a specific shape in mind.

## Funnel definitions

```json
{
  "project_id": "<p>",
  "name": "Checkout",
  "slug": "checkout",
  "description": "Cart through to paid",
  "steps": [
    { "name": "Cart viewed",   "event_filter": { "step_name": "checkout-cart" } },
    { "name": "Address given", "event_filter": { "step_name": "checkout-address" } },
    { "name": "Payment taken", "event_filter": { "step_name": "checkout-paid" } }
  ]
}
```

- Up to 20 ordered steps. 3–6 is the useful range; every step should be a point every
  converting user passes through.
- `step_name` matches `Pulse.step("checkout-cart")` verbatim — no prefix, no
  transformation. A typo produces a step that reads zero forever rather than an error,
  so copy the strings between the definition and the code rather than retyping them.
- `screen_name` in a step filter is an **exact** match. Web screen names are URL paths,
  so a path with a variable segment (`/orders/8123`) can never match — use `Pulse.step`
  for those flows.
- Prefix step names with the funnel slug (`checkout-cart`, not `cart`) so a step name
  is unambiguous across funnels.
- Split alternative paths into separate funnels rather than branching one.

`pubky-pulse:update-funnel` replaces the whole `steps` array; send every step you want
to keep.

## Questionnaires

`pubky-pulse:create-questionnaire` takes `project_id`, an immutable `slug`, a `name`,
an optional `description`, an optional `app_id` (omit for project-wide), `is_active`
(defaults true) and a `schema`:

```json
{
  "version": 1,
  "questions": [
    { "id": "q_nps", "type": "nps", "title": "How likely are you to recommend Lofi?", "required": true },
    { "id": "q_why", "type": "text", "title": "What drove that score?", "multiline": true, "required": false }
  ]
}
```

Question ids match `^[a-z0-9_]{1,32}$`. Up to 30 questions. Put the highest-signal
questions first — a user who quits halfway still leaves those answered.
`references/feedback-and-questionnaires.md` has all five question types and the
analytics shape.

The mobile SDKs render the survey from the slug, so the slug can never change. To
replace one, create a new questionnaire with a new slug.

## Import keys and historical data

```text
create-import-key { app_id, name?: "Migration" }  →  pulse_import_… (shown once)
```

The key is for `POST /v1/import`, which the user's own script calls — no MCP tool
ingests events.

| | `/v1/ingest` (SDKs) | `/v1/import` |
|---|---|---|
| Key | `pulse_client_*` | `pulse_import_*` |
| Batch | 100 events | 1000 events |
| Timestamps | 30 days past to 5 min future | any past date |
| `bundle_id` | required for non-backend apps | not required |
| Rate limit | 100 tokens, 10/s | none |
| Repeated `client_event_id` | skipped | updates the existing event |

Body is `{ "events": [...] }`. Required per event: `message`, `level`, and a UUID
`session_id` — generate one per historical session if the source system has none.
Everything else (`user_id`, `timestamp`, `custom_attributes`, `app_version`,
`environment`, `screen_name`, …) is optional. Messages shaped `metric:<slug>:<phase>`
and `step:<name>` are detected and dual-written into metric and funnel tables, so an
import can rebuild historical funnels — provided the definitions exist first.

Because a repeated `client_event_id` updates rather than duplicates, re-running a
corrected import script is safe. Import requests carry no `Origin` header, so a web
app's `allowed_origins` never applies to them.

## Rollup backfills

`pubky-pulse:trigger-job` accepts exactly two job types:

```json
{ "team_id": "<t>", "job_type": "stats_aggregate_daily", "project_id": "<p>",
  "params": { "start": "2026-01-01", "end": "2026-03-31" } }
```

`stats_aggregate_hourly` is the same with ISO hours in `start`/`end`. With no `params`
either job re-aggregates its trailing three buckets. One run per type per project at a
time — a duplicate returns 409 naming the run already in flight. Poll it with
`pubky-pulse:get-job`, or pass `notify: true` to have the server email the key's
creator when it finishes.

Every other job type is system-scoped and the trigger route refuses it, so a fresh
error cannot be turned into an issue on demand: `issue_scan` runs hourly.
