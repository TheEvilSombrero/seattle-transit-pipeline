-- migrate:up
CREATE TABLE gtfs_static.stops (
    stop_id TEXT PRIMARY KEY,
    stop_name TEXT NOT NULL,
    stop_lat DOUBLE PRECISION NOT NULL,
    stop_lon DOUBLE PRECISION NOT NULL,
    stop_code TEXT,
    stop_desc TEXT,
    zone_id TEXT,
    stop_url TEXT,
    location_type SMALLINT,
    parent_station TEXT REFERENCES gtfs_static.stops(stop_id) DEFERRABLE INITIALLY DEFERRED,
    wheelchair_boarding SMALLINT,
    stop_timezone TEXT,
    platform_code TEXT,
    tts_stop_name TEXT
);

-- migrate:down
DROP TABLE gtfs_static.stops;
