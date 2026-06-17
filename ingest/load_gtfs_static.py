"""Load GTFS static feed into gtfs_static schema, log to meta.ingest_log"""

import argparse
import sys
from pathlib import Path

import psycopg
from psycopg.types.json import Jsonb

from ingest.db import connect

# Order matters - parents before childern for FK enforcement on load
TABLES = [
    "agency",
    "routes",
    "stops",
    "calendar",
    "calendar_dates",
    "shapes",
    "trips",
    "stop_times",
]

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Load a GTFS static snapshot into gtfs_static schema.",
    )
    p.add_argument(
        "--snapshot-dir",
        required=True,
        help="Path to unzipped GTFS snapshot directory (e.g. data/raw/gtfs-static/sound-transit-20260514)",
    )
    p.add_argument(
        "--snapshot-date",
        required=True,
        help="Publication date of the feed (YYYY-MM-DD)",
    )
    p.add_argument(
        "--source-name",
        default="sound-transit-gtfs-static",
        help="Identifier for the feed source",
    )
    p.add_argument(
        "--source-url",
        default=None,
        help="URL the feed was downloaded from (optional)",
    )
    return p.parse_args()

def validate_snapshot(snapshot_dir: Path) -> None:
    """Raise if snapshot_dir is missing or any expected CSV is absent"""
    if not snapshot_dir.is_dir():
        raise FileNotFoundError(f"snapshot dir not found: {snapshot_dir}")

    missing = [
        t for t in TABLES
        if not (snapshot_dir / f"{t}.txt").is_file()
    ]
    if missing:
        raise FileNotFoundError(
            f"missing CSVs in {snapshot_dir}: {', '.join(missing)}"
        )

def start_ingest_log(
    conn: psycopg.Connection,
    source_name: str,
    snapshot_date: str,
    source_url: str | None,
) -> int:
    """Insert a 'started' row, commit, return the ingest_id."""
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO meta.ingest_log (source_name, snapshot_date, source_url)
            VALUES (%s, %s, %s)
            RETURNING ingest_id
            """,
            (source_name, snapshot_date, source_url),
        )
        ingest_id = cur.fetchone()[0]
    conn.commit()
    return ingest_id

def load_all_tables(conn: psycopg.Connection, snapshot_dir: Path) -> dict[str, int]:
    """TRUNCATE all gtfs_static tables, then COPY each CSV. Return {table: rows}."""
    row_counts: dict[str, int] = {}

    with conn.cursor() as cur:
        table_list = ", ".join(f"gtfs_static.{t}" for t in TABLES)
        cur.execute(f"TRUNCATE {table_list} CASCADE")

        for table in TABLES:
            csv_path = snapshot_dir / f"{table}.txt"
            copy_sql = f"COPY gtfs_static.{table} FROM STDIN WITH (FORMAT csv, HEADER true, NULL '')"
            with open(csv_path, "rb") as f, cur.copy(copy_sql) as copy:
                while data := f.read(8192):
                    copy.write(data)
            row_counts[table] = cur.rowcount
            print(f"  loaded {table}: {cur.rowcount} rows")

    conn.commit()
    return row_counts

def complete_ingest_log(
    conn: psycopg.Connection,
    ingest_id: int,
    row_counts: dict[str, int],
) -> None:
    """Mark ingest_log row as completed with row counts"""
    with conn.cursor() as cur: 
        cur.execute(
            """
            UPDATE meta.ingest_log
                SET status = 'completed',
                    completed_at = now(),
                    row_counts = %s
            WHERE ingest_id = %s
            """,
            (Jsonb(row_counts), ingest_id)
        )
    conn.commit()

def fail_ingest_log(
    conn: psycopg.Connection,
    ingest_id: int,
    error_message: str,
) -> None:
    """Mark ingest_log row as failed. Rollback aborted tx first"""
    conn.rollback() # Clear any aborted transaction from the failed load
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE meta.ingest_log
                SET status = 'failed',
                    completed_at = now(),
                    error_message = %s
            WHERE ingest_id = %s
            """,
            (error_message, ingest_id),
        )
    conn.commit()

def refresh_geom(conn: psycopg.Connection) -> dict[str, int]:
    """Rebuild gtfs_geom.* from current gtfs_static.* state. Return row counts"""
    row_counts: dict[str, int] = {}

    with conn.cursor() as cur:
        cur.execute("TRUNCATE gtfs_geom.stops_geom, gtfs_geom.shapes_geom")

        cur.execute(
            """
            INSERT INTO gtfs_geom.stops_geom (stop_id, geom, stop_name, parent_station)
            SELECT
                stop_id,
                ST_SetSRID(ST_MakePoint(stop_lon, stop_lat), 4326),
                stop_name,
                parent_station
            FROM gtfs_static.stops
            WHERE stop_lat IS NOT NULL AND stop_lon IS NOT NULL
            """
        )
        row_counts["stops_geom"] = cur.rowcount
        print(f"  built stops_geom: {cur.rowcount} rows")

        cur.execute(
            """
            INSERT INTO gtfs_geom.shapes_geom (shape_id, geom, n_points)
            SELECT
                shape_id,
                ST_MakeLine(
                    ST_SetSRID(ST_MakePoint(shape_pt_lon, shape_pt_lat), 4326)
                    ORDER BY shape_pt_sequence
                ),
                COUNT(*)
            FROM gtfs_static.shapes
            GROUP BY shape_id
            """
        )
        row_counts["shapes_geom"] = cur.rowcount
        print(f"  built shapes_geom: {cur.rowcount} rows")

    conn.commit()
    return row_counts

def main() -> int:
    args = parse_args()
    snapshot_dir = Path(args.snapshot_dir)
    validate_snapshot(snapshot_dir)

    with connect() as conn:
        ingest_id = start_ingest_log(
            conn, args.source_name, args.snapshot_date, args.source_url
        )
        try:
            row_counts = load_all_tables(conn, snapshot_dir)
            row_counts.update(refresh_geom(conn))
            complete_ingest_log(conn, ingest_id, row_counts)
        except Exception as exc:
            fail_ingest_log(conn, ingest_id, str(exc))
            raise

    return 0

if __name__ == "__main__":
    sys.exit(main())
