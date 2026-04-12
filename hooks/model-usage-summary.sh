#!/usr/bin/env bash
# model-usage-summary.sh — Stop hook: record per-message usage from transcript, then report
# SPDX-License-Identifier: Apache-2.0
#
# Fires on every Stop event (each time Claude finishes a response block).
#
# Strategy: Claude Code's Stop hook receives `transcript_path` pointing to the
# session .jsonl, which contains every assistant message with `model` and `usage`
# attached. We parse that file directly — no separate recorder needed.
#
# Steps:
#   1. Read transcript_path from the Stop hook JSON input
#   2. Parse all assistant messages → emit model-usage.ndjson entries
#   3. Run model-report.py → print tier table to stderr + additionalContext
#
# Never blocks — exit 0 in all code paths.

set -euo pipefail
INPUT=$(cat)

# ── Infinite-loop guard ───────────────────────────────────────────────────────
if [[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" == "true" ]]; then
	exit 0
fi

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
LOG_DIR="$CWD/.claude/logs"
USAGE_LOG="$LOG_DIR/model-usage.ndjson"

# ── Resolve Python binary ─────────────────────────────────────────────────────
PYTHON="${MEMPALACE_PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
	if [[ -x "$HOME/.pyenv/shims/python3" ]]; then
		PYTHON="$HOME/.pyenv/shims/python3"
	elif command -v python3 &>/dev/null; then
		PYTHON="python3"
	else
		exit 0
	fi
fi

REPORT_SCRIPT="$HOME/.config/opencode/scripts/model-report.py"
if [[ ! -f "$REPORT_SCRIPT" ]]; then
	exit 0
fi

# ── Read transcript_path from hook input ──────────────────────────────────────
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)

# Expand ~ if present (jq returns literal ~)
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"

# ── Parse transcript → append new model-usage entries ────────────────────────
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
	mkdir -p "$LOG_DIR"

	# Python script: reads session jsonl, finds assistant messages not yet recorded,
	# emits model-usage.ndjson entries. Idempotent — tracks by message uuid.
	"$PYTHON" - "$TRANSCRIPT" "$USAGE_LOG" "$SESSION_ID" <<'PYEOF'
import sys, json, os
from datetime import datetime, timezone

transcript_path = sys.argv[1]
usage_log       = sys.argv[2]
session_id      = sys.argv[3]

# ── Tier mapping — matches model-usage.ts TIER_MAP ───────────────────────────
# Keys are prefix-matched against modelID (case-sensitive).
TIER_MAP: dict[str, tuple[str, float]] = {
    # Local — zero cost
    "devstral":              ("primary",  0.0),
    "llama3.3":              ("primary",  0.0),
    "gemma4":                ("primary",  0.0),
    "qwen2.5-coder":         ("utility",  0.0),
    # Cloud — sign-off tier
    "claude-opus-4":         ("sign-off", 75.0),
    "claude-sonnet-4":       ("sign-off", 15.0),
    "claude-haiku-4":        ("sign-off",  1.25),
    "claude-opus-3":         ("sign-off", 75.0),
    "claude-sonnet-3":       ("sign-off", 15.0),
    "claude-haiku-3":        ("sign-off",  1.25),
    "gpt-4o":                ("sign-off", 15.0),
    "o3":                    ("sign-off", 60.0),
    "gemini-2.5-pro":        ("sign-off", 10.0),
}

def resolve_tier(model_id: str) -> tuple[str, float]:
    for prefix, entry in TIER_MAP.items():
        if model_id.startswith(prefix):
            return entry
    return ("unknown", 0.0)

# ── Load already-recorded message UUIDs ──────────────────────────────────────
recorded: set[str] = set()
if os.path.exists(usage_log):
    with open(usage_log, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
                if e.get("event") == "model-usage" and "msg_uuid" in e:
                    recorded.add(e["msg_uuid"])
            except json.JSONDecodeError:
                pass

# ── Parse transcript ──────────────────────────────────────────────────────────
new_entries: list[str] = []
with open(transcript_path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue

        if d.get("type") != "assistant":
            continue

        msg = d.get("message", {})
        if not isinstance(msg, dict):
            continue
        if "usage" not in msg or "model" not in msg:
            continue

        uuid = d.get("uuid", "")
        if uuid and uuid in recorded:
            continue  # already written

        model_id  = msg.get("model", "unknown")
        usage     = msg.get("usage", {})
        ts        = d.get("timestamp", datetime.now(tz=timezone.utc).isoformat())
        session   = d.get("sessionId", session_id)

        tok_in        = usage.get("input_tokens", 0)
        tok_out       = usage.get("output_tokens", 0)
        cache_read    = usage.get("cache_read_input_tokens", 0)
        cache_write   = usage.get("cache_creation_input_tokens", 0)

        tier, cost_per_1m = resolve_tier(model_id)
        cost_usd = (tok_out / 1_000_000) * cost_per_1m

        entry = {
            "ts":        ts,
            "event":     "model-usage",
            "session":   session,
            "msg_uuid":  uuid,
            "tier":      tier,
            "model":     model_id,
            "provider":  "anthropic",
            "tokens": {
                "input":       tok_in,
                "output":      tok_out,
                "reasoning":   0,
                "cache_read":  cache_read,
                "cache_write": cache_write,
                "total":       tok_in + tok_out,
            },
            "cost_usd": round(cost_usd, 6),
        }
        new_entries.append(json.dumps(entry))
        if uuid:
            recorded.add(uuid)

# ── Append new entries ────────────────────────────────────────────────────────
if new_entries:
    with open(usage_log, "a", encoding="utf-8") as fh:
        fh.write("\n".join(new_entries) + "\n")
    print(f"wrote {len(new_entries)} entries", file=sys.stderr)

PYEOF
fi

# ── Skip report if still no usage data ───────────────────────────────────────
if [[ ! -f "$USAGE_LOG" ]]; then
	exit 0
fi

# ── Portable timeout wrapper ──────────────────────────────────────────────────
_run_with_timeout() {
	local secs="$1"
	shift
	if command -v timeout &>/dev/null; then
		timeout "$secs" "$@"
	elif command -v gtimeout &>/dev/null; then
		gtimeout "$secs" "$@"
	else
		"$@"
	fi
}

# ── Run report ────────────────────────────────────────────────────────────────
set +e
TABLE=$(_run_with_timeout 5 "$PYTHON" "$REPORT_SCRIPT" --cwd "$CWD" --format table today 2>/dev/null)
RC=$?
set -e

if [[ $RC -ne 0 ]] || [[ -z "$TABLE" ]]; then
	exit 0
fi

# ── Print compact summary to stderr ──────────────────────────────────────────
{
	echo ""
	echo "── Model Usage · today ──────────────────────────────────────────────────"
	echo "$TABLE"
	echo "────────────────────────────────────────────────────────────────────────"
} >&2

# ── additionalContext one-liner for model awareness ───────────────────────────
set +e
JSON=$(_run_with_timeout 5 "$PYTHON" "$REPORT_SCRIPT" --cwd "$CWD" --format json today 2>/dev/null)
set -e

if [[ -n "$JSON" ]]; then
	HEALTH=$(printf '%s' "$JSON" | jq -r '.routing_health.message // ""' 2>/dev/null || true)
	COST=$(printf '%s' "$JSON" | jq -r '.totals.cost_usd // 0' 2>/dev/null || true)
	U_CALLS=$(printf '%s' "$JSON" | jq -r '.by_tier.utility["calls"] // 0' 2>/dev/null || true)
	P_CALLS=$(printf '%s' "$JSON" | jq -r '.by_tier.primary["calls"] // 0' 2>/dev/null || true)
	S_CALLS=$(printf '%s' "$JSON" | jq -r '."by_tier"["sign-off"]["calls"] // 0' 2>/dev/null || true)

	ONE_LINER="Model usage today — utility: ${U_CALLS}  primary: ${P_CALLS}  sign-off: ${S_CALLS} | cost: \$${COST} | ${HEALTH}"
	jq -n --arg ctx "$ONE_LINER" '{"additionalContext": $ctx}'
fi

exit 0
