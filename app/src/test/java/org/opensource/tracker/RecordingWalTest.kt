package org.opensource.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.opensource.tracker.data.wal.RecordingWal
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.model.Waypoint
import org.opensource.tracker.domain.model.WaypointCategory
import java.io.File
import java.time.Instant

class RecordingWalTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun testWalAppendAndRecovery() {
        val file = File(tempFolder.root, "test.wal")
        val wal = RecordingWal.create(file)

        val pt1 = TrackPoint(12.34, 56.78, 100.0, 3.5, 4.0, timestamp = Instant.ofEpochMilli(1000000))
        val pt2 = TrackPoint(12.35, 56.79, 105.0, 3.6, 4.5, timestamp = Instant.ofEpochMilli(2000000))
        val wpt = Waypoint(0L, 1L, "Fresh Spring", "Clear drinking water", 12.345, 56.785, 102.0, WaypointCategory.WATER, timestamp = Instant.ofEpochMilli(1500000))

        wal.appendPoint(pt1)
        wal.appendWaypoint(wpt)
        wal.appendPoint(pt2)
        wal.close()

        val recovered = RecordingWal.recover(file)
        assertEquals(2, recovered.points.size)
        assertEquals(1, recovered.waypoints.size)

        assertEquals(pt1.latitude, recovered.points[0].latitude, 0.0001)
        assertEquals(pt2.latitude, recovered.points[1].latitude, 0.0001)
        assertEquals("Fresh Spring", recovered.waypoints[0].name)
        assertEquals(WaypointCategory.WATER, recovered.waypoints[0].category)
    }

    @Test
    fun testCorruptedLineIsSafelyDropped() {
        val file = File(tempFolder.root, "corrupted.wal")
        val wal = RecordingWal.create(file)
        wal.appendPoint(TrackPoint(10.0, 20.0, 50.0, 2.0, 3.0))
        wal.close()

        // Append corrupted line with bad CRC
        file.appendText("123456,10.1,20.1,52.0,2.1,3.2*99999999\n")

        val recovered = RecordingWal.recover(file)
        // Corrupted line should fail CRC and be safely dropped
        assertEquals(1, recovered.points.size)
    }
}
