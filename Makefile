# Connect to project DB
psql:
		docker compose exec postgis psql -U transit -d transit

# Run ad-hoc SQL string: Make q SQL="SELECT (*) FROM ..."
q:
		docker compose exec postgis psql -U transit -d transit -c "$(SQL)"

# SQL queries via .sql file 
sql:
		docker compose exec -T postgis psql -U transit -d transit < $(FILE)

# Load static GTFS snapshot (override SNAPSHOT_DIR if needed)
SNAPSHOT_DIR ?= data/raw/gtfs-static/sound-transit-20260624
SNAPSHOT_DATE ?= 2026-06-24

load:
		uv run python -m ingest.load_gtfs_static \
						--snapshot-dir $(SNAPSHOT_DIR) \
						--snapshot-date $(SNAPSHOT_DATE)

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

# Single poll
poll:
		uv run python -m ingest.poll_gtfs_rt

# Continuous polling at 30s intervals - Ctrl-C to stop
poll-loop:
		@while true; do \
						$(MAKE) poll; \
						sleep 30; \
		done

.PHONY: psql q sql  load migrate rollback status up down poll poll-loop
