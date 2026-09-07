# Contributing

This repository holds seven skills for one product, so they are written to one
contract rather than to taste. Read this file before editing any `SKILL.md`:
everything below is enforced by `node scripts/lint-skills.mjs`, which CI runs on
every push and pull request.

Skills cannot import each other portably, so the shared blocks in this file are
**duplicated verbatim** into each `SKILL.md`. This file is the canonical copy —
change it here first, then propagate.

## Frontmatter

Only the portable keys. Claude-Code-only keys (`when_to_use`, `argument-hint`,
`disable-model-invocation`, `context`, `agent`, `model`, `hooks`, `paths`) hard-fail
packaging in other harnesses. No `$ARGUMENTS`, no `` !`cmd` `` injection, no
`${CLAUDE_SKILL_DIR}`; relative paths use forward slashes.

```yaml
---
name: pubky-pulse-<x>            # identical to the directory name
description: >-
  <see the template below>
license: MIT
compatibility: >-
  Needs the pubky-pulse MCP server connected for the create and verify steps;
  the code changes work without it. Any harness that reads SKILL.md.
metadata:
  version: "0.1.0"
  product: pubky-pulse
  docs: https://pulse.pubky.org/docs
---
```

## Description

The description is the entire triggering surface — an agent decides whether to
load the skill from this text alone.

```
<what it does, with concrete keywords: product, package names, verbs users type>.
Use when <triggers, phrasings, situations — slightly pushy: "even if the user only says …">.
Not for <X> (see <sibling>), <Y> (see <sibling>).
```

- Third person, never "I" or "you".
- **Target ≤600 characters, hard cap 800.** Seven skills share one listing budget:
  Claude Code truncates the listing and drops least-used descriptions first, and
  Codex caps the whole listing at 8000 characters and shortens what it shows. So
  trigger words go first and the boundary clause goes last — it is the part that
  can be lost without breaking triggering.
- Name only the two or three siblings most likely to be confused with this skill.
- Write triggers around substantive tasks ("instrument", "set up error tracking",
  "what is broken in production"), not trivia an agent handles without a skill.

## Body

- **≤500 lines**, roughly 5k tokens. Only what the model does not already know.
- Imperative voice. Explain *why* instead of stacking MUST / ALWAYS / NEVER.
- One default per decision with a brief escape hatch, not a menu of options.
- Keep **Gotchas in `SKILL.md`** — a trap the agent has already hit is a trap it
  never knew to load a reference for.
- Long material goes in `references/*.md`, one level deep, each with a "Read when …"
  line in `SKILL.md`. Reference files over 100 lines start with `## Contents`.
- Refer to sibling skills **by name only** ("load `pubky-pulse-web`"), never by path.
- Write MCP tools as `pubky-pulse:<tool>` and note once per skill that Claude Code
  exposes them as `mcp__pubky-pulse__<tool>`.

## Shared blocks — copy verbatim

### Block A — What is Pubky Pulse (every skill)

```markdown
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
```

### Block B — Naming rules (every skill)

```markdown
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

Rule of thumb: hyphens mean the name must exist on the server first; underscores
mean a free-form event message. The message is the issue-grouping key, so keep it a
stable template and put the variable data in attributes. If the project already has
a naming convention, stay consistent with it.
```

### Block C — Asking the user (instrument, investigate-issues, operations)

```markdown
**Asking the user.** Whenever a step says to ask the user something, present the
choices as selectable options using your harness's structured question tool rather
than making them type a free-text reply — in Claude Code that tool is
`AskUserQuestion`; Codex and other agents may expose an equivalent. List the
recommended option first. If your harness has no such tool, ask in plain text.
Every question has a default: if no answer comes back, take the recommended option,
continue, and say which default you took in the final report.
```

### Block D — If the MCP server is not connected (every skill)

```markdown
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

Then carry on with every step that only touches code, and finish with a
`Pending Pubky Pulse steps` list naming each project, app, metric and funnel that
still has to be created once the server is connected.
```

Tune the last paragraph per skill: `pubky-pulse-operations` cannot do anything
useful without the server, so it stops there instead of continuing.

### Instrumentation Principles (the four SDK skills)

```markdown
## Instrumentation Principles

1. **Log outcomes, not steps.** Emit one rich event per outcome — the thing the app
   or service did (request handled, checkout completed, job finished) — not one per
   line of code. Intermediate diagnostics (cache lookups, fallbacks) go to `debug`.
2. **Pack attributes wide, not events deep.** One event with 15 attributes beats 15
   events with one each. Think through who (`user_id`, `plan_tier`), what
   (`order_id`, `feature_flag`), where (route, screen, region), how (`auth_method`,
   `retry_count`) and how much (`duration_ms`, `status_code`, `amount_cents`).
   High-cardinality attribute *values* are a feature — they let a chart drill down to
   one failing request. Event *frequency* is the thing to control.
3. **Aggregate hot paths.** Never log inside a loop, a queue drain, a render pass, a
   scroll or timer callback, or per retry attempt. Log one summary event with counts,
   totals and `duration_ms`, or wrap the whole operation in a lifecycle metric.
4. **Log, metric, or funnel — pick by the question.** A log event answers "show me the
   individual records when this went wrong". A lifecycle metric (`startOperation` →
   exactly one of `complete` / `fail` / `cancel`) answers "what is the p95 latency and
   success rate of this operation". A single-shot `recordMetric` answers "what is this
   value, trended". A funnel step answers "where do users drop out of this journey".
   One flow often warrants all four. When in doubt, write one event with more
   attributes rather than several events with fewer.
```

## Banned words

`skills/**` must never contain (case-insensitive): `owlmetry`, `owl_client`,
`revenuecat`, `search ads`, `app store connect`, `apns`, `push notification`,
`attribution token`, `team invitation`, `integrations framework`. These name a
different product or a feature this one does not have, and an agent that reads one
will go looking for it.

The bare word `CLI` is banned too, because the MCP server is the only agent
interface here. A line naming a specific tool (`Codex CLI`, `Gemini CLI`,
`GitHub CLI`) or stating that no such thing exists is allowed.

Do not narrate removals ("X was removed") — simply do not mention what is not there.

## Lint rules

`node scripts/lint-skills.mjs` checks:

1. All five harness manifests parse, agree on the plugin name, and the Codex
   manifest points `skills` at `./skills/`.
2. Per skill: frontmatter keys are within the portable set, `name` matches the
   directory, the description is 1–800 characters and contains both "Use when" and at
   least one sibling skill name, the body is ≤500 lines, and there is no `$ARGUMENTS`
   or `` !`cmd` `` injection.
3. No banned word in `skills/**`.
4. Every `pubky-pulse-<x>` token is a real skill directory or an allow-listed package
   name (`pubky-pulse-web-demo`, `pubky-pulse-skills`, the four SDK packages).
5. Every `pubky-pulse:<tool>` token exists in `scripts/mcp-tools.json` — the guard
   against inventing MCP tools. Regenerate that file from the server's tool registry
   when the tool surface changes.
6. Each referenced `references/*.md` exists, each file in `references/` is mentioned in
   `SKILL.md` on a line saying when to read it, and files over 100 lines start with
   `## Contents`.
7. `evals/triggers.json`, when present, has at least eight `should` and eight
   `should_not` queries. A skill with no evals file yet produces a warning.
8. Every bundled `skills/*/scripts/*` is executable and exits 0 for `--help`.

Failures print one per line and exit 1. Run it before opening a pull request; a
reviewer reads the whole skill, including bundled scripts, before merge.
