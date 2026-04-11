#!/usr/bin/env bash
# dev_check.sh — Full TypeScript quality gate for pnpm projects.
#
# Usage:
#   ./dev_check.sh
#
# Runs in order:
#   1. pnpm typecheck   — tsc --noEmit
#   2. pnpm lint        — eslint --max-warnings 0
#   3. pnpm test        — vitest run
#   4. pnpm build       — tsup or tsc emit
#
# Exit code: 0 if all pass, 1 if any fail.
# Customize step commands by setting env vars:
#   TYPECHECK_CMD, LINT_CMD, TEST_CMD, BUILD_CMD

set -uo pipefail

TYPECHECK_CMD="${TYPECHECK_CMD:-pnpm typecheck}"
LINT_CMD="${LINT_CMD:-pnpm lint --max-warnings 0}"
TEST_CMD="${TEST_CMD:-pnpm test}"
BUILD_CMD="${BUILD_CMD:-pnpm build}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

FAILED=0
declare -A RESULTS
declare -a STEP_ORDER

run_step() {
  local name="$1"
  local cmd="$2"
  STEP_ORDER+=("$name")
  echo ""
  echo -e "${BOLD}--- ${name} ---${NC}"
  echo "$ ${cmd}"
  if eval "$cmd"; then
    RESULTS["$name"]="${GREEN}PASS${NC}"
  else
    RESULTS["$name"]="${RED}FAIL${NC}"
    FAILED=1
  fi
}

if ! command -v pnpm &>/dev/null; then
  echo -e "${RED}ERROR: pnpm not found. Install via: npm install -g pnpm${NC}" >&2
  exit 1
fi

echo -e "${BOLD}=== TypeScript Developer Quality Gate ===${NC}"
echo "Working directory: $(pwd)"

run_step "typecheck" "$TYPECHECK_CMD"
run_step "lint"      "$LINT_CMD"
run_step "test"      "$TEST_CMD"
run_step "build"     "$BUILD_CMD"

# Summary
echo ""
echo -e "${BOLD}==================================="
echo -e "Summary"
echo -e "===================================${NC}"
for step in "${STEP_ORDER[@]}"; do
  printf "  %-15s %b\n" "$step" "${RESULTS[$step]}"
done
echo -e "${BOLD}===================================${NC}"

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
else
  echo -e "${RED}One or more checks failed. Fix issues before committing.${NC}"
  exit 1
fi
