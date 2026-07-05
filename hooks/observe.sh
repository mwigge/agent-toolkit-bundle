#!/usr/bin/env bash
# .claude/hooks/observe.sh
# Universal observability hook — writes structured NDJSON to .claude/logs/events.ndjson
# Fires on all lifecycle events: PreToolUse, PostToolUse, Stop, Notification, etc.
# Pattern inspired by disler/claude-code-hooks-multi-agent-observability
#
# Log format (one JSON object per line):
#   { "ts": "<ISO8601>", "session_id": "...", "event": "...", "tool": "...",
#     "input_summary": "...", "outcome": "ok|blocked|error", "risk": 0-3 }

set -euo pipefail
command -v jq >/dev/null 2>&1 || exit 0  # fail-open: no jq, no audit event

INPUT=$(cat)
PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOG_DIR="$PROJECT/.claude/logs"
LOG_FILE="$LOG_DIR/events.ndjson"
mkdir -p "$LOG_DIR"

# ── Extract common fields ─────────────────────────────────────────────────────
EVENT_TYPE="${CLAUDE_HOOK_EVENT_TYPE:-unknown}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // .tool // "none"' 2>/dev/null || echo "none")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── OTel tracing (via otel-cli) ──────────────────────────────────────────────
OTEL_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}"
OTEL_SERVICE="ai-agent"
OTEL_ENABLED=false
if command -v otel-cli &>/dev/null; then
  OTEL_ENABLED=true
fi

# ── Risk scoring ──────────────────────────────────────────────────────────────
# 0=info  1=low  2=medium  3=high
risk_score() {
  local tool="$1"
  local summary="$2"
  case "$tool" in
    Bash)
      # High risk: destructive, secret-touching, network egress
      if echo "$summary" | grep -qiE '(rm -rf|drop table|truncate|curl|wget|ssh|scp|rsync|git push|git reset|pip install|npm install)'; then
        echo 3; return
      fi
      # Medium: writes, migrations, env
      if echo "$summary" | grep -qiE '(\.env|migration|ALTER TABLE|CREATE TABLE|chmod|chown)'; then
        echo 2; return
      fi
      echo 1
      ;;
    Write|Edit)
      if echo "$summary" | grep -qiE '(\.env|settings\.local|pdm\.lock|package-lock)'; then
        echo 2; return
      fi
      echo 1
      ;;
    WebFetch)   echo 1 ;;
    *)          echo 0 ;;
  esac
}

# ── Summarise input ───────────────────────────────────────────────────────────
summarise_input() {
  local tool="$1"
  local raw="$2"
  case "$tool" in
    Bash)
      echo "$raw" | jq -r '.input.command // .command // ""' 2>/dev/null | cut -c1-200 || echo ""
      ;;
    Write|Edit)
      echo "$raw" | jq -r '.input.file_path // .file_path // ""' 2>/dev/null || echo ""
      ;;
    Read|Glob|Grep)
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

# ── Determine outcome ─────────────────────────────────────────────────────────
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

# ── Write NDJSON line ─────────────────────────────────────────────────────────
# Read previous hash for chain continuity
PREV_HASH="genesis"
if [[ -s "$LOG_FILE" ]]; then
  PREV_HASH=$(tail -1 "$LOG_FILE" | jq -r '._hash // "genesis"' 2>/dev/null || echo "genesis")
fi

ENTRY_BODY=$(jq -c -n \
  --arg ts        "$TIMESTAMP" \
  --arg session   "$SESSION_ID" \
  --arg event     "$EVENT_TYPE" \
  --arg tool      "$TOOL_NAME" \
  --arg summary   "$SUMMARY" \
  --arg outcome   "$OUTCOME" \
  --argjson risk  "$RISK" \
  --arg prev      "$PREV_HASH" \
  '{ts: $ts, session_id: $session, event: $event, tool: $tool,
    input_summary: $summary, outcome: $outcome, risk: $risk,
    _prev_hash: $prev}' 2>/dev/null || echo "")

if [[ -n "$ENTRY_BODY" ]]; then
  ENTRY_HASH=$(printf '%s' "$ENTRY_BODY" | shasum -a 256 | cut -d' ' -f1)
  echo "$ENTRY_BODY" | jq -c --arg h "$ENTRY_HASH" '. + {_hash: $h}' \
    >> "$LOG_FILE" 2>/dev/null || echo "$ENTRY_BODY" >> "$LOG_FILE" 2>/dev/null || true
fi

# ── Risk-3 events also write to audit.log ────────────────────────────────────
if [[ "$RISK" -ge 3 ]]; then
  AUDIT="$PROJECT/.claude/audit.log"
  echo "[$TIMESTAMP] HIGH-RISK event=$EVENT_TYPE tool=$TOOL_NAME summary=${SUMMARY:0:150}" >> "$AUDIT" 2>/dev/null || true
fi

# ── OTel span emission (async, fire-and-forget) ─────────────────────────────
if [[ "$OTEL_ENABLED" == "true" ]]; then
  (
    case "$EVENT_TYPE" in
      SessionStart)
        # Create session root span (background — kept open until Stop)
        otel-cli span \
          --service "$OTEL_SERVICE" \
          --name "ai.session" \
          --endpoint "$OTEL_ENDPOINT" \
          --attrs "ai.session.id=$SESSION_ID" \
          --timeout 3s 2>/dev/null || true
        ;;
      PreToolUse)
        # Tool-call span with attributes
        otel-cli span \
          --service "$OTEL_SERVICE" \
          --name "ai.tool.call" \
          --endpoint "$OTEL_ENDPOINT" \
          --attrs "ai.tool.name=$TOOL_NAME,ai.tool.risk_level=$RISK,ai.session.id=$SESSION_ID" \
          --timeout 2s 2>/dev/null || true
        ;;
      Stop)
        # Session-end span
        otel-cli span \
          --service "$OTEL_SERVICE" \
          --name "ai.session.end" \
          --endpoint "$OTEL_ENDPOINT" \
          --attrs "ai.session.id=$SESSION_ID,ai.outcome=completed" \
          --timeout 3s 2>/dev/null || true
        ;;
    esac
  ) &
fi

exit 0
