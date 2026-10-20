import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'settings_service.dart';

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
          .invokeMethod<bool>('requestPermissions');
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Signals the native background tracking service to start polling GPS coordinates.
  ///
  /// Passes down session configurations like target durations, buffers, and gps polling intervals.
  /// [elapsedBaseSeconds] is the active workout time already accumulated before this segment
  /// (non-zero when resuming after a pause), so native and HUD turn-back timing stay in sync.
  /// Returns a boolean indicating if the service was spawned successfully.
  ///
  /// No timeout: the native side may be waiting on a user-paced permission dialog.
  Future<bool> startTracking({
    required int sessionId,
    required String activityType,
    required int targetDurationSeconds,
    required double safetyBufferPct,
    required int gpsIntervalMs,
    bool googleMapsMode = false,
    int elapsedBaseSeconds = 0,
  }) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('startTracking', {
        'sessionId': sessionId,
        'activityType': activityType,
        'targetDurationSeconds': targetDurationSeconds,
        'safetyBufferPct': safetyBufferPct,
        'gpsIntervalMs': gpsIntervalMs,
        'googleMapsMode': googleMapsMode,
        'elapsedBaseSeconds': elapsedBaseSeconds,
        ..._userTrackingPrefs(),
      });
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to start tracking service: ${e.message}");
      return false;
    }
  }

  /// GPS filter and alert preferences from Settings, forwarded to the native service.
  Map<String, dynamic> _userTrackingPrefs() {
    final settings = SettingsService.instance;
    return {
      'maxAccuracyM': settings.maxAccuracyFilter,
      'minDistanceM': settings.minDistanceFilter,
      'audioAlarms': settings.audioAlarmsEnabled,
      'hapticAlarms': settings.hapticsEnabled,
      'autoPauseMusic': settings.autoPauseCyclingMusic,
    };
  }

  /// Queries the native GPS service for its live state.
  ///
  /// Returns null if the platform channel is unavailable (tests, unsupported platforms).
  Future<NativeTrackingState?> getTrackingState() async {
    try {
      final Map<dynamic, dynamic>? raw = await _controlChannel
          .invokeMethod<Map<dynamic, dynamic>>('getTrackingState')
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (raw == null) return null;
      return NativeTrackingState.fromMap(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Sets Google Maps Co-Navigation Passive Piggybacking Mode.
  /// When active, the native location engine requests updates using Priority.PRIORITY_PASSIVE,
  /// consuming minimal extra battery by intercepting Google Maps' high-accuracy GPS fixes.
  Future<bool> setGoogleMapsMode(bool enabled) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('setGoogleMapsMode', {
        'enabled': enabled,
      }).timeout(const Duration(seconds: 4), onTimeout: () => false);
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to set Google Maps mode: ${e.message}");
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
      debugPrint("Failed to stop tracking service: ${e.message}");
      return false;
    }
  }

  /// Triggers the native activity-specific turn-back alarm (vibration, cycling music pause, audio tone).
  Future<bool> triggerTurnBackAlert({required String activityType}) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('triggerTurnBackAlert', {
        'activityType': activityType,
        ..._userTrackingPrefs(),
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

  /// Shares a file using the native system share sheet (AirDrop, WhatsApp, Google Drive, Files, etc.).
  Future<bool> shareFile(String filePath, {String? title}) async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('shareFile', {
        'filePath': filePath,
        'title': title ?? 'Share GPX',
      });
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to share file: ${e.message}");
      return false;
    }
  }

  /// Copies a generated file directly into the device's public Downloads directory.
  Future<String?> saveFileToDownloads(String filePath) async {
    try {
      final String? dest = await _controlChannel.invokeMethod<String>('saveFileToDownloads', {
        'filePath': filePath,
      });
      return dest;
    } on PlatformException catch (e) {
      debugPrint("Failed to save to downloads: ${e.message}");
      return null;
    }
  }

  /// Requests battery optimization exemption so background GPS tracking isn't killed.
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final bool? success = await _controlChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
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

/// Snapshot of the native GPS foreground service state.
class NativeTrackingState {
  /// Whether the native service is currently logging.
  final bool isRunning;

  /// The session the service is logging to (null when not running).
  final int? sessionId;

  /// Active workout time (excluding pauses) as tracked natively.
  final Duration elapsed;

  /// Whether the turn-back alarm has already fired for this session.
  final bool turnBackAlerted;

  const NativeTrackingState({
    required this.isRunning,
    this.sessionId,
    this.elapsed = Duration.zero,
    this.turnBackAlerted = false,
  });

  /// Parses the map returned by the `getTrackingState` method channel call.
  factory NativeTrackingState.fromMap(Map<dynamic, dynamic> map) {
    final running = map['isRunning'] == true;
    return NativeTrackingState(
      isRunning: running,
      sessionId: running ? (map['sessionId'] as num?)?.toInt() : null,
      elapsed: Duration(milliseconds: (map['elapsedMs'] as num?)?.toInt() ?? 0),
      turnBackAlerted: map['turnBackAlerted'] == true,
    );
  }
}
