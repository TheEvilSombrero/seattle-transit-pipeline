-- migrate:up
CREATE SCHEMA IF NOT EXISTS meta;

-- migrate:down
DROP SCHEMA meta;
