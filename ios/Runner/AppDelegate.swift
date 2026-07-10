import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  
  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    let controlChannel = FlutterMethodChannel(
      name: "org.opensource.tracker/control",
      binaryMessenger: controller.binaryMessenger
    )
    let telemetryChannel = FlutterEventChannel(
      name: "org.opensource.tracker/telemetry",
      binaryMessenger: controller.binaryMessenger
    )
    
    controlChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      
      switch call.method {
      case "startTracking":
        guard let args = call.arguments as? [String: Any],
              let sessionId = args["sessionId"] as? Int,
              let targetDurationSeconds = args["targetDurationSeconds"] as? Int,
              let safetyBufferPct = args["safetyBufferPct"] as? Double,
              let gpsIntervalMs = args["gpsIntervalMs"] as? Int else {
          result(FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Missing target arguments for telemetry startup",
            details: nil
          ))
          return
        }
        
        LocationService.shared.startTracking(
          sessionId: sessionId,
          targetDurationSeconds: targetDurationSeconds,
          safetyBufferPct: safetyBufferPct,
          gpsIntervalMs: gpsIntervalMs
        )
        result(true)
        
      case "stopTracking":
        LocationService.shared.stopTracking()
        result(true)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    telemetryChannel.setStreamHandler(self)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

extension AppDelegate: FlutterStreamHandler {
    func onListen(arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        
        LocationService.telemetryListener = { [weak self] lat, lng, alt, acc, speed, timestamp in
            guard let self = self else { return }
            // Dispatch back to main UI thread to prevent synchronization issues in Flutter
            DispatchQueue.main.async {
                self.eventSink?([
                    "lat": lat,
                    "lng": lng,
                    "altitude": alt,
                    "accuracy": acc,
                    "speed": speed,
                    "timestamp": Int64(timestamp)
                ])
            }
        }
        return nil
    }
    
    func onCancel(arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        LocationService.telemetryListener = nil
        return nil
    }
}
