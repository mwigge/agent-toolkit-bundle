// Template: Function with OpenTelemetry tracing instrumentation

use tracing::{instrument, info, warn};

/// Executes a chaos action against the target.
///
/// Emits an OTel span with chaos-specific attributes.
#[instrument(
    name = "chaos.action.execute",
    skip(connection),
    fields(
        chaos.action.type_ = %action_type,
        chaos.action.provider = "{{provider_name}}",
        chaos.experiment.id = %experiment_id,
        otel.status_code = tracing::field::Empty,
    )
)]
pub async fn execute_action(
    connection: &Connection,
    experiment_id: &str,
    action_type: &str,
    params: &ActionParams,
) -> Result<ActionResult> {
    info!("starting action execution");

    let result = connection
        .run_action(action_type, params)
        .await
        .map_err(|e| {
            // Record error on the span
            tracing::Span::current().record("otel.status_code", "ERROR");
            warn!(error = %e, "action execution failed");
            e
        })?;

    tracing::Span::current().record("otel.status_code", "OK");
    info!(status = %result.status, "action completed");

    Ok(result)
}
