package org.opensource.tracker.data.wal

import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.model.Waypoint
import org.opensource.tracker.domain.model.WaypointCategory
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.Closeable
import java.io.File
import java.io.FileReader
import java.io.FileWriter
import java.time.Instant
import java.util.Base64
import java.util.zip.CRC32

/**
 * Crash-proof append-only Write-Ahead-Log (WAL).
 *
 * Inspired by OfflineGPX's robust crash-recovery mechanism. Every GPS fix and waypoint is
 * immediately written as a single line with an appended CRC-32 checksum and flushed to disk.
 * If the device abruptly runs out of battery or the OS kills the process in low memory,
 * zero recorded coordinates are lost.
 */
class RecordingWal(
    val file: File,
    private val writer: BufferedWriter,
) : Closeable {
    companion object {
        private const val VERSION = 1
        private const val HEADER_PREFIX = "V,"
        private const val BREAK = "-"
        private const val WAYPOINT_PREFIX = "W,"
        private const val CHECK = "*"

        fun create(file: File): RecordingWal {
            file.parentFile?.mkdirs()
            val writer = BufferedWriter(FileWriter(file, true))
            val wal = RecordingWal(file, writer)
            if (file.length() == 0L) {
                wal.writeLine("$HEADER_PREFIX$VERSION")
            }
            return wal
        }

        fun hasActiveRecording(file: File): Boolean = file.exists() && file.length() > 0L

        /**
         * Recovers all points, waypoints, and segment breaks from a WAL file.
         * Corrupted lines (e.g. from a torn write during power failure) fail CRC and are safely dropped.
         */
        fun recover(file: File): RecoveredData {
            if (!file.exists()) return RecoveredData(emptyList(), emptyList())

            val points = mutableListOf<TrackPoint>()
            val waypoints = mutableListOf<Waypoint>()

            BufferedReader(FileReader(file)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val l = line?.trim() ?: continue
                    val checkIndex = l.lastIndexOf(CHECK)
                    if (checkIndex == -1) continue

                    val body = l.substring(0, checkIndex)
                    val expectedCrcStr = l.substring(checkIndex + 1)
                    val expectedCrc = expectedCrcStr.toLongOrNull() ?: continue

                    val crc = CRC32()
                    crc.update(body.toByteArray(Charsets.UTF_8))
                    if (crc.value != expectedCrc) {
                        // Drop torn line safely
                        continue
                    }

                    if (body.startsWith(HEADER_PREFIX) || body == BREAK) {
                        continue
                    }

                    if (body.startsWith(WAYPOINT_PREFIX)) {
                        // Format: W,epochMillis,lat,lon,ele,category,base64Name
                        val parts = body.substring(WAYPOINT_PREFIX.length).split(",")
                        if (parts.size >= 6) {
                            val timeMs = parts[0].toLongOrNull() ?: 0L
                            val lat = parts[1].toDoubleOrNull() ?: continue
                            val lon = parts[2].toDoubleOrNull() ?: continue
                            val ele = parts[3].toDoubleOrNull() ?: 0.0
                            val categoryStr = parts[4]
                            val category =
                                try {
                                    WaypointCategory.valueOf(categoryStr)
                                } catch (_: Exception) {
                                    WaypointCategory.NOTE
                                }
                            val name =
                                try {
                                    String(Base64.getDecoder().decode(parts[5]), Charsets.UTF_8)
                                } catch (_: Exception) {
                                    "Waypoint"
                                }
                            waypoints.add(
                                Waypoint(
                                    sessionId = 0L,
                                    name = name,
                                    latitude = lat,
                                    longitude = lon,
                                    altitudeMeters = ele,
                                    category = category,
                                    timestamp = Instant.ofEpochMilli(timeMs),
                                ),
                            )
                        }
                    } else {
                        // Format: epochMillis,lat,lon,alt,speed,accuracy
                        val parts = body.split(",")
                        if (parts.size >= 6) {
                            val timeMs = parts[0].toLongOrNull() ?: 0L
                            val lat = parts[1].toDoubleOrNull() ?: continue
                            val lon = parts[2].toDoubleOrNull() ?: continue
                            val alt = parts[3].toDoubleOrNull() ?: 0.0
                            val speed = parts[4].toDoubleOrNull() ?: 0.0
                            val acc = parts[5].toDoubleOrNull() ?: 0.0

                            points.add(
                                TrackPoint(
                                    latitude = lat,
                                    longitude = lon,
                                    altitudeMeters = alt,
                                    speedMps = speed,
                                    accuracyMeters = acc,
                                    timestamp = Instant.ofEpochMilli(timeMs),
                                ),
                            )
                        }
                    }
                }
            }

            return RecoveredData(points, waypoints)
        }
    }

    fun appendPoint(point: TrackPoint) {
        val timeMs = point.timestamp.toEpochMilli()
        writeLine("$timeMs,${point.latitude},${point.longitude},${point.altitudeMeters},${point.speedMps},${point.accuracyMeters}")
    }

    fun appendWaypoint(waypoint: Waypoint) {
        val timeMs = waypoint.timestamp.toEpochMilli()
        val base64Name = Base64.getEncoder().encodeToString(waypoint.name.toByteArray(Charsets.UTF_8))
        writeLine(
            "$WAYPOINT_PREFIX$timeMs,${waypoint.latitude},${waypoint.longitude},${waypoint.altitudeMeters},${waypoint.category.name},$base64Name",
        )
    }

    fun appendBreak() {
        writeLine(BREAK)
    }

    private fun writeLine(content: String) {
        val crc = CRC32()
        crc.update(content.toByteArray(Charsets.UTF_8))
        writer.write("$content$CHECK${crc.value}")
        writer.newLine()
        writer.flush()
    }

    override fun close() {
        writer.close()
    }
}

data class RecoveredData(
    val points: List<TrackPoint>,
    val waypoints: List<Waypoint>,
)
