#!/usr/bin/env bash
# .claude/hooks/pii-guard.sh
# PreToolUse gate — scans tool input for PII patterns (PAN, IBAN, email, national IDs)
# and blocks the call if a match is found. Patterns loaded from pii-patterns.json.
# Exit 2 = block (stderr fed back to Claude). Exit 0 = allow.

set -euo pipefail

INPUT=$(cat || true)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

PATTERNS_FILE="${HOME}/.claude/pii-patterns.json"
ALLOWLIST_FILE="${HOME}/.claude/pii-guard-allowlist.txt"
LOG_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/audit.log"

# Only scan tool types that carry prompt content or commands
case "$TOOL" in
  Bash|Agent) ;;
  *) exit 0 ;;
esac

# Extract scannable text from the tool input
TEXT=""
case "$TOOL" in
  Bash)
    TEXT=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    ;;
  Agent)
    TEXT=$(echo "$INPUT" | jq -r '.tool_input.prompt // .tool_input.description // empty' 2>/dev/null || true)
    ;;
esac

[[ -z "$TEXT" ]] && exit 0
[[ ! -f "$PATTERNS_FILE" ]] && exit 0

# Load allowlist entries (if file exists)
ALLOWLIST=""
if [[ -f "$ALLOWLIST_FILE" ]]; then
  ALLOWLIST=$(grep -v '^#' "$ALLOWLIST_FILE" | grep -v '^$' || true)
fi

# ── Luhn check (for PAN validation) ─────────────────────────────────────────
luhn_valid() {
  local num="$1"
  local sum=0 alt=0 i digit
  num=$(echo "$num" | tr -d ' -')
  for (( i=${#num}-1; i>=0; i-- )); do
    digit="${num:$i:1}"
    if (( alt )); then
      digit=$(( digit * 2 ))
      (( digit > 9 )) && digit=$(( digit - 9 ))
    fi
    sum=$(( sum + digit ))
    alt=$(( 1 - alt ))
  done
  (( sum % 10 == 0 ))
}

# ── Check if match is in the allowlist ───────────────────────────────────────
is_allowlisted() {
  local match="$1"
  if [[ -n "$ALLOWLIST" ]]; then
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      if [[ "$match" == *"$entry"* ]]; then
        return 0
      fi
    done <<< "$ALLOWLIST"
  fi
  return 1
}

# ── Scan each pattern ───────────────────────────────────────────────────────
PATTERN_COUNT=$(echo "$INPUT" | python3 -c "
import json, sys, re

patterns_file = '${PATTERNS_FILE}'
text = '''${TEXT//\'/\'\\\'\'}'''

try:
    patterns = json.load(open(patterns_file))
except Exception:
    sys.exit(0)

for p in patterns:
    name = p['name']
    regex = p['pattern']
    needs_luhn = p.get('luhn', False)
    allowlist = p.get('allowlist', [])
    context_required = p.get('context_required', '')

    # If context_required is set, only scan if the context keyword appears in the text
    if context_required and not re.search(context_required, text, re.IGNORECASE):
        continue

    for m in re.finditer(regex, text):
        match_str = m.group()

        # Skip allowlisted domains for email
        if allowlist:
            skip = False
            for al in allowlist:
                if al.lower() in match_str.lower():
                    skip = True
                    break
            if skip:
                continue

        # Output: pattern_name and a redacted indicator
        print(f'{name}:{match_str[:4]}****')
        sys.exit(0)

# No match
" 2>/dev/null) || true

if [[ -n "$PATTERN_COUNT" ]]; then
  PATTERN_NAME="${PATTERN_COUNT%%:*}"
  REDACTED="${PATTERN_COUNT#*:}"

  # Luhn check for PAN
  if [[ "$PATTERN_NAME" == "PAN" ]]; then
    # Extract the full match to validate Luhn
    FULL_MATCH=$(echo "$TEXT" | python3 -c "
import json, re, sys
patterns = json.load(open('${PATTERNS_FILE}'))
pan_pattern = [p for p in patterns if p['name'] == 'PAN'][0]['pattern']
text = sys.stdin.read()
m = re.search(pan_pattern, text)
if m:
    print(m.group())
" 2>/dev/null) || true

    if [[ -n "$FULL_MATCH" ]] && ! luhn_valid "$FULL_MATCH"; then
      # Failed Luhn — not a real PAN, let it pass
      exit 0
    fi
  fi

  # Check file-level allowlist
  if is_allowlisted "$REDACTED"; then
    exit 0
  fi

  # Log the detection (never log the actual PII)
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$(date -u +%FT%TZ) PII-GUARD BLOCKED pattern=$PATTERN_NAME indicator=$REDACTED tool=$TOOL risk=3" >> "$LOG_FILE"

  echo "BLOCKED: PII detected (${PATTERN_NAME}) — redact the sensitive data and retry. The matched content was NOT logged." >&2
  exit 2
fi

exit 0
