#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# observe.sh — Universal observability hook.
# Writes structured NDJSON to .claude/logs/events.ndjson.
# Fires on all lifecycle events: PreToolUse, PostToolUse, Stop, Notification, etc.
#
# Log format (one JSON object per line):
#   { "ts": "<ISO8601>", "session_id": "...", "event": "...", "tool": "...",
#     "input_summary": "...", "outcome": "ok|blocked|error", "risk": 0-3 }

set -euo pipefail

INPUT=$(cat)
LOG_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/logs"
LOG_FILE="$LOG_DIR/events.ndjson"
mkdir -p "$LOG_DIR"

# --- Extract common fields ---------------------------------------------------
EVENT_TYPE="${CLAUDE_HOOK_EVENT_TYPE:-unknown}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // .tool // "none"' 2>/dev/null || echo "none")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Risk scoring ------------------------------------------------------------
# 0=info  1=low  2=medium  3=high
risk_score() {
  local tool="$1"
  local summary="$2"
  case "$tool" in
    Bash)
      # High risk: destructive, secret-touching, network egress
      if echo "$summary" | grep -qiE '(rm -rf|drop table|truncate|curl|wget|ssh|scp|rsync|git push|git reset|pip install|npm install)'; then
        echo 3
        return
      fi
      # Medium: writes, migrations, env
      if echo "$summary" | grep -qiE '(\.env|migration|ALTER TABLE|CREATE TABLE|chmod|chown)'; then
        echo 2
        return
      fi
      echo 1
      ;;
    Write | Edit)
      if echo "$summary" | grep -qiE '(\.env|settings\.local|pdm\.lock|package-lock)'; then
        echo 2
        return
      fi
      echo 1
      ;;
    WebFetch) echo 1 ;;
    *) echo 0 ;;
  esac
}

# --- Summarise input ---------------------------------------------------------
summarise_input() {
  local tool="$1"
  local raw="$2"
  case "$tool" in
    Bash)
      echo "$raw" | jq -r '.input.command // .command // ""' 2>/dev/null | cut -c1-200 || echo ""
      ;;
    Write | Edit)
      echo "$raw" | jq -r '.input.file_path // .file_path // ""' 2>/dev/null || echo ""
      ;;
    Read | Glob | Grep)
      echo "$raw" | jq -r '.input.file_path // .input.pattern // .pattern // ""' 2>/dev/null || echo ""
      ;;
    WebFetch)
      echo "$raw" | jq -r '.input.url // .url // ""' 2>/dev/null || echo ""
      ;;
    *)
      echo "$raw" | jq -r 'to_entries | map(.key + "=" + (.value | tostring)) | join(" ")' 2>/dev/null | cut -c1-200 || echo ""
      ;;
  esac
}

# --- Determine outcome -------------------------------------------------------
OUTCOME="ok"
# PostToolUse failure signals
if [[ "$EVENT_TYPE" == "PostToolUseFailure" ]]; then
  OUTCOME="error"
fi
# PreToolUse block signals
if echo "$INPUT" | jq -e '.decision == "block"' &>/dev/null 2>&1; then
  OUTCOME="blocked"
fi

SUMMARY=$(summarise_input "$TOOL_NAME" "$INPUT")
RISK=$(risk_score "$TOOL_NAME" "$SUMMARY")

# --- Write NDJSON line -------------------------------------------------------
jq -c -n \
  --arg ts "$TIMESTAMP" \
  --arg session "$SESSION_ID" \
  --arg event "$EVENT_TYPE" \
  --arg tool "$TOOL_NAME" \
  --arg summary "$SUMMARY" \
  --arg outcome "$OUTCOME" \
  --argjson risk "$RISK" \
  '{ts: $ts, session_id: $session, event: $event, tool: $tool,
    input_summary: $summary, outcome: $outcome, risk: $risk}' \
  >>"$LOG_FILE" 2>/dev/null || true

# --- Risk-3 events also write to audit.log -----------------------------------
if [[ "$RISK" -ge 3 ]]; then
  AUDIT="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/audit.log"
  echo "[$TIMESTAMP] HIGH-RISK event=$EVENT_TYPE tool=$TOOL_NAME summary=${SUMMARY:0:150}" >>"$AUDIT" 2>/dev/null || true
fi

exit 0
