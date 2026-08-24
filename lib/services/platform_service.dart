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

  /// Returns true if the build is running the Colab P2P flavor.
  static bool get isColabMode => appFlavor == 'colab';

  /// Returns true if the build is running the pure Offline flavor.
  static bool get isOfflineMode => !isColabMode;

  Stream<dynamic>? _telemetryStream;

  /// Checks if background and fine location permissions are granted.
  Future<bool> checkPermissions() async {
    try {
      final bool? granted = await _controlChannel
          .invokeMethod<bool>('checkPermissions')
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Requests runtime location and notification permissions.
  Future<bool> requestPermissions() async {
    try {
      final bool? granted = await _controlChannel
          .invokeMethod<bool>('requestPermissions')
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

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
      }).timeout(const Duration(seconds: 8), onTimeout: () => true);
      return success ?? true;
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

  /// Triggers the native activity-specific turn-back alarm (vibration, cycling music pause, audio tone).
  Future<bool> triggerTurnBackAlert({required String activityType}) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('triggerTurnBackAlert', {
        'activityType': activityType,
      });
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Launches Musicolet (or default system music player).
  Future<bool> launchMusicApp([String packageName = 'in.krosbits.musicolet']) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('launchMusicApp', {
        'packageName': packageName,
      });
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Dispatches media control key events (play/pause, next, prev, volume) to system audio players.
  Future<bool> sendMediaAction(String action) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('sendMediaAction', {
        'action': action,
      });
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Clamps display refresh rate to 30 Hz or lower for battery optimization during tracking HUD.
  Future<bool> setPowerSaveDisplay(bool enable) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('setPowerSaveDisplay', {
        'enable': enable,
      });
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Exposes a broadcast stream to receive real-time location coordinate updates from the native GPS service.
  Stream<dynamic> get telemetryStream {
    _telemetryStream ??= _telemetryChannel.receiveBroadcastStream();
    return _telemetryStream!;
  }
}


