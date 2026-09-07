#!/usr/bin/env node
/**
 * lint-skills.mjs — repository lint for the pubky-pulse-skills marketplace.
 *
 * Zero dependencies, Node 20+, ESM. Run from the repository root:
 *
 *   node scripts/lint-skills.mjs
 *
 * Prints one line per failure and exits 1 if anything failed, otherwise prints a
 * summary and exits 0. Warnings never fail the run.
 *
 * The rules are documented in CONTRIBUTING.md ("Lint rules"). They exist because
 * a skill is loaded straight into a model's context: a hallucinated MCP tool
 * name, a stale product name, or a reference file nobody links to are all silent
 * failures at runtime, not compile errors.
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const PLUGIN_NAME = "pubky-pulse-skills";

/** Package and repository names that share the `pubky-pulse-` prefix but are not skills. */
const ALLOWED_NON_SKILL_NAMES = new Set([
  "pubky-pulse-web",
  "pubky-pulse-node",
  "pubky-pulse-swift",
  "pubky-pulse-android",
  "pubky-pulse-web-demo",
  "pubky-pulse-skills",
]);

/** Frontmatter keys the open Agent Skills spec accepts. Anything else breaks packaging. */
const ALLOWED_FRONTMATTER_KEYS = new Set([
  "name",
  "description",
  "license",
  "compatibility",
  "metadata",
  "allowed-tools",
]);

const MAX_DESCRIPTION_CHARS = 800;
const MAX_BODY_LINES = 500;
const MIN_EVAL_QUERIES = 8;
const REFERENCE_CONTENTS_THRESHOLD = 100;

/** Products and features this fork does not have. Mentioning one misleads the agent. */
const BANNED_PATTERNS = [
  /owlmetry/i,
  /owl_client/i,
  /revenuecat/i,
  /search ads/i,
  /app store connect/i,
  /\bapns\b/i,
  /push notification/i,
  /attribution token/i,
  /team invitation/i,
  /integrations framework/i,
];

/** `CLI` is banned too, except where the line denies one exists or names a specific tool. */
const CLI_PATTERN = /\bcli\b/i;
const CLI_ALLOWED = /(codex|gemini|github)\s+cli|no\s+cli\b|is\s+no\s+command-line/i;

const TEXT_EXTENSIONS = [".md", ".json", ".sh", ".mjs", ".js", ".txt", ".yml", ".yaml"];

const failures = [];
const warnings = [];

const fail = (file, message) => failures.push(`${file}: ${message}`);
const warn = (file, message) => warnings.push(`${file}: ${message}`);

if (process.argv.includes("--help") || process.argv.includes("-h")) {
  process.stdout.write(
    "Usage: node scripts/lint-skills.mjs\n\n" +
      "Validates the harness manifests and every skill under skills/.\n" +
      "Exits 1 with one line per failure, 0 when everything passes.\n",
  );
  process.exit(0);
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function rel(path) {
  return relative(ROOT, path) || path;
}

function readJson(path) {
  try {
    return { value: JSON.parse(readFileSync(path, "utf8")) };
  } catch (error) {
    return { error: error.message };
  }
}

function listDirs(path) {
  if (!existsSync(path)) return [];
  return readdirSync(path)
    .filter((entry) => statSync(join(path, entry)).isDirectory())
    .sort();
}

function listFiles(path) {
  if (!existsSync(path)) return [];
  return readdirSync(path)
    .filter((entry) => statSync(join(path, entry)).isFile())
    .sort();
}

function walkFiles(path, out = []) {
  if (!existsSync(path)) return out;
  for (const entry of readdirSync(path).sort()) {
    const full = join(path, entry);
    if (statSync(full).isDirectory()) walkFiles(full, out);
    else out.push(full);
  }
  return out;
}

function unquote(value) {
  if (value.length >= 2 && /^["'].*["']$/.test(value) && value[0] === value[value.length - 1]) {
    return value.slice(1, -1);
  }
  return value;
}

/**
 * Minimal YAML frontmatter parser: `key: value`, `key: >-` folded blocks (and
 * their `|` literal cousins), and one level of nested mapping keys such as
 * `metadata:`. Anything richer is a sign the frontmatter has drifted from the
 * portable subset, so it is reported as a failure rather than parsed.
 */
function parseFrontmatter(text) {
  const lines = text.split("\n");
  if (lines[0] !== "---") return { error: "file must start with a `---` frontmatter fence" };
  const end = lines.indexOf("---", 1);
  if (end === -1) return { error: "frontmatter is never closed with `---`" };

  const data = {};
  let i = 1;
  while (i < end) {
    const line = lines[i];
    if (line.trim() === "" || line.trimStart().startsWith("#")) {
      i++;
      continue;
    }
    const match = /^([A-Za-z][A-Za-z0-9_-]*):[ \t]*(.*)$/.exec(line);
    if (!match) return { error: `frontmatter line ${i + 1} is not \`key: value\`: ${line.trim()}` };
    const [, key, rawValue] = match;
    const raw = rawValue.trim();

    if (raw === ">" || raw === ">-" || raw === "|" || raw === "|-") {
      const parts = [];
      i++;
      while (i < end && (lines[i].trim() === "" || /^\s/.test(lines[i]))) {
        parts.push(lines[i].trim());
        i++;
      }
      data[key] = (raw.startsWith(">") ? parts.join(" ") : parts.join("\n")).trim();
      continue;
    }

    if (raw === "") {
      const nested = {};
      i++;
      while (i < end && /^\s+\S/.test(lines[i])) {
        const nestedMatch = /^\s+([A-Za-z][A-Za-z0-9_-]*):[ \t]*(.*)$/.exec(lines[i]);
        if (!nestedMatch) {
          return { error: `frontmatter line ${i + 1} is not a nested \`key: value\`` };
        }
        nested[nestedMatch[1]] = unquote(nestedMatch[2].trim());
        i++;
      }
      data[key] = nested;
      continue;
    }

    data[key] = unquote(raw);
    i++;
  }

  return { data, body: lines.slice(end + 1) };
}

// ---------------------------------------------------------------------------
// rule 1 — harness manifests
// ---------------------------------------------------------------------------

function checkManifests() {
  const manifests = [
    ".claude-plugin/marketplace.json",
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
    ".agents/plugins/marketplace.json",
    "gemini-extension.json",
  ];

  for (const path of manifests) {
    const full = join(ROOT, path);
    if (!existsSync(full)) {
      fail(path, "manifest is missing");
      continue;
    }
    const { value, error } = readJson(full);
    if (error) {
      fail(path, `is not valid JSON (${error})`);
      continue;
    }
    if (value.name !== PLUGIN_NAME) {
      fail(path, `name is "${value.name}", expected "${PLUGIN_NAME}"`);
    }
    if (Array.isArray(value.plugins)) {
      for (const plugin of value.plugins) {
        if (plugin.name !== PLUGIN_NAME) {
          fail(path, `plugins[].name is "${plugin.name}", expected "${PLUGIN_NAME}"`);
        }
        if (!plugin.source) fail(path, `plugin "${plugin.name}" has no source`);
      }
    }
  }

  const codex = readJson(join(ROOT, ".codex-plugin/plugin.json")).value;
  if (codex && codex.skills !== "./skills/") {
    fail(".codex-plugin/plugin.json", `skills is "${codex.skills}", expected "./skills/"`);
  }
}

// ---------------------------------------------------------------------------
// rules 2-8 — skills
// ---------------------------------------------------------------------------

function checkSkillFrontmatter(name, skillPath, siblings) {
  const file = join(skillPath, "SKILL.md");
  const path = rel(file);
  if (!existsSync(file)) {
    fail(path, "skill has no SKILL.md");
    return;
  }

  const text = readFileSync(file, "utf8");
  const { data, body, error } = parseFrontmatter(text);
  if (error) {
    fail(path, error);
    return;
  }

  for (const key of Object.keys(data)) {
    if (!ALLOWED_FRONTMATTER_KEYS.has(key)) {
      fail(path, `frontmatter key "${key}" is not portable; allowed: ${[...ALLOWED_FRONTMATTER_KEYS].join(", ")}`);
    }
  }
  if (data.name !== name) {
    fail(path, `frontmatter name "${data.name}" does not match directory name "${name}"`);
  }

  const description = typeof data.description === "string" ? data.description : "";
  if (description.length === 0) {
    fail(path, "description is empty");
  } else if (description.length > MAX_DESCRIPTION_CHARS) {
    fail(path, `description is ${description.length} chars, over the ${MAX_DESCRIPTION_CHARS} cap`);
  }
  if (description && !description.includes("Use when")) {
    fail(path, 'description does not contain "Use when"');
  }
  if (description && !siblings.some((sibling) => description.includes(sibling))) {
    fail(path, "description names no sibling skill, so its boundary is undefined");
  }

  if (body.length > MAX_BODY_LINES) {
    fail(path, `body is ${body.length} lines, over the ${MAX_BODY_LINES} cap`);
  }
  if (text.includes("$ARGUMENTS")) {
    fail(path, "uses $ARGUMENTS, which only exists in Claude Code slash commands");
  }
  if (/!`/.test(text)) {
    fail(path, "uses !`cmd` command injection, which is not portable");
  }
}

/** Rules 3-5: banned words, skill-name tokens and MCP tool tokens, per text file. */
function checkFileContent(file, skillNames, mcpTools) {
  const path = rel(file);
  const text = readFileSync(file, "utf8");

  text.split("\n").forEach((line, index) => {
    for (const pattern of BANNED_PATTERNS) {
      if (pattern.test(line)) {
        fail(path, `line ${index + 1} mentions ${pattern.source}, which this product does not have`);
      }
    }
    if (CLI_PATTERN.test(line) && !CLI_ALLOWED.test(line)) {
      fail(path, `line ${index + 1} says "CLI"; the MCP server is the only agent interface`);
    }
  });

  for (const match of text.matchAll(/pubky-pulse-[a-z0-9]+(?:-[a-z0-9]+)*/g)) {
    const token = match[0];
    if (!skillNames.has(token) && !ALLOWED_NON_SKILL_NAMES.has(token)) {
      fail(path, `"${token}" is neither a skill in skills/ nor an allow-listed package name`);
    }
  }

  for (const match of text.matchAll(/pubky-pulse:([a-z][a-z0-9-]*)/g)) {
    if (!mcpTools.has(match[1])) {
      fail(path, `"pubky-pulse:${match[1]}" is not an MCP tool in scripts/mcp-tools.json`);
    }
  }
}

function checkReferences(skillPath) {
  const skillFile = join(skillPath, "SKILL.md");
  if (!existsSync(skillFile)) return;
  const skillText = readFileSync(skillFile, "utf8");
  const skillLines = skillText.split("\n");
  const path = rel(skillFile);

  for (const match of new Set([...skillText.matchAll(/references\/[A-Za-z0-9._-]+\.md/g)].map((m) => m[0]))) {
    if (!existsSync(join(skillPath, match))) {
      fail(path, `references "${match}", which does not exist`);
    }
  }

  const referencesDir = join(skillPath, "references");
  for (const entry of listFiles(referencesDir)) {
    const token = `references/${entry}`;
    const mentioned = skillLines.some((line) => line.includes(token) && /when/i.test(line));
    if (!mentioned) {
      fail(rel(join(referencesDir, entry)), `is not mentioned in SKILL.md on a line saying when to read it`);
    }
    const lines = readFileSync(join(referencesDir, entry), "utf8").split("\n");
    if (lines.length > REFERENCE_CONTENTS_THRESHOLD) {
      const firstContent = lines.find((line) => line.trim() !== "");
      if ((firstContent ?? "").trim() !== "## Contents") {
        fail(rel(join(referencesDir, entry)), `is over ${REFERENCE_CONTENTS_THRESHOLD} lines and must start with "## Contents"`);
      }
    }
  }
}

function checkEvals(skillPath) {
  const file = join(skillPath, "evals/triggers.json");
  if (!existsSync(file)) {
    warn(rel(join(skillPath, "evals/triggers.json")), "no trigger evals yet");
    return;
  }
  const path = rel(file);
  const { value, error } = readJson(file);
  if (error) {
    fail(path, `is not valid JSON (${error})`);
    return;
  }
  for (const key of ["should", "should_not"]) {
    const queries = value[key];
    if (!Array.isArray(queries)) {
      fail(path, `"${key}" must be an array of query strings`);
      continue;
    }
    if (queries.some((query) => typeof query !== "string" || query.trim() === "")) {
      fail(path, `"${key}" contains a non-string or empty query`);
    }
    if (queries.length < MIN_EVAL_QUERIES) {
      fail(path, `"${key}" has ${queries.length} queries, needs at least ${MIN_EVAL_QUERIES}`);
    }
  }
}

function checkScripts(skillPath) {
  const scriptsDir = join(skillPath, "scripts");
  for (const entry of listFiles(scriptsDir)) {
    const file = join(scriptsDir, entry);
    const path = rel(file);
    if ((statSync(file).mode & 0o111) === 0) {
      fail(path, "is not executable (chmod +x)");
      continue;
    }
    const result = spawnSync(file, ["--help"], { encoding: "utf8", timeout: 30_000 });
    if (result.error) {
      fail(path, `could not be run with --help (${result.error.message})`);
    } else if (result.status !== 0) {
      fail(path, `--help exited ${result.status}, expected 0`);
    }
  }
}

function checkSkills() {
  const skillsDir = join(ROOT, "skills");
  const names = listDirs(skillsDir);
  if (names.length === 0) {
    fail("skills/", "contains no skills");
    return 0;
  }

  const skillNames = new Set(names);
  const toolsPath = join(ROOT, "scripts/mcp-tools.json");
  const { value: tools, error: toolsError } = readJson(toolsPath);
  if (toolsError || !Array.isArray(tools)) {
    fail("scripts/mcp-tools.json", `must be a JSON array of MCP tool names (${toolsError ?? "not an array"})`);
  }
  const mcpTools = new Set(Array.isArray(tools) ? tools : []);

  for (const name of names) {
    const skillPath = join(skillsDir, name);
    const siblings = names.filter((other) => other !== name);
    checkSkillFrontmatter(name, skillPath, siblings);
    checkReferences(skillPath);
    checkEvals(skillPath);
    checkScripts(skillPath);
    for (const file of walkFiles(skillPath)) {
      if (!TEXT_EXTENSIONS.includes(file.slice(file.lastIndexOf(".")))) continue;
      checkFileContent(file, skillNames, mcpTools);
    }
  }

  return names.length;
}

// ---------------------------------------------------------------------------
// run
// ---------------------------------------------------------------------------

checkManifests();
const skillCount = checkSkills();

for (const warning of warnings) process.stdout.write(`warning: ${warning}\n`);

if (failures.length > 0) {
  for (const failure of failures) process.stdout.write(`${failure}\n`);
  process.stdout.write(`\n${failures.length} failure(s) across ${skillCount} skill(s).\n`);
  process.exit(1);
}

process.stdout.write(
  `OK: 5 manifests and ${skillCount} skill(s) passed${warnings.length ? `, ${warnings.length} warning(s)` : ""}.\n`,
);
process.exit(0);
