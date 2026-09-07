## Contents

- [How to read this](#how-to-read-this)
- [Auth](#auth)
- [Projects](#projects)
- [Apps](#apps)
- [Events](#events)
- [Metrics](#metrics)
- [Funnels](#funnels)
- [Issues](#issues)
- [Feedback](#feedback)
- [Questionnaires](#questionnaires)
- [Attachments](#attachments)
- [Time-series rollups](#time-series-rollups)
- [Jobs](#jobs)
- [Audit logs](#audit-logs)
- [Permission map](#permission-map)

## How to read this

All 62 tools, by domain. Write `pubky-pulse:<tool>` in prose; Claude Code exposes
them as `mcp__pubky-pulse__<tool>`.

Every write listed as needing ownership means: the permission **and** the human who
created this key currently owning the target project. Reads need only the permission,
and reach every project in the team. Tools marked **human-only** always return
`403 This operation requires a user session` to an agent key.

Shared conventions: ids are UUIDs; `since` / `until` take `30s|30m|1h|7d|1w` or ISO
8601; `data_mode` is `production` (default) | `development` | `all`; list tools return
`{ ..., cursor, has_more }` and default to 50 rows.

## Auth

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `whoami` | — | any | Identity, team (`team.id`), key type and permission list. Call it first every run. |
| `create-import-key` | `app_id`, `name?` | `apps:write` + ownership | Returns a `pulse_import_*` key **shown once**. The only key an agent may create; listing, updating and revoking keys are human-only. |

## Projects

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-projects` | `team_id?` | `projects:read` | Rows carry `owners` and `access_level` (`owner` \| `viewer`) for this key's creator. `viewer` means writes will 403. |
| `get-project` | `project_id` | `projects:read` | Includes a nested `apps` array; a nested `client_secret` is `null` unless the creator owns the project. |
| `create-project` | `team_id`, `name`, `slug`, `retention_days_events?`, `retention_days_metrics?`, `retention_days_funnels?` | `projects:write` | Makes the creator the project's first owner, so the next call can write to it. Name is the bare product name. |
| `update-project` | `project_id`, `name?`, `color?`, `retention_days_*?`, `attachment_user_quota_bytes?`, `attachment_project_quota_bytes?` | `projects:write` + ownership | At least one field besides the id. `null` on a retention or quota field resets it to the default. `color` is `#RRGGBB`. |

Deleting a project, and changing its owner list, are **human-only** and have no tool.

## Apps

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-apps` | `team_id?` | `apps:read` | Returns `client_secret` (null without ownership), `allowed_origins`, `latest_app_version`, `latest_app_version_updated_at`. |
| `get-app` | `app_id` | `apps:read` | Same shape for one app. Read this before `update-app` to preserve the origin list. |
| `create-app` | `name`, `platform`, `project_id`, `bundle_id?`, `allowed_origins?` | `apps:write` + ownership | `platform` ∈ `apple`, `android`, `web`, `backend`. `bundle_id` required except on `backend`, immutable after creation. `allowed_origins` is `web`-only; sending it elsewhere is a 400. Returns `client_secret`. |
| `update-app` | `app_id`, `name?`, `allowed_origins?` | `apps:write` + ownership | At least one of the two. `allowed_origins` **replaces the whole list**. `bundle_id` and `platform` are immutable. |
| `list-app-users` | `app_id`, `search?`, `is_anonymous?` (`"true"`/`"false"` strings), `data_mode?`, `cursor?`, `limit?` | `apps:read` | A user's dev/prod flag comes from their client (non-backend) events. |
| `list-user-locales` | `team_id?`, `project_id?`, `app_id?`, `data_mode?` | `apps:read` | Localisation demand. The three scope parameters are mutually exclusive; narrow to one project or app or the `shipped` gap flags are `null`. |

Deleting an app is **human-only**. `latest_app_version` is refreshed hourly by a
system job and cannot be forced.

## Events

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `query-events` | `project_id?`, `app_id?`, `level?` (array), `user_id?`, `session_id?`, `environment?`, `screen_name?`, `device_model?`, `os_version?`, `since?`, `until?`, `cursor?`, `limit?`, `data_mode?`, `order?`, `compact?` | `events:read` | `app_id` wins over `project_id`. `screen_name` is exact-or-prefix. `order: "asc"` walks a session forwards. Ad-hoc searches only — for an issue occurrence use `investigate-event`. |
| `get-event` | `event_id` | `events:read` | Full record including `custom_attributes` (stack trace, error type, HTTP fields). |
| `investigate-event` | `event_id`, `window_minutes?` (default 5), `data_mode?`, `compact?` | `events:read` | The breadcrumb builder: the whole session, or ±window when the event has none, plus cross-app events for the same user, merged and sorted ascending. Returns `{ events, target_event_id, total }`. |

Levels are exactly `info`, `debug`, `warn`, `error`. Reserved attribute keys start
with `_` (`_error_type`, `_error_stack`, `_unhandled`, `_http_*`, `_page_url`) and are
SDK-owned — read them, never invent them.

## Metrics

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-metrics` | `project_id` \| `team_id` | `metrics:read` | Mutually exclusive, one required. `team_id` spans every accessible project and each row carries its `project_id`. |
| `get-metric` | `project_id`, `slug` | `metrics:read` | |
| `create-metric` | `project_id`, `name`, `slug`, `description?`, `documentation?`, `schema_definition?`, `aggregation_rules?` | `metrics:write` + ownership | Slug is `^[a-z0-9-]+$`. Must exist before the SDK emits it. |
| `update-metric` | `project_id`, `slug`, `name?`, `description?`, `documentation?`, `schema_definition?`, `aggregation_rules?` | `metrics:write` + ownership | |
| `delete-metric` | `project_id`, `slug` | `metrics:write` + ownership | Soft delete — creating the same slug again restores the definition. |
| `query-metric` | `project_id`, `slug`, `since?`, `until?`, `app_id?`, `app_version?`, `device_model?`, `os_version?`, `user_id?`, `environment?`, `group_by?`, `data_mode?` | `metrics:read` | `group_by` ∈ `app_id`, `app_version`, `device_model`, `os_version`, `environment`, `time:hour`, `time:day`, `time:week`. Returns counts per phase, success rate, avg/p50/p95/p99, unique users, error breakdown. |
| `list-metric-events` | `project_id`, `slug`, `phase?`, `tracking_id?`, `user_id?`, `environment?`, `since?`, `until?`, `cursor?`, `limit?`, `data_mode?` | `metrics:read` | `phase` ∈ `start`, `complete`, `fail`, `cancel`, `record`. |

## Funnels

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-funnels` | `project_id` \| `team_id` | `funnels:read` | Mutually exclusive, one required. |
| `get-funnel` | `project_id`, `slug` | `funnels:read` | Includes the ordered steps. |
| `create-funnel` | `project_id`, `name`, `slug`, `description?`, `steps` | `funnels:write` + ownership | Up to 20 steps, each `{ name, event_filter: { step_name?, screen_name? } }`. `step_name` matches `Pulse.step("…")` verbatim; `screen_name` is an exact match. |
| `update-funnel` | `project_id`, `slug`, `name?`, `description?`, `steps?` | `funnels:write` + ownership | `steps` replaces the whole list. |
| `delete-funnel` | `project_id`, `slug` | `funnels:write` + ownership | Soft delete; funnel events are kept. |
| `query-funnel` | `project_id`, `slug`, `since?` (default 30d), `until?`, `app_id?`, `app_version?`, `environment?`, `mode?`, `group_by?`, `data_mode?` | `funnels:read` | `mode` ∈ `open` (default) \| `closed`. `group_by` ∈ `environment` \| `app_version` only. Events without `user_id` are excluded in both modes. |

## Issues

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-issues` | `project_id`, `status?`, `app_id?`, `is_dev?`, `cursor?`, `limit?` | `issues:read` | Sorted by most recent activity. Sort by `unique_user_count` yourself for severity. Statuses: `new`, `in_progress`, `resolved`, `silenced`, `regressed`, `snoozed`. |
| `get-issue` | `project_id`, `issue_id`, `occurrence_cursor?`, `occurrence_limit?` | `issues:read` | Occurrences (one per session), comments, fingerprints, linked attachments. Walk further pages with `occurrence_cursor` while `occurrence_has_more`. |
| `resolve-issue` | `project_id`, `issue_id`, `version` | `issues:write` + ownership | `version` is required and powers regression detection. Never invent one. |
| `silence-issue` | `project_id`, `issue_id` | `issues:write` + ownership | Terminal: stays silent even if it keeps happening. |
| `snooze-issue` | `project_id`, `issue_id` | `issues:write` + ownership | Auto-reverts to `new` on the next occurrence. |
| `reopen-issue` | `project_id`, `issue_id` | `issues:write` + ownership | Back to `new`. |
| `claim-issue` | `project_id`, `issue_id` | `issues:write` + ownership | Sets `in_progress`; visible to the team. |
| `merge-issues` | `project_id`, `target_issue_id`, `source_issue_id` | `issues:write` + ownership | Moves fingerprints, occurrences and comments to the target and deletes the source. Not reversible. |
| `list-issue-comments` | `project_id`, `issue_id` | `issues:read` | |
| `add-issue-comment` | `project_id`, `issue_id`, `body` (markdown) | `issues:write`, **no ownership needed** | Authored by this exact key; no other key can edit or delete it. |

## Feedback

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-feedback` | `project_id`, `status?`, `app_id?`, `is_dev?`, `cursor?`, `limit?` | `feedback:read` | Statuses `new`, `in_review`, `addressed`, `dismissed`. |
| `get-feedback` | `project_id`, `feedback_id` | `feedback:read` | Includes comments and the `session_id` that links to the user's timeline. |
| `update-feedback-status` | `project_id`, `feedback_id`, `status` | `feedback:write` + ownership | Any transition allowed. |
| `add-feedback-comment` | `project_id`, `feedback_id`, `body` | `feedback:write`, **no ownership needed** | |

Deleting feedback is **human-only**; `dismissed` is the "not actionable" state.

## Questionnaires

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-questionnaires` | `project_id` \| `team_id`, `app_id?`, `is_active?`, `data_mode?`, `cursor?`, `limit?` | `questionnaires:read` | `app_id` and `cursor` apply only with `project_id`. |
| `get-questionnaire` | `project_id`, `questionnaire_id`, `data_mode?` | `questionnaires:read` | Schema plus `response_count`, `submitted_count`, `last_response_at`. |
| `create-questionnaire` | `project_id`, `slug`, `name`, `description?`, `schema`, `app_id?`, `is_active?` | `questionnaires:write` + ownership | `schema` is `{ version: 1, questions: [...] }`, 1–30 questions. Slug immutable after creation. |
| `update-questionnaire` | `project_id`, `questionnaire_id`, `name?`, `description?`, `schema?`, `app_id?`, `is_active?` | `questionnaires:write` + ownership | Schema edits apply going forward; submitted responses keep their snapshot. |
| `delete-questionnaire` | `project_id`, `questionnaire_id` | **human-only** | Responses are preserved. |
| `list-questionnaire-responses` | `project_id`, `questionnaire_id`, `status?`, `app_id?`, `is_dev?`, `data_mode?`, `submitted_only?`, `cursor?`, `limit?` | `questionnaires:read` | Drafts included by default; `status: "draft"` isolates them, `submitted_only: true` excludes them. |
| `get-questionnaire-response` | `project_id`, `questionnaire_id`, `response_id` | `questionnaires:read` | Drafts have `submitted_at: null` and `schema_snapshot: null`. |
| `update-questionnaire-response-status` | `project_id`, `questionnaire_id`, `response_id`, `status` | `questionnaires:write` + ownership | Same four statuses as feedback. |
| `add-questionnaire-response-comment` | `project_id`, `questionnaire_id`, `response_id`, `body` | `questionnaires:write`, **no ownership needed** | |
| `get-questionnaire-analytics` | `project_id`, `questionnaire_id`, `is_dev?`, `data_mode?`, `submitted_only?` | `questionnaires:read` | Per-question distribution; see `references/feedback-and-questionnaires.md`. |

Deleting an individual response is **human-only** and has no tool.

## Attachments

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-attachments` | `project_id?`, `event_id?`, `event_client_id?`, `issue_id?`, `cursor?`, `limit?` | `events:read` | Most issues have none — attachments are a limited resource. |
| `get-attachment` | `attachment_id` | `events:read` | Metadata plus a 60-second signed `download_url`. Unauthenticated while it lives: share narrowly, never store. Do not try to interpret executable or script MIME types. |
| `delete-attachment` | `attachment_id` | **human-only** | Soft delete; the cleanup job removes the file 7 days later. |
| `get-project-attachment-usage` | `project_id`, `user_id?` | `events:read` | Project quota defaults to 5 GB, per-user to 250 MB. Check before asking for a re-run with a file. |

## Time-series rollups

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `query-stats-bucketed` | `kind`, `grain`, `project_id` \| `team_id`, `app_id?`, `days?`, `hours?`, `from?`, `to?`, `excluding_current?`, `data_mode?`, `slug?` | depends on `kind` — see below | `kind` ∈ `events`, `users`, `sessions`, `metric_completions`, `funnel_completions`, `questionnaire_responses`. `grain` ∈ `daily`, `hourly`. Scope is exactly one of project or team. Returns a zero-padded `data: [{bucket, value}]`. |

The permission follows the `kind`: `events`, `users` and `sessions` need
`events:read`; `metric_completions` needs `metrics:read`; `funnel_completions` needs
`funnels:read`; `questionnaire_responses` needs `questionnaires:read`. So a key can
chart events and still be refused a metric series.

Buckets are UTC. The in-progress bucket is dropped unless `excluding_current: false`.
`users` and `sessions` are per-bucket distincts and are not summable. These tables are
exempt from retention pruning, so they outlive the raw events behind them. Backfilling
older ranges is a rollup job — see Jobs.

## Jobs

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-jobs` | `team_id`, `job_type?`, `status?`, `project_id?`, `since?`, `until?`, `cursor?`, `limit?` | `jobs:read` | `status` ∈ `pending`, `running`, `completed`, `failed`, `cancelled`. |
| `get-job` | `run_id` | `jobs:read` | Progress (`{processed, total, message}`) and result. |
| `trigger-job` | `team_id`, `job_type`, `project_id`, `params?`, `notify?` | `jobs:write` + ownership | Only `stats_aggregate_daily` and `stats_aggregate_hourly` are triggerable; everything else is system-scoped and refused. `params` takes `start`/`end` (`YYYY-MM-DD` daily, ISO hour hourly) and `project_id` for a backfill. Duplicate run → 409. |
| `cancel-job` | `run_id` | `jobs:write` + ownership | Running jobs only; cancellation is cooperative. |

System jobs and their schedules, for reading `list-jobs` output: `issue_scan` hourly,
`issue_notify` hourly at :05, `app_version_sync` hourly at :15, `stats_aggregate_hourly`
at :05, `stats_aggregate_daily` at 00:30 UTC, `retention_cleanup` 02:00,
`soft_delete_cleanup` 03:00, `partition_creation` 04:00, `attachment_cleanup` 05:00,
`notification_cleanup` 06:00, `questionnaire_draft_cleanup` 06:30, `db_pruning` hourly,
`notification_deliver` on demand.

## Audit logs

| Tool | Parameters | Permission | Notes |
|---|---|---|---|
| `list-audit-logs` | `team_id`, `resource_type?`, `resource_id?`, `actor_id?`, `action?`, `since?`, `until?`, `cursor?`, `limit?` | `audit_logs:read` + creator is the team owner | `action` ∈ `create`, `update`, `delete`. `resource_type` ∈ `app`, `project`, `project_owner`, `api_key`, `team`, `team_member`, `metric_definition`, `funnel_definition`, `user`, `job_run`, `issue`, `feedback`, `questionnaire`, `questionnaire_response`. Entries carry `actor_type` (`user`, `api_key`, `system`). |

## Permission map

| Permission | Tools |
|---|---|
| `events:read` | query-events, get-event, investigate-event, list-attachments, get-attachment, get-project-attachment-usage, query-stats-bucketed for `events` / `users` / `sessions` |
| `projects:read` | list-projects, get-project |
| `projects:write` | create-project, update-project |
| `apps:read` | list-apps, get-app, list-app-users, list-user-locales |
| `apps:write` | create-app, update-app, create-import-key |
| `metrics:read` | list-metrics, get-metric, query-metric, list-metric-events, query-stats-bucketed for `metric_completions` |
| `metrics:write` | create-metric, update-metric, delete-metric |
| `funnels:read` | list-funnels, get-funnel, query-funnel, query-stats-bucketed for `funnel_completions` |
| `funnels:write` | create-funnel, update-funnel, delete-funnel |
| `issues:read` | list-issues, get-issue, list-issue-comments |
| `issues:write` | resolve-issue, silence-issue, snooze-issue, reopen-issue, claim-issue, merge-issues, add-issue-comment |
| `feedback:read` | list-feedback, get-feedback |
| `feedback:write` | update-feedback-status, add-feedback-comment |
| `questionnaires:read` | list-questionnaires, get-questionnaire, get-questionnaire-analytics, list-questionnaire-responses, get-questionnaire-response, query-stats-bucketed for `questionnaire_responses` |
| `questionnaires:write` | create-questionnaire, update-questionnaire, update-questionnaire-response-status, add-questionnaire-response-comment |
| `jobs:read` | list-jobs, get-job |
| `jobs:write` | trigger-job, cancel-job |
| `audit_logs:read` | list-audit-logs |
