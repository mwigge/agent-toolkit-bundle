// Template: thiserror-based error type for a library crate

use thiserror::Error;

/// Errors that can occur in {{crate_name}}.
#[derive(Debug, Error)]
pub enum Error {
    /// A configuration value is missing or invalid.
    #[error("configuration error: {0}")]
    Config(String),

    /// An I/O operation failed.
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// A database operation failed.
    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    /// Serialization or deserialization failed.
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),

    /// An unexpected internal error.
    #[error(transparent)]
    Internal(#[from] anyhow::Error),
}
