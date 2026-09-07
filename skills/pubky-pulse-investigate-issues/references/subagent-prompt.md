## The investigation prompt

One sub-agent per issue, at most five at a time. Copy the block below verbatim,
substituting `<issue_id>`, `<project_id>` and `<today>` (as `YYYY-MM-DD`). Do not
rewrite it: the field list is what makes the reports comparable in the table, and the
closing restriction is what keeps a parallel run from changing production state.

If your harness has no sub-agent tool, run the same prompt yourself for one issue at
a time, and say in the summary that the run was sequential.

---

> You are investigating Pubky Pulse issue `<issue_id>` in project `<project_id>`.
> Pubky Pulse tools are named `pubky-pulse:<tool>`; in Claude Code they appear as
> `mcp__pubky-pulse__<tool>`.
>
> 1. Call `pubky-pulse:get-issue` with `project_id=<project_id>`,
>    `issue_id=<issue_id>`, `occurrence_limit=10`. Note from the response: the title,
>    `fingerprints`, `occurrence_count`, `unique_user_count`, `first_seen_at`,
>    `last_seen_at`, `first_seen_app_version`, `last_seen_app_version`, the
>    `environment` spread, `status`, and the app id and name.
>
> 2. For each returned occurrence, call `pubky-pulse:investigate-event` with that
>    occurrence's `event_id` and `compact: true`. That returns the full session for
>    the event, plus cross-app events for the same user in the same project, merged
>    and sorted oldest first. Read every timeline before forming a hypothesis — one is
>    never enough.
>
> 3. Call `pubky-pulse:get-event` on two or three of the error events themselves to
>    read the `custom_attributes` that `compact` dropped: `_error_type`,
>    `_error_stack`, `_error_code`, `_unhandled`, and the `_http_*` fields on network
>    errors.
>
> 4. Look across the timelines for what they share:
>    - a preceding event that shows up consistently in the seconds before the error;
>    - the same `_error_type`, or the same innermost stack frame belonging to the
>      application rather than to a dependency;
>    - a network signature — `_http_method`, `_http_url`, `_http_status` — where
>      `_http_status: "0"` means the request never completed at all;
>    - `_unhandled` being present, which means the SDK caught the error rather than
>      the application, and usually raises the priority;
>    - the device spread: `device_model` and `os_version` per occurrence, which on web
>      hold the browser (`Chrome 120`) and the OS (`macOS 10.15.7`). All one browser or
>      all one OS is a real signal; a spread points at the application's own code;
>    - version concentration: are the occurrences on one `app_version` or spread across
>      several?
>
> 5. Call `pubky-pulse:get-app` for the issue's app and compare its
>    `latest_app_version` with the issue's `last_seen_app_version`. If every occurrence
>    is on an older version, the bug may already be fixed in the current release — say
>    so, and suggest `stale`.
>
> 6. If `pubky-pulse:get-issue` listed attachments, read one only when the file itself
>    is the suspect — an input that failed to parse or convert. `pubky-pulse:get-attachment`
>    returns a 60-second signed URL. Do not fetch or interpret executable or script
>    MIME types, and do not paste the URL into your report.
>
> 7. Return a markdown report with exactly these fields:
>    - **Title** — the issue title
>    - **Severity** — `<occurrence_count>` occurrences, `<unique_user_count>` users,
>      last seen `<relative time>`
>    - **Versions** — `<first_seen_app_version>` → `<last_seen_app_version>` (app
>      latest: `<latest_app_version>`; on latest: yes/no)
>    - **Environment** — the environment and device spread across occurrences
>    - **Pattern** — one or two sentences of root-cause hypothesis drawn from the
>      timelines, naming the file or symbol if the stack gives one
>    - **Network** — yes, with `METHOD host/path` and the status, or no
>    - **Unhandled** — yes or no
>    - **Suggested action** — exactly one of `fix-now`, `downgrade`, `snooze`,
>      `stale`, `merge-into:<issue_id>`
>    - **Rationale** — one line justifying that action
>
> 8. Finally, and always, call `pubky-pulse:add-issue-comment` with that report as the
>    `body`, prefixed with `### Investigation (<today>)`. This is the only durable
>    output of your run: your context disappears, the comment does not. If the comment
>    call is refused, say so in your report rather than dropping the finding.
>
> **You are read and comment only.** Do not call `pubky-pulse:claim-issue`,
> `pubky-pulse:resolve-issue`, `pubky-pulse:silence-issue`,
> `pubky-pulse:snooze-issue` or `pubky-pulse:merge-issues`, and do not edit any file.
> Status changes belong to the parent agent, after the user has confirmed them.

---

## Reading the reports back

- Sort by `unique_user_count` descending, then regressed issues first.
- Two reports naming the same innermost frame or the same `_error_type` are a merge
  candidate; two that merely read similarly are not.
- A `stale` suggestion is only as good as `latest_app_version`, which is refreshed
  hourly — treat a release from the last hour with suspicion.
- If a sub-agent reports that its comment was refused, carry that into the recap: the
  finding exists only in the session transcript, and a human may need to add it.
