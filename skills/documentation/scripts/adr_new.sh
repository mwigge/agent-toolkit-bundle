#!/usr/bin/env bash
# adr_new.sh — Create a new Architecture Decision Record with auto-incremented number.
#
# Usage:
#   ./adr_new.sh "Use PostgreSQL for primary data store"
#   ./adr_new.sh "Adopt OpenTelemetry for observability" --dir custom/adr/path
#
# The ADR is created at: <adr_dir>/ADR-NNN-<slug>.md
#
# Exit codes:
#   0  ADR created successfully
#   1  Error

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
DEFAULT_ADR_DIR="docs/adr"

# ─── Argument parsing ────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"ADR title\" [--dir <adr_directory>]" >&2
  exit 1
fi

TITLE="$1"
shift

ADR_DIR="$DEFAULT_ADR_DIR"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      ADR_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ─── Helpers ─────────────────────────────────────────────────────────────────
slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9 ]//g' \
    | sed 's/  */ /g' \
    | sed 's/^ //;s/ $//' \
    | tr ' ' '-'
}

# ─── Find next ADR number ─────────────────────────────────────────────────────
mkdir -p "$ADR_DIR"

LAST_NUM=0
if ls "$ADR_DIR"/ADR-*.md &>/dev/null 2>&1; then
  LAST_NUM=$(ls "$ADR_DIR"/ADR-*.md 2>/dev/null \
    | grep -oP 'ADR-\K\d+' \
    | sort -n \
    | tail -1 \
    || echo 0)
fi

NEXT_NUM=$(printf "%03d" $(( LAST_NUM + 1 )))
SLUG=$(slugify "$TITLE")
FILENAME="ADR-${NEXT_NUM}-${SLUG}.md"
FILEPATH="${ADR_DIR}/${FILENAME}"
TODAY=$(date +%Y-%m-%d)

if [[ -f "$FILEPATH" ]]; then
  echo "ERROR: file already exists: $FILEPATH" >&2
  exit 1
fi

# ─── Write the ADR ─────────────────────────────────────────────────────────────
cat > "$FILEPATH" << EOF
# ADR-${NEXT_NUM}: ${TITLE}

**Date**: ${TODAY}
**Status**: Proposed

---

## Context

<!-- Describe the situation that forces this decision. Include:
  - What is the problem or opportunity?
  - What constraints exist (technical, organisational, regulatory)?
  - What would happen if no decision were made?
-->

[Describe the context and the forces at play]

---

## Decision

<!-- State the decision clearly and directly. Use present tense: "We will use X."
     Do not use "We have decided to..." — that is narrative, not a decision.
-->

We will [state the decision].

---

## Consequences

### Positive

- [Benefit 1]
- [Benefit 2]

### Negative / Trade-offs

- [Trade-off 1]
- [Trade-off 2]

### Neutral

- [Neutral consequence, e.g. "This requires updating the deployment documentation"]

---

## Alternatives Considered

### Option 1: [Alternative name]

**Description**: [Brief description]

**Reasons rejected**:
- [Reason 1]
- [Reason 2]

### Option 2: [Alternative name]

**Description**: [Brief description]

**Reasons rejected**:
- [Reason 1]
- [Reason 2]

---

## Related

- ADR-NNN: [Related decision, if any]
- [CLS-NNN]: [Jira ticket that drove this decision]
- [Link to RFC or design doc, if applicable]
EOF

echo "Created: $FILEPATH"
echo "ADR number: ${NEXT_NUM}"
echo "Title: ${TITLE}"
echo ""
echo "Next steps:"
echo "  1. Fill in the Context, Decision, Consequences, and Alternatives sections"
echo "  2. Share with the team for review"
echo "  3. Change Status from 'Proposed' to 'Accepted' after agreement"
