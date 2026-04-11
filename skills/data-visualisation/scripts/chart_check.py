#!/usr/bin/env python3
"""
chart_check.py — Static analysis for Python data visualisation files.

Usage:
    python chart_check.py path/to/charts.py [another.py ...]

Checks:
  - Missing axis labels (no xlabel/ylabel/set_xlabel/set_ylabel calls)
  - Missing plot titles (no title/set_title calls)
  - Use of 3D plots (Axes3D, plot_surface, scatter3D) — warn: complexity without clarity
  - Rainbow/jet colormaps (not accessible to colour-blind users)
  - plt.show() without plt.savefig() in script context (not reproducible)

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

# Colormaps that are not accessible to colour-blind users
INACCESSIBLE_COLORMAPS = {
    "jet", "rainbow", "hsv", "gist_rainbow", "spectral",
    "Spectral",  # diverging but often misused
    "gist_ncar", "nipy_spectral",
}

# Recognised label-setting call names
XLABEL_CALLS = {"xlabel", "set_xlabel"}
YLABEL_CALLS = {"ylabel", "set_ylabel"}
TITLE_CALLS = {"title", "set_title", "suptitle"}
THREE_D_INDICATORS = {"Axes3D", "plot_surface", "plot_wireframe", "scatter3D", "bar3d", "mpl_toolkits"}

class ChartChecker(ast.NodeVisitor):
    def __init__(self, path: str, source_lines: list[str]) -> None:
        self.path = path
        self.source_lines = source_lines
        self.issues: list[Issue] = []

        self._has_xlabel = False
        self._has_ylabel = False
        self._has_title = False
        self._has_plot_call = False
        self._has_3d = False
        self._has_savefig = False
        self._has_show = False
        self._show_line = 0

    def _issue(self, lineno: int, code: str, severity: str, message: str) -> None:
        self.issues.append(Issue(self.path, lineno, code, severity, message))

    def visit_Call(self, node: ast.Call) -> None:  # noqa: N802
        func_name = self._get_func_name(node)

        if func_name in XLABEL_CALLS:
            self._has_xlabel = True

        if func_name in YLABEL_CALLS:
            self._has_ylabel = True

        if func_name in TITLE_CALLS:
            self._has_title = True

        if func_name in ("plot", "scatter", "bar", "barh", "hist", "pie",
                         "heatmap", "lineplot", "scatterplot", "boxplot",
                         "violinplot", "imshow", "pcolormesh", "contourf"):
            self._has_plot_call = True

            # Check colormap arguments
            for keyword in node.keywords:
                if keyword.arg in ("cmap", "colormap"):
                    cmap_name = self._extract_string_value(keyword.value)
                    if cmap_name and cmap_name in INACCESSIBLE_COLORMAPS:
                        self._issue(
                            node.lineno, "VIZ003", "WARN",
                            f"Colourmap '{cmap_name}' is not accessible to colour-blind users. "
                            f"Use viridis, plasma, cividis, or colorbrewer palettes instead",
                        )

        if func_name == "savefig":
            self._has_savefig = True

        if func_name == "show":
            self._has_show = True
            self._show_line = node.lineno

        # 3D check
        if func_name in THREE_D_INDICATORS or any(
            indicator in func_name for indicator in THREE_D_INDICATORS
        ):
            self._has_3d = True
            self._issue(
                node.lineno, "VIZ004", "WARN",
                f"3D chart ({func_name}): 3D plots are rarely clearer than 2D alternatives. "
                f"Consider a 2D heatmap or small multiples",
            )

        self.generic_visit(node)

    def visit_Import(self, node: ast.Import) -> None:  # noqa: N802
        for alias in node.names:
            if "mpl_toolkits" in alias.name:
                self._has_3d = True
                self._issue(
                    node.lineno, "VIZ004", "WARN",
                    "mpl_toolkits.mplot3d imported: 3D plots are often harder to read than 2D alternatives",
                )
        self.generic_visit(node)

    def _get_func_name(self, node: ast.Call) -> str:
        if isinstance(node.func, ast.Name):
            return node.func.id
        if isinstance(node.func, ast.Attribute):
            return node.func.attr
        return ""

    def _extract_string_value(self, node: ast.expr) -> str | None:
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        return None

    def finalise(self) -> None:
        """Report aggregate issues after visiting the whole file."""
        if self._has_plot_call:
            if not self._has_xlabel:
                self.issues.append(Issue(
                    self.path, 0, "VIZ001", "WARN",
                    "No xlabel/set_xlabel call found — add x-axis label for readability",
                ))
            if not self._has_ylabel:
                self.issues.append(Issue(
                    self.path, 0, "VIZ001", "WARN",
                    "No ylabel/set_ylabel call found — add y-axis label for readability",
                ))
            if not self._has_title:
                self.issues.append(Issue(
                    self.path, 0, "VIZ002", "WARN",
                    "No title/set_title/suptitle call found — add a descriptive chart title",
                ))
            if self._has_show and not self._has_savefig:
                self.issues.append(Issue(
                    self.path, self._show_line, "VIZ005", "INFO",
                    "plt.show() called without plt.savefig() — charts won't be reproducibly saved. "
                    "Add savefig() before show() in script context",
                ))

def check_file(path: Path) -> list[Issue]:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: Cannot read {path}: {exc}", file=sys.stderr)
        return []

    # Quick pre-check — skip files with no matplotlib/seaborn/plotly imports
    if not any(
        lib in source
        for lib in ("matplotlib", "seaborn", "plotly", "altair", "plt", "sns")
    ):
        return []

    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        print(f"ERROR: Syntax error in {path}: {exc}", file=sys.stderr)
        return []

    checker = ChartChecker(path=str(path), source_lines=source.splitlines())
    checker.visit(tree)
    checker.finalise()
    return checker.issues

def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <file.py> [file.py ...]", file=sys.stderr)
        return 2

    all_issues: list[Issue] = []
    for arg in sys.argv[1:]:
        p = Path(arg)
        if p.is_dir():
            for py_file in sorted(p.rglob("*.py")):
                all_issues.extend(check_file(py_file))
        else:
            all_issues.extend(check_file(p))

    warns = [i for i in all_issues if i.severity in ("WARN", "ERROR")]
    infos = [i for i in all_issues if i.severity == "INFO"]

    for issue in sorted(all_issues, key=lambda i: (i.path, i.line)):
        print(issue)

    if all_issues:
        print(f"\n{len(warns)} warning(s), {len(infos)} info(s).", file=sys.stderr)
        return 1 if warns else 0

    print("No chart issues found.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
