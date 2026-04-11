// Template: Binary crate entry point with anyhow + tracing

use anyhow::{Context, Result};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    tracing::info!("starting {{binary_name}}");

    // Load configuration
    let config = {{crate_name}}::Config::from_env()
        .context("failed to load configuration")?;

    // Run the application
    {{crate_name}}::run(config).await?;

    tracing::info!("{{binary_name}} shut down cleanly");
    Ok(())
}
