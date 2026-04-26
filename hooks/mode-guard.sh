#!/usr/bin/env bash
# .claude/hooks/mode-guard.sh
# PreToolUse circuit breaker — enforces separation between company and private work.
# Reads current mode from ~/.claude/mode (company | private).
#
# Customize COMPANY_PATTERN and PRIVATE_PATTERN for your directory layout.
# Neutral (both modes): this toolkit's own dir, ~/.ssh, ~/.claude, everything else
# Exit 2 = block (stderr fed back to Claude). Exit 0 = allow.

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

MODE_FILE="$HOME/.claude/mode"
MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "company")

# ── Customize these two patterns for your directory layout ──────────────────
# COMPANY_PATTERN matches paths that should only be writable in company mode.
# PRIVATE_PATTERN matches paths that should only be writable in private mode.
COMPANY_PATTERN='dev/src/(<your-work-dir>|<your-docs-dir>)($|/)'
PRIVATE_PATTERN='dev/src/(<your-personal-dir>|<your-side-projects-dir>)($|/)'
# ────────────────────────────────────────────────────────────────────────────

block() {
  echo "BLOCKED (mode-guard): $1" >&2
  echo "Current mode: $MODE. Switch with: mode company  |  mode private" >&2
  exit 2
}

check_path() {
  local path="$1"
  [[ -z "$path" ]] && return 0

  if echo "$path" | grep -qE "$COMPANY_PATTERN"; then
    if [[ "$MODE" == "private" ]]; then
      block "'$path' is a COMPANY path but mode is PRIVATE"
    fi
  fi
  if echo "$path" | grep -qE "$PRIVATE_PATTERN"; then
    if [[ "$MODE" == "company" ]]; then
      block "'$path' is a PRIVATE path but mode is COMPANY"
    fi
  fi
}

# Edit/Write: check the target file_path
if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]]; then
  check_path "$FILE_PATH"
fi

# Bash: scan the command string for /dev/src/X paths
if [[ "$TOOL" == "Bash" && -n "$COMMAND" ]]; then
  # Extract any occurrence of dev/src/<dirname>
  while IFS= read -r path; do
    [[ -n "$path" ]] && check_path "$path"
  done < <(echo "$COMMAND" | grep -oE '(/Users/<username>|\$HOME|~)?/?dev/src/[A-Za-z0-9._/-]+' || true)

  # Also check `cd <path>` targets explicitly
  if echo "$COMMAND" | grep -qE 'cd[[:space:]]+[^[:space:];&|]*dev/src/'; then
    cd_target=$(echo "$COMMAND" | grep -oE 'cd[[:space:]]+[^[:space:];&|]*' | head -1 | sed 's/^cd[[:space:]]*//')
    check_path "$cd_target"
  fi
fi

exit 0
