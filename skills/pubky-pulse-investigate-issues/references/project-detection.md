## Contents

- [Order of evidence](#order-of-evidence)
- [Find the client key](#find-the-client-key)
- [Find the configure call](#find-the-configure-call)
- [Read the bundle identifier per platform](#read-the-bundle-identifier-per-platform)
- [Match to a project](#match-to-a-project)
- [Monorepos and multi-app projects](#monorepos-and-multi-app-projects)
- [When to ask](#when-to-ask)

## Order of evidence

Strongest to weakest. Stop at the first hit and say which one it was, so the user can
correct a wrong guess before anything changes.

1. A `pulse_client_*` key in the repository that matches an app's `client_secret`.
2. A `Pulse.configure` call with a `bundleId` that matches an app's `bundle_id`.
3. The project's own bundle identifier or applicationId matching an app's `bundle_id`.
4. Exactly one project exists on the team.
5. Ask.

A key match is exact and unambiguous. A bundle-identifier match is nearly as good, but
a repository that ships several targets can match more than one app — which is fine,
and just means the app filter matters.

## Find the client key

```sh
grep -rEoh 'pulse_client_[A-Za-z0-9]+' \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' \
  --include='*.swift' --include='*.kt' --include='*.java' . | sort -u | head -5

grep -rhE 'PULSE_API_KEY|PULSE_CLIENT_KEY|PULSE_KEY|pulse_client_' .env* 2>/dev/null | head -10
```

Keys are usually in environment files, not source, so check both. A web project also
keeps one in a build-time variable:

```sh
grep -rhE 'VITE_PULSE|NEXT_PUBLIC_PULSE|PUBLIC_PULSE|EXPO_PUBLIC_PULSE' . \
  --include='*.env*' --include='*.ts' --include='*.js' 2>/dev/null | head -10
```

A client key is public by design — it ships inside the app — so finding one in the
repository is not itself a problem. An **agent** key (`pulse_agent_*`) in the
repository is: say so, and do not print its value.

## Find the configure call

```sh
grep -rn 'Pulse.configure' --include='*.ts' --include='*.tsx' --include='*.js' \
  --include='*.swift' --include='*.kt' . | head -20
```

The call carries the `bundleId` (web, and implicitly on native) and often the
`endpoint`, which tells you which Pubky Pulse instance this repository reports to. If
the endpoint is not the instance the connected agent key talks to, stop — the issues
you can read belong to a different deployment.

## Read the bundle identifier per platform

**Apple**

```sh
grep -h 'PRODUCT_BUNDLE_IDENTIFIER' *.xcodeproj/project.pbxproj 2>/dev/null | sort -u | head -5
grep -rh 'PRODUCT_BUNDLE_IDENTIFIER' --include='*.xcconfig' . 2>/dev/null | head -5
```

**Android**

```sh
grep -rhE 'applicationId' --include='build.gradle' --include='build.gradle.kts' . | head -5
grep -h 'package=' app/src/main/AndroidManifest.xml 2>/dev/null | head -3
```

**Web** — the `bundle_id` is a site identifier *name* chosen at app creation, not a URL
and not derived from anything in the repository. The best proxy is the production host:

```sh
grep -rhE 'https?://[a-z0-9.-]+' --include='*.env*' . 2>/dev/null | head -10
```

Match it against `apps[].bundle_id` (`app.acme.com`) rather than expecting an exact
equality.

**Node backend** — backend apps have no `bundle_id` at all. Identify them by name
(`<Project> Backend`) or by the key in the server's environment.

## Match to a project

```text
pubky-pulse:list-apps        → apps[].{ id, name, platform, bundle_id, client_secret, project_id }
pubky-pulse:list-projects    → projects[].{ id, name, slug, owners, access_level }
```

`list-apps` returns `client_secret` for every app whose project this key's creator
owns, so the key comparison usually works directly. A `client_secret` that comes back
`null` means no ownership, not a missing key — fall back to the bundle identifier.

Once matched, print:

```text
Project: Lofi (8f3e1c2a-…)   App filter: Lofi iOS (a91b…)
```

## Monorepos and multi-app projects

A repository holding a web front end and its backend maps to **two apps in one
project**. A repository holding an iOS and an Android app maps to two more. In all
these cases the project is the same and the app filter is the question.

- If the user asked about a specific surface ("what is breaking in the app"), filter to
  that app.
- If the grep in Step 1 found exactly one key, filter to that key's app and say so.
- Otherwise run across all apps: a cross-app project is exactly where an issue in one
  app is explained by an event in another, and `investigate-event` already merges them.

## When to ask

Ask when the evidence is ambiguous rather than picking:

- two or more projects match the name the user used;
- a bundle identifier matches apps in different projects;
- no heuristic hit and there is more than one project on the team.

Present up to four options with the most likely first, and let anything else come
through the free-text option. Never fall back to "the first project in the list" — a
triage run against the wrong project can change the state of somebody else's issues.
