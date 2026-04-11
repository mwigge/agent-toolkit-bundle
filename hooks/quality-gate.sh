#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# quality-gate.sh — Stop hook.
# Runs after the agent declares it is done.
# Blocks completion if quality checks fail.
# IMPORTANT: checks stop_hook_active to prevent infinite loops.

set -euo pipefail
INPUT=$(cat)

# --- Infinite-loop guard -----------------------------------------------------
if [[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false')" == "true" ]]; then
  exit 0
fi

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
FAILURES=()
CHANGED=""

# --- Detect what changed -----------------------------------------------------
HAS_PYTHON=false
HAS_TYPESCRIPT=false
HAS_FRONTEND=false

if command -v git &>/dev/null && git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
  CHANGED=$(git -C "$CWD" diff --name-only HEAD 2>/dev/null || true)
  echo "$CHANGED" | grep -q '\.py$' && HAS_PYTHON=true || true
  echo "$CHANGED" | grep -qE '\.(ts|tsx)$' && HAS_TYPESCRIPT=true || true
  echo "$CHANGED" | grep -qE '\.(ts|tsx|vue|astro)$' && HAS_FRONTEND=true || true
fi

# --- Python quality gates ----------------------------------------------------
if [[ "$HAS_PYTHON" == "true" ]]; then
  # 1. no print() in library code
  PY_DIRS=$(find "$CWD" -maxdepth 3 -name "*.py" -not -path "*/tests/*" -not -path "*/.venv/*" -not -path "*/test_*" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
  if [[ -n "$PY_DIRS" ]]; then
    if grep -rn --include="*.py" "^\s*print(" "$CWD" --exclude-dir=.venv --exclude-dir=tests 2>/dev/null | grep -v "#" | grep -q .; then
      FAILURES+=("Python: print() found in library code - use structured logging")
    fi
  fi

  # 2. no bare except
  if grep -rn --include="*.py" "except:" "$CWD" --exclude-dir=.venv 2>/dev/null | grep -q .; then
    FAILURES+=("Python: bare except: found - catch specific exceptions")
  fi

  # 3. no deprecated typing imports
  if grep -rn --include="*.py" "from typing import.*\b\(Dict\|List\|Tuple\|Set\|Optional\)\b" "$CWD" --exclude-dir=.venv 2>/dev/null | grep -q .; then
    FAILURES+=("Python: deprecated typing.Dict/List/etc found - use dict/list/X | None (Python 3.10+)")
  fi
fi

# --- TypeScript quality gates ------------------------------------------------
if [[ "$HAS_TYPESCRIPT" == "true" ]]; then
  # 1. no console.log in src/
  if find "$CWD/src" \( -name "*.ts" -o -name "*.tsx" \) -print0 2>/dev/null | xargs -0 grep -l "console\." 2>/dev/null | grep -q .; then
    FAILURES+=("TypeScript: console.log/error found in src/ - use structured logger")
  fi

  # 2. tsc type check (if tsconfig present and tsc available)
  if command -v npx &>/dev/null && [[ -f "$CWD/tsconfig.json" ]]; then
    if ! npx --no-install tsc --noEmit 2>/dev/null; then
      FAILURES+=("TypeScript: tsc --noEmit failed - fix type errors")
    fi
  fi
fi

# --- ESLint quality gate (TS / Vue / Astro) ----------------------------------
# Runs only if the repo has an eslint config and the eslint binary is locally
# available. Errors block; warnings do not. Skips cleanly when ESLint is not
# configured for the repo so it does not break Python-only or non-frontend repos.
if [[ "$HAS_FRONTEND" == "true" ]] && command -v npx &>/dev/null; then
  if [[ -f "$CWD/eslint.config.js" || -f "$CWD/eslint.config.mjs" || -f "$CWD/eslint.config.ts" || -f "$CWD/.eslintrc" || -f "$CWD/.eslintrc.json" || -f "$CWD/.eslintrc.js" || -f "$CWD/.eslintrc.cjs" ]]; then
    if [[ -x "$CWD/node_modules/.bin/eslint" ]]; then
      # Lint the changed files only - fast and focused.
      CHANGED_FE=$(echo "$CHANGED" | grep -E '\.(ts|tsx|vue|astro)$' || true)
      if [[ -n "$CHANGED_FE" ]]; then
        # shellcheck disable=SC2086
        if ! (cd "$CWD" && echo "$CHANGED_FE" | tr '\n' '\0' | xargs -0 npx --no-install eslint --max-warnings=0 2>/dev/null); then
          # Re-run without --max-warnings to distinguish errors from warnings;
          # only fail on errors (exit code 1 from eslint = errors present).
          if ! (cd "$CWD" && echo "$CHANGED_FE" | tr '\n' '\0' | xargs -0 npx --no-install eslint 2>/dev/null); then
            FAILURES+=("ESLint: errors found on changed files - run 'npm run lint' to see details")
          fi
        fi
      fi
    fi
  fi
fi

# --- Fail and report ---------------------------------------------------------
if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo "Quality gate failed - fix before finishing:" >&2
  for f in "${FAILURES[@]}"; do
    echo "  - $f" >&2
  done
  exit 2
fi

exit 0
