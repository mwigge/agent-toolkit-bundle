#!/usr/bin/env bash
# .claude/hooks/codegraph-sync.sh
# After a Bash tool call containing `git add`, run codegraph sync
# to keep the code knowledge graph up-to-date with staged changes.
# Exit 0 always — sync is never a blocker.

set -euo pipefail
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# Only trigger on git add commands
if echo "$COMMAND" | grep -qE '(^|\s|&&|\||\;)git\s+add(\s|$)'; then
  if command -v codegraph &>/dev/null; then
    codegraph sync 2>/dev/null || true
  fi
fi

exit 0
