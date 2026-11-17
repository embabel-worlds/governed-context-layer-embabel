#!/usr/bin/env bash
# Prints auth headers for the Knowledge Catalog (Dataplex) MCP server (Claude Code headersHelper
# in .mcp.json): a gcloud application-default access token, and CHAI_PROJECT_ID from the
# checkout's .env as the quota project. Exits non-zero instead of emitting an empty token.
env_file="$(cd "$(dirname "$0")/.." && pwd)/.env"
project="$(grep -E '^[[:space:]]*CHAI_PROJECT_ID[[:space:]]*=' "$env_file" 2>/dev/null | tail -n 1 |
  sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//; s/^"(.*)"$/\1/')"
if [ -z "$project" ]; then
  echo "kc-headers.sh: no CHAI_PROJECT_ID in $env_file." >&2
  exit 1
fi
token=""
for attempt in 1 2; do
  token="$(gcloud auth application-default print-access-token | tail -n 1 | tr -d '[:space:]')"
  [ -n "$token" ] && break
  [ "$attempt" -lt 2 ] && sleep 2  # one retry for transient network/DNS errors
done
if [ -z "$token" ]; then
  echo "kc-headers.sh: gcloud returned no access token (see the gcloud error above). Check network/TLS, or run: gcloud auth application-default login" >&2
  exit 1
fi
printf '{"Authorization":"Bearer %s","x-goog-user-project":"%s"}\n' "$token" "$project"
