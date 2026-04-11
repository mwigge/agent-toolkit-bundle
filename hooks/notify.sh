#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# notify.sh — Notification hook.
# Fires on any Claude Code notification event. Tries macOS (osascript),
# Linux (notify-send), and falls back silently.

set -euo pipefail

INPUT=$(cat)
MSG=$(printf '%s' "$INPUT" | jq -r '.message // "Claude Code needs attention"' 2>/dev/null || printf 'Claude Code needs attention')

# macOS — pass $MSG as a positional argument to osascript rather than
# interpolating it into the AppleScript source. Prevents AppleScript
# injection if the message contains double-quotes or backslashes.
if command -v osascript >/dev/null 2>&1; then
  osascript \
    -e 'on run argv' \
    -e '  display notification (item 1 of argv) with title "Claude Code"' \
    -e 'end run' \
    -- "$MSG" 2>/dev/null &
  exit 0
fi

# Linux / WSL — notify-send takes the message as a positional arg already,
# so no interpolation risk.
if command -v notify-send >/dev/null 2>&1; then
  notify-send "Claude Code" "$MSG" 2>/dev/null &
  exit 0
fi

exit 0
