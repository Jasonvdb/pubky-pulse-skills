---
name: pubky-pulse-instrument
description: >-
  Instruments a codebase end to end with Pubky Pulse: detects the web, backend, iOS and Android
  surfaces, drafts a tracking plan of events, metrics and funnels, creates the project and apps
  over MCP, wires each SDK, covers every error path, and verifies data arrives. Use when asked
  to instrument a repository, or to add analytics or error tracking across it — even if the
  user only says "add Pulse to this repo". Not for one named surface alone (see
  pubky-pulse-web, pubky-pulse-node), errors already collected (see
  pubky-pulse-investigate-issues), or queries and admin (see pubky-pulse-operations).
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

## Instrument the whole repository in one pass

The promise is one prompt in, an instrumented repository out. That means deciding
rather than asking: read the code, work out what the product does, write the plan
down, print it, then carry on through creation, instrumentation and verification
without stopping between surfaces. Stop only for the ambiguity gate in step 4, which
is the one place a wrong guess is expensive to undo.

Plan before touching anything. A tracking plan drafted after the first `Pulse.info`
is a list of whatever happened to be easy, and the names it produces are the
issue-grouping keys and funnel steps the project then has to live with.

**Asking the user.** Whenever a step says to ask the user something, present the
choices as selectable options using your harness's structured question tool rather
than making them type a free-text reply — in Claude Code that tool is
`AskUserQuestion`; Codex and other agents may expose an equivalent. List the
recommended option first. If your harness has no such tool, ask in plain text.
Every question has a default: if no answer comes back, take the recommended option,
continue, and say which default you took in the final report.

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

## Workflow

- [ ] 1. Detect every surface in the repository
- [ ] 2. Audit what is already there, and take a baseline error-coverage count
- [ ] 3. Draft the tracking plan — events, metrics, funnels and error rows per surface
- [ ] 4. Ambiguity gate: always ask about identity, plus whatever else has no
      defensible default, then print the plan
- [ ] 5. Create the project, apps, metrics and funnels over MCP
- [ ] 6. Store the keys and settle the `appVersion` source
- [ ] 7. Instrument each surface by loading its sibling skill
- [ ] 8. Build or typecheck, then re-run the error-coverage script
- [ ] 9. Verify that data actually arrives
- [ ] 10. Report

## 1. Detect the surfaces

A surface is one deployable thing that runs somewhere. Each surface becomes one app.

| Evidence in the repository | Surface | App |
|---|---|---|
| `package.json` with react, vue, svelte, angular or solid; an `index.html`; a bundler config | browser app | `<Project> Web`, platform `web` |
| `package.json` with express, fastify, hono, koa or nest; a `server.ts` entry point | Node service | `<Project> Backend`, platform `backend` |
| Next.js, SvelteKit, Nuxt, Remix or Astro **plus** `app/api/`, `pages/api/`, `+server.ts`, `server/api/`, or server actions that reach a database | **two** surfaces | both of the rows above |
| `*.xcodeproj`, `*.xcworkspace`, or a `Package.swift` with an app target | Apple app | `<Project> iOS` (or `macOS`, `watchOS`), platform `apple` |
| `build.gradle` or `build.gradle.kts` applying `com.android.application` | Android app | `<Project> Android`, platform `android` |
| `pnpm-workspace.yaml`, `apps/`, `packages/`, or a Gradle settings file with several modules | walk each workspace and re-apply the rows above | one app per deployable, not per package |

A full-stack framework is two apps because the halves run on different platforms, take
different SDKs, and fail in unrelated ways — a server error never reaches a `window`
handler, and only the browser half is subject to `allowed_origins`.

Three things that look like surfaces and are not: a published library or shared
package with no deployment of its own; a documentation or marketing site the user did
not ask about; and code targeting an Edge or Workers runtime, which the Node SDK
cannot run on because it needs `node:crypto`, `node:zlib` and `node:fs`.

## 2. Audit

- [ ] `grep` for `Pulse.configure`, `pulse_client_` and `@synonymdev/pubky-pulse` — an
      existing integration gets extended, not replaced, and its naming convention wins.
- [ ] Read the routing table, the screen or page list, and the public API surface.
- [ ] Find the product's own vocabulary — its model names, the verbs in its routes.
      Event names come from the product, not from a generic template.
- [ ] Take the baseline: `scripts/find-uninstrumented-catches.sh <repo root>` (bundled
      beside this skill) prints `{"total":N,"uninstrumented":[…]}` — every `catch`,
      `.catch(`, `onFailure`, `runCatching`, `Result.failure` and `case .failure` with
      no `Pulse.error` in the following 8 lines. Only a Pulse receiver counts —
      `console.error` and `logger.error` leave a site uninstrumented. Record `total`
      and the uninstrumented count now, so step 8 has something to compare against.

## 3. Draft the tracking plan

Write the plan as one table per surface. This is the artefact the rest of the run
executes, and its columns are exactly what the later steps need:

| Kind | Name | Where (file:symbol) | Attributes | Server definition |
|---|---|---|---|---|
| Event | `checkout_completed` | `src/checkout/pay.ts:onSuccess` | `order_id`, `total_cents`, `payment_method` | — |
| Metric | `process-payment` | `src/checkout/pay.ts:pay` | `provider` | `pubky-pulse:create-metric` |
| Funnel step | `checkout-payment` | `src/checkout/Payment.tsx:onSubmit` | — | step of funnel `checkout` |
| Error | `checkout_failed` | `src/checkout/pay.ts:catch` | `order_id`, `stage` | — |

`Kind` is one of Event, Metric, Funnel step, Error. Every row whose `Server definition`
is not `—` has to exist on the server before the code that emits it ships.

Caps, per surface: **≤25 events, ≤8 metrics, 2–3 funnels of 3–6 steps each.** They are
a ceiling that forces the plan to be about outcomes, not a budget to spend. Every
surface also gets Error rows — a surface with none is an unfinished plan.

Where to look, condensed:

| Area | What to emit |
|---|---|
| App start, foreground, screens | already automatic on web, Swift and Android — add nothing |
| Sign-up, sign-in, sign-out | `signed_up`, `signed_in`, `sign_in_failed`; usually the first funnel |
| Onboarding | one funnel step per stage every user passes through |
| The product's core action | one outcome event, plus a lifecycle metric if it can be slow |
| Checkout, subscriptions, payments | `checkout_started` / `_completed` / `_failed`, plus a funnel |
| Uploads, exports, long work | a lifecycle metric wrapping it, an outcome event at the end |
| Search and filters | one `search_performed` with `result_count` — never per keystroke |
| Settings, permissions, feature flags | `setting_changed`, `permission_denied` |
| Backend request handling | one `request_handled` with method, route, status, duration |
| Backend jobs, queues, cron, webhooks | one summary event per run, with counts and duration |
| Every failure path, everywhere | `Pulse.error(err, "<action>_failed", { … })` |

Read `references/where-to-instrument.md` when deciding what a specific app area
deserves, and `references/tracking-plan-template.md` when drafting the plan — it has
the blank table plus a fully worked web-and-backend example to pattern-match against.

## 4. Ambiguity gate

Ask questions 1–4 only when the answer changes what gets created and no reading of the
repository settles it. Ask question 5 every run: the repository can never settle it.

1. **Product name**, when `package.json`, the app display name and the README disagree
   or are placeholders. It becomes the project name and the prefix of every app name.
2. **Ingest endpoint**, when no `PULSE_ENDPOINT` exists anywhere and `whoami` does not
   imply one. Offer the instance the MCP server is already pointed at first.
3. **Which existing project to use**, when `pubky-pulse:list-projects` returns more
   than one plausible match for this product.
4. **A surface to skip**, when one exists but looks abandoned or out of scope — an
   unmaintained example app, a second frontend nobody deploys.
5. **Whether to link real user identifiers.** Every SDK is anonymous by default: the
   client SDKs mint `pulse_anon_<uuid>` per browser or device and that id fills
   `user_id`. `Pulse.setUser(id)` on web, Swift and Android, and `Pulse.withUser(id)`
   on Node, put the product's own identifier there instead, and on the client SDKs
   `setUser` also claims that browser's anonymous history server-side. It decides what
   the app declares in an App Store privacy manifest or a Play data safety form, and
   what a data-subject request has to return, so it is the developer's call, not yours.
   Ask it in the same batch as whichever of 1–4 apply, so it costs no extra round-trip.

| Surface | Still works without identity | Cost of declining |
|---|---|---|
| Web, Swift, Android | unique-user counts, per-user timelines and both funnel modes — the anonymous id already fills `user_id` | those counts are of browsers and devices, so one person on two devices counts twice |
| Node | `withSession`, driven by the client's `X-Pulse-Session-Id` header, still gives the full browser-to-backend trace and needs no consent | there is no backend anonymous id: an unscoped event carries no `user_id` at all and is excluded from funnel analytics, so backend funnel steps never register |

Default: **do not link.** Write the identity call commented out at the exact callsite
with a one-line `// TODO(pulse): ...` marker and nothing else — no commented
scaffolding, no disabled flag. On Node that is one commented
`scope = scope.withUser(...)` line in the auth middleware, with the `withSession` line
beside it instrumented for real. The gate covers exactly `Pulse.setUser` (web, Swift,
Android) and `Pulse.withUser` (Node). `Pulse.clearUser` is never gated: it is the call
that removes a link rather than creating one, so wire it on logout, on a shared device,
and when moving an app off identified analytics — on Swift and Android an identifier a
previous `setUser` stored outlives the process and keeps linking events until it runs.
`setUserProperties` attaches to whichever id is in play, so it follows the answer
rather than being gated on its own. Each SDK skill repeats this question when it is
invoked directly for one surface and nobody handed it an answer.

Everything else has a default: infer it, note the assumption, keep going. Then print
the plan — surfaces, apps to create, the per-surface tables, the metrics and funnels —
and start executing. Do not ask for approval of the plan itself; the user asked for the
work, and the plan is reviewable in the diff and the final report.

## 5. Create on the server

Order matters: a metric or funnel definition has to exist before code emits for its
slug, and an app has to exist before there is a key to configure with. Run these in
order and read each response before making the next call.

- [ ] `pubky-pulse:whoami` → the `team.id` every create needs, and the key's permissions.
- [ ] `pubky-pulse:list-projects` → reuse an existing project whose name or slug matches
      the product. A second project for the same product splits its metrics, funnels
      and issues in half, permanently.
- [ ] `pubky-pulse:create-project` `{ team_id, name: "Lofi", slug: "lofi" }`.
- [ ] `pubky-pulse:create-app` per surface: `{ project_id, name: "Lofi Web",
      platform: "web", bundle_id: "app.lofi.com", allowed_origins: [...] }`. A web app
      needs every origin it is served from **including the dev server**; a backend app
      takes no `bundle_id` and no origins. Record each `client_secret`.
- [ ] `pubky-pulse:create-metric` per metric row: `{ project_id, name, slug }`.
- [ ] `pubky-pulse:create-funnel` per funnel: `{ project_id, name, slug, steps: [{ name,
      event_filter: { step_name: "checkout-payment" } }] }` — filter on `step_name`,
      not `screen_name`.

Only proceed to step 6 once every create has returned an id. A failure here is one of
three `403`s, and they need different fixes:

| Message | Meaning | What unblocks it |
|---|---|---|
| `Missing permission: <p>` | the agent key never had that permission | a human edits the key |
| `Requires project ownership` | the key's creator does not own that project | a human owner adds them; no new key needed |
| `This operation requires a user session` | the operation is human-only | ask a human to do it in the dashboard |

On any of them, stop creating, finish the code-only work, and list what is outstanding
under `Pending Pubky Pulse steps` in the final report.

Read `references/mcp-setup-sequence.md` when you need the exact parameters, the
project-reuse matching rule, or how to add an origin to an app that already exists.

## 6. Keys and app version

The client key is public and ingest-scoped, so it may ship in a bundle — but it still
does not belong in git. Read it from the framework's own environment convention:

| Surface | Variables | Where |
|---|---|---|
| Vite, React, Vue | `VITE_PULSE_ENDPOINT`, `VITE_PULSE_KEY` | `.env.local` |
| Next.js browser half | `NEXT_PUBLIC_PULSE_ENDPOINT`, `NEXT_PUBLIC_PULSE_KEY` | `.env.local` |
| SvelteKit | `PUBLIC_PULSE_ENDPOINT`, `PUBLIC_PULSE_KEY` | `.env` |
| Nuxt | `NUXT_PUBLIC_PULSE_ENDPOINT`, `NUXT_PUBLIC_PULSE_KEY` | `.env` |
| Node backend | `PULSE_ENDPOINT`, `PULSE_API_KEY` — no public prefix, ever | `.env` |
| Apple | an `.xcconfig` value surfaced through `Info.plist` | build settings |
| Android | `local.properties` → `buildConfigField` → `BuildConfig.PULSE_CLIENT_KEY` | Gradle |

Add the names with placeholder values to `.env.example`, and confirm `.env*` is
git-ignored. The web app's key and the backend app's key are different keys: swapping
them sends browser events to the backend app, where `allowed_origins` does not apply,
so nothing looks broken until someone notices the data is in the wrong place.

`appVersion` is what makes issue regression detection and version badges work, and it
has to increase between releases — versions compare segment by segment, so a git SHA
orders alphabetically and is worse than passing nothing:

| Surface | Source |
|---|---|
| Web | the `version` in `package.json`, injected at build time by the bundler |
| Node | `process.env.APP_VERSION`, or that same `package.json` version |
| Apple | automatic from `CFBundleShortVersionString` plus the build number |
| Android | automatic from the manifest's `versionName` |

## 7. Instrument each surface

Do not write SDK calls from memory. For each surface, load the sibling skill by name —
`pubky-pulse-web`, `pubky-pulse-node`, `pubky-pulse-swift`, `pubky-pulse-android` — and
give it that surface's plan rows as its input. The handoff is:

- the ingest endpoint, the app's `client_secret`, and its `bundle_id`
- the `appVersion` source decided in step 6
- the identity answer from step 4 — link real identifiers, or leave the identity call
  commented out at its callsite
- the Event, Metric, Funnel step and Error rows for that surface, with the
  `Where (file:symbol)` column intact
- for a web-plus-backend repository: `propagateSessionTo` on the browser side and the
  matching `X-Pulse-Session-Id` scoping on the server side, so one user's browser and
  server events land on a single session timeline

Work through the surfaces one at a time, finishing each before starting the next.

## Catch every error

The issue tracker contains exactly what the code reported. Automatic capture differs
per platform, and the gap is where instrumentation usually falls short:

| Platform | Captured for you | You must add | Never assume |
|---|---|---|---|
| Web | `window` `error` and `unhandledrejection`, tagged `_unhandled` | error boundaries, router error elements, every `catch` on an async path, non-2xx `fetch` responses, query-library error callbacks, `XMLHttpRequest` and axios, web workers | that `console.error` is captured — it is not |
| Node | `uncaughtException` and `unhandledRejection`, after which the process still dies | the framework error handler, queue workers, cron callbacks, WebSocket handlers, stream `error` events, database pool errors, non-2xx outbound responses | that auto-capture prevents the crash, or that the buffer flushed first |
| Swift | nothing | every `catch`, `Result` `.failure`, unstructured `Task`, `.task` and `.refreshable`, Combine failure completion, decoding failures, non-2xx responses, delegate error callbacks | that runtime traps are reported — a `fatalError` kills the process first |
| Android | nothing | every `catch`, `runCatching { }.onFailure`, a `CoroutineExceptionHandler` on each root scope, `viewModelScope.launch`, `Flow.catch`, WorkManager failures, an OkHttp interceptor | that HTTP failures are captured — `networkTrackingEnabled` does nothing |

Three rules hold on every platform. Pass the error object, not its message: the
extracted `_error_type` is what keeps a decoding failure and a transport failure on
separate issues. Keep the message a fixed snake_case template
(`photo_upload_failed`) and put ids and URLs in attributes, because the message is the
grouping key and an interpolated one produces a new issue per occurrence. Report once,
at the layer that handles the failure, not at every layer it passes through.

Read `references/error-coverage.md` when a boundary is not a plain `catch` — it has the
code shape for each boundary on each platform, and the report-or-skip judgement calls.

## 8. Build, then re-check coverage

- [ ] Build or typecheck every surface you touched: `npm run build` / `tsc --noEmit`,
      `xcodebuild`, `./gradlew assembleDebug`.
- [ ] Re-run `scripts/find-uninstrumented-catches.sh <repo root>` and compare against
      the step 2 baseline.

Only proceed at zero uninstrumented sites, or with a written justification per
remaining site. The legitimate ones are narrow: a `catch` that rethrows immediately to
a layer that does report, a control-flow `catch` where failure is the expected path (a
cache miss, an optional parse), and a `CancellationException` rethrow. A `catch` that
swallows a failure and shows the user a message is not one of them.

## 9. Verify

Run each surface, exercise the instrumented paths, then query. Use
`data_mode: "development"`: localhost, `NODE_ENV !== "production"`, DEBUG builds and
debuggable APKs are all development data, and the default `production` mode shows
nothing at all.

- [ ] `pubky-pulse:query-events` `{ app_id, data_mode: "development", since: "15m" }`
      per app — expect `sdk:session_started` plus that app's planned events.
- [ ] `pubky-pulse:query-funnel` `{ project_id, slug, mode: "open",
      data_mode: "development" }` per funnel — expect users on the steps you fired.
- [ ] `pubky-pulse:query-metric` `{ project_id, slug, data_mode: "development" }` —
      expect a start and exactly one terminal phase per operation.
- [ ] Trigger a deliberate failure on each surface, then `pubky-pulse:query-events`
      with `level: ["error"]`. Errors are queryable immediately.
- [ ] `pubky-pulse:list-issues` only after the hourly issue scan has run. It is a
      system job on a schedule, so there is nothing to trigger; an empty list minutes
      after the error is expected, not a fault.

Nothing arriving is almost always one of eight things, in this order: the web app's
`allowed_origins` (a `403` on the ingest request), the wrong `data_mode`, a key with
the wrong prefix or belonging to another app, an endpoint that already has a path on
it, calls made before `configure()`, a server-rendered path where there is no
`window`, a process that exited before flushing, or a browser buffer that never
reached its threshold. Read `references/verification.md` for the query recipes and the
decision tree that separates them.

## Final report

```markdown
## Pubky Pulse instrumentation

**Project** Lofi (`<project id>`) · created | reused
**Apps** Lofi Web (web, `app.lofi.com`) · Lofi Backend (backend)

| Surface | Events | Metrics | Funnel steps | Error sites |
|---|---|---|---|---|
| Web | 11 | 3 | 4 | 9 |
| Backend | 7 | 2 | 2 | 12 |

**Error coverage** 41 handling sites, 41 reporting (baseline: 6 of 41).
Remaining uninstrumented: none | `<file:line>` — rethrown to `<handler>`.

**Identity** linked, `Pulse.setUser` after sign-in | anonymous only — call left
commented at `src/auth/session.ts:onSignIn`.

**Verified** `sdk:session_started` and 14 planned events in development data mode;
funnel `checkout` shows 4 of 4 steps; metric `process-payment` shows 3 completions;
a deliberate failure appeared at `level: "error"`.

**Assumptions** app version comes from `package.json`; no staging origin was added
because none is configured.

**Pending Pubky Pulse steps** none | <what still has to be created, and why>

**Next** issues cluster on the hourly scan; triage them with pubky-pulse-investigate-issues.
```

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

## Gotchas

- **A full-stack framework is two apps.** One project, `<Project> Web` and
  `<Project> Backend`, two keys, two `configure()` calls.
- **A new web app has no `allowed_origins`** and answers `403` to every browser
  request. This is the most common reason nothing arrives.
- **The dev origin is its own entry.** `http://localhost:3000`,
  `http://localhost:5173` and `http://127.0.0.1:3000` are three different origins.
- **`pubky-pulse:update-app` replaces the whole origin list.** Resend what you keep.
- **`bundle_id` is immutable**, and a web one is a name, not a URL. Fixing a wrong one
  means deleting the app, which is human-only.
- **`create-project` needs `team_id` and a `slug`.** They come from `whoami` and the
  product name; neither is defaulted for you.
- **Reuse the existing project.** A second project for the same product splits its
  metrics, funnels and issues permanently.
- **Definitions come before emission.** A `step()` or `startOperation()` for a slug
  that does not exist server-side records an event no funnel or metric ever reports.
- **Metric slugs are auto-corrected** to `^[a-z0-9-]+$` by the SDKs, with a warning;
  funnel step names are kept verbatim, so a typo quietly becomes its own step.
- **Filter funnel steps on `step_name`, not `screen_name`.** A screen filter is an
  exact match, so a path with a variable segment never matches it.
- **Backend funnel steps need `withUser`.** Events with no `user_id` are excluded from
  funnel analytics entirely, and nothing warns you. That is the fix once identity is
  opted in at the step 4 gate; declined, an empty backend funnel is the expected
  outcome and `withSession` correlation is what answers the question instead.
- **`op.fail` differs by SDK.** The web SDK takes the error value; Node, Swift and
  Android take a `String`. Do not copy a snippet across surfaces.
- **`console.error` is not captured** on web, and neither are React error boundaries,
  `XMLHttpRequest`, resource-load failures, or errors inside a web worker.
- **Swift and Android capture no crashes.** Every error there is one the code sent.
- **Android's `networkTrackingEnabled` does nothing.** Add an OkHttp interceptor.
- **Swift's automatic network tracking misses async/await.** It covers only
  completion-handler `URLSession` calls.
- **Node's auto-capture does not prevent the crash.** The process still exits and the
  supervisor still has to restart it; buffered events can be lost.
- **Non-2xx responses are not errors** to `fetch` or `URLSession`. Check the status.
- **Interpolated messages fragment issues.** `"upload failed for " + id` makes one
  issue per id; the id belongs in an attribute.
- **Pass the error object, not `error.message`.** Without `_error_type`, two unrelated
  error classes with the same wording collapse into one issue.
- **`error.stack` as an attribute value is truncated at 200 characters.** Passing the
  error instead puts the stack in `_error_stack`, with a 16000-character cap.
- **Never invent `_`-prefixed attribute keys.** They belong to the SDK, and on a
  collision the SDK's value wins.
- **Reserved messages are the SDK's too** — never emit `metric:*`, `step:*` or `sdk:*`
  by hand.
- **`appVersion` must increase.** A git SHA sorts alphabetically, so regression
  detection and every version badge quietly stop working.
- **Web has no build number.** `appVersion` is its only release identifier.
- **Verification defaults to production data.** Pass `data_mode: "development"`, or the
  result is an empty list that looks like a broken integration.
- **A staging host is production data on web.** `isDev` is true only on `localhost`,
  `127.0.0.1` and `file:`.
- **A TestFlight build and an internal-testing release are production data too**, from
  `#if DEBUG` and `FLAG_DEBUGGABLE` respectively.
- **Issues lag events by up to an hour.** The scan is a scheduled system job;
  `query-events` at `level: ["error"]` is how to verify immediately.
- **The agent key is not the client key.** `pulse_agent_*` is for MCP only and never
  belongs in a bundle, a `NEXT_PUBLIC_*` variable, or a committed file.
- **A backend key must not carry a public prefix.** A `NEXT_PUBLIC_` backend key ships
  to browsers.
- **Calls before `configure()` are dropped** with one console line, then silence.
- **Re-`configure()` starts a new session.** React StrictMode doubles it in dev.
- **Server rendering is a no-op with a valid config and a throw with an invalid one** —
  a mistyped endpoint fails during server rendering, not in the browser.
- **The endpoint takes no path.** The SDK appends `/v1/ingest` itself.
- **Never log in a loop, a render pass, a scroll or timer callback, or per retry.**
  Emit one summary event with counts and `duration_ms` instead.
- **Do not track a screen twice.** Web tracks History-API navigations automatically,
  and the native SDKs track their screen modifier. An event on top double-counts.
- **No secrets in events.** Tokens, passwords, card numbers, `Authorization` and
  `Cookie` values, full request bodies, raw IPs. The caps truncate, they do not redact.
- **Attach a file only when its bytes are the bug.** Never logs, stack traces or
  screenshots.
- **The Node SDK does not run on Edge or Workers runtimes.**
- **A one-shot script must `await Pulse.flush()`** before exiting, and a serverless
  handler needs `wrapHandler`.
- **Deleting an app or a project is human-only.** Check the names before creating.

## References

- `references/where-to-instrument.md` — read when deciding what a given app area
  deserves, which names to give it, and what to leave alone.
- `references/tracking-plan-template.md` — read when drafting the plan: the blank
  table plus a fully worked web-and-backend example.
- `references/error-coverage.md` — read when a failure boundary is not a plain
  `catch`, or before declaring step 8 done on a platform.
- `references/mcp-setup-sequence.md` — read when creating the project, apps, metrics
  and funnels: exact parameters, expected response fields, reuse and `403` handling.
- `references/verification.md` — read when verifying, and when data does not arrive.
