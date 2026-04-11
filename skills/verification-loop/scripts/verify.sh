#!/usr/bin/env bash
# verify.sh — Full pre-MR verification script.
#
# Usage:
#   ./verify.sh [--python | --node | --auto]   (default: --auto, detects project type)
#
# Runs:
#   1. Lint (ruff or eslint)
#   2. Type check (mypy or tsc)
#   3. Tests with coverage (pytest or vitest)
#   4. Security scan (bandit or npm audit)
#   5. Conventional commit format check (last commit)
#
# Exit code: 0 if all pass, 1 if any fail.
# Prints a PASS/FAIL summary table at the end.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

FAILED=0
declare -A RESULTS
declare -a STEP_ORDER

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass_step() { RESULTS["$1"]="${GREEN}PASS${NC}"; }
fail_step() { RESULTS["$1"]="${RED}FAIL${NC}"; FAILED=1; }
skip_step() { RESULTS["$1"]="${YELLOW}SKIP${NC}"; }

run_step() {
  local name="$1"
  shift
  STEP_ORDER+=("$name")
  echo ""
  echo -e "${BOLD}--- ${name} ---${NC}"
  if "$@" 2>&1; then
    pass_step "$name"
  else
    fail_step "$name"
  fi
}

require() {
  command -v "$1" &>/dev/null
}

# ---------------------------------------------------------------------------
# Detect project type
# ---------------------------------------------------------------------------

detect_project() {
  if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
    echo "python"
  elif [[ -f "package.json" ]]; then
    echo "node"
  else
    echo "unknown"
  fi
}

PROJECT_TYPE="${1:---auto}"
if [[ "$PROJECT_TYPE" == "--auto" ]]; then
  PROJECT_TYPE=$(detect_project)
fi
PROJECT_TYPE="${PROJECT_TYPE#--}"

echo -e "${BOLD}=== Pre-MR Verification ===${NC}"
echo "Project type: $PROJECT_TYPE"
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
echo "Last commit: $(git log -1 --format='%h %s' 2>/dev/null || echo 'unknown')"

# ---------------------------------------------------------------------------
# Python checks
# ---------------------------------------------------------------------------

if [[ "$PROJECT_TYPE" == "python" ]]; then
  # Lint
  STEP_ORDER+=("lint:ruff")
  if require ruff; then
    echo ""
    echo -e "${BOLD}--- lint:ruff ---${NC}"
    if ruff check src/ --output-format=full; then pass_step "lint:ruff"; else fail_step "lint:ruff"; fi
  else
    skip_step "lint:ruff"
  fi

  # Typecheck
  STEP_ORDER+=("typecheck:mypy")
  if require mypy; then
    echo ""
    echo -e "${BOLD}--- typecheck:mypy ---${NC}"
    if mypy --strict src/; then pass_step "typecheck:mypy"; else fail_step "typecheck:mypy"; fi
  else
    skip_step "typecheck:mypy"
  fi

  # Tests
  STEP_ORDER+=("tests:pytest")
  if require pytest; then
    echo ""
    echo -e "${BOLD}--- tests:pytest ---${NC}"
    if pytest tests/ --cov=src --cov-fail-under=95 --cov-report=term-missing -q; then
      pass_step "tests:pytest"
    else
      fail_step "tests:pytest"
    fi
  else
    skip_step "tests:pytest"
  fi

  # Security
  STEP_ORDER+=("security:bandit")
  if require bandit; then
    echo ""
    echo -e "${BOLD}--- security:bandit ---${NC}"
    if bandit -r src/ --severity-level medium --confidence-level medium -q; then
      pass_step "security:bandit"
    else
      fail_step "security:bandit"
    fi
  else
    skip_step "security:bandit"
  fi

  STEP_ORDER+=("security:pip-audit")
  if require pip-audit; then
    echo ""
    echo -e "${BOLD}--- security:pip-audit ---${NC}"
    if pip-audit --strict; then pass_step "security:pip-audit"; else fail_step "security:pip-audit"; fi
  else
    skip_step "security:pip-audit"
  fi

# ---------------------------------------------------------------------------
# Node checks
# ---------------------------------------------------------------------------

elif [[ "$PROJECT_TYPE" == "node" ]]; then
  # Lint
  STEP_ORDER+=("lint:eslint")
  echo ""
  echo -e "${BOLD}--- lint:eslint ---${NC}"
  if npx eslint src/ --max-warnings 0; then pass_step "lint:eslint"; else fail_step "lint:eslint"; fi

  # Typecheck
  STEP_ORDER+=("typecheck:tsc")
  echo ""
  echo -e "${BOLD}--- typecheck:tsc ---${NC}"
  if npx tsc --noEmit; then pass_step "typecheck:tsc"; else fail_step "typecheck:tsc"; fi

  # Tests
  STEP_ORDER+=("tests:vitest")
  echo ""
  echo -e "${BOLD}--- tests:vitest ---${NC}"
  if npx vitest run --coverage --coverage.thresholds.lines=80; then
    pass_step "tests:vitest"
  else
    fail_step "tests:vitest"
  fi

  # Security
  STEP_ORDER+=("security:npm-audit")
  echo ""
  echo -e "${BOLD}--- security:npm-audit ---${NC}"
  if npm audit --audit-level=high; then
    pass_step "security:npm-audit"
  else
    fail_step "security:npm-audit"
  fi

else
  echo -e "${YELLOW}Unknown project type — skipping language-specific checks${NC}"
fi

# ---------------------------------------------------------------------------
# Conventional commit check (language-agnostic)
# ---------------------------------------------------------------------------

STEP_ORDER+=("commit:conventional")
echo ""
echo -e "${BOLD}--- commit:conventional ---${NC}"
LAST_COMMIT_MSG=$(git log -1 --format="%s" 2>/dev/null || echo "")
CONVENTIONAL_REGEX='^(feat|fix|refactor|test|docs|chore|style|perf|ci|build|revert)(\(.+\))?!?: .{1,72}'

if echo "$LAST_COMMIT_MSG" | grep -qE "$CONVENTIONAL_REGEX"; then
  echo "Commit message: OK"
  echo "  $LAST_COMMIT_MSG"
  pass_step "commit:conventional"
else
  echo -e "${RED}Non-conventional commit message:${NC}"
  echo "  $LAST_COMMIT_MSG"
  echo ""
  echo "Expected format: <type>(<scope>): <description>"
  echo "Valid types: feat fix refactor test docs chore style perf ci build revert"
  fail_step "commit:conventional"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}============================================"
echo -e "Pre-MR Verification Summary"
echo -e "============================================${NC}"
for step in "${STEP_ORDER[@]}"; do
  if [[ -v "RESULTS[$step]" ]]; then
    printf "  %-30s %b\n" "$step" "${RESULTS[$step]}"
  fi
done
echo -e "${BOLD}============================================${NC}"

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}All checks passed. Ready for MR.${NC}"
  exit 0
else
  echo -e "${RED}One or more checks failed. Fix before raising MR.${NC}"
  exit 1
fi
