## Contents

- What ships with the SDK
- App Privacy categories to declare
- Conditional declarations
- Tracking prompts and identifiers
- Required-reason APIs
- Privacy policy paragraph
- What carries forward

## What ships with the SDK

The package bundles a `PrivacyInfo.xcprivacy` manifest as a resource. Swift Package
Manager merges it into the app at build time — nothing to import, copy, configure or
call, and no change to `Package.swift`. Xcode's **Generate Privacy Report** on an
archive aggregates it into the app's combined report alongside every other package.

The privacy manifest and the store's privacy questionnaire are separate systems and
Apple does not sync them: the manifest is for static analysis at submission, the
questionnaire is what users read on the listing. Both have to be right.

## App Privacy categories to declare

On the next submission, open the app's **App Privacy** settings and tick these:

| Data type | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|
| Crash Data | No | No | App Functionality, Analytics |
| Other Diagnostic Data | No | No | App Functionality, Analytics |
| Product Interaction | No | No | Analytics, App Functionality |
| Performance Data | No | No | App Functionality, Analytics |
| Other User Content | No | No | App Functionality, Analytics |
| User ID | **Yes**, if the app calls `Pulse.setUser` | No | App Functionality, Analytics |

These match what the bundled manifest declares. Between them they cover error events,
lifecycle and event logs, screen views, funnel and metric events, network
instrumentation timings, custom attributes, and free-text feedback bodies.

## Conditional declarations

**`Pulse.setUser`** ties the SDK's anonymous id to an identifier the app supplies.
Declare **User ID** as linked to the user.

**`PulseFeedbackView` with `showsContactFields: true`** (the default) renders optional
Name and Email fields the user types into themselves. These are user-initiated, so
the SDK's own manifest does not declare them — but shipping that UI means the app
collects them:

- **Email Address** — linked to user, App Functionality, Customer Support
- **Name** — linked to user, App Functionality, Customer Support

Passing `showsContactFields: false`, or calling `Pulse.sendFeedback` without contact
arguments, removes both rows.

**Attachments** are whatever the app chooses to upload. If the app attaches user
documents or media to error events, declare the matching content category — and
reconsider whether the attachment is needed at all (never attach logs, stack traces,
screenshots, or anything already reconstructible from the event).

## Tracking prompts and identifiers

The SDK needs no App Tracking Transparency prompt:

- it does not read the advertising identifier and does not link `AdSupport`;
- it does not read `identifierForVendor`;
- it uses its own anonymous id (`pulse_anon_*`) stored only in this app's Keychain
  entry on this device, never shared across apps.

If the app shows an ATT prompt for other reasons, Pubky Pulse keeps working whether
the user grants or denies it. There is no separate prompt of its own.

## Required-reason APIs

| API category | Reason code | Why |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | persist the real user identifier set via `Pulse.setUser` |

No file-timestamp, boot-time, disk-space or active-keyboard APIs are used.

The bundled manifest covers only the SDK's own usage. If the app itself touches any
required-reason API — and most do, since `UserDefaults` is on the list — it still
needs its own `PrivacyInfo.xcprivacy` at the app target root.

## Privacy policy paragraph

Apple requires a privacy policy URL. If the current policy does not mention
third-party analytics, adapt this:

> We use Pubky Pulse, a self-hosted analytics service, to understand how users
> interact with our app and to diagnose errors. Pubky Pulse collects diagnostic data
> (including crash reports and event logs), product interaction data (such as screen
> views), and any feedback you choose to submit. If you sign in, your user
> identifier is linked to this data so we can support you and improve the product.
> Pubky Pulse does not use the data for cross-app tracking or advertising and does
> not access your device's advertising identifier.

## What carries forward

After the one-time questionnaire update, later submissions need no change. The
manifest travels with the package and updates when the package updates. Revisit the
app's App Privacy settings only when adopting a Pubky Pulse feature that introduces a
category not yet declared — most commonly turning on the feedback view's contact
fields.
