#!/usr/bin/env python3
"""
complexity_check.py --- Check cyclomatic complexity of Python files.

Usage:
    python complexity_check.py src/
    python complexity_check.py src/ --threshold 10
    python complexity_check.py src/ --json

Requires: radon (pip install radon)
Falls back to AST-based analysis if radon is not installed.

Exit codes:
  0 --- all functions below threshold
  1 --- functions exceeding threshold found
  2 --- usage error
"""

from __future__ import annotations

import argparse
import ast
import json
import sys
from dataclasses import dataclass
from pathlib import Path

@dataclass
class ComplexityResult:
    file: str
    function: str
    line: int
    complexity: int
    grade: str

    def __str__(self) -> str:
        return (
            f"  {self.grade} {self.file}:{self.line} "
            f"{self.function} (complexity: {self.complexity})"
        )

def grade_complexity(cc: int) -> str:
    if cc <= 5:
        return "A"
    if cc <= 10:
        return "B"
    if cc <= 20:
        return "C"
    if cc <= 30:
        return "D"
    return "F"

class ComplexityVisitor(ast.NodeVisitor):
    """Simple McCabe complexity calculator using AST."""

    def __init__(self, file_path: str):
        self.file_path = file_path
        self.results: list[ComplexityResult] = []

    def _count_complexity(self, node: ast.AST) -> int:
        """Count decision points in a function body."""
        count = 1  # base complexity
        for child in ast.walk(node):
            if isinstance(child, (ast.If, ast.While, ast.For)):
                count += 1
            elif isinstance(child, ast.BoolOp):
                count += len(child.values) - 1
            elif isinstance(child, ast.ExceptHandler):
                count += 1
            elif isinstance(child, ast.Assert):
                count += 1
            elif isinstance(child, (ast.ListComp, ast.SetComp, ast.GeneratorExp, ast.DictComp)):
                count += sum(1 for _ in child.generators)
        return count

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        cc = self._count_complexity(node)
        self.results.append(ComplexityResult(
            file=self.file_path,
            function=node.name,
            line=node.lineno,
            complexity=cc,
            grade=grade_complexity(cc),
        ))
        self.generic_visit(node)

    visit_AsyncFunctionDef = visit_FunctionDef

def analyse_file(path: Path) -> list[ComplexityResult]:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError:
        return []

    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError:
        return []

    visitor = ComplexityVisitor(str(path))
    visitor.visit(tree)
    return visitor.results

def main() -> int:
    parser = argparse.ArgumentParser(description="Cyclomatic complexity checker")
    parser.add_argument("path", type=Path, help="File or directory to analyse")
    parser.add_argument("--threshold", type=int, default=10, help="Complexity threshold (default: 10)")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()

    all_results: list[ComplexityResult] = []

    if args.path.is_file():
        all_results.extend(analyse_file(args.path))
    elif args.path.is_dir():
        for f in sorted(args.path.rglob("*.py")):
            all_results.extend(analyse_file(f))
    else:
        print(f"ERROR: {args.path} not found", file=sys.stderr)
        return 2

    # Sort by complexity descending
    all_results.sort(key=lambda r: r.complexity, reverse=True)

    violations = [r for r in all_results if r.complexity > args.threshold]

    if args.json:
        output = {
            "threshold": args.threshold,
            "total_functions": len(all_results),
            "violations": len(violations),
            "results": [
                {
                    "file": r.file,
                    "function": r.function,
                    "line": r.line,
                    "complexity": r.complexity,
                    "grade": r.grade,
                }
                for r in all_results
                if r.complexity > args.threshold
            ],
        }
        json.dump(output, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print(f"\n=== Complexity Report (threshold: {args.threshold}) ===\n")
        print(f"Functions analysed: {len(all_results)}")
        print(f"Violations (> {args.threshold}): {len(violations)}")
        print()

        if violations:
            print("Functions exceeding threshold:")
            for r in violations:
                print(r)
            print()

        # Summary by grade
        grades = {"A": 0, "B": 0, "C": 0, "D": 0, "F": 0}
        for r in all_results:
            grades[r.grade] = grades.get(r.grade, 0) + 1
        print("Grade distribution:")
        for g in ("A", "B", "C", "D", "F"):
            if grades[g] > 0:
                print(f"  {g}: {grades[g]}")

    return 1 if violations else 0

if __name__ == "__main__":
    sys.exit(main())
