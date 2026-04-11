-- dbt incremental model: stg_events__deduped.sql
-- Layer: staging (light deduplication before promotion to silver)
--
-- Schema tests (define in schema.yml alongside this file):
--
-- models:
--   - name: stg_events__deduped
--     description: "Deduplicated event stream from the raw CRM source."
--     columns:
--       - name: event_id
--         description: "Unique event identifier."
--         tests:
--           - not_null
--           - unique
--       - name: user_id
--         description: "FK to dim_users."
--         tests:
--           - not_null
--           - relationships:
--               to: ref('dim_users')
--               field: user_id
--       - name: event_type
--         description: "Categorical event classifier."
--         tests:
--           - not_null
--           - accepted_values:
--               values: ['page_view', 'click', 'form_submit', 'purchase', 'logout']
--       - name: event_timestamp
--         tests:
--           - not_null

{{
    config(
        materialized='incremental',
        unique_key='event_id',
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        cluster_by=['event_date'],
        tags=['staging', 'events'],
        meta={
            'owner': 'data-engineering',
            'pii': false,
            'sla_freshness_hours': 1
        }
    )
}}

with source as (

    select * from {{ source('raw_crm', 'events') }}

    {% if is_incremental() %}
        -- Only process records newer than the current table's high-water mark.
        -- Subtract 1 hour to capture any late-arriving records in the overlap window.
        where event_timestamp > (
            select dateadd('hour', -1, max(event_timestamp))
            from {{ this }}
        )
    {% endif %}

),

deduplicated as (

    select
        event_id,
        user_id,
        session_id,
        event_type,
        event_timestamp,
        event_timestamp::date                               as event_date,

        -- Coerce raw properties blob to a typed struct; nullify malformed rows
        try_parse_json(raw_properties)                      as properties,

        -- Standardise nullable string columns
        nullif(trim(lower(referrer_url)), '')               as referrer_url,
        nullif(trim(device_type), '')                       as device_type,

        -- Audit columns
        _loaded_at,
        '{{ invocation_id }}'                               as _dbt_invocation_id

    from source

    -- Deduplicate: keep the latest record per event_id within this micro-batch.
    -- Using QUALIFY instead of a subquery avoids a full re-scan.
    qualify row_number() over (
        partition by event_id
        order by _loaded_at desc
    ) = 1

)

select * from deduplicated
