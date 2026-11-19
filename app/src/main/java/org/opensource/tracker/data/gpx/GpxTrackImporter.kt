package org.opensource.tracker.data.gpx

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.opensource.tracker.data.db.AppDatabase
import org.opensource.tracker.data.db.TrackEntity
import org.opensource.tracker.data.db.WaypointEntity
import org.opensource.tracker.domain.turnback.TurnBackEngine
import java.io.File
import java.time.Duration

/** Brings a `.gpx` file (from a file picker or an "open with" intent) into the track library. */
object GpxTrackImporter {
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

                val first = parsed.points.first().timestamp
                val last = parsed.points.last().timestamp
                val duration = Duration.between(first, last).let { if (it.isNegative) Duration.ZERO else it }
                val stats = TurnBackEngine.computeStats(parsed.points, duration)
                val title = parsed.name.ifBlank { "Imported activity" }

                val gpxFile = File(context.filesDir, "tracks/imported_${System.currentTimeMillis()}.gpx")
                GpxExporter.exportToFile(
                    file = gpxFile,
                    trackName = title,
                    activityType = "RUN",
                    points = parsed.points,
                    waypoints = parsed.waypoints,
                )

                val db = AppDatabase.getInstance(context.applicationContext)
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
        }
}
