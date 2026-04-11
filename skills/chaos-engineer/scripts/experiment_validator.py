#!/usr/bin/env python3
"""
experiment_validator.py --- Validate Chaos Toolkit experiment JSON files.

Usage:
    python experiment_validator.py experiment.json [another.json ...]

Validates:
  - Required top-level fields (title, steady-state-hypothesis, method, rollbacks)
  - Hypothesis has at least one probe
  - Method has at least one action
  - Rollbacks are defined
  - All probes and actions have provider configuration

Exit codes:
  0 --- all experiments valid
  1 --- validation failures found
  2 --- usage error
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path

@dataclass
class ValidationError:
    file: str
    field: str
    message: str

    def __str__(self) -> str:
        return f"  [FAIL] {self.file}: {self.field} — {self.message}"

def validate_experiment(data: dict, file_path: str) -> list[ValidationError]:
    errors: list[ValidationError] = []

    def fail(field: str, msg: str) -> None:
        errors.append(ValidationError(file=file_path, field=field, message=msg))

    # Required top-level fields
    if not data.get("title"):
        fail("title", "missing or empty")

    # Steady-state hypothesis
    hypothesis = data.get("steady-state-hypothesis")
    if not hypothesis:
        fail("steady-state-hypothesis", "missing — every experiment needs a hypothesis")
    elif not isinstance(hypothesis, dict):
        fail("steady-state-hypothesis", "must be a mapping")
    else:
        if not hypothesis.get("title"):
            fail("steady-state-hypothesis.title", "missing or empty")
        probes = hypothesis.get("probes", [])
        if not probes:
            fail("steady-state-hypothesis.probes", "no probes defined — need at least one")
        for i, probe in enumerate(probes):
            if not probe.get("name"):
                fail(f"steady-state-hypothesis.probes[{i}].name", "missing")
            if not probe.get("provider"):
                fail(f"steady-state-hypothesis.probes[{i}].provider", "missing provider configuration")
            elif not probe["provider"].get("type"):
                fail(f"steady-state-hypothesis.probes[{i}].provider.type", "missing provider type")

    # Method (actions)
    method = data.get("method", [])
    if not method:
        fail("method", "no actions defined — need at least one")
    for i, action in enumerate(method):
        if not action.get("name"):
            fail(f"method[{i}].name", "missing")
        if not action.get("provider"):
            fail(f"method[{i}].provider", "missing provider configuration")

    # Rollbacks
    rollbacks = data.get("rollbacks", [])
    if not rollbacks:
        fail("rollbacks", "no rollbacks defined — every experiment needs a rollback plan")
    for i, rollback in enumerate(rollbacks):
        if not rollback.get("name"):
            fail(f"rollbacks[{i}].name", "missing")
        if not rollback.get("provider"):
            fail(f"rollbacks[{i}].provider", "missing provider configuration")

    # Tags (recommended)
    if not data.get("tags"):
        fail("tags", "missing — tags help categorise experiments (warning, not blocking)")

    return errors

def validate_file(path: Path) -> list[ValidationError]:
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as exc:
        return [ValidationError(str(path), "file", f"cannot read: {exc}")]

    try:
        data = json.loads(content)
    except json.JSONDecodeError as exc:
        return [ValidationError(str(path), "json", f"invalid JSON: {exc}")]

    if not isinstance(data, dict):
        return [ValidationError(str(path), "root", "expected a JSON object at root")]

    return validate_experiment(data, str(path))

def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <experiment.json> [...]", file=sys.stderr)
        return 2

    all_errors: list[ValidationError] = []
    files_checked = 0

    for arg in sys.argv[1:]:
        p = Path(arg)
        if p.is_dir():
            for f in sorted(p.rglob("*.json")):
                errors = validate_file(f)
                all_errors.extend(errors)
                files_checked += 1
        elif p.exists():
            errors = validate_file(p)
            all_errors.extend(errors)
            files_checked += 1
        else:
            print(f"ERROR: File not found: {p}", file=sys.stderr)

    print(f"\n=== Chaos Experiment Validation Report ===\n")
    print(f"Files checked: {files_checked}")
    print(f"Errors found:  {len(all_errors)}")
    print()

    if all_errors:
        for e in all_errors:
            print(e)
        return 1

    print("All experiments are valid.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
