# 0003 — GTFS-Realtime Field Coverage from Sound Transit OBA

**Status:** Accepted
**Date:** 2026-06-24

## Context

The GTFS-Realtime specification (https://gtfs.org/realtime/reference/) defines many optional fields on a `VehiclePosition` entity: per-vehicle `current_status`, `current_stop_sequence`, `stop_id`, `speed`, `bearing`, `congestion_level`, `occupancy_status`, and more. Each agency chooses which to publish.

The first polling-and-storage tests of `gtfs_rt.vehicle_positions` revealed that Sound Transit's OneBusAway export populates a smaller subset than the schema anticipated. Inspection of a raw protobuf entity confirmed:

```
id: "1"
vehicle {
  trip { trip_id: "...", route_id: "100479" }
  position { latitude: 47.3473473, longitude: -122.294067 }
  timestamp: 1782268788
  vehicle { id: "253.617847" }
}
```

Published fields per vehicle: `trip_id`, `route_id`, `vehicle.id`, `position.latitude`, `position.longitude`, `timestamp`.

Absent fields: `current_status`, `current_stop_sequence`, `stop_id`, `speed`, `bearing`.

## Decision

**Accept the published field subset. Derive missing fields spatially rather than requesting them from the agency.**

The `gtfs_rt.vehicle_positions` table keeps the missing columns (with `NULL` values for ST pings). They are NOT removed because:
- Other agencies' RT feeds (e.g., KC Metro standalone) may populate them.
- Future agency feed changes could begin populating them.
- Schema cost of nullable columns is negligible.

For ST-served analyses, the pipeline derives equivalent or better data from the precomputed static layer:

| Missing RT field | Spatially derived equivalent |
|---|---|
| `current_status` (approaching / stopped at / in transit) | Compare `actual_fraction` (from `ST_LineLocatePoint`) to the bracketing stops in `trip_stop_progress`. Distance under threshold = "stopped at." |
| `stop_id` (current stop) | Lookup the row in `trip_stop_progress` with the largest `fraction <= actual_fraction`. |
| `current_stop_sequence` | Same lookup, return `stop_sequence`. |
| `speed` | Derivable from consecutive pings: `(distance_meters_2 - distance_meters_1) / (timestamp_2 - timestamp_1)`. Not currently computed; would be a window query. |
| `bearing` | Derivable from consecutive pings: `degrees(ST_Azimuth(p1, p2))`. Not currently computed. |

## Consequences

**Positives:**
- Pipeline doesn't depend on the agency populating optional fields. Works identically against any GTFS-RT publisher.
- Derived `current_status` is arguably more accurate than the agency's self-report: it's measured from actual GPS proximity to the stop geometry, not flagged by an upstream system.
- The substitution-via-derivation pattern is the same technique used for arrival time estimates: linear-interpolating between bracketing scheduled stops. Demonstrates the value of the precomputed `trip_stop_progress` table.

**Tradeoffs:**
- Speed and bearing aren't available without consecutive-ping window queries, which are more expensive than reading a scalar column. Acceptable for analytical workloads; not ideal for a real-time map showing direction-of-travel.
- The mitigation assumes the vehicle is following its scheduled shape. For ad-hoc routing or unscheduled service patterns, the assumption breaks. Not relevant for fixed-guideway Link service.
