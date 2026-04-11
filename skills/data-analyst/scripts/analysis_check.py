#!/usr/bin/env python3
"""
analysis_check.py — Static analyser for Jupyter notebooks (.ipynb files).

Usage:
    python analysis_check.py notebook.ipynb [another.ipynb ...]

Checks:
  - Code cells with no output (potential unrun/stale cells)
  - Use of df.iterrows() (very slow — use vectorised operations)
  - Hardcoded absolute file paths (portability issue)
  - No markdown cells in the notebook (missing documentation)
  - print() calls in code cells (use display() or logging)
  - Cell execution order not sequential (cells run out of order)

Exit codes:
  0 — no issues
  1 — issues found
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

@dataclass
class Issue:
    path: str
    cell_index: int
    line: int
    code: str
    severity: str
    message: str

    def __str__(self) -> str:
        loc = f"cell[{self.cell_index}]"
        if self.line > 0:
            loc += f":line {self.line}"
        return f"[{self.severity}] {self.path} {loc}: [{self.code}] {self.message}"

_ITERROWS_RE = re.compile(r"\biterrows\s*\(\s*\)")
_HARDCODED_PATH_RE = re.compile(r"""['"](/(?:home|Users|var|tmp|data|mnt)/[^\s'"]+)""")
_PRINT_RE = re.compile(r"^\s*print\s*\(", re.MULTILINE)

def check_notebook(path: Path) -> list[Issue]:
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: Cannot read {path}: {exc}", file=sys.stderr)
        return []

    try:
        nb = json.loads(content)
    except json.JSONDecodeError as exc:
        print(f"ERROR: Invalid JSON in {path}: {exc}", file=sys.stderr)
        return []

    cells = nb.get("cells", [])
    if not cells:
        return [Issue(str(path), 0, 0, "NB000", "WARN", "Notebook has no cells")]

    issues: list[Issue] = []

    # Check for markdown cells
    has_markdown = any(c.get("cell_type") == "markdown" for c in cells)
    if not has_markdown:
        issues.append(Issue(
            str(path), 0, 0, "NB001", "WARN",
            "No markdown cells found — add documentation explaining the analysis purpose and findings",
        ))

    # Track execution order for out-of-order detection
    prev_exec_count: int | None = None
    code_cell_idx = 0

    for cell_idx, cell in enumerate(cells):
        cell_type = cell.get("cell_type", "")
        source_lines = cell.get("source", [])
        source = "".join(source_lines)

        if cell_type != "code":
            continue

        code_cell_idx += 1
        exec_count = cell.get("execution_count")
        outputs = cell.get("outputs", [])

        # Check for code cells with no output (might be stale/unrun)
        if source.strip() and not outputs and exec_count is None:
            issues.append(Issue(
                str(path), cell_idx, 0, "NB002", "WARN",
                f"Code cell has no output and was never executed — run the notebook top-to-bottom",
            ))
        elif source.strip() and not outputs and exec_count is not None:
            # Cell was run but produced no output — could be expected (assignment cells)
            # Only warn if it looks like it should produce output
            if any(kw in source for kw in ["plot", "show", "display", "print", "describe", "head"]):
                issues.append(Issue(
                    str(path), cell_idx, 0, "NB003", "WARN",
                    f"Cell appears to produce output but outputs list is empty — cell may be stale",
                ))

        # Execution order check
        if exec_count is not None and prev_exec_count is not None:
            if exec_count != prev_exec_count + 1:
                issues.append(Issue(
                    str(path), cell_idx, 0, "NB004", "WARN",
                    f"Cell execution order is non-sequential "
                    f"(expected {prev_exec_count + 1}, got {exec_count}) — "
                    f"notebook may produce different results when run top-to-bottom",
                ))
        if exec_count is not None:
            prev_exec_count = exec_count

        # Per-line checks
        for lineno, line in enumerate(source_lines, start=1):
            # iterrows
            if _ITERROWS_RE.search(line):
                issues.append(Issue(
                    str(path), cell_idx, lineno, "NB005", "WARN",
                    "df.iterrows() is very slow for large DataFrames — "
                    "use vectorised operations, df.apply(), or polars",
                ))

            # Hardcoded absolute paths
            for m in _HARDCODED_PATH_RE.finditer(line):
                issues.append(Issue(
                    str(path), cell_idx, lineno, "NB006", "WARN",
                    f"Hardcoded absolute path: {m.group(1)!r} — "
                    f"use relative paths or pathlib.Path(__file__).parent",
                ))

            # print() calls
            if _PRINT_RE.match(line):
                issues.append(Issue(
                    str(path), cell_idx, lineno, "NB007", "INFO",
                    "print() in code cell — prefer display() for DataFrames/figures, "
                    "or logging for pipeline scripts",
                ))

    return issues

def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} notebook.ipynb [...]", file=sys.stderr)
        return 2

    all_issues: list[Issue] = []
    for arg in sys.argv[1:]:
        p = Path(arg)
        if p.is_dir():
            for nb in sorted(p.rglob("*.ipynb")):
                if ".ipynb_checkpoints" in str(nb):
                    continue
                all_issues.extend(check_notebook(nb))
        elif p.suffix == ".ipynb":
            all_issues.extend(check_notebook(p))
        else:
            print(f"WARNING: Not a notebook file: {p}", file=sys.stderr)

    errors = [i for i in all_issues if i.severity == "ERROR"]
    warns  = [i for i in all_issues if i.severity == "WARN"]
    infos  = [i for i in all_issues if i.severity == "INFO"]

    for issue in sorted(all_issues, key=lambda i: (i.path, i.cell_index, i.line)):
        print(issue)

    if all_issues:
        print(f"\n{len(errors)} error(s), {len(warns)} warning(s), {len(infos)} info(s).",
              file=sys.stderr)
        return 1 if (errors or warns) else 0

    print("No notebook issues found.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
