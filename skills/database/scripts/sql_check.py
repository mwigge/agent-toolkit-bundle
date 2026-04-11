#!/usr/bin/env python3
"""
sql_check.py — Static analysis for SQL files and Python SQL usage patterns.

Usage:
    python sql_check.py path/to/query.sql [another.sql ...]
    python sql_check.py src/   # scans all .sql and .py files recursively

Checks:
  SQL files:
    - SELECT * usage (missing explicit column list)
    - UPDATE without WHERE clause
    - DELETE without WHERE clause
    - Missing LIMIT on SELECT (warn)

  Python files:
    - f-string interpolation near cursor.execute (SQL injection risk)
    - % formatting near cursor.execute (SQL injection risk)
    - String concatenation with + near cursor.execute

Exit codes:
  0 — no issues
  1 — issues found
"""

from __future__ import annotations

import ast
import re
import sys
from dataclasses import dataclass
from pathlib import Path

@dataclass
class Issue:
    path: str
    line: int
    code: str
    severity: str
    message: str

    def __str__(self) -> str:
        return f"[{self.severity}] {self.path}:{self.line}: [{self.code}] {self.message}"

# ---------------------------------------------------------------------------
# SQL File Checks
# ---------------------------------------------------------------------------

_SELECT_STAR = re.compile(r"\bSELECT\s+\*", re.IGNORECASE)
_UPDATE_NO_WHERE = re.compile(r"\bUPDATE\b(?:(?!\bWHERE\b).)*;", re.IGNORECASE | re.DOTALL)
_DELETE_NO_WHERE = re.compile(r"\bDELETE\b(?:(?!\bWHERE\b).)*;", re.IGNORECASE | re.DOTALL)
_SELECT_WITHOUT_LIMIT = re.compile(r"\bSELECT\b(?:(?!\bLIMIT\b).)*;", re.IGNORECASE | re.DOTALL)

def check_sql_file(path: Path) -> list[Issue]:
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as e:
        print(f"ERROR: Cannot read {path}: {e}", file=sys.stderr)
        return []

    issues: list[Issue] = []
    lines = content.splitlines()

    for lineno, line in enumerate(lines, start=1):
        stripped = line.strip()

        # Skip comments
        if stripped.startswith("--") or stripped.startswith("/*"):
            continue

        # SELECT *
        if _SELECT_STAR.search(line):
            issues.append(Issue(
                path=str(path), line=lineno, code="SQL001", severity="WARN",
                message="SELECT * — specify explicit column names for clarity and stability",
            ))

    # Statement-level checks (across lines)
    # Normalise whitespace for multi-line statements
    normalised = re.sub(r"\s+", " ", content)

    # UPDATE without WHERE
    for match in re.finditer(r"\bUPDATE\s+\S+\s+SET\b[^;]*;", normalised, re.IGNORECASE):
        if not re.search(r"\bWHERE\b", match.group(), re.IGNORECASE):
            # Approximate line number
            preceding = content[: content.find(match.group()[:20]) if match.group()[:20] in content else 0]
            lineno = preceding.count("\n") + 1
            issues.append(Issue(
                path=str(path), line=lineno, code="SQL002", severity="ERROR",
                message="UPDATE without WHERE clause — will affect ALL rows",
            ))

    # DELETE without WHERE
    for match in re.finditer(r"\bDELETE\s+FROM\s+\S+[^;]*;", normalised, re.IGNORECASE):
        if not re.search(r"\bWHERE\b", match.group(), re.IGNORECASE):
            preceding = content[: content.find(match.group()[:20]) if match.group()[:20] in content else 0]
            lineno = preceding.count("\n") + 1
            issues.append(Issue(
                path=str(path), line=lineno, code="SQL003", severity="ERROR",
                message="DELETE without WHERE clause — will delete ALL rows",
            ))

    # SELECT without LIMIT (warn only for non-COUNT queries)
    for match in re.finditer(
        r"\bSELECT\b(?!\s+COUNT)(?:(?!\bLIMIT\b)(?!\bINSERT\b)(?!\bUPDATE\b)(?!\bDELETE\b).)*;",
        normalised,
        re.IGNORECASE,
    ):
        if "LIMIT" not in match.group().upper() and "COUNT(" not in match.group().upper():
            issues.append(Issue(
                path=str(path), line=0, code="SQL004", severity="WARN",
                message="SELECT without LIMIT — consider adding LIMIT to prevent unbounded result sets",
            ))
            break  # One warning per file is enough

    return issues

# ---------------------------------------------------------------------------
# Python File Checks — SQL injection patterns
# ---------------------------------------------------------------------------

class SqlInjectionVisitor(ast.NodeVisitor):
    def __init__(self, path: str) -> None:
        self.path = path
        self.issues: list[Issue] = []

    def _check_execute_call(self, node: ast.Call) -> None:
        """Check if cursor.execute() is called with a non-literal SQL string."""
        # Look for patterns: cursor.execute(f"...", ...) or cursor.execute("..." % ...)
        if len(node.args) == 0:
            return

        first_arg = node.args[0]

        # f-string interpolation
        if isinstance(first_arg, ast.JoinedStr):
            self.issues.append(Issue(
                path=self.path,
                line=node.lineno,
                code="SQL010",
                severity="ERROR",
                message="f-string interpolation in cursor.execute() — SQL injection risk! Use parameterised queries: cursor.execute(sql, (val,))",
            ))

        # % formatting: "SELECT ... WHERE id = %s" % (val,)
        elif isinstance(first_arg, ast.BinOp) and isinstance(first_arg.op, ast.Mod):
            self.issues.append(Issue(
                path=self.path,
                line=node.lineno,
                code="SQL011",
                severity="ERROR",
                message="% string formatting in cursor.execute() — SQL injection risk! Use cursor.execute(sql, params) not sql % params",
            ))

        # String concatenation: "SELECT " + user_input
        elif isinstance(first_arg, ast.BinOp) and isinstance(first_arg.op, ast.Add):
            self.issues.append(Issue(
                path=self.path,
                line=node.lineno,
                code="SQL012",
                severity="ERROR",
                message="String concatenation (+) in cursor.execute() — SQL injection risk! Use parameterised queries",
            ))

    def visit_Call(self, node: ast.Call) -> None:  # noqa: N802
        # Match cursor.execute(...) or session.execute(...) or conn.execute(...)
        if isinstance(node.func, ast.Attribute) and node.func.attr in ("execute", "executemany"):
            self._check_execute_call(node)
        self.generic_visit(node)

def check_python_file(path: Path) -> list[Issue]:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError:
        return []

    if "execute" not in source:
        return []

    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError:
        return []

    visitor = SqlInjectionVisitor(path=str(path))
    visitor.visit(tree)
    return visitor.issues

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <file_or_dir> [...]", file=sys.stderr)
        return 2

    all_issues: list[Issue] = []

    for arg in sys.argv[1:]:
        p = Path(arg)
        if p.is_dir():
            for sql_file in sorted(p.rglob("*.sql")):
                all_issues.extend(check_sql_file(sql_file))
            for py_file in sorted(p.rglob("*.py")):
                all_issues.extend(check_python_file(py_file))
        elif p.suffix == ".sql":
            all_issues.extend(check_sql_file(p))
        elif p.suffix == ".py":
            all_issues.extend(check_python_file(p))
        else:
            print(f"WARNING: Skipping unsupported file type: {p}", file=sys.stderr)

    errors = [i for i in all_issues if i.severity == "ERROR"]
    warns = [i for i in all_issues if i.severity == "WARN"]

    for issue in sorted(all_issues, key=lambda i: (i.path, i.line)):
        print(issue)

    if all_issues:
        print(f"\n{len(errors)} error(s), {len(warns)} warning(s).", file=sys.stderr)
        return 1

    print("No SQL issues found.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
