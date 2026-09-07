## Contents

- Why events go missing
- `wrapHandler`
- Where `configure()` goes in a serverless module
- AWS Lambda, Vercel, Firebase
- Runtimes this SDK cannot run on
- Graceful shutdown on a long-running server
- Containers and orchestrators
- One-shot scripts
- Buffer tuning

## Why events go missing

Events are buffered and sent on a timer (`flushIntervalMs`, 5 seconds) or once
`flushThreshold` (20) events are queued. The timer is `unref()`'d so it never keeps the
process alive. That leaves three ways to lose a batch:

| Situation | What happens | Fix |
|---|---|---|
| Serverless handler returns | the runtime freezes before the timer fires | `wrapHandler` |
| `SIGTERM` / `SIGINT` | `beforeExit` does not run for signal termination | signal handler calling `shutdown()` |
| `SIGKILL`, OOM, `process.exit()` in flight | nothing runs | flush earlier, or accept the loss |

The `beforeExit` hook the SDK registers covers only a graceful exit — the event loop
emptied, no signal. It is a safety net, not a strategy.

## `wrapHandler`

```ts
export const handler = Pulse.wrapHandler(async (event, context) => { /* … */ });
```

It awaits `Pulse.flush()` in a `finally` block, so the flush happens whether the handler
returned or threw; the return value is preserved and the exception is re-thrown afterwards.
`flush()` also awaits pending attachment uploads, so attached files leave too.

Use it on every serverless handler. On a long-running server it is worth wrapping the routes
where losing an event is unacceptable — payment capture, sign-up — and leaving the timer to
handle the rest; wrapping every route turns each request into an extra network round trip.

## Where `configure()` goes in a serverless module

At module scope, outside the handler:

```ts
import { Pulse } from "@synonymdev/pubky-pulse-node";

Pulse.configure({
  endpoint: process.env.PULSE_ENDPOINT!,
  apiKey: process.env.PULSE_API_KEY!,
  serviceName: "checkout-fn",
  appVersion: process.env.APP_VERSION,
});

export const handler = Pulse.wrapHandler(async (event) => { /* … */ });
```

A warm container reuses the module, so `configure()` runs once per container rather than
once per invocation. Calling it inside the handler would shut the previous transport down
and start a new session on every request.

The session id is per process, which means every invocation on a warm container shares one.
That is usually what you want on a worker; on a request-serving function, scope each
invocation with the caller's `X-Pulse-Session-Id` instead.

## AWS Lambda, Vercel, Firebase

Lambda and Vercel functions on the Node runtime need nothing beyond the pattern above.
Firebase's typed wrappers need an explicit parameter annotation, because `wrapHandler`'s
generic rest parameters defeat inference:

```ts
export const myFunction = onCall(
  Pulse.wrapHandler(async (request: CallableRequest) => { /* … */ }),
);
```

Without it: `Property 'data' does not exist on type 'unknown'`.

For Next.js route handlers on Vercel, either wrap the exported function or `await
Pulse.flush()` before every `return` — the wrapper is less error-prone, since a route with
several exits is easy to get wrong.

## Runtimes this SDK cannot run on

It depends on `node:crypto`, `node:zlib` and `node:fs`, so it does not load on Vercel Edge
Functions, Cloudflare Workers, Deno Deploy, or any other Edge runtime, and
`export const runtime = "edge"` on a Next.js route makes that route unable to use it. Keep
those routes on the Node runtime, or leave them uninstrumented and say so in the report —
do not reach for the browser SDK there, which needs a `window`.

## Graceful shutdown on a long-running server

```ts
const server = app.listen(port);

async function shutdown(signal: string) {
  Pulse.info("service_stopping", { signal });
  server.close();                 // stop accepting new connections
  await Pulse.shutdown();         // emit sdk:session_ended, flush, tear down
  process.exit(0);
}

process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
```

`shutdown()` removes the unhandled-error listeners, emits `sdk:session_ended` if a session
ever started, flushes buffered events and pending attachments, and clears state — after it,
log calls are dropped again until the next `configure()`. Order matters: stop taking work
first, then flush, then exit. Fastify's `onClose` hook and NestJS's `onApplicationShutdown`
(with `enableShutdownHooks()`) are the framework-native places for the same call.

## Containers and orchestrators

Kubernetes sends `SIGTERM` and then `SIGKILL` after `terminationGracePeriodSeconds` (30 by
default). The handler above finishes well inside that, but two things break it:

- **`SIGTERM` never reaches the process.** With `CMD node server.js` under a shell form, or
  under an init that does not forward signals, Node runs as a child and sees nothing. Use
  the exec form (`CMD ["node", "server.js"]`) so Node is PID 1, or an init that forwards.
- **Something else calls `process.exit()` first.** Anything exiting inside another `SIGTERM`
  handler cuts the flush short. Have one shutdown path.

## One-shot scripts

A migration or a backfill that ends immediately after its last log call may exit before the
timer fires. `beforeExit` usually saves it, but be explicit:

```ts
try {
  await run();
  Pulse.info("backfill_completed", { rows: String(count) });
} finally {
  await Pulse.shutdown();
}
```

## Buffer tuning

Defaults suit a steady service: 5-second interval, flush at 20 events, drop the oldest past
10,000 buffered. A burst-heavy process — a fan-out worker, a batch importer — can exceed
10,000 between flushes and silently lose the oldest. Raise `maxBufferSize`, or lower
`flushIntervalMs`, rather than logging less. Failed sends retry with exponential backoff up
to six attempts, honouring a server `Retry-After` up to 60 seconds; `flush()` and
`shutdown()` wait for a send already in flight, including one sleeping between retries.
