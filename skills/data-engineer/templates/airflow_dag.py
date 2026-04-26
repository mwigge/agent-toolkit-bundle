"""
airflow_dag.py — Production-grade Airflow DAG using the TaskFlow API.

Pipeline: Extract → Validate → Transform → Load → Notify
Schedule: Daily at 06:00 UTC.
SLA:       All tasks complete within 2 hours of scheduled start.
Retries:   3 attempts with exponential backoff; alert on final failure.
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta
from typing import Any

from airflow.decorators import dag, task
from airflow.models import Variable
from airflow.operators.empty import EmptyOperator
from airflow.utils.trigger_rule import TriggerRule

log = logging.getLogger(__name__)


# ── Callbacks ─────────────────────────────────────────────────────────────────

def on_failure_callback(context: dict[str, Any]) -> None:
    """Send an alert on task failure. Replace with PagerDuty / Slack / SNS."""
    dag_id = context["dag"].dag_id
    task_id = context["task_instance"].task_id
    execution_date = context["execution_date"]
    exception = context.get("exception", "No exception captured")

    # Structured log — never include context["ti"].xcom_pull() values
    # that may contain PII.
    log.error(
        "Task failed",
        extra={
            "dag_id": dag_id,
            "task_id": task_id,
            "execution_date": str(execution_date),
            "exception": str(exception),
        },
    )

    # Example: post to Slack via webhook stored in Airflow Variable (not hardcoded)
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    if webhook_url:
        import urllib.request
        import json

        payload = json.dumps({
            "text": f":red_circle: *{dag_id}.{task_id}* failed at `{execution_date}`\n```{exception}```"
        }).encode()
        req = urllib.request.Request(
            webhook_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            urllib.request.urlopen(req, timeout=10)
        except Exception as exc:  # noqa: BLE001
            log.warning("Slack notification failed: %s", exc)


def on_sla_miss_callback(
    dag: Any,
    task_list: str,
    blocking_task_list: str,
    slas: list[Any],
    blocking_tis: list[Any],
) -> None:
    """Log SLA misses — extend with alerting as needed."""
    log.warning(
        "SLA missed",
        extra={
            "dag_id": dag.dag_id,
            "task_list": task_list,
            "blocking_task_list": blocking_task_list,
        },
    )


# ── Default args ──────────────────────────────────────────────────────────────

DEFAULT_ARGS: dict[str, Any] = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "email_on_failure": False,   # Use on_failure_callback instead
    "email_on_retry": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=60),
    "on_failure_callback": on_failure_callback,
    "execution_timeout": timedelta(hours=1),
}


# ── DAG definition ────────────────────────────────────────────────────────────

@dag(
    dag_id="daily_crm_etl",
    description="Extract CRM events, validate, transform to Silver, load to mart.",
    schedule="0 6 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args=DEFAULT_ARGS,
    sla_miss_callback=on_sla_miss_callback,
    tags=["crm", "silver", "daily"],
    doc_md=__doc__,
)
def daily_crm_etl() -> None:
    """
    ## daily_crm_etl

    ### Overview
    Incremental ETL for CRM event data: raw → silver → gold mart.

    ### Schedule
    Daily at 06:00 UTC. `catchup=False` — missed runs are **not** backfilled
    automatically. Use `airflow dags backfill` for manual backfills.

    ### SLA
    All tasks must complete within 2 hours of the scheduled start time.
    SLA misses trigger `on_sla_miss_callback`.

    ### Backfill
    ```bash
    airflow dags backfill --start-date 2026-01-01 --end-date 2026-03-31 daily_crm_etl
    ```
    """

    # ── Task: extract ─────────────────────────────────────────────────────────
    @task(sla=timedelta(minutes=30))
    def extract(logical_date: str = "{{ ds }}") -> dict[str, Any]:
        """Pull raw events for the logical date from the source API."""
        # Read config from Airflow Variables — never hardcode credentials.
        source_config = Variable.get("crm_source_config", deserialize_json=True)
        api_base_url: str = source_config["api_base_url"]
        api_token: str = os.environ["CRM_API_TOKEN"]  # from env, not Variable

        log.info("Extracting CRM events for date=%s from %s", logical_date, api_base_url)

        # --- real extraction logic here ---
        # records = crm_client.get_events(date=logical_date, token=api_token)

        # Return metadata only — never return PII in XCom.
        return {
            "logical_date": logical_date,
            "source": api_base_url,
            "row_count": 0,  # replace with actual count
            "s3_path": f"s3://raw-bucket/crm/events/dt={logical_date}/",
        }

    # ── Task: validate ────────────────────────────────────────────────────────
    @task(sla=timedelta(minutes=15))
    def validate(extract_meta: dict[str, Any]) -> dict[str, Any]:
        """Run data quality checks against the raw extract."""
        s3_path = extract_meta["s3_path"]
        row_count = extract_meta["row_count"]

        log.info("Validating extract at %s (%d rows)", s3_path, row_count)

        # Example threshold check
        if row_count == 0:
            raise ValueError(
                f"Validation failed: 0 rows extracted for {extract_meta['logical_date']}. "
                "This may indicate a source outage — check CRM API status."
            )

        # --- integrate Great Expectations checkpoint here ---
        # checkpoint_result = context.run_checkpoint("crm_events_daily", batch_kwargs={...})
        # if not checkpoint_result.success:
        #     raise ValueError("Great Expectations checkpoint failed")

        return {**extract_meta, "validation_passed": True}

    # ── Task: transform ───────────────────────────────────────────────────────
    @task(sla=timedelta(minutes=45))
    def transform(validated_meta: dict[str, Any]) -> dict[str, Any]:
        """Run dbt incremental model to promote raw → silver."""
        import subprocess

        logical_date = validated_meta["logical_date"]
        log.info("Running dbt transform for date=%s", logical_date)

        result = subprocess.run(
            [
                "dbt", "run",
                "--select", "stg_events__deduped+",
                "--vars", f'{{"run_date": "{logical_date}"}}',
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            log.error("dbt run stderr: %s", result.stderr[-2000:])
            raise RuntimeError(f"dbt run failed with exit code {result.returncode}")

        log.info("dbt run completed successfully")
        return {**validated_meta, "dbt_run_status": "success"}

    # ── Task: run_tests ───────────────────────────────────────────────────────
    @task(sla=timedelta(minutes=20))
    def run_tests(transform_meta: dict[str, Any]) -> dict[str, Any]:
        """Run dbt tests on the models produced by transform."""
        import subprocess

        result = subprocess.run(
            ["dbt", "test", "--select", "stg_events__deduped+"],
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            log.error("dbt test stderr: %s", result.stderr[-2000:])
            raise RuntimeError("dbt test failed — downstream load aborted")

        return {**transform_meta, "dbt_test_status": "passed"}

    # ── Task: load ────────────────────────────────────────────────────────────
    @task(sla=timedelta(minutes=30))
    def load(test_meta: dict[str, Any]) -> dict[str, Any]:
        """Materialise the gold mart table in Snowflake."""
        import subprocess

        logical_date = test_meta["logical_date"]
        log.info("Loading gold mart for date=%s", logical_date)

        result = subprocess.run(
            [
                "dbt", "run",
                "--select", "tag:mart",
                "--vars", f'{{"run_date": "{logical_date}"}}',
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            log.error("dbt mart run stderr: %s", result.stderr[-2000:])
            raise RuntimeError(f"Mart dbt run failed with exit code {result.returncode}")

        return {**test_meta, "load_status": "success"}

    # ── Task: notify ──────────────────────────────────────────────────────────
    @task(trigger_rule=TriggerRule.ALL_SUCCESS)
    def notify(load_meta: dict[str, Any]) -> None:
        """Emit a structured completion event. Extend with downstream triggers."""
        log.info(
            "Pipeline completed",
            extra={
                "dag_id": "daily_crm_etl",
                "logical_date": load_meta.get("logical_date"),
                "row_count": load_meta.get("row_count"),
                "dbt_run_status": load_meta.get("dbt_run_status"),
                "dbt_test_status": load_meta.get("dbt_test_status"),
                "load_status": load_meta.get("load_status"),
            },
        )

    # ── Wiring ────────────────────────────────────────────────────────────────
    start = EmptyOperator(task_id="start")
    end = EmptyOperator(task_id="end", trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS)

    extract_result = extract()
    validate_result = validate(extract_result)
    transform_result = transform(validate_result)
    test_result = run_tests(transform_result)
    load_result = load(test_result)
    notify_result = notify(load_result)

    start >> extract_result
    notify_result >> end


# Instantiate the DAG
daily_crm_etl()
