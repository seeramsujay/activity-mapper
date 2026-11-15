package org.opensource.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.turnback.TurnBackEngine
import java.time.Duration
import java.time.Instant

class TurnBackEngineTest {

    @Test
    fun testComputeOutboundLimit() {
        val target = Duration.ofMinutes(60)
        // With beta = 0.12 and 15% safety factor:
        // denom = 1 + (1 + 0.12) * 1.15 = 1 + 1.288 = 2.288
        // outbound = 3600 / 2.288 ~ 1573 sec (~26.2 min)
        val limit = TurnBackEngine.computeOutboundLimit(target, beta = 0.12, safetyBufferPercent = 15.0)
        assertTrue(limit.toMinutes() in 25..27)
    }

    @Test
    fun testHaversineDistance() {
        // Distance between (0, 0) and (1, 0) is ~111.19 km (111190 m)
        val dist = TurnBackEngine.haversineDistanceMeters(0.0, 0.0, 1.0, 0.0)
        assertEquals(111195.0, dist, 200.0)
    }

    @Test
    fun testComputeSplits() {
        val now = Instant.now()
        // 3 points, total ~2.22 km
        val points = listOf(
            TrackPoint(latitude = 12.0, longitude = 77.0, altitudeMeters = 100.0, speedMps = 3.5, timestamp = now),
            TrackPoint(latitude = 12.01, longitude = 77.0, altitudeMeters = 110.0, speedMps = 3.5, timestamp = now.plusSeconds(300)),
            TrackPoint(latitude = 12.02, longitude = 77.0, altitudeMeters = 120.0, speedMps = 3.5, timestamp = now.plusSeconds(600))
        )

        val splits = TurnBackEngine.computeSplits(points, splitIntervalKm = 1.0)
        assertTrue(splits.size >= 2)
        assertEquals(1, splits[0].lapNumber)
        assertEquals(2, splits[1].lapNumber)
        assertEquals(1.0, splits[0].distanceKm, 0.1)
    }

    @Test
    fun testFastestAndSlowestSplitIdentification() {
        val now = Instant.now()
        // Create 3 splits with distinct paces:
        // Lap 1: 1 km in 300 sec (5:00 /km, 12 km/h)
        // Lap 2: 1 km in 240 sec (4:00 /km, 15 km/h) -> FASTEST
        // Lap 3: 1 km in 360 sec (6:00 /km, 10 km/h) -> SLOWEST
        val points = mutableListOf<TrackPoint>()
        var t = 0L

        // Lap 1 (0 -> 1 km)
        for (i in 0..10) {
            points.add(TrackPoint(10.0 + (i * 0.0009), 20.0, 100.0, 3.33, 5.0, 0f, now.plusSeconds(t)))
            t += 30L
        }
        // Lap 2 (1 -> 2 km, faster)
        for (i in 1..10) {
            points.add(TrackPoint(10.009 + (i * 0.0009), 20.0, 100.0, 4.16, 5.0, 0f, now.plusSeconds(t)))
            t += 24L
        }
        // Lap 3 (2 -> 3 km, slower)
        for (i in 1..10) {
            points.add(TrackPoint(10.018 + (i * 0.0009), 20.0, 100.0, 2.77, 5.0, 0f, now.plusSeconds(t)))
            t += 36L
        }

        val stats = TurnBackEngine.computeStats(points)
        assertTrue("Should have 3 split laps", stats.splits.size >= 3)
        assertNotNull("Fastest split should be present", stats.fastestSplit)
        assertEquals("Lap 2 should be the fastest split", 2, stats.fastestSplit?.lapNumber)
        assertTrue("Lap 2 must have isFastest set to true", stats.splits[1].isFastest)
        assertEquals("Lap 3 should be the slowest split", 3, stats.slowestSplit?.lapNumber)
        assertTrue("Lap 3 must have isSlowest set to true", stats.splits[2].isSlowest)
    }

    @Test
    fun testElevationHysteresisIgnoresJitter() {
        val now = Instant.now()
        // Small 1m jitter should not accumulate gain
        val points = listOf(
            TrackPoint(latitude = 12.0, longitude = 77.0, altitudeMeters = 100.0, timestamp = now),
            TrackPoint(latitude = 12.001, longitude = 77.0, altitudeMeters = 101.0, timestamp = now.plusSeconds(10)),
            TrackPoint(latitude = 12.002, longitude = 77.0, altitudeMeters = 100.5, timestamp = now.plusSeconds(20)),
            TrackPoint(latitude = 12.003, longitude = 77.0, altitudeMeters = 101.2, timestamp = now.plusSeconds(30))
        )

        val stats = TurnBackEngine.computeStats(points)
        assertEquals(0.0, stats.elevationGainM, 0.1)
    }
}
