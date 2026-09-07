#!/bin/sh
# check-mcp-config.sh — report where a Pubky Pulse MCP server is already configured.
#
# Read-only. Inspects the well-known agent config files for a server whose name
# starts with "pubky-pulse" and prints a JSON summary on stdout:
#
#   {"configured":[{"harness":"...","name":"...","url":"...","file":"..."}],
#    "suggest":"claude mcp add ..."}
#
# Any API key it happens to read is masked to its first four characters before
# it can reach stdout, and authorization headers are never extracted at all.
# A missing or unreadable config file is not an error — it is simply absent.

set -u

PROG=$(basename "$0")

usage() {
	cat <<EOF
Usage: $PROG [--help]

Reports, as JSON on stdout, which agent config files already declare a
Pubky Pulse MCP server. Reads only; changes nothing.

Files inspected (missing ones are skipped silently):
  ~/.claude.json                     Claude Code, user scope
  ./.mcp.json                        Claude Code, project scope
  ~/.codex/config.toml               Codex
  ./.cursor/mcp.json                 Cursor, project scope
  ~/.cursor/mcp.json                 Cursor, user scope
  ~/.gemini/settings.json            Gemini
  ~/.config/opencode/opencode.json   OpenCode

Output fields:
  configured[]  one entry per server found: harness, server name, endpoint URL,
                and the file it was read from
  suggest       a ready-to-run command that adds the server to Claude Code's
                user config, with the key left as a placeholder

Exits 0 whether or not anything was found; 2 on a usage error.
EOF
}

case "${1:-}" in
	-h | --help) usage; exit 0 ;;
	"") ;;
	*) usage >&2; exit 2 ;;
esac

# Masks any pulse_agent_ / pulse_client_ / pulse_import_ key down to its first
# four characters, and escapes the result for embedding in a JSON string.
MASK_AND_ESCAPE='
function mask(s,   res, tok, sep, prefix, keep) {
	res = ""
	while (match(s, /pulse_(agent|client|import)_[A-Za-z0-9_-]+/)) {
		tok = substr(s, RSTART, RLENGTH)
		sep = index(substr(tok, 7), "_") + 6
		prefix = substr(tok, 1, sep)
		keep = substr(tok, sep + 1, 4)
		res = res substr(s, 1, RSTART - 1) prefix keep "***"
		s = substr(s, RSTART + RLENGTH)
	}
	return res s
}
function jesc(s) {
	gsub(/\\/, "\\\\", s)
	gsub(/"/, "\\\"", s)
	gsub(/\t/, " ", s)
	return s
}
function emit(harness, name, url, file) {
	printf "%s\t%s\t%s\t%s\n", jesc(mask(harness)), jesc(mask(name)), jesc(mask(url)), jesc(mask(file))
}
'

# Walks a JSON document character by character, tracking which object each key
# belongs to, so that "pubky-pulse" is only reported when it names a server
# inside an mcpServers / mcp / servers map — never when it merely appears in a
# repository path or some other unrelated key.
scan_json() {
	[ -r "$2" ] || return 0
	awk -v HARNESS="$1" -v FILE="$2" "$MASK_AND_ESCAPE"'
	BEGIN {
		doc = ""
		while ((getline line < FILE) > 0) doc = doc line "\n"
		close(FILE)

		n = length(doc); i = 1; depth = 0; srvDepth = -1
		while (i <= n) {
			c = substr(doc, i, 1)

			if (c == "\"") {
				s = ""; i++
				while (i <= n) {
					ch = substr(doc, i, 1)
					if (ch == "\\") { s = s substr(doc, i, 2); i += 2; continue }
					if (ch == "\"") { i++; break }
					s = s ch; i++
				}
				j = i
				while (j <= n && substr(doc, j, 1) ~ /[ \t\r\n]/) j++
				if (substr(doc, j, 1) == ":") { key[depth] = s; i = j + 1; continue }
				if (depth == srvDepth && (key[depth] == "url" || key[depth] == "httpUrl" || key[depth] == "serverUrl")) url = s
				continue
			}

			if (c == "{" || c == "[") {
				depth++
				k = key[depth - 1]
				isMap[depth] = (c == "{" && (k == "mcpServers" || k == "mcp" || k == "servers")) ? 1 : 0
				if (c == "{" && depth >= 2 && isMap[depth - 1] == 1 && k ~ /^pubky-pulse/) {
					srvDepth = depth; name = k; url = ""
				}
				i++; continue
			}

			if (c == "}" || c == "]") {
				if (depth == srvDepth) { emit(HARNESS, name, url, FILE); srvDepth = -1 }
				key[depth] = ""; isMap[depth] = 0
				depth--
				i++; continue
			}

			i++
		}
	}'
}

# TOML servers are declared as [mcp_servers.<name>] tables; the url sits on a
# following key line until the next table header.
scan_toml() {
	[ -r "$2" ] || return 0
	awk -v HARNESS="$1" -v FILE="$2" "$MASK_AND_ESCAPE"'
	function flush() { if (name != "") { emit(HARNESS, name, url, FILE); name = ""; url = "" } }
	/^[ \t]*\[/ {
		hdr = $0
		sub(/^[ \t]*\[+/, "", hdr)
		sub(/\].*$/, "", hdr)
		gsub(/"/, "", hdr)
		if (hdr ~ /^mcp_servers\.pubky-pulse/) {
			leaf = substr(hdr, length("mcp_servers.") + 1)
			# A sub-table such as mcp_servers.pubky-pulse.env keeps the current server open.
			if (index(leaf, ".") == 0) { flush(); name = leaf; url = "" }
		} else {
			flush()
		}
		next
	}
	name != "" && /^[ \t]*(url|http_url)[ \t]*=/ {
		line = $0
		sub(/^[^=]*=[ \t]*/, "", line)
		gsub(/^["'"'"']|["'"'"'][ \t]*$/, "", line)
		url = line
	}
	END { flush() }
	' "$2"
}

home=${HOME:-.}
found=$(
	scan_json "Claude Code (user)" "$home/.claude.json"
	scan_json "Claude Code (project)" "./.mcp.json"
	scan_toml "Codex" "$home/.codex/config.toml"
	scan_json "Cursor (project)" "./.cursor/mcp.json"
	scan_json "Cursor (user)" "$home/.cursor/mcp.json"
	scan_json "Gemini" "$home/.gemini/settings.json"
	scan_json "OpenCode" "$home/.config/opencode/opencode.json"
)

# Reuse a URL that is already configured somewhere, so the suggestion points at
# the reader's own instance rather than at a guessed host. Query strings are
# dropped: a credential never belongs in a command the user is told to run.
suggest_url=$(printf '%s\n' "$found" | awk -F'\t' 'NF >= 3 && $3 ~ /^https?:/ { sub(/\?.*$/, "", $3); print $3; exit }')
case "$suggest_url" in
	*'***'* | "") suggest_url="https://api.pulse.pubky.org/mcp" ;;
esac

printf '{\n  "configured": ['
printf '%s\n' "$found" | awk -F'\t' '
	NF >= 4 {
		printf "%s\n    {\"harness\": \"%s\", \"name\": \"%s\", \"url\": \"%s\", \"file\": \"%s\"}",
			(count++ ? "," : ""), $1, $2, $3, $4
	}
	END { if (count) printf "\n  " }'
printf '],\n  "suggest": "claude mcp add --transport http --scope user pubky-pulse %s --header \\"Authorization: Bearer pulse_agent_YOUR_KEY_HERE\\""\n}\n' "$suggest_url"
