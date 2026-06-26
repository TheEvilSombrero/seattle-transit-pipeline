# Seattle Transit Pipeline

A real-time geospatial data pipeline that ingests Sound Transit's bus and light-rail data, joins live vehicle positions against the published schedule, and computes on-time performance using PostGIS linear referencing.

**Status:** Phase 1 (static schedule layer) and Phase 2 (real-time vehicle ingestion + spatial analytics) complete. Phase 3 (orchestration, dashboard, cloud deployment) planned.

## What it does

1. Ingests Sound Transit's GTFS static feed (routes, stops, trips, scheduled arrivals, shape geometries) into a normalized PostgreSQL schema.
2. Derives a PostGIS geometry layer (stops as `POINT`, shapes as `LINESTRING`) and precomputes the linear-referenced position of every scheduled stop along its trip's shape.
3. Polls the Sound Transit OneBusAway GTFS-Realtime endpoint every 30 seconds, parses the binary protobuf, and appends each vehicle position to an indexed history table.
4. Joins real-time pings to the precomputed schedule via `ST_LineLocatePoint` to compute, per ping, **where the vehicle actually is along its scheduled trip** and **how that compares to where it should be at this moment** — i.e., on-time performance.

## Stack

- **PostgreSQL 18 + PostGIS 3.6** (containerized) — storage and spatial compute
- **dbmate** — SQL migrations
- **Python 3.13** with `psycopg` (v3), `requests`, `gtfs-realtime-bindings` — orchestration and ingest
- **Docker Compose** — local deployment

## Architecture

Five layers, bottom-up:

1. **Source files** — GTFS static CSVs and GTFS-RT protobuf bytes from the Sound Transit OneBusAway endpoint. Stored on disk in `data/raw/gtfs-static/<snapshot-date>/` (snapshot, immutable) and fetched on demand for RT.

2. **Storage** — PostgreSQL + PostGIS in a Docker container, with persistent named-volume storage. Configured via `docker-compose.yml` and `.env`.

3. **Schema** — SQL migrations in `sql/migrations/` (applied via `dbmate`) declare four schemas:
   - `gtfs_static` — raw mirror of the CSV feed (8 tables)
   - `gtfs_geom` — derived PostGIS layer (`stops_geom` POINTs, `shapes_geom` LINESTRINGs, `trip_stop_progress` precomputed fractions)
   - `gtfs_rt` — append-only vehicle position history with a generated geometry column
   - `meta` — `ingest_log` table for provenance (timestamps, row counts, status, error capture)

4. **Application (Python)** — `ingest/load_gtfs_static.py` (validation → COPY → geometry derivation → linear referencing → log) and `ingest/poll_gtfs_rt.py` (HTTP → protobuf parse → bulk insert). Python orchestrates; PostgreSQL does the heavy lifting (COPY for ingest, PostGIS for spatial math, SQL planner for joins).

5. **Orchestration** — `Makefile` exposes named commands (`make load`, `make poll`, `make poll-loop`, `make psql`, `make sql FILE=...`). Future: Airflow DAG scheduling.

## How to run

Prerequisites: Docker, [uv](https://docs.astral.sh/uv/), [dbmate](https://github.com/amacneil/dbmate), Make.

```bash
# 1. Set credentials
cp .env.example .env
# Edit .env with POSTGRES_PASSWORD and DATABASE_URL.

# 2. Start the database
docker compose up -d

# 3. Apply schema
dbmate up

# 4. Download GTFS static into a dated snapshot dir
#    https://www.soundtransit.org/help-contacts/business-information/open-transit-data-otd/otd-downloads
mkdir -p data/raw/gtfs-static/sound-transit-YYYYMMDD
# (unzip Sound Transit GTFS into the directory above)

# 5. Get an OneBusAway API key by emailing oba_api_key@soundtransit.org
#    Add GTFS_RT_API_KEY and GTFS_RT_VEHICLE_POSITIONS_URL to .env

# 6. Load static, then poll live data
make load SNAPSHOT_DIR=data/raw/gtfs-static/sound-transit-YYYYMMDD SNAPSHOT_DATE=YYYY-MM-DD
make poll-loop   # Ctrl-C to stop
```

## Sample output

After 24 hours of polling at 30-second intervals (~210K pings, 289 unique vehicles), per-route median lateness from `sql/queries/lateness_by_route.sql`:

```
 route_id | pings | median_lateness_sec | p95_lateness_sec
----------+-------+---------------------+------------------
 SNDR_EV  |   890 |               119.6 |            878.2     ← Sounder North Line
 SNDR_TL  |  3691 |               116.8 |            774.4     ← Sounder South Line
 2LINE    | 40808 |                85.9 |            347.7     ← Link 2 Line
 100479   | 44693 |                75.9 |            368.6     ← Link 1 Line
 TLINE    |  6737 |                57.6 |            308.7     ← Tacoma Link Streetcar
```

- Light rail (1 Line, 2 Line, T Line) runs a median of 1–2 minutes behind schedule; the 95th percentile reaches ~5–6 minutes.
- Commuter rail (Sounder) runs ~2 minutes behind at median, with a much fatter tail (95th percentile near 13 minutes).
- 24-hour service curve is visible in the raw data — 158 active vehicles at 4 PM PDT peak, 3 vehicles in the overnight 2–3 AM trough.

Spot-check from `sql/queries/lateness.sql` (latest 5 pings, individual vehicles):

```
 vehicle_id  | route_id |     received_at      | actual_fraction |     lateness
-------------+----------+----------------------+-----------------+------------------
 303.348011  | 100479   | 2026-06-25 03:22:54+ |          0.8382 | +00:00:26
 301.718855  | 2LINE    | 2026-06-25 03:22:54+ |          0.7761 | +00:00:36
 302.575605  | 2LINE    | 2026-06-25 03:22:54+ |          0.1498 | +00:02:07
 2           | TLINE    | 2026-06-25 03:22:54+ |          0.1348 | +00:01:01
 300.275657  | 100479   | 2026-06-25 03:22:54+ |          0.4300 | +00:00:57
```

## What I learned

**ELT, not ETL.** As a GIS analyst my workflows are Extract → Transform → Load. Data engineering inverts the last two: Extract → Load (raw, untouched) → Transform (in-database). The win is keeping the raw layer immutable and auditable: any analyst or downstream system can re-transform from source-of-truth, and every transformation has a versioned definition. The raw `gtfs_static` schema in this project is exactly that — a faithful mirror of the agency's CSVs, never modified by application code.

**Python is the conductor, not the orchestra.** I started expecting Python to do the heavy work. It doesn't — the database does. PostgreSQL's COPY parses CSVs in C; PostGIS computes geometries in C++ (GEOS); the SQL planner is decades of optimization. Every transformation that lives in SQL instead of Python is faster, cleaner, and easier to test. Python's job is opening connections, handling errors, logging provenance, and pointing data at the right tool. About 150 lines of Python orchestrate the load of 313K stop_times rows and the derivation of 313K spatial linear-references in 7 seconds.

**Provenance is a first-class concern.** The `meta.ingest_log` table — every load gets a row recording when it started, when it finished, which source it pulled from, how many rows per table, success/failure, and the error message on failure — is what turns "I ran a script" into "I shipped a pipeline." Without it I couldn't answer "did this query break because the data changed, or because I changed something?"

**Schema drift is real.** Two months apart, Sound Transit republished their GTFS feed with a non-standard column removed. A naive loader that pinned columns to schema position broke on the new snapshot. The loader now reads the CSV header dynamically and inserts the intersection of CSV columns and table columns, surviving schedule reissues without code changes.

## Next steps

- Schedule polling via Airflow (replacing the current `Makefile` while-loop)
- Streamlit dashboard for vehicle positions and lateness distributions over time
- Expand ingestion to King County Metro and other Puget Sound agencies (the OneBusAway feed already returns regional data; static schema would need to load the consolidated zip)
- Cloud deployment (managed Postgres + container runtime) with Terraform for infra reproducibility
- Retention policy on `gtfs_rt.vehicle_positions` (currently append-only; will need periodic aggregation + raw retention rules at scale)

## Repo layout

```
ingest/                      Python loaders + connection helper
sql/migrations/              dbmate-managed schema
sql/queries/                 Saved analytical queries
docs/adr/                    Architecture decision records
data/raw/gtfs-static/        Static GTFS snapshots (gitignored)
docker-compose.yml           Postgres + PostGIS container
Makefile                     Shortcuts for common ops
```
