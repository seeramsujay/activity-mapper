package org.opensource.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.opensource.tracker.data.gpx.GpxExporter
import org.opensource.tracker.data.gpx.GpxImporter
import org.opensource.tracker.data.gpx.GpxTrackImporter
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.turnback.TurnBackEngine
import java.io.ByteArrayInputStream
import java.time.Instant

class GpxImportTest {
    private val t0: Instant = Instant.parse("2026-01-01T10:00:00Z")

    private fun point(
        lat: Double,
        lon: Double,
        secondsFromStart: Long,
        speed: Double = 0.0,
        newSegment: Boolean = false,
    ) = TrackPoint(lat, lon, speedMps = speed, timestamp = t0.plusSeconds(secondsFromStart), newSegment = newSegment)

    private fun gpx(vararg segments: String): String =
        """<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>T</name>""" +
            segments.joinToString("") { "<trkseg>$it</trkseg>" } +
            "</trk></gpx>"

    private fun trkpt(
        lat: Double,
        lon: Double,
        time: String,
    ) = """<trkpt lat="$lat" lon="$lon"><time>$time</time></trkpt>"""

    @Test
    fun `timestamps going backwards are rejected, equal timestamps are fine`() {
        val ordered = listOf(point(0.0, 0.0, 0), point(0.0, 0.001, 10))
        assertNull(GpxTrackImporter.validateTimestamps(ordered))

        val backwards = listOf(point(0.0, 0.0, 10), point(0.0, 0.001, 0))
        assertNotNull(GpxTrackImporter.validateTimestamps(backwards))

        val untimed = listOf(point(0.0, 0.0, 0), point(0.0, 0.001, 0))
        assertNull(GpxTrackImporter.validateTimestamps(untimed))
    }

    @Test
    fun `speeds are derived from distance over time when the file has none`() {
        // ~111 m north every 10 s => ~11 m/s
        val bare = listOf(point(0.000, 0.0, 0), point(0.001, 0.0, 10), point(0.002, 0.0, 20))
        val normalized = GpxTrackImporter.normalizeSpeeds(bare)
        assertEquals(0.0, normalized[0].speedMps, 0.0)
        assertEquals(11.1, normalized[1].speedMps, 0.3)
        assertEquals(11.1, normalized[2].speedMps, 0.3)

        val stats = TurnBackEngine.computeStats(normalized, java.time.Duration.ofSeconds(20))
        assertTrue("moving time must no longer be zero", stats.movingDuration.seconds > 0)
        assertTrue(stats.avgSpeedKmh > 30.0)
    }

    @Test
    fun `explicit speeds are preserved untouched`() {
        val withSpeed = listOf(point(0.0, 0.0, 0, speed = 3.0), point(0.001, 0.0, 10, speed = 0.0))
        assertEquals(withSpeed, GpxTrackImporter.normalizeSpeeds(withSpeed))
    }

    @Test
    fun `no speed is derived across zero elapsed time or segment boundaries`() {
        val sameTime = listOf(point(0.0, 0.0, 0), point(0.001, 0.0, 0))
        assertEquals(0.0, GpxTrackImporter.normalizeSpeeds(sameTime)[1].speedMps, 0.0)

        val segmented = listOf(point(0.0, 0.0, 0), point(5.0, 5.0, 10, newSegment = true))
        assertEquals(0.0, GpxTrackImporter.normalizeSpeeds(segmented)[1].speedMps, 0.0)
    }

    @Test
    fun `parser flags the first point of each later segment`() {
        val xml =
            gpx(
                trkpt(0.0, 0.0, "2026-01-01T10:00:00Z") + trkpt(0.0, 0.001, "2026-01-01T10:00:10Z"),
                trkpt(1.0, 1.0, "2026-01-01T12:00:00Z") + trkpt(1.0, 1.001, "2026-01-01T12:00:10Z"),
            )
        val points = GpxImporter.parse(ByteArrayInputStream(xml.toByteArray())).points
        assertEquals(listOf(false, false, true, false), points.map { it.newSegment })
    }

    @Test
    fun `a single segment keeps its previous behaviour`() {
        val xml = gpx(trkpt(0.0, 0.0, "2026-01-01T10:00:00Z") + trkpt(0.0, 0.001, "2026-01-01T10:00:10Z"))
        val points = GpxImporter.parse(ByteArrayInputStream(xml.toByteArray())).points
        assertEquals(2, points.size)
        assertFalse(points.any { it.newSegment })
    }

    @Test
    fun `distance never bridges the gap between segments`() {
        val connected = listOf(point(0.0, 0.0, 0, speed = 3.0), point(0.0, 0.001, 10, speed = 3.0))
        val oneSegment = TurnBackEngine.computeStats(connected).distanceKm

        // Same two legs, but 100+ km apart as separate segments: the gap must not be counted.
        val twoSegments =
            listOf(
                point(0.0, 0.0, 0, speed = 3.0),
                point(0.0, 0.001, 10, speed = 3.0),
                point(1.0, 1.0, 7200, speed = 3.0, newSegment = true),
                point(1.0, 1.001, 7210, speed = 3.0),
            )
        val stats = TurnBackEngine.computeStats(twoSegments)
        assertEquals(oneSegment * 2, stats.distanceKm, 0.002)
    }

    @Test
    fun `export then parse round-trips segment boundaries`() {
        val points =
            listOf(
                point(0.0, 0.0, 0, speed = 2.0),
                point(0.0, 0.001, 10, speed = 2.0),
                point(1.0, 1.0, 100, speed = 2.0, newSegment = true),
                point(1.0, 1.001, 110, speed = 2.0),
            )
        val xml = GpxExporter.buildGpxString("Round trip", "RUN", points)
        assertEquals(2, Regex("<trkseg>").findAll(xml).count())

        val parsed = GpxImporter.parse(ByteArrayInputStream(xml.toByteArray())).points
        assertEquals(listOf(false, false, true, false), parsed.map { it.newSegment })
    }
}
