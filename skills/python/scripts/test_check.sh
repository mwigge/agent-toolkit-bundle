#!/usr/bin/env bash
# test_check.sh — Run pytest with coverage and validate test conventions.
#
# Usage:
#   ./test_check.sh [path_to_tests_dir]  (default: tests/)
#
# Checks:
#   1. pytest with --cov --cov-fail-under=95 --cov-report=term-missing
#   2. All test files follow test_*.py naming convention
#   3. Warns if no conftest.py is found in the test directory
#
# Exit code:
#   0 — all checks passed
#   1 — one or more checks failed

set -euo pipefail

TESTS_DIR="${1:-tests}"
SRC_DIR="${SRC_DIR:-src}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-95}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=0

info()  { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
error() { echo -e "  ${RED}✗${NC} $*"; FAILED=1; }

echo "=== Test Convention Checks ==="

# Check 1: Test directory exists
if [[ ! -d "$TESTS_DIR" ]]; then
  error "Test directory '$TESTS_DIR' not found"
  exit 1
fi

# Check 2: Naming convention — all Python test files must match test_*.py
echo ""
echo "Checking file naming convention (test_*.py)..."
bad_names=()
while IFS= read -r -d '' f; do
  filename=$(basename "$f")
  if [[ "$filename" != test_*.py ]]; then
    bad_names+=("$f")
  fi
done < <(find "$TESTS_DIR" -type f -name "*.py" ! -name "conftest.py" ! -name "__init__.py" -print0)

if [[ ${#bad_names[@]} -eq 0 ]]; then
  info "All test files follow test_*.py convention"
else
  for f in "${bad_names[@]}"; do
    error "Bad test file name: $f (must match test_*.py)"
  done
fi

# Check 3: conftest.py presence
echo ""
echo "Checking for conftest.py..."
if find "$TESTS_DIR" -name "conftest.py" | grep -q .; then
  info "conftest.py found"
else
  warn "No conftest.py found in '$TESTS_DIR' — shared fixtures will not be available"
fi

# Check 4: Run pytest with coverage
echo ""
echo "=== Running pytest with coverage (threshold: ${COVERAGE_THRESHOLD}%) ==="
echo ""

pytest_args=(
  "$TESTS_DIR"
  "--cov=${SRC_DIR}"
  "--cov-report=term-missing"
  "--cov-report=html:htmlcov"
  "--cov-fail-under=${COVERAGE_THRESHOLD}"
  "--tb=short"
  "-q"
)

if pytest "${pytest_args[@]}"; then
  info "pytest passed with coverage >= ${COVERAGE_THRESHOLD}%"
else
  error "pytest failed or coverage below ${COVERAGE_THRESHOLD}%"
fi

# Summary
echo ""
echo "==================================="
if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
else
  echo -e "${RED}One or more checks failed.${NC}"
  exit 1
fi
