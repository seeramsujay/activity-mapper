package org.opensource.tracker.ui.util

import java.util.Locale

/** Metric/imperial display helpers. All stored values stay metric; only presentation converts. */
object UnitFormat {
    const val KM_PER_MILE = 1.609344
    const val FEET_PER_METER = 3.28084

    fun distanceValue(
        km: Double,
        imperial: Boolean,
    ): Double = if (imperial) km / KM_PER_MILE else km

    fun distanceUnit(imperial: Boolean): String = if (imperial) "mi" else "km"

    fun distance(
        km: Double,
        imperial: Boolean,
    ): String = String.format(Locale.US, "%.2f %s", distanceValue(km, imperial), distanceUnit(imperial))

    fun speedValue(
        kmh: Double,
        imperial: Boolean,
    ): Double = if (imperial) kmh / KM_PER_MILE else kmh

    fun speedUnit(imperial: Boolean): String = if (imperial) "mph" else "km/h"

    fun speed(
        kmh: Double,
        imperial: Boolean,
    ): String = String.format(Locale.US, "%.1f %s", speedValue(kmh, imperial), speedUnit(imperial))

    fun elevationValue(
        meters: Double,
        imperial: Boolean,
    ): Double = if (imperial) meters * FEET_PER_METER else meters

    fun elevationUnit(imperial: Boolean): String = if (imperial) "ft" else "m"

    fun elevation(
        meters: Double,
        imperial: Boolean,
    ): String = String.format(Locale.US, "+%.0f %s", elevationValue(meters, imperial), elevationUnit(imperial))

    fun paceUnit(imperial: Boolean): String = if (imperial) "/mi" else "/km"

    /** Converts a "mm:ss" per-km pace string to the requested unit; passes through placeholders like "--:--". */
    fun pace(
        paceMinKm: String,
        imperial: Boolean,
    ): String {
        if (!imperial) return paceMinKm
        val parts = paceMinKm.split(":")
        if (parts.size != 2) return paceMinKm
        val minutes = parts[0].toIntOrNull() ?: return paceMinKm
        val seconds = parts[1].toIntOrNull() ?: return paceMinKm
        val perMile = ((minutes * 60 + seconds) * KM_PER_MILE).toInt()
        return String.format(Locale.US, "%d:%02d", perMile / 60, perMile % 60)
    }
}
