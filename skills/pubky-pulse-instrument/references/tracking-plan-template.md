## Contents

- [The template](#the-template)
- [Worked example: Lofi, a Next.js app with route handlers](#worked-example-lofi-a-nextjs-app-with-route-handlers)

## The template

One block per surface. Fill the `Where` column with a real `file:symbol` before
writing any code — a row you cannot place is a row you have not thought through.

```markdown
### <Project> <Platform> — app `<Project> <Platform>` (platform `<web|backend|apple|android>`)

Bundle id: `<value or —>` · Origins: `<list or —>` · App version from: `<source>`
Identity: `<linked | anonymous only>`

| Kind | Name | Where (file:symbol) | Attributes | Server definition |
|---|---|---|---|---|
| Event | `` | `` | `` | — |
| Metric | `` | `` | `` | `pubky-pulse:create-metric` |
| Funnel step | `` | `` | — | step of funnel `` |
| Error | `` | `` | `` | — |

Funnels: `<slug>` — `<step>` → `<step>` → `<step>`
Caps: <n>/25 events · <n>/8 metrics · <n>/3 funnels
```

`Identity` carries the answer to the step 4 gate, so the printed plan shows it and not
only the final report. `anonymous only` means every identity call is written commented
out at its callsite. Web, Swift and Android plans are otherwise unchanged, because the
anonymous id keeps filling `user_id`; a backend Funnel step row records nothing until
identity is opted in, so say that in the row instead of leaving it looking live.

## Worked example: Lofi, a Next.js app with route handlers

Lofi is a music-loop marketplace. `app/` holds the browser routes, `app/api/` holds
route handlers that talk to Postgres and a payment provider. That is two surfaces, so
two apps under one project.

Project `Lofi`, slug `lofi`.

### Lofi Web — app `Lofi Web` (platform `web`)

Bundle id: `app.lofi.com` · Origins: `https://app.lofi.com`, `http://localhost:3000` ·
App version from: `package.json` `version`, injected by `next.config.js` `env`
Identity: linked — the developer opted in at the step 4 gate

| Kind | Name | Where (file:symbol) | Attributes | Server definition |
|---|---|---|---|---|
| Event | `signed_up` | `app/(auth)/signup/actions.ts:signUp` | `method`, `referrer` | — |
| Event | `signed_in` | `app/(auth)/login/LoginForm.tsx:onSubmit` | `method` | — |
| Event | `loop_previewed` | `components/LoopCard.tsx:onPlay` | `loop_id`, `genre`, `bpm` | — |
| Event | `loop_added_to_cart` | `components/LoopCard.tsx:onAdd` | `loop_id`, `price_cents` | — |
| Event | `cart_viewed` | `app/cart/page.tsx:CartPage` | `item_count`, `total_cents` | — |
| Event | `checkout_completed` | `app/checkout/Confirm.tsx:onSuccess` | `order_id`, `total_cents`, `item_count`, `payment_method` | — |
| Event | `search_performed` | `components/SearchBar.tsx:onSearch` (debounced) | `query_length`, `result_count`, `genre_filter` | — |
| Event | `download_completed` | `app/library/Download.tsx:onDone` | `loop_id`, `format`, `bytes` | — |
| Metric | `checkout-submit` | `app/checkout/Confirm.tsx:submit` | `payment_method` | `pubky-pulse:create-metric` |
| Metric | `loop-download` | `app/library/Download.tsx:download` | `format` | `pubky-pulse:create-metric` |
| Funnel step | `checkout-cart` | `app/cart/page.tsx:CartPage` | — | step of funnel `checkout` |
| Funnel step | `checkout-address` | `app/checkout/Address.tsx:onNext` | — | step of funnel `checkout` |
| Funnel step | `checkout-payment` | `app/checkout/Payment.tsx:onSubmit` | — | step of funnel `checkout` |
| Funnel step | `checkout-confirmed` | `app/checkout/Confirm.tsx:onSuccess` | — | step of funnel `checkout` |
| Funnel step | `onboarding-signup` | `app/(auth)/signup/actions.ts:signUp` | — | step of funnel `onboarding` |
| Funnel step | `onboarding-verify` | `app/(auth)/verify/page.tsx:onVerified` | — | step of funnel `onboarding` |
| Funnel step | `onboarding-first-preview` | `components/LoopCard.tsx:onPlay` (first only) | — | step of funnel `onboarding` |
| Error | `sign_in_failed` | `app/(auth)/login/LoginForm.tsx:catch` | `reason` | — |
| Error | `checkout_failed` | `app/checkout/Confirm.tsx:catch` | `order_id`, `stage` | — |
| Error | `download_failed` | `app/library/Download.tsx:catch` | `loop_id`, `format` | — |
| Error | `api_request_failed` | `lib/api.ts:request` (non-2xx and throw) | `route`, `status_code` | — |
| Error | `render_failed` | `app/error.tsx:ErrorBoundary` | `route` | — |

Funnels: `checkout` — `checkout-cart` → `checkout-address` → `checkout-payment` →
`checkout-confirmed`; `onboarding` — `onboarding-signup` → `onboarding-verify` →
`onboarding-first-preview`
Caps: 8/25 events · 2/8 metrics · 2/3 funnels

Also on this surface: `propagateSessionTo: ["/api"]` so the browser session id reaches
the route handlers, and — identity being linked here — `void Pulse.setUser(user.id)`
after sign-in, never awaited on the sign-in path.

### Lofi Backend — app `Lofi Backend` (platform `backend`)

Bundle id: — · Origins: — · App version from: `process.env.APP_VERSION`
Identity: linked — same answer, so `withUser` is available to the backend steps

| Kind | Name | Where (file:symbol) | Attributes | Server definition |
|---|---|---|---|---|
| Event | `request_handled` | `lib/pulse-route.ts:withPulse` | `method`, `route`, `status_code`, `duration_ms` | — |
| Event | `order_placed` | `app/api/orders/route.ts:POST` | `order_id`, `item_count`, `total_cents`, `payment_method` | — |
| Event | `payment_captured` | `app/api/webhooks/payments/route.ts:POST` | `order_id`, `provider`, `amount_cents` | — |
| Event | `webhook_received` | `app/api/webhooks/payments/route.ts:POST` | `source`, `type` | — |
| Event | `license_issued` | `lib/licenses.ts:issue` | `order_id`, `loop_count` | — |
| Event | `nightly_royalties_completed` | `jobs/royalties.ts:run` | `processed`, `failed`, `duration_ms` | — |
| Metric | `process-payment` | `lib/payments.ts:charge` | `provider` | `pubky-pulse:create-metric` |
| Metric | `issue-licenses` | `lib/licenses.ts:issue` | — | `pubky-pulse:create-metric` |
| Funnel step | `checkout-confirmed` | `app/api/orders/route.ts:POST` (via `withUser`) | — | step of funnel `checkout` |
| Error | `request_failed` | `lib/pulse-route.ts:withPulse` catch | `method`, `route` | — |
| Error | `payment_failed` | `lib/payments.ts:catch` | `order_id`, `provider`, `code` | — |
| Error | `webhook_rejected` | `app/api/webhooks/payments/route.ts:catch` | `source`, `reason` | — |
| Error | `royalties_job_failed` | `jobs/royalties.ts:catch` | `batch_id` | — |
| Error | `db_query_failed` | `lib/db.ts:query` catch | `operation` | — |

Funnels: contributes `checkout-confirmed` to the web-defined `checkout` funnel, so a
payment webhook can complete a journey the browser started.
Caps: 6/25 events · 2/8 metrics · 0 new funnels

Note the shared step name. The funnel is project-scoped, so one definition spans both
apps; the backend emits its step through `Pulse.withUser(userId).step(...)`, because
an event with no `user_id` is excluded from funnel analytics entirely. That row exists
only because this plan's header says identity is linked; under `anonymous only` the
browser still completes the funnel through `checkout-confirmed` on the web surface.
