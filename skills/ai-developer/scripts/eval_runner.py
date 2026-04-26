#!/usr/bin/env python3
"""
eval_runner.py — Run evals against a JSONL dataset.

Input file format (one JSON object per line):
    {"id": "q001", "input": "...", "expected": "...", "actual": "..."}
    {"id": "q002", "input": "...", "expected": "...", "actual": "...", "match_type": "contains"}

Supported match types:
    "exact"    — strip + lowercase equality (default)
    "contains" — expected string is a substring of actual
    "any"      — passes if actual matches ANY of the expected values
               (expected must be a JSON array string: '["a", "b"]')

Usage:
    python eval_runner.py results.jsonl
    python eval_runner.py results.jsonl --verbose
    cat results.jsonl | python eval_runner.py -

Exit code: 0 = all evals passed, 1 = one or more evals failed.
"""

import json
import sys
import re
from typing import Any


# ── Match functions ────────────────────────────────────────────────────────────

def exact_match(actual: str, expected: str) -> bool:
    return actual.strip().lower() == expected.strip().lower()


def contains_match(actual: str, expected: str) -> bool:
    return expected.strip().lower() in actual.strip().lower()


def any_match(actual: str, expected: str) -> bool:
    """Pass if actual matches any value in a JSON array string."""
    try:
        candidates = json.loads(expected)
        if not isinstance(candidates, list):
            return exact_match(actual, expected)
    except (json.JSONDecodeError, ValueError):
        return exact_match(actual, expected)
    return any(
        actual.strip().lower() == str(candidate).strip().lower()
        for candidate in candidates
    )


MATCH_FUNCTIONS = {
    "exact": exact_match,
    "contains": contains_match,
    "any": any_match,
}


# ── Result types ───────────────────────────────────────────────────────────────

class EvalRecord:
    __slots__ = ("id", "input", "expected", "actual", "match_type", "passed", "raw")

    def __init__(self, raw: dict[str, Any]) -> None:
        self.raw = raw
        self.id: str = str(raw.get("id", "?"))
        self.input: str = str(raw.get("input", ""))
        self.expected: str = str(raw.get("expected", ""))
        self.actual: str = str(raw.get("actual", ""))
        self.match_type: str = str(raw.get("match_type", "exact")).lower()
        self.passed: bool = False

    def evaluate(self) -> None:
        fn = MATCH_FUNCTIONS.get(self.match_type, exact_match)
        self.passed = fn(self.actual, self.expected)


# ── Loading ────────────────────────────────────────────────────────────────────

def load_records(source: Any) -> list[EvalRecord]:
    """Read JSONL records from a file object. Skip blank lines and comments (#)."""
    records: list[EvalRecord] = []
    errors: list[str] = []
    for lineno, line in enumerate(source, start=1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append(f"  Line {lineno}: {exc}")
            continue

        required_fields = {"input", "expected", "actual"}
        missing = required_fields - set(data.keys())
        if missing:
            errors.append(f"  Line {lineno}: missing required fields: {sorted(missing)}")
            continue

        records.append(EvalRecord(data))

    if errors:
        print(f"\nWARNING: {len(errors)} line(s) skipped due to parse errors:", file=sys.stderr)
        for e in errors[:10]:
            print(e, file=sys.stderr)
        if len(errors) > 10:
            print(f"  ... and {len(errors) - 10} more", file=sys.stderr)

    return records


# ── Reporting ─────────────────────────────────────────────────────────────────

def print_summary_table(records: list[EvalRecord], verbose: bool) -> int:
    """Print the eval results table. Returns exit code."""
    passed = [r for r in records if r.passed]
    failed = [r for r in records if not r.passed]
    total = len(records)
    pass_rate = len(passed) / total if total > 0 else 0.0

    # Break down by match type
    by_type: dict[str, dict[str, int]] = {}
    for r in records:
        bt = by_type.setdefault(r.match_type, {"pass": 0, "fail": 0})
        bt["pass" if r.passed else "fail"] += 1

    width = 72
    sep = "─" * width

    print(f"\n{'═' * width}")
    print("  Eval Runner — Results Summary")
    print(f"{'═' * width}")

    # Per-type breakdown
    print(f"\n  {'Match Type':<16} {'Pass':>6} {'Fail':>6} {'Total':>6} {'Rate':>8}")
    print(f"  {sep}")
    for mtype, counts in sorted(by_type.items()):
        t = counts["pass"] + counts["fail"]
        rate = counts["pass"] / t if t > 0 else 0.0
        print(f"  {mtype:<16} {counts['pass']:>6} {counts['fail']:>6} {t:>6} {rate:>7.1%}")
    print(f"  {sep}")
    print(f"  {'TOTAL':<16} {len(passed):>6} {len(failed):>6} {total:>6} {pass_rate:>7.1%}")

    # Failures detail
    if failed:
        print(f"\n  FAILURES ({len(failed)})")
        print(f"  {sep}")
        col_id = 10
        col_exp = 28
        col_act = 28
        header = f"  {'ID':<{col_id}}  {'Expected':<{col_exp}}  {'Actual':<{col_act}}  Type"
        print(header)
        print(f"  {sep}")
        for r in failed:
            eid = (r.id[:col_id - 1] + "…") if len(r.id) > col_id else r.id
            exp = (r.expected[:col_exp - 1] + "…") if len(r.expected) > col_exp else r.expected
            act = (r.actual[:col_act - 1] + "…") if len(r.actual) > col_act else r.actual
            print(f"  {eid:<{col_id}}  {exp:<{col_exp}}  {act:<{col_act}}  {r.match_type}")

    # Verbose: also print passed
    if verbose and passed:
        print(f"\n  PASSED ({len(passed)})")
        print(f"  {sep}")
        for r in passed:
            eid = (r.id[:10] + "…") if len(r.id) > 10 else r.id
            exp = (r.expected[:30] + "…") if len(r.expected) > 30 else r.expected
            print(f"  ✓ [{eid:<10}]  expected: {exp}")

    # Final verdict
    print(f"\n{'═' * width}")
    if len(failed) == 0:
        print(f"  RESULT: PASS — {total}/{total} evals passed ({pass_rate:.1%})")
    else:
        print(f"  RESULT: FAIL — {len(failed)}/{total} eval(s) failed ({pass_rate:.1%} pass rate)")
    print(f"{'═' * width}\n")

    return 0 if len(failed) == 0 else 1


# ── CLI entry point ────────────────────────────────────────────────────────────

def main() -> int:
    args = sys.argv[1:]
    verbose = "--verbose" in args or "-v" in args
    args = [a for a in args if a not in ("--verbose", "-v")]

    filepath = args[0] if args else None

    if filepath == "-" or (filepath is None and not sys.stdin.isatty()):
        records = load_records(sys.stdin)
    elif filepath is not None:
        try:
            with open(filepath, encoding="utf-8") as fh:
                records = load_records(fh)
        except OSError as exc:
            print(f"ERROR: Cannot open file '{filepath}': {exc}", file=sys.stderr)
            return 1
    else:
        print(f"Usage: {sys.argv[0]} <evals.jsonl> [--verbose]", file=sys.stderr)
        print(f"       cat evals.jsonl | {sys.argv[0]} -", file=sys.stderr)
        return 1

    if not records:
        print("ERROR: No valid eval records found in input.", file=sys.stderr)
        return 1

    for record in records:
        record.evaluate()

    return print_summary_table(records, verbose=verbose)


if __name__ == "__main__":
    sys.exit(main())
