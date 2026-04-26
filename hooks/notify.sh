#!/usr/bin/env bash
# .claude/hooks/notify.sh
# Async notification hook — fires on any Claude notification event.
# Tries macOS, Linux (notify-send), and falls back silently.

INPUT=$(cat)
MSG=$(echo "$INPUT" | jq -r '.message // "Claude Code needs attention"' 2>/dev/null || echo "Claude Code needs attention")

# macOS
if command -v osascript &>/dev/null; then
  osascript -e "display notification \"$MSG\" with title \"Claude Code\"" 2>/dev/null &
  exit 0
fi

# Linux / WSL
if command -v notify-send &>/dev/null; then
  notify-send "Claude Code" "$MSG" 2>/dev/null &
  exit 0
fi

exit 0
