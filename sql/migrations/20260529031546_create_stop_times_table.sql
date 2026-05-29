-- migrate:up
CREATE TABLE gtfs_static.stop_times (
    trip_id TEXT NOT NULL REFERENCES gtfs_static.trips(trip_id),
    stop_id TEXT NOT NULL REFERENCES gtfs_static.stops(stop_id),
    arrival_time INTERVAL,
    departure_time INTERVAL,
    timepoint SMALLINT,
    stop_sequence INTEGER NOT NULL,
    shape_dist_traveled DOUBLE PRECISION,
    -- Sound transit custom field, not in GTFS spec 
    departure_buffer TEXT,
    PRIMARY KEY (trip_id, stop_sequence)
);

-- migrate:down
DROP TABLE gtfs_static.stop_times;
