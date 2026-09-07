## Contents

- Where the form lives
- What the SDK collects
- Conditional rows
- What the SDK does not do
- Security and deletion answers
- Permissions the SDK adds
- Anonymous id storage

The app's own collection is wider than the SDK's; this covers only what Pubky Pulse
sends. The developer remains the data controller and owns the final declaration.
This is guidance, not legal advice.

## Where the form lives

Play Console → the app → **Policy → App content → Data safety**. Google publishes a
summary of the answers on the store listing. The SDK collects analytics on the app's
behalf, so its collection is the app's collection.

## What the SDK collects

For each row, the form asks: collected or shared, required or optional, processed
ephemerally, and for what purpose. The answers below hold across the board:
**collected**, not shared, not ephemeral.

| What the SDK sends | Play data type | When | Purpose |
|---|---|---|---|
| Analytics events — `Pulse.info/debug/warn/error`, funnel steps, metrics, screen views, session start | App activity → App interactions / Other actions | always, after `configure` | App functionality, Analytics |
| Diagnostics — `Pulse.error(throwable)`, error type, stack trace, network status, launch timing, OS and device model | App info and performance → Crash logs, Diagnostics | on errors and lifecycle | App functionality, Analytics |
| Product interaction — which screens and features are used, in what order | App activity → App interactions | always | Analytics, App functionality |
| **User id** | App activity → Other user-generated content, or a user-ids entry when the form offers one | only if `Pulse.setUser` is called | App functionality, Analytics |
| **Feedback name and email** | Personal info → Name, Personal info → Email address | only if `PulseFeedbackView` shows contact fields and the user fills them | App functionality |
| Free-text feedback and questionnaire answers | App activity → Other user-generated content | on submit | App functionality, Analytics |

## Conditional rows

- **User id is opt-in.** By default events carry an anonymous device id
  (`pulse_anon_*`), not a personal identifier. It becomes a real id only after
  `Pulse.setUser`. An app that never calls it omits the user-id row.
- **Feedback name and email are opt-in and user-typed.** They exist only if the app
  renders the contact fields *and* the user chooses to fill them. Setting
  `showsContactFields = false`, or building a form without them, removes both rows.
- **Attachments are whatever the app uploads.** If the app attaches user documents or
  media to error events, declare the matching content type — and reconsider the
  attachment: never attach logs, stack traces, screenshots, or anything already
  reconstructible from the event.

## What the SDK does not do

- **Not used for tracking.** No cross-app or cross-site advertising, no data
  brokering. Do not tick "used for advertising or marketing" for any SDK-collected
  type.
- **No advertising identifier.** The SDK never requests, reads or transmits it, and
  declares no advertising-id permission.
- **Not shared with third parties.** "Sharing" means transfer to a separate company.
  Events go only to the ingest endpoint passed to `Pulse.configure` — a
  first-party destination the developer controls. Declare **collected**, not shared.
- **No location, contacts, photos, files, messages or audio** are harvested.

## Security and deletion answers

- **Encrypted in transit: yes.** Everything goes over HTTPS. Use an `https://`
  endpoint; the SDK does not send analytics in the clear.
- **Users can request deletion: yes, best-effort.** The backend belongs to the
  developer, so a user's events and their user row can be purged by id. Offer a
  request path — an in-app control or a documented contact — and point the form's
  deletion answer at it. Events already folded into anonymous time-series rollups are
  not personally identifiable and may be retained.

## Permissions the SDK adds

Two install-time permissions merge into the app's manifest. Neither is a runtime
permission, neither prompts, and neither needs a Data safety declaration of its own:

- `android.permission.INTERNET` — ship events to the ingest endpoint.
- `android.permission.ACCESS_NETWORK_STATE` — detect offline and queue events.

No advertising-id permission is declared, which is what backs the "no advertising
identifier" answers above.

## Anonymous id storage

The stable anonymous id lives in a private `SharedPreferences` file
(`org.pubky.pulse.sdk`) and leaves the device only as the id stamped on events sent
to the app's own endpoint. If the app opts that file into Auto Backup, the id can
follow a reinstall through the user's own Google backup — that is the user's backup,
governed by Google's backup terms, and is not a separate collection or sharing event.
