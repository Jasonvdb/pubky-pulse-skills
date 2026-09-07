# pubky-pulse-skills

[Agent skills](https://agentskills.io) for [Pubky Pulse](https://pulse.pubky.org/docs)
— self-hosted, agent-first observability for web, backend, iOS and Android apps.

Install them once and your coding agent can instrument a whole codebase from a single
prompt: work out which surfaces exist, draft a tracking plan of events, metrics and
funnels, create the project and apps over the Pubky Pulse MCP server, wire up the SDK
on every surface, catch every error path, and then verify the data actually arrives.
Afterwards the same skills triage what production is telling you.

A skill is a folder under [`skills/`](./skills) containing a `SKILL.md`. It follows the
open **Agent Skills** standard, so the same file works across Claude Code, Codex, Cursor,
OpenCode, Gemini CLI, and others. The repo doubles as a Claude Code plugin marketplace.

## Skills

| Skill | What it does | Triggers on |
|---|---|---|
| **`pubky-pulse-instrument`** *(start here)* | Instruments a codebase end to end: detects the web, backend, iOS and Android surfaces, drafts a tracking plan of events, metrics and funnels, creates the project and apps over MCP, wires each SDK, covers every error path, and verifies data arrives. | "add analytics", "add error tracking", "instrument this app", "wire up Pubky Pulse" |
| `pubky-pulse-web` | Adds the web SDK to a browser app — React, Next.js, Vue, Svelte or plain JavaScript: configuration, catching every unhandled and caught error, screens, events, metrics, funnel steps, identity, feedback, and propagating the session to the backend. | browser instrumentation, frontend error tracking |
| `pubky-pulse-node` | Adds the Node SDK to a backend — Express, Fastify, Hono, Nest, tRPC, serverless handlers, workers and cron jobs: configuration, the per-request middleware the SDK does not ship, user and session scoping, lifecycle metrics, graceful shutdown. | instrumenting an API or a worker |
| `pubky-pulse-swift` | Adds the Swift SDK to an iOS, iPadOS, macOS or watchOS app: package setup, configuration, screen tracking, and the error capture the SDK does not do for you — there is no automatic crash capture — plus feedback, questionnaires and the privacy manifest. | instrumenting Apple app code |
| `pubky-pulse-android` | Adds the Android SDK to a Kotlin or Compose app: the Gradle dependency, configuration in `Application.onCreate`, screen tracking, coroutine, `runCatching`, WorkManager and OkHttp error capture, plus feedback, questionnaires and Play data safety. | instrumenting Android code |
| `pubky-pulse-investigate-issues` | Triages issues: inventories open and regressed ones, claims an issue, reads occurrence breadcrumbs across sessions and apps, finds the pattern behind them, then fixes, snoozes, merges or resolves each at a real fix version. | "what is broken in production", an error spike, working the issue inbox |
| `pubky-pulse-operations` | Drives the MCP server directly: projects, apps and allowed origins, metric and funnel definitions, event, metric, funnel and stats queries, feedback, questionnaires, attachments, background jobs, import keys and audit logs. | one-off queries, creating or editing definitions, connecting the MCP server |

`pubky-pulse-instrument` loads the four SDK skills itself, so one prompt covers a whole
repository. Each SDK skill also stands alone when only one surface needs wiring up.

## Prerequisites

The skills read and write your Pubky Pulse instance through its MCP server, so connect
that first. You need a running instance (self-hosted or local) and your personal agent
key (`pulse_agent_*`), created for you on first sign-in to the dashboard.

For Claude Code, that is one command:

```sh
claude mcp add --transport http --scope user pubky-pulse https://api.pulse.pubky.org/mcp \
  --header "Authorization: Bearer pulse_agent_YOUR_KEY_HERE"
```

Substitute your own instance URL — `https://api.yourdomain.com/mcp` self-hosted, or
`http://localhost:4000/mcp` in local development. For any other agent, paste this prompt
and let it configure itself:

```text
Add the Pubky Pulse MCP server to my global (user-level) agent config, so it loads in
every project:

- Name: pubky-pulse
- Transport: remote streamable HTTP
- URL: https://api.pulse.pubky.org/mcp
- Header: Authorization: Bearer pulse_agent_YOUR_KEY_HERE

Use whatever mechanism this harness supports — its own `mcp add` command if it has
one, otherwise the user-level config file. Do not write it into the project or
commit the key anywhere; it is a secret. Then reload the MCP servers and call the
`whoami` tool to confirm the connection works.
```

See the [MCP setup guide](https://pulse.pubky.org/docs/mcp/setup) for the per-client
matrix. The code-writing parts of these skills work without the server connected; the
create-and-verify parts do not.

## Install

Every tool installs from this repo via a marketplace, extension, or managed skills
command — no manual clones.

### Claude Code

```sh
/plugin marketplace add Jasonvdb/pubky-pulse-skills
/plugin install pubky-pulse-skills@pubky-pulse-skills
/reload-plugins
```

Turn on auto-update so new commits flow in: `/plugin` → **Marketplaces** →
`pubky-pulse-skills` → **Enable auto-update** (off by default for third-party
marketplaces). Claude Code then fetches updates at startup; run `/reload-plugins` to
activate them. Skills are namespaced, e.g. `pubky-pulse-skills:pubky-pulse-instrument`.

### Codex CLI

```sh
codex plugin marketplace add Jasonvdb/pubky-pulse-skills
codex plugin add pubky-pulse-skills@pubky-pulse-skills
```

Update with `codex plugin marketplace upgrade pubky-pulse-skills`, then re-run
`codex plugin add pubky-pulse-skills@pubky-pulse-skills`. (The same commands work as
`/plugin …` inside the Codex TUI.)

### Cursor

Import straight from GitHub in the UI — nothing to run in a terminal:

1. Open **Cursor Settings** (`Cmd+Shift+J`).
2. Go to the **Rules** tab.
3. Click **Add Rule** → **Remote Rule (GitHub)**.
4. Enter `https://github.com/Jasonvdb/pubky-pulse-skills`.
5. Select the skills to import.

Cursor copies them into `.cursor/skills/` and auto-discovers them (Cursor 2.4+).
Re-import to pull updates.

### Gemini CLI

Installs as a native extension; `--auto-update` keeps it current automatically:

```sh
gemini extensions install https://github.com/Jasonvdb/pubky-pulse-skills --auto-update
```

Without `--auto-update`, refresh manually with `gemini extensions update
pubky-pulse-skills` (or `--all`).

### Any Agent Skills host

```sh
npx skills add Jasonvdb/pubky-pulse-skills
```

### OpenCode, Copilot, … (GitHub CLI)

Other tools that read the `SKILL.md` standard install via `gh skill` (GitHub CLI
**≥ 2.90**) — it writes into the host's own skills directory:

```sh
gh skill install Jasonvdb/pubky-pulse-skills --all --agent opencode --scope user
gh skill install Jasonvdb/pubky-pulse-skills --all --agent github-copilot --scope user
```

`--agent` picks the host (`opencode`, `codex`, `claude-code`, `github-copilot`, …).
Pull updates with `gh skill update --all`.

## Example: instrument a codebase in one prompt

Point your agent at the repository and ask for the whole thing at once:

```text
Instrument this repo with Pubky Pulse: web app and backend, catch every error, define
metrics and funnels, create everything in Pulse and verify events arrive.
```

`pubky-pulse-instrument` takes it from there:

1. **Detects the surfaces** from the manifests — a Next.js app with API routes is two
   apps, web and backend, not one.
2. **Audits the code** for the places worth instrumenting and for error paths that
   currently report nothing.
3. **Drafts a tracking plan** — events, metrics and funnels per surface, capped so the
   plan stays readable, with error rows for every surface.
4. **Creates the project and one app per surface** over MCP, sets the allowed origins
   for the web app including the dev-server origin, creates every metric and funnel
   definition, and puts each client key where that surface reads it from.
5. **Writes the code** by loading `pubky-pulse-web`, `pubky-pulse-node`,
   `pubky-pulse-swift` or `pubky-pulse-android` for each surface, covering every catch,
   error boundary, rejected promise, failed job and non-2xx response.
6. **Verifies** — builds or typechecks, re-checks that no error path is left
   unreported, then queries the events back in development data mode and reports what
   arrived and what did not.

It decides rather than interviews: questions come only when a choice is genuinely
ambiguous (the product name cannot be inferred, two similar projects already exist), and
every question has a default it takes if no answer comes back.

Two shorter ones, for the days after:

```text
What is broken in production? Work through the new Pubky Pulse issues and fix what you can.
```

```text
How many users finished the onboarding funnel this week, and which step loses the most?
```

The first loads `pubky-pulse-investigate-issues`, the second `pubky-pulse-operations`.

## Conventions the family enforces

All seven skills name things the same way, so a codebase instrumented today still reads
consistently after the next surface is added.

| Thing | Rule | Example |
|---|---|---|
| Project | bare product name, no platform suffix | `Lofi` |
| App | `<Project> <Platform>` | `Lofi Web`, `Lofi Backend`, `Lofi iOS`, `Lofi Android` |
| Event message | snake_case, outcome-oriented, never interpolated | `checkout_completed` |
| Metric slug | kebab-case, created on the server first | `process-payment` |
| Funnel slug and step | kebab-case, created on the server first | `onboarding`, `onboarding-email` |
| Screen name | native: PascalCase human name; web: URL path, tracked automatically | `Checkout`, `/checkout` |

The rule of thumb behind the table: **hyphens = must exist on the server first,
underscores = free-form event**. Event messages are the key errors are grouped by, so
they stay stable templates and the variable data goes into attributes. Where a codebase
already has its own convention, the skills follow that instead.

The full table, along with the description budgets, banned words and lint rules every
skill is written to, lives in [CONTRIBUTING.md](./CONTRIBUTING.md).

## Updates

Merge to `main` and it ships — there is no release step. How updates reach installed
tools:

- **Claude Code** — auto-fetched at startup once auto-update is enabled, then a one-time
  `/reload-plugins` to activate.
- **Gemini CLI** — fully automatic if installed with `--auto-update`; otherwise
  `gemini extensions update pubky-pulse-skills`.
- **Codex** — `codex plugin marketplace upgrade pubky-pulse-skills` + re-add.
- **Cursor** — re-import the Remote Rule from the Rules tab.
- **gh skill hosts (OpenCode, Copilot, …)** — `gh skill update --all`.

Gemini CLI (`--auto-update`) is the only fully hands-off path; the rest take a single
update command. For reproducibility, pin a tag or commit instead of tracking `main`
(`--pin` with `gh skill`, `#tag` when adding the Codex marketplace, `--ref` with Gemini,
or `ref`/`sha` in a Claude Code marketplace source).

## Development

Each skill is a directory of its own:

```text
skills/<name>/
├── SKILL.md      # the skill: frontmatter, body, gotchas (≤500 lines)
├── references/   # long material, one level deep, loaded on demand
├── scripts/      # bundled scripts, executed rather than read
└── evals/        # triggers.json: queries that must and must not load this skill
```

Three checks run over the repo, and CI runs them on every push and pull request (the
last one weekly as well, so upstream tool renames surface without a push here):

```sh
# manifests, frontmatter, budgets, banned words, MCP tool names, references, evals, scripts
node scripts/lint-skills.mjs

# conformance with the Agent Skills spec — one directory per invocation
npx --yes skills-ref validate skills/pubky-pulse-web/
for s in skills/*/; do npx --yes skills-ref validate "$s" || exit 1; done

# scripts/mcp-tools.json matches the tools the server registers
node scripts/check-mcp-tools.mjs --server ../pubky-pulse
```

The two bundled scripts are zero-dependency and self-documenting:

```sh
skills/pubky-pulse-instrument/scripts/find-uninstrumented-catches.sh --help
skills/pubky-pulse-operations/scripts/check-mcp-config.sh --help
```

Both print JSON on stdout and change nothing; the first also has a `--self-test` that
runs its built-in fixtures.

### Trigger evals

A skill is only useful if it loads on the prompts people actually type, so every skill
ships `evals/triggers.json` — queries that **should** load it, and near-miss queries that
**should not**, because they belong to a sibling. There is no automated runner; check
them by hand after changing a description:

```sh
/plugin marketplace add /absolute/path/to/pubky-pulse-skills
/plugin install pubky-pulse-skills@pubky-pulse-skills
/reload-plugins
```

Then run each query in a fresh, non-interactive session and read back which skill was
invoked:

```sh
claude -p "<query from evals/triggers.json>" --output-format json --max-turns 2
```

Every `should` query must load that skill; every `should_not` query must load the sibling
it belongs to, or no skill at all. Use a fresh session per query — a skill already in
context is not a trigger. When two skills claim the same query, fix it by adding
specificity to the boundary clause of each description, not by deleting the query.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the contract every skill is written to.

## Security

Skills are loaded into an agent's context and can instruct it to run bundled scripts —
treat this repo like any other code dependency, and read a skill before you install it.

These skills handle two kinds of Pubky Pulse key. A client key (`pulse_client_*`) is
ingest-scoped and public: it is meant to ship inside your app. An agent key
(`pulse_agent_*`) acts for the person who created it and is a secret — it belongs in your
agent's user-level MCP config, never in a browser bundle, a `NEXT_PUBLIC_*` variable, or a
committed file. Nothing in this repo contains a key, and no skill should ever print one.

## License

MIT — see [LICENSE](./LICENSE).
