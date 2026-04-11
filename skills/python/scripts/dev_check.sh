#!/usr/bin/env bash
# dev_check.sh — Full Python quality gate: lint, format, types, security, deps.
#
# Usage:
#   ./dev_check.sh [src_dir]   (default: src/)
#
# Runs in order:
#   1. ruff check  — lint (fast)
#   2. black --check  — format check
#   3. mypy --strict  — type check
#   4. bandit -r  — security scan (HIGH+MEDIUM)
#   5. pip-audit  — CVE audit
#
# Exit code: 0 if all pass, 1 if any fail.
# Each step prints PASS or FAIL independently.

set -uo pipefail

SRC_DIR="${1:-src}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    echo -e "${YELLOW}⚠ '$tool' not found — skipping${NC}"
    RESULTS["$tool"]="${YELLOW}SKIP (not installed)${NC}"
    return 1
  fi
  return 0
}

echo -e "${BOLD}=== Python Quality Gate ===${NC}"
echo "Source directory: $SRC_DIR"

if [[ ! -d "$SRC_DIR" ]]; then
  echo -e "${RED}ERROR: Source directory '$SRC_DIR' not found.${NC}" >&2
  exit 1
fi

# 1. Ruff lint
if require_tool ruff; then
  run_step "ruff check" ruff check "$SRC_DIR" --output-format=full
else
  RESULTS["ruff check"]="${YELLOW}SKIP${NC}"
fi

# 2. Black format check
if require_tool black; then
  run_step "black --check" black --check "$SRC_DIR"
else
  RESULTS["black --check"]="${YELLOW}SKIP${NC}"
fi

# 3. mypy strict type check
if require_tool mypy; then
  run_step "mypy --strict" mypy --strict "$SRC_DIR"
else
  RESULTS["mypy --strict"]="${YELLOW}SKIP${NC}"
fi

# 4. Bandit security scan (HIGH and MEDIUM severity only)
if require_tool bandit; then
  run_step "bandit -r" bandit -r "$SRC_DIR" --severity-level medium --confidence-level medium -q
else
  RESULTS["bandit -r"]="${YELLOW}SKIP${NC}"
fi

# 5. pip-audit CVE scan
if require_tool pip-audit; then
  run_step "pip-audit" pip-audit --strict
else
  RESULTS["pip-audit"]="${YELLOW}SKIP${NC}"
fi

# Summary table
echo ""
echo -e "${BOLD}==================================="
echo -e "Quality Gate Summary"
echo -e "===================================${NC}"
for step in "ruff check" "black --check" "mypy --strict" "bandit -r" "pip-audit"; do
  if [[ -v "RESULTS[$step]" ]]; then
    printf "  %-20s %b\n" "$step" "${RESULTS[$step]}"
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
