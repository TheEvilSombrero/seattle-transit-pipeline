-- migrate:up
CREATE SCHEMA IF NOT EXISTS gtfs_rt;

-- migrate:down
DROP SCHEMA gtfs_rt;
