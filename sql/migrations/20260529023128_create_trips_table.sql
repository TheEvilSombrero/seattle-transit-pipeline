-- migrate:up
CREATE TABLE gtfs_static.trips (
    route_id TEXT NOT NULL REFERENCES gtfs_static.routes(route_id),
    trip_id TEXT PRIMARY KEY,
    service_id TEXT NOT NULL,
    trip_short_name TEXT,
    trip_headsign TEXT,
    direction_id SMALLINT,
    block_id TEXT,
    shape_id TEXT,
    wheelchair_accessible SMALLINT,
    -- Sound transit custom field, not in GTFS spec 
    drt_advance_book_min TEXT,
    bikes_allowed SMALLINT,
    -- Sound transit custom field, not in GTFS spec 
    peak_offpeak TEXT,
    -- Sound transit custom field, not in GTFS spec
    boarding_type TEXT
);

-- migrate:down
DROP TABLE gtfs_static.trips;
