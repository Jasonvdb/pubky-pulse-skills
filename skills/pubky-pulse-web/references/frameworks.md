## Contents

- Where `init()` goes, per framework
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

## Where `init()` goes, per framework

Use Web SDK 0.6.0 or newer. Put `init()` at module scope of the first browser entry
module when early error capture matters. A passive effect runs after the first render and
misses errors from that render. SSR and missing keys are quiet no-ops; a valid later browser
call works. Repeated initialization keeps the first successful configuration, so there is no
need for a custom initialization flag. Define callbacks and policy once in an app-owned module
and include them in the initial options.

Set `endpoint` explicitly for self-hosting. `bundleId` is optional legacy SDK metadata;
the client key identifies the app. Keep identity opt-in separate from initialization.

## React with Vite

```tsx
// src/main.tsx
import { createRoot } from "react-dom/client";
import { Pulse } from "@synonymdev/pubky-pulse-web";
import { App } from "./App";

Pulse.init({
  endpoint: import.meta.env.VITE_PULSE_ENDPOINT,
  apiKey: import.meta.env.VITE_PULSE_KEY,
  appVersion: __APP_VERSION__,
  propagateSessionTo: ["/api"],
});

createRoot(document.getElementById("root")!).render(<App />);
```

Configuring in the entry module, before `render`, is what makes a failure in the very first
render reportable — an error boundary that fires before `init()` reports into a void.
Repeated `init()` calls also preserve the session during React StrictMode replay.

## Next.js App Router

`init()` needs `window`, so it lives in a client file mounted once in the root layout —
at that file's module scope, so it has run before the tree renders in the browser. The same
module is also evaluated during server rendering, where the call is a no-op. Keep the layout
synchronous — awaiting a session there to fill `userId` would opt the whole tree out of
static rendering.

```tsx
// app/pulse-provider.tsx
"use client";

import { Pulse } from "@synonymdev/pubky-pulse-web";

Pulse.init({
  endpoint: process.env.NEXT_PUBLIC_PULSE_ENDPOINT,
  apiKey: process.env.NEXT_PUBLIC_PULSE_KEY,
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

Identify the user from the client session the app already has, in its own hook — only if the
developer opted into linking real user ids (the `pubky-pulse-instrument` step-4 gate asks);
otherwise leave the `setUser` line commented with a `// TODO(pulse): ...` marker:

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

Pulse.init({
  endpoint: process.env.NEXT_PUBLIC_PULSE_ENDPOINT,
  apiKey: process.env.NEXT_PUBLIC_PULSE_KEY,
  appVersion: process.env.NEXT_PUBLIC_APP_VERSION,
});

export default function App({ Component, pageProps }: AppProps) {
  return <Component {...pageProps} />;
}
```

Module scope, not `useEffect`: `_app.tsx` is evaluated on the server too, where the call does
nothing, and in the browser it runs before the first page renders.

The Pages Router navigates with the History API too. Supply `screenNameForPath` at
initialization to keep routes with identifiers as safe templates.

## SvelteKit

```svelte
<!-- src/routes/+layout.svelte -->
<script lang="ts" context="module">
  import { Pulse } from "@synonymdev/pubky-pulse-web";
  import * as publicEnv from "$env/static/public";

  const env: Record<string, string | undefined> = { ...publicEnv };
  Pulse.init({
    endpoint: env.PUBLIC_PULSE_ENDPOINT,
    apiKey: env.PUBLIC_PULSE_KEY,
    appVersion: __APP_VERSION__,
  });
</script>

<slot />
```

The module block runs once when the layout module is loaded, before the component renders,
which `onMount` does not — it fires after the first mount, too late for a render failure in
the tree below. `init()` is already a no-op without `window`, so no browser guard is needed.
Svelte 5 spells the same block `<script module>`.

The namespace copy allows a missing key to reach `init` as `undefined`: named imports from
[`$env/static/public`](https://svelte.dev/docs/kit/$env-static-public) require that variable
to exist at build time. Keep this static access for prerendered apps; dynamic public env
cannot be read during prerendering. Only public variables are copied; never use a private
environment module in browser code.

`+error.svelte` is where render failures surface — report from it (see
`error-capture-patterns.md`). `+server.ts` endpoints are backend code: Node SDK.

## Vue and Nuxt

Vue with Vite — configure next to `app.mount()`:

```ts
const app = createApp(App);
Pulse.init({
  endpoint: import.meta.env.VITE_PULSE_ENDPOINT,
  apiKey: import.meta.env.VITE_PULSE_KEY,
  appVersion: __APP_VERSION__,
});
app.config.errorHandler = (err, _instance, info) => {
  Pulse.captureException(err, { message: "vue_error", attributes: { info } });
};
app.mount("#app");
```

Nuxt — a client-only plugin, so it never runs during server rendering:

```ts
// plugins/pulse.client.ts
export default defineNuxtPlugin((nuxtApp) => {
  const config = useRuntimeConfig().public;
  Pulse.init({
    endpoint: config.pulseEndpoint,
    apiKey: config.pulseKey,
    appVersion: config.appVersion,
  });
  nuxtApp.hook("vue:error", (err) => {
    Pulse.captureException(err, { message: "vue_error" });
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
        Pulse.init({
          endpoint: environment.pulseEndpoint,
          apiKey: environment.pulseKey,
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

  Pulse.init({
    endpoint: "https://ingest.pulse.example.com",
    apiKey: "pulse_client_…",
    appVersion: "1.4.0",
  });
</script>
```

Serve it over HTTP — a module import fails from `file://`, and attachments need a secure
context. The origin you serve from is the one that has to be in the app's `allowed_origins`.

## Routers that do not use the History API

Some hash routers never call `pushState`, so there is nothing to observe:

```ts
Pulse.init({ endpoint: PULSE_ENDPOINT, apiKey: PULSE_KEY, trackPageViews: false });
router.afterEach((to) => Pulse.trackScreen(safeScreenName(to)));
```

Use an app-owned `safeScreenName` helper that returns approved route names/templates or
`"/unknown"`, never raw parameters. Automatic `screenNameForPath` does not transform manual
`trackScreen` names.

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
