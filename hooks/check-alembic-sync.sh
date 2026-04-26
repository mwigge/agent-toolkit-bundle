#!/usr/bin/env bash
# Blocks git commits that add SQL migrations without a matching Alembic version.
# Only fires in repos that have an alembic/versions/ directory.
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# Only care about git commit commands
if [[ "$COMMAND" != *"git commit"* ]]; then
  exit 0
fi

# Only enforce in repos that use Alembic
if [[ ! -d "alembic/versions" ]]; then
  exit 0
fi

staged_sql=$(git diff --cached --name-only --diff-filter=A 2>/dev/null | grep '^migrations/.*\.sql$' || true)

if [[ -z "$staged_sql" ]]; then
  exit 0
fi

staged_alembic=$(git diff --cached --name-only --diff-filter=A 2>/dev/null | grep '^alembic/versions/.*\.py$' || true)

if [[ -z "$staged_alembic" ]]; then
  echo "BLOCKED: New SQL migration(s) staged without a matching Alembic version file." >&2
  echo "" >&2
  echo "  Staged SQL files:" >&2
  while IFS= read -r f; do
    echo "    $f" >&2
  done <<< "$staged_sql"
  echo "" >&2
  echo "  Create alembic/versions/XXXX_*.py covering the SQL, then re-stage." >&2
  exit 2
fi
