---
name: pubky-pulse-instrument
description: >-
  Instruments a codebase end to end with Pubky Pulse: detects the web, backend, iOS and
  Android surfaces, drafts a tracking plan of events, metrics and funnels, creates the
  project and apps over MCP, wires each SDK, covers every error path, and verifies data
  arrives. Use when asked to add analytics or error tracking, to instrument an app, to wire
  up Pubky Pulse, or to track events and conversion funnels — even if the user only says
  "add Pulse to this repo". Not for triaging errors already collected (see
  pubky-pulse-investigate-issues) or ad-hoc queries and admin (see pubky-pulse-operations).
license: MIT
compatibility: >-
  Needs the pubky-pulse MCP server connected for the create and verify steps; the code
  changes work without it. Any harness that reads SKILL.md.
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
