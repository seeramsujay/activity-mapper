package org.opensource.tracker

import org.junit.Assert.assertTrue
import org.junit.Test
import org.opensource.tracker.data.gpx.GpxExporter
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.model.Waypoint
import org.opensource.tracker.domain.model.WaypointCategory
import java.time.Instant

class GpxServiceTest {

    @Test
    fun testBuildGpxStringContainsWptAndTrkpt() {
        val now = Instant.now()
        val points = listOf(
            TrackPoint(latitude = 37.7749, longitude = -122.4194, altitudeMeters = 15.0, speedMps = 4.2, timestamp = now),
            TrackPoint(latitude = 37.7750, longitude = -122.4195, altitudeMeters = 16.0, speedMps = 4.5, timestamp = now.plusSeconds(5))
        )
        val waypoints = listOf(
            Waypoint(0L, 1L, "Summit Peak", "Great view", 37.7750, -122.4195, 16.0, WaypointCategory.VIEWPOINT, timestamp = now)
        )

        val gpx = GpxExporter.buildGpxString(
            trackName = "Morning Trail",
            activityType = "RUN",
            points = points,
            waypoints = waypoints,
            startTime = now
        )

        assertTrue(gpx.contains("<name>Morning Trail</name>"))
        assertTrue(gpx.contains("<wpt lat=\"37.7750000\" lon=\"-122.4195000\">"))
        assertTrue(gpx.contains("<name>Summit Peak</name>"))
        assertTrue(gpx.contains("<sym>Scenic Area</sym>"))
        assertTrue(gpx.contains("<trkpt lat=\"37.7749000\" lon=\"-122.4194000\">"))
        assertTrue(gpx.contains("<gpxtpx:speed>4.20</gpxtpx:speed>"))
    }
}
