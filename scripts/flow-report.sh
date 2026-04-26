#!/usr/bin/env bash
# flow-report.sh — render tier-split summary from delegation log and task-queue DB
#
# Usage:
#   flow-report.sh          # human-readable table
#   flow-report.sh --json   # machine-readable JSON
#
# Dependencies: bash, jq, sqlite3 (all standard on macOS + Xcode CLT + brew install jq)

set -euo pipefail

JSON_MODE=0
if [[ "${1:-}" == "--json" ]]; then
	JSON_MODE=1
fi

LOG_FILE="${HOME}/.agent_delegation.log"
DB_FILE="${HOME}/.agent_task_queue.db"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Task queue stats ──────────────────────────────────────────────────────────
TQ_TOTAL=0
TQ_PENDING=0
TQ_CLAIMED=0
TQ_IN_PROGRESS=0
TQ_DONE=0
TQ_FAILED=0

if [[ -f "$DB_FILE" ]]; then
	_tq() { sqlite3 "$DB_FILE" "$1" 2>/dev/null || echo "0"; }
	TQ_TOTAL=$(_tq "SELECT COUNT(*) FROM tasks;")
	TQ_PENDING=$(_tq "SELECT COUNT(*) FROM tasks WHERE status='pending';")
	TQ_CLAIMED=$(_tq "SELECT COUNT(*) FROM tasks WHERE status='claimed';")
	TQ_IN_PROGRESS=$(_tq "SELECT COUNT(*) FROM tasks WHERE status='in_progress';")
	TQ_DONE=$(_tq "SELECT COUNT(*) FROM tasks WHERE status='done';")
	TQ_FAILED=$(_tq "SELECT COUNT(*) FROM tasks WHERE status='failed';")
fi

# ── Delegation log stats ──────────────────────────────────────────────────────
DEL_TOTAL=0
DEL_BY_AGENT_JSON="[]"
DEL_RECENT_JSON="[]"
DEL_TOTAL_LINES=0

if [[ -f "$LOG_FILE" ]] && [[ -s "$LOG_FILE" ]]; then
	DEL_TOTAL=$(wc -l <"$LOG_FILE" | tr -d ' ')

	DEL_BY_AGENT_JSON=$(jq -s '
    group_by(.agent) |
    map({
      agent: .[0].agent,
      count: length,
      total_duration_s: (map(.duration_s) | add // 0),
      total_lines_added: (map(.lines_added) | map(select(. >= 0)) | add // 0)
    })
  ' "$LOG_FILE")

	DEL_RECENT_JSON=$(jq -s '
    sort_by(.ts) | reverse | .[0:5] |
    map({ts, agent, exit_code, duration_s})
  ' "$LOG_FILE")

	DEL_TOTAL_LINES=$(jq -s '[.[].lines_added | select(. >= 0)] | add // 0' "$LOG_FILE")
fi

# ── Render ────────────────────────────────────────────────────────────────────
if [[ $JSON_MODE -eq 1 ]]; then
	jq -n \
		--arg gen "$NOW" \
		--argjson tq_total "$TQ_TOTAL" \
		--argjson tq_pending "$TQ_PENDING" \
		--argjson tq_claimed "$TQ_CLAIMED" \
		--argjson tq_in_progress "$TQ_IN_PROGRESS" \
		--argjson tq_done "$TQ_DONE" \
		--argjson tq_failed "$TQ_FAILED" \
		--argjson del_total "$DEL_TOTAL" \
		--argjson del_by_agent "$DEL_BY_AGENT_JSON" \
		--argjson del_recent "$DEL_RECENT_JSON" \
		--argjson del_lines "$DEL_TOTAL_LINES" \
		'{
      generated_at: $gen,
      task_queue: {
        total: $tq_total,
        by_status: {
          pending: $tq_pending,
          claimed: $tq_claimed,
          in_progress: $tq_in_progress,
          done: $tq_done,
          failed: $tq_failed
        }
      },
      delegations: {
        total: $del_total,
        by_agent: $del_by_agent,
        recent: $del_recent
      },
      summary: {
        central_task_posts: $tq_total,
        local_delegations: $del_total,
        local_lines_added: $del_lines
      }
    }'
else
	echo "╔══════════════════════════════════════════════════════════════╗"
	echo "║           TIER SPLIT REPORT — ${NOW}    ║"
	echo "╚══════════════════════════════════════════════════════════════╝"
	echo ""
	echo "── TASK QUEUE (central tier posts) ─────────────────────────────"
	printf "   Total posted   : %d\n" "$TQ_TOTAL"
	printf "   pending        : %d\n" "$TQ_PENDING"
	printf "   claimed        : %d\n" "$TQ_CLAIMED"
	printf "   in_progress    : %d\n" "$TQ_IN_PROGRESS"
	printf "   done           : %d\n" "$TQ_DONE"
	printf "   failed         : %d\n" "$TQ_FAILED"
	echo ""
	echo "── DELEGATIONS (local tier) ─────────────────────────────────────"
	printf "   Total           : %d\n" "$DEL_TOTAL"
	echo ""
	if [[ "$DEL_BY_AGENT_JSON" != "[]" ]]; then
		printf "   %-25s %6s %12s %14s\n" "AGENT" "COUNT" "DURATION(s)" "LINES_ADDED"
		printf "   %-25s %6s %12s %14s\n" "-------------------------" "------" "------------" "--------------"
		echo "$DEL_BY_AGENT_JSON" | jq -r '.[] | "   \(.agent | .[0:25])\t\(.count)\t\(.total_duration_s)\t\(.total_lines_added)"' |
			awk -F'\t' '{ printf "   %-25s %6d %12d %14d\n", $1, $2, $3, $4 }'
	else
		echo "   (no delegations recorded)"
	fi
	echo ""
	echo "   Recent delegations (last 5):"
	if [[ "$DEL_RECENT_JSON" != "[]" ]]; then
		echo "$DEL_RECENT_JSON" | jq -r '.[] | "   \(.ts)  \(.agent)  exit:\(.exit_code)  \(.duration_s)s"'
	else
		echo "   (none)"
	fi
	echo ""
	echo "── SUMMARY ──────────────────────────────────────────────────────"
	printf "   Central tier : %d task posts  |  openspec artifacts: N/A (not tracked yet)\n" "$TQ_TOTAL"
	printf "   Local tier   : %d delegations  |  lines added: %d\n" "$DEL_TOTAL" "$DEL_TOTAL_LINES"
	echo ""
fi
