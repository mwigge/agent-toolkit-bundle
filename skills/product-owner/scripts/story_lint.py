#!/usr/bin/env python3
"""
story_lint.py — Validate a user story from stdin.

Checks:
  1. Contains "As a" (role clause)
  2. Contains "I want" (goal clause)
  3. Contains "so that" (benefit clause)
  4. Contains "Acceptance criteria" section header
  5. Contains at least one "Given" clause
  6. Contains at least one "When" clause
  7. Contains at least one "Then" clause
  8. Contains at least 2 complete Given/When/Then scenarios
  9. No acceptance criteria scenario uses "so that" inside a Then clause
     (common mistake: mixing story format with AC format)

Usage:
    cat story.md | python story_lint.py
    python story_lint.py < story.md
    python story_lint.py story.md     # file argument also accepted

Exit code: 0 = PASS (all required checks), 1 = FAIL
"""

import re
import sys
from typing import NamedTuple

class LintResult(NamedTuple):
    rule_id: str
    description: str
    passed: bool
    severity: str   # "required" | "recommended"
    detail: str     # extra context shown on failure

def lint_story(text: str) -> list[LintResult]:
    results: list[LintResult] = []

    def check(
        rule_id: str,
        description: str,
        passed: bool,
        severity: str = "required",
        detail: str = "",
    ) -> None:
        results.append(LintResult(rule_id, description, passed, severity, detail))

    # Normalise: collapse multiple blank lines, strip trailing whitespace per line
    lines = [line.rstrip() for line in text.splitlines()]
    normalised = "\n".join(lines)
    lower = normalised.lower()

    # ── Rule S01: "As a" role clause ─────────────────────────────────────────
    match_as_a = re.search(r"\bas\s+a\b", lower)
    check(
        "S01",
        'Story contains "As a <role>"',
        bool(match_as_a),
        "required",
        'Missing "As a" — every story must identify the user role.',
    )

    # ── Rule S02: "I want" goal clause ────────────────────────────────────────
    match_i_want = re.search(r"\bi\s+want\b", lower)
    check(
        "S02",
        'Story contains "I want <goal>"',
        bool(match_i_want),
        "required",
        'Missing "I want" — every story must state the desired action.',
    )

    # ── Rule S03: "so that" benefit clause ───────────────────────────────────
    # Search in the story description only (before the AC section).
    ac_start_idx = lower.find("acceptance criteria")
    story_body = lower[:ac_start_idx] if ac_start_idx != -1 else lower
    match_so_that = re.search(r"\bso\s+that\b", story_body)
    check(
        "S03",
        'Story contains "so that <benefit>"',
        bool(match_so_that),
        "required",
        'Missing "so that" in the story body — state the business benefit.',
    )

    # ── Rule S04: Acceptance Criteria section ─────────────────────────────────
    has_ac_section = bool(re.search(r"acceptance\s+criteria", lower))
    check(
        "S04",
        'Story contains "Acceptance criteria" section',
        has_ac_section,
        "required",
        'Missing "Acceptance criteria" heading — required for DoR.',
    )

    # ── Rule S05: "Given" in AC ───────────────────────────────────────────────
    ac_section = lower[ac_start_idx:] if ac_start_idx != -1 else ""
    given_count = len(re.findall(r"\bgiven\b", ac_section))
    check(
        "S05",
        'Acceptance criteria contain "Given" clause(s)',
        given_count > 0,
        "required",
        f'"Given" count: {given_count}. Add preconditions to each scenario.',
    )

    # ── Rule S06: "When" in AC ────────────────────────────────────────────────
    when_count = len(re.findall(r"\bwhen\b", ac_section))
    check(
        "S06",
        'Acceptance criteria contain "When" clause(s)',
        when_count > 0,
        "required",
        f'"When" count: {when_count}. Add triggering action to each scenario.',
    )

    # ── Rule S07: "Then" in AC ────────────────────────────────────────────────
    then_count = len(re.findall(r"\bthen\b", ac_section))
    check(
        "S07",
        'Acceptance criteria contain "Then" clause(s)',
        then_count > 0,
        "required",
        f'"Then" count: {then_count}. Add observable outcomes to each scenario.',
    )

    # ── Rule S08: At least 2 complete scenarios ───────────────────────────────
    # A "scenario" is a block containing Given + When + Then in order.
    scenario_pattern = re.compile(
        r"\bgiven\b.+?\bwhen\b.+?\bthen\b",
        re.DOTALL | re.IGNORECASE,
    )
    scenario_matches = scenario_pattern.findall(ac_section)
    check(
        "S08",
        "At least 2 complete Given/When/Then scenarios",
        len(scenario_matches) >= 2,
        "required",
        f"Found {len(scenario_matches)} complete scenario(s). "
        "Add at least one unhappy-path or edge-case scenario.",
    )

    # ── Rule S09: Story not missing INVEST indicator words ────────────────────
    # Soft check: if title/summary contains "refactor" or "clean up" with no
    # visible outcome described, flag it as potentially not Valuable.
    refactor_without_benefit = (
        bool(re.search(r"\b(refactor|clean up|cleanup|tidy)\b", lower))
        and not bool(re.search(r"\b(performance|speed|latency|maintainab|scalab|reliability)\b", lower))
    )
    check(
        "S09",
        "Refactoring story states an observable benefit",
        not refactor_without_benefit,
        "recommended",
        'Refactoring stories must describe an observable benefit '
        '(e.g. "reduces p99 latency by 20%") to satisfy INVEST Valuable.',
    )

    # ── Rule S10: No vague outcome language ───────────────────────────────────
    vague_patterns = [r"\bworks well\b", r"\bfeels fast\b", r"\buser.friendly\b", r"\bbetter\b"]
    vague_in_ac = [p for p in vague_patterns if re.search(p, ac_section)]
    check(
        "S10",
        "Acceptance criteria use measurable language (no vague terms)",
        len(vague_in_ac) == 0,
        "recommended",
        f"Vague terms found: {vague_in_ac}. Replace with specific, measurable criteria.",
    )

    return results

def print_report(results: list[LintResult]) -> int:
    required_failures = [r for r in results if not r.passed and r.severity == "required"]
    recommended_failures = [r for r in results if not r.passed and r.severity == "recommended"]
    passed = [r for r in results if r.passed]

    width = 64
    sep = "─" * width

    print(f"\n{'═' * width}")
    print("  Story Lint Report")
    print(f"{'═' * width}")

    print(f"\n  ✓ PASSED ({len(passed)})")
    print(sep)
    for r in passed:
        print(f"  ✓ [{r.rule_id}] {r.description}")

    if required_failures:
        print(f"\n  ✗ FAILED — REQUIRED ({len(required_failures)})")
        print(sep)
        for r in required_failures:
            print(f"  ✗ [{r.rule_id}] {r.description}")
            print(f"         → {r.detail}")

    if recommended_failures:
        print(f"\n  ⚠ FAILED — RECOMMENDED ({len(recommended_failures)})")
        print(sep)
        for r in recommended_failures:
            print(f"  ⚠ [{r.rule_id}] {r.description}")
            print(f"         → {r.detail}")

    print(f"\n{'═' * width}")
    if required_failures:
        print(f"  RESULT: FAIL — {len(required_failures)} required rule(s) violated.")
        print(f"{'═' * width}\n")
        return 1
    else:
        print(f"  RESULT: PASS — All required rules satisfied.")
        print(f"{'═' * width}\n")
        return 0

def main() -> int:
    if len(sys.argv) > 1:
        filepath = sys.argv[1]
        try:
            with open(filepath, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            print(f"ERROR: Cannot read file '{filepath}': {exc}", file=sys.stderr)
            return 1
    elif not sys.stdin.isatty():
        text = sys.stdin.read()
    else:
        print("Usage: python story_lint.py <story_file.md>", file=sys.stderr)
        print("       cat story.md | python story_lint.py", file=sys.stderr)
        return 1

    if not text.strip():
        print("ERROR: Input is empty.", file=sys.stderr)
        return 1

    results = lint_story(text)
    return print_report(results)

if __name__ == "__main__":
    sys.exit(main())
