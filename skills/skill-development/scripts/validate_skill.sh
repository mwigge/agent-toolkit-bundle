#!/usr/bin/env bash
# validate_skill.sh — Validate a Claude Code skill directory structure and content.
#
# Usage:
#   bash validate_skill.sh path/to/skill-directory
#
# Checks:
#   1. SKILL.md exists
#   2. Frontmatter has name, description, version
#   3. Directory name matches frontmatter name
#   4. Body word count is between 500 and 3000
#   5. Description contains trigger phrases (quoted strings)
#   6. Resource files referenced in body exist
#
# Exit codes:
#   0 — all checks pass
#   1 — one or more checks failed
#   2 — usage error

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <skill-directory>" >&2
    exit 2
fi

SKILL_DIR="$1"
SKILL_FILE="$SKILL_DIR/SKILL.md"
ERRORS=0
WARNINGS=0

error() {
    echo "[ERROR] $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo "[WARN]  $1"
    WARNINGS=$((WARNINGS + 1))
}

ok() {
    echo "[OK]    $1"
}

# ---------------------------------------------------------------------------
# Check 1: SKILL.md exists
# ---------------------------------------------------------------------------
if [[ ! -f "$SKILL_FILE" ]]; then
    error "SKILL.md not found in $SKILL_DIR"
    echo ""
    echo "$ERRORS error(s), $WARNINGS warning(s)."
    exit 1
fi
ok "SKILL.md exists"

# ---------------------------------------------------------------------------
# Check 2: Frontmatter fields
# ---------------------------------------------------------------------------
FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$SKILL_FILE" | head -20)

if echo "$FRONTMATTER" | grep -q "^name:"; then
    ok "Frontmatter has 'name'"
    FM_NAME=$(echo "$FRONTMATTER" | grep "^name:" | sed 's/name: *//')
else
    error "Frontmatter missing 'name'"
    FM_NAME=""
fi

if echo "$FRONTMATTER" | grep -q "description:"; then
    ok "Frontmatter has 'description'"
else
    error "Frontmatter missing 'description'"
fi

if echo "$FRONTMATTER" | grep -q "version:"; then
    ok "Frontmatter has 'version'"
else
    error "Frontmatter missing 'version'"
fi

# ---------------------------------------------------------------------------
# Check 3: Directory name matches frontmatter name
# ---------------------------------------------------------------------------
DIR_NAME=$(basename "$SKILL_DIR")
if [[ -n "$FM_NAME" && "$FM_NAME" == "$DIR_NAME" ]]; then
    ok "Directory name matches frontmatter name ($DIR_NAME)"
elif [[ -n "$FM_NAME" ]]; then
    error "Directory name '$DIR_NAME' does not match frontmatter name '$FM_NAME'"
fi

# ---------------------------------------------------------------------------
# Check 4: Body word count
# ---------------------------------------------------------------------------
# Extract body (everything after second ---)
BODY=$(sed '1,/^---$/d' "$SKILL_FILE" | sed '1,/^---$/d')
WORD_COUNT=$(echo "$BODY" | wc -w | tr -d ' ')

if [[ "$WORD_COUNT" -lt 500 ]]; then
    warn "Body word count is $WORD_COUNT (target: 1500-3000, minimum: 500)"
elif [[ "$WORD_COUNT" -gt 3000 ]]; then
    warn "Body word count is $WORD_COUNT (exceeds 3000 word maximum)"
else
    ok "Body word count: $WORD_COUNT (within range)"
fi

# ---------------------------------------------------------------------------
# Check 5: Description has trigger phrases
# ---------------------------------------------------------------------------
DESC_BLOCK=$(sed -n '/^description:/,/^[a-z]/p' "$SKILL_FILE" | head -10)
if echo "$DESC_BLOCK" | grep -q '"'; then
    ok "Description contains trigger phrases (quoted strings)"
else
    warn "Description may lack trigger phrases (no quoted strings found)"
fi

# ---------------------------------------------------------------------------
# Check 6: Referenced resource files exist
# ---------------------------------------------------------------------------
# Look for patterns like `refs/something.md`, `scripts/something.sh`, etc.
REFS=$(echo "$BODY" | grep -oE '(refs|scripts|templates|assets)/[A-Za-z0-9_.-]+' | sort -u)
if [[ -n "$REFS" ]]; then
    while IFS= read -r ref; do
        if [[ -f "$SKILL_DIR/$ref" ]]; then
            ok "Referenced resource exists: $ref"
        else
            error "Referenced resource missing: $ref"
        fi
    done <<< "$REFS"
else
    ok "No resource file references found in body (none to check)"
fi

# ---------------------------------------------------------------------------
# Check 7: Imperative style (heuristic)
# ---------------------------------------------------------------------------
# Check if H2/H3 headings start with a verb-like word (heuristic, not perfect)
HEADING_COUNT=$(echo "$BODY" | grep -cE '^#{2,3} ' || true)
if [[ "$HEADING_COUNT" -gt 0 ]]; then
    ok "Found $HEADING_COUNT section headings"
else
    warn "No H2/H3 headings found — consider adding section structure"
fi

# ---------------------------------------------------------------------------
# Check 8: Subdirectory structure
# ---------------------------------------------------------------------------
for subdir in scripts refs templates; do
    if [[ -d "$SKILL_DIR/$subdir" ]]; then
        FILE_COUNT=$(find "$SKILL_DIR/$subdir" -type f | wc -l | tr -d ' ')
        if [[ "$FILE_COUNT" -gt 0 ]]; then
            ok "$subdir/ contains $FILE_COUNT file(s)"
        else
            warn "$subdir/ exists but is empty"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "--- Summary ---"
echo "Skill:    $DIR_NAME"
echo "Words:    $WORD_COUNT"
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"

if [[ "$ERRORS" -gt 0 ]]; then
    echo "RESULT:   FAIL"
    exit 1
else
    if [[ "$WARNINGS" -gt 0 ]]; then
        echo "RESULT:   PASS (with warnings)"
    else
        echo "RESULT:   PASS"
    fi
    exit 0
fi
