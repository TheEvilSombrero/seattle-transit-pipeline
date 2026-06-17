-- migrate:up
CREATE TABLE gtfs_geom.shapes_geom (
    shape_id    TEXT PRIMARY KEY,
    geom        geometry(LineString, 4326) NOT NULL,
    n_points    INTEGER NOT NULL
);

CREATE INDEX shapes_geom_geom_idx ON gtfs_geom.shapes_geom USING gist (geom);

-- migrate:down
DROP TABLE gtfs_geom.shapes_geom;
