# MVP: S3 raw zone -> Snowflake -> dbt -> reconciliation

Scaffold only (per CLAUDE.md): shapes, signatures, decisions, verification steps. You type the code.

**Goal.** Reproduce the evolv pattern on this project: raw data lands in AWS, Snowflake ingests it from S3 through an external stage, dbt transforms it, and a reconciliation step proves no rows were lost between hops. Two evenings. Airflow, weather source, and Snowpipe come after.

**Why this shape.** The Snowflake-specific mechanism in that stack is the storage integration + external stage + COPY INTO handshake. boto3 puts are generic AWS; the handshake is the part you have never done.

---

## Pre-work (travel-compatible, ~45 min total, no Docker)

- [ ] AWS account (new accounts get $100 credit at signup, up to $200 with onboarding tasks; pick the **Free plan**, which caps charges at zero). Region **us-west-2** to match the Snowflake trial.
- [ ] Set an AWS Budget alert at $5. Enable MFA on the root user, then never use root again.
- [ ] IAM user `transit-pipeline-writer` with programmatic keys and ONE inline policy scoped to one bucket:
  `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` on `arn:aws:s3:::<bucket>` and `arn:aws:s3:::<bucket>/*`. Nothing else.
- [ ] Bucket `<yourname>-transit-raw-usw2` (names are global; keep it boring). Block all public access. Versioning off for MVP.
- [ ] Snowflake: decide convert-with-card (data preserved, few dollars/month at X-Small + 60s auto-suspend) vs. let it lapse ~10-11 and re-create. Either works; the dbt-sprint repo rebuilds in 15 min.
- [ ] Snowflake resource monitor on `COMPUTE_WH`, e.g. 5 credits/month, suspend at 100%.
- [ ] Read once: Snowflake docs, "Configuring a Snowflake storage integration to access Amazon S3" (docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration). Understand the two-way trust before evening 1.

## Housekeeping found while scaffolding

- `.gitignore` ignores `.env.example` and `.gitignore` itself. Both should be committed; only `.env` should be ignored. The README's `cp .env.example .env` step fails for anyone who clones.

---

## Evening 1 (~2.5 h): land raw in S3, ingest into Snowflake

### Step 1. Poller writes raw to S3 (~60 min)

**Decision to record as ADR 0005:** what is "raw"? Options: (a) the protobuf bytes, (b) parsed pings as JSON Lines, (c) both. Recommend **(b) for MVP**: Snowflake reads NDJSON natively, protobuf would need a UDF. Note the trade-off honestly: (a) is the only truly immutable source-of-truth; a parser bug in (b) is baked into the raw zone. Revisit when adding Snowpipe.

New module `ingest/landing.py` (S3 is a landing zone, not a database; keep the boundary explicit):

```python
def raw_object_key(source: str, feed_timestamp: datetime) -> str:
    """Hive-style partitioned key:
    raw/{source}/dt=YYYY-MM-DD/hour=HH/{epoch_seconds}.jsonl
    Partition by the FEED timestamp, not wall-clock. Why? (answer before coding)"""
    pass

def to_jsonl(pings: list[dict]) -> bytes:
    """One JSON object per line. Dates/datetimes must serialize (isoformat).
    Every line carries feed_timestamp so a row is self-describing outside its file."""
    pass

def put_raw(bucket: str, key: str, body: bytes, row_count: int) -> str:
    """boto3 put_object. content_type application/x-ndjson.
    Metadata={'row_count': str(row_count)} so reconciliation can read expected counts
    without downloading files. Return the ETag."""
    pass
```

Changes to `poll_gtfs_rt.py::main()`: after `parse_feed`, call the three functions above, print the key and row count, then continue with the existing Postgres insert. Both sinks get the same `pings` list, so **Postgres rowcount == S3 row_count** for every poll. That equality is your first reconciliation invariant, for free.

Env: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION=us-west-2`, `S3_RAW_BUCKET`. Add to `.env` and `.env.example`. `uv add boto3`.

Verify: run `make poll` twice, then `uv run python -c "import boto3; ..."` to list `raw/gtfs_rt/`. Confirm two objects, correct partitions, metadata row_count present. Compare to `select count(*) from gtfs_rt.vehicle_positions where feed_timestamp = ...`.

### Step 2. Snowflake reads S3 through a storage integration (~75 min)

Do this in a Snowsight worksheet as ACCOUNTADMIN. Save every statement to `sql/snowflake/01_ingest_setup.sql` so it is reproducible.

Objects, in order:

1. `CREATE DATABASE TRANSIT; CREATE SCHEMA TRANSIT.RAW;`
2. **Storage integration** (the handshake, part 1):
   ```sql
   CREATE STORAGE INTEGRATION s3_transit_raw
     TYPE = EXTERNAL_STAGE STORAGE_PROVIDER = 'S3' ENABLED = TRUE
     STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<acct>:role/snowflake-transit-raw-reader'   -- role does not exist yet; that is expected
     STORAGE_ALLOWED_LOCATIONS = ('s3://<bucket>/raw/');
   DESC INTEGRATION s3_transit_raw;  -- copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID
   ```
3. **IAM role** `snowflake-transit-raw-reader` in AWS (handshake, part 2): trust policy allows the Snowflake IAM user ARN with `sts:ExternalId` = the external ID from step 2; permissions = `s3:GetObject`, `s3:GetObjectVersion`, `s3:ListBucket` on the bucket, read only. Snowflake assumes this role; **no AWS keys are stored in Snowflake**. That sentence is the interview answer to "how does Snowflake authenticate to S3."
4. `CREATE FILE FORMAT TRANSIT.RAW.ff_jsonl TYPE = JSON STRIP_OUTER_ARRAY = FALSE;`
5. `CREATE STAGE TRANSIT.RAW.stg_s3_raw STORAGE_INTEGRATION = s3_transit_raw URL = 's3://<bucket>/raw/' FILE_FORMAT = ff_jsonl;`
   Verify: `LIST @TRANSIT.RAW.stg_s3_raw;` must show your objects. If it errors, the trust policy or external ID is wrong. Debug with the framework: read the error literally, it names the layer.
6. Landing table, schema-on-read:
   ```sql
   CREATE TABLE TRANSIT.RAW.gtfs_rt_vehicle_positions (
     payload          VARIANT,
     source_file      STRING,
     source_row       NUMBER,
     loaded_at        TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
   );
   ```
7. **COPY INTO** with file metadata columns:
   ```sql
   COPY INTO TRANSIT.RAW.gtfs_rt_vehicle_positions (payload, source_file, source_row)
   FROM (SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER FROM @TRANSIT.RAW.stg_s3_raw/gtfs_rt/)
   FILE_FORMAT = (FORMAT_NAME = TRANSIT.RAW.ff_jsonl)
   ON_ERROR = 'ABORT_STATEMENT';
   ```
   Run it **twice**. Second run loads 0 files. COPY tracks load history per file for 64 days, so re-runs are idempotent. Know this; it is the Snowflake answer to "how do you avoid double-loading."
8. Verify: `SELECT COUNT(*) FROM TRANSIT.RAW.gtfs_rt_vehicle_positions;` vs. sum of S3 metadata row_count. Then
   `SELECT * FROM TABLE(TRANSIT.INFORMATION_SCHEMA.COPY_HISTORY(TABLE_NAME=>'GTFS_RT_VEHICLE_POSITIONS', START_TIME=>DATEADD(hour,-2,CURRENT_TIMESTAMP())));`
   COPY_HISTORY gives per-file ROW_COUNT and ROW_PARSED. That is the load-side ledger for reconciliation.

Optional at the end of evening 1: a tiny `ingest/load_snowflake.py` that runs the COPY via the `snowflake-connector-python` with your existing key-pair, so the whole loop is one `make` target. Signature: `def copy_into_raw(conn, stage_path: str) -> list[dict]` returning the per-file results COPY prints.

---

## Evening 2 (~2.5 h): dbt transforms, reconciliation proves it

### Step 3. dbt project in `dbt/` (~75 min)

The empty `dbt/` dir has never been committed. It becomes real tonight. Copy the dbt-sprint layout, not its models. Add a `transit` profile to `~/.dbt/profiles.yml` reusing the key-pair, database `TRANSIT`, schema `dev_vidul`.

- `models/staging/gtfs_rt/sources.yml`: source `raw`, table `gtfs_rt_vehicle_positions`, with `loaded_at_field: loaded_at` and a freshness warn at, say, 2 hours (real feed, so freshness is meaningful here, unlike TPCH).
- `models/staging/gtfs_rt/stg_gtfs_rt__vehicle_positions.sql`: flatten `payload:vehicle_id::string`, `payload:route_id::string`, `payload:feed_timestamp::timestamp_tz`, lat/lon `::float`, etc. Keep `source_file`, `source_row` as lineage columns. Materialized view.
- Tests: `not_null` on vehicle_id, feed_timestamp; `unique` on a surrogate of (feed_timestamp, vehicle_id) via `dbt_utils.generate_surrogate_key`. Predict first whether that is actually unique in the feed; then let the test tell you.
- One mart, `marts/fct_pings_by_route_hour.sql`: route_id, hour bucket, ping count, distinct vehicles. Non-spatial on purpose; Snowflake has no `ST_LineLocatePoint` equivalent (verify), so lateness stays in PostGIS for now.

### Step 4. Reconciliation, three hops (~60 min)

This is the daily task Paul described. Counts must agree at every boundary:

| Hop | Expected | Actual | Where the number lives |
|---|---|---|---|
| Parse -> S3 | `len(pings)` | S3 metadata `row_count` | poller print + object metadata |
| S3 -> RAW | sum of `row_count` over objects | `COUNT(*)` raw, and COPY_HISTORY `ROW_COUNT` per file | S3 list + Snowflake |
| RAW -> STG | raw count | `COUNT(*)` staging view | dbt singular test |
| (bonus) Postgres | `gtfs_rt.vehicle_positions` count for the same feed_timestamps | raw count | you already have this sink |

Two implementations, do both:

1. **dbt singular test** `tests/assert_raw_matches_staging.sql`: a query returning rows when the counts differ. Also one per-file variant: group raw by `source_file`, compare to... (what? think about where a per-file expected count could come from inside Snowflake. Hint: COPY_HISTORY, or a seed/manifest table the poller writes.)
2. **Python `ingest/reconcile.py`**, run after each load:
   ```python
   @dataclass
   class HopResult:
       hop: str; expected: int; actual: int
       @property
       def ok(self) -> bool: ...

   def s3_expected_rows(bucket: str, prefix: str) -> int:
       """Sum row_count metadata across objects under prefix (head_object per key, or a manifest)."""
       pass

   def snowflake_raw_rows(conn, source_file_prefix: str) -> int: pass
   def postgres_rows(conn, feed_timestamps: list[datetime]) -> int: pass

   def reconcile(window_prefix: str) -> list[HopResult]:
       """Return all hops; non-zero exit if any hop is not ok. Write results to meta.ingest_log
       (extend the table with a 'reconcile' status row) so provenance and QA live together."""
       pass
   ```
   `make reconcile` target. Exit code drives the future Airflow task's success/failure.

When a hop disagrees, apply the debugging framework: which boundary, minimal failing file, observe (row_parsed vs row_count in COPY_HISTORY, malformed lines, timezone drift in the partition key), one-sentence hypothesis, cheapest fix.

---

## Talking points this unlocks (say them in your own words)

- Raw zone is partitioned, immutable, append-only; Snowflake is schema-on-read via VARIANT, flattened in staging.
- Snowflake authenticates to S3 by assuming an IAM role through a storage integration; no long-lived keys in the warehouse.
- COPY INTO is idempotent per file via load history; reruns are safe. Snowpipe is the same mechanism triggered by S3 event notifications (the "stream" version, next step).
- Reconciliation = counts at every hop, persisted in a log table, failing loudly. Same discipline as the 921K-feature cutover reconciliation at Apple.
- Cost controls: X-Small, auto-suspend, resource monitor, AWS budget alert.

## After the MVP (in order)

1. Weather source (Open-Meteo, no key) landing under `raw/weather/`, second staging model, join in the mart.
2. Airflow in docker-compose: one DAG, tasks poll -> land -> copy -> dbt build -> reconcile.
3. Snowpipe with S3 event notifications instead of scheduled COPY.
4. Terraform for the bucket, IAM user, role, and policies (you will have built them by hand once, so the Terraform is a transcription, not a mystery).
