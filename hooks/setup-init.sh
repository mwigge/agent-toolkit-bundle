#!/usr/bin/env bash
# .claude/hooks/setup-init.sh
# SessionStart hook — first-run and per-session initialisation.
# • Creates required directories if absent
# • Injects CLAUDE.md + memory.md reminder via additionalContext
# • Idempotent: safe to run every session start

set -euo pipefail

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ── Ensure required dirs exist ────────────────────────────────────────────────
mkdir -p \
  "$PROJECT/.claude/logs" \
  "$PROJECT/.claude/backups" \
  "$PROJECT/.claude/cache"

# ── Ensure audit.log exists ───────────────────────────────────────────────────
touch "$PROJECT/.claude/audit.log"

# ── Hook executability check ──────────────────────────────────────────────────
for hook in "$PROJECT"/.claude/hooks/*.sh; do
  [[ -f "$hook" ]] && chmod +x "$hook" 2>/dev/null || true
done

# ── Log rotation (50 MB threshold, 5 rotations) ─────────────────────────────
MAX_LOG_SIZE=$((50 * 1024 * 1024))
for logfile in events.ndjson model-usage.ndjson; do
  lpath="$PROJECT/.claude/logs/$logfile"
  if [[ -f "$lpath" ]]; then
    fsize=$(stat -f%z "$lpath" 2>/dev/null || stat -c%s "$lpath" 2>/dev/null || echo 0)
    if (( fsize > MAX_LOG_SIZE )); then
      for i in 4 3 2 1; do
        [[ -f "$lpath.$i.gz" ]] && mv "$lpath.$i.gz" "$lpath.$((i+1)).gz"
      done
      gzip -c "$lpath" > "$lpath.1.gz" 2>/dev/null
      : > "$lpath"
    fi
  fi
done

# ── Emit session start event to observability log ─────────────────────────────
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
echo "{\"ts\":\"$TIMESTAMP\",\"event\":\"SessionStart\",\"session_id\":\"$SESSION_ID\"}" \
  >> "$PROJECT/.claude/logs/events.ndjson" 2>/dev/null || true

# ── Context reminder via additionalContext ────────────────────────────────────
MEMORY_EXISTS=false
[[ -f "$PROJECT/ai_local/memory.md" ]] && MEMORY_EXISTS=true

MSG="SESSION INITIALISED. "
MSG+="Required reading before your first action: "
MSG+="(1) ${PROJECT}/ai_local/CLAUDE.md — project rules and conventions. "
if [[ "$MEMORY_EXISTS" == "true" ]]; then
  MSG+="(2) ${PROJECT}/ai_local/memory.md — session state from previous work (active branch, pending tasks, key decisions). "
fi
MSG+="Apply conventional commits. No AI attribution. No hardcoded secrets."

jq -n --arg ctx "$MSG" '{"additionalContext": $ctx}'

exit 0
