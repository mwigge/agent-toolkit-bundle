#!/usr/bin/env bash
# .claude/hooks/inline-quality.sh
# PostToolUse hook on Edit|Write — provides additionalContext feedback so Claude
# self-corrects inline rather than waiting for the Stop quality-gate.
# Uses exit 0 + additionalContext JSON — never blocks, only advises.
#
# additionalContext format:
#   { "additionalContext": "INLINE QUALITY FEEDBACK:\n..." }

set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

EXT="${FILE_PATH##*.}"
ISSUES=()

# ── Python checks ────────────────────────────────────────────────────────────
if [[ "$EXT" == "py" ]]; then
  # print() in non-test code
  if [[ "$FILE_PATH" != *test* ]] && [[ "$FILE_PATH" != *tests* ]]; then
    if grep -nE '^\s*print\(' "$FILE_PATH" 2>/dev/null | grep -v '#' | grep -q .; then
      LINE=$(grep -nE '^\s*print\(' "$FILE_PATH" 2>/dev/null | grep -v '#' | head -1 | cut -d: -f1)
      ISSUES+=("Line $LINE: print() in library code — replace with structured logger (logger.info / logger.debug)")
    fi
  fi

  # bare except
  if grep -nE '^\s*except\s*:' "$FILE_PATH" 2>/dev/null | grep -q .; then
    LINE=$(grep -nE '^\s*except\s*:' "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
    ISSUES+=("Line $LINE: bare except: — catch a specific exception (e.g. except ValueError)")
  fi

  # deprecated typing imports (Dict, List, Optional, Tuple, Set)
  if grep -nE 'from typing import.*\b(Dict|List|Tuple|Set|Optional)\b' "$FILE_PATH" 2>/dev/null | grep -q .; then
    LINE=$(grep -nE 'from typing import.*\b(Dict|List|Tuple|Set|Optional)\b' "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
    ISSUES+=("Line $LINE: deprecated typing.Dict/List/Optional — use dict / list / X | None (Python 3.10+)")
  fi

  # hardcoded secret patterns
  if grep -nE '(api_key|secret_key|password|token)\s*=\s*["'"'"'][^$\{][^"'"'"']{8,}' "$FILE_PATH" 2>/dev/null | grep -q .; then
    LINE=$(grep -nE '(api_key|secret_key|password|token)\s*=\s*["'"'"'][^$\{][^"'"'"']{8,}' "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
    ISSUES+=("Line $LINE: potential hardcoded secret — use environment variable instead")
  fi
fi

# ── TypeScript checks ─────────────────────────────────────────────────────────
if [[ "$EXT" == "ts" || "$EXT" == "tsx" ]]; then
  # console.log in non-test files
  if [[ "$FILE_PATH" != *.test.* ]] && [[ "$FILE_PATH" != *.spec.* ]]; then
    if grep -nE 'console\.(log|error|warn|info|debug)\(' "$FILE_PATH" 2>/dev/null | grep -q .; then
      LINE=$(grep -nE 'console\.(log|error|warn|info|debug)\(' "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
      ISSUES+=("Line $LINE: console.log in src/ — use structured logger")
    fi
  fi

  # untyped 'any' without comment justification
  if grep -nE ':\s*any\b' "$FILE_PATH" 2>/dev/null | grep -v '// any:' | grep -q .; then
    LINE=$(grep -nE ':\s*any\b' "$FILE_PATH" 2>/dev/null | grep -v '// any:' | head -1 | cut -d: -f1)
    ISSUES+=("Line $LINE: use of 'any' — provide explicit type or add // any: <justification> comment")
  fi
fi

# ── SQL checks ────────────────────────────────────────────────────────────────
if [[ "$EXT" == "py" ]]; then
  # string-interpolated SQL (f-string or % format)
  if grep -nE 'cursor\.execute\(f"|cursor\.execute\(.*%\s*[a-z]' "$FILE_PATH" 2>/dev/null | grep -q .; then
    LINE=$(grep -nE 'cursor\.execute\(f"|cursor\.execute\(.*%\s*[a-z]' "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
    ISSUES+=("Line $LINE: non-parameterised SQL — use cursor.execute('... WHERE id = %s', (val,))")
  fi
fi

# ── Emit additionalContext ────────────────────────────────────────────────────
if [[ ${#ISSUES[@]} -gt 0 ]]; then
  MSG="INLINE QUALITY FEEDBACK for ${FILE_PATH##*/}:\n"
  for issue in "${ISSUES[@]}"; do
    MSG+="  • $issue\n"
  done
  MSG+="Fix these issues now before moving on."
  jq -n --arg ctx "$MSG" '{"additionalContext": $ctx}'
fi

exit 0
