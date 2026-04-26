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
	--agent)
		AGENT="$2"
		shift 2
		;;
	--dir)
		WORKDIR="$2"
		shift 2
		;;
	--prompt)
		PROMPT="$2"
		shift 2
		;;
	--timeout)
		TIMEOUT="$2"
		shift 2
		;;
	*)
		echo "unknown argument: $1" >&2
		exit 1
		;;
	esac
done

if [[ -z "$AGENT" ]]; then
	echo "delegate.sh: --agent is required" >&2
	exit 1
fi
if [[ -z "$PROMPT" ]]; then
	echo "delegate.sh: --prompt is required" >&2
	exit 1
fi
if [[ ! -d "$WORKDIR" ]]; then
	echo "delegate.sh: --dir '$WORKDIR' does not exist" >&2
	exit 1
fi

# OpenCode uses either agent/ (canonical) or agents/ (older layout) — check both.
AGENT_FILE=""
for _dir in "agent" "agents"; do
	_candidate="$HOME/.config/opencode/${_dir}/${AGENT}.md"
	if [[ -f "$_candidate" ]]; then
		AGENT_FILE="$_candidate"
		break
	fi
done
if [[ -z "$AGENT_FILE" ]]; then
	echo "delegate.sh: agent '${AGENT}' not found in ~/.config/opencode/agent/ or ~/.config/opencode/agents/" >&2
	exit 1
fi

# Resolve a portable timeout wrapper.
# macOS ships without GNU coreutils timeout; use gtimeout if available,
# otherwise fall back to perl as a last resort.
_timeout_cmd() {
	if command -v gtimeout >/dev/null 2>&1; then
		gtimeout "$@"
	elif command -v timeout >/dev/null 2>&1; then
		timeout "$@"
	else
		# No timeout wrapper available — run without a timeout guard.
		# Install coreutils via `brew install coreutils` for proper support.
		shift # drop the seconds argument
		"$@"
	fi
}

# --- delegation log: capture pre-run state ---
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_SECS=$SECONDS
PROMPT_HASH=$(printf '%s' "${PROMPT:0:200}" | shasum -a 256 | awk '{print $1}')
PRE_HASH=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || true)
# --- end pre-run state ---

# Use --dangerously-skip-permissions so subagent tool calls are auto-approved
# (permissions are scoped per-agent in the agent .md frontmatter).
# Note: || true prevents set -e from killing the script on non-zero exit;
# EXIT captures the real code for logging and final exit.
_timeout_cmd "${TIMEOUT}" opencode run \
	--agent "$AGENT" \
	--dir "$WORKDIR" \
	--dangerously-skip-permissions \
	"$PROMPT" || true

EXIT=$?
if [[ $EXIT -eq 124 ]]; then
	echo "delegate.sh: agent '${AGENT}' timed out after ${TIMEOUT}s" >&2
	# remap exit code so the log records the real cause
	EXIT=2
fi

# --- delegation log: write JSON-Lines record ---
# Guarded with set +e so a log failure never kills the delegation.
set +e
DURATION_S=$((SECONDS - START_SECS))
if [[ -n "$PRE_HASH" ]]; then
	_STAT=$(git -C "$WORKDIR" diff --stat "$PRE_HASH" HEAD 2>/dev/null || true)
	LINES_ADDED=$(echo "$_STAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' | head -1)
	LINES_REMOVED=$(echo "$_STAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' | head -1)
	LINES_ADDED=${LINES_ADDED:-0}
	LINES_REMOVED=${LINES_REMOVED:-0}
else
	LINES_ADDED=-1
	LINES_REMOVED=-1
fi
printf '{"ts":"%s","agent":"%s","workdir":"%s","prompt_hash":"%s","exit_code":%d,"duration_s":%d,"lines_added":%d,"lines_removed":%d}\n' \
	"$TS" "$AGENT" "$WORKDIR" "$PROMPT_HASH" "$EXIT" "$DURATION_S" "$LINES_ADDED" "$LINES_REMOVED" \
	>>~/.agent_delegation.log || true
set -e
# --- end delegation log ---

exit $EXIT
