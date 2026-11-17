#!/usr/bin/env bash
# Fills in this checkout for your machine and Google Cloud project, from .env.
#
# 1. Renders realm-chai/ into realms/realm-chai/, replacing ${CHAI_PROJECT_ID}, ${CHAI_REGION},
#    ${CHAI_INSTANCE} and ${CHAI_PROXY_PORT}. realms/ is what `embabel realms link` points at.
# 2. Writes the Claude Code session folders sessions/agent, sessions/setup and
#    sessions/agent-no-kc, each holding only a .mcp.json with this checkout's helper paths.
#
# Both outputs are gitignored. Re-run it after editing realm-chai/ or .env; it replaces only
# what it made. Edit realm-chai/, never realms/realm-chai/. Windows: use configure.ps1.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="$root/.env"
if [ ! -f "$env_file" ]; then
  echo "No .env in $root. Copy .env.example to .env and fill in CHAI_PROJECT_ID." >&2
  exit 1
fi

# setting NAME DEFAULT REGEX: last assignment in .env wins; surrounding quotes are dropped.
setting() {
  local value
  value="$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$env_file" | tail -n 1 |
    sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//; s/^"(.*)"$/\1/'"; s/^'(.*)'\$/\\1/")" || true
  [ -n "$value" ] || value="$2"
  if [ -z "$value" ]; then echo "$1 is not set in $env_file." >&2; exit 1; fi
  if ! printf '%s' "$value" | grep -Eq "$3"; then
    echo "$1='$value' in $env_file does not match $3." >&2; exit 1
  fi
  printf '%s' "$value"
}

project="$(setting CHAI_PROJECT_ID '' '^[a-z][a-z0-9-]{4,28}[a-z0-9]$')"
region="$(setting CHAI_REGION asia-south1 '^[a-z]+-[a-z]+[0-9]+$')"
instance="$(setting CHAI_INSTANCE chai-and-co-pg '^[a-z][a-z0-9-]*$')"
port="$(setting CHAI_PROXY_PORT 5433 '^[0-9]{2,5}$')"
mcp_url="$(setting EMBABEL_MCP_URL http://localhost:11043/mcp/code '^https?://[^[:space:]"\\]+$')"

# ── 1. Render the realm ──────────────────────────────────────────────────────────────────────
src="$root/realm-chai"
out="$root/realms/realm-chai"
note='Generated from realm-chai/ by scripts/configure; edit the source, not this copy.'

rm -rf "$out"
mkdir -p "$out"
(cd "$src" && find . -type f) | while IFS= read -r rel; do
  rel="${rel#./}"
  mkdir -p "$out/$(dirname "$rel")"
  {
    case "$rel" in
      *.yml | *.yaml) printf '# %s\n' "$note" ;;
      *.md) printf '<!-- %s -->\n' "$note" ;;
    esac
    sed -e "s|\${CHAI_PROJECT_ID}|$project|g" \
        -e "s|\${CHAI_REGION}|$region|g" \
        -e "s|\${CHAI_INSTANCE}|$instance|g" \
        -e "s|\${CHAI_PROXY_PORT}|$port|g" "$src/$rel"
  } > "$out/$rel"
  if left="$(grep -oE '\$\{CHAI_[A-Z_]+\}' "$out/$rel" | head -n 1)" && [ -n "$left" ]; then
    echo "realm-chai/$rel uses $left, which configure does not fill in." >&2
    exit 1
  fi
done

# ── 2. Write the session folders ─────────────────────────────────────────────────────────────
json_string() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }
helper() {
  local path="$root/scripts/$1"
  case "$path" in *' '*) path="\"$path\"" ;; esac
  printf 'bash %s' "$path"
}

embabel="    \"embabel\": {
      \"type\": \"http\",
      \"url\": $(json_string "$mcp_url"),
      \"headersHelper\": $(json_string "$(helper embabel-headers.sh)")
    }"
catalog="    \"datacloud_knowledge_catalog_remote\": {
      \"type\": \"http\",
      \"url\": \"https://dataplex.googleapis.com/mcp\",
      \"headersHelper\": $(json_string "$(helper kc-headers.sh)")
    },"

write_session() {
  mkdir -p "$root/sessions/$1"
  printf '{\n  "mcpServers": {\n%s\n  }\n}\n' "$2" > "$root/sessions/$1/.mcp.json"
}
write_session agent "$catalog
$embabel"
write_session setup "$embabel"
write_session agent-no-kc "$embabel"

echo "Rendered $out"
echo "Wrote sessions/agent, sessions/setup and sessions/agent-no-kc"
echo
echo "Cloud SQL Auth Proxy (README step 3):"
echo "  cloud-sql-proxy --port $port $project:$region:$instance"
echo "Link the realm folder (README step 6):"
echo "  embabel realms link \"$root/realms\""
