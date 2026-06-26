-- Per-route lateness distribution across all matched pings.
-- Outlier-trim at the 95th percentile to ignore obviously stale trip assignments.
WITH ping_fractions AS (
    SELECT
        vp.ping_id,
        vp.trip_id,
        vp.received_at,
        COALESCE(
            vp.start_date,
            (vp.received_at AT TIME ZONE 'America/Los_Angeles')::date
        ) AS service_date,
        t.route_id,
        ST_LineLocatePoint(sh.geom, vp.geom) AS actual_fraction
    FROM gtfs_rt.vehicle_positions vp
    JOIN gtfs_static.trips t USING (trip_id)
    JOIN gtfs_geom.shapes_geom sh ON sh.shape_id = t.shape_id
    WHERE vp.trip_id IS NOT NULL
),
bracketed AS (
    SELECT
        p.*,
        prev.fraction     AS prev_frac,
        prev.arrival_time AS prev_arrival,
        next.fraction     AS next_frac,
        next.arrival_time AS next_arrival
    FROM ping_fractions p
    LEFT JOIN LATERAL (
        SELECT tsp.fraction, st.arrival_time
        FROM gtfs_geom.trip_stop_progress tsp
        JOIN gtfs_static.stop_times st
            ON (st.trip_id, st.stop_sequence) = (tsp.trip_id, tsp.stop_sequence)
        WHERE tsp.trip_id = p.trip_id
          AND tsp.fraction <= p.actual_fraction
          AND st.arrival_time IS NOT NULL
        ORDER BY tsp.fraction DESC LIMIT 1
    ) prev ON true
    LEFT JOIN LATERAL (
        SELECT tsp.fraction, st.arrival_time
        FROM gtfs_geom.trip_stop_progress tsp
        JOIN gtfs_static.stop_times st
            ON (st.trip_id, st.stop_sequence) = (tsp.trip_id, tsp.stop_sequence)
        WHERE tsp.trip_id = p.trip_id
          AND tsp.fraction > p.actual_fraction
          AND st.arrival_time IS NOT NULL
        ORDER BY tsp.fraction ASC LIMIT 1
    ) next ON true
    WHERE prev.fraction IS NOT NULL
      AND next.fraction IS NOT NULL
      AND next.fraction > prev.fraction
),
with_lateness AS (
    SELECT
        route_id,
        EXTRACT(EPOCH FROM (
            received_at -
            ((service_date::timestamp
                + prev_arrival
                + (actual_fraction - prev_frac) / (next_frac - prev_frac)
                  * (next_arrival - prev_arrival)
            ) AT TIME ZONE 'America/Los_Angeles')
        )) AS lateness_seconds
    FROM bracketed
),
-- Trim outliers (mismatched trip assignments produce huge lateness values)
trimmed AS (
    SELECT * FROM with_lateness
    WHERE abs(lateness_seconds) < 1800   -- ignore > 30 min in either direction
)
SELECT
    route_id,
    COUNT(*) AS pings,
    round(avg(lateness_seconds)::numeric, 1) AS mean_lateness_sec,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY lateness_seconds)::numeric, 1) AS median_lateness_sec,
    round(percentile_cont(0.95) WITHIN GROUP (ORDER BY lateness_seconds)::numeric, 1) AS p95_lateness_sec,
    round(min(lateness_seconds)::numeric, 1) AS min_lateness_sec,
    round(max(lateness_seconds)::numeric, 1) AS max_lateness_sec
FROM trimmed
GROUP BY route_id
ORDER BY median_lateness_sec DESC;
