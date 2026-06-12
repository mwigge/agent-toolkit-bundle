#!/usr/bin/env bash
# scripts/test-guard-patterns.sh
# Drift + fixture check for policy/guard-patterns.json and its consumers.
#
# 1. Asserts that the bash hooks and TS plugins which used to hardcode
#    security/cost patterns still reference policy/guard-patterns.json —
#    catches a future edit re-hardcoding a pattern and silently drifting.
# 2. Runs hooks/security-guard.sh and hooks/permission-autoapprove.sh against
#    a shared set of allow/deny fixtures derived from policy/guard-patterns.json
#    so the bash side can't silently regress when the policy changes.
#
# Usage: scripts/test-guard-patterns.sh

set -euo pipefail
cd "$(dirname "$0")/.."

FAIL=0

# ── 1. Drift check: consumers must load the shared policy file ───────────────
for f in hooks/security-guard.sh hooks/permission-autoapprove.sh \
         plugins/security-guard.ts plugins/model-usage.ts \
         hooks/model-usage-summary.sh tools/model-report.py; do
  if ! grep -q "guard-patterns.json" "$f"; then
    echo "FAIL: $f does not reference policy/guard-patterns.json — pattern may have drifted back to a hardcoded copy" >&2
    FAIL=1
  fi
done

# ── 2. Fixture-based allow/deny checks ────────────────────────────────────────
check_exit() {
  local desc="$1" script="$2" input="$3" expected="$4"
  local actual=0
  echo "$input" | bash "$script" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $script: $desc — expected exit $expected, got $actual" >&2
    FAIL=1
  fi
}

check_decision() {
  local desc="$1" input="$2" expect_substr="$3"
  local out
  out=$(echo "$input" | bash hooks/permission-autoapprove.sh 2>/dev/null) || true
  if [[ "$out" != *"$expect_substr"* ]]; then
    echo "FAIL: permission-autoapprove.sh: $desc — expected output to contain '$expect_substr', got '$out'" >&2
    FAIL=1
  fi
}

# security-guard.sh: destructive commands and protected files (RED, exit 2)
check_exit "rm -rf /" hooks/security-guard.sh \
  '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' 2

check_exit "rm -fr / (reversed flags)" hooks/security-guard.sh \
  '{"tool_name":"Bash","tool_input":{"command":"rm -fr /"}}' 2

check_exit "sudo rm -rf /" hooks/security-guard.sh \
  '{"tool_name":"Bash","tool_input":{"command":"sudo rm -rf /"}}' 2

check_exit "rm --recursive --force /" hooks/security-guard.sh \
  '{"tool_name":"Bash","tool_input":{"command":"rm --recursive --force /"}}' 2

check_exit "find / -delete" hooks/security-guard.sh \
  '{"tool_name":"Bash","tool_input":{"command":"find / -delete -name x"}}' 2

check_exit "force-push to main" hooks/security-guard.sh \
  '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' 2

check_exit "edit .env" hooks/security-guard.sh \
  '{"tool_name":"Edit","tool_input":{"file_path":".env","new_string":"FOO=bar"}}' 2

check_exit "edit pnpm-lock.yaml (shared protected_files)" hooks/security-guard.sh \
  '{"tool_name":"Edit","tool_input":{"file_path":"pnpm-lock.yaml","new_string":"x"}}' 2

check_exit "secret in pending content" hooks/security-guard.sh \
  '{"tool_name":"Edit","tool_input":{"file_path":"src/x.py","new_string":"api_key = \"sk-1234567890abcdef\""}}' 2

# security-guard.sh: benign operations (allow, exit 0)
check_exit "read-only bash command" hooks/security-guard.sh \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' 0

check_exit "ordinary source edit" hooks/security-guard.sh \
  '{"tool_name":"Edit","tool_input":{"file_path":"src/x.py","new_string":"x = 1"}}' 0

# permission-autoapprove.sh: RED — denied outright
check_exit "rm -rf /" hooks/permission-autoapprove.sh \
  '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"hook_event_name":"PermissionRequest"}' 2

check_exit "edit pnpm-lock.yaml (shared protected_files)" hooks/permission-autoapprove.sh \
  '{"tool_name":"Edit","tool_input":{"file_path":"pnpm-lock.yaml"},"hook_event_name":"PermissionRequest"}' 2

# permission-autoapprove.sh: self-protection — escalate (exit 0, no decision)
check_exit "edit hooks/*.sh escalates" hooks/permission-autoapprove.sh \
  '{"tool_name":"Edit","tool_input":{"file_path":"hooks/foo.sh"},"hook_event_name":"PermissionRequest"}' 0
check_decision "edit hooks/*.sh produces no allow decision" \
  '{"tool_name":"Edit","tool_input":{"file_path":"hooks/foo.sh"},"hook_event_name":"PermissionRequest"}' ""

# permission-autoapprove.sh: GREEN/YELLOW — allow decisions
check_decision "Read tool is auto-approved" \
  '{"tool_name":"Read","tool_input":{"file_path":"src/x.py"},"hook_event_name":"PermissionRequest"}' \
  '"permissionDecision":"allow"'

check_decision "edit to project source file is auto-approved" \
  '{"tool_name":"Edit","tool_input":{"file_path":"src/x.py"},"hook_event_name":"PermissionRequest"}' \
  '"permissionDecision":"allow"'

if [[ "$FAIL" -eq 0 ]]; then
  echo "OK: guard-patterns drift check and fixtures passed"
fi

exit "$FAIL"
