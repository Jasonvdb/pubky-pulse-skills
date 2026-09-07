---
name: pubky-pulse-operations
description: >-
  Drives the Pubky Pulse MCP server directly: projects, apps and allowed origins, metric and
  funnel definitions, event, metric, funnel and stats queries, feedback, questionnaires,
  attachments, background jobs, import keys and audit logs. Use when asked to create or update
  a Pubky Pulse project, app, metric or funnel, to query analytics or read feedback and survey
  results, or to connect the MCP server and check what a key can do. Not for instrumenting a
  repository or writing SDK code (see pubky-pulse-instrument) or triaging error issues (see
  pubky-pulse-investigate-issues).
license: MIT
compatibility: >-
  Requires the pubky-pulse MCP server connected with an agent key (pulse_agent_*). Any
  harness that reads SKILL.md.
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

**Asking the user.** Whenever a step says to ask the user something, present the
choices as selectable options using your harness's structured question tool rather
than making them type a free-text reply — in Claude Code that tool is
`AskUserQuestion`; Codex and other agents may expose an equivalent. List the
recommended option first. If your harness has no such tool, ask in plain text.
Every question has a default: if no answer comes back, take the recommended option,
continue, and say which default you took in the final report.

## Step 1 — Connect

Call `pubky-pulse:whoami` before anything else, every run. It is the cheapest call on
the server and it returns the three facts every later step depends on: the team id,
the key's permission list, and that the key is live.

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

Before printing that prompt, run the bundled detector to find out whether the server
is configured somewhere the current harness is not reading:

```sh
sh scripts/check-mcp-config.sh
```

It prints JSON on stdout — `configured[]` with the harness, server name and endpoint
URL of every Pubky Pulse entry it found, plus a `suggest` command. It reads only, and
masks any key it passes over. A hit in another harness's config means the URL is
known: substitute that one into the prompt instead of guessing a host.

Everything this skill does goes through the server, so stop there and wait for the
connection rather than half-doing the work. Say plainly which task is blocked.

## Step 2 — Know what the key can do

Reads are wide, writes are narrow. The key reads **every project in the team** for
each read permission it holds. An ordinary write additionally requires the human who
created the key to currently own the target project. Authorization is an
intersection, never a union:

```text
key is active
AND key holds the route's explicit permission
AND the creator is an active team member on an allowed email domain
AND the creator currently owns the target project
AND the operation is agent-supported
```

Ownership is re-read on every request, so a human adding the creator to a project
takes effect on the very next call — nothing is re-issued or reconnected. And
`pubky-pulse:create-project` makes the creator the new project's first owner, so a
project this key just created is immediately writable.

Read the 403 rather than retrying it. There are exactly three, and they mean
different things:

| 403 message | What it means | What unblocks it |
|---|---|---|
| `Missing permission: <p>` | the key was never granted that permission | a human edits the key in the dashboard |
| `Requires project ownership` | permission is fine; the creator does not own this project | a human owner adds them to the project's owner list — same key, next call works |
| `This operation requires a user session` | the operation is human-only, for anybody's agent key | nothing; ask a human to do it in the dashboard |

**Human-only, always:** changing a project's owner list; deleting a project, an app, a
feedback item, a questionnaire, a questionnaire response, or an attachment; deleting a
comment this exact key did not write; and listing, updating or revoking API keys —
`pubky-pulse:create-import-key` is the one key operation an agent may do.

**Agent-supported writes:** creating and updating projects, apps, metric and funnel
definitions and questionnaires; deleting metric and funnel definitions; merging issues
and changing issue, feedback and questionnaire-response status; triggering and
cancelling project jobs; and writing comments.

Commenting is the single exception to ownership: the matching `:write` permission on
any readable project is enough. So when a status change is refused, a comment
recording what you found still lands.

`references/access-model.md` has the permission-to-tool map and the recovery move for
each refusal — read it when a call returns 403 or a key seems under-permissioned.

## Step 3 — Find the ids

Nearly every tool takes a `project_id`; several take `team_id` instead, and a few take
one or the other but never both.

- team id — `pubky-pulse:whoami` → `team.id`
- project id — `pubky-pulse:list-projects` → `projects[].id`; the row also carries
  `owners` and `access_level` (`owner` | `viewer`) for this key's creator, so a
  `viewer` row tells you a write will 403 before you attempt it
- app id and client key — `pubky-pulse:list-apps` → `apps[].id`, `client_secret`
- metric and funnel slugs — `pubky-pulse:list-metrics` / `pubky-pulse:list-funnels`,
  with either `project_id` for one project or `team_id` for every accessible project

Resolve names to ids once, at the start, and reuse them. When a name the user gave
matches more than one project, ask which — do not pick.

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

Rule of thumb: hyphens mean the name must exist on the server first; underscores mean
a free-form event message. The message is the issue-grouping key, so keep it a stable
template and put the variable data in attributes. If the project already has a naming
convention, stay consistent with it.

## Setup recipes

**Create a project.** The name is the bare product name; a platform suffix here is the
most common setup mistake and renaming the apps later does not undo it.

```json
{ "team_id": "<team>", "name": "Lofi", "slug": "lofi" }
```

Retention is optional — `retention_days_events` (default 120),
`retention_days_metrics` and `retention_days_funnels` (default 365 each). A display
colour is assigned automatically; `pubky-pulse:update-project` overrides it.

**Create one app per platform.** `platform` is `apple`, `android`, `web` or `backend`.
`bundle_id` is required for everything but `backend` and is **immutable** — a wrong one
can only be fixed by a human deleting and recreating the app.

| Platform | `bundle_id` | `allowed_origins` |
|---|---|---|
| `apple` | the bundle identifier, `com.acme.lofi` | rejected |
| `android` | the applicationId, `com.acme.lofi` | rejected |
| `web` | a site identifier *name*, `app.acme.com` — not a URL, never matched against the page origin | required in practice |
| `backend` | omit the field entirely | rejected |

```json
{
  "name": "Lofi Web", "platform": "web", "project_id": "<project>",
  "bundle_id": "app.acme.com",
  "allowed_origins": ["https://app.acme.com", "http://localhost:5173"]
}
```

`allowed_origins` rules: full origins only — scheme, host, optional port, no path, no
trailing slash, no wildcards, at most 50, lowercased and de-duplicated on write. A web
app whose list is empty refuses every request carrying an `Origin` header, which is
every request a browser makes, so create the app with its origins already in place,
including the developer's local port. This is per app and has nothing to do with the
server's own `CORS_ORIGINS`, which is the dashboard's origin.

`pubky-pulse:update-app` **replaces the whole list**. Read the current value with
`pubky-pulse:get-app` and send it back with the addition, or the change silently locks
out every origin you dropped.

The create response carries `client_secret` — the `pulse_client_*` key the SDK
configures with. Hand it to whoever is wiring the SDK; do not print it unprompted (see
Output conventions).

**Create metric definitions before the SDK emits them.** A slug is `^[a-z0-9-]+$` and
the server rejects anything else.

```json
{ "project_id": "<project>", "name": "Process payment", "slug": "process-payment",
  "description": "Checkout charge, start to settled" }
```

**Create funnels before the SDK emits steps.** Up to 20 ordered steps; each step has a
display `name` and an `event_filter` matching `step_name`, `screen_name`, or both.

```json
{
  "project_id": "<project>", "name": "Onboarding", "slug": "onboarding",
  "steps": [
    { "name": "Signed up",  "event_filter": { "step_name": "onboarding-signed-up" } },
    { "name": "Email sent", "event_filter": { "step_name": "onboarding-email" } },
    { "name": "Verified",   "event_filter": { "step_name": "onboarding-verified" } }
  ]
}
```

`step_name` matches **verbatim** what the SDK passes to `Pulse.step("…")` — no prefix,
no transformation, and a typo simply never matches rather than erroring. `screen_name`
in a step filter is an **exact** match, unlike the prefix matching
`pubky-pulse:query-events` does, so a web path with a variable segment (`/orders/8123`)
never matches a step filter — use `Pulse.step` for those.
`pubky-pulse:update-funnel` replaces the whole step list, same as origins.

`references/setup-recipes.md` has the full parameter tables, the questionnaire and
import-key recipes, and the end-to-end new-product sequence — read it when setting up a
project from scratch or creating a questionnaire.

## Query recipes

**Time.** `since` and `until` take a relative duration — `30s`, `30m`, `1h`, `7d`, `1w`,
counted backwards from now — or an ISO 8601 timestamp. Defaults differ per tool: events
24 hours, metrics 24 hours, funnels 30 days.

**Data mode.** `data_mode` is `production` by default; `development` and `all` are the
other two. Local runs are development data: `localhost`, `127.0.0.1` and `file:` pages
in a browser, `NODE_ENV !== "production"` on Node, DEBUG builds on Apple, debuggable
builds on Android. So a query that "returns nothing" right after a developer tested a
change is nearly always a data-mode mistake, not missing data.

**Events.** `pubky-pulse:query-events` filters on `project_id` or `app_id` (app wins),
`level` as an array (`["warn","error"]`), `user_id`, `session_id`, `environment`,
`screen_name`, `device_model`, `os_version`, plus `since`/`until`/`data_mode`.
`screen_name` matches exactly or as a path prefix — `/checkout` also returns
`/checkout/payment` but not `/checkout-abandoned`. `device_model` and `os_version` are
exact and platform-dependent: on web they hold the browser (`Chrome 120`) and the OS
(`macOS 10.15.7`). Pass `order: "asc"` to read a session forwards, and `compact: true`
on anything long — it drops `custom_attributes` and device metadata, which is what
keeps a session timeline under the MCP response limit.

**Metrics.** `pubky-pulse:query-metric` returns counts per phase, success rate,
avg/p50/p95/p99 duration, unique users and an error breakdown. `group_by` takes one of
`app_id`, `app_version`, `device_model`, `os_version`, `environment`, `time:hour`,
`time:day`, `time:week` — grouping by `app_version` is how you show a regression
between releases. `pubky-pulse:list-metric-events` drills into single operations by
`phase` or `tracking_id`.

**Funnels.** `pubky-pulse:query-funnel` defaults to `mode: "open"` — each step counts
distinct users independently, right for non-linear flows. `mode: "closed"` requires the
steps in order per user with strict timestamp ordering, right for a linear checkout.
Both group users by `user_id`, so **events with no `user_id` are excluded entirely** —
the usual cause of an empty backend funnel, which `Pulse.withUser(id).step(...)` fixes
only where identity linking was opted into (the gate in `pubky-pulse-instrument`).
Anonymous-only, an empty backend funnel is the correct outcome: `Pulse.withSession(...)`,
driven by the client's `X-Pulse-Session-Id` header, is what ties backend events to a
browser session without identifying anyone. `group_by` is only `environment` or
`app_version`.

**Trends.** `pubky-pulse:query-stats-bucketed` reads pre-aggregated rollups instead of
rescanning raw events: `kind` is `events`, `users`, `sessions`, `metric_completions`,
`funnel_completions` or `questionnaire_responses`, `grain` is `daily` or `hourly`,
scope is `project_id` **or** `team_id` and never both, with an optional `app_id` and a
`slug` to narrow to one definition. Windows are `days` (default 30) or `hours` (default
24), or explicit `from`/`to`. Buckets are UTC and the in-progress one is dropped unless
`excluding_current: false`. These tables survive retention pruning, so they answer
year-long questions raw events no longer can.

**Pagination.** List tools return `cursor` and `has_more`; pass the cursor back to walk
pages, and keep every other parameter — including `order` — identical, because the
cursor encodes them. Default page size is 50; raise `limit` only when you will actually
read the extra rows.

`references/query-recipes.md` has worked queries per question — "which release broke
it", "where do users drop out", "what did this user do" — read it when a query needs
shaping beyond one filter.

## The other surfaces

**Feedback** is free-text from end users. `pubky-pulse:list-feedback` filtered to
`status: "new"` → `pubky-pulse:get-feedback` for the message and its `session_id` →
`pubky-pulse:investigate-event` on an event from that session to see what they were
doing → `pubky-pulse:add-feedback-comment` → `pubky-pulse:update-feedback-status`.
Statuses are `new`, `in_review`, `addressed`, `dismissed` and any transition is
allowed. Deleting is human-only; `dismissed` is the "not actionable" state.

**Questionnaires** are structured surveys the mobile SDKs render in-app. Read the shape
with `pubky-pulse:get-questionnaire`, the rolled-up distribution with
`pubky-pulse:get-questionnaire-analytics`, and individual answers with
`pubky-pulse:list-questionnaire-responses`. Unsubmitted drafts are included by default,
which is what makes the analytics show drop-off; `submitted_only: true` excludes them.

**Attachments** are files an SDK uploaded alongside an error event. List them per event,
issue or project; `pubky-pulse:get-attachment` returns metadata plus a signed download
URL that expires in 60 seconds — treat it as a secret and do not paste it into a
comment. Check headroom with `pubky-pulse:get-project-attachment-usage` (project quota
5 GB, per-user 250 MB) before asking anyone to re-run a scenario with a file attached.

**Jobs.** `pubky-pulse:trigger-job` accepts exactly two job types, both project scoped:
`stats_aggregate_daily` and `stats_aggregate_hourly`. Every other job type —
`issue_scan`, `app_version_sync`, `retention_cleanup`, `db_pruning`,
`soft_delete_cleanup`, `partition_creation`, `attachment_cleanup`, `issue_notify`,
`notification_deliver`, `notification_cleanup`, `questionnaire_draft_cleanup` — is
system scoped and the trigger route refuses it, so an issue scan cannot be forced; it
runs hourly. Trigger takes `team_id`, `job_type`, `project_id` and optional `params`
(`start`/`end` for a rollup backfill) and `notify`. `pubky-pulse:list-jobs` and
`pubky-pulse:get-job` need only team membership.

**Import keys.** `pubky-pulse:create-import-key` with an `app_id` returns a
`pulse_import_*` key, shown once. It is for `POST /v1/import`: up to 1000 events per
request, any historical timestamp, and a repeat `client_event_id` updates the existing
event rather than being skipped, so a corrected re-run is safe. Required event fields
are `message`, `level` and a UUID `session_id`. No MCP tool ingests events; the import
endpoint is an HTTP call the user's own script makes.

**Audit logs.** `pubky-pulse:list-audit-logs` needs `audit_logs:read` *and* a creator
who is the team owner, because the trail spans every project. Filter by
`resource_type`, `resource_id`, `actor_id`, `action` and a time range to answer "who
changed this app".

`references/feedback-and-questionnaires.md` has the questionnaire schema with all five
question types, the triage flow and how to read the analytics — read it when creating a
questionnaire or summarising responses.

`references/tool-catalog.md` lists all 62 tools by domain with their parameters,
required permission and traps — read it when you need a tool you have not used before,
or to confirm a parameter name instead of guessing.

## Output conventions

- **Print the resolved project name and id before the first write of a run.** It is the
  user's one chance to catch a wrong-project misfire while it is still harmless.
- **Never echo a `client_secret`, an import key or an attachment download URL unless the
  user asked for it.** Say "created, client key returned" and hand the value over only
  on request, or write it straight into the file that needs it. Nothing about a key
  belongs in a commit, a comment body or a chat log.
- Report writes as a short list of what changed, with ids — not a transcript of every
  call.
- When a call fails, quote the server's message. The three 403s and the 409 on a
  duplicate job each have a different fix, and a paraphrase loses it.

## Gotchas

1. `whoami` first, always — a stale or revoked key fails with 401 on the first real
   call, and that error is easier to read before you are three tools deep.
2. Reads span the whole team; writes need the key creator's ownership of that exact
   project. Check `access_level` on the `list-projects` row before planning changes.
3. `Missing permission` and `Requires project ownership` have completely different
   fixes. Retrying either one unchanged never helps.
4. Human-only operations return `403 This operation requires a user session` no matter
   how the key is provisioned. There is no permission that unlocks them.
5. Commenting is exempt from ownership, so a refused status change can still be
   documented — do that rather than dropping the finding.
6. `bundle_id` is immutable. Getting it wrong means a human deletes and recreates the
   app, which orphans the old app's data.
7. A `web` app with empty `allowed_origins` rejects every browser request. This is the
   number one reason "no events arrive".
8. `update-app` and `update-funnel` replace whole lists. Read first, then send the full
   intended list.
9. `allowed_origins` is rejected outright for `apple`, `android` and `backend` apps —
   sending the field at all is a 400.
10. A project name must not carry a platform suffix; the platform belongs on the app
    name. Both names are read by humans later and are painful to unpick.
11. `client_secret` comes back `null` for an app whose project the key's creator does
    not own. That is a permissions answer, not a missing key.
12. Metric and funnel definitions must exist **before** the SDK emits their slug.
13. Slugs are `^[a-z0-9-]+$`. The server rejects anything else; the SDKs quietly correct
    it and warn, which is worse — the data lands under a slug you did not plan.
14. A funnel `step_name` filter matches verbatim. A mismatched step is not an error, it
    is a step that reads zero forever.
15. `screen_name` is prefix-matched in `query-events` but exactly matched in a funnel
    step filter. The same string behaves differently in the two places.
16. Funnels exclude events with no `user_id` in both modes. Backend steps need
    `Pulse.withUser(id).step(...)`, which exists only where identity linking was opted
    into; anonymous-only, an empty backend funnel is expected and `Pulse.withSession(...)`
    correlation answers the question instead.
17. `data_mode` defaults to `production`. Anything a developer just did locally is
    `development` data and invisible until you ask for it.
18. `project_id` and `team_id` are mutually exclusive on `list-metrics`, `list-funnels`,
    `list-questionnaires` and `query-stats-bucketed`. Passing both, or neither, errors.
19. `list-user-locales` treats `team_id`, `project_id` and `app_id` the same way —
    narrow to one project or app, or the `shipped` gap flags come back `null`.
20. `app_id` overrides `project_id` on `query-events`. Passing both narrows to the app;
    it does not intersect.
21. `level` on `query-events` is an array, and there are exactly four levels — `info`,
    `debug`, `warn`, `error`. No `fatal`, no `critical`.
22. Long responses overflow the MCP limit. Pass `compact: true` and page with `cursor`
    rather than raising `limit`.
23. A pagination cursor encodes the query. Change `order` or a filter mid-walk and the
    pages stop lining up.
24. `query-stats-bucketed` drops the in-progress bucket by default, so "today" looks
    missing until you pass `excluding_current: false`.
25. `users` and `sessions` rollups are per-bucket distinct counts and cannot be summed
    across buckets — seven daily figures do not make a weekly one.
26. `trigger-job` accepts only `stats_aggregate_daily` and `stats_aggregate_hourly`.
    Every other job type is system-scoped and refused.
27. Only one run of a job type per project may be pending or running; a duplicate
    returns 409 with the existing run's id, which is usually the answer anyway.
28. Issues are produced by the hourly `issue_scan`, and it cannot be triggered. A new
    error is invisible as an *issue* for up to an hour, though the error *event* is
    queryable immediately.
29. `app_version_sync` is also hourly and also not triggerable, so `latest_app_version`
    can lag a fresh release.
30. Deleting a metric or funnel definition is a soft delete. Recreating the same slug
    restores the definition rather than starting clean.
31. `create-import-key` is the only key an agent may create, and its value is shown
    once. Losing it means creating another.
32. The import endpoint takes up to 1000 events per request and updates on a repeated
    `client_event_id`; the live ingest endpoint takes 100 and skips duplicates. Two
    endpoints, two key types, two behaviours.
33. Questionnaire slugs are immutable — the SDK call site references them. A rename
    means a new questionnaire.
34. Deleting a questionnaire, a response, a feedback item or an attachment is
    human-only. Use `dismissed` for feedback and responses that are not actionable.
35. Questionnaire responses include unsubmitted drafts by default, in both the list and
    the analytics. A response count that looks too high is usually drafts.
36. Editing a questionnaire schema is allowed at any time; each submitted response keeps
    its own `schema_snapshot`, so historical answers still render.
37. An attachment download URL lives 60 seconds and is unauthenticated. Fetch it when
    you are ready to use it, and never store it.
38. Attachment uploads that exceed a quota fail with 413 while the event itself still
    posts — a missing attachment does not mean a missing error.
39. `list-audit-logs` needs the key's creator to be the team owner. A 403 here is about
    who they are, not about the key.
40. Every write lands in the audit log with this key as the actor. There is no quiet
    change.

## References

- `references/tool-catalog.md` — read when you need a tool's exact parameters, required
  permission or return shape.
- `references/setup-recipes.md` — read when creating a project, apps, metrics, funnels,
  questionnaires or an import key from scratch.
- `references/query-recipes.md` — read when a question needs a query shaped beyond a
  single filter.
- `references/feedback-and-questionnaires.md` — read when creating a questionnaire or
  triaging feedback and survey responses.
- `references/access-model.md` — read when a call returns 403 or a key looks
  under-permissioned.
- `scripts/check-mcp-config.sh` — run when `pubky-pulse:whoami` is unavailable, to find
  an existing configuration and its endpoint URL.
