# Meridian Air dbt Project

Hands-on-lab starter project for the LNRS x Cortex Code session.

## What's here
- `dbt_project.yml` - project config, staging/intermediate/marts folder layering
- `dbt_projects_profiles.yml` - profile used by dbt Projects on Snowflake
- `env.yml` - environment variables (DBT_DATABASE, DBT_SCHEMA)
- `models/sources.yml` - source table declarations for the `raw` schema
- `models/staging/_example__stg_aircraft.sql` - reference staging model; copy this shape
- `macros/normalize_iata.sql` - Jinja macro applied in Module 2
- `snapshots/`, `tests/` - empty; filled in during the lab

## What you build during the lab
- Module 2: `stg_airports`, `stg_schedules`, `stg_flights`, `stg_maintenance_events`, `stg_aviation_bulletins`
- Module 3: `int_flight_events` (incremental), `aircraft_owner_snapshot`
- Module 4: `int_bulletins_classified`, `int_bulletins_extracted`, `fct_bulletin_impact`
- Module 5: `dim_aircraft`, `dim_airport`, `fct_flight_performance`, and the `meridian_air_ops` semantic view
