#!/usr/bin/env bash
# .claude/hooks/security-guard.sh
# PreToolUse gate — blocks destructive commands, protects sensitive paths,
# enforces no-secrets-in-code rule, and audits all tool calls.
# Exit 2 = block (stderr fed back to Claude). Exit 0 = allow.

set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
LOG_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/audit.log"

# ── Audit log ────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
echo "$(date -u +%FT%TZ) TOOL=$TOOL FILE=${FILE_PATH:-} CMD=${COMMAND:0:120}" >> "$LOG_FILE"

# ── Bash: block destructive commands ─────────────────────────────────────────
if [[ "$TOOL" == "Bash" && -n "$COMMAND" ]]; then
  if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+/|git\s+push\s+--force\s+.*main|drop\s+table|truncate\s+table|format\s+[cCdD]:'; then
    echo "BLOCKED: destructive command not permitted — $COMMAND" >&2
    exit 2
  fi
fi

# ── Edit/Write: protect sensitive paths ──────────────────────────────────────
if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]] && [[ -n "$FILE_PATH" ]]; then
  if echo "$FILE_PATH" | grep -qE '\.env$|\.env\.|migrations/.*\.(sql|py)$|pdm\.lock$|package-lock\.json$'; then
    echo "BLOCKED: $FILE_PATH is a protected file — edit manually" >&2
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

# ── Bash: egress allowlisting (Phase 1 — log-only) ─────────────────────────
ALLOWLIST_FILE="${HOME}/.claude/egress-allowlist.txt"
if [[ "$TOOL" == "Bash" && -n "$COMMAND" && -f "$ALLOWLIST_FILE" ]]; then
  # Extract hostname from curl/wget/ssh/scp commands
  EGRESS_HOST=$(echo "$COMMAND" | grep -oE '(curl|wget|ssh|scp)\s+[^|;]*' | \
    grep -oE '(https?://)?([a-zA-Z0-9._-]+\.[a-zA-Z]{2,})' | \
    head -1 | sed 's|https://||;s|http://||')

  if [[ -n "$EGRESS_HOST" ]]; then
    ALLOWED=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"  # strip comments
      line="${line// /}"  # strip spaces
      [[ -z "$line" ]] && continue
      if [[ "$line" == \** ]]; then
        # Wildcard: *.ginfra.net matches foo.ginfra.net
        suffix="${line#\*}"
        [[ "$EGRESS_HOST" == *"$suffix" ]] && ALLOWED=true && break
      else
        [[ "$EGRESS_HOST" == "$line" ]] && ALLOWED=true && break
      fi
    done < "$ALLOWLIST_FILE"

    if [[ "$ALLOWED" == "false" ]]; then
      echo "$(date -u +%FT%TZ) EGRESS-WARNING host=$EGRESS_HOST command=${COMMAND:0:80} risk=2" >> "$LOG_FILE"
      # Phase 1: log only, do not block
      # Phase 2: uncomment the next two lines to enforce
      # echo "BLOCKED: egress to $EGRESS_HOST not in allowlist" >&2
      # exit 2
    fi
  fi
fi

exit 0
