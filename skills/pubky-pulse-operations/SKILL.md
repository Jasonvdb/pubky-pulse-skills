---
name: pubky-pulse-operations
description: >-
  Drives the Pubky Pulse MCP server directly: projects, apps and allowed origins, metric and
  funnel definitions, event, metric, funnel and stats queries, feedback, questionnaires,
  attachments, background jobs, import keys and audit logs. Use when asked to create or
  update a Pubky Pulse project, app, metric or funnel, to query analytics or read feedback
  and survey results, or to connect the MCP server and check what a key can do. Not for
  writing SDK code into a repo (see pubky-pulse-instrument) or triaging error issues (see
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

<!-- body written in a later phase -->
