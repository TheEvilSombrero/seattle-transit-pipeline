-- migrate:up
CREATE TABLE gtfs_static.shapes(
    shape_id TEXT NOT NULL,
    shape_pt_sequence INTEGER NOT NULL,
    shape_pt_lat DOUBLE PRECISION NOT NULL,
    shape_pt_lon DOUBLE PRECISION NOT NULL,
    shape_dist_traveled DOUBLE PRECISION,
    PRIMARY KEY (shape_id, shape_pt_sequence)
);

-- migrate:down
DROP TABLE gtfs_static.shapes;
