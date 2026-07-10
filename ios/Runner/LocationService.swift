import Foundation
import CoreLocation

class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    
    // Direct in-memory event stream hook to AppDelegate (swift)
    static var telemetryListener: ((Double, Double, Double, Double, Double, Double) -> Void)?

    private let locationManager = CLLocationManager()
    private let kalmanFilter = KalmanFilter()
    
    private var sessionId: Int = -1
    private var isTracking = false
    
    // iOS 17+ background session tracker
    private var backgroundSession: Any?

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func startTracking(
        sessionId: Int,
        targetDurationSeconds: Int,
        safetyBufferPct: Double,
        gpsIntervalMs: Int
    ) {
        self.sessionId = sessionId
        self.isTracking = true
        
        kalmanFilter.reset()

        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        if #available(iOS 17.0, *) {
            // Keeps location tracking active even if the user closes/suspends the foreground app
            self.backgroundSession = CLBackgroundActivitySession()
        }

        locationManager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        if #available(iOS 17.0, *) {
            if let session = backgroundSession as? CLBackgroundActivitySession {
                session.invalidate()
            }
            self.backgroundSession = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking, let location = locations.last else { return }

        // Sanity check: ignore points with negative accuracy or extreme GPS jitter (> 50m accuracy)
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 50 {
            return
        }

        let timestampMs = location.timestamp.timeIntervalSince1970 * 1000.0

        // Kalman coordinate smoothing
        let (filteredLat, filteredLng) = kalmanFilter.filter(
            measuredLat: location.coordinate.latitude,
            measuredLng: location.coordinate.longitude,
            measuredAccuracyMeters: location.horizontalAccuracy,
            timestampMs: timestampMs
        )

        // Native SQL persistence (safe checkpointing)
        _ = DatabaseHelper.shared.insertPoint(
            sessionId: sessionId,
            timestamp: Int64(timestampMs),
            lat: filteredLat,
            lng: filteredLng,
            altitude: location.altitude,
            accuracy: location.horizontalAccuracy,
            speed: location.speed
        )

        // Forward to the Flutter UI event sink
        LocationService.telemetryListener?(
            filteredLat,
            filteredLng,
            location.altitude,
            location.horizontalAccuracy,
            location.speed,
            timestampMs
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("TurnBack GPS: iOS CoreLocation failed: \(error.localizedDescription)")
    }
}
