# Architecture Deep Dive

A walk through the pipeline layer by layer. For each layer: what it stores or runs, the code that built it, what it's optimized for, and **why it works the way it does**.

The five layers in order:

```
LAYER 5 — Orchestration         (Makefile, future Airflow)
LAYER 4 — Application           (Python)
LAYER 3 — Schema                (SQL migrations, dbmate)
LAYER 2 — Storage               (PostgreSQL + PostGIS in Docker)
LAYER 1 — Source                (GTFS static CSVs, GTFS-RT protobuf bytes)
```

Higher layers depend on lower layers but lower layers don't know about higher. Storage doesn't know about the Python loader; the Python loader doesn't know about Make.

---

## Layer 1 — Source

### What it is

- **GTFS static CSVs**: 14 CSV files (despite `.txt` extension) downloaded from Sound Transit's OTD portal. Unzipped on disk into `data/raw/gtfs-static/sound-transit-<YYYYMMDD>/`. Files include `agency.txt`, `routes.txt`, `stops.txt`, `trips.txt`, `stop_times.txt`, `shapes.txt`, `calendar.txt`, `calendar_dates.txt`, plus several GTFS-Fares-v2 extensions the project doesn't load.
- **GTFS-RT protobuf bytes**: a 10–50 KB binary stream from `https://api.pugetsound.onebusaway.org/api/gtfs_realtime/vehicle-positions-for-agency/40.pb?key=<key>`. Fetched fresh on every poll, never stored on disk.

### Why a dated snapshot directory

GTFS static is republished by the agency every few weeks aligned with service changes. The directory name encodes the publication date (`sound-transit-20260624/`) so multiple snapshots can coexist on disk, and any question of "which version of the schedule did this load come from?" is answerable by looking at the file path.

This is the cheapest possible form of provenance — the filesystem itself tracks which snapshot is which.

### Why we never edit these files

Once a snapshot lands on disk, it's immutable. If the agency's CSVs have problems (we found this with the `departure_buffer` column drop), the response is *never* "edit the CSV." It's:

1. Note the discrepancy in an ADR (`docs/adr/0004-schema-drift-handling.md`).
2. Adjust the loader (Layer 4) or schema (Layer 3) to tolerate the discrepancy.
3. Reload the snapshot.

This invariant is what makes the raw layer trustworthy. Any downstream system can rebuild from these files; if we modified them, that promise breaks.

### Why GTFS-RT bytes aren't saved to disk

The bytes are a 10–50 KB delta of vehicle positions valid for ~30 seconds. Saving every poll would be ~3000 small files per day with no value over the parsed table. The bytes are parsed once, inserted into `gtfs_rt.vehicle_positions`, and discarded. The DB is the durable form.

---

## Layer 2 — Storage

### What it is

PostgreSQL 18 + PostGIS 3.6 running in a Docker container, defined by `docker-compose.yml`. Data persists in a Docker-managed named volume (`pgdata`) outside the container. The container exposes port 5432 internally; we map it to 5433 on the host.

### Code

- `docker-compose.yml` — the container definition
- `.env` (gitignored) — credentials and host port
- `.env.example` (tracked) — template
- `sql/ddl/00_extensions.sql` — runs once on first container init, creates the PostGIS extension

### Why Docker

Three reasons, ordered by importance:

1. **Reproducibility.** Anyone cloning this repo runs `docker compose up -d` and gets an identical Postgres + PostGIS setup. Without Docker, the next person would need to manually install Postgres, manually add PostGIS, manually match versions. Docker makes the engine itself a versioned, declarative artifact.
2. **Isolation.** The container can be wiped (`docker compose down -v`) and recreated without touching anything else on the host. During schema iteration this is invaluable.
3. **Portability.** The same `docker-compose.yml` works on macOS (Intel and Apple Silicon), Linux, and Windows (via WSL). The container abstracts the OS.

### Why a named volume, not a bind mount

The `pgdata:/var/lib/postgresql` line creates a Docker-managed volume. Alternatives would be:
- **No volume**: data lives in the container's writable layer, lost on container removal. Useless.
- **Bind mount** (`./data:/var/lib/postgresql`): data lives in the host filesystem at a predictable path. Possible but introduces permission issues across Docker's Linux user and the host's user.

The named volume is the standard pattern. Docker handles permissions and storage location; the host just refers to it by name (`pgdata`).

### Why the `imresamu/postgis` image, not the official

See `docs/adr/0002-postgis-container-image.md`. Short version: the official `postgis/postgis` image only publishes `linux/amd64`. Apple Silicon hosts need `arm64`. `imresamu/postgis` publishes both architectures.

### Why port 5433 on the host (not 5432)

Postgres.app was running on the host's 5432 when this project started. Mapping container 5432 → host 5433 avoids the collision. Inside the container, Postgres still hears connections on 5432; only the host-side port differs. This is documented in `.env` as `POSTGRES_HOST_PORT=5433`.

### What the storage layer doesn't do

It doesn't know about your schema, your migrations, your loaders, or your queries. It's just an engine. Layer 3 declares what tables it should hold; Layer 4 puts data in.

---

## Layer 3 — Schema

### What it is

19 SQL migration files in `sql/migrations/`, applied in timestamp order by `dbmate`. Together they declare four PostgreSQL schemas (namespaces) and the tables inside them:

```
gtfs_static  ─── agency, routes, stops, calendar, calendar_dates,
                 trips, stop_times, shapes
                 (raw mirror of the CSV feed)

gtfs_geom    ─── stops_geom, shapes_geom, trip_stop_progress
                 (PostGIS-typed derived spatial layer)

gtfs_rt      ─── vehicle_positions
                 (append-only live ping history with generated geom column)

meta         ─── ingest_log
                 (operational provenance — one row per load run)

public       ─── schema_migrations (dbmate bookkeeping)
                 spatial_ref_sys, geography_columns, geometry_columns (PostGIS)
```

### Code

- `sql/migrations/*.sql` — one file per logical schema change. Filename format: `<timestamp>_<name>.sql`. Each file has a `migrate:up` and `migrate:down` block.
- `sql/schema.sql` — auto-dumped by `dbmate` after every migration. The current full state of the schema, useful as a single-pane reference.

### Why migrations instead of pgAdmin clicks

If the schema only lived in someone's running pgAdmin session, it would be:

- **Not reproducible** — anyone else cloning the repo couldn't recreate it
- **Not versioned** — no `git diff` to see how the schema evolved
- **Not portable** — couldn't deploy to a cloud Postgres without re-clicking everything

Migrations solve all three. Each migration is a tiny SQL script in git; the DB tracks which ones have been applied in a `public.schema_migrations` table; re-running migrations on a fresh DB rebuilds identical state.

### Why dbmate specifically

Three alternatives we could have used:

- **Plain `psql` + shell scripts** — educational but reinvents what dbmate already does (state tracking, idempotency, ordering).
- **Alembic** (SQLAlchemy's tool) — Python-native, but introduces SQLAlchemy as a dependency we don't otherwise want.
- **dbmate** — plain `.sql` files, single Go binary, zero Python overhead, used in production DE shops.

dbmate's "plain SQL files" approach keeps the focus on SQL skills (the actual skill being demonstrated) rather than learning a DSL.

### Why separate schemas (namespaces)

The four schemas aren't just organizational. Each represents a different *contract*:

- `gtfs_static` is a **promise to be faithful to the source file**. Nothing computes anything; nothing transforms. The CSV is the truth; this schema mirrors it.
- `gtfs_geom` is a **promise that everything here is derived from `gtfs_static`** by the loader. If the raw data is consistent, the geom layer is consistent — and we can wipe and rebuild this schema without touching anything else.
- `gtfs_rt` is **append-only event history**. Different temporal semantics from the others (rows accumulate forever, vs the static layers which are TRUNCATEd on each load).
- `meta` is **operational metadata about loads**, separate from any user data. If the load succeeded, why, when.

Mixing these contracts in one schema would conflate roles. Separating them makes the codebase legible: "this is raw data, this is derived, this is observation, this is bookkeeping."

### Why each table is shaped the way it is

Worth knowing for the geometry tables and the rt table — they have specific design tricks:

**`gtfs_geom.shapes_geom`** — one row per `shape_id` with a single `LineString` geometry. The raw `gtfs_static.shapes` has 8000+ point rows; the geom layer collapses them into 22 LineStrings via `ST_MakeLine(... ORDER BY shape_pt_sequence)`. The `ORDER BY` inside the aggregate is critical — without it, points come in arbitrary order and you get a self-intersecting mess.

**`gtfs_geom.trip_stop_progress`** — one row per (`trip_id`, `stop_sequence`) carrying the `fraction` (0.0–1.0) and `distance_meters` of each scheduled stop along its trip's shape. Computed once by the loader via `ST_LineLocatePoint(shape.geom, stop.geom)`. This is the **precomputation that makes real-time analysis fast**: any vehicle ping joined against this table can be located in the trip's stop sequence with a single index lookup, not a per-ping geometry computation.

**`gtfs_rt.vehicle_positions.geom`** — a **generated column**:

```sql
geom geometry(Point, 4326) GENERATED ALWAYS AS (
    ST_SetSRID(ST_MakePoint(vehicle_lon, vehicle_lat), 4326)
) STORED
```

The application code inserts `vehicle_lat` and `vehicle_lon`. Postgres derives `geom` automatically on every insert. The Python poller never has to call PostGIS functions — it just inserts numbers. And the column is `STORED` (physically materialized) so the GiST index on `geom` works.

### Why the indexes on `gtfs_rt.vehicle_positions`

Three indexes besides the PK, each for a known access pattern:

```sql
CREATE INDEX vehicle_positions_geom_idx          USING gist (geom);                   -- spatial queries
CREATE INDEX vehicle_positions_trip_received_idx ON ... (trip_id, received_at);       -- "show one trip's pings over time"
CREATE INDEX vehicle_positions_received_idx      ON ... (received_at);                -- "show all pings in the last N seconds"
```

The point: **indexes follow queries, not data**. We didn't pick "obviously important" columns; we picked the columns the dashboard and analytical queries actually filter on. Indexing without a query in mind is overhead with no payoff.

### Why FKs in `gtfs_static` but not from `gtfs_geom` to `gtfs_static`

Inside `gtfs_static`, we declared real foreign keys:
- `routes.agency_id → agency`
- `trips.route_id → routes`
- `stops.parent_station → stops` (self-referencing, `DEFERRABLE INITIALLY DEFERRED`)
- `stop_times.trip_id → trips`
- `stop_times.stop_id → stops`

These enforce referential integrity inside the raw layer. If `stop_times` references a `trip_id` that doesn't exist in `trips`, the load fails loudly.

But there are NO foreign keys from `gtfs_geom` or `gtfs_rt` back to `gtfs_static`. Two reasons:

1. **The loader's TRUNCATE-and-reload pattern.** Adding an FK from `gtfs_geom.stops_geom` to `gtfs_static.stops` would force complex ordering during reload. Easier to enforce the contract in loader code: "after a load, both layers are consistent."
2. **`gtfs_rt.vehicle_positions.trip_id` references trips from the LIVE feed, which may not exist in the static schema** (if the schedule period drifted, or if the ping is from a different agency). An FK would reject those pings, losing data. Soft references via SQL joins handle the mismatch gracefully (the join just drops rows).

### Why `INTERVAL` for arrival/departure times

GTFS allows values like `25:30:00` for trips that cross midnight (1:30 AM the *next* service day). Postgres's `TIME` type only accepts 00:00:00–24:00:00, so it rejects `25:30:00`. `INTERVAL` accepts arbitrary durations, including >24h. This was a critical schema choice — using `TIME` would have failed the load.

### Why `TIMESTAMPTZ` everywhere there's a real timestamp

`TIMESTAMP` (without timezone) is the "naive" version: just a wall-clock string with no timezone. Two systems can write to it interpreting the same wall-clock differently and you'd never know.

`TIMESTAMPTZ` stores UTC under the hood and converts on display per the session timezone. There's never ambiguity. We use it for `started_at`, `completed_at`, `received_at`, `feed_timestamp` — every column that records "when something happened in the real world."

The exception is `gtfs_static.calendar.start_date` and similar — those are `DATE` because they have no time-of-day at all.

---

## Layer 4 — Application

### What it is

About 350 lines of Python in three files:

- `ingest/db.py` — a 10-line connection helper. Reads `DATABASE_URL` from `.env`, returns a `psycopg.Connection`.
- `ingest/load_gtfs_static.py` — the static loader. Reads CSVs from disk, COPYs them into `gtfs_static`, derives `gtfs_geom`, precomputes `trip_stop_progress`, logs everything to `meta.ingest_log`.
- `ingest/poll_gtfs_rt.py` — the RT poller. HTTP GETs the feed URL, parses protobuf into Python dicts, batch-inserts into `gtfs_rt.vehicle_positions`.

### Why Python is light

This is the central design pattern of the project. Python's role is **conducting**, not **computing**. The actual work happens elsewhere:

| Work | Done by | Why |
|---|---|---|
| Parse 313K CSV rows | Postgres COPY (C) | 10–100× faster than parsing in Python |
| Aggregate 8,443 shape points into 22 LineStrings | PostGIS `ST_MakeLine` | C++ GEOS library; orders of magnitude faster than Python loops |
| Compute 313K linear-references | PostGIS `ST_LineLocatePoint` | Same; one SQL statement, ~5 seconds |
| Parse protobuf bytes | `gtfs-realtime-bindings` (compiled extension) | Hand-parsing protobuf in Python is pain |
| Batch-insert 84 pings | `psycopg.executemany` | Single network round-trip + Postgres binary protocol |

The Python code itself handles: opening connections, reading env vars, choosing files, error catching, logging, calling the right library function. About 3 lines of orchestration for every 1 line of actual computation.

This is the modern DE pattern. Push work to where it's most efficient. Python is the glue.

### Why TRUNCATE-and-reload for static data, but append-only for RT

Two opposite ingest patterns in the same codebase, each correct for its data:

**Static (TRUNCATE + reload):** the agency publishes one snapshot at a time. A new snapshot is a full replacement, not a delta. Trying to compute deltas would be more error-prone than wiping and reloading.

```python
cur.execute(f"TRUNCATE {table_list} CASCADE")
for table in TABLES:
    cur.execute(f"COPY gtfs_static.{table} ... FROM STDIN ...")
```

The whole load is one transaction. Observers either see the old data or the new data, never half-and-half.

**Realtime (append-only):** the agency publishes new vehicle positions every 30 seconds. We want the *history* — the whole accumulation — for analytics. Every poll inserts new rows; nothing is ever deleted (until a retention policy is added later).

```python
cur.executemany("INSERT INTO gtfs_rt.vehicle_positions (...) VALUES (...)", pings)
```

Mixing the patterns would be wrong. TRUNCATEing `vehicle_positions` on every poll would destroy the history; appending to `gtfs_static.stops` on every static load would corrupt the raw layer with duplicates.

### Why dynamic CSV column detection

Originally the loader assumed columns 1:1 between CSV and table, positionally. When ST dropped `departure_buffer` between snapshots, the load broke (see ADR 0004). The fix:

```python
csv_cols = _csv_header(csv_path)
table_cols = set(_table_columns(cur, "gtfs_static", table))
shared = [c for c in csv_cols if c in table_cols]
col_list = ", ".join(f'"{c}"' for c in shared)
copy_sql = f'COPY gtfs_static.{table} ({col_list}) FROM STDIN ...'
```

Read the CSV's first line, look up the table's actual columns from `information_schema`, intersect them, pass the intersection to COPY. Columns in the CSV but not the table are silently skipped; columns in the table but not the CSV get NULL.

This is a real DE move. Production GTFS pipelines need to tolerate agency schema changes without code edits.

### Why provenance is its own layer

The `start_ingest_log` → `load_all_tables` → `refresh_geom` → `compute_trip_progress` → `complete_ingest_log` sequence in `main()` is deliberate. The `meta.ingest_log` row gets inserted at `status='started'` immediately and **committed before any data work begins**. Two consequences:

1. **Failures are visible.** If the load crashes mid-stream, the `started` row survives in the log. We can see "load attempted at 2026-06-25 03:00 UTC, never completed" — vs. silently failing with no trace.
2. **The audit row gets updated to `'failed'` with the error message** via `fail_ingest_log`, which **rolls back the aborted transaction first** so the UPDATE itself can run.

Without this discipline, "did the load succeed?" would be answerable only by querying user data — much less reliable than checking a dedicated audit row.

### Why the poller doesn't write to `ingest_log`

A row per static load is one row per few weeks. A row per RT poll would be 2880 rows per day per agency — noise that overwhelms the signal. The static load's `ingest_log` row is meaningful audit; an RT-poll log row would be junk telemetry.

If we eventually want RT observability, the right pattern is a separate metrics table (or push to Prometheus/Datadog), not the `ingest_log`. Different concern, different storage.

### Why service date is derived in the lateness query, not in the poller

The GTFS-RT spec says `trip.start_date` is the service day in agency-local time. ST's feed omits it. We could:

A. **Hack the poller** to derive `start_date` from `received_at` when the feed omits it. Side effect: future pings carry the derived value, queries can use it directly.
B. **Leave the poller as-is** (raw mirror of what the feed sent — NULL when absent), and derive in SQL using `COALESCE(start_date, (received_at AT TIME ZONE 'America/Los_Angeles')::date)`.

We chose B. Reason: the raw layer's promise is to be faithful to the source. ST sent NULL; we stored NULL. The lateness query — which is a *derived* analysis — handles the substitution. Keeping derivation out of ingest preserves a clean raw layer.

This is the same principle as the ELT pattern: don't transform during load; transform when querying.

---

## Layer 5 — Orchestration

### What it is

A `Makefile` with named targets. Each target is a shortcut for a longer command.

```makefile
make load   = uv run python -m ingest.load_gtfs_static --snapshot-dir ... --snapshot-date ...
make poll   = uv run python -m ingest.poll_gtfs_rt
make psql   = docker compose exec postgis psql -U transit -d transit
make sql    = docker compose exec -T postgis psql -U transit -d transit < $(FILE)
make q      = docker compose exec postgis psql -U transit -d transit -c "$(SQL)"
make migrate, rollback, status, up, down, poll-loop
```

### Why Make

Three reasons in order:

1. **Universal.** Any Unix shell can run Make. No new tools to install. Recruiters reviewing the repo don't need to learn a project-specific runner.
2. **Editor-agnostic.** Make targets work in any terminal, any IDE, any container. Not tied to a specific dev environment.
3. **Documentation.** A Makefile is also a checklist of "what commands does this project understand?" One file shows every named operation.

The Makefile would be replaced (or augmented) by Airflow in Phase 3 — Airflow DAGs are Make on steroids with scheduling, dependencies, and retries.

### Why default variables in the Makefile

```makefile
SNAPSHOT_DIR ?= data/raw/gtfs-static/sound-transit-20260624
SNAPSHOT_DATE ?= 2026-06-24
```

The `?=` operator means "set this default only if not already defined." So `make load` uses the defaults; `make load SNAPSHOT_DIR=... SNAPSHOT_DATE=...` overrides them. Common case is cheap; less-common case is also possible.

---

## Cross-cutting concerns

A few patterns that span multiple layers and deserve their own treatment.

### Reproducibility

The promise: a fresh machine + `git clone` + 5 commands (configure `.env`, `docker compose up`, `dbmate up`, download GTFS zip, `make load`) reproduces the entire pipeline. No undocumented system state, no manual clicks.

This is enforced by:
- Schema lives in migrations (Layer 3) — not pgAdmin
- Engine lives in Docker (Layer 2) — not the host's PostgreSQL
- Python deps live in `pyproject.toml` + `uv.lock` (Layer 4) — not the system Python
- Data lives in gitignored `data/raw/` — re-downloaded as needed, not committed
- Credentials live in gitignored `.env` — templated by `.env.example`

Anything that needs to "live on Vidul's laptop" to work would be a bug.

### Idempotency

Re-running a load should converge to the same state, not accumulate side effects. This is enforced by:

- TRUNCATE-and-reload in the static loader
- `INSERT INTO ... ON CONFLICT DO NOTHING` patterns where they appear
- dbmate skipping already-applied migrations
- `IF NOT EXISTS` on schema creation

For the RT poller, idempotency is different: every poll *intentionally* adds new rows because each poll captures a new moment in time. The unique key is `(vehicle_id, received_at)` implicitly — same vehicle can be polled many times, each at a different received_at.

### Validation boundaries

Where the pipeline checks its inputs:

- **`validate_snapshot()`** in the static loader: snapshot dir exists, all 8 expected CSVs present. Run before any DB connection.
- **NOT NULL constraints** in `gtfs_static.*`: required columns must be in the CSV. The dynamic loader will fail at COPY time if a `NOT NULL` column is missing from the source.
- **CHECK constraint** on `meta.ingest_log.status`: only `'started'`, `'completed'`, `'failed'` allowed.
- **HTTP status check** in the poller via `resp.raise_for_status()`: any 4xx/5xx kills the poll.

Each is at a layer boundary — between source and DB, between Python and DB, between network and code. Errors that originate outside a layer should be caught at its entry point.

### What we deliberately don't do

Worth knowing what would be wrong:

- **Don't write business logic in the raw layer.** The `gtfs_static.*` schema is faithful to the source; never patch source quirks here.
- **Don't compute lateness in Python.** SQL is the right place — it's a join, an interpolation, and a subtraction. Doing it in Python would mean fetching all the joined rows over the network first.
- **Don't pin static data to a single snapshot in code.** The `SNAPSHOT_DIR` is parameterized for a reason. The pipeline should work against any snapshot.
- **Don't trust the raw RT feed without verification.** ADRs 0001 and 0003 document the surprises we found: regional aggregation, missing fields, NULL start_date. Real DE assumes the source publisher is sometimes wrong.

---

## Connecting layers in one query

A query that joins across all four DB schemas demonstrates how the layers compose:

```sql
SELECT
    vp.vehicle_id, vp.received_at,         -- from gtfs_rt (Layer 3)
    t.route_id,                             -- from gtfs_static (Layer 3)
    ST_LineLocatePoint(sh.geom, vp.geom),  -- using gtfs_geom (Layer 3)
    tsp.fraction                            -- from gtfs_geom (Layer 3)
FROM gtfs_rt.vehicle_positions vp
JOIN gtfs_static.trips        t   USING (trip_id)
JOIN gtfs_geom.shapes_geom    sh  ON sh.shape_id = t.shape_id
JOIN gtfs_geom.trip_stop_progress tsp ON tsp.trip_id = vp.trip_id;
```

The Python loader (Layer 4) populated each of these. The schema (Layer 3) declares their shapes. PostGIS in Docker (Layer 2) executes the query. The CSVs and protobuf bytes (Layer 1) are the original truth this query traces back to.

Make (Layer 5) just runs the file: `make sql FILE=sql/queries/lateness.sql`.

That's the whole pipeline.
