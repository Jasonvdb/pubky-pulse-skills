## Contents

- [Choosing the action](#choosing-the-action)
- [Finding the call site](#finding-the-call-site)
- [Where each platform keeps its version](#where-each-platform-keeps-its-version)
- [Fix and resolve](#fix-and-resolve)
- [Downgrade](#downgrade)
- [Snooze and silence](#snooze-and-silence)
- [Merge](#merge)
- [Stale issues](#stale-issues)
- [When a write is refused](#when-a-write-is-refused)

## Choosing the action

| Evidence | Action |
|---|---|
| Reproducible fault in this repository's code, on the current release | fix, then resolve at the shipping version |
| Error the SDK already retries and the interface already handles | downgrade the log call to `warn`, then resolve |
| One occurrence, one user, no shared pattern | snooze |
| Infrastructure blip already accepted, nothing to fix, ever | silence |
| Same root cause as another issue | merge the newer into the older |
| Every occurrence on a version older than the current release | resolve at the current release |
| Real but not this session's work | leave open, keep the investigation comment |

Every one of these except the comment waits for the user to pick it.

## Finding the call site

Start from `_error_stack` and work inwards to the first frame that belongs to this
repository rather than to a dependency. Then confirm with the message text, which the
fingerprint normalised but the source did not.

```sh
# TypeScript / JavaScript
grep -rn '<message fragment>' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' . | head -20
grep -rn 'Pulse.error(' --include='*.ts' --include='*.tsx' --include='*.js' . | head -40

# Swift
grep -rn '<message fragment>' --include='*.swift' . | head -20
grep -rn 'Pulse.error(' --include='*.swift' . | head -40

# Kotlin
grep -rn '<message fragment>' --include='*.kt' . | head -20
grep -rn 'Pulse.error(' --include='*.kt' . | head -40
```

Because event messages are stable snake_case templates rather than interpolated
strings, the message from the issue usually greps straight to the `Pulse.error` call
that emitted it. When it does not, the message came from a thrown error rather than a
log call — grep for the error class in `_error_type` instead.

A web stack trace from a minified bundle points at the bundle, not the source. Fall
back to the `screen_name` on the occurrences (the URL path) and the preceding
breadcrumb events to locate the feature.

## Where each platform keeps its version

Read the current value before offering a bump, and never edit these files without an
explicit yes.

| Platform | File | Field |
|---|---|---|
| Apple | `*.xcodeproj/project.pbxproj`, or an `.xcconfig` | `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` for the build number) |
| Apple, older projects | `Info.plist` | `CFBundleShortVersionString` |
| Android | `app/build.gradle` or `build.gradle.kts` | `versionName` (and `versionCode`) |
| Node / web | `package.json` | `version` |
| Web, injected at build | the bundler config | whatever feeds `appVersion` into `Pulse.configure` |

```sh
grep -h 'MARKETING_VERSION' *.xcodeproj/project.pbxproj 2>/dev/null | sort -u | head -3
grep -rhE 'versionName' --include='build.gradle' --include='build.gradle.kts' . | head -3
grep -m1 '"version"' package.json 2>/dev/null
```

The value must be **monotonic** for regression detection to work. Semver and
date-style versions order correctly; a git SHA or a build hash orders alphabetically,
so `b12ef00` counting as newer than `a3f9c21` is luck rather than release order. If a
project's `appVersion` is a hash, say so — it is a separate bug worth fixing, and it
silently disables regression detection everywhere.

## Fix and resolve

1. Apply the smallest change that addresses the root cause the investigation found,
   not the symptom in the message.
2. Stop after editing. The user runs their own build and tests.
3. Bump the version only when asked, to the value the user picked.
4. `pubky-pulse:resolve-issue` with `version` set to the version the fix **ships in**.

The version is required by the server. It is what a later occurrence is compared
against: an occurrence on a newer version flips the issue to `regressed`
automatically, which is the whole point. Resolving at the version the bug was *found*
in means the very next occurrence — on the release that contains the fix — reads as a
regression, so the signal inverts.

If the fix is not shipping yet, `Don't bump — resolve once shipped` leaves the issue
`in_progress`, which is honest and costs nothing.

## Downgrade

The pattern: an error that is expected, handled, and already visible to the user. A
failed request the SDK retries; an offline save that queues; a cancelled upload. It
should never have been an `error`, and while it is one it clusters into an issue and
competes for attention with real faults.

The change is one word at the call site:

```diff
- Pulse.error(err, "receipt_sync_failed", { attempt: String(attempt) });
+ Pulse.warn("receipt_sync_failed", { attempt: String(attempt), reason: String(err) });
```

Two things to keep straight:

- `warn` events are still ingested, still queryable, and still show in a session
  timeline. Only issue clustering stops, because the scan looks at `error` level only.
- Pass the reason as an attribute if you drop the error object, or the diagnostic
  information goes with it. The reserved `_error_*` attributes are only extracted from
  an error passed to `Pulse.error`.

Then resolve at the app's current `latest_app_version` — the downgrade ships like any
other change, and if that call site ever emits `error` again, a new issue is created
as a safety net.

## Snooze and silence

Both stop notifications and neither claims a fix. The difference is what happens next
time:

- **Snooze** reverts the issue to `new` on the very next occurrence and re-fires the
  alert. Use it whenever the hypothesis is "this was a one-off" — snoozing tests that
  hypothesis for free.
- **Silence** is terminal. The issue stays silenced however often it recurs;
  occurrences are still recorded. Use it only for something already understood and
  accepted, where a recurrence would tell nobody anything new.

Snooze is the safer default. Reaching for silence because an issue is annoying is how
a real fault goes quiet permanently.

Both are reversible with `pubky-pulse:reopen-issue`, which puts the issue back to
`new`.

## Merge

`pubky-pulse:merge-issues` moves every fingerprint, occurrence and comment from the
source into the target, then deletes the source. It cannot be undone through the API.

- Target = the **older** issue, so the first-seen version and history survive.
- Merge on shared evidence: the same innermost application frame, the same
  `_error_type` with a shared root cause, or one error demonstrably causing the other.
- Do **not** merge on similar wording. Web messages are already canonicalised across
  Chrome, Firefox and Safari before fingerprinting, and errors carrying an
  `_error_type` are deliberately kept apart by runtime type. Two issues that survived
  both are usually different bugs.
- The hourly scan already aliases error events that fire within five seconds of each
  other in the same session, so a cascade from a single failure is one issue already.
  Two issues that were never aliased did not co-occur.

When declining a proposed merge, comment the reasoning on both issues so the next
investigation does not re-propose it.

## Stale issues

An issue whose occurrences all sit on versions older than the app's
`latest_app_version` was probably fixed by something already shipped. Resolving it at
`latest_app_version` is safe: if the error reappears on a newer version, regression
detection flips it back automatically and the team is alerted.

Check `latest_app_version` from `pubky-pulse:get-app` rather than from the repository —
it is computed from what production is actually running, and it is refreshed hourly,
so a release from the last hour may not be reflected yet.

Batch these: one question, several resolves, one line in the recap.

## When a write is refused

- `403 Requires project ownership` — the key's creator does not own this project. The
  status change cannot happen from here. Post the finding as a comment (commenting is
  exempt from ownership) and list, in the recap, exactly which transitions a human
  still has to make.
- `403 Missing permission: issues:write` — the key was never granted it. Even
  commenting is unavailable; keep the findings in the session summary and say they were
  not persisted.
- `403 This operation requires a user session` — human-only. Nothing unlocks it.
- `400` from `resolve-issue` — the version is missing or empty. Ask for one, or snooze
  instead. Never pass a placeholder.
