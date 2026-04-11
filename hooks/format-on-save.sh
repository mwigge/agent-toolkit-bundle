#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# format-on-save.sh — PostToolUse hook for Edit|Write.
# Auto-formats files after every Edit or Write tool call.
# Runs ruff+black for Python, prettier for TS/JS/JSON/YAML, sqlfluff for SQL,
# shfmt+shellcheck for shell scripts. Exit 0 always — formatting/linting is
# never a blocker.

set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

EXT="${FILE_PATH##*.}"

case "$EXT" in
  py)
    # ruff first (fixes imports, deprecated typing, unused vars)
    if command -v ruff &>/dev/null; then
      ruff check --fix --quiet "$FILE_PATH" 2>/dev/null || true
      ruff format --quiet "$FILE_PATH" 2>/dev/null || true
    fi
    # black for CI-matching format
    if command -v black &>/dev/null; then
      black --quiet "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  ts | tsx | js | jsx | mjs | cjs)
    if command -v prettier &>/dev/null; then
      prettier --write --log-level silent "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  json)
    if command -v prettier &>/dev/null; then
      prettier --write --log-level silent "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  yaml | yml)
    if command -v prettier &>/dev/null; then
      prettier --write --log-level silent "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  sql)
    if command -v sqlfluff &>/dev/null; then
      sqlfluff fix --dialect postgres --quiet "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  sh | bash)
    # shfmt first (auto-fix formatting), then shellcheck (advisory only).
    # shfmt writes its output back to the file; shellcheck just reports.
    if command -v shfmt &>/dev/null; then
      shfmt -w -i 2 -ci "$FILE_PATH" 2>/dev/null || true
    fi
    if command -v shellcheck &>/dev/null; then
      # Advisory only — print findings to stderr but never block.
      shellcheck "$FILE_PATH" >&2 2>/dev/null || true
    fi
    ;;
esac

exit 0
