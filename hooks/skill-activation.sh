#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# skill-activation.sh — UserPromptSubmit hook.
# Scans the prompt for domain keywords and injects skill activation hints via
# additionalContext so the relevant skill is loaded without the user needing
# to invoke /skill-name manually.
#
# Mapping is driven by .claude/skill-rules.json:
#   [ { "pattern": "<keyword regex>", "skill": "<skill-name>" }, ... ]
#
# Exit 0 always — never blocks a prompt.

set -euo pipefail
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || true)

[[ -z "$PROMPT" ]] && exit 0

RULES_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/skill-rules.json"
[[ ! -f "$RULES_FILE" ]] && exit 0

ACTIVATED=()

# Read each rule: pattern -> skill name
while IFS= read -r line; do
  PATTERN=$(echo "$line" | jq -r '.pattern' 2>/dev/null || true)
  SKILL=$(echo "$line" | jq -r '.skill' 2>/dev/null || true)
  [[ -z "$PATTERN" || -z "$SKILL" ]] && continue

  if echo "$PROMPT" | grep -qiE "$PATTERN" 2>/dev/null; then
    ACTIVATED+=("$SKILL")
  fi
done < <(jq -c '.[]' "$RULES_FILE" 2>/dev/null || true)

# Deduplicate
if [[ ${#ACTIVATED[@]} -gt 0 ]]; then
  mapfile -t UNIQUE < <(printf '%s\n' "${ACTIVATED[@]}" | sort -u)
else
  UNIQUE=()
fi

if [[ ${#UNIQUE[@]} -gt 0 ]]; then
  NAMES=$(printf '%s, ' "${UNIQUE[@]}" | sed 's/, $//')
  MSG="SKILL ACTIVATION: The following skills are relevant to this prompt - load them before responding: ${NAMES}. "
  MSG+="Skills live in \${CLAUDE_PROJECT_DIR}/skills/. Read the SKILL.md for each activated skill."
  jq -n --arg ctx "$MSG" '{"additionalContext": $ctx}'
fi

exit 0
