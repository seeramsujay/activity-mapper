import Foundation

/// Metric 2D Kalman Filter for GNSS / GPS tracking.
/// Operates in local metric coordinates to prevent angular scaling collapse.
class KalmanFilter {
    private var defaultProcessNoiseQ: Double
    private var isInitialized = false
    private var lat = 0.0
    private var lng = 0.0
    private var varianceP = 25.0 // Estimation variance in meters^2
    private var lastTimeStamp: Double = 0

    init(processNoiseQ: Double = 3.0) {
        self.defaultProcessNoiseQ = processNoiseQ
    }

    func filter(
        measuredLat: Double,
        measuredLng: Double,
        measuredAccuracyMeters: Double,
        timestampMs: Double,
        speedMetersPerSec: Double = 0.0
    ) -> (Double, Double) {
        let safeAccuracy = max(1.0, measuredAccuracyMeters)

        if !isInitialized {
            lat = measuredLat
            lng = measuredLng
            varianceP = safeAccuracy * safeAccuracy
            lastTimeStamp = timestampMs
            isInitialized = true
            return (lat, lng)
        }

        var dt = (timestampMs - lastTimeStamp) / 1000.0
        if dt < 0.0 { dt = 0.0 }
        if dt > 10.0 { dt = 10.0 } // Clamp to avoid huge covariance leaps

        // 1. Physical process noise scaled by movement dynamics (m^2 / s)
        let speedFactor = max(1.0, speedMetersPerSec * 1.5)
        let processNoise = (defaultProcessNoiseQ * speedFactor) * max(dt, 0.5)

        // Predict covariance (meters^2)
        varianceP += processNoise

        // 2. Metric distance between measurement and estimate
        let latRad = measuredLat * .pi / 180.0
        let metersPerLat = 111320.0
        let metersPerLng = 111320.0 * max(0.1, cos(latRad))

        let dLatMeters = (measuredLat - lat) * metersPerLat
        let dLngMeters = (measuredLng - lng) * metersPerLng
        let distMeters = (dLatMeters * dLatMeters + dLngMeters * dLngMeters).squareRoot()

        // 3. Measurement noise covariance R (meters^2)
        let measurementNoiseR = safeAccuracy * safeAccuracy

        // 4. Kalman Gain calculation K in [0, 1]
        var kalmanGainK = varianceP / (varianceP + measurementNoiseR)

        // If movement exceeds twice the measurement accuracy, the device turned or accelerated;
        // boost Kalman gain so the filter never lags behind the physical runner/vehicle
        if distMeters > safeAccuracy * 1.5 {
            kalmanGainK = max(kalmanGainK, 0.50)
        }

        // Clamp gain between 0.15 (smooth drift rejection) and 0.95 (rapid responsiveness)
        kalmanGainK = min(0.95, max(0.15, kalmanGainK))

        // 5. Update state estimate
        lat += kalmanGainK * (measuredLat - lat)
        lng += kalmanGainK * (measuredLng - lng)

        // 6. Update estimation covariance
        varianceP *= (1.0 - kalmanGainK)
        lastTimeStamp = timestampMs

        return (lat, lng)
    }

    func reset() {
        isInitialized = false
        varianceP = 25.0
        lat = 0.0
        lng = 0.0
        lastTimeStamp = 0
    }
}
