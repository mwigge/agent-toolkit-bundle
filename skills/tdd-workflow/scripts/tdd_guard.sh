#!/usr/bin/env bash
# tdd_guard.sh — Git pre-commit hook: blocks commits when tests are red.
#
# Installation:
#   cp tdd_guard.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Or for all team members via a hook manager:
#   # .pre-commit-config.yaml (pre-commit framework)
#   # OR copy to .githooks/ and set: git config core.hooksPath .githooks
#
# Behaviour:
#   - Detects project type (Python/pytest or Node/Vitest)
#   - Runs tests and fails the commit if tests fail
#   - Checks coverage threshold if configured
#   - Skips if SKIP_TDD_GUARD=1 is set (use sparingly, with reason)

set -uo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

PYTHON_COVERAGE_THRESHOLD="${PYTHON_COVERAGE_THRESHOLD:-95}"
NODE_COVERAGE_THRESHOLD="${NODE_COVERAGE_THRESHOLD:-80}"

# Allow bypass with explicit acknowledgement
if [[ "${SKIP_TDD_GUARD:-0}" == "1" ]]; then
  echo -e "${YELLOW}[tdd-guard] SKIP_TDD_GUARD=1 — skipping test gate.${NC}"
  echo -e "${YELLOW}[tdd-guard] Reason required: ensure you document why in your commit message.${NC}"
  exit 0
fi

echo -e "${BOLD}[tdd-guard] Running pre-commit test gate...${NC}"

FAILED=0

run_python_tests() {
  echo ""
  echo -e "${BOLD}Detected: Python/pytest project${NC}"

  if ! command -v pytest &>/dev/null; then
    echo -e "${RED}ERROR: pytest not found. Is your virtualenv activated?${NC}" >&2
    return 1
  fi

  # Only run tests related to changed files for speed (with fallback to all tests)
  local changed_py
  changed_py=$(git diff --cached --name-only --diff-filter=ACM | grep '\.py$' || true)

  pytest_args=(
    "--tb=short"
    "-q"
    "--cov=src"
    "--cov-report=term-missing:skip-covered"
    "--cov-fail-under=${PYTHON_COVERAGE_THRESHOLD}"
    "--no-header"
  )

  if ! pytest "${pytest_args[@]}"; then
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  COMMIT BLOCKED: Tests are red or coverage low   ║${NC}"
    echo -e "${RED}║  Fix failing tests before committing.             ║${NC}"
    echo -e "${RED}║  Coverage threshold: ${PYTHON_COVERAGE_THRESHOLD}%                          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    return 1
  fi
  return 0
}

run_node_tests() {
  echo ""
  echo -e "${BOLD}Detected: Node.js/Vitest project${NC}"

  if ! command -v pnpm &>/dev/null && ! command -v npx &>/dev/null; then
    echo -e "${RED}ERROR: Neither pnpm nor npx found.${NC}" >&2
    return 1
  fi

  local test_cmd
  if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
    test_cmd="pnpm test"
  else
    test_cmd="npx vitest run --coverage --coverage.thresholds.lines=${NODE_COVERAGE_THRESHOLD}"
  fi

  if ! eval "$test_cmd"; then
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  COMMIT BLOCKED: Tests are red or coverage low   ║${NC}"
    echo -e "${RED}║  Fix failing tests before committing.             ║${NC}"
    echo -e "${RED}║  Coverage threshold: ${NODE_COVERAGE_THRESHOLD}%                          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    return 1
  fi
  return 0
}

# Detect project type
if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "pytest.ini" ]]; then
  if ! run_python_tests; then
    FAILED=1
  fi
elif [[ -f "package.json" ]] || [[ -f "vitest.config.ts" ]] || [[ -f "vitest.config.js" ]]; then
  if ! run_node_tests; then
    FAILED=1
  fi
else
  echo -e "${YELLOW}[tdd-guard] Could not detect project type — skipping test gate.${NC}"
  echo -e "${YELLOW}[tdd-guard] Add pyproject.toml or package.json to enable.${NC}"
  exit 0
fi

if [[ $FAILED -eq 0 ]]; then
  echo ""
  echo -e "${GREEN}[tdd-guard] All tests pass. Proceeding with commit.${NC}"
  exit 0
else
  exit 1
fi
