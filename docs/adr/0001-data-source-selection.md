# 0001 — Data Source Selection

**Status:** Accepted
**Date:** 2026-05-02

## Context

Two regional agencies publish GTFS-Realtime feeds for Puget Sound transit: **King County Metro** (KC Metro) and **Sound Transit** (ST). The project goal is a portfolio-grade pipeline demonstrating GTFS-static ingestion + GTFS-RT analysis + spatial work. A primary feed had to be chosen for Phase 1; the choice affects schema design, demo legibility, and operational complexity.

Two qualifying APIs exist for Sound Transit:
- The **OneBusAway REST API** (`/api/where/...`, JSON/XML)
- The **GTFS-Realtime export** (`/api/gtfs_realtime/vehicle-positions-for-agency/<id>.pb`, binary protobuf)

Both require an OBA API key, obtained by emailing `oba_api_key@soundtransit.org`.

## Decision

**Use Sound Transit's GTFS-Realtime export endpoint as the primary RT source for Phase 1.**

The endpoint is `https://api.pugetsound.onebusaway.org/api/gtfs_realtime/vehicle-positions-for-agency/40.pb?key=<key>` where `40` is the Sound Transit agency ID.

Use the Sound Transit standalone GTFS-static zip from the OTD downloads page (not the Puget Sound Consolidated zip) for Phase 1; the consolidated zip is reserved for Phase 1.5 expansion.

## Consequences

**Positives:**
- GTFS-Realtime is the industry-standard format; protobuf parsing transfers to any other agency's RT feed without code changes. Stronger résumé signal than vendor-specific REST.
- Link light rail has fixed-guideway shapes — linear referencing (`ST_LineLocatePoint`) snaps cleanly to rail without GPS drift artifacts. Easier to validate correctness on a learning project than bus data.
- Smaller dataset (8 routes vs KC Metro's ~200) makes correctness inspection tractable while still demonstrating real scale at the stop_times level (313K–396K rows depending on snapshot).

**Surprises discovered after implementation:**
- The OBA "agency 40" endpoint is **not** Sound Transit only. Live polling returns vehicle pings from KC Metro fleet IDs (route IDs in the `100xxx`/`102xxx` ranges) alongside Sound Transit pings. The OBA deployment evidently aggregates multiple agencies' RT into the same feed. Effective consequence: Phase 1 already has KC Metro data flowing in; only the static schema needs expanding (via the Consolidated zip) to make it queryable.
- The published RT feed contains fewer fields than the GTFS-RT spec permits. Observed per-vehicle fields: `trip_id`, `route_id`, `vehicle.id`, `position.latitude`, `position.longitude`, `timestamp`. Absent: `current_status`, `stop_id`, `current_stop_sequence`, `speed`, `bearing`. See ADR 0003 for how the project compensates by deriving these spatially.

**Tradeoffs accepted:**
- Phase 1 lateness analytics only join cleanly for ST trips (8 routes). KC Metro pings exist in the table but lack matching `gtfs_static.trips` rows until the consolidated GTFS zip is loaded.
- The OBA REST API offers richer per-vehicle metadata (deviation, occupancy) that the GTFS-RT export omits. If those metrics become priorities later, a secondary REST-based poller can be added without disturbing the primary pipeline.
