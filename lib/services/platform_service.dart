import 'package:flutter/services.dart';

/// Platform channel coordinator that links Flutter with native code.
///
/// Communicates with Android Foreground Service or iOS Background Telemetry using
/// platform-specific MethodChannels and EventChannels.
class PlatformService {
  /// The singleton instance of [PlatformService].
  static final PlatformService instance = PlatformService._init();

  static const MethodChannel _controlChannel = MethodChannel('org.opensource.tracker/control');
  static const EventChannel _telemetryChannel = EventChannel('org.opensource.tracker/telemetry');

  PlatformService._init();

  Stream<dynamic>? _telemetryStream;

  /// Signals the native background tracking service to start polling GPS coordinates.
  ///
  /// Passes down session configurations like target durations, buffers, and gps polling intervals.
  /// Returns a boolean indicating if the service was spawned successfully.
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

  /// Signals the native background tracking service to pause or stop polling.
  ///
  /// Returns a boolean indicating if the command was successfully processed by the platform service.
  Future<bool> stopTracking() async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('stopTracking');
      return success ?? false;
    } on PlatformException catch (e) {
      print("Failed to stop tracking service: ${e.message}");
      return false;
    }
  }

  /// Exposes a broadcast stream to receive real-time location coordinate updates from the native GPS service.
  Stream<dynamic> get telemetryStream {
    _telemetryStream ??= _telemetryChannel.receiveBroadcastStream();
    return _telemetryStream!;
  }
}

