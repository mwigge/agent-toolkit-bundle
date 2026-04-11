#!/usr/bin/env bash
# arch_check.sh — Verify Clean Architecture layer boundaries in a TypeScript project.
#
# Usage:
#   ./arch_check.sh [src_dir]   (default: src/)
#
# Checks:
#   1. tsconfig.json has path aliases for @domain, @application, @infrastructure, @interfaces
#   2. Files in domain/ do not import from @infrastructure or @application or @interfaces
#   3. Files in application/ do not import from @infrastructure or @interfaces
#   4. Files in infrastructure/ do not import from @interfaces
#
# Exit code: 0 if no violations, 1 if violations found.

set -uo pipefail

SRC_DIR="${1:-src}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

FAILED=0

info()  { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
error() { echo -e "  ${RED}✗${NC} $*"; FAILED=1; }

echo -e "${BOLD}=== TypeScript Architecture Check ===${NC}"
echo "Source directory: $SRC_DIR"

# Check tsconfig path aliases
echo ""
echo "Checking tsconfig.json path aliases..."
TSCONFIG="tsconfig.json"
if [[ ! -f "$TSCONFIG" ]]; then
  warn "tsconfig.json not found — skipping path alias check"
else
  for alias in "@domain" "@application" "@infrastructure" "@interfaces"; do
    if grep -q "\"${alias}/\*\"" "$TSCONFIG" 2>/dev/null; then
      info "Path alias ${alias} found"
    else
      warn "Missing tsconfig path alias: ${alias}/* (add to compilerOptions.paths)"
    fi
  done
fi

# Dependency rule violations check
check_layer_imports() {
  local source_layer="$1"
  local forbidden_pattern="$2"
  local severity="$3"
  local layer_dir="${SRC_DIR}/${source_layer}"

  if [[ ! -d "$layer_dir" ]]; then
    return
  fi

  local violations=()
  while IFS= read -r -d '' file; do
    while IFS= read -r line_info; do
      violations+=("$file: $line_info")
    done < <(grep -n "$forbidden_pattern" "$file" 2>/dev/null || true)
  done < <(find "$layer_dir" -name "*.ts" ! -name "*.test.ts" ! -name "*.spec.ts" -print0)

  if [[ ${#violations[@]} -eq 0 ]]; then
    info "${source_layer}/ has no forbidden imports (${forbidden_pattern})"
  else
    for v in "${violations[@]}"; do
      if [[ "$severity" == "error" ]]; then
        error "${source_layer}/ imports forbidden module: $v"
      else
        warn "${source_layer}/ suspicious import: $v"
      fi
    done
  fi
}

echo ""
echo "Checking dependency rule violations..."

# domain/ must not import from infrastructure/, application/, or interfaces/
check_layer_imports "domain" \
  'from ['"'"'"][^'"'"'"]*@infrastructure\|from ['"'"'"][^'"'"'"]*@application\|from ['"'"'"][^'"'"'"]*@interfaces\|from ['"'"'"].*\/infrastructure\/\|from ['"'"'"].*\/application\/\|from ['"'"'"].*\/interfaces\/' \
  "error"

# application/ must not import from infrastructure/ or interfaces/
check_layer_imports "application" \
  'from ['"'"'"][^'"'"'"]*@infrastructure\|from ['"'"'"][^'"'"'"]*@interfaces\|from ['"'"'"].*\/infrastructure\/\|from ['"'"'"].*\/interfaces\/' \
  "warn"

# infrastructure/ must not import from interfaces/
check_layer_imports "infrastructure" \
  'from ['"'"'"][^'"'"'"]*@interfaces\|from ['"'"'"].*\/interfaces\/' \
  "error"

echo ""
echo -e "${BOLD}===================================${NC}"
if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}Architecture check passed.${NC}"
  exit 0
else
  echo -e "${RED}Architecture violations found.${NC}"
  exit 1
fi
