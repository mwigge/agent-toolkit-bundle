#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# security-guard.sh — PreToolUse gate.
# Blocks destructive commands, protects sensitive paths, enforces the
# no-secrets-in-code rule, and audits all tool calls.
# Exit 2 = block (stderr fed back to the agent). Exit 0 = allow.

set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
LOG_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/audit.log"

# --- Audit log ---------------------------------------------------------------
mkdir -p "$(dirname "$LOG_FILE")"
echo "$(date -u +%FT%TZ) TOOL=$TOOL FILE=${FILE_PATH:-} CMD=${COMMAND:0:120}" >>"$LOG_FILE"

# --- Bash: block destructive commands ---------------------------------------
if [[ "$TOOL" == "Bash" && -n "$COMMAND" ]]; then
  if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+/|git\s+push\s+--force\s+.*main|drop\s+table|truncate\s+table|format\s+[cCdD]:'; then
    echo "BLOCKED: destructive command not permitted - $COMMAND" >&2
    exit 2
  fi
fi

# --- Edit/Write: protect sensitive paths ------------------------------------
if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]] && [[ -n "$FILE_PATH" ]]; then
  if echo "$FILE_PATH" | grep -qE '\.env$|\.env\.|migrations/.*\.(sql|py)$|pdm\.lock$|package-lock\.json$'; then
    echo "BLOCKED: $FILE_PATH is a protected file - edit manually" >&2
    exit 2
  fi

  # Block committing secrets patterns (basic check)
  if [[ -f "$FILE_PATH" ]]; then
    if grep -qE '(api_key|secret_key|password|token)\s*=\s*["'"'"'][^$][^"'"'"']{8,}' "$FILE_PATH" 2>/dev/null; then
      echo "BLOCKED: potential hardcoded secret detected in $FILE_PATH" >&2
      exit 2
    fi
  fi
fi

exit 0
