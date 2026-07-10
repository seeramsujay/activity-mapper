import Foundation

class KalmanFilter {
    private var processNoiseQ: Double
    private var isInitialized = false
    private var lat = 0.0
    private var lng = 0.0
    private var varianceP = 1.0
    private var lastTimeStamp: Double = 0

    init(processNoiseQ: Double = 0.00005) {
        self.processNoiseQ = processNoiseQ
    }

    func filter(
        measuredLat: Double,
        measuredLng: Double,
        measuredAccuracyMeters: Double,
        timestampMs: Double
    ) -> (Double, Double) {
        if !isInitialized {
            lat = measuredLat
            lng = measuredLng
            varianceP = measuredAccuracyMeters * measuredAccuracyMeters
            lastTimeStamp = timestampMs
            isInitialized = true
            return (lat, lng)
        }

        let dt = (timestampMs - lastTimeStamp) / 1000.0
        
        // 1. Predict covariance
        varianceP += processNoiseQ * dt

        // 2. Kalman Gain calculation
        let measurementNoiseR = measuredAccuracyMeters * measuredAccuracyMeters
        let kalmanGainK = varianceP / (varianceP + measurementNoiseR)

        // 3. Update estimate
        lat += kalmanGainK * (measuredLat - lat)
        lng += kalmanGainK * (measuredLng - lng)

        // 4. Update covariance
        varianceP *= (1.0 - kalmanGainK)
        lastTimeStamp = timestampMs

        return (lat, lng)
    }

    func reset() {
        isInitialized = false
    }
}
