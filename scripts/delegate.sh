#!/usr/bin/env bash
# delegate.sh — dispatch a task to an OpenCode subagent via `opencode run`
#
# Usage:
#   delegate.sh --agent <agent-name> --dir <workdir> --prompt <text>
#   delegate.sh --agent coder-rust --dir /path/to/repo --prompt "Fix the build..."
#   delegate.sh --agent coder-go   --dir /path/to/repo --spec-file /tmp/task.md
#   delegate.sh --agent coder-go   --dir /path/to/repo --session <id> --continue
#
# Flags:
#   --agent       Agent name (required unless --continue with --session)
#   --dir         Working directory (default: $PWD)
#   --prompt      Inline task prompt (mutually exclusive with --spec-file)
#   --spec-file   Path to a markdown spec file — preferred for multi-file tasks;
#                 reduces inline context pressure on the subagent
#   --session     Session ID to continue (use with --continue)
#   --continue    Resume a previous session (requires --session)
#   --timeout     Wall-clock timeout in seconds (default: $DELEGATE_TIMEOUT or 600)
#   --stall-limit Seconds with no new commit before declaring stalled (default: 300)
#
# Exit codes:
#   0  — agent completed and produced output
#   1  — missing required argument or bad invocation
#   2  — timed out (no progress at all)
#   3  — stalled (some commits made but then no progress for --stall-limit seconds)
#   4  — agent ran but produced zero lines (silent failure)
#
# Environment:
#   DELEGATE_TIMEOUT   Override default wall-clock timeout
#
# Progress detection:
#   A background poller watches `git log` every 30s. If a new commit appears,
#   the stall timer resets. If --stall-limit seconds pass with no new commit,
#   the agent is killed and exit 3 is returned with a partial-work report.
#
# Session resume:
#   The session ID is written to ~/.agent_sessions/<agent>_<ts>.id after each run.
#   Use --session <id> --continue to resume a stalled session.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
AGENT=""
WORKDIR="$PWD"
PROMPT=""
SPEC_FILE=""
SESSION_ID=""
DO_CONTINUE=false
TIMEOUT="${DELEGATE_TIMEOUT:-600}"
STALL_LIMIT=450   # seconds without any activity → stalled

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
	case "$1" in
	--agent)      AGENT="$2";      shift 2 ;;
	--dir)        WORKDIR="$2";    shift 2 ;;
	--prompt)     PROMPT="$2";     shift 2 ;;
	--spec-file)  SPEC_FILE="$2";  shift 2 ;;
	--session)    SESSION_ID="$2"; shift 2 ;;
	--continue)   DO_CONTINUE=true; shift ;;
	--timeout)    TIMEOUT="$2";    shift 2 ;;
	--stall-limit) STALL_LIMIT="$2"; shift 2 ;;
	*) echo "delegate.sh: unknown argument: $1" >&2; exit 1 ;;
	esac
done

# ── Validation ────────────────────────────────────────────────────────────────
if [[ -z "$AGENT" ]]; then
	echo "delegate.sh: --agent is required" >&2; exit 1
fi
if [[ -z "$PROMPT" && -z "$SPEC_FILE" && "$DO_CONTINUE" == false ]]; then
	echo "delegate.sh: one of --prompt, --spec-file, or --continue is required" >&2; exit 1
fi
if [[ -n "$PROMPT" && -n "$SPEC_FILE" ]]; then
	echo "delegate.sh: --prompt and --spec-file are mutually exclusive" >&2; exit 1
fi
if [[ "$DO_CONTINUE" == true && -z "$SESSION_ID" ]]; then
	echo "delegate.sh: --continue requires --session <id>" >&2; exit 1
fi
if [[ ! -d "$WORKDIR" ]]; then
	echo "delegate.sh: --dir '$WORKDIR' does not exist" >&2; exit 1
fi
if [[ -n "$SPEC_FILE" && ! -f "$SPEC_FILE" ]]; then
	echo "delegate.sh: --spec-file '$SPEC_FILE' does not exist" >&2; exit 1
fi

# ── Agent file lookup ─────────────────────────────────────────────────────────
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_FILE=""
for _candidate in \
	"$HOME/.config/opencode/agents/${AGENT}.md" \
	"$HOME/.config/opencode/agent/${AGENT}.md" \
	"${_SCRIPT_DIR}/../agents/opencode/${AGENT}.md" \
	"${_SCRIPT_DIR}/${AGENT}.md"; do
	if [[ -f "$_candidate" ]]; then
		AGENT_FILE="$_candidate"
		break
	fi
done
if [[ -z "$AGENT_FILE" ]]; then
	echo "delegate.sh: agent '${AGENT}' not found (searched ~/.config/opencode/agents/, bundle agents/opencode/)" >&2
	exit 1
fi

# ── Portable timeout wrapper ───────────────────────────────────────────────────
_timeout_cmd() {
	if command -v gtimeout >/dev/null 2>&1; then
		gtimeout "$@"
	elif command -v timeout >/dev/null 2>&1; then
		timeout "$@"
	else
		shift; "$@"
	fi
}

# ── Spec file handling ────────────────────────────────────────────────────────
_TMP_SPEC=""
_cleanup_spec() { [[ -n "$_TMP_SPEC" ]] && rm -f "$_TMP_SPEC"; }
trap _cleanup_spec EXIT

EXTRA_FILE_ARGS=()
EFFECTIVE_PROMPT=""

# Inject subagent rules: prefer ~/.config/opencode/ then bundle-local scripts/
_SUBAGENT_RULES=""
for _sr in "$HOME/.config/opencode/subagent_AGENTS.md" "${_SCRIPT_DIR}/subagent_AGENTS.md"; do
	if [[ -f "$_sr" ]]; then
		_SUBAGENT_RULES="$_sr"
		break
	fi
done
if [[ -n "$_SUBAGENT_RULES" ]]; then
	EXTRA_FILE_ARGS=(--file "$_SUBAGENT_RULES")
fi

if [[ -n "$SPEC_FILE" ]]; then
	# Pass the spec file directly to opencode; inline prompt is just a short header
	EFFECTIVE_PROMPT="Implement the task described in the attached spec file."
	EXTRA_FILE_ARGS+=("--file" "$SPEC_FILE")
elif [[ -n "$PROMPT" ]]; then
	# For long prompts, write to a tmp file to keep inline args clean
	if [[ ${#PROMPT} -gt 500 ]]; then
		_TMP_SPEC=$(mktemp /tmp/delegate_spec_XXXXXX.md)
		printf '%s\n' "$PROMPT" > "$_TMP_SPEC"
		EFFECTIVE_PROMPT="Implement the task described in the attached spec file."
		EXTRA_FILE_ARGS=(--file "$_TMP_SPEC")
	else
		EFFECTIVE_PROMPT="$PROMPT"
	fi
fi

# ── Pre-run state ─────────────────────────────────────────────────────────────
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_SECS=$SECONDS
PROMPT_HASH=$(printf '%s' "${EFFECTIVE_PROMPT}${SPEC_FILE}" | shasum -a 256 | awk '{print $1}')
PRE_HASH=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "")
LAST_COMMIT_HASH="$PRE_HASH"
LAST_COMMIT_SECS=$SECONDS

# ── Session directory ─────────────────────────────────────────────────────────
SESSION_DIR="$HOME/.agent_sessions"
mkdir -p "$SESSION_DIR"

# ── Build opencode command ────────────────────────────────────────────────────
OC_ARGS=(
	--agent "$AGENT"
	--dir   "$WORKDIR"
	--dangerously-skip-permissions
)
if [[ "$DO_CONTINUE" == true ]]; then
	OC_ARGS+=(--session "$SESSION_ID" --continue)
fi
if [[ ${#EXTRA_FILE_ARGS[@]} -gt 0 ]]; then
	OC_ARGS+=("${EXTRA_FILE_ARGS[@]}")
fi

# ── Progress poller ───────────────────────────────────────────────────────────
# Runs in background; updates LAST_COMMIT_HASH and LAST_COMMIT_SECS.
# If stall is detected, kills the opencode process.
OC_PID=""
POLLER_PID=""

_poller() {
	local oc_pid="$1"
	local workdir="$2"
	local stall_limit="$3"
	local last_hash="$4"
	local last_secs=$SECONDS
	# Also track newest mtime of tracked files — any write resets the stall timer
	local last_mtime=""
	last_mtime=$(git -C "$workdir" ls-files 2>/dev/null 		| xargs stat -f "%m" 2>/dev/null 		| sort -rn | head -1 || echo "0")

	while kill -0 "$oc_pid" 2>/dev/null; do
		sleep 30
		current_hash=$(git -C "$workdir" rev-parse HEAD 2>/dev/null || echo "")
		if [[ "$current_hash" != "$last_hash" ]]; then
			last_hash="$current_hash"
			last_secs=$SECONDS
			echo "delegate.sh [poller]: new commit detected — stall timer reset" >&2
			last_mtime=$(git -C "$workdir" ls-files 2>/dev/null 				| xargs stat -f "%m" 2>/dev/null 				| sort -rn | head -1 || echo "0")
			continue
		fi
		# Check if any tracked file was written since last check
		current_mtime=$(git -C "$workdir" ls-files 2>/dev/null 			| xargs stat -f "%m" 2>/dev/null 			| sort -rn | head -1 || echo "0")
		if [[ "$current_mtime" != "$last_mtime" ]]; then
			last_mtime="$current_mtime"
			last_secs=$SECONDS
			echo "delegate.sh [poller]: file write detected — stall timer reset" >&2
			continue
		fi
		stalled_for=$(( SECONDS - last_secs ))
		if [[ $stalled_for -ge $stall_limit ]]; then
			echo "delegate.sh [poller]: no activity for ${stalled_for}s (limit ${stall_limit}s) — killing agent" >&2
			kill "$oc_pid" 2>/dev/null || true
			return
		fi
	done
}

# ── Run ───────────────────────────────────────────────────────────────────────
EXIT=0

_timeout_cmd "${TIMEOUT}" opencode run "${OC_ARGS[@]}" -- "$EFFECTIVE_PROMPT" &
OC_PID=$!

# Start poller (only meaningful for git repos)
if [[ -n "$PRE_HASH" ]]; then
	_poller "$OC_PID" "$WORKDIR" "$STALL_LIMIT" "$PRE_HASH" &
	POLLER_PID=$!
fi

wait "$OC_PID" || EXIT=$?

# Stop the poller if it's still running
if [[ -n "$POLLER_PID" ]]; then
	kill "$POLLER_PID" 2>/dev/null || true
	wait "$POLLER_PID" 2>/dev/null || true
fi

# Remap timeout exit codes
if [[ $EXIT -eq 124 || $EXIT -eq 143 ]]; then
	echo "delegate.sh: agent '${AGENT}' timed out or was stalled-killed after ${TIMEOUT}s" >&2
	EXIT=2
fi

# ── Ollama fallback ───────────────────────────────────────────────────────────
# If opencode stalled (exit 2/3) and no commits were produced, retry with the
# direct ollama_agent.py wrapper which bypasses opencode entirely.
_OLLAMA_AGENT="${_SCRIPT_DIR}/ollama_agent.py"
if [[ $EXIT -eq 2 || $EXIT -eq 3 ]] && [[ -f "$_OLLAMA_AGENT" ]]; then
	echo "delegate.sh: opencode stalled — retrying with ollama_agent.py fallback" >&2
	_OA_EXIT=0
	_OA_ARGS=(--agent "$AGENT" --dir "$WORKDIR" --max-turns 40 --timeout 90)
	if [[ -n "$SPEC_FILE" ]]; then
		_OA_ARGS+=(--spec-file "$SPEC_FILE")
	elif [[ -n "$_TMP_SPEC" ]]; then
		_OA_ARGS+=(--spec-file "$_TMP_SPEC")
	else
		_OA_ARGS+=(--prompt "$EFFECTIVE_PROMPT")
	fi
	python3 "$_OLLAMA_AGENT" "${_OA_ARGS[@]}" >&2 || _OA_EXIT=$?
	if [[ $_OA_EXIT -eq 0 ]]; then
		echo "delegate.sh: ollama fallback succeeded" >&2
		EXIT=0
	else
		echo "delegate.sh: ollama fallback also failed (exit $_OA_EXIT)" >&2
	fi
fi

# ── Session ID capture ────────────────────────────────────────────────────────
# opencode writes its session ID to stdout in some versions; attempt to scrape it.
# Also store the last-known session lookup path for manual resume.
SESSION_FILE="${SESSION_DIR}/${AGENT}_${TS//[: ]/_}.last"
printf 'agent=%s\nts=%s\nworkdir=%s\ntimeout=%s\nexit=%d\n' \
	"$AGENT" "$TS" "$WORKDIR" "$TIMEOUT" "$EXIT" > "$SESSION_FILE"

# ── Post-run analysis ─────────────────────────────────────────────────────────
set +e
DURATION_S=$((SECONDS - START_SECS))
LINES_ADDED=0
LINES_REMOVED=0
COMMITS_MADE=0

if [[ -n "$PRE_HASH" ]]; then
	POST_HASH=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "")
	if [[ "$POST_HASH" != "$PRE_HASH" ]]; then
		_STAT=$(git -C "$WORKDIR" diff --stat "$PRE_HASH" HEAD 2>/dev/null || true)
		LINES_ADDED=$(echo "$_STAT"  | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' | head -1)
		LINES_REMOVED=$(echo "$_STAT" | grep -oE '[0-9]+ deletion'  | grep -oE '[0-9]+' | head -1)
		LINES_ADDED=${LINES_ADDED:-0}
		LINES_REMOVED=${LINES_REMOVED:-0}
		COMMITS_MADE=$(git -C "$WORKDIR" rev-list --count "${PRE_HASH}..HEAD" 2>/dev/null || echo 0)
	fi
else
	LINES_ADDED=-1
	LINES_REMOVED=-1
fi

# Detect silent failure: agent ran to completion but wrote nothing
if [[ $EXIT -eq 0 && $LINES_ADDED -eq 0 && -n "$PRE_HASH" ]]; then
	echo "delegate.sh: WARNING — agent '${AGENT}' exited 0 but produced no output (lines_added=0)" >&2
	EXIT=4
fi

# ── Delegation log ────────────────────────────────────────────────────────────
printf '{"ts":"%s","agent":"%s","workdir":"%s","prompt_hash":"%s","exit_code":%d,"duration_s":%d,"lines_added":%d,"lines_removed":%d,"commits":%d}\n' \
	"$TS" "$AGENT" "$WORKDIR" "$PROMPT_HASH" "$EXIT" "$DURATION_S" \
	"$LINES_ADDED" "$LINES_REMOVED" "$COMMITS_MADE" \
	>>~/.agent_delegation.log || true

printf 'exit=%d\nlines_added=%d\nlines_removed=%d\ncommits=%d\n' \
	"$EXIT" "$LINES_ADDED" "$LINES_REMOVED" "$COMMITS_MADE" >> "$SESSION_FILE"

set -e

echo "delegate.sh: ${AGENT} finished — exit=${EXIT} duration=${DURATION_S}s lines_added=${LINES_ADDED} commits=${COMMITS_MADE}" >&2
exit $EXIT
