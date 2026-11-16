-- Reference staging model. Copy this shape when authoring the rest.
-- Conventions:
--   * One model per source table, named stg_<source_table>
--   * CTE named `source` pulls from `{{ source(...) }}`
--   * CTE named `renamed` does column rename + light typing only
--   * Final SELECT has no transformations beyond what `renamed` did
--   * No business logic in staging; that lives in intermediate/
with source as (

    select * from {{ source('raw', 'aircraft') }}

),

renamed as (

    select
        aircraft_id,
        tail_number,
        aircraft_type,
        manufacturer,
        seats                            as seat_count,
        owner_entity,
        delivery_date,
        _loaded_at                       as loaded_at,
        _source_system                   as source_system,
        _ingest_batch_id                 as ingest_batch_id

    from source

)

select * from renamed
