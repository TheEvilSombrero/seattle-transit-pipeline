-- migrate:up
CREATE TABLE gtfs_geom.stops_geom (
    stop_id         TEXT PRIMARY KEY,
    geom            geometry(Point, 4326) NOT NULL,
    stop_name       TEXT,
    parent_station  TEXT
);

CREATE INDEX stops_geom_geom_idx ON gtfs_geom.stops_geom USING gist (geom);

-- migrate:down
DROP TABLE gtfs_geom.stops_geom;
