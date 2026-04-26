#!/usr/bin/env python3
"""
quality_check.py — Validate a dbt project directory structure.

Checks for the presence of required files and conventions:
  - dbt_project.yml at root
  - profiles.yml existence hint
  - models/ directory with staging/, intermediate/, marts/ subdirectories
  - At least one sources.yml in models/staging/
  - schema.yml files in each model layer
  - tests/ directory
  - macros/ directory
  - packages.yml (optional, warns if absent)
  - Column-level tests in schema.yml files (not_null, unique at minimum)

Usage:
    python quality_check.py [project_dir]
    python quality_check.py /path/to/my_dbt_project

Exit code: 0 = all required checks passed, 1 = one or more required checks failed.
"""

import os
import sys
import re
from pathlib import Path
from typing import NamedTuple


class CheckResult(NamedTuple):
    name: str
    passed: bool
    severity: str  # "required" | "recommended" | "optional"
    detail: str


def find_yaml_files(directory: Path, pattern: str) -> list[Path]:
    """Recursively find YAML files matching a name pattern."""
    matches = []
    for ext in ("*.yml", "*.yaml"):
        matches.extend(directory.rglob(ext))
    return [f for f in matches if re.search(pattern, f.name, re.IGNORECASE)]


def check_file_contains(filepath: Path, pattern: str) -> bool:
    """Return True if the file contains the given regex pattern."""
    try:
        content = filepath.read_text(encoding="utf-8")
        return bool(re.search(pattern, content))
    except (OSError, UnicodeDecodeError):
        return False


def count_schema_tests(schema_files: list[Path]) -> dict[str, int]:
    """Count occurrences of each built-in dbt test across schema files."""
    counts: dict[str, int] = {
        "not_null": 0,
        "unique": 0,
        "relationships": 0,
        "accepted_values": 0,
    }
    for f in schema_files:
        try:
            content = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for test in counts:
            counts[test] += len(re.findall(rf"\b{test}\b", content))
    return counts


def run_checks(project_dir: Path) -> list[CheckResult]:
    results: list[CheckResult] = []

    def add(name: str, passed: bool, severity: str, detail: str) -> None:
        results.append(CheckResult(name, passed, severity, detail))

    # ── Root structure ────────────────────────────────────────────────────────
    dbt_project_yml = project_dir / "dbt_project.yml"
    add(
        "dbt_project.yml exists",
        dbt_project_yml.is_file(),
        "required",
        str(dbt_project_yml),
    )

    packages_yml = project_dir / "packages.yml"
    add(
        "packages.yml exists",
        packages_yml.is_file(),
        "recommended",
        "Declare dbt package dependencies in packages.yml",
    )

    # ── models/ ───────────────────────────────────────────────────────────────
    models_dir = project_dir / "models"
    add(
        "models/ directory exists",
        models_dir.is_dir(),
        "required",
        str(models_dir),
    )

    for layer in ("staging", "intermediate", "marts"):
        layer_dir = models_dir / layer
        add(
            f"models/{layer}/ layer exists",
            layer_dir.is_dir(),
            "recommended",
            f"Medallion layer directory: {layer_dir}",
        )

    # ── sources.yml ───────────────────────────────────────────────────────────
    source_files = find_yaml_files(models_dir, r"^sources?\.ya?ml$") if models_dir.is_dir() else []
    add(
        "sources.yml present in models/",
        len(source_files) > 0,
        "required",
        f"Found {len(source_files)} sources file(s): "
        + (", ".join(str(f.relative_to(project_dir)) for f in source_files[:3]) or "none"),
    )

    if source_files:
        has_freshness = any(
            check_file_contains(f, r"\bfreshness\b") for f in source_files
        )
        add(
            "sources.yml defines freshness checks",
            has_freshness,
            "recommended",
            "Add `freshness:` blocks to source definitions to enable SLO monitoring",
        )

    # ── schema.yml ────────────────────────────────────────────────────────────
    schema_files = find_yaml_files(models_dir, r"^schema\.ya?ml$") if models_dir.is_dir() else []
    add(
        "schema.yml present in models/",
        len(schema_files) > 0,
        "required",
        f"Found {len(schema_files)} schema file(s): "
        + (", ".join(str(f.relative_to(project_dir)) for f in schema_files[:3]) or "none"),
    )

    # ── Column-level tests ────────────────────────────────────────────────────
    if schema_files:
        test_counts = count_schema_tests(schema_files)
        add(
            "not_null tests defined",
            test_counts["not_null"] > 0,
            "required",
            f"not_null test count: {test_counts['not_null']}",
        )
        add(
            "unique tests defined",
            test_counts["unique"] > 0,
            "required",
            f"unique test count: {test_counts['unique']}",
        )
        add(
            "relationships tests defined",
            test_counts["relationships"] > 0,
            "recommended",
            f"relationships test count: {test_counts['relationships']}",
        )
        add(
            "accepted_values tests defined",
            test_counts["accepted_values"] > 0,
            "optional",
            f"accepted_values test count: {test_counts['accepted_values']}",
        )

    # ── tests/ directory ──────────────────────────────────────────────────────
    tests_dir = project_dir / "tests"
    add(
        "tests/ directory exists",
        tests_dir.is_dir(),
        "recommended",
        "Singular SQL tests live here",
    )

    # ── macros/ directory ─────────────────────────────────────────────────────
    macros_dir = project_dir / "macros"
    add(
        "macros/ directory exists",
        macros_dir.is_dir(),
        "optional",
        str(macros_dir),
    )

    # ── Incremental models ────────────────────────────────────────────────────
    sql_files: list[Path] = []
    if models_dir.is_dir():
        sql_files = list(models_dir.rglob("*.sql"))

    incremental_models = [
        f for f in sql_files if check_file_contains(f, r"materialized\s*=\s*['\"]incremental['\"]")
    ]
    if incremental_models:
        missing_unique_key = [
            f for f in incremental_models
            if not check_file_contains(f, r"unique_key")
        ]
        add(
            "Incremental models have unique_key",
            len(missing_unique_key) == 0,
            "required",
            f"{len(incremental_models)} incremental model(s) found; "
            f"{len(missing_unique_key)} missing unique_key: "
            + ", ".join(str(f.relative_to(project_dir)) for f in missing_unique_key[:3]),
        )

    # ── No hardcoded credentials ──────────────────────────────────────────────
    credential_pattern = r"password\s*=\s*['\"][^'\"]{4,}"
    offending_files = [
        f for f in (sql_files + schema_files + source_files)
        if check_file_contains(f, credential_pattern)
    ]
    add(
        "No hardcoded passwords in SQL/YAML",
        len(offending_files) == 0,
        "required",
        f"Suspicious files: "
        + (", ".join(str(f.relative_to(project_dir)) for f in offending_files) or "none"),
    )

    # ── Snapshots ─────────────────────────────────────────────────────────────
    snapshots_dir = project_dir / "snapshots"
    if snapshots_dir.is_dir():
        snap_files = list(snapshots_dir.rglob("*.sql"))
        missing_strategy = [
            f for f in snap_files
            if not check_file_contains(f, r"strategy\s*=")
        ]
        add(
            "Snapshots define strategy",
            len(missing_strategy) == 0,
            "required",
            f"{len(snap_files)} snapshot(s) found; "
            f"{len(missing_strategy)} missing strategy config",
        )

    return results


def print_report(results: list[CheckResult], project_dir: Path) -> int:
    """Print the compliance report. Returns exit code (0=pass, 1=fail)."""
    required_failures = [r for r in results if not r.passed and r.severity == "required"]
    recommended_failures = [r for r in results if not r.passed and r.severity == "recommended"]
    optional_failures = [r for r in results if not r.passed and r.severity == "optional"]
    passed = [r for r in results if r.passed]

    width = 72
    sep = "─" * width

    print(f"\n{'═' * width}")
    print(f"  dbt Project Quality Report")
    print(f"  Project: {project_dir.resolve()}")
    print(f"{'═' * width}")

    if passed:
        print(f"\n  ✓ PASSED ({len(passed)})")
        print(sep)
        for r in passed:
            label = f"[{r.severity.upper()[:3]}]"
            print(f"  ✓ {label:<6} {r.name}")

    if required_failures:
        print(f"\n  ✗ FAILED — REQUIRED ({len(required_failures)})")
        print(sep)
        for r in required_failures:
            print(f"  ✗ [REQ]   {r.name}")
            print(f"            → {r.detail}")

    if recommended_failures:
        print(f"\n  ⚠ FAILED — RECOMMENDED ({len(recommended_failures)})")
        print(sep)
        for r in recommended_failures:
            print(f"  ⚠ [REC]   {r.name}")
            print(f"            → {r.detail}")

    if optional_failures:
        print(f"\n  · FAILED — OPTIONAL ({len(optional_failures)})")
        print(sep)
        for r in optional_failures:
            print(f"  · [OPT]   {r.name}")
            print(f"            → {r.detail}")

    total = len(results)
    passed_count = len(passed)
    print(f"\n{'═' * width}")
    print(f"  Total: {total}  |  Passed: {passed_count}  |  "
          f"Required failures: {len(required_failures)}  |  "
          f"Recommended failures: {len(recommended_failures)}")

    if required_failures:
        print(f"\n  RESULT: FAIL — {len(required_failures)} required check(s) not met.")
    else:
        print(f"\n  RESULT: PASS — All required checks satisfied.")
    print(f"{'═' * width}\n")

    return 1 if required_failures else 0


def main() -> int:
    project_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()

    if not project_dir.exists():
        print(f"ERROR: Directory not found: {project_dir}", file=sys.stderr)
        return 1

    if not project_dir.is_dir():
        print(f"ERROR: Not a directory: {project_dir}", file=sys.stderr)
        return 1

    results = run_checks(project_dir)
    return print_report(results, project_dir)


if __name__ == "__main__":
    sys.exit(main())
