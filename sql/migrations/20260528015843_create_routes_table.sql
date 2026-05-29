-- migrate:up
CREATE TABLE gtfs_static.routes(
    agency_id TEXT NOT NULL REFERENCES gtfs_static.agency(agency_id),
    route_id TEXT PRIMARY KEY,
    route_short_name TEXT,
    route_long_name TEXT,
    route_type INTEGER NOT NULL,
    route_desc TEXT,
    route_url TEXT,
    route_color TEXT,
    route_text_color TEXT
);

-- migrate:down
DROP TABLE gtfs_static.routes;
