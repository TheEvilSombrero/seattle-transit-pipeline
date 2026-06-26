"""Poll Sound Transit GTFS-RT vehicle positions, insert into gtfs_rt.vehicle_positions."""

import os
import sys
from datetime import datetime, timezone

import psycopg
import requests
from google.transit import gtfs_realtime_pb2

from ingest.db import connect


def fetch_feed() -> bytes:
    """HTTP GET the configurede feed URL with API key. Return raw protobuf bytes."""
    url = os.environ["GTFS_RT_VEHICLE_POSITIONS_URL"]
    api_key = os.environ["GTFS_RT_API_KEY"]
    resp = requests.get(url, params={"key": api_key}, timeout=10)
    resp.raise_for_status()
    return resp.content

def _parse_start_date(s: str) -> "date | None":
    """Convert GTFS-RT YYYYMMDD string to date. Return None if empty/malformed"""
    from datetime import date
    if not s or len(s) != 8:
        return None
    return date(int(s[:4]), int(s[4:6]), int(s[6:8]))

def parse_feed(feed_bytes: bytes) -> tuple[datetime | None, list[dict]]:
    """Parse protobuf bytes. Return (feed_timestamp, list of vehicle dicts)."""
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(feed_bytes)

    feed_timestamp = (
        datetime.fromtimestamp(feed.header.timestamp, tz=timezone.utc)
        if feed.header.HasField("timestamp")
        else None
    )

    pings: list[dict] = []
    for entity in feed.entity:
        if not entity.HasField("vehicle"):
            continue
        v = entity.vehicle

        pings.append({
            "vehicle_id":             v.vehicle.id              if v.HasField("vehicle") else None,
            "trip_id":                v.trip.trip_id            if v.HasField("trip") else None,
            "route_id":               v.trip.route_id           if v.HasField("trip") else None,
            "direction_id":           v.trip.direction_id       if v.HasField("trip") and v.trip.HasField("direction_id") else None,
            "start_date":             _parse_start_date(v.trip.start_date) if v.HasField("trip") else None,
            "vehicle_lat":            v.position.latitude       if v.HasField("position") else None,
            "vehicle_lon":            v.position.longitude      if v.HasField("position") else None,
            "bearing":                v.position.bearing        if v.HasField("position") and v.position.HasField("bearing") else None,
            "speed":                  v.position.speed          if v.HasField("position") and v.position.HasField("speed") else None,
            "current_status":         gtfs_realtime_pb2.VehiclePosition.VehicleStopStatus.Name(v.current_status) if v.HasField("current_status") else None,
            "current_stop_seq":       v.current_stop_sequence if v.HasField("current_stop_sequence") else None,
            "stop_id":                v.stop_id if v.HasField("stop_id") else None,
            "timestamp":              datetime.fromtimestamp(v.timestamp, tz=timezone.utc) if v.HasField("timestamp") else None,
        })

    return feed_timestamp, pings

def insert_pings(
    conn: psycopg.Connection,
    feed_timestamp: datetime | None,
    pings: list[dict],
) -> int:
    """Bulk insert vehicle position rows. Return rowcount."""
    sql = """
        INSERT INTO gtfs_rt.vehicle_positions (
            feed_timestamp, vehicle_id, trip_id, route_id, direction_id,
            start_date, vehicle_lat, vehicle_lon, bearing, speed,
            current_status, current_stop_seq, stop_id
        ) VALUES (
            %(feed_timestamp)s, %(vehicle_id)s, %(trip_id)s, %(route_id)s, %(direction_id)s,
            %(start_date)s, %(vehicle_lat)s, %(vehicle_lon)s, %(bearing)s, %(speed)s,
            %(current_status)s, %(current_stop_seq)s, %(stop_id)s
        )
    """

    # Inject feed_timestamp into every dict - same value across the whole batch
    for p in pings:
        p["feed_timestamp"] = feed_timestamp

    with conn.cursor() as cur:
        cur.executemany(sql, pings)
        rowcount = cur.rowcount

    conn.commit()
    return rowcount

def main() -> int:
    feed_bytes = fetch_feed()
    feed_timestamp, pings = parse_feed(feed_bytes)
    print(f"parsed {len(pings)} vehicles, feed_timestamp={feed_timestamp}")

    if not pings:
        print("no vehicles in feed, nothing to insert")
        return 0

    with connect() as conn:
        n = insert_pings(conn, feed_timestamp, pings)
        print(f"inserted {n} rows")

    return 0

if __name__ == "__main__":
    sys.exit(main())
