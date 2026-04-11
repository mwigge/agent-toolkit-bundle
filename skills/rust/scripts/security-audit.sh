#!/usr/bin/env bash
# Rust security audit script
# Usage: ./security-audit.sh
set -euo pipefail

echo "=== Rust Security Audit ==="

# 1. Dependency vulnerabilities
echo ">> cargo audit"
if command -v cargo-audit &>/dev/null; then
    cargo audit
else
    echo "   (install: cargo install cargo-audit)"
fi

# 2. Unsafe code scan
echo ""
echo ">> Scanning for unsafe blocks..."
UNSAFE_COUNT=$(grep -rn "unsafe " --include="*.rs" src/ 2>/dev/null | grep -v "// SAFETY:" | wc -l | tr -d ' ')
if [ "$UNSAFE_COUNT" -gt 0 ]; then
    echo "   WARNING: $UNSAFE_COUNT unsafe blocks without // SAFETY: comment:"
    grep -rn "unsafe " --include="*.rs" src/ 2>/dev/null | grep -v "// SAFETY:"
else
    echo "   OK: All unsafe blocks have SAFETY comments (or none found)"
fi

# 3. Unwrap scan
echo ""
echo ">> Scanning for .unwrap() in src/..."
UNWRAP_COUNT=$(grep -rn "\.unwrap()" --include="*.rs" src/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNWRAP_COUNT" -gt 0 ]; then
    echo "   WARNING: $UNWRAP_COUNT .unwrap() calls in library code:"
    grep -rn "\.unwrap()" --include="*.rs" src/ 2>/dev/null
else
    echo "   OK: No .unwrap() in src/"
fi

# 4. Clippy security lints
echo ""
echo ">> cargo clippy (security-relevant)"
cargo clippy -- -W clippy::unwrap_used -W clippy::expect_used -W clippy::panic 2>&1 | head -30

echo ""
echo "=== Security Audit Complete ==="
