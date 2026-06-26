# 0004 — Handling GTFS Schema Drift Between Snapshots

**Status:** Accepted
**Date:** 2026-06-25

## Context

Sound Transit republishes its GTFS static feed every few weeks, typically aligned with service changes. The May 14, 2026 snapshot included a non-standard column `departure_buffer` in `stop_times.txt` (an ST-custom extension, not in the GTFS spec). The June 24, 2026 snapshot dropped that column.

The original loader assumed each table's columns were positionally aligned with the CSV file's fields. When the June snapshot was loaded against the schema that included `departure_buffer`, COPY failed:

```
psycopg.errors.BadCopyFileFormat: missing data for column "departure_buffer"
```

This is a generic problem: agency feeds can add or drop columns at any service change. A pipeline that breaks on every reissue is fragile.

## Decision

**Detect CSV columns dynamically at load time and pass the intersection of CSV-present and table-present columns to COPY.**

`ingest/load_gtfs_static.py` now contains:
- `_csv_header(path)` reads the first line of each CSV and returns the column name list.
- `_table_columns(cur, schema, table)` queries `information_schema.columns` for the table's declared columns.
- `load_all_tables` computes the intersection (preserving CSV column order, which matches the field order in data rows) and passes it explicitly to COPY:
  ```sql
  COPY gtfs_static.X (col1, col2, ...) FROM STDIN WITH (FORMAT csv, HEADER true, NULL '')
  ```

CSV columns absent from the table are silently skipped (logged at load time but not errored). Table columns absent from the CSV get their column default (NULL for the project's nullable columns).

## Consequences

**Positives:**
- Loader tolerates both added and dropped CSV columns without code changes.
- The May 14 snapshot (with `departure_buffer`) and the June 24 snapshot (without) both load against the same schema. No schema migration is required for the drop.
- Clear audit trail: skipped CSV columns are logged at load time, so a column being silently ignored is visible in stdout (and could be wired to the ingest log if it becomes a concern).

**Tradeoffs:**
- Table columns that the CSV no longer populates become silently empty. If a downstream query expects values there, it will see NULLs and may quietly return wrong results. Mitigation: rely on declared `NOT NULL` constraints — the loader will error if a required column is absent from the CSV.
- Adding a new field to the schema doesn't auto-populate from new CSVs unless a column with the matching name appears in the CSV header. This is the desired behavior; the alternative would silently overload an existing column.

**Future:** if this pipeline expanded to many agencies with widely varying GTFS feeds, the next step would be a staging-table pattern (load every CSV column as `TEXT` into per-agency staging tables, then `INSERT ... SELECT` with explicit casts into typed reference tables). Not warranted for one agency at portfolio scale.
