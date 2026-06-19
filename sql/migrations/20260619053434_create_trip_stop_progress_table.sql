-- migrate:up
CREATE TABLE gtfs_geom.trip_stop_progress(
    trip_id         TEXT              NOT NULL,
    stop_sequence   INTEGER           NOT NULL,
    stop_id         TEXT              NOT NULL,
    fraction        DOUBLE PRECISION  NOT NULL,
    distance_meters DOUBLE PRECISION  NOT NULL,
    PRIMARY KEY (trip_id, stop_sequence)
);

-- migrate:down
DROP TABLE gtfs_geom.trip_stop_progress;
