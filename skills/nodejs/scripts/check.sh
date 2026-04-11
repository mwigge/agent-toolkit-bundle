#!/usr/bin/env bash
# scripts/check.sh — Node.js skill quality gate
# Verifies Node >= 22, runs node:test with coverage on all test files.
# Usage: bash scripts/check.sh [test-root-dir]
#
# Exit codes:
#   0 — all checks passed
#   1 — Node version too old
#   2 — no test files found
#   3 — tests failed

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { printf "${GREEN}[check]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${NC}  %s\n" "$*"; }
error() { printf "${RED}[error]${NC} %s\n" "$*" >&2; }

# ── 1. Node version check ────────────────────────────────────────────────────
info "Checking Node.js version..."

if ! command -v node &>/dev/null; then
  error "node not found in PATH"
  exit 1
fi

NODE_VERSION=$(node --version)
NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v\([0-9]*\).*/\1/')

if [[ "$NODE_MAJOR" -lt 22 ]]; then
  error "Node.js >= 22 required, found $NODE_VERSION"
  error "Install via: nvm install 22 && nvm use 22"
  exit 1
fi

info "Node.js $NODE_VERSION OK (>= 22 required)"

# ── 2. Locate test files ─────────────────────────────────────────────────────
TEST_ROOT="${1:-src}"

if [[ ! -d "$TEST_ROOT" ]]; then
  warn "Test root '$TEST_ROOT' not found — trying current directory"
  TEST_ROOT="."
fi

# Collect .test.js, .test.ts, .spec.js, .spec.ts files
mapfile -t TEST_FILES < <(
  find "$TEST_ROOT" \
    \( -name "*.test.js" -o -name "*.test.ts" -o -name "*.spec.js" -o -name "*.spec.ts" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    | sort
)

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  warn "No test files found in '$TEST_ROOT'"
  warn "Expected patterns: *.test.js | *.test.ts | *.spec.js | *.spec.ts"
  exit 2
fi

info "Found ${#TEST_FILES[@]} test file(s):"
for f in "${TEST_FILES[@]}"; do
  printf "  %s\n" "$f"
done

# ── 3. Detect TypeScript project ─────────────────────────────────────────────
USE_TS=false
if [[ -f "tsconfig.json" ]] && command -v tsx &>/dev/null; then
  USE_TS=true
  info "TypeScript project detected — using tsx as loader"
elif [[ -f "tsconfig.json" ]]; then
  warn "tsconfig.json found but 'tsx' not installed (npm i -D tsx)"
  warn "Falling back to plain node — .ts files may fail"
fi

# ── 4. Run node:test with coverage ───────────────────────────────────────────
info "Running tests with coverage..."
echo "──────────────────────────────────────────────"

NODE_FLAGS=(
  "--experimental-test-coverage"
  "--test-reporter=spec"
)

if [[ "$USE_TS" == "true" ]]; then
  NODE_FLAGS+=("--import=tsx")
fi

# Build file arguments
FILE_ARGS=()
for f in "${TEST_FILES[@]}"; do
  FILE_ARGS+=("--test=$f")
done

# Run tests; capture exit code without triggering set -e
node "${NODE_FLAGS[@]}" "${FILE_ARGS[@]}" && TEST_EXIT=0 || TEST_EXIT=$?

echo "──────────────────────────────────────────────"

if [[ "$TEST_EXIT" -ne 0 ]]; then
  error "Tests failed (exit $TEST_EXIT)"
  exit 3
fi

info "All tests passed."

# ── 5. Optional: ESLint ───────────────────────────────────────────────────────
if [[ -f "eslint.config.js" ]] || [[ -f ".eslintrc.js" ]] || [[ -f ".eslintrc.json" ]]; then
  if command -v npx &>/dev/null; then
    info "Running ESLint..."
    npx eslint "$TEST_ROOT" --max-warnings=0 && \
      info "ESLint: no issues" || \
      warn "ESLint reported warnings/errors (non-blocking — fix before commit)"
  fi
fi

# ── 6. Optional: tsc type check ──────────────────────────────────────────────
if [[ -f "tsconfig.json" ]] && command -v npx &>/dev/null; then
  info "Running tsc type check..."
  npx tsc --noEmit && \
    info "TypeScript: no type errors" || \
    { error "TypeScript type errors found"; exit 3; }
fi

echo ""
info "check.sh complete — all gates passed."
