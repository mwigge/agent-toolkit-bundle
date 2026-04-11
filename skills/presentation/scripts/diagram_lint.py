#!/usr/bin/env python3
"""
diagram_lint.py — Lint a Mermaid .mmd file for common structural mistakes.

Usage:
    python diagram_lint.py <file.mmd>

Exit codes:
    0  PASS — no issues found
    1  FAIL — one or more issues detected
"""

import sys
import re
from pathlib import Path

DIRECTION_KEYWORDS = {"LR", "RL", "TB", "TD", "BT"}

DIAGRAM_TYPES_REQUIRING_DIRECTION = {
    "graph",
    "flowchart",
}

# An unterminated string is indicated by an odd number of unescaped double-quotes
# on the line.  Even counts mean all strings are closed.
# We count unescaped quotes by removing escaped ones first, then counting.
def _has_unterminated_string(line: str) -> bool:
    """Return True if the line contains an unterminated double-quoted string."""
    # Remove escaped quotes so they don't affect the count
    stripped = re.sub(r'\\"', "", line)
    # An odd number of quote characters means at least one string is unclosed
    return stripped.count('"') % 2 != 0

TITLE_RE = re.compile(r"^\s*title\s+\S", re.MULTILINE)
INIT_TITLE_RE = re.compile(r'"title"\s*:\s*"[^"]+"')

def load_file(path: str) -> list[str]:
    p = Path(path)
    if not p.exists():
        print(f"ERROR: file not found: {path}", file=sys.stderr)
        sys.exit(2)
    if p.suffix.lower() not in {".mmd", ".md"}:
        print(f"WARNING: expected .mmd extension, got {p.suffix}", file=sys.stderr)
    return p.read_text(encoding="utf-8").splitlines()

def check_title(lines: list[str]) -> list[str]:
    """Return error messages if no title directive is found."""
    full_text = "\n".join(lines)
    if TITLE_RE.search(full_text):
        return []
    if INIT_TITLE_RE.search(full_text):
        return []
    return ["MISSING TITLE: add `title Your Diagram Title` after the diagram type declaration"]

def detect_diagram_type(lines: list[str]) -> str | None:
    """Return the primary diagram type keyword from the first non-comment line."""
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("%%"):
            continue
        # %%{init: ...}%% blocks are not the type declaration
        if stripped.startswith("%%{"):
            continue
        token = stripped.split()[0].lower()
        return token
    return None

def check_direction(lines: list[str]) -> list[str]:
    """Return error messages if a graph/flowchart has no direction keyword."""
    diagram_type = detect_diagram_type(lines)
    if diagram_type not in DIAGRAM_TYPES_REQUIRING_DIRECTION:
        return []

    full_text = "\n".join(lines)
    # Direction appears as: graph LR  /  flowchart TD  etc.
    direction_pattern = re.compile(
        r"^(graph|flowchart)\s+(" + "|".join(DIRECTION_KEYWORDS) + r")\b",
        re.MULTILINE | re.IGNORECASE,
    )
    if direction_pattern.search(full_text):
        return []
    return [
        f"MISSING DIRECTION: {diagram_type} diagram must declare direction "
        f"(one of: {', '.join(sorted(DIRECTION_KEYWORDS))}). "
        f"Example: `{diagram_type} LR`"
    ]

def check_unterminated_strings(lines: list[str]) -> list[str]:
    """Return error messages for lines that appear to have unterminated quoted strings."""
    errors: list[str] = []
    for lineno, line in enumerate(lines, start=1):
        # Strip inline comments (%%...)
        code_part = re.sub(r"%%.*$", "", line)
        if _has_unterminated_string(code_part):
            errors.append(
                f"UNTERMINATED STRING at line {lineno}: {line.strip()!r}"
            )
    return errors

def check_empty_node_labels(lines: list[str]) -> list[str]:
    """Warn about nodes defined with empty labels like A[] or A()."""
    errors: list[str] = []
    empty_label_re = re.compile(r"\b\w+\s*(\[\s*\]|\(\s*\)|\{\s*\})")
    for lineno, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("%%"):
            continue
        if empty_label_re.search(line):
            errors.append(
                f"EMPTY NODE LABEL at line {lineno}: {stripped!r} — "
                "every node should have a meaningful label"
            )
    return errors

def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python diagram_lint.py <file.mmd>", file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]
    lines = load_file(path)

    all_errors: list[str] = []
    all_errors.extend(check_title(lines))
    all_errors.extend(check_direction(lines))
    all_errors.extend(check_unterminated_strings(lines))
    all_errors.extend(check_empty_node_labels(lines))

    if all_errors:
        print(f"FAIL — {path}")
        for err in all_errors:
            print(f"  • {err}")
        sys.exit(1)
    else:
        print(f"PASS — {path}")
        sys.exit(0)

if __name__ == "__main__":
    main()
