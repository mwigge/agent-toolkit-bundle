#!/usr/bin/env python3
"""
eval-suite.py --- Template for prompt evaluation test suites.

Customise the test cases and prompt function for your use case.
Run with: python eval-suite.py

Requires: anthropic SDK (pip install anthropic)
"""

from __future__ import annotations

import json
import os
import sys
import time
from dataclasses import dataclass


@dataclass
class TestCase:
    name: str
    input_text: str
    expected_contains: list[str] | None = None
    expected_format: str | None = None  # "json", "markdown"
    max_output_tokens: int = 1024


@dataclass
class EvalResult:
    name: str
    passed: bool
    failure_reason: str | None = None
    latency_ms: float = 0.0
    output_preview: str = ""


# --- Define your prompt here ---
SYSTEM_PROMPT = """You are a chaos engineering assistant.
Analyse experiment results and provide structured recommendations.
Always respond with valid JSON matching this schema:
{
  "summary": "string",
  "slo_impact": "none" | "minor" | "major" | "critical",
  "recommendations": ["string"]
}"""


def call_llm(user_input: str, max_tokens: int = 1024) -> tuple[str, float]:
    """Call the LLM and return (output, latency_ms)."""
    try:
        import anthropic
    except ImportError:
        print("ERROR: pip install anthropic", file=sys.stderr)
        sys.exit(2)

    client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY", ""))
    start = time.monotonic()
    response = client.messages.create(
        model="claude-sonnet-4-5",
        max_tokens=max_tokens,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_input}],
    )
    latency = (time.monotonic() - start) * 1000
    return response.content[0].text, latency


# --- Define test cases ---
TEST_CASES = [
    TestCase(
        name="basic_analysis",
        input_text="API returned 503 errors for 30 seconds during database failover, then recovered.",
        expected_contains=["summary", "recommendations"],
        expected_format="json",
    ),
    TestCase(
        name="graceful_degradation",
        input_text="Cache service was unavailable for 5 minutes. API latency increased from 50ms to 200ms but remained within SLO.",
        expected_contains=["summary", "slo_impact"],
        expected_format="json",
    ),
    TestCase(
        name="critical_failure",
        input_text="Complete network partition between API and database for 2 minutes. 100% of requests failed. Recovery took 45 seconds after partition healed.",
        expected_contains=["critical", "recommendations"],
        expected_format="json",
    ),
]


def evaluate(test_case: TestCase) -> EvalResult:
    """Run a single test case and return the result."""
    try:
        output, latency = call_llm(test_case.input_text, test_case.max_output_tokens)
    except Exception as exc:
        return EvalResult(
            name=test_case.name,
            passed=False,
            failure_reason=f"LLM call failed: {exc}",
        )

    # Check format
    if test_case.expected_format == "json":
        try:
            json.loads(output)
        except json.JSONDecodeError as e:
            return EvalResult(
                name=test_case.name,
                passed=False,
                failure_reason=f"Invalid JSON: {e}",
                latency_ms=latency,
                output_preview=output[:200],
            )

    # Check content
    if test_case.expected_contains:
        missing = [s for s in test_case.expected_contains if s.lower() not in output.lower()]
        if missing:
            return EvalResult(
                name=test_case.name,
                passed=False,
                failure_reason=f"Missing expected strings: {missing}",
                latency_ms=latency,
                output_preview=output[:200],
            )

    return EvalResult(
        name=test_case.name,
        passed=True,
        latency_ms=latency,
        output_preview=output[:200],
    )


def main() -> int:
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ERROR: Set ANTHROPIC_API_KEY environment variable", file=sys.stderr)
        return 2

    print(f"\n=== Prompt Evaluation Suite ===\n")
    print(f"Test cases: {len(TEST_CASES)}")
    print()

    results: list[EvalResult] = []
    for tc in TEST_CASES:
        print(f"Running: {tc.name}...", end=" ", flush=True)
        result = evaluate(tc)
        results.append(result)
        status = "PASS" if result.passed else "FAIL"
        print(f"{status} ({result.latency_ms:.0f}ms)")
        if not result.passed:
            print(f"  Reason: {result.failure_reason}")

    print(f"\n--- Summary ---")
    passed = sum(1 for r in results if r.passed)
    print(f"Passed: {passed}/{len(results)}")
    avg_latency = sum(r.latency_ms for r in results) / max(len(results), 1)
    print(f"Avg latency: {avg_latency:.0f}ms")

    return 0 if all(r.passed for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
