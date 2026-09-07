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
    Pulse.error(error, "react_render_failed", {
      component_stack: info.componentStack?.slice(0, 200) ?? "",
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
    Pulse.error(
      error instanceof Error ? error : new Error(String(error)),
      "route_error",
      { route: location.pathname },
    );
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
  Pulse.error(error instanceof Error ? error : new Error(String(error)), "client_error", {
    route: event.route.id ?? "unknown",
  });
  return { message: "Something went wrong." };
};
```

Vue — `app.config.errorHandler` (or Nuxt's `vue:error` hook) catches everything the
component tree throws:

```ts
app.config.errorHandler = (err, _instance, info) => {
  Pulse.error(err instanceof Error ? err : new Error(String(err)), "vue_error", { info });
};
```

Angular — routes through its own `ErrorHandler`, which is why the `window` hooks see so
little in an Angular app:

```ts
@Injectable()
export class PulseErrorHandler implements ErrorHandler {
  handleError(error: unknown): void {
    Pulse.error(error instanceof Error ? error : new Error(String(error)), "angular_error");
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
    onError: (error, query) => {
      Pulse.error(error instanceof Error ? error : new Error(String(error)), "query_failed", {
        query_key: JSON.stringify(query.queryKey).slice(0, 200),
      });
    },
  }),
  mutationCache: new MutationCache({
    onError: (error, _vars, _ctx, mutation) => {
      Pulse.error(error instanceof Error ? error : new Error(String(error)), "mutation_failed", {
        mutation_key: JSON.stringify(mutation.options.mutationKey ?? "").slice(0, 200),
      });
    },
  }),
});
```

SWR — `onError` on the global config:

```tsx
<SWRConfig value={{ onError: (error, key) => Pulse.error(error, "swr_failed", { key }) }}>
```

Apollo — an error link in front of the HTTP link:

```ts
const errorLink = onError(({ graphQLErrors, networkError, operation }) => {
  for (const e of graphQLErrors ?? []) {
    Pulse.error(new Error(e.message), "graphql_error", {
      operation: operation.operationName,
      path: e.path?.join(".") ?? "",
    });
  }
  if (networkError) {
    Pulse.error(networkError, "graphql_network_error", { operation: operation.operationName });
  }
});
```

Note the retry interaction: with retries on, report the final outcome and put the attempt
count in an attribute rather than logging every attempt.

## `fetch` responses that are not 2xx

`fetch` rejects only on a network failure. A `404` or a `500` is a resolved promise, so it
is invisible unless you check:

```ts
const res = await fetch(url, init);
if (!res.ok) {
  Pulse.error("api_request_failed", {
    _http_url: url,
    _http_method: init?.method ?? "GET",
    _http_status: String(res.status),
  });
  throw new Error(`${init?.method ?? "GET"} ${url} → ${res.status}`);
}
```

Use the reserved `_http_*` keys — the issue tracker discriminates network errors on method
and templated path, so a failure against a third party stays separate from one against your
own API. Do this once in the app's fetch wrapper, not at every call site.

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
    Pulse.error(error instanceof Error ? error : new Error(String(error)), "api_request_failed", {
      _http_url: error.config?.url ?? "",
      _http_method: (error.config?.method ?? "get").toUpperCase(),
      _http_status: String(error.response?.status ?? 0),
    });
    return Promise.reject(error);
  },
);
```

Re-reject: swallowing the error here would break every caller's own handling. A bare
`XMLHttpRequest` needs the same header set by hand — see the SDK's `Pulse.sessionId`.

## Web workers

A worker has its own global scope, so its failures never reach the page's `window`
listeners. Report from the page side, which is where `Pulse` is configured:

```ts
const worker = new Worker(new URL("./parser.worker.ts", import.meta.url), { type: "module" });

worker.onerror = (event) => {
  Pulse.error("worker_failed", {
    worker: "parser",
    detail: event.message ?? "",
    file: event.filename ?? "",
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
Pulse.error(err, `Failed to load order ${id}`);        // splits per order
Pulse.error(err, "order_load_failed", { order_id: id }); // one issue, filterable
```

Always pass the error object rather than only its message: the extracted `_error_type` is
what keeps a `TypeError` and a `RangeError` with identical wording on separate issues.
