#!/usr/bin/env python3
"""
pr_checklist.py — Static analysis checklist for code review diffs.

Reads a unified diff from stdin or a file, then checks for:
  - Hardcoded secret patterns (password=, api_key=, token=, etc.)
  - print() statements in non-test files
  - TODO / FIXME comments without a Jira ticket reference
  - Changed source files that have no corresponding change in a test file

Usage:
    git diff main...HEAD | python pr_checklist.py
    python pr_checklist.py changes.diff
    python pr_checklist.py --file changes.diff

Exit codes:
    0  No issues found
    1  One or more issues found
"""

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

# ─── Pattern definitions ───────────────────────────────────────────────────────

SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("password assignment",     re.compile(r'(?i)(password|passwd|pwd)\s*[=:]\s*["\'][^"\']{3,}["\']')),
    ("api_key assignment",      re.compile(r'(?i)(api_key|apikey|api-key)\s*[=:]\s*["\'][^"\']{8,}["\']')),
    ("token assignment",        re.compile(r'(?i)(token|access_token|auth_token|bearer)\s*[=:]\s*["\'][^"\']{8,}["\']')),
    ("secret assignment",       re.compile(r'(?i)(secret|client_secret)\s*[=:]\s*["\'][^"\']{6,}["\']')),
    ("private key header",      re.compile(r'-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----')),
    ("AWS access key",          re.compile(r'AKIA[0-9A-Z]{16}')),
    ("generic bearer token",    re.compile(r'[Bb]earer\s+[A-Za-z0-9\-_]{20,}\.[A-Za-z0-9\-_]{20,}')),
]

PRINT_PATTERN = re.compile(r'^\+\s*print\s*\(')

TODO_PATTERN = re.compile(r'(?i)(TODO|FIXME|HACK|XXX)')
TODO_WITH_TICKET = re.compile(r'(?i)(TODO|FIXME|HACK|XXX)[:\s]+[A-Z]+-\d+')

# Patterns that identify a diff hunk as belonging to an added line (+) in source
ADDED_LINE = re.compile(r'^\+(?!\+\+)')

# Identify which file a hunk belongs to
DIFF_FILE_RE = re.compile(r'^(?:---|\+\+\+)\s+(?:a/|b/)?(.+)')
NEW_FILE_RE = re.compile(r'^\+\+\+\s+(?:b/)?(.+)')

# Test file heuristics
TEST_FILE_PATTERNS = [
    re.compile(r'tests?/'),
    re.compile(r'_test\.(py|ts|js)$'),
    re.compile(r'\.test\.(ts|js|tsx|jsx)$'),
    re.compile(r'\.spec\.(ts|js|tsx|jsx)$'),
    re.compile(r'spec/'),
]

# ─── Data model ────────────────────────────────────────────────────────────────

@dataclass
class Issue:
    category: str
    filepath: str
    line_number: int
    line_content: str
    description: str
    blocking: bool = True

@dataclass
class ReviewReport:
    issues: list[Issue] = field(default_factory=list)

    def add(self, issue: Issue) -> None:
        self.issues.append(issue)

    @property
    def blocking_count(self) -> int:
        return sum(1 for i in self.issues if i.blocking)

    @property
    def nonblocking_count(self) -> int:
        return sum(1 for i in self.issues if not i.blocking)

# ─── Diff parsing ──────────────────────────────────────────────────────────────

@dataclass
class DiffLine:
    filepath: str
    line_number: int   # line number in the new file (+ lines only)
    content: str       # the raw diff line (including the leading +)

def parse_diff(text: str) -> tuple[list[DiffLine], set[str]]:
    """
    Parse a unified diff into a list of added lines with file context.
    Also returns the set of all file paths touched by the diff.
    """
    lines: list[DiffLine] = []
    changed_files: set[str] = set()
    current_file = "<unknown>"
    new_lineno = 0

    for raw_line in text.splitlines():
        # Detect file header
        m = NEW_FILE_RE.match(raw_line)
        if m:
            current_file = m.group(1).strip()
            changed_files.add(current_file)
            new_lineno = 0
            continue

        # Detect hunk header: @@ -old_start,old_count +new_start,new_count @@
        hunk_m = re.match(r'^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s+@@', raw_line)
        if hunk_m:
            new_lineno = int(hunk_m.group(1)) - 1
            continue

        if raw_line.startswith("+++") or raw_line.startswith("---"):
            continue

        if raw_line.startswith("+"):
            new_lineno += 1
            lines.append(DiffLine(
                filepath=current_file,
                line_number=new_lineno,
                content=raw_line,
            ))
        elif raw_line.startswith("-"):
            pass  # removed lines don't increment new_lineno
        else:
            new_lineno += 1  # context lines

    return lines, changed_files

# ─── Checks ────────────────────────────────────────────────────────────────────

def is_test_file(filepath: str) -> bool:
    return any(p.search(filepath) for p in TEST_FILE_PATTERNS)

def check_secrets(diff_lines: list[DiffLine], report: ReviewReport) -> None:
    for dl in diff_lines:
        code = dl.content[1:]  # strip leading '+'
        for name, pattern in SECRET_PATTERNS:
            if pattern.search(code):
                report.add(Issue(
                    category="SECRET",
                    filepath=dl.filepath,
                    line_number=dl.line_number,
                    line_content=code.strip(),
                    description=f"Possible hardcoded secret — {name}. Use environment variables.",
                    blocking=True,
                ))

def check_print_statements(diff_lines: list[DiffLine], report: ReviewReport) -> None:
    for dl in diff_lines:
        if is_test_file(dl.filepath):
            continue
        if PRINT_PATTERN.match(dl.content):
            code = dl.content[1:].strip()
            report.add(Issue(
                category="PRINT",
                filepath=dl.filepath,
                line_number=dl.line_number,
                line_content=code,
                description="print() in non-test code. Use structured logging (logger.info/warning/error).",
                blocking=True,
            ))

def check_todos(diff_lines: list[DiffLine], report: ReviewReport) -> None:
    for dl in diff_lines:
        code = dl.content[1:]
        if TODO_PATTERN.search(code) and not TODO_WITH_TICKET.search(code):
            report.add(Issue(
                category="TODO",
                filepath=dl.filepath,
                line_number=dl.line_number,
                line_content=code.strip(),
                description=(
                    "TODO/FIXME without a Jira ticket reference. "
                    "Add a ticket: # TODO: <PROJ>-123 — description"
                ),
                blocking=False,
            ))

def check_test_coverage(changed_files: set[str], report: ReviewReport) -> None:
    """
    For every changed source file, check that at least one test file was also changed.
    Heuristic only — not a replacement for actual coverage metrics.
    """
    source_extensions = {".py", ".ts", ".js", ".tsx", ".jsx"}
    source_files = {
        f for f in changed_files
        if Path(f).suffix in source_extensions and not is_test_file(f)
    }
    test_files_changed = {f for f in changed_files if is_test_file(f)}

    for source_file in sorted(source_files):
        stem = Path(source_file).stem
        # Check whether any changed test file references this source file by stem name
        has_test = any(stem in tf for tf in test_files_changed)
        if not has_test:
            report.add(Issue(
                category="COVERAGE",
                filepath=source_file,
                line_number=0,
                line_content="",
                description=(
                    f"No test file change detected for '{source_file}'. "
                    "Verify test coverage meets the minimum threshold."
                ),
                blocking=False,
            ))

# ─── Rendering ────────────────────────────────────────────────────────────────

CATEGORY_LABEL = {
    "SECRET":   "BLOCKING — SECRET",
    "PRINT":    "BLOCKING — PRINT STATEMENT",
    "TODO":     "nit — TODO WITHOUT TICKET",
    "COVERAGE": "nit — UNTESTED FILE",
}

def render_report(report: ReviewReport) -> str:
    if not report.issues:
        return "PR CHECKLIST: PASS — no issues found.\n"

    lines: list[str] = []
    lines.append(f"PR CHECKLIST: {report.blocking_count} blocking, {report.nonblocking_count} non-blocking\n")
    lines.append("=" * 60)

    by_file: dict[str, list[Issue]] = defaultdict(list)
    for issue in report.issues:
        by_file[issue.filepath].append(issue)

    for filepath in sorted(by_file.keys()):
        lines.append(f"\n{filepath}")
        lines.append("-" * len(filepath))
        for issue in by_file[filepath]:
            label = CATEGORY_LABEL.get(issue.category, issue.category)
            loc = f"line {issue.line_number}" if issue.line_number else "file"
            lines.append(f"  [{label}] ({loc})")
            lines.append(f"  {issue.description}")
            if issue.line_content:
                lines.append(f"  > {issue.line_content[:120]}")
            lines.append("")

    return "\n".join(lines)

# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="PR review checklist — static analysis of a unified diff")
    parser.add_argument(
        "file",
        nargs="?",
        help="Path to a unified diff file. If omitted, reads from stdin.",
    )
    parser.add_argument(
        "--file",
        dest="file_flag",
        help="Path to a unified diff file (alternative to positional argument).",
    )
    args = parser.parse_args()

    filepath = args.file or args.file_flag
    if filepath:
        try:
            diff_text = Path(filepath).read_text(encoding="utf-8")
        except OSError as e:
            print(f"ERROR: cannot read file: {e}", file=sys.stderr)
            sys.exit(2)
    elif not sys.stdin.isatty():
        diff_text = sys.stdin.read()
    else:
        print("ERROR: provide a diff file or pipe diff to stdin.", file=sys.stderr)
        print("  Usage: git diff main...HEAD | python pr_checklist.py", file=sys.stderr)
        sys.exit(2)

    if not diff_text.strip():
        print("No diff content provided.", file=sys.stderr)
        sys.exit(0)

    diff_lines, changed_files = parse_diff(diff_text)
    report = ReviewReport()

    check_secrets(diff_lines, report)
    check_print_statements(diff_lines, report)
    check_todos(diff_lines, report)
    check_test_coverage(changed_files, report)

    print(render_report(report))
    sys.exit(1 if report.blocking_count > 0 else 0)

if __name__ == "__main__":
    main()
