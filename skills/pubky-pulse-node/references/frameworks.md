## Contents

- The shape every framework needs
- Hono
- NestJS
- Koa
- Next.js route handlers
- Next.js server actions
- tRPC
- AWS Lambda
- Vercel functions
- Firebase Cloud Functions
- Raw `node:http`

## The shape every framework needs

Four pieces, whatever the framework:

1. a scope per request — `withUser` from your auth layer, `withSession` from the
   `X-Pulse-Session-Id` header;
2. one outcome event when the response is finished, carrying method, route pattern, status
   and duration;
3. one error hook, registered so nothing can bypass it;
4. a flush on the way out — `shutdown()` on a signal, or `wrapHandler` when the runtime
   freezes.

Every `withUser` below is opt-in and written unqualified for brevity: wire it only when the
developer has explicitly agreed to link analytics to real user ids (the
`pubky-pulse-instrument` step-4 gate asks). With no answer, leave that one line commented out
with a `// TODO(pulse): ...` marker and keep the `withSession` line beside it live — Node has
no anonymous id, so `withSession` is what preserves the browser-to-backend trace.

Express and Fastify are written out in `SKILL.md`. The rest follow.

## Hono

Hono's `c.set` / `c.get` carry the scope, and one middleware covers all four pieces:

```ts
import { Hono } from "hono";
import { Pulse, type ScopedPulse } from "@synonymdev/pubky-pulse-node";

type Env = { Variables: { pulse: typeof Pulse | ScopedPulse } };

const app = new Hono<Env>();

app.use("*", async (c, next) => {
  const sessionId = c.req.header("x-pulse-session-id");
  let scope: typeof Pulse | ScopedPulse = Pulse;
  const userId = c.get("userId");
  if (userId) scope = scope.withUser(userId);
  if (sessionId) scope = scope.withSession(sessionId);
  c.set("pulse", scope);

  const startedAt = Date.now();
  await next();
  const attrs = {
    method: c.req.method,
    route: c.req.routePath,
    status_code: String(c.res.status),
    duration_ms: String(Date.now() - startedAt),
  };
  if (c.res.status >= 500) scope.warn("request_handled", attrs);
  else scope.info("request_handled", attrs);
});

app.onError((err, c) => {
  c.get("pulse").error(err, "request_failed", { method: c.req.method, route: c.req.routePath });
  return c.json({ error: "Internal error" }, 500);
});
```

Hono runs on Edge runtimes too — this SDK does not. On Bun or Node it is fine; on Workers or
Vercel Edge it will not load, because it needs `node:crypto`, `node:zlib` and `node:fs`.

## NestJS

Nest wants two providers: an interceptor for the outcome event and an exception filter for
failures. Both are global, so no controller repeats itself.

```ts
// pulse.interceptor.ts
import { throwError } from "rxjs";
import { catchError, finalize } from "rxjs/operators";

@Injectable()
export class PulseInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest();
    const res = context.switchToHttp().getResponse();
    const sessionId = req.headers["x-pulse-session-id"];

    let scope: typeof Pulse | ScopedPulse = Pulse;
    if (req.user?.id) scope = scope.withUser(req.user.id);
    if (typeof sessionId === "string") scope = scope.withSession(sessionId);
    req.pulse = scope;

    const startedAt = Date.now();
    let status = 0;
    return next.handle().pipe(
      // catchError stashes the status the filter is about to send, so the
      // failure path reports the real code rather than the response's default.
      catchError((err) => {
        status = err instanceof HttpException ? err.getStatus() : 500;
        return throwError(() => err);
      }),
      // finalize runs exactly once, on completion or on error — tap would fire
      // per emission, which is none on the error path and several for a
      // multi-emission Observable. One request, one outcome event.
      finalize(() => {
        scope.info("request_handled", {
          method: req.method,
          route: req.route?.path ?? req.url,
          status_code: String(status || res.statusCode),
          duration_ms: String(Date.now() - startedAt),
        });
      }),
    );
  }
}
```

```ts
// pulse-exception.filter.ts
@Catch()
export class PulseExceptionFilter extends BaseExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const req = host.switchToHttp().getRequest();
    const status =
      exception instanceof HttpException ? exception.getStatus() : 500;

    // 4xx are expected outcomes, not defects: warn rather than error so they
    // never become issues.
    const log = req.pulse ?? Pulse;
    if (status >= 500) {
      log.error(exception instanceof Error ? exception : new Error(String(exception)),
        "request_failed", { method: req.method, route: req.route?.path ?? req.url });
    } else {
      log.warn("request_rejected", { status_code: String(status), route: req.url });
    }

    super.catch(exception, host);
  }
}
```

Register both in the root module and flush on shutdown:

```ts
providers: [
  { provide: APP_INTERCEPTOR, useClass: PulseInterceptor },
  { provide: APP_FILTER, useClass: PulseExceptionFilter },
]
```

```ts
// main.ts
app.enableShutdownHooks();
// or, in a module: onApplicationShutdown() { return Pulse.shutdown(); }
```

`super.catch(...)` keeps Nest's own response behaviour — dropping it turns every error into
a blank 500.

## Koa

One middleware, outermost, because Koa unwinds through the same function:

```ts
app.use(async (ctx, next) => {
  const sessionId = ctx.get("x-pulse-session-id");
  let scope: typeof Pulse | ScopedPulse = Pulse;
  if (ctx.state.user?.id) scope = scope.withUser(ctx.state.user.id);
  if (sessionId) scope = scope.withSession(sessionId);
  ctx.state.pulse = scope;

  const startedAt = Date.now();
  try {
    await next();
  } catch (err) {
    scope.error(err instanceof Error ? err : new Error(String(err)), "request_failed", {
      method: ctx.method,
      route: ctx._matchedRoute ?? ctx.path,
    });
    throw err;   // let Koa's own error handling produce the response
  } finally {
    scope.info("request_handled", {
      method: ctx.method,
      route: ctx._matchedRoute ?? ctx.path,
      status_code: String(ctx.status),
      duration_ms: String(Date.now() - startedAt),
    });
  }
});
```

## Next.js route handlers

There is no middleware layer that can hold a scope, so each handler builds its own. Keep it
to two lines with a helper:

```ts
// lib/pulse-request.ts
export async function scopedPulse(req: Request) {
  const session = await getSession();
  const sessionId = req.headers.get("x-pulse-session-id");
  let scope: typeof Pulse | ScopedPulse = Pulse;
  if (session?.userId) scope = scope.withUser(session.userId);
  if (sessionId) scope = scope.withSession(sessionId);
  return scope;
}
```

```ts
// app/api/checkout/route.ts
export async function POST(req: Request) {
  const pulse = await scopedPulse(req);
  const op = pulse.startOperation("checkout");
  try {
    const receipt = await charge(await req.json());
    op.complete();
    return Response.json(receipt);
  } catch (err) {
    pulse.error(err, "checkout_failed");
    op.fail(err instanceof Error ? err.message : String(err));
    return Response.json({ error: "Checkout failed" }, { status: 500 });
  }
}
```

The user id comes from the server session, never from the body. `Headers.get` returns
`string | null`, which is why the guard exists. On Vercel these run on the serverless
runtime — wrap them with `Pulse.wrapHandler` or `await Pulse.flush()` before returning; see
`serverless-and-shutdown.md`. The Edge runtime cannot run this SDK at all.

## Next.js server actions

Same shape, with the header read through `headers()`:

```ts
"use server";

export async function submitFeedback(message: string) {
  const session = await getSession();
  const sessionId = (await headers()).get("x-pulse-session-id");
  let pulse: typeof Pulse | ScopedPulse = Pulse.withUser(session.userId);
  if (sessionId) pulse = pulse.withSession(sessionId);

  pulse.step("feedback-submitted");
  await pulse.sendFeedback(message);
}
```

## tRPC

A middleware on the base procedure gives every procedure a scoped logger in its context:

```ts
const pulseMiddleware = t.middleware(async ({ ctx, path, type, next }) => {
  let scope: typeof Pulse | ScopedPulse = Pulse;
  if (ctx.userId) scope = scope.withUser(ctx.userId);
  if (ctx.sessionId) scope = scope.withSession(ctx.sessionId);

  const startedAt = Date.now();
  const result = await next({ ctx: { ...ctx, pulse: scope } });

  if (!result.ok) {
    scope.error(result.error, "procedure_failed", { procedure: path, type });
  }
  scope.info("procedure_handled", {
    procedure: path,
    type,
    ok: String(result.ok),
    duration_ms: String(Date.now() - startedAt),
  });
  return result;
});

export const publicProcedure = t.procedure.use(pulseMiddleware);
```

`next()` resolves with `{ ok: false, error }` rather than throwing, so a try/catch here
catches nothing — check `result.ok`. Put `ctx.sessionId` in the context from the
`X-Pulse-Session-Id` header in `createContext`.

## AWS Lambda

```ts
export const handler = Pulse.wrapHandler(async (event, context) => {
  const userId = event.requestContext?.authorizer?.userId;
  const sessionId = event.headers?.["x-pulse-session-id"];
  let pulse: typeof Pulse | ScopedPulse = Pulse;
  if (userId) pulse = pulse.withUser(userId);
  if (sessionId) pulse = pulse.withSession(sessionId);

  pulse.info("job_started", { request_id: context.awsRequestId });
  const result = await run(event);
  return { statusCode: 200, body: JSON.stringify(result) };
});
```

`wrapHandler` flushes in a `finally`, so events leave before the runtime freezes.
`configure()` runs at module scope, outside the handler, so a warm container reuses it.

## Vercel functions

Identical to Lambda on the Node runtime: `configure()` at module scope, `wrapHandler` around
the exported handler or route handler. `export const runtime = "edge"` is incompatible.

## Firebase Cloud Functions

`wrapHandler` uses generic rest parameters, so TypeScript cannot always infer the callback's
parameter type through a wrapper like `onCall`. Annotate it:

```ts
import { onCall, type CallableRequest } from "firebase-functions/v2/https";

export const myFunction = onCall(
  Pulse.wrapHandler(async (request: CallableRequest) => {
    Pulse.withUser(request.auth?.uid ?? "anonymous").info("function_invoked");
    return { ok: true };
  }),
);
```

Without the annotation you get `Property 'data' does not exist on type 'unknown'`.

## Raw `node:http`

```ts
const server = http.createServer((req, res) => {
  const sessionId = req.headers["x-pulse-session-id"];
  const pulse = typeof sessionId === "string" ? Pulse.withSession(sessionId) : Pulse;
  const startedAt = Date.now();

  res.on("finish", () => {
    pulse.info("request_handled", {
      method: req.method ?? "",
      status_code: String(res.statusCode),
      duration_ms: String(Date.now() - startedAt),
    });
  });

  handle(req, res).catch((err) => {
    pulse.error(err, "request_failed", { method: req.method ?? "" });
    res.writeHead(500).end();
  });
});
```

Use the route pattern rather than `req.url` once a router is involved — a raw URL makes one
attribute value per path parameter.
