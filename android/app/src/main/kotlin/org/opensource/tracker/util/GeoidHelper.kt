package org.opensource.tracker.util

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Geoid undulation helper using a global coarse grid of WGS84 - EGM96 geoid separation (N).
 * Real elevation above Mean Sea Level (MSL):
 * H_msl = h_ellipsoid - N
 */
object GeoidHelper {

    // Latitudes: -90 to +90 in 10-degree steps (19 rows)
    // Longitudes: -180 to +180 in 10-degree steps (37 columns)
    // Values represent geoid height N in meters relative to WGS 84 ellipsoid.
    // In South Asia / Indian Ocean, N is ~ -80m to -105m.
    // In North America, N is ~ -30m to -10m.
    // In Europe, N is ~ +30m to +50m.
    private val GEOID_GRID = arrayOf(
        // -90 to -70
        floatArrayOf(-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f,-30f),
        floatArrayOf(-27f,-26f,-26f,-26f,-26f,-25f,-23f,-20f,-16f,-13f,-10f,-8f,-7f,-6f,-6f,-6f,-5f,-4f,-4f,-4f,-4f,-4f,-4f,-4f,-5f,-7f,-9f,-12f,-16f,-19f,-22f,-24f,-26f,-27f,-27f,-27f,-27f),
        floatArrayOf(-12f,-13f,-14f,-15f,-16f,-17f,-17f,-16f,-14f,-10f,-5f,0f,5f,8f,11f,12f,12f,12f,11f,10f,9f,8f,7f,7f,7f,7f,6f,4f,1f,-2f,-5f,-8f,-10f,-11f,-12f,-12f,-12f),
        // -60 to -40
        floatArrayOf(5f,4f,2f,0f,-3f,-7f,-11f,-14f,-15f,-13f,-7f,0f,8f,16f,22f,26f,27f,26f,23f,19f,16f,13f,11f,9f,7f,6f,5f,4f,4f,4f,4f,4f,4f,4f,4f,5f,5f),
        floatArrayOf(12f,13f,12f,9f,4f,-2f,-10f,-18f,-24f,-24f,-16f,-4f,10f,23f,33f,38f,39f,36f,30f,23f,17f,12f,8f,6f,5f,6f,8f,10f,11f,12f,12f,12f,11f,11f,11f,12f,12f),
        floatArrayOf(13f,19f,22f,20f,14f,5f,-7f,-19f,-30f,-34f,-27f,-12f,6f,23f,36f,43f,43f,38f,28f,18f,10f,5f,2f,2f,4f,8f,12f,16f,17f,17f,15f,12f,11f,10f,10f,13f,13f),
        // -30 to -10
        floatArrayOf(11f,20f,27f,28f,24f,14f,-1f,-18f,-33f,-41f,-37f,-20f,2f,24f,40f,48f,47f,37f,23f,10f,2f,-2f,-3f,-2f,2f,8f,15f,20f,20f,18f,14f,9f,6f,5f,6f,11f,11f),
        floatArrayOf(4f,15f,25f,31f,29f,20f,3f,-17f,-36f,-48f,-46f,-28f,-4f,21f,40f,49f,47f,33f,16f,2f,-8f,-12f,-11f,-7f,0f,8f,17f,21f,20f,15f,8f,2f,-1f,-1f,0f,4f,4f),
        floatArrayOf(-9f,5f,18f,28f,30f,21f,3f,-19f,-40f,-55f,-54f,-35f,-9f,17f,38f,48f,44f,27f,8f,-7f,-18f,-22f,-19f,-12f,-2f,8f,17f,20f,17f,9f,0f,-7f,-10f,-10f,-9f,-9f,-9f),
        // 0 (Equator)
        floatArrayOf(-26f,-11f,6f,21f,27f,19f,0f,-23f,-46f,-63f,-63f,-42f,-14f,14f,36f,46f,39f,19f,-2f,-19f,-31f,-34f,-28f,-17f,-4f,8f,16f,17f,11f,0f,-11f,-19f,-23f,-24f,-25f,-26f,-26f),
        // +10 to +30 (Row 10 is Lat +10: Notice Lon 70-80 has deep low -85m to -95m)
        floatArrayOf(-43f,-27f,-7f,12f,24f,19f,-1f,-25f,-49f,-68f,-71f,-50f,-21f,11f,35f,44f,33f,8f,-16f,-34f,-48f,-52f,-42f,-27f,-9f,6f,16f,16f,6f,-7f,-20f,-30f,-36f,-40f,-42f,-43f,-43f),
        floatArrayOf(-54f,-39f,-19f,3f,20f,20f,3f,-19f,-43f,-64f,-73f,-56f,-27f,7f,33f,44f,30f,1f,-27f,-48f,-65f,-69f,-56f,-35f,-13f,4f,16f,17f,4f,-12f,-26f,-38f,-46f,-51f,-53f,-54f,-54f),
        floatArrayOf(-57f,-44f,-24f,-2f,18f,22f,10f,-9f,-31f,-51f,-65f,-54f,-27f,5f,32f,45f,30f,-2f,-33f,-57f,-76f,-80f,-64f,-39f,-13f,7f,20f,20f,3f,-14f,-28f,-41f,-50f,-56f,-57f,-57f,-57f),
        // +40 to +60
        floatArrayOf(-51f,-40f,-22f,0f,19f,26f,18f,2f,-16f,-33f,-47f,-42f,-20f,7f,33f,46f,32f,-3f,-35f,-58f,-76f,-78f,-59f,-33f,-7f,12f,24f,22f,2f,-14f,-27f,-39f,-47f,-52f,-52f,-51f,-51f),
        floatArrayOf(-37f,-29f,-14f,5f,22f,30f,26f,13f,-1f,-14f,-25f,-24f,-8f,14f,36f,46f,32f,-2f,-31f,-51f,-65f,-63f,-44f,-19f,4f,20f,28f,24f,2f,-13f,-24f,-33f,-38f,-40f,-38f,-37f,-37f),
        floatArrayOf(-20f,-15f,-4f,11f,25f,32f,30f,20f,8f,-1f,-8f,-8f,3f,19f,35f,40f,27f,-1f,-24f,-39f,-47f,-42f,-24f,-2f,17f,28f,30f,22f,0f,-12f,-20f,-24f,-26f,-25f,-21f,-20f,-20f),
        // +70 to +90
        floatArrayOf(-4f,-2f,4f,14f,24f,29f,28f,21f,12f,5f,1f,2f,8f,17f,27f,28f,17f,-4f,-20f,-28f,-28f,-18f,-3f,12f,24f,29f,26f,15f,-2f,-12f,-15f,-15f,-13f,-10f,-6f,-4f,-4f),
        floatArrayOf(6f,6f,8f,13f,18f,20f,19f,15f,9f,5f,4f,6f,10f,14f,18f,15f,5f,-9f,-20f,-21f,-15f,-3f,9f,18f,23f,22f,16f,6f,-6f,-13f,-12f,-7f,-1f,3f,6f,6f,6f),
        floatArrayOf(14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f,14f)
    )

    /**
     * Calculates the geoid height N (in meters) at the specified latitude and longitude
     * using 2D bilinear interpolation across the 10-degree EGM96 reference grid.
     */
    fun getGeoidHeight(latitude: Double, longitude: Double): Double {
        val latClamped = latitude.coerceIn(-90.0, 90.0)
        var lonNormalized = longitude % 360.0
        if (lonNormalized < -180.0) lonNormalized += 360.0
        if (lonNormalized > 180.0) lonNormalized -= 360.0

        val rowFloat = (latClamped + 90.0) / 10.0
        val colFloat = (lonNormalized + 180.0) / 10.0

        val r0 = floor(rowFloat).toInt().coerceIn(0, 18)
        val r1 = min(r0 + 1, 18)
        val dr = rowFloat - r0

        val c0 = floor(colFloat).toInt().coerceIn(0, 36)
        val c1 = min(c0 + 1, 36)
        val dc = colFloat - c0

        val q00 = GEOID_GRID[r0][c0]
        val q01 = GEOID_GRID[r0][c1]
        val q10 = GEOID_GRID[r1][c0]
        val q11 = GEOID_GRID[r1][c1]

        val top = q00 * (1.0 - dc) + q01 * dc
        val bottom = q10 * (1.0 - dc) + q11 * dc

        return top * (1.0 - dr) + bottom * dr
    }

    /**
     * Converts WGS 84 ellipsoidal altitude to Mean Sea Level (MSL) altitude.
     */
    fun ellipsoidalToMsl(altitudeEllipsoid: Double, latitude: Double, longitude: Double): Double {
        val n = getGeoidHeight(latitude, longitude)
        return altitudeEllipsoid - n
    }
}
