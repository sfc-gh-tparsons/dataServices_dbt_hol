# Meridian Air Ops HOL — Attendee Walkthrough

Welcome. Over the next ~2 hours you will build a dbt pipeline on Snowflake using Cortex Code. By the end you will have:

- A live `MERIDIAN_DBT` project object in your Snowflake database
- Staging, intermediate, and marts models produced by prompting Cortex Code
- An incremental model and a snapshot
- Three AI-enriched models using `AI_CLASSIFY` and `AI_EXTRACT`
- A semantic view on top of your marts, queryable via Cortex Analyst

**Keep this doc open in one tab, Cortex Code open in another.**

---

## Module 0 — Kickoff & Env Check (10 min)

### 0.1 Confirm your workspace
You have a pre-provisioned Snowflake user, database, warehouse, and workspace. Open your workspace in Snowsight.

### 0.2 Open this walkthrough + your Cortex Code chat side by side
You should see two things on your screen:
- This walkthrough
- A Cortex Code chat panel

### 0.3 First prompt (sanity check)
Paste this into Cortex Code:

```
Show me which database, warehouse, schema, and role I'm currently using in Snowflake.
```

Expected: Cortex Code runs a `SELECT CURRENT_DATABASE(), ...` and reports your DB/WH. Confirm the DB matches your assigned environment.

---

## Module 1 — Project Bootstrap (10 min)

### 1.1 Run the data setup script
In your workspace, open `00_setup_data.sql` (shared with you as a Snowflake artifact). Run it top to bottom. Expected runtime: ~45 seconds.

This creates `RAW.AIRCRAFT`, `RAW.AIRPORTS`, `RAW.SCHEDULES`, `RAW.FLIGHTS`, `RAW.MAINTENANCE_EVENTS`, `RAW.AVIATION_BULLETINS`. The last one uses `AI_COMPLETE` to generate 200 NOTAM-style bulletins.

The last query returns row counts for each table. Expected:

| Table | Rows (approx) |
|---|---|
| AIRCRAFT | 300 |
| AIRPORTS | ~500 |
| SCHEDULES | 20,000 |
| FLIGHTS | 100,000 |
| MAINTENANCE_EVENTS | 5,000 |
| AVIATION_BULLETINS | 50 |

### 1.2 Run the dbt project deploy script
Open `01_deploy_dbt_project.sql` and run it top to bottom. Expected runtime: ~30 seconds.

The last two statements show:
- `SHOW DBT PROJECTS` — you should see `MERIDIAN_DBT`
- `EXECUTE DBT PROJECT ... ARGS = 'build --select source:raw+1 --full-refresh'` — a smoke build that resolves sources and the one reference model. All ~12 source tests pass.

### 1.3 Ask Cortex Code to orient you
Paste:

```
List the files in my MERIDIAN_DBT project and give me a 5-line summary of what each does. I'm new to dbt — explain `dbt_project.yml`, `dbt_projects_profiles.yml`, and `env.yml` like I've never seen them.
```

Expected: Cortex Code reads the files from the project stage and gives you a plain-English tour.

---

## Module 2 — Staging with Grounded Authoring (20 min)

**Goal:** author 5 staging models following the shape of `_example__stg_aircraft.sql`.

### 2.1 Author `stg_airports`
Paste:

```
Use CoCo to look up RAW.AIRPORTS in my current database and author a staging model stg_airports.sql in models/staging/ following the convention in _example__stg_aircraft.sql. Apply the normalize_iata macro to both iata_code and icao_code columns. Keep the audit columns.
```

Review the proposed diff. Accept.

### 2.2 Author `stg_schedules`, `stg_flights`, `stg_maintenance_events`, `stg_aviation_bulletins`
Paste one at a time (or batch them — up to you):

```
Author stg_schedules.sql following the same convention as stg_airports.sql.
```
```
Author stg_flights.sql following the same convention. Keep every column from RAW.FLIGHTS.
```
```
Author stg_maintenance_events.sql following the same convention.
```
```
Author stg_aviation_bulletins.sql following the same convention.
```

### 2.3 Deploy and build
Paste:

```
Redeploy the MERIDIAN_DBT project with my new staging models, then execute `build --select staging+`.
```

Expected: 6 staging models materialize (5 new + 1 reference) as views in the `<DB>.ANALYTICS_STAGING` schema. All source tests continue to pass.

> **Stretch for experienced attendees**: ask Cortex Code to add a `not_null` test on every `*_id` column across the staging layer by extending `models/staging/_staging.yml`.

---

## Module 3 — Incremental & Snapshot (20 min)

### 3.1 Author the incremental intermediate model
Paste:

```
Author an incremental model int_flight_events.sql in models/intermediate/.
- Source: ref('stg_flights')
- materialized: incremental
- unique_key: flight_id
- incremental_strategy: merge
- incremental filter: scheduled_departure_ts > (select coalesce(max(scheduled_departure_ts), '1900-01-01') from {{ this }})
- Derive a calculated column `is_late` = (flight_status in ('DELAYED','DIVERTED') or delay_minutes > 15).
- Keep audit columns.
In models/intermediate/_intermediate.yml add generic tests on int_flight_events:
- unique on flight_id
- not_null on flight_id
- not_null on schedule_id
```

### 3.2 Author the snapshot
Paste:

```
Author a snapshot in snapshots/aircraft_owner.sql against ref('stg_aircraft'):
- strategy: check
- check_cols: ['owner_entity']
- unique_key: aircraft_id
This tracks SCD-2 changes to who owns each tail.
```

### 3.3 Deploy and first full build
```
Redeploy and run `build --select +int_flight_events --full-refresh` then `snapshot`.
```

Expected: `int_flight_events` has ~100,000 rows. All tests pass.

### 3.4 Deliberate break-and-fix (teaching moment)

In real pipelines, the dangerous moment isn't the first build — it's the second, when new source data arrives. We'll simulate that now.

**Step A — Simulate a new batch of RAW flights arriving.** Paste:

```
Insert 500 new rows into RAW.FLIGHTS that look like a fresh ingest batch:
- Generate new flight_id values, e.g. 'FL-NEW-00001' through 'FL-NEW-00500'.
- scheduled_departure_ts should be CURRENT_TIMESTAMP() + a random number of hours between 1 and 72 (so they pass the is_incremental() cursor).
- schedule_id values should be drawn from EXISTING schedule_ids in RAW.SCHEDULES (reuse them — this mimics weekly scheduled flights repeating).
- aircraft_id drawn from existing aircraft.
- origin_iata / dest_iata drawn from existing airports.
- Set flight_status = 'ON_TIME' for simplicity.
- Use the same _SOURCE_SYSTEM and a new _INGEST_BATCH_ID = 'BATCH_NEW_ARRIVALS'.
Run the insert. Then show me the count of RAW.FLIGHTS and SELECT 3 of the new rows.
```

**Step B — Run a normal (non-full-refresh) incremental build to prove the pipeline is healthy.** Paste:

```
Execute `build --select int_flight_events` (no --full-refresh).
```

Expected: 500 new rows merge in cleanly on `flight_id`. All tests pass. Count is now ~100,500.

**Step C — Break it.** Paste:

```
Change the unique_key of int_flight_events from `flight_id` to `schedule_id`, keep merge strategy, redeploy the project.
```

**Step D — Simulate another batch arriving and trigger the failure.** Paste:

```
Insert another 500 rows into RAW.FLIGHTS the same way as before — fresh flight_ids 'FL-NEW2-00001'..'FL-NEW2-00500', scheduled_departure_ts in the next 24-96 hours, schedule_ids REUSED from existing. Then execute `build --select int_flight_events` (no --full-refresh).
```

Expected error (Snowflake MERGE guard against nondeterministic matches):

```
Duplicate row detected during DML action
```

or

```
A MERGE statement attempted to update or delete the same row more than once
```

This happens because the 500 incoming source rows share `schedule_id` values with each other **and** with multiple existing target rows. Snowflake MERGE refuses to pick a winner.

**Step E — Diagnose and fix.** Paste (including the actual error text):

```
That build just failed. Here's the error:
[paste the error from your output]

Explain what happened in one paragraph, then:
1. Revert unique_key back to `flight_id`.
2. Redeploy.
3. Run `build --select int_flight_events --full-refresh` because we need to rebuild from scratch after the incremental logic change.
```

Expected: Cortex Code explains that `schedule_id` is not unique in the source so the MERGE source-to-target match is ambiguous, reverts to `flight_id`, and runs a full refresh to clean any partial state. The `unique` test on `flight_id` passes, confirming the fix.

**Why this matters**: `unique_key` is a dbt-side declaration, not an enforced constraint. `--full-refresh` ignores it entirely. The bug only surfaces when a MERGE actually has to pick rows — which is the moment production data starts flowing. Catching this kind of mistake in the authoring loop with Cortex Code (rather than in a 3am pager) is the point of the exercise.

---

## Module 4 — Cortex AI Inside dbt (25 min)

This is the showcase module.

### 4.1 Classify bulletins
Paste:

```
Author int_bulletins_classified.sql in models/intermediate/.
- Source: ref('stg_aviation_bulletins')
- Add a column `category` = SNOWFLAKE.CORTEX.AI_CLASSIFY(bulletin_text, ['weather','mechanical','atc','regulatory','security'])
- Keep bulletin_id, issued_at, source, bulletin_text, category, and audit columns.
Add an accepted_values test on `category`.
```

### 4.2 Extract structured facts from bulletins
Paste:

```
Author int_bulletins_extracted.sql in models/intermediate/.
- Source: ref('stg_aviation_bulletins')
- Use SNOWFLAKE.CORTEX.AI_EXTRACT(bulletin_text, ['effective_date','airport_iata','severity']) to produce three columns.
- Cast effective_date to DATE; leave airport_iata and severity as strings.
- Keep bulletin_id and audit columns.
```

### 4.3 Join AI output to flight events
Paste:

```
Author fct_bulletin_impact.sql in models/marts/.
Join int_bulletins_classified and int_bulletins_extracted on bulletin_id.
Then for each bulletin row, join to stg_flights on origin_iata = airport_iata and flight_date within 7 days of effective_date.
One row per (bulletin_id, flight_id). Keep bulletin_text, category, severity, flight_id, flight_date, origin_iata, dest_iata, flight_status, delay_minutes.
Add not_null tests on bulletin_id and flight_id.
```

### 4.4 Deploy, build, verify
```
Redeploy and run `build --select +fct_bulletin_impact`.
```

Preview the top rows:

```
Show me the top 10 bulletins that impacted the most flights.
```

---

## Module 5 — Semantic View on Marts (15 min)

### 5.1 Author the supporting marts
```
Author dim_aircraft.sql in models/marts/ from the aircraft_owner snapshot (dbt_valid_from, dbt_valid_to -> is_current flag). Add dim_airport.sql from stg_airports (current state only). Add fct_flight_performance.sql joining int_flight_events to dim_aircraft (current) and dim_airport (origin + dest).
```

### 5.2 Author the semantic view DDL
```
Create a Snowflake SEMANTIC VIEW named `meridian_air_ops` in the marts schema over the marts fact and dim tables. Metrics: 
- flights = count(*)
- on_time_pct = sum(case when is_late then 0 else 1 end) / nullifzero(count(*)) * 100
- avg_delay_min = avg(delay_minutes)
- impacted_flights = count(distinct flight_id from fct_bulletin_impact)
Dimensions: origin_airport, origin_country, dest_airport, aircraft_type, aircraft_owner, flight_month (date_trunc('month', flight_date)).
Verify it with reflect_semantic_model.
```

Note: Snowflake semantic views use an inverted `alias AS expression` syntax (`alias AS expression`, not `expression AS alias`). If Cortex Code writes it the standard way first, feed back the reflect error and ask it to invert.

### 5.3 Query the view
```
Use cortex analyst against meridian_air_ops: "Which 5 airports had the lowest on-time percentage last month, and how many flights were impacted by a bulletin?"
```

Try one more:
```
"For each aircraft owner, what was the average delay in minutes over the last 180 days?"
```

---

## Module 6 — Wrap (5 min)

Recap the loop:

1. **Draft** — let Cortex Code author the SQL/model.
2. **Run** — deploy and build.
3. **Test** — dbt tests + eyeballing marts.
4. **Fix** — paste errors back into chat.

Then open `TAKE_HOME.md` and pick where you'll go next.

---

## Floating Q&A / Buffer (15 min)
Open mic.

---

## Appendix — If you get stuck

| Symptom | Likely cause | Fix |
|---|---|---|
| `SHOW DBT PROJECTS` returns nothing | 01_deploy_dbt_project.sql didn't finish | Re-run it. Idempotent. |
| `build` fails with "relation RAW.X does not exist" | 00_setup_data.sql didn't run or ran in wrong DB | Re-run with correct DB in session |
| `AI_COMPLETE` returns NULL for bulletins | Model name wrong or no AI access | Use `llama3.1-8b` instead of `claude-3-5-sonnet` |
| Incremental model re-runs produce zero rows | `is_incremental()` guard matched nothing | Run with `--full-refresh` once |
| MERGE fails with "Duplicate row detected during DML" | `unique_key` isn't actually unique in source | Revert to a true PK, then `--full-refresh` |
| Semantic view `reflect` fails with "unknown expression" | Inverted alias-first syntax | Ask Cortex Code to flip `expr AS alias` -> `alias AS expr` |
