# AGENTS.md - Meridian Air dbt project

> Cortex Code reads this file every session. Keep it short. Every token here
> is a token you cannot use later. Edit live during the demo to swap in
> customer-specific standards. Each section is self-contained; delete what
> you don't need.

## Project context
This is the Meridian Air Operations dbt project. It runs via **dbt Projects on Snowflake** (`CREATE DBT PROJECT ... EXECUTE DBT PROJECT ...`). Sources live in `RAW.*`; outputs land in `ANALYTICS_STAGING`, `ANALYTICS_INTERMEDIATE`, `ANALYTICS_MARTS`, `ANALYTICS_SNAPSHOTS` in the attendee's current database.

---

## Coding standards

### Model naming
- Staging: `stg_<source_table>` (one model per source table; no joins here).
- Intermediate: `int_<business_concept>`.
- Marts: `dim_<entity>` or `fct_<business_process>`.
- Snapshots: `<entity>_<tracked_attribute>` e.g. `aircraft_owner`.
- <EDIT_ME: customer may use different prefixes - e.g. LNRS uses `stg__`, `int__`, `fct__` with double underscore>

### SQL style
- Lowercase keywords (`select`, `from`, `where`).
- One column per line in `select`.
- CTE-first: every model is a sequence of `with … as ( ... )` CTEs ending in `select * from <final_cte>`.
- No `select *` in final SELECT; always enumerate columns in marts.
- Column aliases on their own line, right-aligned under the first column.
- <EDIT_ME: insert company linting rule, e.g. sqlfluff config path>

### Required CTE pattern for staging models
```sql
with source as (
    select * from {{ source('raw', '<table>') }}
),
renamed as (
    select
        <col1>  as <renamed_col1>,
        <col2>  as <renamed_col2>,
        _loaded_at       as loaded_at,
        _source_system   as source_system,
        _ingest_batch_id as ingest_batch_id
    from source
)
select * from renamed
```

### Materializations
- Staging: `view` (never a table; data freshness matters).
- Intermediate: `table` by default; `incremental` when > 10M rows.
- Marts: `table`.
- <EDIT_ME: company override, e.g. "dynamic_table with target_lag='10 minutes' for dim_*" >

### Incremental model rules
- `unique_key` MUST be a column with an enforced or demonstrable 1:1 to rows. Never a foreign key.
- Always include a `unique` + `not_null` dbt test on `unique_key`.
- Cursor column goes in `is_incremental()` guard; prefer event timestamps over dates.
- After changing `unique_key` or strategy: full-refresh.
- <EDIT_ME: company rule - e.g. "all incrementals must set on_schema_change='sync_all_columns'">

### Snapshot rules
- Use `check` strategy over `timestamp` unless you have an immutable `updated_at` from source.
- `target_schema` lives in a shared `snapshots` schema, never in `marts`.
- Snapshot keys never change; if the key changes upstream, that is a new entity.

### Testing
- Every PK: `not_null` + `unique`.
- Every FK: `not_null` + `relationships` test to its referenced table.
- Every categorical column with fixed values: `accepted_values`.
- Singular tests live in `tests/`; name them `assert_<expected_invariant>.sql`.
- <EDIT_ME: company rule - e.g. "all marts must have a freshness test via dbt-utils.recency">

---

## Cortex AI conventions

### AI functions in dbt models
- Use `SNOWFLAKE.CORTEX.AI_CLASSIFY` for bounded categorical labeling.
- Use `SNOWFLAKE.CORTEX.AI_EXTRACT` for structured field extraction.
- Use `SNOWFLAKE.CORTEX.AI_COMPLETE` only when the above two don't fit.
- Default model: `claude-3-5-sonnet`. Fallback: `llama3.1-8b`.
- <EDIT_ME: company policy - e.g. "only approved models: llama3.1-8b, claude-3-5-sonnet">

### Cost guards
- First build of any AI-enriched model must include a Jinja `limit` of ~20 rows so the full-table cost cannot surprise someone.
- After confirming, remove the limit in the same model file (don't leave it toggleable via var - too easy to re-enable by accident).

---

## Semantic view conventions
- Snowflake SEMANTIC VIEW DDL uses **inverted syntax**: `alias AS expression`, not `expression AS alias`.
- Section order is fixed: `TABLES` -> `RELATIONSHIPS` -> `FACTS` -> `DIMENSIONS` -> `METRICS`.
- FACTS are per-row atoms; METRICS aggregate FACTS or raw columns.
- Add `WITH SYNONYMS` on dimensions business users will ask about by other names.

---

## Review gates (what to always check before accepting a diff)
1. Does the staging model follow the `source` + `renamed` CTE pattern?
2. Are all required tests declared in the sibling `_<layer>.yml`?
3. Does the incremental model have `unique` + `not_null` tests on `unique_key`?
4. Is every AI function call guarded by a first-pass `limit`?
5. Do model names match the naming convention above?
6. <EDIT_ME: company rule - e.g. "no business logic in staging", "PII columns must be masked via dbt macros/mask_pii">

---

## Things to never do
- Do not `select *` in marts.
- Do not put business logic in staging models.
- Do not hardcode database or schema names; always use `{{ source() }}`, `{{ ref() }}`, or `{{ env_var() }}`.
- Do not use `var()` to work around a missing `env_var()`; add the variable to `env.yml` instead.
- Do not drop a snapshot and recreate it; use `dbt snapshot` to amend.
- <EDIT_ME: company red-line, e.g. "do not add an external package without security review">

---

## Company-specific additions
<!-- EDIT_ME - paste 3 to 6 rules from the customer's actual dbt handbook here.
Examples to prompt the room with:
  - "All models must have `meta.owner` set."
  - "Column-level tests for PII must use the `pii_scrub` macro."
  - "Tag every mart with `tag: ['tier_1']` or `['tier_2']` for freshness SLAs."
  - "Pull requests require a `dbt docs generate` run."
-->
