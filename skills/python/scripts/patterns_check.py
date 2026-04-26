#!/usr/bin/env python3
"""
patterns_check.py — Static pattern checker for Python source files.

Usage:
    python patterns_check.py path/to/file.py [path/to/another.py ...]

Checks for:
  - Deprecated typing imports (Dict, List, Optional, Tuple, Union) — use builtins
  - Bare `except:` clauses
  - print() calls in library code
  - Mutable default arguments ([], {}, set())
  - Public functions/methods missing type hints on parameters or return
  - Missing return type annotation on public functions

Exit codes:
  0 — no issues found
  1 — one or more issues found
"""

from __future__ import annotations

import ast
import sys
from dataclasses import dataclass, field
from pathlib import Path


DEPRECATED_TYPING = {"Dict", "List", "Optional", "Tuple", "Union", "Set", "FrozenSet", "Type", "Deque"}

MUTABLE_DEFAULTS = {"list", "dict", "set"}


@dataclass
class Issue:
    path: str
    line: int
    col: int
    code: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}:{self.col}: [{self.code}] {self.message}"


@dataclass
class Checker(ast.NodeVisitor):
    path: str
    issues: list[Issue] = field(default_factory=list)

    def _issue(self, node: ast.AST, code: str, message: str) -> None:
        self.issues.append(
            Issue(
                path=self.path,
                line=getattr(node, "lineno", 0),
                col=getattr(node, "col_offset", 0),
                code=code,
                message=message,
            )
        )

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:  # noqa: N802
        if node.module == "typing":
            for alias in node.names:
                if alias.name in DEPRECATED_TYPING:
                    self._issue(
                        node,
                        "P001",
                        f"Deprecated typing import `typing.{alias.name}` — "
                        f"use builtin equivalent (e.g. `{alias.name.lower()}[...]` or `X | Y`)",
                    )
        self.generic_visit(node)

    def visit_Import(self, node: ast.Import) -> None:  # noqa: N802
        for alias in node.names:
            if alias.name == "typing":
                # Allow `import typing` — only flag specific attribute usage
                pass
        self.generic_visit(node)

    def visit_Attribute(self, node: ast.Attribute) -> None:  # noqa: N802
        # Catch `typing.Dict` etc. via attribute access
        if isinstance(node.value, ast.Name) and node.value.id == "typing":
            if node.attr in DEPRECATED_TYPING:
                self._issue(
                    node,
                    "P001",
                    f"Deprecated `typing.{node.attr}` — use builtin equivalent",
                )
        self.generic_visit(node)

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:  # noqa: N802
        if node.type is None:
            self._issue(node, "P002", "Bare `except:` — catch specific exception types")
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:  # noqa: N802
        if isinstance(node.func, ast.Name) and node.func.id == "print":
            self._issue(node, "P003", "print() call — use structured logging instead")
        self.generic_visit(node)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:  # noqa: N802
        self._check_function(node)
        self.generic_visit(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:  # noqa: N802
        self._check_function(node)
        self.generic_visit(node)

    def _check_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        is_public = not node.name.startswith("_")

        # Check mutable default arguments
        defaults = node.args.defaults + node.args.kw_defaults
        for default in defaults:
            if default is None:
                continue
            if isinstance(default, (ast.List, ast.Dict, ast.Set)):
                kind = type(default).__name__.lower()
                self._issue(
                    node,
                    "P004",
                    f"Mutable default argument `{kind}` in `{node.name}` — use `None` and set inside function",
                )
            elif isinstance(default, ast.Call):
                if isinstance(default.func, ast.Name) and default.func.id in MUTABLE_DEFAULTS:
                    self._issue(
                        node,
                        "P004",
                        f"Mutable default argument `{default.func.id}()` in `{node.name}` — use `None` sentinel",
                    )

        if not is_public:
            return

        # Check return type annotation
        if node.returns is None and node.name not in ("__init__", "__new__"):
            self._issue(
                node,
                "P005",
                f"Public function `{node.name}` missing return type annotation",
            )

        # Check parameter annotations (skip self/cls)
        args = node.args
        all_args = args.args + args.posonlyargs + args.kwonlyargs
        if args.vararg:
            all_args.append(args.vararg)
        if args.kwarg:
            all_args.append(args.kwarg)

        for arg in all_args:
            if arg.arg in ("self", "cls"):
                continue
            if arg.annotation is None:
                self._issue(
                    node,
                    "P005",
                    f"Public function `{node.name}` — parameter `{arg.arg}` missing type annotation",
                )


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

    checker = Checker(path=str(path))
    checker.visit(tree)
    return checker.issues


def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <file.py> [file.py ...]", file=sys.stderr)
        return 2

    all_issues: list[Issue] = []
    for arg in sys.argv[1:]:
        p = Path(arg)
        if not p.exists():
            print(f"ERROR: File not found: {p}", file=sys.stderr)
            continue
        if p.is_dir():
            for py_file in sorted(p.rglob("*.py")):
                all_issues.extend(check_file(py_file))
        else:
            all_issues.extend(check_file(p))

    for issue in sorted(all_issues, key=lambda i: (i.path, i.line)):
        print(issue)

    if all_issues:
        print(f"\n{len(all_issues)} issue(s) found.", file=sys.stderr)
        return 1

    print("No issues found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
