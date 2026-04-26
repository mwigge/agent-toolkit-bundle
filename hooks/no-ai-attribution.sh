#!/usr/bin/env bash
# .claude/hooks/no-ai-attribution.sh
# PreToolUse gate — blocks git commits and PRs containing AI attribution.
# Only checks Bash commands that produce git commits or GitHub PRs.
# Does NOT block file edits (docs need to mention patterns as examples).
# Exit 2 = block. Exit 0 = allow.

set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only gate Bash commands
[[ "$TOOL" != "Bash" || -z "$COMMAND" ]] && exit 0

# Only check git commit and gh pr create commands
echo "$COMMAND" | grep -qE 'git\s+commit|gh\s+pr\s+create' || exit 0

# Patterns to block
AI_PATTERN='Co-Authored-By:.*[Cc]laude|Co-Authored-By:.*[Oo]pen[Aa][Ii]|Co-Authored-By:.*[Aa]ntropic|Generated with.*[Cc]laude|Generated with.*AI'

if echo "$COMMAND" | grep -qiE "$AI_PATTERN"; then
  echo "BLOCKED: AI attribution detected in git commit or PR. Remove Co-Authored-By, Generated-with footers, or AI references." >&2
  exit 2
fi

exit 0
