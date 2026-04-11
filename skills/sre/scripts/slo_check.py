#!/usr/bin/env python3
"""
slo_check.py — Validate Prometheus alerting rules for SLO compliance.

Usage:
    python slo_check.py prometheus-rules.yaml [another.yaml ...]

Validates each alert rule has:
  - expr
  - for (evaluation window)
  - labels.severity
  - annotations.summary
  - annotations.description
  - annotations.runbook_url

Exit codes:
  0 — all rules compliant
  1 — one or more rules fail validation
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import yaml
    def _load_yaml(text: str) -> object:
        return yaml.safe_load(text)
except ImportError:
    import json
    def _load_yaml(text: str) -> object:
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            # Minimal YAML parser for simple cases
            raise ImportError(
                "PyYAML is required for YAML files: pip install pyyaml\n"
                "Alternatively, provide JSON-format rules."
            )

REQUIRED_ANNOTATIONS = ["summary", "description", "runbook_url"]
REQUIRED_LABELS = ["severity"]
VALID_SEVERITIES = {"critical", "warning", "info", "page"}

@dataclass
class RuleViolation:
    file: str
    group: str
    rule_name: str
    field: str
    message: str

    def __str__(self) -> str:
        return (
            f"  [FAIL] {self.file} "
            f"group={self.group!r} "
            f"alert={self.rule_name!r}: "
            f"{self.field} — {self.message}"
        )

@dataclass
class RulePass:
    file: str
    group: str
    rule_name: str

    def __str__(self) -> str:
        return f"  [PASS] {self.file} group={self.group!r} alert={self.rule_name!r}"

def validate_rule(
    rule: dict,
    group_name: str,
    file_path: str,
) -> list[RuleViolation]:
    violations: list[RuleViolation] = []
    rule_name = rule.get("alert", "<unnamed>")

    def fail(field: str, msg: str) -> None:
        violations.append(RuleViolation(
            file=file_path, group=group_name, rule_name=rule_name, field=field, message=msg
        ))

    # Required top-level fields
    if not rule.get("expr"):
        fail("expr", "missing or empty — the alert expression is required")

    if not rule.get("for"):
        fail("for", "missing — specify evaluation window (e.g. '5m')")

    # Labels
    labels = rule.get("labels") or {}
    if not isinstance(labels, dict):
        fail("labels", "must be a mapping")
    else:
        for required_label in REQUIRED_LABELS:
            if not labels.get(required_label):
                fail(f"labels.{required_label}", f"missing — add labels.{required_label}")

        severity = labels.get("severity", "")
        if severity and severity not in VALID_SEVERITIES:
            fail(
                "labels.severity",
                f"'{severity}' is not a standard severity. Use: {sorted(VALID_SEVERITIES)}",
            )

    # Annotations
    annotations = rule.get("annotations") or {}
    if not isinstance(annotations, dict):
        fail("annotations", "must be a mapping")
    else:
        for required_ann in REQUIRED_ANNOTATIONS:
            value = annotations.get(required_ann, "")
            if not value or not str(value).strip():
                fail(f"annotations.{required_ann}", f"missing or empty")

        # Validate runbook_url is actually a URL
        runbook = annotations.get("runbook_url", "")
        if runbook and not str(runbook).startswith(("http://", "https://")):
            fail(
                "annotations.runbook_url",
                f"'{runbook}' does not look like a URL — must start with http(s)://",
            )

    return violations

def validate_file(path: Path) -> tuple[list[RuleViolation], list[RulePass]]:
    violations: list[RuleViolation] = []
    passes: list[RulePass] = []

    try:
        content = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: Cannot read {path}: {exc}", file=sys.stderr)
        return violations, passes

    try:
        doc = _load_yaml(content)
    except Exception as exc:
        print(f"ERROR: Cannot parse {path}: {exc}", file=sys.stderr)
        return violations, passes

    if not isinstance(doc, dict):
        print(f"ERROR: {path} — expected a YAML mapping at root", file=sys.stderr)
        return violations, passes

    groups = doc.get("groups", [])
    if not groups:
        print(f"WARNING: {path} — no groups found", file=sys.stderr)
        return violations, passes

    for group in groups:
        if not isinstance(group, dict):
            continue
        group_name = group.get("name", "<unnamed>")
        rules = group.get("rules", [])

        for rule in rules:
            if not isinstance(rule, dict):
                continue
            if "alert" not in rule:
                continue  # Recording rule, not alert — skip

            rule_violations = validate_rule(rule, group_name, str(path))
            if rule_violations:
                violations.extend(rule_violations)
            else:
                passes.append(RulePass(
                    file=str(path),
                    group=group_name,
                    rule_name=rule.get("alert", "<unnamed>"),
                ))

    return violations, passes

def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <rules.yaml> [...]", file=sys.stderr)
        return 2

    all_violations: list[RuleViolation] = []
    all_passes: list[RulePass] = []

    for arg in sys.argv[1:]:
        p = Path(arg)
        if p.is_dir():
            for f in sorted(p.rglob("*.yaml")) + sorted(p.rglob("*.yml")):
                v, ps = validate_file(f)
                all_violations.extend(v)
                all_passes.extend(ps)
        elif p.exists():
            v, ps = validate_file(p)
            all_violations.extend(v)
            all_passes.extend(ps)
        else:
            print(f"ERROR: File not found: {p}", file=sys.stderr)

    total = len(all_violations) + len(all_passes)
    print(f"\n=== Prometheus Alert Rule SLO Compliance Report ===\n")
    print(f"Rules checked: {total}")
    print(f"  Passing:  {len(all_passes)}")
    print(f"  Failing:  {len(all_violations)}")
    print()

    for p in all_passes:
        print(p)

    if all_violations:
        print()
        for v in all_violations:
            print(v)
        print(f"\n{len(all_violations)} compliance failure(s) found.")
        return 1

    print("\nAll alert rules are SLO-compliant.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
