#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# setup-init.sh — SessionStart hook.
# First-run and per-session initialisation.
#   - Creates required directories if absent
#   - Injects a CLAUDE.md + memory.md reminder via additionalContext
#   - Idempotent: safe to run every session start

set -euo pipefail

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# --- Ensure required dirs exist ---------------------------------------------
mkdir -p \
  "$PROJECT/.claude/logs" \
  "$PROJECT/.claude/backups" \
  "$PROJECT/.claude/cache"

# --- Ensure audit.log exists ------------------------------------------------
touch "$PROJECT/.claude/audit.log"

# --- Hook executability check -----------------------------------------------
for hook in "$PROJECT"/.claude/hooks/*.sh; do
  [[ -f "$hook" ]] && chmod +x "$hook" 2>/dev/null || true
done

# --- Emit session start event to observability log -------------------------
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
echo "{\"ts\":\"$TIMESTAMP\",\"event\":\"SessionStart\",\"session_id\":\"$SESSION_ID\"}" \
  >>"$PROJECT/.claude/logs/events.ndjson" 2>/dev/null || true

# --- Context reminder via additionalContext ---------------------------------
# Looks for a project-level CLAUDE.md and an optional memory.md scratchpad.
# Both paths are convention, not contract - customise for your own layout.
CLAUDE_MD="$PROJECT/CLAUDE.md"
MEMORY_MD="$PROJECT/memory.md"

MSG="SESSION INITIALISED. "
if [[ -f "$CLAUDE_MD" ]]; then
  MSG+="Required reading before your first action: ${CLAUDE_MD} - project rules and conventions. "
fi
if [[ -f "$MEMORY_MD" ]]; then
  MSG+="Also review ${MEMORY_MD} - session state from previous work (active branch, pending tasks, key decisions). "
fi
MSG+="Apply conventional commits. No AI attribution. No hardcoded secrets."

jq -n --arg ctx "$MSG" '{"additionalContext": $ctx}'

exit 0
