#!/usr/bin/env bash
# Rust quality gate — run before every commit
# Usage: ./quality-gate.sh [--fix]
set -euo pipefail

FIX="${1:-}"

echo "=== Rust Quality Gate ==="

# 1. Format check (or fix)
if [ "$FIX" = "--fix" ]; then
    echo ">> cargo fmt"
    cargo fmt
else
    echo ">> cargo fmt --check"
    cargo fmt --check
fi

# 2. Clippy (pedantic)
echo ">> cargo clippy"
cargo clippy -- -D warnings -W clippy::pedantic

# 3. Tests
echo ">> cargo test --workspace"
cargo test --workspace

# 4. Security audit
if command -v cargo-audit &>/dev/null; then
    echo ">> cargo audit"
    cargo audit
else
    echo ">> cargo audit (skipped — install with: cargo install cargo-audit)"
fi

echo "=== Quality Gate PASSED ==="
