---
name: pubky-pulse-swift
description: >-
  Adds the Pubky Pulse Swift SDK to an iOS, iPadOS, macOS or watchOS app. Covers Swift
  Package Manager setup, configuration, screen tracking, and the error capture the SDK does
  not do for you — there is no automatic crash capture, so every catch, Result and Task
  boundary reports itself. Also events, metrics, funnels, identity, feedback, questionnaires
  and privacy manifests. Use when adding analytics or error tracking to Apple app code. Not
  for Kotlin (see pubky-pulse-android) or for planning what to track first (see
  pubky-pulse-instrument).
license: MIT
compatibility: >-
  The code changes need no MCP server. The pubky-pulse MCP server is needed only to create
  the app, read its client key, and check that events arrive. Any harness that reads
  SKILL.md.
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
