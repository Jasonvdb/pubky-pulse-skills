## Contents

- Feedback: programmatic submit
- Feedback: the drop-in Compose view
- Feedback: strings and theming
- Questionnaires: create the definition first
- What end users see versus what stays internal
- The auto-trigger gate and its parameters
- Composable triggers and eligibility
- Manual presentation and resume
- One-shot save, dismissal, and where responses land

## Feedback: programmatic submit

```kotlin
lifecycleScope.launch {
    try {
        val receipt = Pulse.sendFeedback(
            message = "Love the new import flow!",
            name = currentUser?.displayName,   // optional
            email = currentUser?.email,        // optional
        )
        Log.d("Feedback", "stored ${receipt.id}")
    } catch (e: PulseFeedbackError) {
        // EmptyMessage, NotConfigured, ServerError, TransportFailure
        showRetrySnackbar()
    }
}
```

`sendFeedback` is a suspending call that goes straight to the server and is **not**
offline-queued: it returns a receipt on success and throws on failure, so the UI can
offer a retry rather than silently losing what the user typed. Session, user id, app
version, device and environment are attached automatically.

## Feedback: the drop-in Compose view

```kotlin
var showFeedback by remember { mutableStateOf(false) }

if (showFeedback) {
    ModalBottomSheet(onDismissRequest = { showFeedback = false }) {
        PulseFeedbackView(
            name = user?.displayName,
            email = user?.email,
            onSubmitted = { showFeedback = false },
            onCancel = { showFeedback = false },
        )
    }
}
```

It is an ordinary composable — put it in a sheet, on its own screen, or inline.
`showsContactFields = false` drops the optional name and email inputs;
`actionsPlacement` chooses the toolbar action (default) or an inline bottom bar,
which is the better fit when the view is embedded rather than presented.

Showing the contact fields means the app collects a name and an email address, which
changes the store's Data safety answers. See `privacy-play-data-safety.md`.

## Feedback: strings and theming

`PulseFeedbackStrings.DEFAULT` supplies every user-facing string; override the ones
that need the app's own voice or a localized resource. The view uses the ambient
Material theme, so colors and typography follow the app without extra work.

## Questionnaires: create the definition first

The SDK reads and submits; it never defines. Create the questionnaire before writing
the call site — dashboard, or `pubky-pulse:create-questionnaire`. The slug is
immutable after creation, so pick the call-site name carefully (`post-onboarding`,
`weekly-checkin`).

Question types: `text` (with an optional multiline variant), single choice, multi
choice (2–20 options), rating 1–5, NPS 0–10. Up to 30 questions.

## What end users see versus what stays internal

Most of the spec is user-facing copy. Getting this wrong ships a draft note to
production.

| Field | Where it shows | Visibility |
|---|---|---|
| `slug` | SDK call site only | internal |
| `name` | dashboard tables and team notifications | internal |
| `description` | **the in-app consent sheet body** — replaces the default consent copy when non-empty | user-facing |
| `questions[].title` | header on the question page | user-facing |
| `questions[].subtitle` | secondary text under the title | user-facing |
| `questions[].placeholder` | text-field placeholder | user-facing |
| `questions[].options[].label` | choice row label | user-facing |
| `questions[].id` | wire format and analytics column | internal |
| `is_active` | gates whether the SDK can fetch it | internal |

There is no private note field. `description` is the survey's pitch, written for
users ("Short survey — 30 seconds, helps us prioritise next month's work").

## The auto-trigger gate and its parameters

`PulseQuestionnaireGate` wraps content rather than decorating it, so put it around
the app's root composable:

```kotlin
PulseQuestionnaireGate(
    slug = "post-onboarding",
    trigger = PulseQuestionnaireTrigger.afterLaunches(3),
) {
    AppNavHost()
}
```

| Parameter | Default | What it does |
|---|---|---|
| `slug` | required | looks up the server-side spec; must match the created slug |
| `trigger` | `afterLaunch` | when to evaluate; conditions are ANDed |
| `showsConsent` | `true` | opens at a consent step (accept / maybe later / never) before the questions |
| `isEligible` | `null` | synchronous closure; return `false` to skip, re-evaluated on each foreground |
| `forceShow` | `false` | debug override: bypasses local gates and asks the server to ignore already-responded and dismissed. `is_active` still applies |
| `strings` | `DEFAULT` | overrides the surrounding chrome |
| `onSubmitted` | `null` | fires once, on the call that flips the response to submitted |
| `onCancel` | `null` | user dismissed without submitting |
| `onDismissed` | `null` | user chose the global opt-out |
| `content` | required | the wrapped app content |

**Progressive saves.** Answers persist on every Next, not only on Submit. If the user
leaves mid-flow, the next eligible launch resumes at the first unanswered question
with prior answers pre-filled — no extra code. Drafts are keyed server-side on the
user id, so they survive reinstalls, and the team notification fires only on the
final submit.

## Composable triggers and eligibility

```kotlin
PulseQuestionnaireGate(
    slug = "weekly-checkin",
    trigger = PulseQuestionnaireTrigger.whenAll(
        PulseQuestionnaireCondition.Launches(atLeast = 3),
        PulseQuestionnaireCondition.DaysSinceFirstLaunch(atLeast = 7),
    ),
    isEligible = { !user.isPaid },
) { AppNavHost() }
```

Conditions: `Launches`, `Foregrounds`, `DaysSinceFirstLaunch`, `HoursSinceFirstLaunch`
— each with an `atLeast`. Shortcuts: `afterLaunch`, `afterLaunches(n)`, `manual`
(never auto-trigger). There is no OR — use `isEligible`, or two gates with different
slugs.

Counts come from the SDK's own persistent state (`Pulse.launchCount`,
`Pulse.foregroundCount`, `Pulse.firstLaunchAt`), so a trigger counts launches since
the SDK was added to the app, not since the app's own first run.

## Manual presentation and resume

```kotlin
var spec by remember { mutableStateOf<PulseQuestionnaire?>(null) }
var draft by remember { mutableStateOf<PulseQuestionnaireDraft?>(null) }

LaunchedEffect(showSurvey) {
    if (!showSurvey) return@LaunchedEffect
    runCatching { Pulse.fetchQuestionnaire(slug = "post-import") }
        .onSuccess { result ->
            spec = result.questionnaire        // null → ineligible; result.ineligibleReason says why
            draft = result.inProgress          // resume mid-flow
        }
}

spec?.let { questionnaire ->
    PulseQuestionnaireView(
        questionnaire = questionnaire,
        inProgress = draft,
        showsConsent = draft == null,          // no consent prompt on resume
        onSubmitted = { showSurvey = false },
        onCancel = { showSurvey = false },
    )
}
```

## One-shot save, dismissal, and where responses land

For a fully custom UI, the underlying call is:

```kotlin
val receipt = Pulse.saveQuestionnaireResponse(
    slug = "post-import",
    answers = mapOf(
        "q_text" to PulseQuestionnaireAnswerValue.TextValue("Loved it"),
        "q_rating" to PulseQuestionnaireAnswerValue.RatingValue(5),
    ),
    isComplete = true,      // false saves a draft
)
// receipt.wasSubmitted is true exactly once — on the call that finalized it.
```

The server upserts on (project, slug, user id) and merges incoming keys, so no
response id has to be tracked client-side.

```kotlin
Pulse.dismissQuestionnaires()   // global opt-out for this user, idempotent, suspending
```

Responses and per-question analytics are readable over MCP with
`pubky-pulse:list-questionnaire-responses` and
`pubky-pulse:get-questionnaire-analytics`. Each response stores the schema snapshot it
was answered against, so editing the questionnaire later never rewrites history.
