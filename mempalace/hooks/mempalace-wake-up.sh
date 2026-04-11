#!/usr/bin/env bash
# mempalace-wake-up.sh — SessionStart connectivity probe for the BYO
# MemPalace MCP server.
# SPDX-License-Identifier: Apache-2.0
#
# Calls mempalace_status once at session start. If the server is reachable,
# prints a one-line confirmation to stderr. If it is not, prints a warning
# and exits 0 — wake-up is advisory, never a blocker.
#
# Exit codes: always 0. A dead MemPalace must not break your session.

set -o pipefail

CONFIG_FILE="${MEMPALACE_CONFIG:-$HOME/.agents/mempalace/config/mempalace.conf}"

MCP_URL_FROM_FILE=""
MCP_TOKEN_FROM_FILE=""

if [[ -f "$CONFIG_FILE" ]]; then
  # Same narrow key=value parser as mempalace-ingest.sh.
  while IFS='=' read -r key value; do
    key="${key## }"
    key="${key%% }"
    value="${value## }"
    value="${value%% }"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    case "$key" in
      MCP_URL) MCP_URL_FROM_FILE="$value" ;;
      MCP_TOKEN) MCP_TOKEN_FROM_FILE="$value" ;;
      '' | \#*) ;;
    esac
  done < <(grep -vE '^[[:space:]]*(#|$)' "$CONFIG_FILE" 2>/dev/null || true)
fi

MCP_URL="${MEMPALACE_MCP_URL:-$MCP_URL_FROM_FILE}"
MCP_TOKEN="${MEMPALACE_MCP_TOKEN:-$MCP_TOKEN_FROM_FILE}"
MEMPALACE_CLI_BIN="${MEMPALACE_CLI:-mempalace}"

log() {
  printf 'mempalace-wake-up: %s\n' "$1" >&2
}

if [[ -z "$MCP_URL" ]]; then
  log "MEMPALACE_MCP_URL not set — palace offline"
  exit 0
fi

have() { command -v "$1" >/dev/null 2>&1; }

call_status_cli() {
  printf '{}' | "$MEMPALACE_CLI_BIN" call mempalace_status 2>/dev/null
}

call_status_http() {
  local auth=()
  if [[ -n "$MCP_TOKEN" ]]; then
    auth=(-H "Authorization: Bearer $MCP_TOKEN")
  fi
  curl -sS --max-time 5 \
    -H "Content-Type: application/json" \
    "${auth[@]}" \
    -X POST \
    --data '{"tool":"mempalace_status","arguments":{}}' \
    "$MCP_URL/tools/call" 2>/dev/null
}

RESPONSE=""
if have "$MEMPALACE_CLI_BIN"; then
  RESPONSE=$(call_status_cli || printf '')
elif have curl; then
  RESPONSE=$(call_status_http || printf '')
else
  log "neither \$MEMPALACE_CLI nor curl available — palace offline"
  exit 0
fi

if [[ -z "$RESPONSE" ]]; then
  log "palace unreachable at $MCP_URL"
  exit 0
fi

if have jq; then
  STATUS=$(printf '%s' "$RESPONSE" | jq -r '.status // .result.status // empty' 2>/dev/null)
  if [[ -z "$STATUS" ]]; then
    log "palace responded but status field missing"
    exit 0
  fi
  log "palace connected (status=$STATUS)"
else
  log "palace connected"
fi

exit 0
