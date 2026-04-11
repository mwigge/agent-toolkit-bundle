# Rust Error Handling Cheatsheet

## Library errors → `thiserror`

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("database query failed: {0}")]
    Database(#[from] sqlx::Error),

    #[error("configuration missing: {key}")]
    ConfigMissing { key: String },

    #[error("validation failed: {0}")]
    Validation(String),

    #[error(transparent)]
    Other(#[from] anyhow::Error),
}
```

## Binary/CLI errors → `anyhow`

```rust
use anyhow::{Context, Result};

fn main() -> Result<()> {
    let config = std::fs::read_to_string("config.toml")
        .context("failed to read config file")?;
    let parsed: Config = toml::from_str(&config)
        .context("invalid TOML in config file")?;
    run(parsed)?;
    Ok(())
}
```

## Patterns

```rust
// ? operator — propagate with conversion
let data = fetch_data().context("fetching data")?;

// map_err — transform error type
let val = parse(input).map_err(|e| AppError::Validation(e.to_string()))?;

// ok_or / ok_or_else — Option → Result
let user = users.get(&id).ok_or(AppError::NotFound { id })?;

// bail! — early return with error (anyhow)
if input.is_empty() {
    anyhow::bail!("input must not be empty");
}

// ensure! — conditional bail (anyhow)
anyhow::ensure!(!input.is_empty(), "input must not be empty");
```

## Rules

- Never `.unwrap()` in library code — use `?` or explicit handling
- Never `panic!()` in library code — return `Result`
- Add `#[must_use]` on all `Result`-returning public functions
- Use `.context()` to add human-readable messages at each call site
- Match on error variants for recovery; use `?` for propagation
