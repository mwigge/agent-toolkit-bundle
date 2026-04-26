#!/usr/bin/env bash
# .claude/hooks/transcript-backup.sh
# PreCompact hook — runs before context is compacted.
# Saves current conversation transcript to .claude/backups/ so context loss is
# recoverable. Runs async (non-blocking) — always exits 0.
#
# Output file: .claude/backups/transcript-<session_id>-<timestamp>.jsonl

set -euo pipefail

INPUT=$(cat)
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
BACKUP_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/backups"

mkdir -p "$BACKUP_DIR"

OUTFILE="$BACKUP_DIR/transcript-${SESSION_ID}-${TIMESTAMP}.jsonl"

# Write the raw compaction input to disk (contains conversation context)
echo "$INPUT" | jq -c '.' > "$OUTFILE" 2>/dev/null || echo "$INPUT" > "$OUTFILE"

# Keep only the 10 most recent backups to avoid unbounded growth
ls -t "$BACKUP_DIR"/transcript-*.jsonl 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true

# Log to events
LOG_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/logs"
mkdir -p "$LOG_DIR"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"PreCompact\",\"session_id\":\"$SESSION_ID\",\"backup\":\"$OUTFILE\"}" \
  >> "$LOG_DIR/events.ndjson" 2>/dev/null || true

exit 0
