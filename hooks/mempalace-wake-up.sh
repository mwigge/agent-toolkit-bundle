#!/usr/bin/env bash
# .claude/hooks/mempalace-wake-up.sh
# SessionStart hook — injects MemPalace L0+L1 context at session start.
#
# Strategy: CWD is not a reliable wing signal (user often starts in docs_local/).
# Instead, detect active OpenSpec changes from memory.md + recently modified
# openspec/changes/ dirs, then map change names to domain wings.
#
# Output: additionalContext with L0+L1 wake-up text, or a hint if palace not ready.
# Blocking: yes (10s timeout). Fails gracefully — always exits 0.

set -uo pipefail

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ── Resolve mempalace binary: prefer pyenv 3.12, fall back to PATH ────────────
MEMPALACE_BIN=""
PYENV_BIN="$HOME/.pyenv/versions/3.12.13/bin/mempalace"
if [[ -x "$PYENV_BIN" ]]; then
  MEMPALACE_BIN="$PYENV_BIN"
elif command -v mempalace &>/dev/null; then
  MEMPALACE_BIN="$(command -v mempalace)"
fi

# ── Locate docs_local ─────────────────────────────────────────────────────────
find_docs_local() {
  # 1. Explicit env var
  if [[ -n "${DOCS_LOCAL_PATH:-}" && -d "$DOCS_LOCAL_PATH" ]]; then
    echo "$DOCS_LOCAL_PATH"; return
  fi
  # 2. Walk up from PROJECT looking for openspec/changes/
  local dir="$PROJECT"
  for _ in 1 2 3 4 5; do
    if [[ -d "$dir/openspec/changes" ]]; then
      echo "$dir"; return
    fi
    dir="$(dirname "$dir")"
  done
  # 3. Hardcoded fallback
  if [[ -d "$HOME/dev/src/docs_local" ]]; then
    echo "$HOME/dev/src/docs_local"; return
  fi
  echo ""
}

DOCS_LOCAL="$(find_docs_local)"

# ── Wing keyword map (bash associative array) ─────────────────────────────────
declare -A WING_KEYWORDS=(
  [wing_cls_architecture]="mcp agent sso auth multitenancy org-role idp wl-sso apigee compliance"
  [wing_cls_platform]="early-adopter onboarding feedback admin-role tester-first demo learning gamification slack slo dora"
  [wing_cls_resilience]="resilience maturity score complexity ontology scenario experiment library steadystate recommend incident"
  [wing_cls_infra]="postgres pgbouncer observability pre-production hardening compute metric typed session-metric quality-lake run-probe run-experiment guardrail extension analytics cloud kubernetes artifactory alerting"
)

detect_wing() {
  local change_name="${1,,}"  # lowercase
  for wing in wing_cls_architecture wing_cls_platform wing_cls_resilience wing_cls_infra; do
    local keywords="${WING_KEYWORDS[$wing]}"
    for kw in $keywords; do
      if [[ "$change_name" == *"$kw"* ]]; then
        echo "$wing"; return
      fi
    done
  done
  echo "wing_cls_infra"  # default
}

# ── Collect active change names ───────────────────────────────────────────────
declare -A DETECTED_WINGS=()

# From memory.md branch names: feat/CLS-NNN/change-name -> change-name
if [[ -n "$DOCS_LOCAL" && -f "$DOCS_LOCAL/memory.md" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ feat/CLS-[0-9]+/([a-z0-9_-]+) ]]; then
      change="${BASH_REMATCH[1]}"
      wing="$(detect_wing "$change")"
      DETECTED_WINGS[$wing]=1
    fi
  done < "$DOCS_LOCAL/memory.md"
fi

# From recently modified openspec/changes/ dirs (last 7 days)
if [[ -n "$DOCS_LOCAL" && -d "$DOCS_LOCAL/openspec/changes" ]]; then
  while IFS= read -r change_dir; do
    change="$(basename "$change_dir")"
    [[ "$change" == "archive" ]] && continue
    wing="$(detect_wing "$change")"
    DETECTED_WINGS[$wing]=1
  done < <(find "$DOCS_LOCAL/openspec/changes" -maxdepth 1 -mindepth 1 -type d -newer "$DOCS_LOCAL/openspec/changes" -not -name "archive" 2>/dev/null || true)
fi

# ── Pick primary wing (most detected, with priority ordering) ─────────────────
PRIMARY_WING=""
for preferred in wing_cls_architecture wing_cls_platform wing_cls_resilience wing_cls_infra; do
  if [[ -v DETECTED_WINGS[$preferred] ]]; then
    PRIMARY_WING="$preferred"; break
  fi
done
[[ -z "$PRIMARY_WING" ]] && PRIMARY_WING="wing_ai_dev"

# ── Run mempalace wake-up ─────────────────────────────────────────────────────
WAKE_UP_TEXT=""

if [[ -n "$MEMPALACE_BIN" ]]; then
  if "$MEMPALACE_BIN" status &>/dev/null 2>&1; then
    WAKE_UP_TEXT="$("$MEMPALACE_BIN" wake-up --wing "$PRIMARY_WING" 2>/dev/null || true)"
  fi
fi

# ── Emit additionalContext ────────────────────────────────────────────────────
if [[ -n "$WAKE_UP_TEXT" ]]; then
  MSG="MEMPALACE WAKE-UP [wing: ${PRIMARY_WING}]"$'\n'
  MSG+="$WAKE_UP_TEXT"$'\n'
  MSG+="Use mempalace_search(query=...) or mempalace_list_rooms(wing=...) for deeper recall."
else
  MSG="MEMPALACE: Palace not initialised or empty. "
  MSG+="Run /mine all to populate from existing OpenSpec artifacts. "
  MSG+="See ai_local/skills/mempalace/SKILL.md for installation steps."
fi

# Log to observability
LOG_DIR="${PROJECT}/.claude/logs"
mkdir -p "$LOG_DIR"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"SessionStart\",\"hook\":\"mempalace-wake-up\",\"session_id\":\"$SESSION_ID\",\"wing\":\"$PRIMARY_WING\",\"palace_ready\":$([ -n "$WAKE_UP_TEXT" ] && echo true || echo false)}" \
  >> "$LOG_DIR/events.ndjson" 2>/dev/null || true

jq -n --arg ctx "$MSG" '{"additionalContext": $ctx}'
exit 0
