-- Count rows at each stage of the lateness pipeline
SELECT 'total pings' AS stage, count(*) FROM gtfs_rt.vehicle_positions
UNION ALL
SELECT 'pings with trip_id',
        COUNT(*) FROM gtfs_rt.vehicle_positions WHERE trip_id IS NOT NULL
UNION ALL
SELECT 'pings whose trip_id exists in gtfs_static.trips',
        COUNT(*) FROM gtfs_rt.vehicle_positions vp
        WHERE EXISTS (SELECT 1 FROM gtfs_static.trips t WHERE t.trip_id = vp.trip_id)
UNION ALL
SELECT 'pings whose trip has rows in trip_stop_progress',
        COUNT(*) FROM gtfs_rt.vehicle_positions vp
        WHERE EXISTS (SELECT 1 FROM gtfs_geom.trip_stop_progress tsp WHERE tsp.trip_id = vp.trip_id)
UNION ALL
SELECT 'pings with start_date populated',
        COUNT(*) FROM gtfs_rt.vehicle_positions WHERE start_date IS NOT NULL
UNION ALL
SELECT 'pings with trip_id AND start_date AND matching static trip',
        COUNT(*) FROM gtfs_rt.vehicle_positions vp
        WHERE vp.trip_id IS NOT NULL
          AND vp.start_date IS NOT NULL
          AND EXISTS (SELECT 1 FROM gtfs_static.trips t WHERE t.trip_id = vp.trip_id);
