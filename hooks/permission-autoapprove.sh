#!/usr/bin/env bash
# .claude/hooks/permission-autoapprove.sh
# Rule-based auto-approval of safe operations (registered as PermissionRequest,
# see docs/hooks.md — input shape is identical to PreToolUse).
#
# Outcomes:
#   exit 0 + hookSpecificOutput JSON (permissionDecision=allow) = approved
#   exit 0, no stdout                                           = escalate to human (default)
#   exit 2 + stderr                                             = denied, message shown to Claude
#
# Rule tiers:
#   GREEN  -> auto-approve silently (allow decision, no audit entry)
#   YELLOW -> auto-approve with audit log entry (allow decision)
#   RED    -> deny with explanation (exit 2) or escalate self-edits to a human
#   UNMATCHED -> fall through (human review)

set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT"    | jq -r '.tool_name // ""'           2>/dev/null || true)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""'  2>/dev/null || true)
FILE=$(echo "$INPUT"    | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
# Echo back whatever event name the harness sent us so the decision JSON
# always matches the hook event this script is actually registered under.
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "PermissionRequest"' 2>/dev/null || echo "PermissionRequest")
AUDIT="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/audit.log"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Shared policy patterns ───────────────────────────────────────────────────
# policy/guard-patterns.json is the single source of truth for these regexes
# (shared with hooks/security-guard.sh and plugins/security-guard.ts). Fall
# back to the previous hardcoded values if the file is missing or unreadable
# so this hook degrades gracefully instead of failing outright.
SCRIPT_PATH="${BASH_SOURCE[0]}"
command -v readlink &>/dev/null && SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")"
POLICY_FILE="$(dirname "$SCRIPT_PATH")/../policy/guard-patterns.json"

load_pattern() {
  local key="$1" fallback="$2" val=""
  if [[ -f "$POLICY_FILE" ]]; then
    val=$(jq -r "$key" "$POLICY_FILE" 2>/dev/null || true)
  fi
  [[ -z "$val" || "$val" == "null" ]] && val="$fallback"
  echo "$val"
}

PROTECTED_FILE_PATTERN=$(load_pattern '.protected_files | join("|")' \
  '\.env$|\.env\.|pdm\.lock$|package-lock\.json$|pnpm-lock\.yaml$|migrations/.*\.(sql|py)$')
SELF_PROTECT_PATTERN=$(load_pattern '.self_protect_files | join("|")' \
  '\.claude/|\.github/workflows/|hooks/.*\.sh$|plugins/.*\.ts$|settings.*\.json$')

log_audit() {
  mkdir -p "$(dirname "$AUDIT")"
  echo "[$TIMESTAMP] PERMISSION tier=$1 tool=$TOOL cmd=${COMMAND:0:100} file=${FILE:0:80}" >> "$AUDIT" 2>/dev/null || true
}

# Emit an "allow" decision and exit 0.
approve() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$HOOK_EVENT" "$1"
  exit 0
}

# ── RED: always deny ──────────────────────────────────────────────────────────
if [[ "$TOOL" == "Bash" ]]; then
  if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+/|git\s+push\s+.*(-f\b|--force(-with-lease)?).*(\bmain\b|\bmaster\b)|git\s+push\s+.*(\bmain\b|\bmaster\b).*(-f\b|--force(-with-lease)?)|DROP\s+TABLE|TRUNCATE\s+TABLE'; then
    log_audit "RED"
    echo "DENIED: This command is categorically unsafe — $COMMAND" >&2
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
  if echo "$FILE" | grep -qE "$PROTECTED_FILE_PATTERN"; then
    log_audit "RED"
    echo "DENIED: $FILE is a protected file — edit manually or get explicit approval" >&2
    exit 2
  fi

  # Self-protection: edits to the guard/policy infrastructure itself always
  # escalate to a human (no decision), regardless of file extension — an
  # agent must not be able to silently widen its own permissions.
  if echo "$FILE" | grep -qE "$SELF_PROTECT_PATTERN"; then
    log_audit "ESCALATE-SELF"
    exit 0
  fi
fi

# ── GREEN: auto-approve silently ──────────────────────────────────────────────
if [[ "$TOOL" == "Read" || "$TOOL" == "Glob" || "$TOOL" == "Grep" ]]; then
  approve "read-only tool"
fi

if [[ "$TOOL" == "Bash" ]]; then
  if echo "$COMMAND" | grep -qE '^(ls|cat|echo|pwd|which|git (status|log|diff|show|branch)|grep|find|head|tail|wc|sort|uniq)'; then
    approve "read-only inspection command"
  fi
  # pytest, ruff, black, mypy, tsc — always safe
  if echo "$COMMAND" | grep -qE '^(pytest|ruff|black|mypy|npx tsc|npx vitest|pnpm (build|test|lint)|pdm run)'; then
    approve "test/lint/build command"
  fi
fi

# ── YELLOW: approve with audit log ────────────────────────────────────────────
if [[ "$TOOL" == "Bash" ]]; then
  # Dependency installs are a deliberate YELLOW (approved + audited) rather
  # than an escalation — see docs/hooks.md for the rationale.
  if echo "$COMMAND" | grep -qE '(pip install|pip-audit|npm install|pnpm install|pdm (add|remove|update))'; then
    log_audit "YELLOW"
    approve "dependency management command (audited)"
  fi
  if echo "$COMMAND" | grep -qE '(git (add|commit|checkout|merge|rebase|tag)|docker (build|run|pull))'; then
    log_audit "YELLOW"
    approve "git/docker workflow command (audited)"
  fi
fi

if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]]; then
  if echo "$FILE" | grep -qE '\.(py|ts|tsx|js|sql|yaml|yml|json|md|sh)$'; then
    # Only auto-approve source files inside the project tree; absolute paths
    # outside $CLAUDE_PROJECT_DIR fall through to human review.
    if [[ "$FILE" != /* || "$FILE" == "$PROJECT_DIR"/* ]]; then
      log_audit "YELLOW"
      approve "edit to project source file (audited)"
    fi
  fi
fi

# ── UNMATCHED: fall through to human ─────────────────────────────────────────
# No output, no exit code change — Claude Code will ask the human
exit 0
