-- =====================================================================
-- Meridian Air Operations HOL - Step 00: Generate raw source data
-- =====================================================================
-- Run this ONCE in your personal workspace against your personal database
-- and warehouse. It is idempotent - safe to re-run.
--
-- What it does:
--   1. Creates schema RAW in your current database
--   2. Creates 6 raw source tables
--   3. Populates them with synthetic Meridian Air operations data
--   4. Uses AI_COMPLETE to generate 200 NOTAM-style aviation bulletins
--
-- Expected runtime on an XS warehouse: ~45 seconds (AI step dominates).
-- =====================================================================

-- ----- 0. Session context ----------------------------------------------
-- Uses the warehouse and database you are currently connected to.
-- Confirm before running:
SELECT
  CURRENT_DATABASE()  AS db,
  CURRENT_SCHEMA()    AS sch,
  CURRENT_WAREHOUSE() AS wh,
  CURRENT_ROLE()      AS role;

-- ----- 1. Schema -------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS RAW
  COMMENT = 'Raw source data for Meridian Air Operations HOL';

USE SCHEMA RAW;

-- A single ingest batch id for this run (so re-runs are distinguishable)
SET BATCH_ID = 'BATCH_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDDHH24MISS');

-- ======================================================================
-- 2. AIRCRAFT (300 rows) - reference
-- ======================================================================
CREATE OR REPLACE TABLE AIRCRAFT AS
WITH types AS (
  SELECT * FROM VALUES
    ('A320', 'Airbus',   180),
    ('A321', 'Airbus',   220),
    ('A350', 'Airbus',   325),
    ('B737', 'Boeing',   189),
    ('B777', 'Boeing',   396),
    ('B787', 'Boeing',   296),
    ('E190', 'Embraer',  114)
  AS t(aircraft_type, manufacturer, seats)
),
owners AS (
  SELECT * FROM VALUES
    ('Northgate Leasing'),
    ('Polaris Aviation Capital'),
    ('Avion Trust'),
    ('Keystone Fleet Partners'),
    ('Helios Aircraft Holdings')
  AS t(owner_entity)
),
n AS (
  SELECT SEQ4() + 1 AS i
  FROM TABLE(GENERATOR(ROWCOUNT => 300))
),
picked AS (
  SELECT
    n.i,
    'AC-' || LPAD(n.i::VARCHAR, 5, '0')                              AS aircraft_id,
    'N'  || LPAD((10000 + UNIFORM(1, 89999, HASH(n.i)))::VARCHAR, 5, '0')
         || 'MH'                                                     AS tail_number,
    types.aircraft_type,
    types.manufacturer,
    types.seats,
    owners.owner_entity,
    DATEADD(day,
            -UNIFORM(0, 7300, HASH(n.i + 1)),
            CURRENT_DATE())                                          AS delivery_date
  FROM n
  JOIN types
    ON MOD(n.i, 7) = CASE types.aircraft_type
                       WHEN 'A320' THEN 0 WHEN 'A321' THEN 1
                       WHEN 'A350' THEN 2 WHEN 'B737' THEN 3
                       WHEN 'B777' THEN 4 WHEN 'B787' THEN 5
                       WHEN 'E190' THEN 6 END
  JOIN owners
    ON MOD(n.i, 5) = CASE owners.owner_entity
                       WHEN 'Northgate Leasing'        THEN 0
                       WHEN 'Polaris Aviation Capital' THEN 1
                       WHEN 'Avion Trust'              THEN 2
                       WHEN 'Keystone Fleet Partners'  THEN 3
                       WHEN 'Helios Aircraft Holdings' THEN 4 END
)
SELECT
  aircraft_id, tail_number, aircraft_type, manufacturer, seats,
  owner_entity, delivery_date,
  CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS _LOADED_AT,
  'MERIDIAN_FLEET_MGMT'              AS _SOURCE_SYSTEM,
  $BATCH_ID                          AS _INGEST_BATCH_ID
FROM picked;

-- ======================================================================
-- 3. AIRPORTS (50 real + synthetic noise = ~500 rows) - reference
-- ======================================================================
-- Inline a curated set of 50 major real airports so Analyst answers
-- feel recognizable, then pad with synthetic entries to reach ~500.
CREATE OR REPLACE TABLE AIRPORTS AS
WITH real_airports AS (
  SELECT * FROM VALUES
    ('ATL','KATL','Hartsfield-Jackson Atlanta Intl','Atlanta','United States','America/New_York',33.6407,-84.4277),
    ('LAX','KLAX','Los Angeles Intl','Los Angeles','United States','America/Los_Angeles',33.9416,-118.4085),
    ('ORD','KORD','Chicago O''Hare Intl','Chicago','United States','America/Chicago',41.9742,-87.9073),
    ('DFW','KDFW','Dallas/Fort Worth Intl','Dallas','United States','America/Chicago',32.8998,-97.0403),
    ('DEN','KDEN','Denver Intl','Denver','United States','America/Denver',39.8561,-104.6737),
    ('JFK','KJFK','John F. Kennedy Intl','New York','United States','America/New_York',40.6413,-73.7781),
    ('SFO','KSFO','San Francisco Intl','San Francisco','United States','America/Los_Angeles',37.6213,-122.3790),
    ('SEA','KSEA','Seattle-Tacoma Intl','Seattle','United States','America/Los_Angeles',47.4502,-122.3088),
    ('LAS','KLAS','Harry Reid Intl','Las Vegas','United States','America/Los_Angeles',36.0840,-115.1537),
    ('MCO','KMCO','Orlando Intl','Orlando','United States','America/New_York',28.4312,-81.3081),
    ('EWR','KEWR','Newark Liberty Intl','Newark','United States','America/New_York',40.6895,-74.1745),
    ('BOS','KBOS','Boston Logan Intl','Boston','United States','America/New_York',42.3656,-71.0096),
    ('MIA','KMIA','Miami Intl','Miami','United States','America/New_York',25.7959,-80.2870),
    ('PHX','KPHX','Phoenix Sky Harbor Intl','Phoenix','United States','America/Phoenix',33.4342,-112.0116),
    ('IAH','KIAH','George Bush Intercontinental','Houston','United States','America/Chicago',29.9902,-95.3368),
    ('LHR','EGLL','London Heathrow','London','United Kingdom','Europe/London',51.4700,-0.4543),
    ('CDG','LFPG','Paris Charles de Gaulle','Paris','France','Europe/Paris',49.0097,2.5479),
    ('AMS','EHAM','Amsterdam Schiphol','Amsterdam','Netherlands','Europe/Amsterdam',52.3105,4.7683),
    ('FRA','EDDF','Frankfurt Intl','Frankfurt','Germany','Europe/Berlin',50.0379,8.5622),
    ('MAD','LEMD','Madrid Barajas','Madrid','Spain','Europe/Madrid',40.4719,-3.5626),
    ('BCN','LEBL','Barcelona El Prat','Barcelona','Spain','Europe/Madrid',41.2974,2.0833),
    ('FCO','LIRF','Rome Fiumicino','Rome','Italy','Europe/Rome',41.8003,12.2389),
    ('MUC','EDDM','Munich Intl','Munich','Germany','Europe/Berlin',48.3538,11.7861),
    ('ZRH','LSZH','Zurich Intl','Zurich','Switzerland','Europe/Zurich',47.4647,8.5492),
    ('VIE','LOWW','Vienna Intl','Vienna','Austria','Europe/Vienna',48.1103,16.5697),
    ('DUB','EIDW','Dublin Airport','Dublin','Ireland','Europe/Dublin',53.4213,-6.2701),
    ('CPH','EKCH','Copenhagen Kastrup','Copenhagen','Denmark','Europe/Copenhagen',55.6180,12.6476),
    ('ARN','ESSA','Stockholm Arlanda','Stockholm','Sweden','Europe/Stockholm',59.6519,17.9186),
    ('OSL','ENGM','Oslo Gardermoen','Oslo','Norway','Europe/Oslo',60.1939,11.1004),
    ('HEL','EFHK','Helsinki Vantaa','Helsinki','Finland','Europe/Helsinki',60.3172,24.9633),
    ('IST','LTFM','Istanbul Airport','Istanbul','Turkey','Europe/Istanbul',41.2753,28.7519),
    ('DXB','OMDB','Dubai Intl','Dubai','United Arab Emirates','Asia/Dubai',25.2532,55.3657),
    ('DOH','OTHH','Hamad Intl','Doha','Qatar','Asia/Qatar',25.2731,51.6080),
    ('SIN','WSSS','Singapore Changi','Singapore','Singapore','Asia/Singapore',1.3644,103.9915),
    ('HKG','VHHH','Hong Kong Intl','Hong Kong','China','Asia/Hong_Kong',22.3080,113.9185),
    ('NRT','RJAA','Tokyo Narita','Tokyo','Japan','Asia/Tokyo',35.7720,140.3929),
    ('HND','RJTT','Tokyo Haneda','Tokyo','Japan','Asia/Tokyo',35.5494,139.7798),
    ('ICN','RKSI','Seoul Incheon','Seoul','South Korea','Asia/Seoul',37.4602,126.4407),
    ('PEK','ZBAA','Beijing Capital','Beijing','China','Asia/Shanghai',40.0799,116.6031),
    ('PVG','ZSPD','Shanghai Pudong','Shanghai','China','Asia/Shanghai',31.1434,121.8052),
    ('SYD','YSSY','Sydney Kingsford Smith','Sydney','Australia','Australia/Sydney',-33.9399,151.1753),
    ('MEL','YMML','Melbourne Tullamarine','Melbourne','Australia','Australia/Melbourne',-37.6690,144.8410),
    ('AKL','NZAA','Auckland Airport','Auckland','New Zealand','Pacific/Auckland',-37.0082,174.7850),
    ('YYZ','CYYZ','Toronto Pearson','Toronto','Canada','America/Toronto',43.6777,-79.6248),
    ('YVR','CYVR','Vancouver Intl','Vancouver','Canada','America/Vancouver',49.1967,-123.1815),
    ('GRU','SBGR','Sao Paulo Guarulhos','Sao Paulo','Brazil','America/Sao_Paulo',-23.4356,-46.4731),
    ('MEX','MMMX','Mexico City Intl','Mexico City','Mexico','America/Mexico_City',19.4361,-99.0719),
    ('JNB','FAOR','Johannesburg OR Tambo','Johannesburg','South Africa','Africa/Johannesburg',-26.1392,28.2460),
    ('CAI','HECA','Cairo Intl','Cairo','Egypt','Africa/Cairo',30.1219,31.4056),
    ('DEL','VIDP','Delhi Indira Gandhi','Delhi','India','Asia/Kolkata',28.5562,77.1000)
  AS t(iata, icao, name, city, country, tz, lat, lon)
),
seq AS (
  SELECT SEQ4() + 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 450))
),
synthetic AS (
  -- 450 synthetic padding airports so marts have variety
  SELECT
    i,
    -- synthetic IATA: 3 random uppercase letters that don't collide with real ones
    CHR(65 + MOD(UNIFORM(0, 25, HASH(i)),    26)) ||
    CHR(65 + MOD(UNIFORM(0, 25, HASH(i+77)), 26)) ||
    CHR(65 + MOD(UNIFORM(0, 25, HASH(i+99)), 26))               AS iata,
    'Z' || LPAD(i::VARCHAR, 3, '0')                               AS icao,
    'Synthetic Regional ' || i::VARCHAR                           AS name,
    'City ' || i::VARCHAR                                         AS city,
    'Synthetica'                                                  AS country,
    'UTC'                                                         AS tz,
    UNIFORM(-60, 60,   HASH(i+1))::FLOAT                        AS lat,
    UNIFORM(-180, 180, HASH(i+2))::FLOAT                        AS lon
  FROM seq
),
combined AS (
  SELECT iata, icao, name, city, country, tz, lat, lon FROM real_airports
  UNION ALL
  SELECT iata, icao, name, city, country, tz, lat, lon FROM synthetic
),
dedup AS (
  SELECT iata, icao, name, city, country, tz, lat, lon,
         ROW_NUMBER() OVER (PARTITION BY iata ORDER BY name) AS rn
  FROM combined
)
SELECT
  'AP-' || LPAD(ROW_NUMBER() OVER (ORDER BY iata)::VARCHAR, 5, '0') AS airport_id,
  iata     AS iata_code,
  icao     AS icao_code,
  name     AS airport_name,
  city,
  country,
  tz       AS timezone,
  lat      AS latitude,
  lon      AS longitude,
  CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS _LOADED_AT,
  'MERIDIAN_NETWORK_PLANNING'        AS _SOURCE_SYSTEM,
  $BATCH_ID                          AS _INGEST_BATCH_ID
FROM dedup
WHERE rn = 1;

-- ======================================================================
-- 4. SCHEDULES (~20k rows) - slow-change reference
-- ======================================================================
CREATE OR REPLACE TABLE SCHEDULES AS
WITH origins AS (
  SELECT airport_id, iata_code, ROW_NUMBER() OVER (ORDER BY airport_id) AS rn
  FROM AIRPORTS
),
dests AS (
  SELECT airport_id, iata_code, ROW_NUMBER() OVER (ORDER BY airport_id DESC) AS rn
  FROM AIRPORTS
),
n AS (
  SELECT SEQ4() + 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 20000))
),
schedules AS (
  SELECT
    n.i,
    'SCH-' || LPAD(n.i::VARCHAR, 6, '0') AS schedule_id,
    'MH' || LPAD((100 + MOD(n.i, 8999))::VARCHAR, 4, '0') AS flight_number,
    o.iata_code AS origin_iata,
    d.iata_code AS dest_iata,
    TIME_FROM_PARTS(
      MOD(UNIFORM(5, 22, HASH(n.i)), 24),
      MOD(UNIFORM(0, 59, HASH(n.i+3)), 60),
      0
    ) AS scheduled_departure_local,
    TIME_FROM_PARTS(
      MOD(UNIFORM(6, 23, HASH(n.i+5)), 24),
      MOD(UNIFORM(0, 59, HASH(n.i+7)), 60),
      0
    ) AS scheduled_arrival_local,
    CASE MOD(n.i, 7)
      WHEN 0 THEN 'A320' WHEN 1 THEN 'A321' WHEN 2 THEN 'A350'
      WHEN 3 THEN 'B737' WHEN 4 THEN 'B777' WHEN 5 THEN 'B787'
      ELSE 'E190' END AS aircraft_type,
    DATEADD(day, -UNIFORM(0, 365, HASH(n.i+11)), CURRENT_DATE()) AS effective_from
  FROM n
  JOIN origins o ON MOD(n.i,     (SELECT COUNT(*) FROM origins)) + 1 = o.rn
  JOIN dests   d ON MOD(n.i + 3, (SELECT COUNT(*) FROM dests))   + 1 = d.rn
  WHERE o.iata_code <> d.iata_code
)
SELECT
  schedule_id, flight_number, origin_iata, dest_iata,
  scheduled_departure_local, scheduled_arrival_local, aircraft_type,
  effective_from,
  DATEADD(day, UNIFORM(90, 365, HASH(i+13)), effective_from) AS effective_to,
  CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS _LOADED_AT,
  'MERIDIAN_SCHED_PLANNING'          AS _SOURCE_SYSTEM,
  $BATCH_ID                          AS _INGEST_BATCH_ID
FROM schedules;

-- ======================================================================
-- 5. FLIGHTS (~100k rows, last 180 days) - incremental target in dbt
-- ======================================================================
CREATE OR REPLACE TABLE FLIGHTS AS
WITH sched AS (
  SELECT
    s.schedule_id, s.flight_number, s.origin_iata, s.dest_iata,
    s.scheduled_departure_local, s.scheduled_arrival_local,
    s.aircraft_type,
    ROW_NUMBER() OVER (ORDER BY s.schedule_id) AS sn
  FROM SCHEDULES s
),
air AS (
  SELECT aircraft_id, aircraft_type,
         ROW_NUMBER() OVER (PARTITION BY aircraft_type ORDER BY aircraft_id) AS an,
         COUNT(*)    OVER (PARTITION BY aircraft_type)                       AS cn
  FROM AIRCRAFT
),
n AS (
  SELECT SEQ4() + 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 100000))
),
flights AS (
  SELECT
    n.i,
    'FL-' || LPAD(n.i::VARCHAR, 7, '0') AS flight_id,
    s.schedule_id,
    a.aircraft_id,
    DATEADD(day, -UNIFORM(0, 180, HASH(n.i)), CURRENT_DATE()) AS flight_date,
    s.origin_iata, s.dest_iata,
    s.scheduled_departure_local, s.scheduled_arrival_local,
    -- Outcome mix: 80 on-time / 15 delayed / 3 cancelled / 2 diverted
    CASE
      WHEN UNIFORM(1, 100, HASH(n.i+1)) <= 80 THEN 'ON_TIME'
      WHEN UNIFORM(1, 100, HASH(n.i+1)) <= 95 THEN 'DELAYED'
      WHEN UNIFORM(1, 100, HASH(n.i+1)) <= 98 THEN 'CANCELLED'
      ELSE 'DIVERTED'
    END AS flight_status,
    CASE MOD(UNIFORM(0, 6, HASH(n.i+9)), 7)
      WHEN 0 THEN 'WX' WHEN 1 THEN 'MX' WHEN 2 THEN 'ATC'
      WHEN 3 THEN 'CREW' WHEN 4 THEN 'SEC' WHEN 5 THEN 'OTHER'
      ELSE NULL END AS delay_reason_code
  FROM n
  JOIN sched s ON MOD(n.i, (SELECT COUNT(*) FROM sched)) + 1 = s.sn
  JOIN air   a ON a.aircraft_type = s.aircraft_type
              AND MOD(n.i, a.cn) + 1 = a.an
)
SELECT
  flight_id, schedule_id, aircraft_id, flight_date,
  origin_iata, dest_iata,
  TIMESTAMP_FROM_PARTS(flight_date, scheduled_departure_local)::TIMESTAMP_NTZ AS scheduled_departure_ts,
  CASE WHEN flight_status = 'CANCELLED' THEN NULL
       ELSE DATEADD(minute,
                    IFF(flight_status = 'ON_TIME', 0, UNIFORM(10, 240, HASH(i+21))),
                    TIMESTAMP_FROM_PARTS(flight_date, scheduled_departure_local))::TIMESTAMP_NTZ
  END AS actual_departure_ts,
  TIMESTAMP_FROM_PARTS(flight_date, scheduled_arrival_local)::TIMESTAMP_NTZ AS scheduled_arrival_ts,
  CASE WHEN flight_status = 'CANCELLED' THEN NULL
       ELSE DATEADD(minute,
                    IFF(flight_status = 'ON_TIME', 0, UNIFORM(10, 240, HASH(i+23))),
                    TIMESTAMP_FROM_PARTS(flight_date, scheduled_arrival_local))::TIMESTAMP_NTZ
  END AS actual_arrival_ts,
  flight_status,
  CASE WHEN flight_status IN ('DELAYED','DIVERTED') THEN UNIFORM(10, 240, HASH(i+25))
       ELSE 0 END AS delay_minutes,
  CASE WHEN flight_status IN ('DELAYED','DIVERTED','CANCELLED') THEN delay_reason_code
       ELSE NULL END AS delay_reason_code,
  CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS _LOADED_AT,
  'MERIDIAN_OPS_CONTROL'             AS _SOURCE_SYSTEM,
  $BATCH_ID                          AS _INGEST_BATCH_ID
FROM flights;

-- ======================================================================
-- 6. MAINTENANCE_EVENTS (~5k rows) - snapshot target in dbt
-- ======================================================================
CREATE OR REPLACE TABLE MAINTENANCE_EVENTS AS
WITH air AS (
  SELECT aircraft_id, ROW_NUMBER() OVER (ORDER BY aircraft_id) AS rn,
         COUNT(*)   OVER ()                                    AS cn
  FROM AIRCRAFT
),
n AS (
  SELECT SEQ4() + 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 5000))
)
SELECT
  'ME-' || LPAD(n.i::VARCHAR, 6, '0') AS event_id,
  a.aircraft_id,
  DATEADD(day, -UNIFORM(0, 365, HASH(n.i)), CURRENT_DATE()) AS event_date,
  CASE MOD(n.i, 4)
    WHEN 0 THEN 'A_CHECK' WHEN 1 THEN 'B_CHECK'
    WHEN 2 THEN 'C_CHECK' ELSE 'AD_HOC' END AS event_type,
  CASE MOD(UNIFORM(0, 100, HASH(n.i+1)), 4)
    WHEN 0 THEN 'SCHEDULED' WHEN 1 THEN 'IN_PROGRESS'
    WHEN 2 THEN 'COMPLETED' ELSE 'DEFERRED' END AS status,
  DATEADD(hour, -UNIFORM(0, 72, HASH(n.i+3)), CURRENT_TIMESTAMP())::TIMESTAMP_NTZ AS last_updated_at,
  CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS _LOADED_AT,
  'MERIDIAN_MX_SYSTEM'               AS _SOURCE_SYSTEM,
  $BATCH_ID                          AS _INGEST_BATCH_ID
FROM n
JOIN air a ON MOD(n.i, a.cn) + 1 = a.rn;

-- ======================================================================
-- 7. AVIATION_BULLETINS (200 rows) - AI_COMPLETE generated
-- ======================================================================
-- Generate 200 realistic NOTAM-style bulletins via a single AI call.
-- We ask the model for a JSON array, then flatten into rows.
-- Cost: one AI_COMPLETE call with ~2k tokens output.

CREATE OR REPLACE TABLE LION_DB.RAW.AVIATION_BULLETINS AS
WITH airports AS (
  SELECT a.iata_code, a.airport_name, a.city,
         ROW_NUMBER() OVER (ORDER BY a.iata_code) AS rn,
         COUNT(*) OVER () AS cnt
  FROM LION_DB.RAW.AIRPORTS a
  WHERE a.country <> 'Synthetica'
    AND a.iata_code IN (SELECT DISTINCT origin_iata FROM LION_DB.RAW.FLIGHTS)
),
flight_window AS (
  SELECT MIN(flight_date) AS lo, MAX(flight_date) AS hi FROM LION_DB.RAW.FLIGHTS
),
slots AS (
  SELECT
    SEQ4() AS n,
    FLOOR(SEQ4() / 10) AS batch_no,
    MOD(SEQ4(), 10) + 1 AS slot,
    DECODE(MOD(SEQ4(), 5), 0, 'weather', 1, 'mechanical', 2, 'atc', 3, 'regulatory', 'security') AS category,
    DECODE(MOD(SEQ4(), 3), 0, 'LOW', 1, 'MEDIUM', 'HIGH') AS severity,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS r_airport,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS r_date
  FROM TABLE(GENERATOR(ROWCOUNT => 20))
),
specs AS (
  SELECT
    s.batch_no, s.slot, s.category, s.severity,
    a.iata_code, a.city,
    DATEADD(day, FLOOR(s.r_date * DATEDIFF(day, w.lo, w.hi)), w.lo) AS effective_date
  FROM slots s
  CROSS JOIN flight_window w
  JOIN airports a ON a.rn = LEAST(FLOOR(s.r_airport * a.cnt) + 1, a.cnt)
),
batch_prompts AS (
  SELECT
    batch_no,
    LISTAGG(
      slot || '. category=' || category || ', airport=' || iata_code || ' (' || city || ')'
      || ', effective_date=' || TO_VARCHAR(effective_date, 'YYYY-MM-DD') || ', severity=' || severity,
      '\n') WITHIN GROUP (ORDER BY slot) AS spec_lines
  FROM specs
  GROUP BY batch_no
),
ai_raw AS (
  SELECT
    batch_no,
    AI_COMPLETE(
      model => 'claude-sonnet-4-5',
      prompt => $$Write one NOTAM-style aviation bulletin for each numbered spec below, in the same order, so the output array has exactly as many items as there are specs.

Rules for every bulletin:
- The text is 120-280 characters of NOTAM-style English in upper case.
- Mention the airport ONLY by its exact 3-letter IATA code from the spec. Never use a 4-letter ICAO code and never mention any other airport.
- Include the effective date exactly in the form EFFECTIVE YYYY-MM-DD using the spec date. Do not write any other date or year.
- End the text with IMPACT: followed by the spec severity (LOW, MEDIUM or HIGH).
- The content must clearly and only belong to the spec category.
  weather means storms, snow, fog, wind, ice or volcanic ash.
  mechanical means aircraft defects, inspections, groundings or maintenance.
  atc means runway or taxiway closures, ATC staffing, frequencies, flow control or airspace changes.
  regulatory means directives, rule changes, compliance deadlines or certification.
  security means screening, threats, perimeter incidents or access control.
- source is one of FAA, EASA, ICAO, OPS_DESK.

Specs:
$$ || spec_lines,
      model_parameters => {'temperature': 0.5, 'max_tokens': 4096},
      response_format => {
        'type': 'json',
        'schema': {
          'type': 'object',
          'properties': {
            'bulletins': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'slot':   {'type': 'integer'},
                  'source': {'type': 'string', 'enum': ['FAA', 'EASA', 'ICAO', 'OPS_DESK']},
                  'text':   {'type': 'string'}
                },
                'required': ['slot', 'source', 'text']
              }
            }
          },
          'required': ['bulletins']
        }
      }
    ) AS raw
  FROM batch_prompts
),
parsed AS (
  SELECT a.batch_no, f.value:slot::INT AS slot, f.value AS b
  FROM ai_raw a, LATERAL FLATTEN(input => a.raw:bulletins) f
)
SELECT
  'BUL-' || LPAD(ROW_NUMBER() OVER (ORDER BY p.batch_no, p.slot)::VARCHAR, 5, '0') AS bulletin_id,
  DATEADD(hour, -UNIFORM(0, 72, RANDOM()), s.effective_date::TIMESTAMP_NTZ) AS issued_at,
  p.b:source::VARCHAR AS source,
  p.b:text::VARCHAR   AS bulletin_text,
  CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS _LOADED_AT,
  'MERIDIAN_OPS_NEWSFEED'            AS _SOURCE_SYSTEM,
  'BATCH_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDDHH24MISS') AS _INGEST_BATCH_ID
FROM parsed p
JOIN specs s ON s.batch_no = p.batch_no AND s.slot = p.slot;
-- ======================================================================
-- 8. Sanity checks
-- ======================================================================
SELECT 'AIRCRAFT'            AS table_name, COUNT(*) AS row_count FROM AIRCRAFT
UNION ALL SELECT 'AIRPORTS',            COUNT(*) FROM AIRPORTS
UNION ALL SELECT 'SCHEDULES',           COUNT(*) FROM SCHEDULES
UNION ALL SELECT 'FLIGHTS',             COUNT(*) FROM FLIGHTS
UNION ALL SELECT 'MAINTENANCE_EVENTS',  COUNT(*) FROM MAINTENANCE_EVENTS
UNION ALL SELECT 'AVIATION_BULLETINS',  COUNT(*) FROM AVIATION_BULLETINS;
