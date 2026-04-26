#!/usr/bin/env bash
# .claude/hooks/mempalace-ingest.sh
# PreCompact hook — mines OpenSpec artifacts and memory.md into MemPalace
# before context is compacted, preserving cross-session knowledge.
#
# Runs async (non-blocking) — output is ignored by Claude Code.
# Always exits 0. Fails gracefully if MemPalace is not installed.

set -uo pipefail

INPUT=$(cat)  # consume stdin (PreCompact payload)
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
LOG_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/logs"
mkdir -p "$LOG_DIR"

log_event() {
  local status="$1" detail="${2:-}"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"MemPalaceIngest\",\"session_id\":\"$SESSION_ID\",\"status\":\"$status\",\"detail\":\"$detail\"}" \
    >> "$LOG_DIR/events.ndjson" 2>/dev/null || true
}

# ── Resolve Python: prefer pyenv 3.12, fall back to python3 in PATH ──────────
resolve_python() {
  local pyenv_py="$HOME/.pyenv/versions/3.12.13/bin/python3"
  if [[ -x "$pyenv_py" ]] && "$pyenv_py" -c "import mempalace" 2>/dev/null; then
    echo "$pyenv_py"; return
  fi
  if python3 -c "import mempalace" 2>/dev/null; then
    echo "python3"; return
  fi
  echo ""
}

PYTHON="$(resolve_python)"

# ── Guard: MemPalace must be importable ──────────────────────────────────────
if [[ -z "$PYTHON" ]]; then
  log_event "skip" "mempalace not importable"
  exit 0
fi

# ── Locate docs_local ────────────────────────────────────────────────────────
find_docs_local() {
  if [[ -n "${DOCS_LOCAL_PATH:-}" && -d "$DOCS_LOCAL_PATH" ]]; then
    echo "$DOCS_LOCAL_PATH"; return
  fi
  local dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  for _ in 1 2 3 4 5; do
    if [[ -d "$dir/openspec/changes" ]]; then
      echo "$dir"; return
    fi
    dir="$(dirname "$dir")"
  done
  if [[ -d "$HOME/dev/src/docs_local" ]]; then
    echo "$HOME/dev/src/docs_local"; return
  fi
  echo ""
}

DOCS_LOCAL="$(find_docs_local)"

if [[ -z "$DOCS_LOCAL" ]]; then
  log_event "skip" "docs_local not found"
  exit 0
fi

CHANGES_DIR="$DOCS_LOCAL/openspec/changes"
MINED=0
ERRORS=0

mine_file() {
  local filepath="$1"
  if [[ ! -f "$filepath" ]]; then return; fi
  if "$PYTHON" -m mempalace mine "$filepath" 2>/dev/null; then
    MINED=$((MINED + 1))
  else
    ERRORS=$((ERRORS + 1))
  fi
}

# ── Mine recently modified OpenSpec change dirs (last 7 days) ────────────────
if [[ -d "$CHANGES_DIR" ]]; then
  while IFS= read -r -d '' change_dir; do
    for artifact in proposal.md design.md delivery.md; do
      mine_file "$change_dir/$artifact"
    done
    # tasks.md: only if under 150 lines (avoid noisy umbrella delivery plans)
    tasks_file="$change_dir/tasks.md"
    if [[ -f "$tasks_file" ]]; then
      line_count=$(wc -l < "$tasks_file" 2>/dev/null || echo 999)
      if [[ "$line_count" -lt 150 ]]; then
        mine_file "$tasks_file"
      fi
    fi
  done < <(find "$CHANGES_DIR" -mindepth 1 -maxdepth 1 -type d -newer "$CHANGES_DIR" -mtime -7 -print0 2>/dev/null)
fi

# ── Mine memory.md (session scratchpad) ─────────────────────────────────────
memory_file="$DOCS_LOCAL/memory.md"
if [[ -f "$memory_file" ]]; then
  mine_file "$memory_file"
fi

log_event "done" "mined=${MINED} errors=${ERRORS}"
exit 0
