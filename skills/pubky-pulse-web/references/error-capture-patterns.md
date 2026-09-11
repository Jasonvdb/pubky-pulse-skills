## Contents

- What the SDK catches by itself
- React error boundary
- React Router `errorElement`
- SvelteKit, Vue and Angular equivalents
- TanStack Query, SWR and Apollo
- `fetch` responses that are not 2xx
- axios and anything on `XMLHttpRequest`
- Web workers
- Cross-origin `Script error.`
- Keeping messages stable

## What the SDK catches by itself

Two `window` listeners, installed while `captureUnhandled` is on: `error` and
`unhandledrejection`. Both are observers — they never call `preventDefault()`, so the
browser still logs the error and any other handler still runs. Each event is logged at
error level with `_unhandled` set to `uncaught_exception` or `unhandled_rejection`.

Use `captureException` (Web SDK 0.6.0+) at the owning boundary for handled failures.
Pass the original value without wrapping it; repeated capture of the same Error object is
attempted only once per client lifetime. Distinct objects and primitive values can repeat.
Centralize expected-error filtering, metadata allowlists and redaction in `ignoreErrors` /
`beforeSend` at initialization; see `api-reference.md`.

Everything else is yours. In particular: `console.error`, framework error boundaries,
resource-load failures (`<img>`, `<script>`), `XMLHttpRequest`, and anything thrown inside
a worker.

## React error boundary

React swallows a render error into the nearest boundary, so a boundary that does not report
is a silent failure. There is no hook form — it has to be a class:

```tsx
import { Component, type ErrorInfo, type ReactNode } from "react";
import { Pulse } from "@synonymdev/pubky-pulse-web";

export class PulseErrorBoundary extends Component<
  { children: ReactNode; fallback?: ReactNode },
  { hasError: boolean }
> {
  state = { hasError: false };

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    Pulse.captureException(error, {
      message: "react_render_failed",
      attributes: { component_stack: info.componentStack ?? "" },
    });
  }

  render() {
    return this.state.hasError ? (this.props.fallback ?? null) : this.props.children;
  }
}
```

Wrap the app once at the root, and again around any subtree that should degrade on its own
(a dashboard widget, an embedded editor). Reset `hasError` on navigation if the fallback
should not be sticky.

## React Router `errorElement`

A route's `errorElement` catches throws from its loaders, actions and render. Report from
the element, not from the loader:

```tsx
function RouteError() {
  const error = useRouteError();
  useEffect(() => {
    Pulse.captureException(error, { message: "route_error" });
  }, [error]);
  return <p>Something went wrong.</p>;
}
```

A route without an `errorElement` bubbles to the nearest ancestor that has one, so one at
the root plus one per independent area is usually enough.

## SvelteKit, Vue and Angular equivalents

SvelteKit — `src/routes/+error.svelte` for render and load failures, and `handleError` in
`src/hooks.client.ts` for the rest:

```ts
// src/hooks.client.ts
export const handleError: HandleClientError = ({ error, event }) => {
  Pulse.captureException(error, {
    message: "client_error",
    attributes: { route: event.route.id ?? "unknown" },
  });
  return { message: "Something went wrong." };
};
```

Vue — `app.config.errorHandler` (or Nuxt's `vue:error` hook) catches everything the
component tree throws:

```ts
app.config.errorHandler = (err, _instance, info) => {
  Pulse.captureException(err, { message: "vue_error", attributes: { info } });
};
```

Angular — routes through its own `ErrorHandler`, which is why the `window` hooks see so
little in an Angular app:

```ts
@Injectable()
export class PulseErrorHandler implements ErrorHandler {
  handleError(error: unknown): void {
    Pulse.captureException(error, { message: "angular_error" });
    console.error(error);
  }
}
```

Keep the `console.error` — replacing Angular's default handler otherwise silences the
developer console.

## TanStack Query, SWR and Apollo

Data libraries catch rejections and hand you an `error` value, so nothing reaches the
`unhandledrejection` hook. Report once, centrally, rather than in every component.

TanStack Query — the query cache, so one call covers every query:

```ts
const queryClient = new QueryClient({
  queryCache: new QueryCache({
    onError: (error) => {
      Pulse.captureException(error, { message: "query_failed" });
    },
  }),
  mutationCache: new MutationCache({
    onError: (error) => {
      Pulse.captureException(error, { message: "mutation_failed" });
    },
  }),
});
```

SWR — `onError` on the global config:

```tsx
<SWRConfig value={{ onError: (error) => Pulse.captureException(error, { message: "swr_failed" }) }}>
```

Apollo — an error link in front of the HTTP link:

```ts
const errorLink = onError(({ graphQLErrors, networkError, operation }) => {
  for (const e of graphQLErrors ?? []) {
    Pulse.captureException(e, {
      message: "graphql_error",
      attributes: { operation: operation.operationName },
    });
  }
  if (networkError) {
    Pulse.captureException(networkError, {
      message: "graphql_network_error",
      attributes: { operation: operation.operationName },
    });
  }
});
```

Query keys, mutation variables and request bodies can contain private values; add only
reviewed labels through the shared policy.

Note the retry interaction: with retries on, report the final outcome and put the attempt
count in an attribute rather than logging every attempt.

## `fetch` responses that are not 2xx

`fetch` rejects only on a network failure. A non-2xx response is resolved, so decide once
in the existing request layer how it becomes an application failure. If that layer throws
an error that a query-cache or another owning boundary already reports, let that boundary
capture it. Avoid a separate Pulse call just before every throw.

When automatic fetch diagnostics are requested, `networkTracking: { urlMode: "origin" }`
captures statuses and failures without path parameters. Session propagation works without
network tracking. If the app instead reports a response locally, use a stable message and
safe attributes, and ensure an outer layer does not also report the same outcome:

```ts
if (!res.ok) {
  Pulse.error("api_request_failed", {
    request: "load_orders",
    _http_method: "GET",
    _http_status: String(res.status),
  });
  return showRequestError(res.status);
}
```

A manual `_http_url` must be an approved route template or origin; the SDK's network URL
mode does not sanitize attributes you supply. Never put raw request URLs into error messages.

## axios and anything on `XMLHttpRequest`

The SDK wraps the global `fetch` only. axios in its default browser build uses
`XMLHttpRequest`, so neither the session header nor `networkTracking` sees it. One
interceptor pair fixes both:

```ts
api.interceptors.request.use((config) => {
  if (Pulse.sessionId) config.headers["X-Pulse-Session-Id"] = Pulse.sessionId;
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    Pulse.captureException(error, {
      message: "api_request_failed",
      attributes: {
        _http_method: (error.config?.method ?? "get").toUpperCase(),
        _http_status: String(error.response?.status ?? 0),
      },
    });
    return Promise.reject(error);
  },
);
```

Install this on an API client restricted to trusted destinations, because it attaches the
session header. If a query-cache boundary already owns reporting, retain only session
propagation here. Do not copy axios config or response bodies into attributes.

Re-reject: swallowing the error here would break every caller's own handling. A bare
`XMLHttpRequest` needs the same header set by hand — see the SDK's `Pulse.sessionId`.

## Web workers

A worker has its own global scope, so its failures never reach the page's `window`
listeners. Report from the page side, which is where `Pulse` is configured:

```ts
const worker = new Worker(new URL("./parser.worker.ts", import.meta.url), { type: "module" });

worker.onerror = (event) => {
  Pulse.captureException(event.error ?? event.message, {
    message: "worker_failed",
    attributes: { worker: "parser" },
  });
};
worker.onmessageerror = () => Pulse.error("worker_message_failed", { worker: "parser" });
```

Inside the worker, catch and `postMessage` a structured failure to the page rather than
trying to configure a second SDK instance there.

## Cross-origin `Script error.`

When a script served from another origin throws, the browser hides the detail and the
listener receives the literal message `Script error.` with no error object. Two fixes, in
order of preference:

1. Serve the script with `Access-Control-Allow-Origin` and add `crossorigin="anonymous"` to
   the `<script>` tag. The real message and stack then come through.
2. Failing that, accept it: the issue tracker canonicalises the `Script error.` literal
   across browsers, so all of them collapse into one issue rather than three.

Do not "fix" it by rewriting the message — that only fragments the issue.

## Keeping messages stable

The message is the issue-grouping key. Interpolating variable data into it splits one
problem across many issues, and the server's normalisation only strips the obvious shapes
(UUIDs, numbers, quoted strings).

```ts
Pulse.captureException(err, { message: "order_load_failed" });
```

Keep variable metadata in approved attributes, not interpolated messages. Pass the original
error rather than only its message: the extracted `_error_type` is
what keeps a `TypeError` and a `RangeError` with identical wording on separate issues.
