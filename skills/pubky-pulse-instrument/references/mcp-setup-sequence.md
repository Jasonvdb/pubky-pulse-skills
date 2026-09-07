## Contents

- [The sequence](#the-sequence)
- [Reusing an existing project](#reusing-an-existing-project)
- [Creating the apps](#creating-the-apps)
- [Metrics and funnels](#metrics-and-funnels)
- [When a call returns 403](#when-a-call-returns-403)
- [Storing the keys](#storing-the-keys)
- [Adding an origin later](#adding-an-origin-later)

## The sequence

| # | Call | Required parameters | Read back from the response |
|---|---|---|---|
| 1 | `pubky-pulse:whoami` | none | `team.id`, `permissions` |
| 2 | `pubky-pulse:list-projects` | none (`team_id` optional) | `id`, `name`, `slug`, `access_level` per project |
| 3 | `pubky-pulse:create-project` | `team_id`, `name`, `slug` | `id` |
| 4 | `pubky-pulse:create-app` (once per surface) | `project_id`, `name`, `platform` | `id`, `client_secret` |
| 5 | `pubky-pulse:create-metric` (once per metric) | `project_id`, `name`, `slug` | `slug` |
| 6 | `pubky-pulse:create-funnel` (once per funnel) | `project_id`, `name`, `slug`, `steps` | `slug` |

Nothing later works without the id from the step before, so check each response before
the next call. A missing id means the call failed; do not carry on and instrument
against a definition that was never created.

`whoami` answers with the single team the key belongs to. `create-project` does not
default `team_id`, so it is a required read, not an optional one.

## Reusing an existing project

Instrumenting a product twice under two projects splits its metrics, funnels and
issues permanently, and there is no MCP tool to merge or delete a project afterwards.
So match before creating:

1. Slug equality against the product name slugified (`Lofi` → `lofi`) — reuse.
2. Case-insensitive name equality — reuse.
3. One clear substring match, and its apps look like this product's platforms — reuse.
4. Several plausible matches, or a match whose apps belong to a different product —
   this is ambiguity-gate question 3. Ask, defaulting to the closest name match.
5. No match — create.

`access_level` on the row says whether writes will work: `viewer` means every read
succeeds and every write returns `403 Requires project ownership`.

## Creating the apps

```json
{ "project_id": "<id>", "name": "Lofi Web", "platform": "web",
  "bundle_id": "app.lofi.com",
  "allowed_origins": ["https://app.lofi.com", "http://localhost:3000"] }
```

| Platform | `bundle_id` | `allowed_origins` |
|---|---|---|
| `web` | a site identifier name, not a URL — `app.lofi.com` | required in practice: every origin the site is served from, including the dev server |
| `backend` | omitted — backend apps have none | not accepted |
| `apple` | the bundle identifier, `com.example.lofi` | not accepted |
| `android` | the release `applicationId` | not accepted |

Rules that bite:

- `bundle_id` is immutable. Correcting one means deleting the app, and deleting an app
  is human-only.
- An empty `allowed_origins` refuses every browser request with `403`, and CORS
  refuses the preflight before that. A newly created web app has an empty list unless
  you pass one.
- Each entry is a full origin: scheme, host, optional port, no path, no trailing
  slash, no wildcards, at most 50. Entries are normalised on write.
- One `apple` app covers the iOS, iPadOS, macOS and watchOS builds of one product;
  `environment` on the event separates them.
- The response's `client_secret` is the `pulse_client_*` key. Record it now — it is
  also readable later with `pubky-pulse:get-app`, but only by a project owner.

## Metrics and funnels

```json
{ "project_id": "<id>", "name": "Process payment", "slug": "process-payment" }
```

```json
{ "project_id": "<id>", "name": "Checkout", "slug": "checkout",
  "steps": [
    { "name": "Cart",      "event_filter": { "step_name": "checkout-cart" } },
    { "name": "Address",   "event_filter": { "step_name": "checkout-address" } },
    { "name": "Payment",   "event_filter": { "step_name": "checkout-payment" } },
    { "name": "Confirmed", "event_filter": { "step_name": "checkout-confirmed" } }
  ] }
```

- Slugs are `^[a-z0-9-]+$`; the server rejects anything else, and the SDKs
  auto-correct metric slugs with a warning rather than failing loudly.
- `event_filter.step_name` matches what the code passes to `Pulse.step(...)`,
  verbatim. Prefer it to `screen_name`, which is an exact match and therefore never
  matches a path with a variable segment.
- Steps are ordered and capped at 20; 3–6 is the useful range.
- Definitions are project-scoped, so one funnel spans the web and backend apps.
- `pubky-pulse:update-metric` and `pubky-pulse:update-funnel` amend a definition;
  `pubky-pulse:list-metrics` and `pubky-pulse:list-funnels` show what already exists,
  which is worth checking before creating a near-duplicate slug.

## When a call returns 403

| Message | Cause | Fix |
|---|---|---|
| `Missing permission: <p>` | the agent key was never granted that permission | a human edits the key; nothing you can do |
| `Requires project ownership` | the permission is there, but the human who created the key does not own that project | a human owner adds them to the owner list — the very next call then works, with no new key |
| `This operation requires a user session` | the operation is human-only (deleting projects, apps, feedback, questionnaires, attachments; changing owners) | ask a human to do it in the dashboard |

Reads are team-wide and keep working through all three. So on a `403`, keep reading,
finish every code-only step, and end the run with a `Pending Pubky Pulse steps` list
naming each project, app, metric and funnel still to be created and which `403`
blocked it.

## Storing the keys

The `client_secret` is public by design and ships inside the app, but it still does
not belong in a commit. Put it in the environment file the framework already reads,
add the variable name with a placeholder to `.env.example`, and check `.env*` is
git-ignored. The `pulse_agent_*` key is different: it is the MCP credential, it is not
ingest-scoped, and it never belongs in a project file, a bundle, or a `NEXT_PUBLIC_*`
variable.

## Adding an origin later

`pubky-pulse:update-app` replaces the whole `allowed_origins` list, so read the app
first and resend the entries you are keeping:

```json
{ "app_id": "<id>",
  "allowed_origins": ["https://app.lofi.com", "http://localhost:3000", "https://staging.lofi.com"] }
```

Origin changes take effect on ingest immediately. `name` and `allowed_origins` are the
only fields `update-app` accepts — `platform` and `bundle_id` are immutable.
