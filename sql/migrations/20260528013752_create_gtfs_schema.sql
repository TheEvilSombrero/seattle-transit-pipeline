-- migrate:up
CREATE SCHEMA IF NOT EXISTS gtfs_static;

-- migrate:down
DROP SCHEMA gtfs_static;
