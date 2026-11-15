package org.opensource.tracker.domain.model

import java.time.Instant

/**
 * Immutable GPS point recorded during an activity.
 *
 * @property latitude WGS84 latitude in degrees [-90.0, 90.0]
 * @property longitude WGS84 longitude in degrees [-180.0, 180.0]
 * @property altitudeMeters MSL altitude in meters
 * @property speedMps Speed in meters per second
 * @property accuracyMeters Estimated 68% horizontal accuracy radius in meters
 * @property bearingDegrees Direction of movement in degrees [0.0, 360.0)
 * @property timestamp Capture timestamp
 */
data class TrackPoint(
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double = 0.0,
    val speedMps: Double = 0.0,
    val accuracyMeters: Double = 0.0,
    val bearingDegrees: Float = 0f,
    val timestamp: Instant = Instant.now(),
) {
    val speedKmh: Double get() = speedMps * 3.6
}
