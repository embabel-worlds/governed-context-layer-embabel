#!/usr/bin/env bash
# Prints the auth header for the appliance's MCP door (Claude Code headersHelper in .mcp.json).
# Reads EMBABEL_MCP_TOKEN from the checkout's .env, so the token never sits in .mcp.json.
# Exits non-zero instead of emitting an empty "Bearer " token when the line is missing.
env_file="$(cd "$(dirname "$0")/.." && pwd)/.env"
token="$(grep -E '^[[:space:]]*EMBABEL_MCP_TOKEN[[:space:]]*=' "$env_file" 2>/dev/null | tail -n 1 |
  sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//; s/^"(.*)"$/\1/')"
if [ -z "$token" ]; then
  echo "embabel-headers.sh: no EMBABEL_MCP_TOKEN in $env_file. Add the token the appliance minted at setup (README step 6)." >&2
  exit 1
fi
printf '{"Authorization":"Bearer %s"}\n' "$token"
