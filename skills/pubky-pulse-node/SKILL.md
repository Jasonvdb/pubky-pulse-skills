---
name: pubky-pulse-node
description: >-
  Adds the Pubky Pulse Node SDK to a backend — Express, Fastify, Hono, Nest, tRPC,
  serverless handlers, workers and cron jobs. Covers configuration, the per-request
  middleware the SDK does not ship, user and session scoping, catching every error path,
  lifecycle metrics, funnel steps and graceful shutdown. Use when adding analytics or error
  tracking to an API or worker, or when a tracking plan needs backend instrumentation. Not
  for browser code (see pubky-pulse-web) or for planning what to track first (see
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

A backend app is the simplest kind: no `bundle_id`, no allowed origins, no browser rules.

| Input | Where it comes from | Trap |
|---|---|---|
| `endpoint` | the Pulse server base URL | no trailing path; the SDK appends its own |
| `apiKey` | the `client_secret` of a `backend` app (`pulse_client_…`) | server-side only — never a `NEXT_PUBLIC_`/`VITE_` variable |
| `serviceName` | your choice | labels which service emitted an event when several share the app |

Get them with `pubky-pulse:list-apps` / `pubky-pulse:get-app`, or create the app with
`pubky-pulse:create-app` (`platform: "backend"`, no `bundle_id`). A repository that serves
both a browser bundle and an API is **two** apps in one project — `<Project> Web` and
`<Project> Backend` — because they run on different platforms and carry different keys.

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

## Install and configure

```sh
npm install @synonymdev/pubky-pulse-node
```

Node 20+, zero runtime dependencies, ESM and CommonJS. It uses `node:crypto`, `node:zlib`
and `node:fs`, so it does not run on Edge runtimes or Workers — those need a different
approach entirely, not this SDK.

Configure exactly once, in a module every handler imports:

```ts
// src/lib/pulse.ts
import { Pulse } from "@synonymdev/pubky-pulse-node";

Pulse.configure({
  endpoint: process.env.PULSE_ENDPOINT!,
  apiKey: process.env.PULSE_API_KEY!,
  serviceName: "api",
  appVersion: process.env.APP_VERSION,
});

export { Pulse };
```

Importing that module — rather than calling `configure()` in each entry point — is what
keeps one process to one session and one flush timer. `isDev` defaults to
`process.env.NODE_ENV !== "production"`, so local runs stay out of production numbers on
their own. `appVersion` should increase between releases; a git SHA sorts alphabetically and
breaks issue regression detection.

## The request middleware the SDK does not ship

There is no Express or Fastify plugin in the package, so this is the part you write. It does
three things: scope every event in the request to a user and the caller's session, emit one
outcome event when the response finishes, and report anything that reaches the error handler.

### Express

```ts
import express, { type ErrorRequestHandler } from "express";
import { Pulse, type ScopedPulse } from "@synonymdev/pubky-pulse-node";

declare global {
  namespace Express {
    interface Request {
      pulse: typeof Pulse | ScopedPulse;
    }
  }
}

const app = express();

// 1. Scope. Mount after the auth middleware that populates req.auth, before the routes.
app.use((req, res, next) => {
  const sessionId = req.get("x-pulse-session-id");
  let scope: typeof Pulse | ScopedPulse = Pulse;
  if (req.auth?.userId) scope = scope.withUser(req.auth.userId);
  if (sessionId) scope = scope.withSession(sessionId);
  req.pulse = scope;

  // 2. One outcome event per request, whatever the exit path.
  const startedAt = Date.now();
  res.on("finish", () => {
    const attrs = {
      method: req.method,
      route: req.route?.path ?? req.path,
      status_code: String(res.statusCode),
      duration_ms: String(Date.now() - startedAt),
    };
    // warn on 5xx so a bad deploy stands out, without making it an issue —
    // only error-level events feed the issue tracker.
    if (res.statusCode >= 500) req.pulse.warn("request_handled", attrs);
    else req.pulse.info("request_handled", attrs);
  });

  next();
});

app.use("/api", routes);

// 3. The error handler is registered LAST, and must take four arguments —
//    Express identifies it by arity, so dropping `next` makes it an ordinary
//    middleware that never runs on failure.
const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  req.pulse.error(err instanceof Error ? err : new Error(String(err)), "request_failed", {
    method: req.method,
    route: req.route?.path ?? req.path,
  });
  res.status(500).json({ error: "Internal error" });
};
app.use(errorHandler);

// 4. Stop taking work, let the in-flight requests finish, then drain the buffer.
const server = app.listen(port);
process.on("SIGTERM", async () => {
  await Promise.race([
    new Promise((resolve) => server.close(() => resolve())),
    new Promise((resolve) => setTimeout(resolve, 10_000).unref()),
  ]);
  await Pulse.shutdown();
  process.exit(0);
});
```

`server.close()` only stops new connections and returns straight away — its callback is what
fires once the last in-flight request has finished. Shutting Pulse down before that point
kills those requests and throws away the events they were about to emit, so the order is:
await the close, then flush, then exit. The race caps the wait, because one stuck keep-alive
connection would otherwise hold the process until the orchestrator sends `SIGKILL`.

An async route handler that rejects reaches this error handler only on Express 5, or on
Express 4 with a wrapper that forwards to `next(err)`. On Express 4, wrap async handlers:
`const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);`.

`req.route` is undefined when nothing matched, so a 404 falls back to `req.path` and makes
one `route` value per URL tried. Send a constant there instead if scanners make that noisy.

### Fastify

```ts
import Fastify from "fastify";
import { Pulse, type ScopedPulse } from "@synonymdev/pubky-pulse-node";

declare module "fastify" {
  interface FastifyRequest {
    pulse: typeof Pulse | ScopedPulse;
    pulseStartedAt: number;
  }
}

const app = Fastify();

app.decorateRequest("pulse", null);
app.decorateRequest("pulseStartedAt", 0);

app.addHook("onRequest", async (request) => {
  const sessionId = request.headers["x-pulse-session-id"];
  let scope: typeof Pulse | ScopedPulse = Pulse;
  if (request.user?.id) scope = scope.withUser(request.user.id);
  if (typeof sessionId === "string") scope = scope.withSession(sessionId);
  request.pulse = scope;
  request.pulseStartedAt = Date.now();
});

app.addHook("onResponse", async (request, reply) => {
  const attrs = {
    method: request.method,
    route: request.routeOptions?.url ?? request.url,
    status_code: String(reply.statusCode),
    duration_ms: String(Date.now() - request.pulseStartedAt),
  };
  if (reply.statusCode >= 500) request.pulse.warn("request_handled", attrs);
  else request.pulse.info("request_handled", attrs);
});

app.setErrorHandler((error, request, reply) => {
  request.pulse.error(error, "request_failed", {
    method: request.method,
    route: request.routeOptions?.url ?? request.url,
  });
  reply.status(error.statusCode ?? 500).send({ error: "Internal error" });
});

app.addHook("onClose", async () => {
  await Pulse.shutdown();
});

process.on("SIGTERM", async () => {
  await app.close(); // resolves once in-flight requests finish, then runs onClose
  process.exit(0);
});
```

Fastify does the same sequencing for you: `app.close()` resolves only after the in-flight
requests are done, and the `onClose` hook flushes after that — so await it before exiting.

`onRequest` runs before the body is parsed, which is what you want — the scope has to exist
before anything can fail. Use `request.routeOptions.url` (the route pattern) rather than
`request.url`, so `/orders/:id` stays one value instead of one per order.

Read `references/frameworks.md` when the project is Hono, NestJS, Koa, tRPC, Next.js route
handlers or server actions, or a serverless handler — each has its own placement.

## Scoping rules

| Call | Effect |
|---|---|
| `Pulse.withUser(id)` | every event from the returned scope carries `user_id` |
| `Pulse.withSession(uuid)` | overrides the process-wide session id |
| `scope.withUser(...).withSession(...)` | chains in either order; scopes are immutable |
| `Pulse.info(msg, attrs, { sessionId })` | per-call override, the highest precedence |

Precedence is per-call `options.sessionId` > `withSession(...)` > the session `configure()`
generated. The user id comes from your auth layer — never from a request body or a header a
caller can set. The session id, by contrast, is safe to forward blindly: a non-UUID value is
ignored silently and the scope falls back to the process session, so a malformed header can
never break a handler. Turn on `debug: true` to see those rejections.

Without `withSession`, every request in the process shares one session id, and the dashboard
shows one enormous session that lines up with nothing.

## Catch every error

`configure()` installs `process.on("uncaughtException")` and `process.on("unhandledRejection")`
listeners that record the error with `_unhandled` and then preserve Node's crash semantics —
the process still dies exactly as it would have, so a process manager still has to restart
it. That covers the failures nobody handled. Everything caught is yours:

- [ ] **Framework error handler** — the Express 4-argument handler or Fastify's
      `setErrorHandler`, registered once, so no route needs its own try/catch for the
      500 path.
- [ ] **Queue workers** — a job that throws is marked failed by BullMQ or pg-boss and
      reaches no process handler; instrument the job body.
- [ ] **Scheduled jobs** — a `node-cron` callback that throws is swallowed by the scheduler.
- [ ] **WebSocket and Socket.IO** — connection, message and close handlers each need one.
- [ ] **Streams** — an `error` event on a pipeline is not an exception anywhere.
- [ ] **Database and outbound HTTP clients** — pool `error` events, and non-2xx responses
      from `fetch`, which resolve rather than reject.

Report at the layer that handles the failure, not at every layer it passes through — one
error, one event. Always pass the error value itself: the extracted `_error_type` is what
keeps different error classes with the same wording on separate issues, and Node errors also
contribute `code`, `errno`, `syscall` and `path`.

Read `references/error-capture-patterns.md` when wiring a queue worker, a cron job, a
WebSocket server, a stream pipeline, a database pool, or an outbound HTTP client.

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

On a backend specifically: health checks, heartbeats and keep-alives are noise; a nightly
job that processes 10,000 rows is one event with `processed`, `failed` and `duration_ms`,
not 10,000 events; a retried call is one event carrying `retry_count`.

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

## Events

```ts
req.pulse.info("order_placed", {
  order_id: order.id,
  item_count: String(order.items.length),
  total_cents: String(order.totalCents),
  payment_method: order.paymentMethod,
  duration_ms: String(Date.now() - startedAt),
});
```

`source_module` (`routes/orders.ts:123`) is captured from the call stack automatically —
do not pass it. Attribute values are stringified and capped at 200 characters; the message
is capped at 2000. Backend events never carry a screen name or a country: `screen_name` is a
client concept, and `country_code` is always null for a backend app because the request
reaches Pulse from your datacenter. If you need per-user geography, put it in an attribute.

## Metrics

Create the definition with `pubky-pulse:create-metric` first, then wrap the operation:

```ts
const op = req.pulse.startOperation("process-payment", { provider: "stripe" });
try {
  const charge = await charge(order);
  op.complete({ charge_id: charge.id });
} catch (err) {
  op.fail(err instanceof Error ? err.message : String(err), { order_id: order.id });
  throw err;
}
```

`op.fail(error: string, attrs?)` on the Node SDK takes a **string**, not the error value.
Attributes are stringified with `String(value)`, so passing an `Error` records
`"Error: boom"` and passing a thrown plain object records `"[object Object]"` — either way
the type, stack and cause chain are lost. (The web SDK's `fail` takes the value itself; do
not copy a snippet across.) Report the error separately with `pulse.error(err, …)` when you
want those `_error_*` attributes; the hourly issue scan aliases both onto one issue when
they happen in the same session within five seconds.

Start an operation from the scoped logger, not the global one, so every phase carries the
user and session. `op.cancel()` is for abandoned work; finishing more than once double-counts
here, unlike on web, so keep exactly one terminal call per exit path.
`Pulse.recordMetric("queue-depth", { size: String(queue.length) })` covers a value you
already have.

## Funnels

Create the funnel with `pubky-pulse:create-funnel` first, then emit its steps from a
**user-scoped** logger:

```ts
const pulse = Pulse.withUser(userId);
pulse.step("checkout-payment");
```

Events with no `user_id` are excluded from funnel analytics entirely, so a bare
`Pulse.step(...)` from the global logger is silently dropped from every funnel it should
have fed. This is the single most common backend funnel mistake. Backend steps pair with
browser steps under the same user id — a webhook confirming a payment completes a funnel the
browser started.

## Feedback

`Pulse.sendFeedback(message, options)` forwards feedback your own frontend collected. It
awaits the server and throws on failure, so wrap it. A scoped logger fills in the user and
session for you:

```ts
const receipt = await req.pulse.sendFeedback(req.body.message, { email: req.body.email });
```

A browser can post feedback to Pulse directly with the web SDK; forward through Node when it
should be attributed to the backend app, when it arrives from something other than a browser,
or when only the server knows who the user is. There are no screens, no `setUser` and no
questionnaires in this SDK.

## Serverless and shutdown

Serverless runtimes freeze the process the moment a handler returns, so the flush timer may
never fire. Wrap the handler:

```ts
export const handler = Pulse.wrapHandler(async (event) => { /* … */ });
```

`wrapHandler` awaits `Pulse.flush()` in a `finally` block, preserving the return value and
re-throwing. On a long-running server the interval flush covers normal operation, and
`SIGTERM` → `await Pulse.shutdown()` covers the exit; the built-in `beforeExit` hook only
catches a graceful, signal-free exit.

Read `references/serverless-and-shutdown.md` when deploying to Lambda, Vercel functions or
Firebase, or when a container is being killed before its buffer drains.

## Privacy

Never put these in a message or an attribute — the caps truncate, they do not redact:
secrets, API keys, bearer tokens, cookies, JWT contents, passwords, card or account numbers,
full request or response bodies, `Authorization` / `Cookie` header values, or raw IP
addresses. Log status codes, sizes and resource ids instead. Do not pass `error.stack` as an
attribute value: pass the error to `pulse.error()` and let the SDK put it in `_error_stack`
with the right cap and the right fingerprinting key. Attach a file only when its bytes are
what make the bug reproducible — never logs or stack traces.

## Verify

Run the service, exercise the instrumented paths, then check with
`data_mode: "development"` — a local process has `NODE_ENV !== "production"`, so the default
`production` mode will show nothing:

- [ ] `pubky-pulse:query-events` with `data_mode: "development"`, `since: "15m"` returns
      `sdk:session_started` plus your outcome events.
- [ ] Events from a request made by the browser carry the same `session_id` as the browser's.
- [ ] `pubky-pulse:query-metric` shows a `start` and one terminal phase per operation.
- [ ] `pubky-pulse:query-funnel` with `mode: "open"` shows steps — if it is empty, the steps
      were emitted without `withUser`.
- [ ] A deliberate throw appears via `pubky-pulse:query-events` with `level: "error"`.
      Issues come from an hourly scan, so `pubky-pulse:list-issues` lags behind.

Nothing arriving at all: check the process actually imported the configuring module, that
the key belongs to a `backend` app, and that the process lived long enough to flush (a
one-shot script needs `await Pulse.flush()` before it exits).

## Gotchas

- **`op.fail` takes a string here.** `op.fail(err.message)` or `op.fail(String(err))`; the
  web SDK's `fail(err: unknown)` signature does not apply.
- **Global `Pulse.step()` is excluded from every funnel.** Funnels need a `user_id`.
- **One session per process without `withSession`.** Forward `X-Pulse-Session-Id`.
- **A non-UUID session id is ignored silently.** Safe to forward, invisible when wrong —
  `debug: true` is how you find out.
- **Auto-capture does not prevent the crash.** The process still exits; the supervisor
  restarts it. Buffered events may be lost on a hard kill.
- **`beforeExit` does not fire on `SIGTERM` or `SIGINT`.** Add the signal handler.
- **Serverless needs `wrapHandler`.** The 5-second timer will not have fired.
- **Not an Edge or Workers runtime SDK.** It needs `node:crypto`, `node:zlib`, `node:fs`.
- **`serviceName` is not a `bundle_id`.** Backend apps have none; the key identifies the app.
- **The client key is server-side only.** It never belongs in a `NEXT_PUBLIC_` variable, even
  though it is called public — that publicity is about the browser app's own key.
- **Express identifies the error handler by arity.** Four parameters, registered last.
- **Metric slugs are auto-corrected** to `^[a-z0-9-]+$` (warned only with `debug: true`);
  funnel step names are kept verbatim.
- **`setUserProperties` differs by receiver.** `Pulse.setUserProperties(userId, props)`
  globally, `scope.setUserProperties(props)` on a user scope, and it is fire-and-forget.
- **Backend events carry no country and no screen name.** Both are client concepts.
- **The buffer drops the oldest events past `maxBufferSize`** (10000). A burst-heavy service
  wants a larger buffer or a shorter flush interval.

## References

- `references/frameworks.md` — read when the project is Hono, NestJS, Koa, tRPC, Next.js
  route handlers or server actions, or a Lambda / Vercel / Firebase handler.
- `references/error-capture-patterns.md` — read when instrumenting a queue worker, a cron
  job, a WebSocket server, a stream pipeline, a database client, or outbound HTTP.
- `references/serverless-and-shutdown.md` — read when deploying to a serverless runtime, or
  when events go missing on deploy, restart or container shutdown.
- `references/api-reference.md` — read when you need the full configuration table, an exact
  method signature, or the attachment and error-attribute contracts.
