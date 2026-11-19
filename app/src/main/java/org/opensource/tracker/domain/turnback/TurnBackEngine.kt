package org.opensource.tracker.domain.turnback

import org.opensource.tracker.domain.model.SplitLap
import org.opensource.tracker.domain.model.TelemetryStats
import org.opensource.tracker.domain.model.TrackPoint
import java.time.Duration
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * TurnBack Core Physics & Pacing Engine.
 *
 * Implements non-linear endurance fatigue compensation, out-and-back timing thresholds,
 * elevation gain hysteresis filtering, sequential 1-km/1-mi lap split calculations,
 * and fastest/slowest split identification.
 */
object TurnBackEngine {
    /**
     * Calculates optimal outbound duration before turning back.
     *
     * T_outbound = T_target / (1 + (1 + beta) * safetyFactor)
     *
     * @param targetDuration Total scheduled duration for the out-and-back session
     * @param beta Fatigue factor (0.00 to 0.35, default 0.12)
     * @param safetyBufferPercent Headwind / safety buffer reserve (default 15.0%)
     */
    fun computeOutboundLimit(
        targetDuration: Duration,
        beta: Double = 0.12,
        safetyBufferPercent: Double = 15.0,
    ): Duration {
        val targetSeconds = targetDuration.seconds.toDouble()
        if (targetSeconds <= 0.0) return Duration.ZERO

        val safetyMultiplier = 1.0 + (safetyBufferPercent / 100.0)
        val denom = 1.0 + (1.0 + beta) * safetyMultiplier
        val outboundSeconds = (targetSeconds / denom).toLong()

        return Duration.ofSeconds(outboundSeconds.coerceAtLeast(1L))
    }

    /**
     * Calculates planimetric Haversine distance in meters between two coordinates.
     */
    fun haversineDistanceMeters(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double,
    ): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val rLat1 = Math.toRadians(lat1)
        val rLat2 = Math.toRadians(lat2)

        val a =
            sin(dLat / 2) * sin(dLat / 2) +
                cos(rLat1) * cos(rLat2) * sin(dLon / 2) * sin(dLon / 2)
        val c = 2 * asin(sqrt(a.coerceIn(0.0, 1.0)))

        return 6371000.0 * c
    }

    /**
     * Formats speed in m/s into running pace string "mm:ss".
     */
    fun formatPaceFromMps(mps: Double): String {
        if (mps <= 0.3) return "--:--"
        val secPerKm = (1000.0 / mps).toInt()
        val min = secPerKm / 60
        val sec = secPerKm % 60
        if (min > 99) return "--:--"
        return String.format("%d:%02d", min, sec)
    }

    /**
     * Computes comprehensive telemetry statistics and lap splits from recorded trackpoints.
     */
    fun computeStats(
        points: List<TrackPoint>,
        totalDuration: Duration = Duration.ZERO,
    ): TelemetryStats {
        if (points.isEmpty()) return TelemetryStats(totalDuration = totalDuration)

        var totalDistM = 0.0
        var movingSeconds = 0.0
        var maxSpeedMps = 0.0
        var minAlt = Double.MAX_VALUE
        var maxAlt = -Double.MAX_VALUE

        // 3m elevation hysteresis accumulator (avoids GPS altitude noise)
        var referenceAlt = Double.NaN
        var gainM = 0.0
        var lossM = 0.0
        val thresholdM = 3.0

        for (i in points.indices) {
            val curr = points[i]
            val alt = curr.altitudeMeters

            if (alt < minAlt) minAlt = alt
            if (alt > maxAlt) maxAlt = alt
            if (curr.speedMps > maxSpeedMps) maxSpeedMps = curr.speedMps

            if (referenceAlt.isNaN()) {
                referenceAlt = alt
            } else {
                val deltaAlt = alt - referenceAlt
                if (deltaAlt >= thresholdM) {
                    gainM += deltaAlt
                    referenceAlt = alt
                } else if (deltaAlt <= -thresholdM) {
                    lossM += -deltaAlt
                    referenceAlt = alt
                }
            }

            // A new segment starts a disconnected span: never count the gap from the previous segment's end.
            if (i > 0 && !curr.newSegment) {
                val prev = points[i - 1]
                val d =
                    haversineDistanceMeters(
                        prev.latitude,
                        prev.longitude,
                        curr.latitude,
                        curr.longitude,
                    )
                totalDistM += d

                val dt = Duration.between(prev.timestamp, curr.timestamp).seconds.coerceAtLeast(0)
                if (curr.speedMps >= 0.5) {
                    movingSeconds += dt
                }
            }
        }

        val totalDistKm = totalDistM / 1000.0
        val movingDuration = Duration.ofSeconds(movingSeconds.toLong())
        val effectiveTotalDuration =
            if (totalDuration.isZero && points.size >= 2) {
                Duration.between(points.first().timestamp, points.last().timestamp)
            } else {
                totalDuration
            }

        val stoppedSeconds = (effectiveTotalDuration.seconds - movingSeconds).coerceAtLeast(0.0)
        val stoppedDuration = Duration.ofSeconds(stoppedSeconds.toLong())

        val avgSpeedKmh =
            if (movingSeconds > 0) {
                (totalDistKm / (movingSeconds / 3600.0))
            } else {
                0.0
            }

        val avgMps = if (movingSeconds > 0) totalDistM / movingSeconds else 0.0
        val splits = computeSplits(points)
        val fastestSplit = splits.firstOrNull { it.isFastest }
        val slowestSplit = splits.firstOrNull { it.isSlowest }

        return TelemetryStats(
            distanceKm = totalDistKm,
            totalDuration = effectiveTotalDuration,
            movingDuration = movingDuration,
            stoppedDuration = stoppedDuration,
            avgSpeedKmh = avgSpeedKmh,
            maxSpeedKmh = maxSpeedMps * 3.6,
            avgPaceMinKm = formatPaceFromMps(avgMps),
            bestPaceMinKm = formatPaceFromMps(maxSpeedMps),
            elevationGainM = gainM,
            elevationLossM = lossM,
            minAltitudeM = if (minAlt == Double.MAX_VALUE) 0.0 else minAlt,
            maxAltitudeM = if (maxAlt == -Double.MAX_VALUE) 0.0 else maxAlt,
            splits = splits,
            totalTrackpoints = points.size,
            fastestSplit = fastestSplit,
            slowestSplit = slowestSplit,
        )
    }

    /**
     * Divides trackpoints into sequential 1-km distance split laps and marks fastest/slowest.
     */
    fun computeSplits(
        points: List<TrackPoint>,
        splitIntervalKm: Double = 1.0,
    ): List<SplitLap> {
        if (points.size < 2 || splitIntervalKm <= 0.0) return emptyList()

        val splits = mutableListOf<SplitLap>()
        var currentLapNumber = 1
        var currentLapDistM = 0.0
        var currentLapDurationSec = 0.0
        var currentLapGain = 0.0
        var currentLapLoss = 0.0
        val targetSplitM = splitIntervalKm * 1000.0

        for (i in 1 until points.size) {
            val prev = points[i - 1]
            val curr = points[i]
            if (curr.newSegment) continue // don't bridge disconnected GPX segments

            var segDist =
                haversineDistanceMeters(
                    prev.latitude,
                    prev.longitude,
                    curr.latitude,
                    curr.longitude,
                )
            var segDt = Duration.between(prev.timestamp, curr.timestamp).toMillis() / 1000.0
            val dAlt = curr.altitudeMeters - prev.altitudeMeters

            while (segDist > 0 && (currentLapDistM + segDist) >= targetSplitM) {
                val needed = targetSplitM - currentLapDistM
                val ratio = if (segDist > 0) (needed / segDist).coerceIn(0.0, 1.0) else 1.0
                val dtPart = segDt * ratio

                currentLapDistM += needed
                currentLapDurationSec += dtPart
                if (dAlt > 0) {
                    currentLapGain += dAlt * ratio
                } else if (dAlt < 0) {
                    currentLapLoss += (-dAlt) * ratio
                }

                val dur = Duration.ofSeconds(currentLapDurationSec.toLong())
                val durHours = currentLapDurationSec / 3600.0
                val speedKmh = if (durHours > 0) (currentLapDistM / 1000.0) / durHours else 0.0
                val paceMps = if (currentLapDurationSec > 0) currentLapDistM / currentLapDurationSec else 0.0

                splits.add(
                    SplitLap(
                        lapNumber = currentLapNumber++,
                        distanceKm = currentLapDistM / 1000.0,
                        duration = dur,
                        avgSpeedKmh = speedKmh,
                        paceMinKm = formatPaceFromMps(paceMps),
                        elevationGainM = currentLapGain,
                        elevationLossM = currentLapLoss,
                    ),
                )

                segDist -= needed
                segDt -= dtPart
                currentLapDistM = 0.0
                currentLapDurationSec = 0.0
                currentLapGain = 0.0
                currentLapLoss = 0.0
            }

            if (segDist > 0) {
                currentLapDistM += segDist
                currentLapDurationSec += segDt
                if (dAlt > 0) {
                    currentLapGain += dAlt
                } else if (dAlt < 0) {
                    currentLapLoss += (-dAlt)
                }
            }
        }

        // Add remaining segment if > 50 meters
        if (currentLapDistM >= 50.0) {
            val dur = Duration.ofSeconds(currentLapDurationSec.toLong())
            val durHours = currentLapDurationSec / 3600.0
            val speedKmh = if (durHours > 0) (currentLapDistM / 1000.0) / durHours else 0.0
            val paceMps = if (currentLapDurationSec > 0) currentLapDistM / currentLapDurationSec else 0.0

            splits.add(
                SplitLap(
                    lapNumber = currentLapNumber,
                    distanceKm = currentLapDistM / 1000.0,
                    duration = dur,
                    avgSpeedKmh = speedKmh,
                    paceMinKm = formatPaceFromMps(paceMps),
                    elevationGainM = currentLapGain,
                    elevationLossM = currentLapLoss,
                ),
            )
        }

        if (splits.isEmpty()) return emptyList()

        // Identify fastest and slowest completed splits (filter >= 0.8 km to prevent tiny final partials from winning)
        val fullSplits = splits.filter { it.distanceKm >= 0.8 }
        val candidates = if (fullSplits.isNotEmpty()) fullSplits else splits

        val fastest = candidates.maxByOrNull { it.avgSpeedKmh }
        val slowest = if (candidates.size > 1) candidates.minByOrNull { it.avgSpeedKmh } else null

        return splits.map { s ->
            s.copy(
                isFastest = fastest != null && s.lapNumber == fastest.lapNumber,
                isSlowest = slowest != null && s.lapNumber == slowest.lapNumber,
            )
        }
    }
}
