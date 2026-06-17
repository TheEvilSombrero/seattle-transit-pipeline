-- migrate:up
CREATE TABLE meta.ingest_log(
    ingest_id BIGSERIAL PRIMARY KEY,
    source_name TEXT NOT NULL,
    snapshot_date DATE NOT NULL,
    source_url TEXT,
    file_checksum TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'started' CHECK (status IN ('started','completed','failed')),
    row_counts JSONB,
    error_message TEXT,
    notes TEXT
);

-- migrate:down
DROP TABLE meta.ingest_log;
