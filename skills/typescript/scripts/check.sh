#!/usr/bin/env bash
# check.sh — TypeScript type check and lint gate.
#
# Usage:
#   ./check.sh
#
# Runs:
#   1. tsc --noEmit — full type check, no output files
#   2. eslint with --max-warnings 0 — zero-tolerance lint
#
# Exit code: 0 if all pass, 1 if any fail.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

FAILED=0
declare -A RESULTS

run_step() {
  local name="$1"
  shift
  echo ""
  echo -e "${BOLD}--- ${name} ---${NC}"
  if "$@"; then
    RESULTS["$name"]="${GREEN}PASS${NC}"
  else
    RESULTS["$name"]="${RED}FAIL${NC}"
    FAILED=1
  fi
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" &>/dev/null; then
    # Try npx fallback
    if ! npx --no-install "$tool" --version &>/dev/null 2>&1; then
      echo -e "${RED}ERROR: '$tool' not found and not available via npx${NC}" >&2
      return 1
    fi
  fi
  return 0
}

echo -e "${BOLD}=== TypeScript Quality Gate ===${NC}"

# 1. tsc --noEmit
echo ""
echo -e "${BOLD}--- tsc --noEmit ---${NC}"
if npx tsc --noEmit; then
  RESULTS["tsc --noEmit"]="${GREEN}PASS${NC}"
else
  RESULTS["tsc --noEmit"]="${RED}FAIL${NC}"
  FAILED=1
fi

# 2. ESLint with zero warnings
echo ""
echo -e "${BOLD}--- eslint --max-warnings 0 ---${NC}"
ESLINT_ARGS=("--max-warnings" "0")

# Detect source directories
if [[ -d "src" ]]; then
  ESLINT_ARGS+=("src")
elif [[ -d "lib" ]]; then
  ESLINT_ARGS+=("lib")
else
  ESLINT_ARGS+=(".")
fi

if npx eslint "${ESLINT_ARGS[@]}"; then
  RESULTS["eslint"]="${GREEN}PASS${NC}"
else
  RESULTS["eslint"]="${RED}FAIL${NC}"
  FAILED=1
fi

# Summary
echo ""
echo -e "${BOLD}==================================="
echo -e "Summary"
echo -e "===================================${NC}"
for step in "tsc --noEmit" "eslint"; do
  if [[ -v "RESULTS[$step]" ]]; then
    printf "  %-25s %b\n" "$step" "${RESULTS[$step]}"
  fi
done
echo -e "${BOLD}===================================${NC}"

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
else
  echo -e "${RED}One or more checks failed.${NC}"
  exit 1
fi
