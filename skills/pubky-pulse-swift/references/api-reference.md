## Contents

- Configuration
- Logging
- Funnel steps
- Metrics
- Identity and user properties
- Session and launch state
- Feedback
- Questionnaires
- Attachments
- SwiftUI surface
- Lifecycle
- Reserved messages and attribute keys

Every signature below is the SDK's own. Do not call a method that is not listed here.

## Configuration

```swift
public static func configure(
    endpoint: String,
    apiKey: String,
    flushOnBackground: Bool = true,
    compressionEnabled: Bool = true,
    networkTrackingEnabled: Bool = true,
    consoleLogging: Bool = true,
    attributionEnabled: Bool = true      // pass false
) throws
```

Throws `PulseConfigurationError`: `.invalidEndpoint(String)`, `.invalidApiKey(String)`,
`.missingBundleId`. The bundle id comes from the app bundle; the SDK never takes one
as a parameter.

## Logging

```swift
public static func info(_ message: String, screenName: String? = nil,
                        attributes: [String: String?] = [:],
                        attachments: [PulseAttachment]? = nil,
                        file: String = #file, function: String = #function, line: Int = #line)
```

`debug`, `warn` and `error` share that shape. `error` has a second overload:

```swift
public static func error(_ error: Error, _ message: String? = nil,
                         screenName: String? = nil,
                         attributes: [String: String?] = [:],
                         attachments: [PulseAttachment]? = nil, …)
```

`file` / `function` / `line` default to the call site and become `source_module`;
never pass them explicitly. `nil` attribute values are dropped before send. SDK-owned
`_error_*` keys overwrite caller-supplied keys of the same name.

## Funnel steps

```swift
public static func step(_ stepName: String, attributes: [String: String?] = [:], …)
```

Emits `step:<stepName>` at info level. `track(_:)` is a deprecated alias that
forwards to `step`.

## Metrics

```swift
public static func startOperation(_ metric: String, attributes: [String: String?] = [:], …) -> PulseOperation
public static func recordMetric(_ metric: String, attributes: [String: String?] = [:], …)
```

```swift
public final class PulseOperation {
    public let trackingId: String
    public func complete(attributes: [String: String?] = [:], …)
    public func fail(error: String, attributes: [String: String?] = [:], …)   // String, not Error
    public func cancel(attributes: [String: String?] = [:], …)
}
```

`complete`, `fail` and `cancel` each add `tracking_id` and `duration_ms`; `fail` also
adds `error` and emits at error level. A slug that is not already
`^[a-z0-9-]+$` is auto-corrected to that shape with a console warning.

## Identity and user properties

```swift
public static func setUser(_ identifier: String)
public static func clearUser(newAnonymousId: Bool = false)
public static func setUserProperties(_ properties: [String: String])
public static var currentUserId: String? { get }
```

Up to 50 properties, keys ≤50 characters and values ≤200; an empty string value
deletes a key; the server merges rather than replaces. The anonymous id lives in the
Keychain (survives reinstall), the real user id in `UserDefaults` (does not).

## Session and launch state

```swift
public static var sessionId: String? { get }        // nil before configure
public static var launchCount: Int { get }
public static var foregroundCount: Int { get }
public static var firstLaunchAt: Date? { get }
```

A fresh session id is minted on every `configure` call.

## Feedback

```swift
@discardableResult
public static func sendFeedback(message: String, name: String? = nil,
                                email: String? = nil) async throws -> PulseFeedbackReceipt
```

Throws `PulseFeedbackError` (`.emptyMessage`, `.notConfigured`, `.serverError`,
`.transportFailure`). Message 1–4000 characters. Not offline-queued. A successful
submission also emits `sdk:feedback_submitted`.

## Questionnaires

```swift
public static func fetchQuestionnaire(slug: String, force: Bool = false) async throws -> PulseQuestionnaireFetchResult
public static func saveQuestionnaireResponse(slug: String,
                                             answers: [String: PulseQuestionnaireAnswerValue],
                                             isComplete: Bool) async throws -> PulseQuestionnaireReceipt
@discardableResult
public static func dismissQuestionnaires() async throws -> Date
```

`PulseQuestionnaireFetchResult` carries `questionnaire` (nil when ineligible),
`inProgress` (a resumable draft) and `ineligibleReason`. Answer values:
`.text`, `.choice`, `.choices`, `.rating`, `.nps`.

## Attachments

```swift
public struct PulseAttachment {
    public init(fileURL: URL, name: String? = nil, contentType: String? = nil)
    public init(data: Data, name: String, contentType: String? = nil)
}
```

Pass through the `attachments:` parameter of any log call — almost always
`Pulse.error`. Uploads are out of band and non-fatal: a quota rejection or an offline
device drops the file and still sends the event.

## SwiftUI surface

```swift
func pulseScreen(_ name: String) -> some View

func pulseQuestionnaire(slug: String,
                        trigger: PulseQuestionnaireTrigger = .afterLaunch,
                        showsConsent: Bool = true,
                        consentIcon: Image? = Image(systemName: "quote.bubble.fill"),
                        isEligible: (() -> Bool)? = nil,
                        forceShow: Bool = false,
                        tint: Color? = nil,
                        strings: PulseQuestionnaireStrings = .default,
                        onSubmitted: ((PulseQuestionnaireReceipt) -> Void)? = nil,
                        onCancel: (() -> Void)? = nil,
                        onDismissed: (() -> Void)? = nil) -> some View
```

```swift
PulseFeedbackView(name: String? = nil, email: String? = nil,
                  showsContactFields: Bool = true,
                  actionsPlacement: PulseFeedbackActionsPlacement = .toolbar,
                  strings: PulseFeedbackStrings = .default,
                  onSubmitted: ((PulseFeedbackReceipt) -> Void)? = nil,
                  onCancel: (() -> Void)? = nil)

PulseQuestionnaireView(questionnaire: PulseQuestionnaire,
                       inProgress: PulseQuestionnaireDraft? = nil,
                       showsConsent: Bool = false,
                       consentIcon: Image? = Image(systemName: "quote.bubble.fill"),
                       strings: PulseQuestionnaireStrings = .default,
                       onSubmitted: ((PulseQuestionnaireReceipt) -> Void)? = nil,
                       onCancel: (() -> Void)? = nil,
                       onDismissed: (() -> Void)? = nil)
```

Triggers: `.manual`, `.afterLaunch`, `.afterLaunches(n)`, `.when(conditions…)` with
`.launches(atLeast:)`, `.foregrounds(atLeast:)`, `.daysSinceFirstLaunch(atLeast:)`,
`.hoursSinceFirstLaunch(atLeast:)`.

## Lifecycle

```swift
public static func shutdown() async
@discardableResult
public static func handleWatchUserInfo(_ userInfo: [String: Any]) -> Bool
```

There is no synchronous flush: `shutdown()` drains the buffer and stops the
background-flush observer, and `flushOnBackground` (on by default) covers ordinary
app lifecycles. `handleWatchUserInfo` exists only on the iPhone side.

## Reserved messages and attribute keys

The SDK owns `metric:<slug>:<start|complete|fail|cancel|record>`, `step:<name>`, and
the `sdk:` family (`session_started`, `app_foregrounded`, `app_backgrounded`,
`screen_appeared`, `screen_disappeared`, `network_request`, `feedback_submitted`,
`questionnaire_submitted`, `questionnaire_dismissed`). It also owns every
underscore-prefixed attribute key: `_error_*`, `_http_*`, `_launch_ms`,
`_duration_ms`, `_connection`, `_unhandled`. Emit application events with plain
snake_case messages and plain attribute keys.
