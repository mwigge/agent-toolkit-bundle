#!/usr/bin/env bash
# mempalace-ingest.sh — scan configured paths and ingest files via the BYO
# MemPalace MCP server. Pure directory walk, no content heuristics.
# SPDX-License-Identifier: Apache-2.0
#
# Two invocation modes:
#
#   1. Claude Code PostToolUse hook — reads a JSON payload from stdin:
#        { "tool_name": "Edit"|"Write", "tool_input": { "file_path": "..." } }
#      When a tool writes a file that lives inside a configured scan path,
#      that single file is ingested. Everything else is ignored.
#
#   2. Direct invocation — `mempalace-ingest.sh scan` walks every configured
#      scan path in full. Used by the /mempalace-mine slash command.
#
# Never fails loudly. If the MCP server is unreachable, or curl/jq are
# missing, the hook logs to stderr and exits 0 so the surrounding tool
# pipeline is unaffected.
#
# Exit codes: always 0. Degrade silently, never block.

set -o pipefail

# ---- config -----------------------------------------------------------------

CONFIG_FILE="${MEMPALACE_CONFIG:-$HOME/.agents/mempalace/config/mempalace.conf}"

# Defaults. Every one is overridable via the config file or an environment
# variable (env wins).
SCAN_PATHS_DEFAULT="docs_local,docs_local/openspec"
EXTRA_PATHS_DEFAULT=""
INGEST_GLOBS_DEFAULT="*.md,*.yaml,*.yml"

SCAN_PATHS=""
EXTRA_PATHS=""
INGEST_GLOBS=""
MCP_URL_FROM_FILE=""
MCP_TOKEN_FROM_FILE=""

if [[ -f "$CONFIG_FILE" ]]; then
  # Narrow, non-eval parser: whitelist-only key handling. A tampered config
  # cannot execute arbitrary shell — unknown keys are dropped on the floor.
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
      SCAN_PATHS) SCAN_PATHS="$value" ;;
      EXTRA_PATHS) EXTRA_PATHS="$value" ;;
      INGEST_GLOBS) INGEST_GLOBS="$value" ;;
      MCP_URL) MCP_URL_FROM_FILE="$value" ;;
      MCP_TOKEN) MCP_TOKEN_FROM_FILE="$value" ;;
      '' | \#*) ;;
    esac
  done < <(grep -vE '^[[:space:]]*(#|$)' "$CONFIG_FILE" 2>/dev/null || true)
fi

: "${SCAN_PATHS:=$SCAN_PATHS_DEFAULT}"
: "${EXTRA_PATHS:=$EXTRA_PATHS_DEFAULT}"
: "${INGEST_GLOBS:=$INGEST_GLOBS_DEFAULT}"

MCP_URL="${MEMPALACE_MCP_URL:-$MCP_URL_FROM_FILE}"
MCP_TOKEN="${MEMPALACE_MCP_TOKEN:-$MCP_TOKEN_FROM_FILE}"
MEMPALACE_CLI_BIN="${MEMPALACE_CLI:-mempalace}"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

log() {
  printf 'mempalace-ingest: %s\n' "$1" >&2
}

if [[ -z "$MCP_URL" ]]; then
  log "MEMPALACE_MCP_URL not set — nothing to do"
  exit 0
fi

# ---- dependency probe -------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

USE_CLI=0
if have "$MEMPALACE_CLI_BIN"; then
  USE_CLI=1
elif ! have curl; then
  log "neither \$MEMPALACE_CLI ($MEMPALACE_CLI_BIN) nor curl available — skipping"
  exit 0
fi

if ! have jq; then
  log "jq not found — cannot build MCP requests, skipping"
  exit 0
fi

# ---- MCP transport ----------------------------------------------------------
#
# Two back-ends. Both accept a tool name and a JSON arguments blob and return
# the server's raw response on stdout. Neither ever fails the script.

mcp_call_http() {
  local tool="$1" args_json="$2"
  local body
  body=$(jq -n --arg t "$tool" --argjson a "$args_json" \
    '{tool: $t, arguments: $a}')
  local auth=()
  if [[ -n "$MCP_TOKEN" ]]; then
    auth=(-H "Authorization: Bearer $MCP_TOKEN")
  fi
  curl -sS --max-time 10 \
    -H "Content-Type: application/json" \
    "${auth[@]}" \
    -X POST \
    --data "$body" \
    "$MCP_URL/tools/call" 2>/dev/null || printf '{}'
}

mcp_call_cli() {
  local tool="$1" args_json="$2"
  # CLI contract: `mempalace call <tool>` reads JSON args on stdin and prints
  # JSON response on stdout. Users who prefer a direct binary to HTTP can
  # point MEMPALACE_CLI at their own wrapper.
  printf '%s' "$args_json" |
    "$MEMPALACE_CLI_BIN" call "$tool" 2>/dev/null || printf '{}'
}

mcp_call() {
  local tool="$1" args_json="$2"
  if [[ "$USE_CLI" -eq 1 ]]; then
    mcp_call_cli "$tool" "$args_json"
  else
    mcp_call_http "$tool" "$args_json"
  fi
}

# ---- ingest a single file ---------------------------------------------------

sha256_of() {
  local path="$1"
  if have sha256sum; then
    sha256sum "$path" | awk '{print $1}'
  elif have shasum; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    printf 'no-hash'
  fi
}

ingest_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  [[ -r "$path" ]] || return 0

  # Skip anything larger than 1 MiB. Memory records are short notes, not blobs.
  local size
  if [[ "$(uname -s)" == "Darwin" ]]; then
    size=$(stat -f '%z' "$path" 2>/dev/null || printf '0')
  else
    size=$(stat -c '%s' "$path" 2>/dev/null || printf '0')
  fi
  if [[ "$size" -gt 1048576 ]]; then
    log "skipping $path (size $size > 1MiB)"
    return 0
  fi

  local hash rel prefix
  hash=$(sha256_of "$path")
  # Strip the project prefix so the backend sees a project-relative path.
  prefix="$PROJECT_DIR/"
  # shellcheck disable=SC2295  # intentional: pattern stripping vs literal prefix
  rel="${path#$prefix}"

  # Idempotency: ask the backend whether we have already ingested this hash.
  local dup_args dup_response already
  dup_args=$(jq -n --arg h "$hash" --arg p "$rel" \
    '{content_hash: $h, source_path: $p}')
  dup_response=$(mcp_call mempalace_check_duplicate "$dup_args")
  already=$(printf '%s' "$dup_response" | jq -r '.duplicate // false' 2>/dev/null)
  if [[ "$already" == "true" ]]; then
    return 0
  fi

  # Read file contents. jq handles escaping.
  local add_args
  add_args=$(jq -n \
    --arg path "$rel" \
    --arg hash "$hash" \
    --rawfile content "$path" \
    '{source_path: $path, content_hash: $hash, content: $content}')

  mcp_call mempalace_add_drawer "$add_args" >/dev/null
  log "ingested $rel"
}

# ---- scan configured paths --------------------------------------------------

# Build the `find -name` predicate array from INGEST_GLOBS. Each entry is
# appended to the caller's `find` argv, so no eval and no shell word-splitting
# on whitespace paths is possible downstream.
build_find_predicate() {
  local IFS=','
  # shellcheck disable=SC2206  # intentional word-split on comma
  local -a globs=($INGEST_GLOBS)
  local -a out=()
  local first=1 g
  for g in "${globs[@]}"; do
    g="${g## }"
    g="${g%% }"
    [[ -z "$g" ]] && continue
    if [[ "$first" -eq 1 ]]; then
      out+=("(" "-name" "$g")
      first=0
    else
      out+=("-o" "-name" "$g")
    fi
  done
  if [[ "$first" -eq 0 ]]; then
    out+=(")")
  fi
  # Emit one argument per line for the caller to re-read via `mapfile`.
  printf '%s\n' "${out[@]}"
}

scan_one_path() {
  local base="$1"
  [[ -d "$base" ]] || return 0

  local -a predicate=()
  while IFS= read -r token; do
    [[ -n "$token" ]] && predicate+=("$token")
  done < <(build_find_predicate)

  while IFS= read -r file; do
    [[ -n "$file" ]] && ingest_file "$file"
  done < <(find "$base" -type f "${predicate[@]}" 2>/dev/null || true)
}

discover_openspec_dirs() {
  # Any openspec/ directories inside the project, capped at depth 3 for speed.
  find "$PROJECT_DIR" -maxdepth 3 -type d -name openspec 2>/dev/null || true
}

scan_all() {
  local IFS=','
  # shellcheck disable=SC2206
  local -a configured=($SCAN_PATHS $EXTRA_PATHS)
  for p in "${configured[@]}"; do
    p="${p## }"
    p="${p%% }"
    [[ -z "$p" ]] && continue
    if [[ "$p" = /* ]]; then
      scan_one_path "$p"
    else
      scan_one_path "$PROJECT_DIR/$p"
    fi
  done
  while IFS= read -r os; do
    [[ -n "$os" ]] && scan_one_path "$os"
  done < <(discover_openspec_dirs)
}

# ---- dispatch: hook mode vs scan mode --------------------------------------

if [[ "${1:-}" == "scan" ]]; then
  scan_all
  exit 0
fi

# Hook mode: try to read a JSON payload from stdin. If stdin is a terminal or
# the payload is empty, fall back to a full scan.
if [[ -t 0 ]]; then
  scan_all
  exit 0
fi

INPUT=$(cat)
if [[ -z "$INPUT" ]]; then
  scan_all
  exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

case "$TOOL" in
  Edit | Write | MultiEdit)
    if [[ -n "$FILE_PATH" ]]; then
      # Only ingest files that live inside a configured scan root.
      case "$FILE_PATH" in
        "$PROJECT_DIR"/*) ingest_file "$FILE_PATH" ;;
      esac
    fi
    ;;
  *) ;;
esac

exit 0
