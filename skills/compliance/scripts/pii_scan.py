#!/usr/bin/env python3
"""
pii_scan.py — Scan source files recursively for common PII patterns.

Detects:
  - Email addresses
  - Phone numbers (international and local formats)
  - UK/US National Insurance / Social Security Number patterns
  - Credit card numbers (Luhn-plausible 13–19 digit sequences)
  - IBAN patterns
  - UK National Insurance Number pattern

Usage:
    python pii_scan.py <directory>
    python pii_scan.py src/
    python pii_scan.py . --exclude tests/ --include "*.py,*.ts"

Exit codes:
    0  No PII patterns found
    1  One or more PII patterns found
    2  Usage error

Note: This tool detects patterns, not confirmed PII. Review matches manually.
     False positives are expected (e.g. test fixture data, example values).
     The goal is to surface candidates for review, not to provide a definitive audit.
"""

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


# ─── PII patterns ─────────────────────────────────────────────────────────────

@dataclass
class PiiPattern:
    name: str
    pattern: re.Pattern[str]
    description: str
    # Some patterns need post-processing validation (e.g. Luhn for credit cards)
    validator: "None | callable" = None  # type: ignore[type-arg]


def luhn_valid(number_str: str) -> bool:
    """Return True if the digit string passes the Luhn algorithm."""
    digits = [int(c) for c in number_str if c.isdigit()]
    if len(digits) < 13:
        return False
    total = 0
    for i, digit in enumerate(reversed(digits)):
        if i % 2 == 1:
            doubled = digit * 2
            total += doubled - 9 if doubled > 9 else doubled
        else:
            total += digit
    return total % 10 == 0


def extract_cc_candidate(match: re.Match[str]) -> str:
    """Strip spaces/dashes from a credit card candidate match."""
    return re.sub(r"[\s\-]", "", match.group(0))


PII_PATTERNS: list[PiiPattern] = [
    PiiPattern(
        name="Email address",
        pattern=re.compile(
            r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b'
        ),
        description="Email address — may be a direct identifier",
    ),
    PiiPattern(
        name="Phone number (E.164 / international)",
        pattern=re.compile(
            r'(?<!\d)(\+?[1-9]\d{0,2}[\s\-.]?)?\(?\d{2,4}\)?[\s\-.]?\d{3,4}[\s\-.]?\d{3,4}(?!\d)'
        ),
        description="Phone number — verify context before flagging",
    ),
    PiiPattern(
        name="UK National Insurance Number",
        pattern=re.compile(
            r'\b(?!BG|GB|NK|KN|TN|NT|ZZ)[A-CEGHJ-PR-TW-Z]{1}[A-CEGHJ-NPR-TW-Z]{1}'
            r'[0-9]{6}[A-D]?\b',
            re.IGNORECASE,
        ),
        description="UK National Insurance Number (NIN)",
    ),
    PiiPattern(
        name="US Social Security Number",
        pattern=re.compile(
            r'\b(?!000|666|9\d{2})\d{3}[- ]?(?!00)\d{2}[- ]?(?!0{4})\d{4}\b'
        ),
        description="US Social Security Number (SSN)",
    ),
    PiiPattern(
        name="Credit card number",
        pattern=re.compile(
            r'\b(?:4[0-9]{12}(?:[0-9]{3,6})?'       # Visa
            r'|5[1-5][0-9]{14}'                       # Mastercard
            r'|3[47][0-9]{13}'                        # Amex
            r'|3(?:0[0-5]|[68][0-9])[0-9]{11}'       # Diners
            r'|6(?:011|5[0-9]{2})[0-9]{12,15}'       # Discover
            r'|(?:2131|1800|35\d{3})\d{11}'          # JCB
            r'|\d{4}[- ]\d{4}[- ]\d{4}[- ]\d{4}'    # spaced 16-digit
            r')\b'
        ),
        description="Credit / debit card number (Luhn-validated)",
        validator=lambda m: luhn_valid(re.sub(r"[\s\-]", "", m.group(0))),
    ),
    PiiPattern(
        name="IBAN",
        pattern=re.compile(
            r'\b[A-Z]{2}\d{2}[A-Z0-9]{1,30}\b'
        ),
        description="International Bank Account Number (IBAN)",
    ),
    PiiPattern(
        name="IPv4 address (potential quasi-identifier)",
        pattern=re.compile(
            r'\b(?:25[0-5]|2[0-4]\d|[01]?\d\d?)'
            r'(?:\.(?:25[0-5]|2[0-4]\d|[01]?\d\d?)){3}\b'
        ),
        description="IPv4 address — a quasi-identifier; may need pseudonymisation in logs",
    ),
]


# ─── File filtering ───────────────────────────────────────────────────────────

BINARY_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".woff", ".woff2",
    ".ttf", ".eot", ".pdf", ".zip", ".tar", ".gz", ".bin", ".pyc",
    ".pyo", ".so", ".dll", ".exe", ".db", ".sqlite", ".lock",
}

DEFAULT_SOURCE_EXTENSIONS = {
    ".py", ".ts", ".js", ".tsx", ".jsx", ".json", ".yaml", ".yml",
    ".env", ".env.example", ".toml", ".ini", ".cfg", ".conf", ".sql",
    ".md", ".txt", ".html", ".jinja", ".j2", ".sh", ".bash",
}


def should_scan(path: Path, include_extensions: set[str] | None, exclude_dirs: set[str]) -> bool:
    if path.suffix in BINARY_EXTENSIONS:
        return False
    for part in path.parts:
        if part in exclude_dirs:
            return False
    if include_extensions:
        return path.suffix in include_extensions
    return path.suffix in DEFAULT_SOURCE_EXTENSIONS


# ─── Scanning ─────────────────────────────────────────────────────────────────

@dataclass
class Finding:
    filepath: str
    line_number: int
    pattern_name: str
    description: str
    matched_text: str


def scan_file(path: Path) -> list[Finding]:
    findings: list[Finding] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return findings

    lines = text.splitlines()
    for lineno, line in enumerate(lines, start=1):
        for pii in PII_PATTERNS:
            for match in pii.pattern.finditer(line):
                if pii.validator is not None and not pii.validator(match):
                    continue
                # Redact the actual match in output to avoid echoing sensitive data
                matched = match.group(0)
                redacted = matched[:3] + "*" * max(0, len(matched) - 6) + matched[-3:] if len(matched) > 6 else "***"
                findings.append(Finding(
                    filepath=str(path),
                    line_number=lineno,
                    pattern_name=pii.name,
                    description=pii.description,
                    matched_text=redacted,
                ))
    return findings


def scan_directory(
    root: Path,
    include_extensions: set[str] | None,
    exclude_dirs: set[str],
) -> list[Finding]:
    all_findings: list[Finding] = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and should_scan(path, include_extensions, exclude_dirs):
            all_findings.extend(scan_file(path))
    return all_findings


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Scan source files for PII patterns",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python pii_scan.py src/\n"
            "  python pii_scan.py . --exclude .git,node_modules,__pycache__\n"
            "  python pii_scan.py . --include .py,.ts\n"
        ),
    )
    parser.add_argument("directory", help="Root directory to scan")
    parser.add_argument(
        "--exclude",
        default=".git,node_modules,__pycache__,.venv,dist,build,.mypy_cache",
        help="Comma-separated directory names to exclude (default: common build/cache dirs)",
    )
    parser.add_argument(
        "--include",
        default=None,
        help="Comma-separated file extensions to scan (e.g. .py,.ts). Default: common source extensions.",
    )
    parser.add_argument(
        "--no-redact",
        action="store_true",
        help="Show full matched text instead of redacted version (use with caution)",
    )

    args = parser.parse_args()

    root = Path(args.directory)
    if not root.is_dir():
        print(f"ERROR: not a directory: {args.directory}", file=sys.stderr)
        sys.exit(2)

    exclude_dirs = {d.strip() for d in args.exclude.split(",") if d.strip()}
    include_extensions: set[str] | None = None
    if args.include:
        include_extensions = {
            (e.strip() if e.strip().startswith(".") else f".{e.strip()}")
            for e in args.include.split(",")
            if e.strip()
        }

    findings = scan_directory(root, include_extensions, exclude_dirs)

    if not findings:
        print(f"PASS: No PII patterns found in {args.directory}")
        sys.exit(0)

    print(f"FAIL: {len(findings)} potential PII match(es) found in {args.directory}")
    print("=" * 60)
    print("NOTE: These are pattern matches — review manually before taking action.")
    print("      Test fixtures and example values may produce false positives.")
    print("=" * 60)
    print()

    current_file = None
    for finding in findings:
        if finding.filepath != current_file:
            current_file = finding.filepath
            print(f"\n{finding.filepath}")
            print("-" * len(finding.filepath))
        display = finding.matched_text if args.no_redact else finding.matched_text
        print(f"  Line {finding.line_number:>5}: [{finding.pattern_name}] {display!r}")
        print(f"           {finding.description}")

    print(f"\nTotal: {len(findings)} match(es)")
    sys.exit(1)


if __name__ == "__main__":
    main()
