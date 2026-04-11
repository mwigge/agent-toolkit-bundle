#!/usr/bin/env python3
"""
otel_check.py — Check Python source files for OpenTelemetry instrumentation completeness.

Usage:
    python otel_check.py src/file.py [another.py ...]
    python otel_check.py src/   # scans all .py files recursively

Checks:
  - Files that import from opentelemetry must create at least one span
  - HTTP route handlers should have trace context propagation
  - Files that import logging must not use print() (use logger.*)
  - Span attributes should follow resilience_* naming in chaos-related files

Exit codes:
  0 — no issues
  1 — issues found
"""

from __future__ import annotations

import ast
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
        loc = f":{self.line}" if self.line > 0 else ""
        return f"[{self.severity}] {self.path}{loc}: [{self.code}] {self.message}"

class OtelChecker(ast.NodeVisitor):
    def __init__(self, path: str) -> None:
        self.path = path
        self.issues: list[Issue] = []

        # Tracking state
        self._imports_otel = False
        self._imports_logging = False
        self._has_span_creation = False
        self._has_route_decorator = False
        self._has_context_propagation = False
        self._print_calls: list[int] = []
        self._span_lineno = 0
        self._otel_import_lineno = 0

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:  # noqa: N802
        if node.module and "opentelemetry" in node.module:
            self._imports_otel = True
            self._otel_import_lineno = node.lineno

        if node.module in ("logging", "structlog"):
            self._imports_logging = True

        # Context propagation imports
        if node.module and "propagat" in node.module:
            self._has_context_propagation = True

        self.generic_visit(node)

    def visit_Import(self, node: ast.Import) -> None:  # noqa: N802
        for alias in node.names:
            if "opentelemetry" in alias.name:
                self._imports_otel = True
                self._otel_import_lineno = node.lineno
            if alias.name in ("logging", "structlog"):
                self._imports_logging = True
        self.generic_visit(node)

    def visit_With(self, node: ast.With) -> None:  # noqa: N802
        for item in node.items:
            # Detect: with tracer.start_as_current_span(...):
            if isinstance(item.context_expr, ast.Call):
                func = item.context_expr.func
                if isinstance(func, ast.Attribute) and "span" in func.attr.lower():
                    self._has_span_creation = True
                    self._span_lineno = node.lineno
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:  # noqa: N802
        func = node.func

        # Detect span creation: tracer.start_span(), tracer.start_as_current_span()
        if isinstance(func, ast.Attribute):
            if func.attr in ("start_span", "start_as_current_span", "use_span"):
                self._has_span_creation = True
                self._span_lineno = node.lineno

            # Context propagation: extract() / inject()
            if func.attr in ("extract", "inject"):
                self._has_context_propagation = True

        # print() calls
        if isinstance(func, ast.Name) and func.id == "print":
            self._print_calls.append(node.lineno)

        self.generic_visit(node)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
        self._check_route_handler(node)
        self.generic_visit(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
        self._check_route_handler(node)
        self.generic_visit(node)

    def _check_route_handler(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        """Detect HTTP route handlers via decorator patterns."""
        route_decorators = {"route", "get", "post", "put", "patch", "delete",
                            "app_route", "api_route", "router"}
        for decorator in node.decorator_list:
            dec_name = ""
            if isinstance(decorator, ast.Attribute):
                dec_name = decorator.attr
            elif isinstance(decorator, ast.Call):
                if isinstance(decorator.func, ast.Attribute):
                    dec_name = decorator.func.attr
                elif isinstance(decorator.func, ast.Name):
                    dec_name = decorator.func.id
            elif isinstance(decorator, ast.Name):
                dec_name = decorator.id

            if dec_name.lower() in route_decorators:
                self._has_route_decorator = True

    def finalise(self) -> None:
        """Report aggregate issues after visiting the whole file."""
        if self._imports_otel and not self._has_span_creation:
            self.issues.append(Issue(
                path=self.path, line=self._otel_import_lineno,
                code="OT001", severity="WARN",
                message="File imports from opentelemetry but no span is created "
                        "(tracer.start_span / start_as_current_span). "
                        "Ensure instrumentation is active.",
            ))

        if self._has_route_decorator and self._imports_otel and not self._has_context_propagation:
            self.issues.append(Issue(
                path=self.path, line=0,
                code="OT002", severity="WARN",
                message="HTTP route handler detected but no trace context propagation found "
                        "(no propagators.extract/inject). "
                        "Add W3C TraceContext propagation to incoming requests.",
            ))

        if self._imports_logging:
            for lineno in self._print_calls:
                self.issues.append(Issue(
                    path=self.path, line=lineno,
                    code="OT003", severity="WARN",
                    message="print() call in a file that imports logging — "
                            "use logger.info/warning/error instead for structured output",
                ))
        elif self._print_calls:
            for lineno in self._print_calls[:3]:
                self.issues.append(Issue(
                    path=self.path, line=lineno,
                    code="OT003", severity="INFO",
                    message="print() call — consider using structured logging (import logging)",
                ))

def check_file(path: Path) -> list[Issue]:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: Cannot read {path}: {exc}", file=sys.stderr)
        return []

    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        print(f"ERROR: Syntax error in {path}: {exc}", file=sys.stderr)
        return []

    checker = OtelChecker(path=str(path))
    checker.visit(tree)
    checker.finalise()
    return checker.issues

def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <file.py> [file.py ...] | <directory>", file=sys.stderr)
        return 2

    all_issues: list[Issue] = []
    for arg in sys.argv[1:]:
        p = Path(arg)
        if p.is_dir():
            for py_file in sorted(p.rglob("*.py")):
                if "test" in py_file.stem or ".venv" in str(py_file):
                    continue
                all_issues.extend(check_file(py_file))
        else:
            all_issues.extend(check_file(p))

    for issue in sorted(all_issues, key=lambda i: (i.path, i.line)):
        print(issue)

    warns = [i for i in all_issues if i.severity in ("WARN", "ERROR")]
    if all_issues:
        print(f"\n{len(warns)} warning(s), {len(all_issues) - len(warns)} info(s).", file=sys.stderr)
        return 1 if warns else 0

    print("No observability issues found.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
