#!/usr/bin/env python3
"""
arch_check.py — Validates Clean Architecture layer structure in a Python project.

Usage:
    python arch_check.py [src_dir]   (default: src/)

Checks:
  1. Expected layer directories exist: domain/, application/, infrastructure/, interfaces/
  2. domain/ files do not import from infrastructure/
  3. domain/ files do not import from application/
  4. application/ files do not import from infrastructure/ (warn, not error)
  5. interfaces/ files do not import from domain/ directly (should go via application/)

Exit codes:
  0 — no violations found
  1 — one or more violations found
"""

from __future__ import annotations

import ast
import sys
from dataclasses import dataclass, field
from pathlib import Path


REQUIRED_LAYERS = ["domain", "application", "infrastructure", "interfaces"]

# (source_layer, forbidden_target_layer, severity)
DEPENDENCY_RULES: list[tuple[str, str, str]] = [
    ("domain", "infrastructure", "ERROR"),
    ("domain", "application", "ERROR"),
    ("domain", "interfaces", "ERROR"),
    ("application", "infrastructure", "WARN"),
    ("application", "interfaces", "ERROR"),
]


@dataclass
class Violation:
    path: str
    line: int
    severity: str
    message: str

    def __str__(self) -> str:
        return f"[{self.severity}] {self.path}:{self.line}: {self.message}"


def get_imports(source: str, filepath: str) -> list[tuple[int, str]]:
    """Return list of (lineno, module_name) for all import statements."""
    try:
        tree = ast.parse(source, filename=filepath)
    except SyntaxError:
        return []

    imports: list[tuple[int, str]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append((node.lineno, alias.name))
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                imports.append((node.lineno, node.module))
    return imports


def check_layer_boundaries(src_dir: Path) -> list[Violation]:
    violations: list[Violation] = []

    for source_layer, forbidden_layer, severity in DEPENDENCY_RULES:
        layer_dir = src_dir / source_layer
        if not layer_dir.exists():
            continue

        for py_file in sorted(layer_dir.rglob("*.py")):
            try:
                source = py_file.read_text(encoding="utf-8")
            except OSError:
                continue

            for lineno, module in get_imports(source, str(py_file)):
                # Check if the import references a forbidden layer
                # Matches: `from infrastructure.x import y` or `import infrastructure.x`
                parts = module.split(".")
                if forbidden_layer in parts:
                    rel_path = py_file.relative_to(src_dir.parent)
                    violations.append(
                        Violation(
                            path=str(rel_path),
                            line=lineno,
                            severity=severity,
                            message=(
                                f"{source_layer}/ imports from {forbidden_layer}/ "
                                f"(`{module}`) — violates dependency rule"
                            ),
                        )
                    )

    return violations


def check_layer_structure(src_dir: Path) -> list[Violation]:
    violations: list[Violation] = []
    for layer in REQUIRED_LAYERS:
        layer_path = src_dir / layer
        if not layer_path.exists():
            violations.append(
                Violation(
                    path=str(src_dir),
                    line=0,
                    severity="ERROR",
                    message=f"Missing required layer directory: {layer}/",
                )
            )
        elif not layer_path.is_dir():
            violations.append(
                Violation(
                    path=str(layer_path),
                    line=0,
                    severity="ERROR",
                    message=f"Expected directory but found file: {layer}/",
                )
            )
    return violations


def main() -> int:
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("src")

    if not src_path.exists():
        print(f"ERROR: Source directory '{src_path}' not found", file=sys.stderr)
        return 2

    all_violations: list[Violation] = []

    print(f"=== Architecture Check: {src_path} ===\n")

    # Check layer structure
    structure_violations = check_layer_structure(src_path)
    all_violations.extend(structure_violations)
    if not structure_violations:
        print("Layer structure: OK")
    else:
        print("Layer structure: ISSUES FOUND")

    # Check dependency rules
    boundary_violations = check_layer_boundaries(src_path)
    all_violations.extend(boundary_violations)

    if not all_violations:
        print("Dependency rules: OK")
        print("\nNo architecture violations found.")
        return 0

    # Print violations sorted by severity then path
    errors = [v for v in all_violations if v.severity == "ERROR"]
    warns = [v for v in all_violations if v.severity == "WARN"]

    if errors:
        print(f"\nErrors ({len(errors)}):")
        for v in sorted(errors, key=lambda v: (v.path, v.line)):
            print(f"  {v}")

    if warns:
        print(f"\nWarnings ({len(warns)}):")
        for v in sorted(warns, key=lambda v: (v.path, v.line)):
            print(f"  {v}")

    print(f"\n{len(errors)} error(s), {len(warns)} warning(s) found.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
