#!/usr/bin/env bash
# queue_delegate.sh — task-queue handoff for local devstral agents
#
# Unlike delegate.sh (one blocking call), this script:
#   1. Writes the task to a spec file in a work queue directory
#   2. Polls for completion by watching git commits in the workdir
#   3. Splits the task into sub-units if the first attempt stalls
#   4. Reports per-unit progress so the orchestrator can assemble the result
#
# Usage:
#   queue_delegate.sh --agent <name> --dir <workdir> --spec-file <path>
#   queue_delegate.sh --agent coder-go --dir /repo --spec-file /tmp/task.md
#
# Flags:
#   --agent       Agent name (required)
#   --dir         Working directory (default: $PWD)
#   --spec-file   Markdown spec file describing the full task (required)
#   --attempts    Max delegate.sh attempts before giving up (default: 3)
#   --timeout     Per-attempt timeout in seconds (default: 600)
#   --stall-limit Seconds without commit before splitting (default: 240)
#
# Exit codes:
#   0  — at least one commit produced; task likely complete
#   1  — bad arguments
#   5  — all attempts exhausted with zero output

set -euo pipefail

AGENT=""
WORKDIR="$PWD"
SPEC_FILE=""
ATTEMPTS=3
TIMEOUT=700
STALL_LIMIT=450

while [[ $# -gt 0 ]]; do
	case "$1" in
	--agent)      AGENT="$2";       shift 2 ;;
	--dir)        WORKDIR="$2";     shift 2 ;;
	--spec-file)  SPEC_FILE="$2";   shift 2 ;;
	--attempts)   ATTEMPTS="$2";    shift 2 ;;
	--timeout)    TIMEOUT="$2";     shift 2 ;;
	--stall-limit) STALL_LIMIT="$2"; shift 2 ;;
	*) echo "queue_delegate.sh: unknown argument: $1" >&2; exit 1 ;;
	esac
done

if [[ -z "$AGENT" || -z "$SPEC_FILE" ]]; then
	echo "queue_delegate.sh: --agent and --spec-file are required" >&2; exit 1
fi
if [[ ! -f "$SPEC_FILE" ]]; then
	echo "queue_delegate.sh: spec file '$SPEC_FILE' not found" >&2; exit 1
fi

DELEGATE="$(dirname "$0")/delegate.sh"
if [[ ! -f "$DELEGATE" ]]; then
	echo "queue_delegate.sh: delegate.sh not found at $DELEGATE" >&2; exit 1
fi

QUEUE_DIR="$HOME/.agent_queue"
mkdir -p "$QUEUE_DIR"

TASK_ID="qdel-$(date +%s)-$$"
TASK_LOG="${QUEUE_DIR}/${TASK_ID}.log"
TOTAL_COMMITS=0
ATTEMPT=0

echo "queue_delegate.sh: starting task ${TASK_ID} — ${ATTEMPTS} max attempts, ${TIMEOUT}s each" >&2

while [[ $ATTEMPT -lt $ATTEMPTS ]]; do
	ATTEMPT=$(( ATTEMPT + 1 ))
	echo "queue_delegate.sh: attempt ${ATTEMPT}/${ATTEMPTS}" >&2

	PRE_HASH=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "")

	EXIT=0
	bash "$DELEGATE" \
		--agent "$AGENT" \
		--dir "$WORKDIR" \
		--spec-file "$SPEC_FILE" \
		--timeout "$TIMEOUT" \
		--stall-limit "$STALL_LIMIT" \
		2>>"$TASK_LOG" || EXIT=$?

	POST_HASH=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "")
	COMMITS_THIS_RUN=0
	if [[ -n "$PRE_HASH" && "$POST_HASH" != "$PRE_HASH" ]]; then
		COMMITS_THIS_RUN=$(git -C "$WORKDIR" rev-list --count "${PRE_HASH}..HEAD" 2>/dev/null || echo 0)
	fi
	TOTAL_COMMITS=$(( TOTAL_COMMITS + COMMITS_THIS_RUN ))

	printf '{"attempt":%d,"exit":%d,"commits":%d,"total_commits":%d}\n' \
		"$ATTEMPT" "$EXIT" "$COMMITS_THIS_RUN" "$TOTAL_COMMITS" >> "$TASK_LOG"

	echo "queue_delegate.sh: attempt ${ATTEMPT} done — exit=${EXIT} commits_this_run=${COMMITS_THIS_RUN} total=${TOTAL_COMMITS}" >&2

	# If we got output, task is progressing — stop here
	if [[ $COMMITS_THIS_RUN -gt 0 ]]; then
		echo "queue_delegate.sh: task produced output on attempt ${ATTEMPT} — done" >&2
		echo "queue_delegate.sh: log: ${TASK_LOG}" >&2
		exit 0
	fi

	# Stalled or silent — if we have more attempts, add a nudge to the spec
	if [[ $ATTEMPT -lt $ATTEMPTS ]]; then
		RETRY_SPEC=$(mktemp "${QUEUE_DIR}/${TASK_ID}_retry${ATTEMPT}_XXXXXX.md")
		cat > "$RETRY_SPEC" << SPEC
# Retry ${ATTEMPT} — previous attempt produced no commits

The previous attempt timed out or stalled without writing any files.
**Start immediately with the simplest possible unit of work from the spec below.**
Do not plan. Do not delegate. Open a file and write code NOW.

$(cat "$SPEC_FILE")
SPEC
		SPEC_FILE="$RETRY_SPEC"
		echo "queue_delegate.sh: injected retry nudge for attempt $(( ATTEMPT + 1 ))" >&2
	fi
done

echo "queue_delegate.sh: all ${ATTEMPTS} attempts exhausted — total commits: ${TOTAL_COMMITS}" >&2
echo "queue_delegate.sh: log: ${TASK_LOG}" >&2

if [[ $TOTAL_COMMITS -eq 0 ]]; then
	exit 5
fi
exit 0
