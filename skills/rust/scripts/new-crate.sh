#!/usr/bin/env bash
# Scaffold a new Rust crate with standard structure
# Usage: ./new-crate.sh <crate-name> [--lib|--bin]
set -euo pipefail

NAME="${1:?Usage: new-crate.sh <name> [--lib|--bin]}"
TYPE="${2:---lib}"

echo "Creating crate: $NAME ($TYPE)"
cargo new "$NAME" "$TYPE"
cd "$NAME"

# Add standard dev dependencies
cat >> Cargo.toml <<'EOF'

[lints.clippy]
pedantic = { level = "warn", priority = -1 }
correctness = "deny"

[profile.release]
lto = true
codegen-units = 1
strip = true
EOF

# Add rustfmt config
cat > rustfmt.toml <<'EOF'
edition = "2024"
max_width = 100
use_field_init_shorthand = true
use_try_shorthand = true
EOF

# Add clippy config
cat > clippy.toml <<'EOF'
too-many-arguments-threshold = 7
type-complexity-threshold = 250
EOF

echo "Crate $NAME created with standard config."
echo "Next: cd $NAME && cargo build"
