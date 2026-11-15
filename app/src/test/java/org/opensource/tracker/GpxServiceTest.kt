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
        val points =
            listOf(
                TrackPoint(
                    latitude = 37.7749,
                    longitude = -122.4194,
                    altitudeMeters = 15.0,
                    speedMps = 4.2,
                    timestamp = now,
                ),
                TrackPoint(
                    latitude = 37.7750,
                    longitude = -122.4195,
                    altitudeMeters = 16.0,
                    speedMps = 4.5,
                    timestamp = now.plusSeconds(5),
                ),
            )
        val waypoints =
            listOf(
                Waypoint(
                    sessionId = 0L,
                    id = 1L,
                    name = "Summit Peak",
                    description = "Great view",
                    latitude = 37.7750,
                    longitude = -122.4195,
                    altitudeMeters = 16.0,
                    category = WaypointCategory.VIEWPOINT,
                    timestamp = now,
                ),
            )

        val gpx =
            GpxExporter.buildGpxString(
                trackName = "Morning Trail",
                activityType = "RUN",
                points = points,
                waypoints = waypoints,
                startTime = now,
            )

        assertTrue(gpx.contains("<name>Morning Trail</name>"))
        assertTrue(gpx.contains("<type>RUN</type>"))
        assertTrue(gpx.contains("<wpt lat=\"37.775\" lon=\"-122.4195\">"))
        assertTrue(gpx.contains("<sym>Scenic Area</sym>"))
        assertTrue(gpx.contains("<trkpt lat=\"37.7749\" lon=\"-122.4194\">"))
        assertTrue(gpx.contains("<gpxtpx:speed>4.2</gpxtpx:speed>"))
    }
}
