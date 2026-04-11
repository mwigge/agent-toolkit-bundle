# Rust Debugging Techniques

## Wolf Fence Method

1. Identify the failing behaviour
2. Add `dbg!()` at the midpoint of the suspected code path
3. If bug is before the midpoint, move fence earlier; if after, move later
4. Repeat until the exact line is isolated

```rust
fn process(data: &[u8]) -> Result<Output> {
    let parsed = parse(data)?;
    dbg!(&parsed);  // FENCE: is parsed correct?
    
    let transformed = transform(parsed)?;
    dbg!(&transformed);  // FENCE: is transform correct?
    
    let result = finalize(transformed)?;
    Ok(result)
}
```

## dbg! macro

```rust
// Prints file:line = value to stderr, returns value
let result = dbg!(expensive_computation());

// Works in expressions
let x = dbg!(a + b) * dbg!(c + d);

// Prints vectors/structs with Debug
dbg!(&my_vec);
```

## RUST_BACKTRACE

```bash
# Full backtrace on panic
RUST_BACKTRACE=1 cargo run

# Full backtrace including dependencies
RUST_BACKTRACE=full cargo run
```

## RUST_LOG with tracing

```bash
# Enable all debug logs
RUST_LOG=debug cargo run

# Module-specific
RUST_LOG=my_crate::module=trace cargo run

# Multiple targets
RUST_LOG=my_crate=debug,hyper=warn cargo run
```

## cargo expand (macro debugging)

```bash
cargo install cargo-expand
cargo expand module::path
```

## Compiler error exploration

```bash
# Explain an error code
rustc --explain E0382

# Show type inference
cargo check 2>&1 | head -50
```
