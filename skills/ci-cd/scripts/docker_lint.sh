#!/usr/bin/env bash
# docker_lint.sh — Lint all Dockerfiles in the current directory tree.
#
# Uses hadolint if available; falls back to grep-based heuristic checks.
#
# Usage:
#   ./docker_lint.sh [directory]      # default: current directory
#
# Exit codes:
#   0  All Dockerfiles passed all checks
#   1  One or more issues found
#   2  Usage error

set -euo pipefail

TARGET_DIR="${1:-.}"
FAIL=0
FILES_CHECKED=0

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Colour

log_pass()  { printf "${GREEN}PASS${NC}  %s\n" "$1"; }
log_fail()  { printf "${RED}FAIL${NC}  %s\n" "$1"; FAIL=1; }
log_warn()  { printf "${YELLOW}WARN${NC}  %s\n" "$1"; }
log_issue() { printf "       ${RED}•${NC} %s\n" "$1"; }

# ─── Find all Dockerfiles ────────────────────────────────────────────────────
mapfile -t DOCKERFILES < <(find "$TARGET_DIR" -type f \( -name "Dockerfile" -o -name "Dockerfile.*" \) | sort)

if [[ ${#DOCKERFILES[@]} -eq 0 ]]; then
  echo "No Dockerfiles found in: $TARGET_DIR"
  exit 0
fi

echo "Found ${#DOCKERFILES[@]} Dockerfile(s) in $TARGET_DIR"
echo "────────────────────────────────────────────────────"

# ─── hadolint path ──────────────────────────────────────────────────────────
HADOLINT_BIN=""
if command -v hadolint &>/dev/null; then
  HADOLINT_BIN="hadolint"
elif [[ -x "/usr/local/bin/hadolint" ]]; then
  HADOLINT_BIN="/usr/local/bin/hadolint"
elif [[ -x "$HOME/.local/bin/hadolint" ]]; then
  HADOLINT_BIN="$HOME/.local/bin/hadolint"
fi

# ─── hadolint-based linting ──────────────────────────────────────────────────
run_hadolint() {
  local file="$1"
  if hadolint_output=$("$HADOLINT_BIN" --failure-threshold warning "$file" 2>&1); then
    log_pass "$file (hadolint)"
  else
    log_fail "$file (hadolint)"
    while IFS= read -r line; do
      log_issue "$line"
    done <<< "$hadolint_output"
  fi
}

# ─── Grep-based heuristic checks ─────────────────────────────────────────────
run_heuristic_checks() {
  local file="$1"
  local issues=()

  # 1. FROM with :latest tag
  if grep -qP '^FROM\s+\S+:latest' "$file"; then
    issues+=("Uses :latest tag in FROM instruction — pin to a specific version (e.g. python:3.10.14-slim)")
  fi

  # 2. FROM with no tag at all (implicit :latest)
  if grep -qP '^FROM\s+[a-zA-Z0-9/_-]+\s*$' "$file"; then
    issues+=("FROM instruction has no tag — implicit :latest is unpredictable; pin to a specific version")
  fi

  # 3. ADD instead of COPY (ADD has implicit tar-extraction and URL-fetching behaviour)
  if grep -qP '^\s*ADD\s' "$file"; then
    issues+=("Uses ADD instead of COPY — prefer COPY unless you need ADD's tar-extraction or URL-fetching features")
  fi

  # 4. No HEALTHCHECK directive
  if ! grep -qP '^\s*HEALTHCHECK\s' "$file"; then
    issues+=("No HEALTHCHECK directive — container orchestrators cannot detect unhealthy containers without it")
  fi

  # 5. Root user (no USER directive, or USER root)
  if ! grep -qP '^\s*USER\s' "$file"; then
    issues+=("No USER directive — container will run as root; add a non-root user")
  elif grep -qP '^\s*USER\s+root' "$file"; then
    issues+=("USER root found — switch to a non-root user before the final CMD/ENTRYPOINT")
  fi

  # 6. Secrets-like patterns in ENV or ARG
  if grep -qiP '^\s*(ENV|ARG)\s+.*(password|secret|token|api_key|private_key)\s*=' "$file"; then
    issues+=("Possible secret in ENV/ARG directive — use runtime environment variables or Docker build secrets instead")
  fi

  # 7. apt-get without --no-install-recommends
  if grep -qP 'apt-get install' "$file" && ! grep -qP 'apt-get install.*--no-install-recommends' "$file"; then
    issues+=("apt-get install without --no-install-recommends — inflates image size")
  fi

  # 8. pip install without --no-cache-dir
  if grep -qP 'pip install' "$file" && ! grep -qP 'pip install.*--no-cache-dir' "$file"; then
    issues+=("pip install without --no-cache-dir — pip cache adds unnecessary layer size")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    log_pass "$file (heuristic)"
  else
    log_fail "$file (heuristic — ${#issues[@]} issue(s))"
    for issue in "${issues[@]}"; do
      log_issue "$issue"
    done
  fi
}

# ─── Main loop ───────────────────────────────────────────────────────────────
for dockerfile in "${DOCKERFILES[@]}"; do
  ((FILES_CHECKED++))
  if [[ -n "$HADOLINT_BIN" ]]; then
    run_hadolint "$dockerfile"
  else
    run_heuristic_checks "$dockerfile"
  fi
done

echo "────────────────────────────────────────────────────"

if [[ -z "$HADOLINT_BIN" ]]; then
  log_warn "hadolint not found — using grep-based heuristics only"
  log_warn "Install hadolint for comprehensive linting: https://github.com/hadolint/hadolint"
fi

echo "Checked: $FILES_CHECKED file(s)"

if [[ $FAIL -eq 1 ]]; then
  echo -e "${RED}RESULT: FAIL${NC}"
  exit 1
else
  echo -e "${GREEN}RESULT: PASS${NC}"
  exit 0
fi
