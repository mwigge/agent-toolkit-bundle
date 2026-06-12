#!/usr/bin/env bash
# .claude/hooks/security-guard.sh
# PreToolUse gate — blocks destructive commands, protects sensitive paths,
# enforces no-secrets-in-code rule, and audits all tool calls.
# Exit 2 = block (stderr fed back to Claude). Exit 0 = allow.
#
# NOTE: the destructive-command and egress regexes below are best-effort
# tripwires, not a security boundary — they catch common cases (`rm -rf /`,
# force-push to main) but variants (`rm -fr /`, `find / -delete`, raw-IP
# URLs, `nc`/python egress) can slip through. permission-autoapprove.sh's
# RED/escalation tiers and human review are the real boundary.

set -euo pipefail
INPUT=$(cat || true)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
LOG_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/audit.log"

# ── Shared policy patterns ───────────────────────────────────────────────────
# policy/guard-patterns.json is the single source of truth for these regexes
# (shared with plugins/security-guard.ts and permission-autoapprove.sh). Fall
# back to the previous hardcoded values if the file is missing or unreadable
# so this hook degrades gracefully instead of failing outright.
SCRIPT_PATH="${BASH_SOURCE[0]}"
command -v readlink &>/dev/null && SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")"
POLICY_FILE="$(dirname "$SCRIPT_PATH")/../policy/guard-patterns.json"

load_pattern() {
  local key="$1" fallback="$2" val=""
  if [[ -f "$POLICY_FILE" ]]; then
    val=$(jq -r "$key" "$POLICY_FILE" 2>/dev/null || true)
  fi
  [[ -z "$val" || "$val" == "null" ]] && val="$fallback"
  echo "$val"
}

DESTRUCTIVE_PATTERN=$(load_pattern '.destructive_commands | join("|")' \
  'rm\s+-rf\s+/|git\s+push\s+--force\s+.*main|drop\s+table|truncate\s+table|format\s+[cCdD]:')
PROTECTED_FILE_PATTERN=$(load_pattern '.protected_files | join("|")' \
  '\.env$|\.env\.|migrations/.*\.(sql|py)$|pdm\.lock$|package-lock\.json$')
SECRET_PATTERN=$(load_pattern '.secret_pattern' \
  '(api_key|secret_key|password|token)\s*=\s*["'"'"'][^$'"'"'{][^"'"'"']{8,}')

# ── Audit log ────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
echo "$(date -u +%FT%TZ) TOOL=$TOOL FILE=${FILE_PATH:-} CMD=${COMMAND:0:120}" >> "$LOG_FILE"

# ── Bash: block destructive commands ─────────────────────────────────────────
if [[ "$TOOL" == "Bash" && -n "$COMMAND" ]]; then
  if echo "$COMMAND" | grep -qE "$DESTRUCTIVE_PATTERN"; then
    echo "BLOCKED: destructive command not permitted — $COMMAND" >&2
    exit 2
  fi
fi

# ── Edit/Write: protect sensitive paths ──────────────────────────────────────
if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]] && [[ -n "$FILE_PATH" ]]; then
  if echo "$FILE_PATH" | grep -qE "$PROTECTED_FILE_PATTERN"; then
    echo "BLOCKED: $FILE_PATH is a protected file — edit manually" >&2
    exit 2
  fi

  # Block committing secrets patterns (basic check) — scan the pending
  # content being written/edited, not whatever is already on disk.
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null || true)
  if [[ -n "$NEW_CONTENT" ]] && echo "$NEW_CONTENT" | grep -qiE "$SECRET_PATTERN"; then
    echo "BLOCKED: potential hardcoded secret in pending change to $FILE_PATH" >&2
    exit 2
  fi
fi

# ── Bash: egress allowlisting (Phase 1 — log-only) ─────────────────────────
ALLOWLIST_FILE="${HOME}/.claude/egress-allowlist.txt"
if [[ "$TOOL" == "Bash" && -n "$COMMAND" && -f "$ALLOWLIST_FILE" ]]; then
  # Extract every hostname seen in curl/wget/ssh/scp invocations (not just
  # the first) so e.g. `curl a.com b.evil.com` is fully checked.
  EGRESS_HOSTS=$(echo "$COMMAND" | grep -oE '(curl|wget|ssh|scp)\s+[^|;]*' | \
    grep -oE '(https?://)?([a-zA-Z0-9._-]+\.[a-zA-Z]{2,})' | \
    sed 's|https://||;s|http://||' | sort -u)

  while IFS= read -r EGRESS_HOST; do
    [[ -z "$EGRESS_HOST" ]] && continue
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
  done <<< "$EGRESS_HOSTS"
fi

exit 0
