## Contents

- Feedback
- Questionnaires: the server side
- Fetching a questionnaire
- The answer helpers
- Rendering and saving
- Opting out
- Attachments

## Feedback

Free text from a person who is waiting on the result. `sendFeedback` makes a single attempt
and throws on failure — there is no retry and no background queue — so surface the error and
let them try again.

```ts
try {
  const receipt = await Pulse.sendFeedback(message, { name: form.name, email: form.email });
  showThanks(receipt.id);
} catch (err) {
  setError((err as Error).message);
}
```

The message is trimmed and capped at 4000 characters; the SDK rejects an empty or over-long
one before the network. Session id, user id, app version, browser, OS and the dev flag are
filled in from the configured state — do not pass them yourself. A successful submission
also logs `sdk:feedback_submitted` recording *whether* a name and email were given, never
their values.

The Web SDK ships no form. Render one that fits the product: a textarea with `maxLength`
4000, an optional email field, a disabled submit while the message is blank, and an error
region with `role="alert"`.

Read submitted feedback with `pubky-pulse:list-feedback` and `pubky-pulse:get-feedback`.

## Questionnaires: the server side

A questionnaire is defined on the server, never in the app. Create it with
`pubky-pulse:create-questionnaire` before writing any client code: an immutable slug, up to
30 questions of type `text`, `single_choice`, `multi_choice` (2–20 options), `rating` (1–5)
or `nps` (0–10). The client only reads the spec and saves answers.

## Fetching a questionnaire

```ts
const result = await Pulse.fetchQuestionnaire("nps-q3");

if (result.ineligibleReason) {
  // "already_responded" | "globally_dismissed" | "inactive" — a normal outcome
  return;
}

showSurvey(result.questionnaire!, result.inProgress?.answers);
```

| Field | Meaning |
|---|---|
| `questionnaire` | the definition — `id`, `slug`, `name`, optional `description`, versioned `schema` |
| `inProgress` | an unsubmitted draft to resume: `responseId` and the answers saved so far |
| `ineligibleReason` | why there is nothing to show; not an error |

An unknown slug or a failed request throws `PulseQuestionnaireError` with a `reason` to
branch on: `not_configured`, `not_found`, `invalid_answers`, `already_responded`,
`globally_dismissed`, `inactive`, `server_error`, `network_error`. Pass `{ force: true }`
while developing to bypass the already-responded and dismissed gates; `inactive` is still
enforced server-side.

## The answer helpers

Pure functions over a plain object, so they suit React state, a Svelte store or bare DOM
equally:

| Helper | Purpose |
|---|---|
| `createAnswerStore(prefill?)` | start a store, optionally from a draft's answers |
| `setAnswer(store, questionId, value)` | new store with one answer set; empty clears it |
| `isAnswered(store, question)` | true when the answer has a usable value of the right shape |
| `hasAllRequired(store, schema)` | gate the submit button on this |
| `collected(store, schema)` | the set to send: known ids only, text trimmed, choices sorted |
| `firstUnansweredIndex(store, schema)` | where to land a resumed flow |

## Rendering and saving

`saveQuestionnaireResponse(slug, answers, isComplete)` saves a draft when `isComplete` is
false and submits when it is true. Always send the full accumulated set — that is what
`collected()` produces — because a save replaces the stored answers rather than patching
them.

```tsx
const [answers, setAnswers] = useState(() => createAnswerStore(draft));
const [index, setIndex] = useState(() => firstUnansweredIndex(answers, schema));

function answer(value: string | string[] | number) {
  const next = setAnswer(answers, schema.questions[index].id, value);
  setAnswers(next);
  void Pulse.saveQuestionnaireResponse(slug, collected(next, schema), false);
}

async function submit() {
  const receipt = await Pulse.saveQuestionnaireResponse(slug, collected(answers, schema), true);
  if (receipt.wasSubmitted) showThanks();
}
```

Saving a draft on every answer is what makes abandonment visible as a drop-off curve in
`pubky-pulse:get-questionnaire-analytics`. `receipt.wasSubmitted` is true only on the call
that flipped the response from draft to submitted, so a resumed flow shows its success state
exactly once.

## Opting out

```ts
const dismissedAt = await Pulse.dismissQuestionnaires();
```

Opts the current user out of **every** questionnaire in the project, permanently, and
returns the timestamp the server recorded. Offer it wherever a "don't ask me again" control
belongs; later fetches come back with `ineligibleReason: "globally_dismissed"`.

## Attachments

Logger calls take attachments in per-call options; `captureException` does not. Keep the
existing Error overload for this case, and ensure `err` is an `Error` (a string selects the
message logger overload):

```ts
Pulse.error(err, "import_failed", { rows: "1200" }, {
  attachments: [{ data: file, filename: "import.csv", contentType: "text/csv" }],
});
```

`data` is a `Blob` (a `File` from an `<input type="file">` is one) or a `Uint8Array`. The
file is hashed and uploaded on its own queue, so the event is never delayed; `Pulse.flush()`
waits for that queue.

Uploads need `crypto.subtle`, which browsers expose only in a secure context (HTTPS or
`localhost`). Over plain HTTP the upload is skipped with a debug note and the event still
sends — an attachment never costs you the error report it was attached to.

Attach a file only when its bytes are what make the bug reproducible: the document that
failed to parse, the malformed import. Never logs, stack traces, screenshots, or anything
reconstructible from the attributes you already send. Quotas are 250 MB per user and 5 GB
per project; check headroom with `pubky-pulse:get-project-attachment-usage` before asking a
user to reproduce something with a file attached.
