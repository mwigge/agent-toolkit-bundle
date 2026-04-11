#!/usr/bin/env bash
# scripts/check.sh — run the full Python quality pipeline
# Usage: bash scripts/check.sh [package_name]
# Expects to run from the project root (where pyproject.toml lives).

set -euo pipefail
PKG="${1:-$(basename "$PWD")}"

echo "==> ruff fix + format"
ruff check --fix .
ruff format .

echo "==> black"
black "$PKG"/

echo "==> ruff final check (must be zero)"
ruff check .

echo "==> mypy"
mypy "$PKG"/ --ignore-missing-imports --strict

echo "==> bandit (HIGH = block)"
bandit -r "$PKG"/ -ll -q

echo "==> pytest + coverage"
pytest tests/ -v \
  --cov="$PKG" \
  --cov-report=term-missing \
  --cov-fail-under=95

echo "==> pip-audit"
pip-audit --strict --desc on

echo ""
echo "All checks passed."
