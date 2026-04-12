#!/usr/bin/env bash
# model-usage-summary.sh — Stop hook: print tiered model usage after each block
# SPDX-License-Identifier: Apache-2.0
#
# Fires on every Stop event (each time Claude finishes a response block).
# Reads .claude/logs/model-usage.ndjson, runs model-report.py scoped to today,
# and prints a compact tier table to stderr (shown in the Claude Code terminal).
# Also emits a one-liner additionalContext to stdout so the model is aware of
# its current token/cost profile for the session.
#
# Never blocks — exit 0 in all code paths.

set -euo pipefail
INPUT=$(cat)

# ── Infinite-loop guard ───────────────────────────────────────────────────────
if [[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false')" == "true" ]]; then
  exit 0
fi

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
USAGE_LOG="$CWD/.claude/logs/model-usage.ndjson"

# ── Skip silently if no usage data yet ───────────────────────────────────────
if [[ ! -f "$USAGE_LOG" ]]; then
  exit 0
fi

# ── Resolve Python binary ─────────────────────────────────────────────────────
PYTHON="${MEMPALACE_PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
  if [[ -x "$HOME/.pyenv/shims/python3" ]]; then
    PYTHON="$HOME/.pyenv/shims/python3"
  elif command -v python3 &>/dev/null; then
    PYTHON="python3"
  else
    exit 0   # python not found — skip silently
  fi
fi

REPORT_SCRIPT="$HOME/.config/opencode/scripts/model-report.py"
if [[ ! -f "$REPORT_SCRIPT" ]]; then
  exit 0   # script not installed — skip silently
fi

# ── Run report (timeout 4s — must not block the Stop hook chain) ──────────────
set +e
TABLE=$(timeout 4 "$PYTHON" "$REPORT_SCRIPT" --cwd "$CWD" --format table today 2>/dev/null)
RC=$?
set -e

if [[ $RC -ne 0 ]] || [[ -z "$TABLE" ]]; then
  exit 0   # report failed or empty — skip silently
fi

# ── Print compact summary to stderr (shown in Claude Code terminal) ───────────
{
  echo ""
  echo "── Model Usage · this session ──────────────────────────────────────────"
  echo "$TABLE"
  echo "────────────────────────────────────────────────────────────────────────"
} >&2

# ── Extract one-liner for additionalContext (model awareness) ─────────────────
# Parse health status and total cost from JSON for a compact one-liner
set +e
JSON=$(timeout 4 "$PYTHON" "$REPORT_SCRIPT" --cwd "$CWD" --format json today 2>/dev/null)
set -e

if [[ -n "$JSON" ]]; then
  HEALTH=$(echo "$JSON"  | jq -r '.routing_health.message // ""'      2>/dev/null || true)
  COST=$(echo "$JSON"    | jq -r '.totals.cost_usd // 0'              2>/dev/null || true)
  SESSIONS=$(echo "$JSON"| jq -r '.totals.sessions // 0'              2>/dev/null || true)
  U_CALLS=$(echo "$JSON" | jq -r '.by_tier.utility["calls"] // 0'     2>/dev/null || true)
  P_CALLS=$(echo "$JSON" | jq -r '.by_tier.primary["calls"] // 0'     2>/dev/null || true)
  S_CALLS=$(echo "$JSON" | jq -r '."by_tier"["sign-off"]["calls"] // 0' 2>/dev/null || true)

  ONE_LINER="Model usage today — utility: ${U_CALLS} calls  primary: ${P_CALLS} calls  sign-off: ${S_CALLS} calls | cost: \$${COST} | sessions: ${SESSIONS} | ${HEALTH}"
  jq -n --arg ctx "$ONE_LINER" '{"additionalContext": $ctx}'
fi

exit 0
