// Template: Library crate entry point
//
// Standard structure for a well-organized Rust library.

// Lint configuration
#![deny(clippy::correctness)]
#![warn(clippy::pedantic)]
#![warn(missing_docs)]

//! # {{crate_name}}
//!
//! {{description}}
//!
//! ## Quick Start
//!
//! ```rust
//! use {{crate_name}}::{{primary_type}};
//!
//! let instance = {{primary_type}}::new();
//! ```

mod error;
mod config;

// Re-export public API
pub use error::Error;
pub use config::Config;

/// Result type alias for this crate.
pub type Result<T> = std::result::Result<T, Error>;
