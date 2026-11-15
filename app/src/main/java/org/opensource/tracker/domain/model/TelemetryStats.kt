package org.opensource.tracker.domain.model

import java.time.Duration

enum class ActivityType(val displayName: String, val iconName: String) {
    RUN("Running", "directions_run"),
    HIKE("Hiking", "hiking"),
    CYCLE("Cycling", "directions_bike"),
    WALK("Walking", "directions_walk")
}

data class SplitLap(
    val lapNumber: Int,
    val distanceKm: Double,
    val duration: Duration,
    val avgSpeedKmh: Double,
    val paceMinKm: String,
    val elevationGainM: Double = 0.0,
    val elevationLossM: Double = 0.0
)

data class TelemetryStats(
    val distanceKm: Double = 0.0,
    val totalDuration: Duration = Duration.ZERO,
    val movingDuration: Duration = Duration.ZERO,
    val stoppedDuration: Duration = Duration.ZERO,
    val avgSpeedKmh: Double = 0.0,
    val maxSpeedKmh: Double = 0.0,
    val avgPaceMinKm: String = "--:--",
    val bestPaceMinKm: String = "--:--",
    val elevationGainM: Double = 0.0,
    val elevationLossM: Double = 0.0,
    val minAltitudeM: Double = 0.0,
    val maxAltitudeM: Double = 0.0,
    val splits: List<SplitLap> = emptyList(),
    val totalTrackpoints: Int = 0
)
