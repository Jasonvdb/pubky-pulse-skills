## Contents

- Feedback: programmatic submit
- Feedback: the drop-in view
- Feedback: strings and tint
- Questionnaires: create the definition first
- What end users see versus what stays internal
- Auto-trigger modifier and its parameters
- Composable triggers and eligibility
- Manual presentation and resume
- One-shot save, dismissal, and where responses land

## Feedback: programmatic submit

```swift
do {
    let receipt = try await Pulse.sendFeedback(
        message: "Love the new import flow!",
        name: currentUser?.displayName,   // optional
        email: currentUser?.email         // optional
    )
    print("Feedback stored: \(receipt.id)")
} catch let error as PulseFeedbackError {
    // .emptyMessage, .notConfigured, .serverError, .transportFailure
    showAlert(error.localizedDescription)
}
```

Unlike events, `sendFeedback` is synchronous over the wire and **not offline-queued**:
it returns a receipt on success and throws on failure, so the UI can offer a retry
rather than silently losing what the user typed. Session, user id, app version,
device and environment are attached automatically.

## Feedback: the drop-in view

`PulseFeedbackView` is a plain SwiftUI `View` — present it as a sheet, push it, or
embed it inline.

```swift
// As a sheet
.sheet(isPresented: $showFeedback) {
    NavigationStack {
        PulseFeedbackView(
            name: user?.displayName,
            email: user?.email,
            onSubmitted: { _ in showFeedback = false },
            onCancel: { showFeedback = false }
        )
        .navigationTitle("Feedback")
    }
}

// As a navigation destination
NavigationLink("Send feedback") { PulseFeedbackView() }

// Embedded, without the optional contact fields
PulseFeedbackView(showsContactFields: false)
```

`actionsPlacement` chooses between the toolbar confirm action (`.toolbar`, the
default) and an inline bottom bar — use the inline placement when the view is
embedded rather than presented.

Showing the contact fields means the app collects a name and an email address, which
changes what its privacy declarations have to say. See `privacy-app-store.md`.

## Feedback: strings and tint

```swift
// Override one string
PulseFeedbackView(strings: .default.with(header: "How are we doing?"))

// Point at the app's own localized catalog
PulseFeedbackView(strings: PulseFeedbackStrings(
    header: LocalizedStringResource("feedback.header", table: "MyApp")
    // remaining fields keep their defaults
))
```

Both the toolbar action and the inline Send button read the SwiftUI environment
tint, so `.tint(.orange)` on any ancestor brands them. Applied at the `WindowGroup`
level, every Pubky Pulse surface downstream inherits it.

## Questionnaires: create the definition first

The SDK reads and submits; it never defines. Create the questionnaire before writing
the call site — dashboard, or `pubky-pulse:create-questionnaire`. The slug is
immutable after creation, so pick the call-site name carefully
(`post-onboarding`, `weekly-checkin`).

Question types: `text` (add `"multiline": true` for an answer longer than a phrase),
single choice, multi choice (2–20 options), rating 1–5, NPS 0–10. Up to 30 questions.

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

## Auto-trigger modifier and its parameters

```swift
struct RootView: View {
    var body: some View {
        TabView { … }
            .pulseQuestionnaire(slug: "post-onboarding", trigger: .afterLaunches(3))
    }
}
```

| Parameter | Default | What it does |
|---|---|---|
| `slug` | required | looks up the server-side spec; must match the created slug |
| `trigger` | `.afterLaunch` | when to evaluate; conditions are ANDed |
| `showsConsent` | `true` | opens at a small consent detent (accept / maybe later / never) before the questions |
| `consentIcon` | `Image(systemName: "quote.bubble.fill")` | icon on the consent sheet; `nil` hides it |
| `isEligible` | `nil` | synchronous main-thread closure; return `false` to skip, re-evaluated on each foreground |
| `forceShow` | `false` | debug override: bypasses local gates and asks the server to ignore already-responded and dismissed. `is_active` still applies |
| `tint` | `nil` | accent for the progress bar, rating stars, NPS chips and buttons |
| `strings` | `.default` | overrides the surrounding chrome via `PulseQuestionnaireStrings` |
| `onSubmitted` | `nil` | fires once, on the call that flips the response to submitted |
| `onCancel` | `nil` | user dismissed without submitting |
| `onDismissed` | `nil` | user chose the global opt-out |

When the trigger fires and the server says the user is eligible (has not responded,
has not globally dismissed), a non-swipe-dismissible sheet opens. Questions render
one per page with a progress bar and Back / Next / Submit, then an in-sheet success
page.

**Progressive saves.** Answers persist on every Next, not only on Submit. If the user
quits mid-flow, the next eligible launch resumes at the first unanswered question
with prior answers pre-filled — no extra code. Drafts are keyed server-side on the
user id, so they survive reinstalls, and team notification fires only on the final
submit.

## Composable triggers and eligibility

```swift
.pulseQuestionnaire(
    slug: "weekly-checkin",
    trigger: .when(.launches(atLeast: 3), .daysSinceFirstLaunch(atLeast: 7)),
    isEligible: { !user.isPaid }
)
```

Conditions: `.launches(atLeast:)`, `.foregrounds(atLeast:)`,
`.daysSinceFirstLaunch(atLeast:)`, `.hoursSinceFirstLaunch(atLeast:)`. Shortcuts:
`.afterLaunch`, `.afterLaunches(n)`, `.manual` (never auto-trigger). There is no OR
— use `isEligible` or attach two modifiers with different slugs.

Launch and foreground counts come from the SDK's own persistent state
(`Pulse.launchCount`, `Pulse.foregroundCount`, `Pulse.firstLaunchAt`), so a trigger
counts launches since the SDK was installed in the app, not since the app's own
first run.

## Manual presentation and resume

```swift
@State private var spec: PulseQuestionnaire?
@State private var inProgress: PulseQuestionnaireDraft?
@State private var show = false

Button("Take a quick survey") {
    Task {
        let result = try? await Pulse.fetchQuestionnaire(slug: "post-import")
        if let questionnaire = result?.questionnaire {
            spec = questionnaire
            inProgress = result?.inProgress      // resume mid-flow
            show = true
        }
        // questionnaire == nil → ineligible; result.ineligibleReason says why
    }
}
.sheet(isPresented: $show) {
    if let spec {
        NavigationStack {
            PulseQuestionnaireView(
                questionnaire: spec,
                inProgress: inProgress,
                showsConsent: inProgress == nil,   // no consent prompt on resume
                onSubmitted: { _ in show = false },
                onCancel: { show = false }
            )
        }
    }
}
```

## One-shot save, dismissal, and where responses land

For a fully custom UI, the underlying call is:

```swift
let receipt = try await Pulse.saveQuestionnaireResponse(
    slug: "post-import",
    answers: ["q_text": .text("Loved it"), "q_rating": .rating(5)],
    isComplete: true      // false saves a draft
)
// receipt.wasSubmitted is true exactly once — on the call that finalized it.
```

The server upserts on (project, slug, user id) and merges incoming keys, so no
response id has to be tracked client-side.

```swift
try await Pulse.dismissQuestionnaires()   // global opt-out for this user, idempotent
```

Responses and per-question analytics are readable over MCP with
`pubky-pulse:list-questionnaire-responses` and
`pubky-pulse:get-questionnaire-analytics`. Each response stores the schema snapshot
it was answered against, so editing the questionnaire later never rewrites history.
