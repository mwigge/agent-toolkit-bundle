#!/usr/bin/env bash
# tdd_check.sh — Run Vitest with coverage and enforce 80% line threshold.
#
# Usage:
#   ./tdd_check.sh [--watch]
#
# Environment:
#   COVERAGE_THRESHOLD  — override default 80 (e.g. COVERAGE_THRESHOLD=90)
#
# Exit code: 0 if tests pass and coverage >= threshold, 1 otherwise.

set -uo pipefail

COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"
WATCH_MODE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

for arg in "$@"; do
  case "$arg" in
    --watch) WATCH_MODE=true ;;
    *) echo -e "${YELLOW}Unknown argument: $arg${NC}" ;;
  esac
done

echo -e "${BOLD}=== Vitest Coverage Check (threshold: ${COVERAGE_THRESHOLD}%) ===${NC}"

if ! command -v npx &>/dev/null; then
  echo -e "${RED}ERROR: npx not found — install Node.js${NC}" >&2
  exit 1
fi

# Check vitest is available
if ! npx vitest --version &>/dev/null 2>&1; then
  echo -e "${RED}ERROR: vitest not found — run: pnpm add -D vitest @vitest/coverage-v8${NC}" >&2
  exit 1
fi

if [[ "$WATCH_MODE" == true ]]; then
  echo "Starting in watch mode (no coverage threshold in watch mode)..."
  exec npx vitest
fi

echo ""
VITEST_ARGS=(
  "run"
  "--coverage"
  "--coverage.provider=v8"
  "--coverage.reporter=text"
  "--coverage.reporter=lcov"
  "--coverage.thresholds.lines=${COVERAGE_THRESHOLD}"
  "--coverage.thresholds.functions=${COVERAGE_THRESHOLD}"
  "--coverage.thresholds.branches=${COVERAGE_THRESHOLD}"
  "--coverage.thresholds.statements=${COVERAGE_THRESHOLD}"
  "--reporter=verbose"
)

if npx vitest "${VITEST_ARGS[@]}"; then
  echo ""
  echo -e "${GREEN}Tests passed with coverage >= ${COVERAGE_THRESHOLD}%.${NC}"
  echo "Coverage report: coverage/lcov-report/index.html"
  exit 0
else
  echo ""
  echo -e "${RED}Tests failed or coverage below ${COVERAGE_THRESHOLD}%.${NC}"
  exit 1
fi
