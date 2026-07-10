import 'package:flutter/services.dart';

class PlatformService {
  static final PlatformService instance = PlatformService._init();

  static const MethodChannel _controlChannel = MethodChannel('org.opensource.tracker/control');
  static const EventChannel _telemetryChannel = EventChannel('org.opensource.tracker/telemetry');

  PlatformService._init();

  Stream<dynamic>? _telemetryStream;

  // Control tracking service
  Future<bool> startTracking({
    required int sessionId,
    required String activityType,
    required int targetDurationSeconds,
    required double safetyBufferPct,
    required int gpsIntervalMs,
  }) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('startTracking', {
        'sessionId': sessionId,
        'activityType': activityType,
        'targetDurationSeconds': targetDurationSeconds,
        'safetyBufferPct': safetyBufferPct,
        'gpsIntervalMs': gpsIntervalMs,
      });
      return success ?? false;
    } on PlatformException catch (e) {
      print("Failed to start tracking service: ${e.message}");
      return false;
    }
  }

  Future<bool> stopTracking() async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('stopTracking');
      return success ?? false;
    } on PlatformException catch (e) {
      print("Failed to stop tracking service: ${e.message}");
      return false;
    }
  }

  // Telemetry stream from native service
  Stream<dynamic> get telemetryStream {
    _telemetryStream ??= _telemetryChannel.receiveBroadcastStream();
    return _telemetryStream!;
  }
}
