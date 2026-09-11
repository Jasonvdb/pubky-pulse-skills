---
name: pubky-pulse-web
description: >-
  Adds the Pubky Pulse web SDK to a browser app — React, Next.js, Vue, Svelte, or plain
  JavaScript. Covers configuration, catching every unhandled and caught error, screen tracking,
  events, lifecycle metrics, funnel steps, user identity, feedback and questionnaires, and
  propagating the session to the backend. Use when adding analytics or error tracking to
  browser code, or when a tracking plan needs browser instrumentation. Not for server code (see
  pubky-pulse-node) or for planning what to track and creating the project first (see
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

## Before writing code

Use the client key for the Pulse app and the endpoint for its instance:

| Input | Where it comes from | Trap |
|---|---|---|
| `endpoint` | the Pulse server base URL | set it explicitly for self-hosting; omitted uses `https://ingest.pubkypulse.com` |
| `apiKey` | the `client_secret` of a `web` app (`pulse_client_…`) | public by design, so a `VITE_`/`NEXT_PUBLIC_` variable is correct here |
| `bundleId` | optional legacy identifier | the client key identifies the web app; omit from new integrations |

Get them with `pubky-pulse:list-apps` / `pubky-pulse:get-app`, or create the app with
`pubky-pulse:create-app` (`platform: "web"`, a site-identifier `bundle_id`, and `allowed_origins`). Then
check the origins before anything else:

- [ ] The app's `allowed_origins` lists every origin the site is served from, **including
      the dev server** (`http://localhost:5173`, `http://localhost:3000`).
- [ ] Entries are full origins — scheme, host, optional port, no path, no trailing slash.
- [ ] `pubky-pulse:update-app` replaces the whole list, so resend the origins you keep.

An empty list is the single most common reason nothing arrives: a web app with no origins
answers `403` to every request a browser makes, and CORS refuses the preflight before that.
This is per app; the server's own `CORS_ORIGINS` is the dashboard's origin and is unrelated.

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

## Install and initialize

```sh
npm install @synonymdev/pubky-pulse-web
```

`Pulse` is a module singleton — no provider, context or hooks required. These patterns
require **Web SDK 0.6.0 or newer**; upgrade an older installed version before using them.
Initialize in the browser entry module before rendering:

```ts
import { Pulse } from "@synonymdev/pubky-pulse-web";

Pulse.init({
  endpoint: import.meta.env.VITE_PULSE_ENDPOINT,
  apiKey: import.meta.env.VITE_PULSE_KEY,
  appVersion: __APP_VERSION__,
  propagateSessionTo: ["/api"],
});
```

An absent or blank key and `enabled: false` disable telemetry without creating browser
identity, storage, listeners or network requests. SSR is a quiet no-op; a later browser
initialization can succeed. Inspect the returned `status` / `reason` when diagnosing setup.
The first successful configuration wins, so repeated startup calls need no custom guard.
Keep callbacks and policy in one app-owned module. `configure()` remains available when
throwing validation and explicit reconfiguration are intentional.

`appVersion` is the only release identifier a browser app has — there is no build number —
so leaving it out disables issue regression detection and every version badge for this app.
It must **increase** between releases: a semver string or a date-style version orders
correctly, a git SHA orders alphabetically and is worse than nothing. Inject it at build
time from `package.json`; `references/frameworks.md` has the one-liner per bundler.

Where the call goes depends on the framework:

| Framework | Placement |
|---|---|
| React / Vite | the browser entry module (`main.tsx`), before `createRoot(...).render(...)` |
| Next.js App Router | module scope of a `"use client"` provider file mounted once in the root layout |
| Next.js Pages Router | module scope of `_app.tsx`, above the component |
| SvelteKit | `<script context="module">` in the root `+layout.svelte`, before the layout renders |
| Vue / Nuxt | `app.mount()` site, or a client-only plugin in Nuxt |
| Angular | an `APP_INITIALIZER` factory |
| Plain page | a `<script type="module">` before the code that logs |

Read `references/frameworks.md` when the project is Next.js, SvelteKit, Nuxt, Angular or a
hash router, or when you need the build-time version injection for its bundler.

## Capture failures at their owning boundaries

Automatic capture covers exactly two hooks: `window`'s `error` and `unhandledrejection`
events, tagged `_unhandled`. Add reporting where the framework or app handles failures
before they reach those hooks. Prefer one existing error boundary, query-cache callback or
request wrapper over reporting the same failure at every callsite. Review these paths:

- [ ] **Error boundary** — React (and every other framework's equivalent) swallows render
      errors. A boundary that does not report is a silent failure.
- [ ] **Router error elements** — `errorElement` / `+error.svelte` / Vue's `onErrorCaptured`.
- [ ] **Handled async failures** — data loading, mutations, uploads, parsing; cover them
      centrally where possible and exclude expected cancellations through app policy.
- [ ] **Non-2xx `fetch` responses** — a `404` is a resolved promise, not a rejection.
- [ ] **Data-layer hooks** — TanStack Query, SWR, Apollo, RTK Query error callbacks.
- [ ] **`XMLHttpRequest` and axios** — the SDK wraps `fetch` only.
- [ ] **Web workers** — a worker's failures never reach the page's `window` handlers.
- [ ] **`console.error` sites** — not captured; convert the ones that mean a real failure.

Pass the original thrown value directly; `captureException` accepts `unknown` and extracts
error type, stack and causes without serializing arbitrary error properties:

```ts
try {
  await pay(order);
} catch (err) {
  Pulse.captureException(err, {
    message: "checkout_failed",
    attributes: { checkout_stage: "payment" },
  });
}
```

Use one app-owned `ignoreErrors` list and a synchronous `beforeSend(event, hint)` policy
for expected failures, redaction and allowlisted metadata. `hint.originalException` is
capture-only context; never copy the object or its context wholesale into the event.
Returning `null` drops the event. The same `Error` object is attempted once per client
lifetime, even if filtered; distinct errors and primitive throws are not deduplicated.
`captureException` stays quiet before initialization and while disabled.

Read `references/error-capture-patterns.md` when wiring a React error boundary, a router
error element, a query-library error handler, an axios interceptor, or a web worker — it
has each of those written out, plus what to do about cross-origin `Script error.`.

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

In the browser specifically: a render pass, a `resize`/`scroll`/`mousemove` handler, a
`requestAnimationFrame` loop and a React effect that runs on every keystroke are all hot
paths. Debounce to an outcome, or measure the whole interaction with one operation.

## Naming rules

| Thing | Rule | Example |
|---|---|---|
| Project | bare product name, no platform suffix | `Lofi` |
| App | `<Project> <Platform>` | `Lofi Web`, `Lofi Backend`, `Lofi iOS`, `Lofi Android` |
| Event message | snake_case, outcome-oriented, never interpolated | `checkout_completed` |
| Metric slug | kebab-case, created on the server first | `process-payment` |
| Funnel slug and step | kebab-case, created on the server first | `onboarding`, `onboarding-email` |
| Questionnaire slug | kebab-case, immutable after creation | `nps-q3` |
| Screen name | native: PascalCase human name; web: app-owned safe route template, tracked automatically | `Checkout`, `/users/[id]` |
| Web `bundle_id` | a site identifier name, not a URL | `app.acme.com` |

Rule of thumb: hyphens mean the name must exist on the server first; underscores
mean a free-form event message. The message is the issue-grouping key, so keep it a
stable template and put the variable data in attributes. If the project already has
a naming convention, stay consistent with it.

## Events

```ts
Pulse.debug("cache_hit", { key: "profile" });
Pulse.info("signed_up", { plan: "pro", source: "pricing_page" });
Pulse.warn("slow_response", { ms: "2400", endpoint: "/api/search" });
Pulse.error("payment_declined", { code: "insufficient_funds" });
```

Attribute values are stringified and capped at 200 characters; entries whose value is
`undefined` or `null` are dropped, so optional fields pass straight through. Never invent an
underscore-prefixed key — those are reserved for the SDK. Do not add raw page URLs or
referrers merely for extra context: they can contain identifiers and query secrets. Use safe route templates and allowlisted attributes instead.

## Screens

History-API navigations are tracked automatically: `pushState`, `replaceState` and
`popstate` emit `sdk:screen_appeared` / `sdk:screen_disappeared` at debug level whenever
`location.pathname` changes. Hash-only changes are ignored.

The default is the raw pathname. For routes containing identifiers, reuse app-owned routing
constants with the exported mapper instead of writing another path sanitizer:

```ts
import { createScreenNameMapper } from "@synonymdev/pubky-pulse-web";

const screenNameForPath = createScreenNameMapper(
  ["/", "/orders/new", "/orders/[orderId]"],
  { fallback: "/unknown" },
);
// Include screenNameForPath in the initial Pulse.init options.
```

Only configured templates or the fallback are emitted. Static routes beat parameters;
`[name]` matches one segment, with no catch-all or optional syntax. Invalid templates throw
when creating the mapper. Manual screen labels still need the same app-owned privacy policy.

Call `Pulse.trackScreen("Checkout / Payment")` for what the URL does not describe — a
modal, a wizard step, a tab. It also becomes the default `screen_name` for later events,
and repeating the current name is a no-op. With a hash router that never touches the
History API, set `trackPageViews: false` and drive `trackScreen` from the route hook.

## Identity

Identity is opt-in. Events carry an anonymous id (`pulse_anon_*`) until `setUser` runs, so
unique-user counts, per-user timelines and both funnel modes already work without it. Write
`setUser` only when the developer has explicitly agreed to link analytics to real user ids:
use the answer the `pubky-pulse-instrument` step-4 gate supplies, and when none was supplied,
this skill having been invoked directly for the web surface, put the same question to the
developer yourself — as selectable options in your harness's structured question tool
(`AskUserQuestion` in Claude Code, plain text if it has none), staying anonymous recommended
first. With no answer, write it commented out at the callsite with a one-line
`// TODO(pulse): ...` marker and nothing else. `clearUser` is never gated: it creates no link,
so an agent may always write it. It removes none either — a bare `clearUser()` restores the
previous anonymous id, which the server resolves straight back to the account that claimed it,
so only `Pulse.clearUser({ newAnonymousId: true })` separates future activity, and neither form
unclaims events that are already attributed.

```ts
void Pulse.setUser(user.id);
```

`setUser` flushes buffered events, claims the anonymous history server-side, then switches
the id — which is what makes a sign-up funnel measurable. Do not `await` it on the sign-in
path: the promise waits for request attempts that retry with backoff, so a failing endpoint
can hold it for minutes. Call it on every load where the user is known; the claim is
idempotent. On sign-out use `Pulse.clearUser({ newAnonymousId: true })` on shared devices.

`Pulse.setUserProperties({ plan: "pro" })` merges user-level metadata (50 keys, 200-char
values, empty string deletes). Call it after `setUser`, or it attaches to the anonymous id.

## Metrics

Create the definition first with `pubky-pulse:create-metric` — the slug has to exist on the
server before the SDK emits for it. Then wrap the operation and finish it on every exit:

```ts
const op = Pulse.startOperation("image-upload", { source: "camera" });
try {
  await upload(file);
  op.complete({ bytes: String(file.size) });
} catch (err) {
  op.fail(err);            // web takes the error value itself
}
```

`op.fail(error: unknown, attributes?)` on the web SDK accepts any value and describes it
into an `error` attribute. (The Node SDK's `fail` takes a `string` — do not copy a snippet
across.) `op.cancel()` is for work the user abandoned, which is not a failure. Finishing is
idempotent, so a late `complete()` after a `fail()` is ignored rather than double-counted.
For a number you already have, `Pulse.recordMetric("page-load", { duration_ms: "820" })`.

## Funnels

Create the funnel with `pubky-pulse:create-funnel` first, then emit its steps verbatim:

```ts
Pulse.step("onboarding-email");
Pulse.step("onboarding-verify", { attempt: "2" });
```

Step names are kept exactly as written — a typo becomes its own step. Every browser event
already carries a user id (anonymous before sign-in), so bare `Pulse.step` works here.

Prefer `Pulse.step` over `screen_name` filters in the funnel definition: a step filter on
`screen_name` is an exact match, so `/checkout` does not match `/checkout/payment`, and a
route with a variable segment (`/orders/8f21/confirm`) never matches a fixed filter at all.

## Sending the session to your backend

```ts
Pulse.init({
  endpoint: PULSE_ENDPOINT,
  apiKey: PULSE_KEY,
  propagateSessionTo: ["/api", "https://api.acme.com"],
});
```

Include these options in the initial configuration. Listed prefixes get an
`X-Pulse-Session-Id` header, so browser and server events land on one
session timeline. It is implemented by wrapping the global `fetch`, so `XMLHttpRequest`,
`sendBeacon` and axios in its default browser build are **not** annotated and must set the
header themselves:

```ts
if (Pulse.sessionId) xhr.setRequestHeader("X-Pulse-Session-Id", Pulse.sessionId);
```

List only origins you control. The backend half is `pubky-pulse-node`.

## Feedback, questionnaires and attachments

`Pulse.sendFeedback(message, { name, email })` submits free text and throws on failure — a
person is waiting on it, so there is no retry. Questionnaires are fetched by slug and
rendered by you; the SDK ships data and pure answer helpers, no UI. Attachments ride along
in the per-call options.

Read `references/feedback-questionnaires-attachments.md` when the app needs a feedback form,
an in-app survey, or a file attached to an error.

## Privacy

The client key is public and the request body is visible in devtools, so nothing sensitive
belongs in an event: no tokens, passwords, card numbers, full request or response bodies,
`Authorization` or `Cookie` values, or raw IP addresses. Country is derived server-side.
Attach a file only when its bytes are what make the bug reproducible — never logs, stack
traces, screenshots, or anything reconstructible from attributes.

## Verify

Run the app, exercise the instrumented paths, then check with `data_mode: "development"` —
localhost is dev traffic, and the default `production` mode will show nothing:

- [ ] `pubky-pulse:query-events` with `data_mode: "development"`, `since: "15m"` returns
      `sdk:session_started` plus the events you added.
- [ ] `pubky-pulse:query-metric` shows a `start` and one terminal phase per operation.
- [ ] `pubky-pulse:query-funnel` with `mode: "open"` shows the steps you emitted.
- [ ] A deliberate throw appears via `pubky-pulse:query-events` with `level: "error"`.
      Issues are derived by an hourly scan, so `pubky-pulse:list-issues` lags behind.

Nothing arriving: check `allowed_origins` (a `403` on the ingest request is this), then the
initialization result (`disabled` for no key/SSR, `error` for invalid setup), then the
browser network tab and whether capture runs after browser initialization.

## Gotchas

- **Empty `allowed_origins` blocks everything.** A newly created web app has none.
- **The dev origin is a separate entry.** `http://localhost:3000` and `http://localhost:5173`
  are different origins, and so is `http://127.0.0.1:3000`.
- **Set the endpoint for self-hosting.** Omitting it uses the hosted ingest service. The
  client key identifies the web app; `bundleId` is optional legacy metadata.
- **Use `captureException` for unknown throws.** `Pulse.error("string", …)` is the logger
  overload. Retain the Error overload when per-event screen/attachment options are needed.
- **`console.error` is not captured**, and neither are React error boundaries, resource-load
  failures, `XMLHttpRequest`, or errors inside a web worker.
- **`networkTracking` is off by default.** When requested, prefer
  `{ urlMode: "origin" }` if paths contain identifiers. `true` retains sanitized paths.
  Session propagation does not require network events. Manual URL attributes are not sanitized
  by this setting; keep them origin-only or use approved templates.
- **Initialize before rendering when early errors matter.** A passive effect misses events
  from the first render. `init()` is safe at module scope during SSR and missing-key builds.
- **The first successful `init()` wins.** Changed options are ignored until shutdown or
  disable. `await Pulse.shutdown()` drains; `Pulse.init({ enabled: false })` discards pending
  memory without flushing. Disable preserves existing storage and cannot recall sent data;
  an old offline queue may replay on later initialization.
- **`configure()` remains strict.** It validates even during SSR and replaces a running
  configuration. Existing logger calls before setup retain their one-time console note.
- **`isDev` defaults to true only on `localhost`, `127.0.0.1` and `file:`.** A staging
  hostname counts as production until you set `isDev` yourself.
- **Attachments need a secure context** (`crypto.subtle`). Over plain HTTP the upload is
  skipped and the event still sends.
- **Questionnaires ship no UI on web** — fetch, render your own form, save.
- **Metric slugs are auto-corrected** to `^[a-z0-9-]+$` with one warning per page; funnel
  step names are not corrected at all.
- **`_`-prefixed attribute keys are reserved.** SDK values win over yours on a collision.
- **`supportedLanguages` overwrites the app record.** Only set it to the locales you ship.

## References

- `references/frameworks.md` — read when placing `init()` in Next.js (App or Pages
  Router), SvelteKit, Vue/Nuxt, Angular or a plain page, or when injecting `appVersion`
  from the bundler.
- `references/error-capture-patterns.md` — read when wiring an error boundary, a router
  error element, a query-library handler, an axios interceptor, or a web worker.
- `references/feedback-questionnaires-attachments.md` — read when the app needs a feedback
  form, an in-app survey, or a file attached to an event.
- `references/api-reference.md` — read when you need the full configuration table, an exact
  method signature, or the list of events the SDK emits by itself.
