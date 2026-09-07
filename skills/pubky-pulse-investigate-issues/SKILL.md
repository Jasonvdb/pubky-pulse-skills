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

<!-- body written in a later phase -->
