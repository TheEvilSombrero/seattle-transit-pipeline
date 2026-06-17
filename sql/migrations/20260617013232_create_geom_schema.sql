-- migrate:up
CREATE SCHEMA IF NOT EXISTS gtfs_geom;

-- migrate:down
DROP SCHEMA gtfs_geom;
