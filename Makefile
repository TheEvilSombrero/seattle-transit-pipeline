# Connect to project DB
psql:
		docker compose exec postgis psql -U transit -d transit

# Run ad-hoc SQL string: Make q SQL="SELECT (*) FROM ..."
q:
		docker compose exec postgis psql -U transit -d transit -c "$(SQL)"

# Load static GTFS snapshot (override SNAPSHOT_DIR if needed)
SNAPSHOT-DIR ?= data/raw/gtfs-static/sound-transit-20260514
SNAPSHOT-DATE ?= 2026-05-14

load:
		uv run python -m ingest.load_gtfs_static \
						--snapshot_dir $(SNAPSHOT_DIR) \
						--snapshot_date $(SNAPSHOT_DATE)

# dbmate shortcuts
migrate:
		dbmate up

rollback:
		dbmate rollback

status:
		dbmate status

# Spin stack up/down
up:
		docker compose up -d

down:
		docker compose down

.PHONY: psql q load migrate rollback status up down
