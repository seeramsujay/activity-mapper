package org.opensource.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.opensource.tracker.data.gpx.GpxExporter
import org.opensource.tracker.data.gpx.GpxImporter
import org.opensource.tracker.data.wal.RecordingWal
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.model.Waypoint
import org.opensource.tracker.domain.model.WaypointCategory
import org.opensource.tracker.domain.turnback.TurnBackEngine
import java.io.ByteArrayInputStream
import java.io.File
import java.time.Duration
import java.time.Instant

/**
 * Automated verification of all user scenarios defined in user-checklist.md.
 */
class UserUseCasesTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun testUseCase1_TimedTrailRunnerPacing() {
        // Target: 60 minutes
        val target60 = Duration.ofMinutes(60)
        val outbound60 = TurnBackEngine.computeOutboundLimit(target60, beta = 0.12, safetyBufferPercent = 15.0)
        // With beta = 0.12 and 15% safety factor, outbound is ~26.2 minutes
        assertTrue("Outbound should be between 25 and 27 minutes", outbound60.toMinutes() in 25..27)

        // Target: 120 minutes with higher fatigue (beta = 0.20)
        val target120 = Duration.ofMinutes(120)
        val outbound120 = TurnBackEngine.computeOutboundLimit(target120, beta = 0.20, safetyBufferPercent = 15.0)
        // denom = 1 + 1.2 * 1.15 = 2.38 -> 120 / 2.38 ~ 50.4 minutes
        assertTrue("Outbound should be between 49 and 52 minutes", outbound120.toMinutes() in 49..52)
    }

    @Test
    fun testUseCase2_MountainHikerElevationAndWaypoints() {
        val now = Instant.now()
        // Ascending 100m in steps with small noise
        val points = mutableListOf<TrackPoint>()
        var currentAlt = 500.0
        for (i in 0..20) {
            currentAlt += 5.0
            points.add(
                TrackPoint(
                    latitude = 45.0 + (i * 0.001),
                    longitude = 6.0 + (i * 0.001),
                    altitudeMeters = currentAlt,
                    speedMps = 1.2,
                    timestamp = now.plusSeconds((i * 60).toLong())
                )
            )
        }

        val stats = TurnBackEngine.computeStats(points)
        // Sustained climb should accumulate ~100m of gain
        assertEquals(105.0, stats.elevationGainM, 5.0)
        assertEquals(0.0, stats.elevationLossM, 1.0)

        // Verify Waypoints
        val spring = Waypoint(
            sessionId = 1L,
            name = "Clear Spring",
            description = "Potable water source",
            latitude = 45.005,
            longitude = 6.005,
            altitudeMeters = 525.0,
            category = WaypointCategory.WATER
        )
        val summit = Waypoint(
            sessionId = 1L,
            name = "Eagle Peak",
            latitude = 45.020,
            longitude = 6.020,
            altitudeMeters = 605.0,
            category = WaypointCategory.VIEWPOINT
        )

        val gpx = GpxExporter.buildGpxString("Mountain Hike", "HIKE", points, listOf(spring, summit))
        assertTrue(gpx.contains("<sym>Water Source</sym>"))
        assertTrue(gpx.contains("<sym>Scenic Area</sym>"))
        assertTrue(gpx.contains("<name>Clear Spring</name>"))
        assertTrue(gpx.contains("<name>Eagle Peak</name>"))
    }

    @Test
    fun testUseCase4_MovingVsStoppedTimeDetection() {
        val now = Instant.now()
        val points = listOf(
            // Moving leg: 5 minutes at 2.5 m/s (~9 km/h)
            TrackPoint(latitude = 10.000, longitude = 20.000, speedMps = 2.5, timestamp = now),
            TrackPoint(latitude = 10.005, longitude = 20.005, speedMps = 2.5, timestamp = now.plusSeconds(300)),
            // Stopped leg (lunch / rest at viewpoint): 10 minutes at 0.1 m/s
            TrackPoint(latitude = 10.005, longitude = 20.005, speedMps = 0.1, timestamp = now.plusSeconds(900)),
            // Resuming moving leg: 5 minutes at 2.5 m/s
            TrackPoint(latitude = 10.010, longitude = 20.010, speedMps = 2.5, timestamp = now.plusSeconds(1200))
        )

        val stats = TurnBackEngine.computeStats(points, totalDuration = Duration.ofSeconds(1200))
        // Moving time should count the two 5-min intervals (~600s), stopped time ~600s
        assertEquals(10, stats.movingDuration.toMinutes())
        assertEquals(10, stats.stoppedDuration.toMinutes())
    }

    @Test
    fun testUseCase5_CrashProofWalRecoveryFullFidelity() {
        val file = File(tempFolder.root, "crash_test.wal")
        val wal = RecordingWal.create(file)

        val now = Instant.ofEpochMilli(1700000000000L)
        for (i in 0..10) {
            wal.appendPoint(
                TrackPoint(
                    latitude = 12.0 + (i * 0.001),
                    longitude = 77.0 + (i * 0.001),
                    altitudeMeters = 900.0 + i,
                    speedMps = 3.0,
                    accuracyMeters = 4.0,
                    timestamp = now.plusSeconds((i * 10).toLong())
                )
            )
        }
        val campWpt = Waypoint(
            sessionId = 1L,
            name = "Base Camp",
            description = "Shelter with tent site",
            latitude = 12.005,
            longitude = 77.005,
            altitudeMeters = 905.0,
            category = WaypointCategory.CAMP,
            timestamp = now.plusSeconds(50)
        )
        wal.appendWaypoint(campWpt)
        wal.close()

        // Simulate reading after unexpected phone shutdown
        val recovered = RecordingWal.recover(file)
        assertEquals(11, recovered.points.size)
        assertEquals(1, recovered.waypoints.size)
        assertEquals("Base Camp", recovered.waypoints[0].name)
        assertEquals(WaypointCategory.CAMP, recovered.waypoints[0].category)
        assertEquals(12.010, recovered.points.last().latitude, 0.0001)
    }

    @Test
    fun testUseCase6_IntervalSplitsPacing() {
        val now = Instant.now()
        // Create 3.5 km of points
        val points = mutableListOf<TrackPoint>()
        for (i in 0..35) {
            points.add(
                TrackPoint(
                    latitude = 10.0 + (i * 0.0009), // ~100m each step
                    longitude = 20.0,
                    altitudeMeters = 100.0 + (i % 5),
                    speedMps = 3.33, // 12 km/h -> 5:00 /km pace
                    timestamp = now.plusSeconds((i * 30).toLong())
                )
            )
        }

        val splits = TurnBackEngine.computeSplits(points, splitIntervalKm = 1.0)
        assertTrue("Should have at least 3 completed 1-km splits", splits.size >= 3)
        assertEquals(1, splits[0].lapNumber)
        assertEquals(2, splits[1].lapNumber)
        assertEquals(3, splits[2].lapNumber)
        for (split in splits.take(3)) {
            assertEquals(1.0, split.distanceKm, 0.15)
            assertFalse("Pace should be populated", split.paceMinKm == "--:--")
        }
    }

    @Test
    fun testUseCase8_GpxRoundTripImportExport() {
        val now = Instant.ofEpochMilli(1700000000000L)
        val originalPoints = listOf(
            TrackPoint(latitude = 37.7749, longitude = -122.4194, altitudeMeters = 15.0, speedMps = 4.2, timestamp = now),
            TrackPoint(latitude = 37.7755, longitude = -122.4180, altitudeMeters = 18.0, speedMps = 4.8, timestamp = now.plusSeconds(30)),
            TrackPoint(latitude = 37.7760, longitude = -122.4170, altitudeMeters = 20.0, speedMps = 5.0, timestamp = now.plusSeconds(60))
        )
        val originalWaypoints = listOf(
            Waypoint(0L, 1L, "Hazard Tree", "Fallen trunk across path", 37.7755, -122.4180, 18.0, WaypointCategory.HAZARD, timestamp = now)
        )

        val gpxString = GpxExporter.buildGpxString(
            trackName = "Sunset Loop",
            activityType = "RUN",
            points = originalPoints,
            waypoints = originalWaypoints,
            startTime = now
        )

        // Parse back
        val parsed = GpxImporter.parse(ByteArrayInputStream(gpxString.toByteArray(Charsets.UTF_8)))
        assertEquals("Sunset Loop", parsed.name)
        assertEquals(3, parsed.points.size)
        assertEquals(1, parsed.waypoints.size)

        assertEquals(37.7749, parsed.points[0].latitude, 0.0001)
        assertEquals(-122.4194, parsed.points[0].longitude, 0.0001)
        assertEquals(15.0, parsed.points[0].altitudeMeters, 0.1)
        assertEquals("Hazard Tree", parsed.waypoints[0].name)
        assertEquals(WaypointCategory.HAZARD, parsed.waypoints[0].category)
    }
}
