-- migrate:up
CREATE TABLE gtfs_static.calendar_dates (
    service_id TEXT NOT NULL,
    date DATE NOT NULL,
    exception_type SMALLINT NOT NULL,
    PRIMARY KEY (service_id, date)
);

-- migrate:down
DROP TABLE gtfs_static.calendar_dates;
