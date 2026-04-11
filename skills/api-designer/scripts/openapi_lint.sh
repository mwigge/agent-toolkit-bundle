#!/usr/bin/env bash
# openapi_lint.sh — Lint an OpenAPI spec with Spectral (fallback: Python check).
#
# Usage:
#   ./openapi_lint.sh path/to/openapi.yaml
#
# Checks (Python fallback):
#   - Every operation has an operationId
#   - Every operation has at least one 4xx response
#   - info.version is present
#   - Operations have at least one example
#
# Exit code: 0 if all checks pass, 1 if any fail.

set -uo pipefail

SPEC_FILE="${1:-openapi.yaml}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

if [[ ! -f "$SPEC_FILE" ]]; then
  echo -e "${RED}ERROR: OpenAPI spec not found: $SPEC_FILE${NC}" >&2
  exit 1
fi

echo -e "${BOLD}=== OpenAPI Lint: $SPEC_FILE ===${NC}"

# Try Spectral first (best-in-class linter)
if command -v spectral &>/dev/null; then
  echo "Using Spectral..."
  spectral lint "$SPEC_FILE" --ruleset @stoplight/spectral-openapi
  exit $?
fi

# Try via npx
if command -v npx &>/dev/null && npx --no-install @stoplight/spectral-cli --version &>/dev/null 2>&1; then
  echo "Using Spectral via npx..."
  npx @stoplight/spectral-cli lint "$SPEC_FILE"
  exit $?
fi

# Fallback: Python-based check
echo -e "${YELLOW}Spectral not found — using Python fallback check${NC}"
echo ""

python3 - "$SPEC_FILE" <<'PYEOF'
import sys
import json
from pathlib import Path

try:
    import yaml
    def load_spec(path):
        return yaml.safe_load(Path(path).read_text())
except ImportError:
    import json as _json
    def load_spec(path):
        # Try JSON if yaml not available
        try:
            return _json.loads(Path(path).read_text())
        except _json.JSONDecodeError:
            print("ERROR: PyYAML not installed and file is not valid JSON. Install: pip install pyyaml", file=sys.stderr)
            sys.exit(2)

spec_path = sys.argv[1]
spec = load_spec(spec_path)

issues = []
HTTP_METHODS = {"get", "post", "put", "patch", "delete", "head", "options", "trace"}

# Check info.version
info = spec.get("info", {})
if not info.get("version"):
    issues.append("ERROR: info.version is missing or empty")

# Check paths
paths = spec.get("paths", {})
for path, path_item in paths.items():
    if not isinstance(path_item, dict):
        continue
    for method, operation in path_item.items():
        if method not in HTTP_METHODS:
            continue
        if not isinstance(operation, dict):
            continue

        op_id = f"{method.upper()} {path}"

        # operationId
        if not operation.get("operationId"):
            issues.append(f"ERROR: Missing operationId for {op_id}")

        # 4xx response
        responses = operation.get("responses", {})
        has_4xx = any(
            str(code).startswith("4") or code == "default"
            for code in responses.keys()
        )
        if not has_4xx:
            issues.append(f"WARN: No 4xx response defined for {op_id}")

        # examples (check request body or responses for examples)
        has_example = False
        request_body = operation.get("requestBody", {})
        for media_content in request_body.get("content", {}).values():
            if media_content.get("example") or media_content.get("examples"):
                has_example = True
        for response_obj in responses.values():
            if not isinstance(response_obj, dict):
                continue
            for media_content in response_obj.get("content", {}).values():
                if media_content.get("example") or media_content.get("examples"):
                    has_example = True

        if not has_example and method in ("get", "post", "put", "patch"):
            issues.append(f"WARN: No examples in request/response for {op_id}")

# Report
errors = [i for i in issues if i.startswith("ERROR")]
warns = [i for i in issues if i.startswith("WARN")]

for issue in issues:
    prefix = "\033[31m✗\033[0m" if issue.startswith("ERROR") else "\033[33m⚠\033[0m"
    print(f"  {prefix} {issue}")

if not issues:
    print("\033[32m  ✓ All checks passed\033[0m")

print(f"\n{len(errors)} error(s), {len(warns)} warning(s)")
sys.exit(1 if errors else 0)
PYEOF
