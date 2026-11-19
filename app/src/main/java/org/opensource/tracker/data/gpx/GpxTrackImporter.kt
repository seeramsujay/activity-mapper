package org.opensource.tracker.data.gpx

import android.content.Context
import android.net.Uri
import androidx.room.withTransaction
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.opensource.tracker.data.db.AppDatabase
import org.opensource.tracker.data.db.TrackEntity
import org.opensource.tracker.data.db.WaypointEntity
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.turnback.TurnBackEngine
import java.io.File
import java.time.Duration

/** Brings a `.gpx` file (from a file picker or an "open with" intent) into the track library. */
object GpxTrackImporter {
    /**
     * Fails with a user-presentable message if timestamps ever go backwards. Equal timestamps are fine
     * (untimed routes parse with identical times).
     */
    internal fun validateTimestamps(points: List<TrackPoint>): String? {
        for (i in 1 until points.size) {
            if (points[i].timestamp.isBefore(points[i - 1].timestamp)) {
                return "This GPX file's timestamps are out of order, so it can't be imported reliably."
            }
        }
        return null
    }

    /**
     * Many GPX files carry only coordinates and times. When *no* point has a speed we derive one per point from
     * distance over positive elapsed time; if any point has an explicit speed the file is left untouched.
     * Without this, moving time, average and maximum speed would all come out as zero.
     */
    internal fun normalizeSpeeds(points: List<TrackPoint>): List<TrackPoint> {
        if (points.none { it.speedMps <= 0.0 }) return points
        if (points.any { it.speedMps > 0.0 }) return points
        return points.mapIndexed { index, point ->
            if (index == 0 || point.newSegment) {
                point
            } else {
                val previous = points[index - 1]
                val seconds = Duration.between(previous.timestamp, point.timestamp).toMillis() / 1000.0
                if (seconds <= 0.0) {
                    point
                } else {
                    val meters =
                        TurnBackEngine.haversineDistanceMeters(
                            previous.latitude,
                            previous.longitude,
                            point.latitude,
                            point.longitude,
                        )
                    point.copy(speedMps = meters / seconds)
                }
            }
        }
    }

    /** Returns the new track id, or a failure with a user-presentable message. */
    suspend fun import(
        context: Context,
        uri: Uri,
    ): Result<Long> =
        withContext(Dispatchers.IO) {
            runCatching {
                val parsed =
                    context.contentResolver.openInputStream(uri)?.use { GpxImporter.parse(it) }
                        ?: error("Couldn't open that file")
                require(parsed.points.size >= 2) { "No track found in this GPX file" }
                validateTimestamps(parsed.points)?.let { error(it) }

                // Use the normalized points for statistics AND export so the detail screen shows the same numbers.
                val points = normalizeSpeeds(parsed.points)
                val first = points.first().timestamp
                val last = points.last().timestamp
                val stats = TurnBackEngine.computeStats(points, Duration.between(first, last))
                val title = parsed.name.ifBlank { "Imported activity" }

                val gpxFile = File(context.filesDir, "tracks/imported_${System.currentTimeMillis()}.gpx")
                GpxExporter.exportToFile(
                    file = gpxFile,
                    trackName = title,
                    activityType = "RUN",
                    points = points,
                    waypoints = parsed.waypoints,
                )

                val db = AppDatabase.getInstance(context.applicationContext)
                try {
                    // One transaction: a failure leaves neither a half-imported track nor an orphaned file.
                    db.withTransaction {
                        val trackId =
                            db.trackDao().insertTrack(
                                TrackEntity(
                                    title = title,
                                    startTime = first.toEpochMilli(),
                                    endTime = last.toEpochMilli(),
                                    distanceKm = stats.distanceKm,
                                    movingDurationSeconds = stats.movingDuration.seconds,
                                    totalDurationSeconds = stats.totalDuration.seconds,
                                    avgSpeedKmh = stats.avgSpeedKmh,
                                    maxSpeedKmh = stats.maxSpeedKmh,
                                    elevationGainMeters = stats.elevationGainM,
                                    elevationLossMeters = stats.elevationLossM,
                                    gpxFilePath = gpxFile.absolutePath,
                                ),
                            )
                        db.waypointDao().insertWaypoints(
                            parsed.waypoints.map { w ->
                                WaypointEntity(
                                    trackId = trackId,
                                    name = w.name,
                                    description = w.description,
                                    latitude = w.latitude,
                                    longitude = w.longitude,
                                    altitudeMeters = w.altitudeMeters,
                                    category = w.category.name,
                                    timestamp = w.timestamp.toEpochMilli(),
                                )
                            },
                        )
                        trackId
                    }
                } catch (e: Exception) {
                    gpxFile.delete()
                    throw e
                }
            }
        }
}
