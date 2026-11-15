package org.opensource.tracker.domain.model

import java.time.Instant

/**
 * Standard outdoor waypoint categories inspired by OsmAnd & Garmin.
 */
enum class WaypointCategory(val displayName: String, val gpxSymbol: String) {
    WATER("Water Source", "Water Source"),
    VIEWPOINT("Viewpoint / Summit", "Scenic Area"),
    CAMP("Campsite / Shelter", "Campground"),
    HAZARD("Hazard / Obstacle", "Danger Area"),
    NOTE("General Note", "Waypoint")
}

/**
 * Custom POI or landmark pinned during recording or imported from GPX.
 */
data class Waypoint(
    val id: Long = 0L,
    val sessionId: Long,
    val name: String,
    val description: String = "",
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double = 0.0,
    val category: WaypointCategory = WaypointCategory.NOTE,
    val timestamp: Instant = Instant.now()
)
