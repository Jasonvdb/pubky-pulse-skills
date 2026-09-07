## Contents

- Where `configure()` goes, per framework
- React with Vite
- Next.js App Router
- Next.js Pages Router
- SvelteKit
- Vue and Nuxt
- Angular
- Plain page, no bundler
- Routers that do not use the History API
- Injecting `appVersion` at build time
- Environment variables per bundler

## Where `configure()` goes, per framework

One rule covers all of them: `configure()` runs once, in the browser, before anything logs.
Put it at **module scope** of the first module the browser evaluates, not inside a mounted
effect — a passive effect such as `useEffect` runs after the first render has committed, so a
crash during that render, and anything the render itself logged, is already lost. Module
scope is safe on every server-rendered framework here because `configure()` needs `window`:
on a server render it validates its arguments and then returns without installing anything —
an accidental import from server code is harmless with a valid config and still throws with
an invalid one.

## React with Vite

```tsx
// src/main.tsx
import { createRoot } from "react-dom/client";
import { Pulse } from "@synonymdev/pubky-pulse-web";
import { App } from "./App";

Pulse.configure({
  endpoint: import.meta.env.VITE_PULSE_ENDPOINT,
  apiKey: import.meta.env.VITE_PULSE_KEY,
  bundleId: "app.acme.com",
  appVersion: __APP_VERSION__,
  propagateSessionTo: ["/api"],
});

createRoot(document.getElementById("root")!).render(<App />);
```

Configuring in the entry module, before `render`, is what makes a failure in the very first
render reportable — an error boundary that fires before `configure()` reports into a void.
It also sidesteps React StrictMode, which runs effects twice in development, where a second
`configure()` would tear the first pipeline down and start a new session.

## Next.js App Router

`configure()` needs `window`, so it lives in a client file mounted once in the root layout —
at that file's module scope, so it has run before the tree renders in the browser. The same
module is also evaluated during server rendering, where the call is a no-op. Keep the layout
synchronous — awaiting a session there to fill `userId` would opt the whole tree out of
static rendering.

```tsx
// app/pulse-provider.tsx
"use client";

import { Pulse } from "@synonymdev/pubky-pulse-web";

Pulse.configure({
  endpoint: process.env.NEXT_PUBLIC_PULSE_ENDPOINT!,
  apiKey: process.env.NEXT_PUBLIC_PULSE_KEY!,
  bundleId: "app.acme.com",
  appVersion: process.env.NEXT_PUBLIC_APP_VERSION,
  propagateSessionTo: ["/api"],
});

export function PulseProvider() {
  return null;
}
```

```tsx
// app/layout.tsx
import { PulseProvider } from "./pulse-provider";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <PulseProvider />
        {children}
      </body>
    </html>
  );
}
```

Both keys are `NEXT_PUBLIC_`, which is correct: the client key is public and ingest-scoped.
An agent key (`pulse_agent_…`) never belongs in a `NEXT_PUBLIC_` variable.

Identify the user from the client session the app already has, in its own hook:

```tsx
"use client";

export function usePulseUser() {
  const { user } = useAuth();
  useEffect(() => {
    if (user) void Pulse.setUser(user.id);
  }, [user]);
}
```

Route handlers and server actions are backend surfaces: instrument them with the Node SDK
(load `pubky-pulse-node`), reading the `X-Pulse-Session-Id` header that `propagateSessionTo`
adds. That makes a Next.js repository **two** Pulse apps — `<Project> Web` and
`<Project> Backend` — sharing one project.

## Next.js Pages Router

```tsx
// pages/_app.tsx
import { Pulse } from "@synonymdev/pubky-pulse-web";

Pulse.configure({ /* same options */ });

export default function App({ Component, pageProps }: AppProps) {
  return <Component {...pageProps} />;
}
```

Module scope, not `useEffect`: `_app.tsx` is evaluated on the server too, where the call does
nothing, and in the browser it runs before the first page renders.

The Pages Router navigates with the History API too, so screen tracking needs nothing extra.

## SvelteKit

```svelte
<!-- src/routes/+layout.svelte -->
<script lang="ts" context="module">
  import { browser } from "$app/environment";
  import { Pulse } from "@synonymdev/pubky-pulse-web";
  import { PUBLIC_PULSE_ENDPOINT, PUBLIC_PULSE_KEY } from "$env/static/public";

  if (browser) {
    Pulse.configure({
      endpoint: PUBLIC_PULSE_ENDPOINT,
      apiKey: PUBLIC_PULSE_KEY,
      bundleId: "app.acme.com",
      appVersion: __APP_VERSION__,
    });
  }
</script>

<slot />
```

The module block runs once when the layout module is loaded, before the component renders,
which `onMount` does not — it fires after the first mount, too late for a render failure in
the tree below. The `browser` guard is belt and braces: `configure()` is already a no-op
without `window`. Svelte 5 spells the same block `<script module>`.

`+error.svelte` is where render failures surface — report from it (see
`error-capture-patterns.md`). `+server.ts` endpoints are backend code: Node SDK.

## Vue and Nuxt

Vue with Vite — configure next to `app.mount()`:

```ts
const app = createApp(App);
Pulse.configure({ endpoint: import.meta.env.VITE_PULSE_ENDPOINT, /* … */ });
app.config.errorHandler = (err, _instance, info) => {
  Pulse.error(err instanceof Error ? err : new Error(String(err)), "vue_error", { info });
};
app.mount("#app");
```

Nuxt — a client-only plugin, so it never runs during server rendering:

```ts
// plugins/pulse.client.ts
export default defineNuxtPlugin((nuxtApp) => {
  Pulse.configure({ endpoint: useRuntimeConfig().public.pulseEndpoint, /* … */ });
  nuxtApp.hook("vue:error", (err) => {
    Pulse.error(err instanceof Error ? err : new Error(String(err)), "vue_error");
  });
});
```

Nuxt's `server/api/*` routes are backend code: Node SDK, second app.

## Angular

```ts
// src/app/app.config.ts
export const appConfig: ApplicationConfig = {
  providers: [
    {
      provide: APP_INITIALIZER,
      multi: true,
      useFactory: () => () => {
        Pulse.configure({
          endpoint: environment.pulseEndpoint,
          apiKey: environment.pulseKey,
          bundleId: "app.acme.com",
          appVersion: environment.version,
        });
      },
    },
    { provide: ErrorHandler, useClass: PulseErrorHandler },
  ],
};
```

`PulseErrorHandler` is in `error-capture-patterns.md`; Angular routes through its own
`ErrorHandler`, so the `window` hooks see far less than you would expect.

## Plain page, no bundler

```html
<script type="module">
  import { Pulse } from "https://esm.sh/@synonymdev/pubky-pulse-web";

  Pulse.configure({
    endpoint: "https://ingest.pulse.example.com",
    apiKey: "pulse_client_…",
    bundleId: "app.acme.com",
    appVersion: "1.4.0",
  });
</script>
```

Serve it over HTTP — a module import fails from `file://`, and attachments need a secure
context. The origin you serve from is the one that has to be in the app's `allowed_origins`.

## Routers that do not use the History API

Some hash routers never call `pushState`, so there is nothing to observe:

```ts
Pulse.configure({ /* … */ trackPageViews: false });
router.afterEach((to) => Pulse.trackScreen(to.name ?? to.path));
```

With `trackPageViews: false` the SDK still holds a current screen — only `trackScreen`
moves it.

## Injecting `appVersion` at build time

Read the version from `package.json` at build time. A git SHA is worse than nothing: the
version comparator falls back to string ordering on non-numeric segments, so "latest"
becomes whichever hash sorts highest.

| Bundler | How |
|---|---|
| Vite | `define: { __APP_VERSION__: JSON.stringify(pkg.version) }` in `vite.config.ts`, plus `declare const __APP_VERSION__: string` in a `.d.ts` |
| Next.js | `env: { NEXT_PUBLIC_APP_VERSION: pkg.version }` in `next.config.js` |
| SvelteKit | `define` in the Vite config, same as Vite |
| Angular | write it into `environment.ts` from a prebuild script, or read `version` from `package.json` with `resolveJsonModule` |
| Webpack | `new webpack.DefinePlugin({ __APP_VERSION__: JSON.stringify(pkg.version) })` |
| No bundler | hard-code it and bump it with the release |

## Environment variables per bundler

| Bundler | Public prefix | Read as |
|---|---|---|
| Vite | `VITE_` | `import.meta.env.VITE_PULSE_KEY` |
| Next.js | `NEXT_PUBLIC_` | `process.env.NEXT_PUBLIC_PULSE_KEY` |
| SvelteKit | `PUBLIC_` | `$env/static/public` |
| Nuxt | `runtimeConfig.public` | `useRuntimeConfig().public.pulseKey` |
| Angular | none | `environment.ts` |

The client key is meant to ship in the bundle. Keep it out of source control anyway, so
rotating it is a deploy rather than a commit.
