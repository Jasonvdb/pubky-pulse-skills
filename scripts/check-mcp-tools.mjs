#!/usr/bin/env node
// Checks scripts/mcp-tools.json against the tools the Pubky Pulse server registers.
// The skills lint validates every `pubky-pulse:<tool>` mention against that JSON file,
// so this is what catches a tool renamed or added upstream that the skills do not know.
//
// Usage: node scripts/check-mcp-tools.mjs --server <path-to-pubky-pulse-checkout>
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);

if (args.includes("--help") || args.includes("-h")) {
  console.log("Usage: node scripts/check-mcp-tools.mjs --server <path-to-pubky-pulse-checkout>");
  console.log("Exits 1 when scripts/mcp-tools.json differs from the tools registered in apps/server/src/mcp/tools/.");
  process.exit(0);
}

const serverIdx = args.indexOf("--server");
const serverRoot = serverIdx >= 0 ? args[serverIdx + 1] : undefined;
if (!serverRoot) {
  console.error("error: --server <path-to-pubky-pulse-checkout> is required (see --help)");
  process.exit(2);
}

const toolsDir = join(serverRoot, "apps/server/src/mcp/tools");
let files;
try {
  files = readdirSync(toolsDir).filter((f) => f.endsWith(".ts"));
} catch (err) {
  console.error(`error: cannot read ${toolsDir}: ${err.message}`);
  process.exit(2);
}

const registered = new Set();
for (const file of files) {
  const source = readFileSync(join(toolsDir, file), "utf8");
  for (const match of source.matchAll(/registerTool\(\s*"([a-z][a-z0-9-]*)"/g)) {
    registered.add(match[1]);
  }
}
if (registered.size === 0) {
  console.error(`error: no registerTool(...) calls found under ${toolsDir}; the server layout may have changed`);
  process.exit(2);
}

const listed = new Set(JSON.parse(readFileSync(join(ROOT, "scripts/mcp-tools.json"), "utf8")));
const missing = [...registered].filter((t) => !listed.has(t)).sort();
const stale = [...listed].filter((t) => !registered.has(t)).sort();

const result = { server_tools: registered.size, listed_tools: listed.size, missing, stale };
console.log(JSON.stringify(result, null, 2));

if (missing.length || stale.length) {
  console.error("scripts/mcp-tools.json is out of date with the server.");
  if (missing.length) console.error(`  add:    ${missing.join(", ")}`);
  if (stale.length) console.error(`  remove: ${stale.join(", ")} (and fix every skill that mentions them)`);
  process.exit(1);
}
