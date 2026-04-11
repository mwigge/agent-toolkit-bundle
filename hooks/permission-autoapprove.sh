#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# permission-autoapprove.sh — PermissionRequest hook.
# Rule-based auto-approval of safe operations.
# Exit 0     = allow (approved)
# Exit 2     = deny (stderr fed back to the agent)
# No output  = escalate to human (default behaviour)
#
# Rule tiers:
#   GREEN  -> auto-approve silently (exit 0)
#   YELLOW -> auto-approve with audit log entry
#   RED    -> deny with explanation (exit 2)
#   UNMATCHED -> fall through (human review)

set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
AUDIT="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/audit.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log_audit() {
  mkdir -p "$(dirname "$AUDIT")"
  echo "[$TIMESTAMP] PERMISSION tier=$1 tool=$TOOL cmd=${COMMAND:0:100} file=${FILE:0:80}" >>"$AUDIT" 2>/dev/null || true
}

# --- RED: always deny --------------------------------------------------------
if [[ "$TOOL" == "Bash" ]]; then
  if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+/|git\s+push\s+--force\s+(origin\s+)?(main|master)|DROP\s+TABLE|TRUNCATE\s+TABLE'; then
    log_audit "RED"
    echo "DENIED: This command is categorically unsafe - $COMMAND" >&2
    exit 2
  fi

  # Writing to /etc, /usr, /bin, /sbin
  if echo "$COMMAND" | grep -qE '(>|tee|cp|mv|install)\s+/etc/|/usr/(bin|lib|local)|/bin/|/sbin/'; then
    log_audit "RED"
    echo "DENIED: Writing to system paths requires explicit human approval" >&2
    exit 2
  fi
fi

if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]]; then
  # Protect lock files, .env, migrations
  if echo "$FILE" | grep -qE '\.env$|\.env\.|pdm\.lock$|package-lock\.json$|pnpm-lock\.yaml$|migrations/.*\.(sql|py)$'; then
    log_audit "RED"
    echo "DENIED: $FILE is a protected file - edit manually or get explicit approval" >&2
    exit 2
  fi
fi

# --- GREEN: auto-approve silently --------------------------------------------
if [[ "$TOOL" == "Read" || "$TOOL" == "Glob" || "$TOOL" == "Grep" ]]; then
  exit 0
fi

if [[ "$TOOL" == "Bash" ]]; then
  if echo "$COMMAND" | grep -qE '^(ls|cat|echo|pwd|which|git (status|log|diff|show|branch)|grep|find|head|tail|wc|sort|uniq)'; then
    exit 0
  fi
  # pytest, ruff, black, mypy, tsc - always safe
  if echo "$COMMAND" | grep -qE '^(pytest|ruff|black|mypy|npx tsc|npx vitest|pnpm (build|test|lint)|pdm run)'; then
    exit 0
  fi
fi

# --- YELLOW: approve with audit log ------------------------------------------
if [[ "$TOOL" == "Bash" ]]; then
  if echo "$COMMAND" | grep -qE '(pip install|pip-audit|npm install|pnpm install|pdm (add|remove|update))'; then
    log_audit "YELLOW"
    exit 0
  fi
  if echo "$COMMAND" | grep -qE '(git (add|commit|checkout|merge|rebase|tag)|docker (build|run|pull))'; then
    log_audit "YELLOW"
    exit 0
  fi
fi

if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]]; then
  if echo "$FILE" | grep -qE '\.(py|ts|tsx|js|sql|yaml|yml|json|md|sh)$'; then
    log_audit "YELLOW"
    exit 0
  fi
fi

# --- UNMATCHED: fall through to human ----------------------------------------
# No output, no exit code change - Claude Code will ask the human
exit 0
