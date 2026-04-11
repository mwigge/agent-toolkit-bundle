#!/usr/bin/env bash
# security_scan.sh — Run security scans against a Python or Node.js project.
#
# Usage:
#   ./security_scan.sh [--python | --node | --auto]   (default: --auto)
#
# Runs (Python):
#   1. bandit -r src/ -ll   (HIGH+MEDIUM severity)
#   2. pip-audit
#   3. detect-secrets scan (if installed)
#
# Runs (Node):
#   1. npm audit --audit-level=high
#   2. detect-secrets scan (if installed)
#
# Exit code: 0 if all pass, 1 if any critical/high issues found.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

FAILED=0
declare -A RESULTS
declare -a STEP_ORDER

pass_step() { RESULTS["$1"]="${GREEN}PASS${NC}"; STEP_ORDER+=("$1"); }
fail_step() { RESULTS["$1"]="${RED}FAIL${NC}"; STEP_ORDER+=("$1"); FAILED=1; }
skip_step() { RESULTS["$1"]="${YELLOW}SKIP${NC}"; STEP_ORDER+=("$1"); }
warn_step() { RESULTS["$1"]="${YELLOW}WARN${NC}"; STEP_ORDER+=("$1"); }

run() {
  local name="$1"
  shift
  STEP_ORDER+=("$name")
  echo ""
  echo -e "${BOLD}--- ${name} ---${NC}"
  if "$@"; then
    RESULTS["$name"]="${GREEN}PASS${NC}"
  else
    RESULTS["$name"]="${RED}FAIL${NC}"
    FAILED=1
  fi
}

detect_project() {
  if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
    echo "python"
  elif [[ -f "package.json" ]]; then
    echo "node"
  else
    echo "unknown"
  fi
}

ARG="${1:---auto}"
PROJECT="${ARG#--}"
if [[ "$PROJECT" == "auto" ]]; then
  PROJECT=$(detect_project)
fi

echo -e "${BOLD}=== Security Scan (${PROJECT}) ===${NC}"
echo "Directory: $(pwd)"

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
if [[ "$PROJECT" == "python" ]]; then
  SRC="${SRC_DIR:-src}"

  # bandit
  if command -v bandit &>/dev/null; then
    echo ""
    echo -e "${BOLD}--- bandit ---${NC}"
    # -ll = HIGH and MEDIUM severity; -i = HIGH and MEDIUM confidence
    if bandit -r "${SRC}" --severity-level medium --confidence-level medium -q; then
      pass_step "bandit"
    else
      fail_step "bandit"
    fi
  else
    echo ""
    echo -e "${YELLOW}bandit not found (pip install bandit)${NC}"
    skip_step "bandit"
  fi

  # pip-audit
  if command -v pip-audit &>/dev/null; then
    echo ""
    echo -e "${BOLD}--- pip-audit ---${NC}"
    if pip-audit --strict; then
      pass_step "pip-audit"
    else
      fail_step "pip-audit"
    fi
  else
    echo ""
    echo -e "${YELLOW}pip-audit not found (pip install pip-audit)${NC}"
    skip_step "pip-audit"
  fi

# ---------------------------------------------------------------------------
# Node
# ---------------------------------------------------------------------------
elif [[ "$PROJECT" == "node" ]]; then

  # npm audit
  echo ""
  echo -e "${BOLD}--- npm audit ---${NC}"
  if npm audit --audit-level=high; then
    pass_step "npm audit"
  else
    fail_step "npm audit"
  fi

  # pnpm audit (if pnpm project)
  if [[ -f "pnpm-lock.yaml" ]] && command -v pnpm &>/dev/null; then
    echo ""
    echo -e "${BOLD}--- pnpm audit ---${NC}"
    if pnpm audit --audit-level=high; then
      pass_step "pnpm audit"
    else
      fail_step "pnpm audit"
    fi
  fi

else
  echo -e "${YELLOW}Unknown project type '${PROJECT}' — skipping language checks${NC}"
fi

# ---------------------------------------------------------------------------
# detect-secrets (language-agnostic)
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}--- detect-secrets ---${NC}"
if command -v detect-secrets &>/dev/null; then
  BASELINE=".secrets.baseline"
  if [[ -f "$BASELINE" ]]; then
    if detect-secrets-hook --baseline "$BASELINE" $(git diff --cached --name-only 2>/dev/null || echo "."); then
      pass_step "detect-secrets"
    else
      fail_step "detect-secrets"
      echo -e "${RED}  Potential secrets found! Review the output above before committing.${NC}"
    fi
  else
    echo -e "${YELLOW}  No .secrets.baseline found. Run: detect-secrets scan > .secrets.baseline${NC}"
    # Run a full scan for info
    detect-secrets scan --list-all-plugins 2>/dev/null | head -5 || true
    if detect-secrets scan | python3 -c "import json,sys; d=json.load(sys.stdin); exit(1 if d.get('results') else 0)" 2>/dev/null; then
      pass_step "detect-secrets"
    else
      warn_step "detect-secrets"
      echo -e "${YELLOW}  Potential secrets found (no baseline to compare against). Review and create baseline.${NC}"
    fi
  fi
else
  echo -e "${YELLOW}detect-secrets not found (pip install detect-secrets)${NC}"
  skip_step "detect-secrets"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================"
echo -e "Security Scan Summary"
echo -e "============================================${NC}"
for step in "${STEP_ORDER[@]}"; do
  if [[ -v "RESULTS[$step]" ]]; then
    printf "  %-25s %b\n" "$step" "${RESULTS[$step]}"
  fi
done
echo -e "${BOLD}============================================${NC}"

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}Security scan passed.${NC}"
  exit 0
else
  echo -e "${RED}Security issues found — fix before merging.${NC}"
  exit 1
fi
