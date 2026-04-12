#!/usr/bin/env bash
# delegate.sh — dispatch a task to an OpenCode subagent via `opencode run`
#
# Usage:
#   delegate.sh --agent <agent-name> --dir <workdir> --prompt <text>
#   delegate.sh --agent coder-rust --dir /path/to/repo --prompt "Fix the build..."
#
# The agent runs in its own OpenCode session with the full native tool loop
# (primary-tier model with streaming tool calls). Output is printed to stdout.
#
# Exit codes:
#   0  — agent completed successfully
#   1  — missing required argument
#   2  — opencode run failed / timed out
#
# This is the correct delegation mechanism from orchestrator → primary-tier agents.
# Do NOT use the Claude Code `task` tool for coder agents — it does not give
# the local model the iterative tool loop it needs to actually execute commands.

set -euo pipefail

AGENT=""
WORKDIR="$PWD"
PROMPT=""
TIMEOUT="${DELEGATE_TIMEOUT:-600}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)   AGENT="$2";   shift 2 ;;
    --dir)     WORKDIR="$2"; shift 2 ;;
    --prompt)  PROMPT="$2";  shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$AGENT" ]]; then
  echo "delegate.sh: --agent is required" >&2; exit 1
fi
if [[ -z "$PROMPT" ]]; then
  echo "delegate.sh: --prompt is required" >&2; exit 1
fi
if [[ ! -d "$WORKDIR" ]]; then
  echo "delegate.sh: --dir '$WORKDIR' does not exist" >&2; exit 1
fi

AGENT_FILE="$HOME/.config/opencode/agents/${AGENT}.md"
if [[ ! -f "$AGENT_FILE" ]]; then
  echo "delegate.sh: agent '${AGENT}' not found at ${AGENT_FILE}" >&2; exit 1
fi

# Use --dangerously-skip-permissions so subagent tool calls are auto-approved
# (permissions are scoped per-agent in the agent .md frontmatter).
timeout "${TIMEOUT}" opencode run \
  --agent  "$AGENT"   \
  --dir    "$WORKDIR" \
  --dangerously-skip-permissions \
  "$PROMPT"

EXIT=$?
if [[ $EXIT -eq 124 ]]; then
  echo "delegate.sh: agent '${AGENT}' timed out after ${TIMEOUT}s" >&2; exit 2
fi
exit $EXIT
