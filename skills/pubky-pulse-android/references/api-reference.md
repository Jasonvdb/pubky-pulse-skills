## Contents

- Artifacts and packages
- Configuration
- Logging
- Funnel steps
- Metrics
- Identity and user properties
- Session and launch state
- Feedback
- Questionnaires
- Attachments
- Compose surface
- Lifecycle
- Reserved messages and attribute keys

Every signature below is the SDK's own. Do not call a method that is not listed here.

## Artifacts and packages

| Artifact | Package | Holds |
|---|---|---|
| `org.pubky.pulse:pulse-android:0.1.0` | `org.pubky.pulse.android` | `Pulse`, `PulseOperation`, `PulseAttachment`, questionnaire and feedback models and errors |
| `org.pubky.pulse:pulse-android-compose:0.1.0` | `org.pubky.pulse.android.compose` | `Modifier.pulseScreen`, `PulseFeedbackView`, `PulseQuestionnaireGate`, `PulseQuestionnaireView`, the strings types |

`Pulse` is a Kotlin `object`, so every call is `Pulse.something(...)`.

## Configuration

```kotlin
@Throws(PulseConfigurationError::class)
public fun configure(
    context: Context,
    endpoint: String,
    apiKey: String,
    flushOnBackground: Boolean = true,
    compressionEnabled: Boolean = true,
    networkTrackingEnabled: Boolean = true,   // reserved, currently a no-op
    consoleLogging: Boolean = true,
)
```

`PulseConfigurationError` is sealed: `InvalidEndpoint`, `InvalidApiKey`,
`MissingBundleId`. The bundle id comes from `context.packageName`; the SDK never
takes one as a parameter. `configure` uses `applicationContext` internally, so
passing `this` from `Application` is correct.

## Logging

```kotlin
public fun info(
    message: String,
    screenName: String? = null,
    attributes: Map<String, String?> = emptyMap(),
    attachments: List<PulseAttachment>? = null,
)
```

`debug`, `warn` and `error` share that shape. `error` has a second overload:

```kotlin
public fun error(
    error: Throwable,
    message: String? = null,
    screenName: String? = null,
    attributes: Map<String, String?> = emptyMap(),
    attachments: List<PulseAttachment>? = null,
)
```

`null` attribute values are dropped before send. SDK-owned `_error_*` keys overwrite
caller-supplied keys of the same name. Each call also carries `file`, `function` and
`line` parameters that default to a stack-derived call site — leave them alone.

## Funnel steps

```kotlin
public fun step(stepName: String, attributes: Map<String, String?> = emptyMap())
```

Emits `step:<stepName>` at info level. `track(...)` is a deprecated alias that
forwards to `step`.

## Metrics

```kotlin
public fun startOperation(metric: String, attributes: Map<String, String?> = emptyMap()): PulseOperation
public fun recordMetric(metric: String, attributes: Map<String, String?> = emptyMap())
```

```kotlin
public class PulseOperation {
    public val trackingId: String
    public fun complete(attributes: Map<String, String?> = emptyMap())
    public fun fail(error: String, attributes: Map<String, String?> = emptyMap())   // String, not Throwable
    public fun cancel(attributes: Map<String, String?> = emptyMap())
}
```

`complete`, `fail` and `cancel` each add `tracking_id` and `duration_ms`; `fail` also
adds `error` and emits at error level. A slug that is not already `^[a-z0-9-]+$` is
auto-corrected to that shape with a Logcat warning.

## Identity and user properties

`setUser` and `clearUser` are opt-in — write them only when the developer has agreed to link
analytics to real user ids (the `pubky-pulse-instrument` step-4 gate asks), because they
change what the Play data safety form declares. Everything below works on the anonymous id.

```kotlin
public fun setUser(identifier: String)
public fun clearUser(newAnonymousId: Boolean = false)
public fun setUserProperties(properties: Map<String, String>)
public val currentUserId: String?
```

`setUser` and `clearUser` are safe before `configure` — the change is stashed and
applied when configuration runs. Up to 50 properties, keys ≤50 characters and values
≤200; an empty string value deletes a key; the server merges rather than replaces.

## Session and launch state

```kotlin
public val sessionId: String?      // null before configure
public val launchCount: Int
public val foregroundCount: Int
public val firstLaunchAt: Long?
```

A fresh session id is minted on every `configure` call.

## Feedback

```kotlin
public suspend fun sendFeedback(
    message: String,
    name: String? = null,
    email: String? = null,
): PulseFeedbackReceipt
```

Throws `PulseFeedbackError`: `EmptyMessage`, `NotConfigured`, `ServerError`,
`TransportFailure`. Message 1–4000 characters. Not offline-queued. A successful
submission also emits `sdk:feedback_submitted`.

## Questionnaires

```kotlin
public suspend fun fetchQuestionnaire(slug: String, force: Boolean = false): PulseQuestionnaireFetchResult
public suspend fun saveQuestionnaireResponse(
    slug: String,
    answers: Map<String, PulseQuestionnaireAnswerValue>,
    isComplete: Boolean,
): PulseQuestionnaireReceipt
public suspend fun dismissQuestionnaires(): java.util.Date
```

`PulseQuestionnaireFetchResult` carries `questionnaire` (null when ineligible),
`inProgress` (a resumable draft) and `ineligibleReason`. Answer values:
`TextValue`, `ChoiceValue`, `ChoicesValue(List<String>)`, `RatingValue(Int)`,
`NpsValue(Int)`.

## Attachments

```kotlin
PulseAttachment.file(file: File, name: String? = null, contentType: String? = null)
PulseAttachment.bytes(bytes: ByteArray, name: String, contentType: String? = null)
```

Pass through the `attachments` parameter of any log call — almost always
`Pulse.error`. Uploads run on their own coroutine and are strictly non-fatal: an
offline device or an exhausted quota drops the file and still sends the event. There
is no offline queue for attachments.

## Compose surface

```kotlin
public fun Modifier.pulseScreen(name: String): Modifier

@Composable public fun PulseFeedbackView(
    modifier: Modifier = Modifier,
    name: String? = null,
    email: String? = null,
    showsContactFields: Boolean = true,
    actionsPlacement: PulseFeedbackActionsPlacement = PulseFeedbackActionsPlacement.TOOLBAR,
    strings: PulseFeedbackStrings = PulseFeedbackStrings.DEFAULT,
    onSubmitted: ((PulseFeedbackReceipt) -> Unit)? = null,
    onCancel: (() -> Unit)? = null,
)

@Composable public fun PulseQuestionnaireGate(
    slug: String,
    modifier: Modifier = Modifier,
    trigger: PulseQuestionnaireTrigger = PulseQuestionnaireTrigger.afterLaunch,
    showsConsent: Boolean = true,
    isEligible: (() -> Boolean)? = null,
    forceShow: Boolean = false,
    strings: PulseQuestionnaireStrings = PulseQuestionnaireStrings.DEFAULT,
    onSubmitted: ((PulseQuestionnaireReceipt) -> Unit)? = null,
    onCancel: (() -> Unit)? = null,
    onDismissed: (() -> Unit)? = null,
    content: @Composable () -> Unit,
)

@Composable public fun PulseQuestionnaireView(
    questionnaire: PulseQuestionnaire,
    modifier: Modifier = Modifier,
    inProgress: PulseQuestionnaireDraft? = null,
    showsConsent: Boolean = false,
    strings: PulseQuestionnaireStrings = PulseQuestionnaireStrings.DEFAULT,
    onSubmitted: ((PulseQuestionnaireReceipt) -> Unit)? = null,
    onCancel: (() -> Unit)? = null,
    onDismissed: (() -> Unit)? = null,
)
```

Triggers: `PulseQuestionnaireTrigger.manual`, `.afterLaunch`, `.afterLaunches(n)`,
`.whenAll(vararg conditions)` with `PulseQuestionnaireCondition.Launches`,
`.Foregrounds`, `.DaysSinceFirstLaunch`, `.HoursSinceFirstLaunch`, each taking
`atLeast`.

## Lifecycle

```kotlin
public suspend fun shutdown()
```

Flushes the buffer and stops the background-flush observer; the SDK can be configured
again afterwards. There is no synchronous flush, and `flushOnBackground` (on by
default) covers ordinary app lifecycles — reach for `shutdown` only in a test harness
or a deliberate teardown.

## Reserved messages and attribute keys

The SDK owns `metric:<slug>:<start|complete|fail|cancel|record>`, `step:<name>`, and
the `sdk:` family (`session_started`, `app_foregrounded`, `app_backgrounded`,
`screen_appeared`, `screen_disappeared`, `feedback_submitted`,
`questionnaire_submitted`, `questionnaire_dismissed`). It also owns every
underscore-prefixed attribute key: `_error_*`, `_launch_ms`, `_duration_ms`,
`_connection`. Emit application events with plain snake_case messages and plain
attribute keys — the hand-rolled screen tracker in `screen-tracking.md` is the single
deliberate exception.
