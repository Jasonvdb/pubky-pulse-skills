---
name: pubky-pulse-investigate-issues
description: >-
  Triages Pubky Pulse issues: inventories open and regressed issues, claims one, reads
  occurrence breadcrumbs across sessions and apps, finds the pattern behind them, then
  fixes, snoozes, merges or resolves each at a real fix version. Use when asked what is
  broken in production, what errors or crashes users are hitting, to investigate an error
  spike or a specific Pubky Pulse issue, or to work through the issue inbox. Not for adding
  instrumentation in the first place (see pubky-pulse-instrument) or general queries and
  project admin (see pubky-pulse-operations).
license: MIT
compatibility: >-
  Requires the pubky-pulse MCP server connected with an agent key; without it there are no
  issues to read. Any harness that reads SKILL.md.
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

## What this skill does

Pubky Pulse clusters error events into **issues** by fingerprint, hourly. This skill
turns "scroll the list, open each one, read thirty occurrences, cross-reference" into
one pass: detect the project, pull every open and regressed issue, investigate them in
parallel, comment the findings back onto each issue, then present one ranked table and
walk through fixing, downgrading, snoozing or merging the ones the user picks.

## Guardrails

**Read-mostly.** Investigation writes exactly one kind of thing: a comment. Comments
are always allowed — they need `issues:write` on a readable project and no ownership —
so findings are never lost to a permissions problem.

**Every status change waits for confirmation.** `claim-issue`, `resolve-issue`,
`silence-issue`, `snooze-issue` and `merge-issues` happen only after the user picks
that option. Never auto-claim, auto-resolve, auto-silence, auto-snooze or auto-merge,
and never bump an app version without being asked to.

**Sub-agents never change status.** They read, they comment, they report. The parent
agent owns every transition, after the user's answer.

**Resolve needs a real fix version.** The server requires one because it powers
regression detection. If there is no version to give, snooze or silence instead — an
invented version silently disables regression detection for that issue.

**Print the resolved project name and id before any state changes.** It is the one
chance to catch a wrong-project run while it is still harmless.

**Asking the user.** Whenever a step says to ask the user something, present the
choices as selectable options using your harness's structured question tool rather
than making them type a free-text reply — in Claude Code that tool is
`AskUserQuestion`; Codex and other agents may expose an equivalent. List the
recommended option first. If your harness has no such tool, ask in plain text.
Every question has a default: if no answer comes back, take the recommended option,
continue, and say which default you took in the final report.

Each step below names the question header (≤12 characters) and the exact option
labels. Keep them — they are what makes a long triage session readable afterwards.

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

There are no issues to read without the server, so stop there rather than guessing at
what production might be doing.

## Step 1 — Determine the project

Take the first heuristic that hits. Do not cache the answer across runs — the user may
have changed directory between them.

**a. The client key in the code.** Grep for a configured key and match it to an app:

```sh
grep -rEoh 'pulse_client_[A-Za-z0-9]+' --include='*.ts' --include='*.js' --include='*.tsx' . | head -5
grep -rEoh 'pulse_client_[A-Za-z0-9]+' --include='*.swift' --include='*.kt' . | head -5
grep -rhE 'PULSE_API_KEY|PULSE_CLIENT_KEY|pulse_client_' .env* 2>/dev/null | head -5
```

Then `pubky-pulse:list-apps` and find the app whose `client_secret` matches. Its
`project_id` is the answer.

**b. The configure call.** `grep -rn 'Pulse.configure' .` finds the call site and
usually the `bundleId` beside it, even when the key itself is in an environment
variable.

**c. The bundle identifier.** Match the repository's own identifier against
`pubky-pulse:list-apps` → `apps[].bundle_id`. `references/project-detection.md` has
the per-platform commands for reading it out of an Xcode project, a Gradle file, a
`package.json` or a web build config.

**d. One project only.** If `pubky-pulse:list-projects` returns exactly one project,
use it and say so.

**e. Ask.** With 2–4 projects, ask directly (header `"Project"`, one option per
project labelled `<Name> (<slug>)`). With five or more, list them all in plain text
first, then ask with the three most likely — recent activity first — and let the user
name any other in the free-text option.

Then decide the app filter. A multi-app project usually wants all apps; if the
detection in (a)–(c) pointed at one specific app, use it and say which. Otherwise ask
(header `"App filter"`, options: each app name, plus `All apps (Recommended)`).

Print the resolved project name and id before going further.

## Step 2 — Pull the inventory

Two calls, because `status` filters one value at a time:

```text
pubky-pulse:list-issues  { project_id, status: "new",       is_dev: false, [app_id] }
pubky-pulse:list-issues  { project_id, status: "regressed", is_dev: false, [app_id] }
```

Follow `cursor` until `has_more` is false. `is_dev: false` keeps the run on production
data, which is what "what is broken" means; include dev issues only if the user asks.
Leave `in_progress` out unless asked — somebody is already on those.

Print a one-line preview before doing any work:

```text
Found 14 issues to investigate in Lofi:
  11 new
   3 regressed (thought fixed, came back)
   (4 in_progress excluded)
```

A regressed issue usually wins the priority race: it was believed fixed and returned
in a newer version.

**Zero issues → say "nothing open to investigate" and stop.** Do not spawn anything,
and do not go hunting through `pubky-pulse:query-events` for errors that have not been
clustered yet — mention instead that the hourly scan may not have run since the most
recent error.

## Step 3 — Investigate in parallel

Use your harness's sub-agent tool — Agent or Task in Claude Code — to run one
investigator per issue. **Cap concurrency at five.** With more than five issues,
launch five, wait for all of them, then launch the next five. If your harness has no
sub-agent tool, run the same prompt yourself, one issue at a time, and say that the
run is sequential.

The prompt to give each sub-agent is in `references/subagent-prompt.md` — copy it
verbatim, substituting the issue id, the project id and today's date. It ends by
telling the sub-agent to post its report as a comment and to change nothing else; that
restriction is load-bearing, so do not paraphrase it away.

Each sub-agent returns a short markdown report with a suggested action. Collect them
and keep them for the table.

## Step 4 — The breakdown table

One table, sorted by users affected descending, then regressed first. Cap it at 20
rows and list the rest below as "Also open".

```text
| # | Issue                                         | Users | Occ. | Versions       | Suggested | Why |
|---|-----------------------------------------------|------:|-----:|----------------|-----------|-----|
| 1 | Regressed: crash in SignatureRenderer.export  |    42 |  318 | 1.4.0 (latest) | fix-now   | back on the current release, no fallback |
| 2 | Network error: POST api.acme.com/v1/receipts  |    28 |  121 | 1.3.5–1.4.0    | downgrade | SDK retries, UX shows a toast |
| 3 | TypeError: cannot read 'id' of undefined      |    14 |   44 | 1.4.0 (latest) | fix-now   | unhandled, top of session |
| 4 | EAI_AGAIN getaddrinfo api.x.com               |     6 |   12 | 1.3.0 only     | stale     | every occurrence on an old version |
```

Mark regressed rows plainly in the title column. Suggested actions are `fix-now`,
`downgrade`, `snooze`, `stale` (already fixed in a later release) and
`merge-into:<row>`.

## Step 5 — Recommend, then ask

Three to six bullets under the table:

- the top `fix-now` candidate and why it beats the others;
- any batch of `downgrade` candidates that can be handled in one pass;
- any `stale` batch that can be resolved at the app's current `latest_app_version`;
- any pair the sub-agents flagged as the same root cause, as a merge candidate.

Then ask (header `"First issue"`), recommended option first:

- `Fix #<n> — <short title> (Recommended)`
- `Batch downgrade <N> network issues` — only when there are at least two
- `Batch resolve <N> stale issues at v<latest>` — only when there are at least two
- `Merge #<a> into #<b>` — only when a clear duplicate pair exists
- `Stop for now`

Four options is the practical ceiling: keep the top fix plus the two biggest batches
plus `Stop for now`, and let anything else arrive through the free-text option as a
row number.

Nothing has changed state yet. This is the checkpoint.

## Step 6 — Fix flow

1. **Claim** (header `"Claim?"`): `Claim and start (Recommended)` →
   `pubky-pulse:claim-issue`, which sets `in_progress` and is visible to the team;
   `Investigate without claiming`; `Cancel`.
2. **Find the call site.** Re-read the sub-agent's `_error_type` and `_error_stack`,
   then grep for the innermost frame that belongs to this repository rather than to a
   dependency. `references/triage-actions.md` has the per-language patterns.
3. **Propose the fix**, apply it, and stop there. Do not claim the tests pass — let
   the user run their own verification.
4. **Version** (header `"Version"`): read the current version from the project's own
   version file (`references/triage-actions.md` lists where it lives per platform),
   then offer `Bump to <next patch> (Recommended)`, `Bump to <next minor>`, and
   `Don't bump — resolve once shipped`. Wait for an explicit yes before editing a
   version file.
5. **Resolve** (header `"Resolve?"`): `Resolve at v<Y> (Recommended)` →
   `pubky-pulse:resolve-issue` with that version; `Snooze instead`; `Silence instead`;
   `Cancel` (leaves it claimed).

Resolve at the version the fix **ships in**, not the version it was found in.
Resolving at the current released version tells the regression detector the bug was
fixed in code users already have, so every later occurrence looks like a fresh issue
instead of a regression.

## Step 7 — Downgrade flow

For issues where the SDK already retries and the UX handles the failure — typically
network errors with a visible toast — the error level itself is the bug. Ask (header
`"How to fix"`):

- `Downgrade the log call + resolve (Recommended)` — change `Pulse.error(...)` to
  `Pulse.warn(...)` at that call site so future occurrences never cluster into an
  issue, then resolve at the app's `latest_app_version`. Warnings stay queryable; only
  issue clustering stops.
- `Silence in the dashboard only` — `pubky-pulse:silence-issue`, terminal, occurrences
  still recorded.
- `Treat as a real bug` — fall through to Step 6.
- `Skip — leave open`.

Downgrading is a code change like any other: same version bump, same confirmation
before a file is edited.

## Step 8 — Snooze flow

For a single occurrence, one user, no consistent pattern (header `"Snooze?"`):

- `Snooze — re-alert if it recurs (Recommended)` — `pubky-pulse:snooze-issue`. It
  reverts to `new` on the very next occurrence, so the assumption gets tested for you.
- `Silence — stay silent even if it recurs` — `pubky-pulse:silence-issue`, terminal;
  for infrastructure blips already accepted.
- `Investigate anyway` — Step 6.
- `Skip — leave open`.

Snooze is the honest default when there is nothing to fix yet: it claims no fix and
costs nothing if the guess turns out wrong.

## Step 9 — Merge duplicates

When two issues are the same underlying bug, merge the newer into the **older** so the
history survives. Merges are not reversible, so confirm (header `"Merge?"`):

- `Merge #<newer> into #<older> (Recommended)` — `pubky-pulse:merge-issues` with
  `target_issue_id` = older, `source_issue_id` = newer. Fingerprints, occurrences and
  comments move; the source is deleted.
- `Keep separate — different bugs` — no change, and comment the reasoning on both so
  the next reader does not re-propose it.
- `Pick a different target` — take the id from the free-text option.

Merge only on evidence the sub-agents produced: an overlapping stack, the same call
site, the same root cause. Similar wording alone is not enough — browser phrasings are
already canonicalised before fingerprinting, so two issues that survived that are
usually genuinely different.

## Step 10 — Recap

Close with a compact summary, whatever the user did:

```text
Session summary for Lofi (project 8f3e…):
  Investigated:   14  (one comment posted per issue)
  Claimed:         2  → PP-A12, PP-B7
  Resolved:        1  → PP-A12 at v1.4.1
  Silenced:        3  → PP-N1, PP-N4, PP-N5
  Snoozed:         1  → PP-S2
  Merged:          1  → PP-D3 into PP-D1
  Left open:       6
  Defaults taken:  app filter = all apps (no answer)
```

Name any question that fell through to its default, and any status change that was
refused, with the reason.

## Gotchas

1. Issues come from an hourly scan that cannot be triggered. An error from five
   minutes ago is a queryable *event* but not yet an *issue*.
2. `is_dev: true` issues exist and never notify anyone. Filter them out unless the
   user is debugging their own machine.
3. `list-issues` sorts by recent activity, not severity. Sort by `unique_user_count`
   yourself.
4. `status` takes one value per call, so open work is two calls: `new` and
   `regressed`.
5. Occurrences are one per **session**, not one per error. A tight loop that threw a
   thousand times is one occurrence.
6. Error events within five seconds of each other in one session are aliased onto a
   single issue — a loader throwing, a caller logging it, and an `op.fail()` are one
   issue by design.
7. `resolve-issue` requires a version and the server rejects the call without one.
   Never invent one to get past it.
8. Resolve at the version the fix ships in. Resolving at the version it was found in
   makes every later occurrence look like a fresh issue.
9. `appVersion` must be monotonic for regression detection to work. A git SHA sorts
   alphabetically, which is worse than no version at all.
10. Silence is terminal; snooze auto-reverts to `new` on the next occurrence. The
    wrong choice either hides a live bug or re-alerts on a dead one.
11. Merge is irreversible through the API and deletes the source issue.
12. Merge into the **older** issue so its history and first-seen version survive.
13. `investigate-event` is the breadcrumb tool, not `query-events`: it pulls the whole
    session plus cross-app events for the same user, already sorted.
14. Pass `compact: true` on every breadcrumb call. Full events overflow the MCP
    response limit on any session of reasonable length.
15. `compact` drops `custom_attributes`, so fetch the one error event with
    `pubky-pulse:get-event` when you need the stack trace.
16. One occurrence is never enough. Read several — the pattern is what identifies the
    bug, and a single timeline usually points at a symptom.
17. `get-issue` paginates occurrences separately: keep going while
    `occurrence_has_more`, passing `occurrence_cursor`.
18. Web error messages are canonicalised across browsers before fingerprinting, so a
    Chrome-worded title does not mean a Chrome-only bug. Compare `device_model` across
    occurrences instead — on web that field holds the browser.
19. All-one-browser or all-one-OS across occurrences is a real signal. A spread points
    at your own code.
20. Network issues discriminate on `METHOD host/templated-path`, so a third-party
    outage and your own backend failing are separate issues by construction.
21. `_unhandled` in the attributes means the SDK caught it, not the app — usually
    higher priority, because nobody expected it.
22. `_error_type` is what splits two issues with identical wording. Read it before
    proposing a merge.
23. Compare `last_seen_app_version` against the app's `latest_app_version` from
    `pubky-pulse:get-app`. Occurrences only on older versions often mean it is already
    fixed.
24. `latest_app_version` is refreshed hourly and cannot be forced, so it lags a release
    that shipped in the last hour.
25. Backend events frequently carry no `app_version`, and an occurrence with no version
    never triggers regression detection.
26. A status change needs the key creator's ownership of the project; commenting does
    not. On `403 Requires project ownership`, comment the finding and tell the user
    which transitions a human still has to make.
27. `403 This operation requires a user session` means human-only. No permission change
    unlocks it.
28. Sub-agents comment and nothing else. Give them the prompt as written, including the
    closing restriction.
29. Five concurrent sub-agents is the cap. More exhausts context and the reports come
    back thinner.
30. Each sub-agent has its own context, so its comment is the only durable output.
    Never skip the comment step to save a call.
31. Do not cache the detected project between runs. The user may have changed
    directory.
32. Multiple apps in one project mean multiple platforms. Decide the app filter before
    the inventory, not after.
33. Claiming sets `in_progress` and is visible to the team, so do not claim
    speculatively — a claimed issue looks owned.
34. Downgrading a log call is a code change: it needs a version bump and a resolve like
    any other fix.
35. Attachments exist on some issues and most have none. Read one only when the file
    itself is the suspect, and never interpret an executable or script MIME type.

## References

- `references/project-detection.md` — read when the project or app is not obvious from
  a client key, for the per-platform bundle-identifier commands.
- `references/subagent-prompt.md` — read when fanning out at Step 3; it holds the
  investigation prompt to copy verbatim for each sub-agent.
- `references/triage-actions.md` — read when acting on an issue at Steps 6–9, for
  call-site grep patterns, where each platform keeps its version, and the downgrade,
  snooze, silence and merge decision rules.
