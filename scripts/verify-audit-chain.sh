#!/usr/bin/env bash
# verify-audit-chain.sh — verify the SHA-256 hash chain in events.ndjson
#
# Usage: bash verify-audit-chain.sh [path/to/events.ndjson]
# Default: .claude/logs/events.ndjson
#
# Exit 0 if chain is valid, exit 1 if tampered or broken.

set -euo pipefail

EVENTS_FILE="${1:-.claude/logs/events.ndjson}"

if [[ ! -f "$EVENTS_FILE" ]]; then
  echo "File not found: $EVENTS_FILE" >&2
  exit 1
fi

TOTAL=0
VALID=0
BROKEN=0
EXPECTED_PREV="genesis"

while IFS= read -r line; do
  TOTAL=$((TOTAL + 1))

  STORED_HASH=$(echo "$line" | jq -r '._hash // ""' 2>/dev/null)
  STORED_PREV=$(echo "$line" | jq -r '._prev_hash // ""' 2>/dev/null)

  # Skip entries without hash fields (pre-chain entries)
  if [[ -z "$STORED_HASH" || -z "$STORED_PREV" ]]; then
    EXPECTED_PREV="genesis"
    VALID=$((VALID + 1))
    continue
  fi

  # Check prev_hash matches expected
  if [[ "$STORED_PREV" != "$EXPECTED_PREV" ]]; then
    echo "CHAIN BREAK at line $TOTAL: expected _prev_hash=$EXPECTED_PREV, got $STORED_PREV" >&2
    BROKEN=$((BROKEN + 1))
  fi

  # Recompute hash: remove _hash field, hash the rest
  BODY=$(echo "$line" | jq -c 'del(._hash)' 2>/dev/null)
  COMPUTED_HASH=$(printf '%s' "$BODY" | shasum -a 256 | cut -d' ' -f1)

  if [[ "$COMPUTED_HASH" != "$STORED_HASH" ]]; then
    echo "HASH MISMATCH at line $TOTAL: computed=$COMPUTED_HASH, stored=$STORED_HASH" >&2
    BROKEN=$((BROKEN + 1))
  else
    VALID=$((VALID + 1))
  fi

  EXPECTED_PREV="$STORED_HASH"

done < "$EVENTS_FILE"

echo "Verified $TOTAL entries: $VALID valid, $BROKEN broken"

if [[ "$BROKEN" -gt 0 ]]; then
  echo "AUDIT CHAIN TAMPERED — $BROKEN entries failed verification" >&2
  exit 1
fi

echo "Audit chain is intact."
exit 0
