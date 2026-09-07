## Contents

- [Two different surfaces](#two-different-surfaces)
- [Feedback triage](#feedback-triage)
- [Questionnaire schema](#questionnaire-schema)
- [The five question types](#the-five-question-types)
- [Drafts and abandonment](#drafts-and-abandonment)
- [Reading the analytics](#reading-the-analytics)
- [Response triage](#response-triage)
- [Writing a good questionnaire](#writing-a-good-questionnaire)

## Two different surfaces

**Feedback** is one free-text message a user chose to send. It arrives synchronously,
carries whatever the user typed plus the session that produced it, and lands as a row
to triage.

**Questionnaires** are structured surveys defined on the server: up to 30 typed
questions behind an immutable slug, fetched and rendered in-app by the Swift and
Android SDKs. The web SDK exposes the same server flow as an API and ships no UI; the
Node SDK has no questionnaire surface at all.

Both share a four-state triage lifecycle (`new`, `in_review`, `addressed`,
`dismissed`), a comment thread, and the rule that deletion is human-only.

## Feedback triage

```text
list-feedback   { project_id, status: "new" }
get-feedback    { project_id, feedback_id }        → message, session_id, app_version, device
investigate-event { event_id, compact: true }      → what the user was doing
add-feedback-comment { project_id, feedback_id, body }
update-feedback-status { project_id, feedback_id, status: "in_review" }
```

Each row carries the submitter's optional name and email, the app and app version, the
environment, the device, and `is_dev`. `country_code` is derived server-side and is
always null for backend apps.

To reach the session timeline you need an event id, not just the session id: query one
event from that session first.

```json
// query-events
{ "session_id": "<from the feedback row>", "order": "asc", "limit": 1, "compact": true }
```

Then pass that event's id to `pubky-pulse:investigate-event`.

Status meanings: `in_review` while someone is looking, `addressed` once something
shipped or a reply went out, `dismissed` for spam, duplicates and anything not
actionable. Deleting is human-only by design — `dismissed` is the agent's version of
"no". Commenting needs `feedback:write` but **not** project ownership, so a finding can
always be recorded even when the status change is refused.

## Questionnaire schema

`pubky-pulse:create-questionnaire` takes `project_id`, `slug` (immutable), `name`,
optional `description`, optional `app_id` (omit for project-wide), `is_active`
(defaults true), and `schema`:

```json
{
  "version": 1,
  "questions": [
    {
      "id": "q_nps",
      "type": "nps",
      "title": "How likely are you to recommend Lofi to a friend?",
      "required": true
    },
    {
      "id": "q_reason",
      "type": "single_choice",
      "title": "What matters most to you right now?",
      "required": true,
      "options": [
        { "id": "speed",   "label": "Speed" },
        { "id": "offline", "label": "Offline support" },
        { "id": "price",   "label": "Price" }
      ]
    },
    {
      "id": "q_detail",
      "type": "text",
      "title": "Anything else you'd like to share?",
      "required": false,
      "multiline": true,
      "placeholder": "Optional — as much as you like"
    }
  ]
}
```

Rules the server enforces: `version` is `1`; 1–30 questions; every question `id`
matches `^[a-z0-9_]{1,32}$`; choice questions carry 2–20 options; a rating scale is
fixed at 5; NPS is implicitly 0–10. Text answers cap at 4000 characters.

The slug is immutable because the SDK call site references it. Renaming means creating
a new questionnaire.

## The five question types

| `type` | Answer shape | Notes |
|---|---|---|
| `text` | string | `multiline: true` renders a tall editor; otherwise a single-line field. Pair it with a `placeholder`. |
| `single_choice` | one option id | 2–20 options, each `{ id, label }`. |
| `multi_choice` | array of option ids | Same option shape; renders as toggles. |
| `rating` | integer 1–5 | Scale is fixed at 5. |
| `nps` | integer 0–10 | Implicit "not at all likely / extremely likely" ends. |

Any question can be `required: true`, which keeps Submit disabled until it is answered.

## Drafts and abandonment

The mobile SDKs save the answer set on **every Next tap**, not only on Submit. So a
response row exists as soon as the user answers the first question:

- A draft has `submitted_at: null`, `status: "draft"`, `schema_snapshot: null`, and
  only the answered keys in `answers`.
- Going back and changing an answer overwrites it in the same row.
- On the final Submit, `submitted_at` becomes non-null, `status` flips to `new`, and
  the live schema is snapshotted onto the response.
- The team notification fires only on that flip.
- A user with an unfinished draft resumes at their first unanswered question on the
  next eligible launch.
- Drafts untouched for 90 days are cleaned up by a daily job.

This is why a response count can look higher than the number of completed surveys.
`submitted_only: true` on the list and the analytics counts only submissions;
`status: "draft"` isolates the drafts.

Because drafts are counted per question, the natural drop-off across questions **is**
the abandonment curve — Q1 has more answers than Q5. That is a feature of the default
view, not a bug in the data.

## Reading the analytics

```json
// get-questionnaire-analytics
{ "project_id": "<p>", "questionnaire_id": "<q>", "data_mode": "production" }
```

Per question type:

- `text` — the 10 most recent answers, not aggregated. Quote a couple verbatim rather
  than paraphrasing all of them.
- `single_choice` / `multi_choice` — counts per option plus `total_answered`, which is
  the denominator percentages must use. A multi-choice question's counts sum to more
  than `total_answered`.
- `rating` — bucket counts for 1–5 plus the arithmetic mean.
- `nps` — bucket counts for 0–10, a detractor / passive / promoter split, and the
  standard score (% promoters − % detractors), which ranges from −100 to 100.

The response envelope carries `total_responses` (everything, drafts included) and
`submitted_count` (submissions only) — quote both, or the headline is ambiguous.

When summarising for a human: lead with the NPS or rating headline, give the split
that produced it, then two or three verbatim text answers, then the completion rate as
`submitted_count` of `total_responses`.

## Response triage

```text
list-questionnaire-responses { project_id, questionnaire_id, status: "new" }
get-questionnaire-response   { project_id, questionnaire_id, response_id }
add-questionnaire-response-comment { ..., body }
update-questionnaire-response-status { ..., status: "in_review" }
```

A submitted response carries its own `schema_snapshot`, so it renders against the
schema it was captured under even after the definition changes. Drafts have none and
render against the live schema until they complete.

Editing a questionnaire's schema is allowed at any time and applies going forward.
Removing or renaming a question id orphans those answers in the rollups — the question
simply disappears from new charts — while the raw answers survive in each response's
snapshot. Deleting a questionnaire or an individual response is human-only.

## Writing a good questionnaire

- Put the highest-signal question first. Everyone who starts answers question one;
  fewer reach the last.
- Three to six questions. Thirty is the ceiling, not a target.
- One NPS or rating question, then one open text question asking why — that pairing
  produces the number and the explanation for it.
- Give choice options short stable ids (`offline`, not `opt_2`); the id is what the
  analytics group by, and it outlives label edits.
- Mark at most one or two questions `required`; a required question late in the list
  converts abandonment into no data at all.
- Pin to one app with `app_id` only when the question is genuinely platform-specific.
