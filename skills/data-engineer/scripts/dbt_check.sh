#!/usr/bin/env bash
# dbt_check.sh — Run dbt preflight checks for a project.
# Usage: ./dbt_check.sh [project_dir]
#
# Runs: dbt debug, dbt deps, dbt compile, dbt test --select state:modified+
# Requires: dbt CLI installed and profiles.yml configured.
# Exit code: 0 = all checks passed, 1 = one or more checks failed.

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
section() { printf "\n${YELLOW}══════════════════════════════════════════${NC}\n"; \
            printf "${YELLOW}  %s${NC}\n" "$*"; \
            printf "${YELLOW}══════════════════════════════════════════${NC}\n\n"; }

# ── Guard: dbt must be installed ──────────────────────────────────────────────
if ! command -v dbt &>/dev/null; then
  error "dbt is not installed or not in PATH."
  error "Install: pip install dbt-core dbt-snowflake  (or your adapter)"
  error "See: https://docs.getdbt.com/docs/core/installation-overview"
  exit 1
fi

DBT_VERSION=$(dbt --version 2>&1 | head -1)
info "Found: ${DBT_VERSION}"

# ── Project directory ─────────────────────────────────────────────────────────
PROJECT_DIR="${1:-$(pwd)}"
if [[ ! -f "${PROJECT_DIR}/dbt_project.yml" ]]; then
  error "No dbt_project.yml found in: ${PROJECT_DIR}"
  error "Run this script from your dbt project root, or pass the path as argument."
  exit 1
fi
info "Project directory: ${PROJECT_DIR}"

cd "${PROJECT_DIR}"

FAILED_STEPS=()

run_step() {
  local name="$1"
  shift
  section "${name}"
  if "$@"; then
    info "${name} — PASSED"
  else
    error "${name} — FAILED"
    FAILED_STEPS+=("${name}")
  fi
}

# ── Step 1: dbt debug ─────────────────────────────────────────────────────────
run_step "dbt debug" dbt debug

# ── Step 2: dbt deps ──────────────────────────────────────────────────────────
run_step "dbt deps" dbt deps

# ── Step 3: dbt compile ───────────────────────────────────────────────────────
run_step "dbt compile" dbt compile

# ── Step 4: dbt test (state:modified+) ───────────────────────────────────────
# Requires a manifest.json from a previous run in ./target/ or a state path.
section "dbt test --select state:modified+"

STATE_FLAG=""
if [[ -f "target/manifest.json" ]]; then
  STATE_FLAG="--state target"
  info "Using state from: target/manifest.json"
  dbt test --select "state:modified+" ${STATE_FLAG} && \
    info "dbt test — PASSED" || \
    { error "dbt test — FAILED"; FAILED_STEPS+=("dbt test"); }
else
  warn "No target/manifest.json found — running full test suite instead."
  warn "To enable state-aware testing, run 'dbt compile' first to generate a manifest."
  dbt test && \
    info "dbt test — PASSED" || \
    { error "dbt test — FAILED"; FAILED_STEPS+=("dbt test"); }
fi

# ── Summary ───────────────────────────────────────────────────────────────────
section "Summary"

if [[ ${#FAILED_STEPS[@]} -eq 0 ]]; then
  info "All checks PASSED."
  exit 0
else
  error "The following steps FAILED:"
  for step in "${FAILED_STEPS[@]}"; do
    error "  • ${step}"
  done
  exit 1
fi
