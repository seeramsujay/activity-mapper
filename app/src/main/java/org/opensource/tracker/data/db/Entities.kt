package org.opensource.tracker.data.db

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "tracks")
data class TrackEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0L,
    val title: String,
    val activityType: String = "RUN",
    val startTime: Long,
    val endTime: Long? = null,
    val targetDurationSeconds: Long = 3600L,
    val safetyBufferPercent: Double = 15.0,
    val turnBackTriggeredAt: Long? = null,
    val distanceKm: Double = 0.0,
    val movingDurationSeconds: Long = 0L,
    val totalDurationSeconds: Long = 0L,
    val avgSpeedKmh: Double = 0.0,
    val maxSpeedKmh: Double = 0.0,
    val elevationGainMeters: Double = 0.0,
    val elevationLossMeters: Double = 0.0,
    val gpxFilePath: String? = null
)

@Entity(
    tableName = "waypoints",
    foreignKeys = [
        ForeignKey(
            entity = TrackEntity::class,
            parentColumns = ["id"],
            childColumns = ["trackId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["trackId"])]
)
data class WaypointEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0L,
    val trackId: Long,
    val name: String,
    val description: String = "",
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double = 0.0,
    val category: String = "NOTE",
    val timestamp: Long
)
