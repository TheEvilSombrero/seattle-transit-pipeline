-- migrate:up
CREATE TABLE gtfs_rt.vehicle_positions (
    ping_id           BIGSERIAL PRIMARY KEY,
    received_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    feed_timestamp    TIMESTAMPTZ,
    vehicle_id        TEXT NOT NULL,
    trip_id           TEXT,
    route_id          TEXT,
    direction_id      SMALLINT,
    start_date        DATE,
    vehicle_lat       DOUBLE PRECISION NOT NULL,
    vehicle_lon       DOUBLE PRECISION NOT NULL,
    bearing           REAL,
    speed             REAL,
    current_status    TEXT,
    current_stop_seq  INTEGER,
    stop_id           TEXT,
    geom              geometry(point, 4326) GENERATED ALWAYS AS (
                          ST_SetSRID(ST_MakePoint(vehicle_lon, vehicle_lat), 4326)
                      ) STORED
);

CREATE INDEX vehicle_positions_geom_idx
          ON gtfs_rt.vehicle_positions USING gist (geom);

CREATE INDEX vehicle_positions_trip_received_idx
          ON gtfs_rt.vehicle_positions (trip_id, received_at);

CREATE INDEX vehicle_positions_received_idx
          ON gtfs_rt.vehicle_positions (received_at);

-- migrate:down
DROP TABLE gtfs_rt.vehicle_positions;
