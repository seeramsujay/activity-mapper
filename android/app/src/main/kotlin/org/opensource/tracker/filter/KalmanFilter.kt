package org.opensource.tracker.filter

class KalmanFilter(private val processNoiseQ: Double = 0.00005) {
    private var isInitialized = false
    private var lat = 0.0
    private var lng = 0.0
    private var varianceP = 1.0 // Estimation variance
    private var lastTimeStamp: Long = 0

    fun filter(
        measuredLat: Double,
        measuredLng: Double,
        measuredAccuracyMeters: Double,
        timestampMs: Long
    ): Pair<Double, Double> {
        if (!isInitialized) {
            lat = measuredLat
            lng = measuredLng
            varianceP = measuredAccuracyMeters * measuredAccuracyMeters
            lastTimeStamp = timestampMs
            isInitialized = true
            return Pair(lat, lng)
        }

        val dt = (timestampMs - lastTimeStamp) / 1000.0
        
        // 1. Predict covariance
        varianceP += processNoiseQ * dt

        // 2. Calculate Kalman Gain
        val measurementNoiseR = measuredAccuracyMeters * measuredAccuracyMeters
        val kalmanGainK = varianceP / (varianceP + measurementNoiseR)

        // 3. Update estimate
        lat += kalmanGainK * (measuredLat - lat)
        lng += kalmanGainK * (measuredLng - lng)

        // 4. Update covariance
        varianceP *= (1.0 - kalmanGainK)
        lastTimeStamp = timestampMs

        return Pair(lat, lng)
    }

    fun reset() {
        isInitialized = false
    }
}
