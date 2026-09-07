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

<!-- TODO: table of the seven skills — name, what it does, when it triggers. -->

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

<!-- TODO: the one-shot prompt and a sketch of what the agent does with it. -->

## Conventions

<!-- TODO: naming rules, event/metric/funnel choice, and where they come from. -->

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

<!-- TODO: repo layout, how to run the lint, and how to add or change a skill. -->

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
