## Contents

- [The rule](#the-rule)
- [The three refusals](#the-three-refusals)
- [What is human-only](#what-is-human-only)
- [What an agent key may write](#what-an-agent-key-may-write)
- [Comments are exempt from ownership](#comments-are-exempt-from-ownership)
- [Key types](#key-types)
- [Diagnosing a refusal](#diagnosing-a-refusal)

## The rule

An agent key belongs to a person and acts for that person. Reads follow the key's
permissions; writes follow the person's project ownership.

```text
allowed = key is active
       AND key holds the route's explicit permission
       AND the creator is an active team member on an allowed email domain
       AND the creator currently owns the target project
       AND the operation is agent-supported
```

An intersection, never a union. Holding `projects:write` does not by itself let the key
write to a project, and owning a project does not substitute for the permission.

Two consequences worth internalising:

- **Reads are team-wide.** If `pubky-pulse:list-projects` shows a project, every read
  permission the key holds works against it. There is nothing to unlock per project.
- **Ownership is re-read on every request.** A human adding the creator to a project's
  owner list takes effect on the very next tool call. Nothing is re-issued,
  reconnected, or restarted. The same is true in reverse.

`pubky-pulse:create-project` makes the creator the new project's first owner, in the
same transaction as the project row — so a project the key just created is writable
immediately. The key itself never owns anything; a key is not a person.

If the creator leaves the team, or their email domain stops being configured, the key
starts returning 401 rather than 403.

## The three refusals

| Message | Cause | Fix |
|---|---|---|
| `403 Missing permission: <p>` | the key was never granted `<p>` | a human edits the key's permissions in the dashboard, or issues a new key |
| `403 Requires project ownership` | the permission is present; the creator is not an owner of this project | a human project owner adds them to the owner list — same key, next call succeeds |
| `403 This operation requires a user session` | the operation is human-only | nothing unlocks it; ask a human to do it in the dashboard |
| `401` | the key is inactive, or its creator lost team membership | a human reactivates the key or restores membership |

Never retry an unchanged call after a 403. Quote the message to the user: the three
have completely different remedies and a paraphrase loses the distinction.

`pubky-pulse:list-projects` returns `access_level` (`owner` | `viewer`) for the key's
creator on every row, so an ownership refusal is predictable before it happens. Check
it while planning, not after failing.

## What is human-only

These return `403 This operation requires a user session` for **every** agent key,
however it is provisioned and whoever created it:

- changing a project's owner list (adding or removing owners);
- deleting a project;
- deleting an app;
- deleting a feedback item;
- deleting a questionnaire, or an individual questionnaire response;
- deleting an attachment;
- deleting a comment this exact key did not author;
- listing, updating or revoking API keys.

`pubky-pulse:create-import-key` is the single exception on that last line: an agent may
create an import key, and nothing else about keys.

Because there is no `delete-app` tool, a wrong immutable `bundle_id` is a human's
problem to fix, and fixing it orphans the old app's data. Get it right at creation.

## What an agent key may write

With the matching permission and the creator's ownership:

- create and update projects, apps, metric definitions, funnel definitions and
  questionnaires;
- delete metric and funnel definitions (soft deletes — recreating the same slug
  restores the definition);
- change issue status: claim, resolve, silence, snooze, reopen;
- merge issues (not reversible);
- change feedback and questionnaire-response status;
- trigger and cancel project-scoped jobs;
- write comments, and edit or delete comments **this exact key** authored (MCP exposes
  creation only; editing and deleting go through the dashboard or REST).

## Comments are exempt from ownership

Commenting on an issue, a feedback item or a questionnaire response needs the matching
`:write` permission and a readable project — and nothing else. The exception replaces
only the ownership check; authentication, containment and permission still apply.

This is the fallback whenever a status change is refused: record what you found as a
comment so the next reader (human or agent) starts from your work rather than
repeating it. Say in the summary that the status could not be changed and why.

Comment authorship is bound to the exact key. Another key cannot edit or delete this
key's comment, even under the same creator, and this key can never moderate somebody
else's.

## Key types

| Prefix | Used by | Scope |
|---|---|---|
| `pulse_agent_*` | the MCP server, this skill | reads across the team, writes where the creator owns; never in a browser bundle, a `NEXT_PUBLIC_*` variable, or a committed file |
| `pulse_client_*` | the four SDKs, inside the shipped app | ingest only for one app: writes events, feedback and user data, reads questionnaire specs and its own drafts; cannot read analytics |
| `pulse_import_*` | a migration script calling `POST /v1/import` | one app, historical events, shown once at creation |

The MCP endpoint accepts agent keys only; a client key or a session token is rejected
with 401.

## Diagnosing a refusal

- [ ] Call `pubky-pulse:whoami`. Is the key active, and is the permission in its list?
      A missing permission is a dashboard edit by a human.
- [ ] Call `pubky-pulse:list-projects`. Is `access_level` on the target row `owner`?
      `viewer` explains every ordinary write refusal, and the fix is an owner adding
      the creator — no new key.
- [ ] Is the operation on the human-only list? Then stop asking for permissions and
      ask a human.
- [ ] Was the target project created by this key's creator via
      `pubky-pulse:create-project`? Then ownership is already there, and the refusal is
      about permission or about the operation being human-only.
- [ ] Still refused after a human says they fixed it? Call again rather than
      reconnecting — ownership is re-read per request, so there is nothing to reload.
