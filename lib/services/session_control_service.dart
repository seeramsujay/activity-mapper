import 'dart:io';
import 'package:flutter/foundation.dart';
import 'adaptive_pacing_service.dart';
import 'db_service.dart';
import 'gpx_service.dart';
import 'platform_service.dart';
import 'settings_service.dart';

/// Single place for session lifecycle transitions (pause, resume, continue, finish) and for the
/// turn-back alarm, so the HUD, home dashboard and history screens behave identically.
///
/// Timing model: "elapsed" is active workout time, i.e. wall-clock time excluding pauses. Pausing
/// stops the native GPS service (no points are logged during a break) and persists the elapsed
/// time; resuming restarts the service with that elapsed time as its base.
class SessionControlService {
  /// The singleton instance of [SessionControlService].
  static final SessionControlService instance = SessionControlService._();

  SessionControlService._();

  /// Seconds into the workout at which the turn-back alarm fires.
  static int outboundLimitSeconds({
    required int targetDurationSeconds,
    required double safetyBufferPct,
    required String activityType,
  }) {
    return AdaptivePacingService.calculateAsymmetricOutboundLimitSeconds(
      targetDurationSeconds: targetDurationSeconds,
      safetyBufferPct: safetyBufferPct,
      isMotorVehicle: isMotorVehicle(activityType),
    );
  }

  /// Whether the activity type is a motorised profile (no fatigue asymmetry).
  static bool isMotorVehicle(String activityType) {
    final type = activityType.toLowerCase();
    return type.contains('vehicle') || type.contains('drive') || type.contains('car') || type.contains('motor');
  }

  /// Best-known active elapsed time for a session row.
  ///
  /// Prefers the live native service; falls back to the persisted value, then to wall-clock time
  /// since start for sessions recorded before elapsed time was persisted.
  Future<Duration> recoverElapsed(Map<String, dynamic> session) async {
    final int id = session['id'] as int;
    final native = await PlatformService.instance.getTrackingState();
    if (native != null && native.isRunning && native.sessionId == id) {
      return native.elapsed;
    }
    final stored = (session['active_elapsed_ms'] as num?)?.toInt();
    if (stored != null) return Duration(milliseconds: stored);
    final start = session['start_time'] as int;
    return Duration(milliseconds: max0(DateTime.now().millisecondsSinceEpoch - start));
  }

  /// Ensures the native service is logging for an `active` session (e.g. after the app or
  /// phone was restarted). Returns true if tracking is (now) running for [sessionId].
  Future<bool> ensureNativeTracking(Map<String, dynamic> session, Duration elapsed) async {
    if (session['status'] != 'active') return false;
    final id = session['id'] as int;
    final native = await PlatformService.instance.getTrackingState();
    if (native == null) return false;
    if (native.isRunning && native.sessionId == id) return true;
    return PlatformService.instance.startTracking(
      sessionId: id,
      activityType: (session['activity_type'] as String? ?? 'run').toLowerCase(),
      targetDurationSeconds: session['target_duration'] as int,
      safetyBufferPct: (session['safety_buffer'] as num).toDouble(),
      gpsIntervalMs: SettingsService.instance.gpsSamplingRateMs,
      elapsedBaseSeconds: elapsed.inSeconds,
    );
  }

  /// Pauses a session: stops GPS logging and persists the elapsed time.
  Future<void> pause(int sessionId, Duration elapsed) async {
    await PlatformService.instance.stopTracking();
    await DbService.instance.saveActiveElapsed(sessionId, elapsed);
    await DbService.instance.updateSessionStatus(sessionId, 'paused');
  }

  /// Resumes (or restarts) logging for a session.
  ///
  /// With [resetTurnBack] the alarm is re-armed, used when the countdown restarts or the
  /// target changes. Returns whether the native service started.
  Future<bool> resume({
    required int sessionId,
    required String activityType,
    required int targetDurationSeconds,
    required double safetyBufferPct,
    required Duration elapsedBase,
    bool resetTurnBack = false,
    bool googleMapsMode = false,
    int? gpsIntervalMs,
  }) async {
    final db = DbService.instance;
    if (resetTurnBack) await db.clearTurnBackTriggered(sessionId);
    await db.updateSessionTargetDuration(sessionId, targetDurationSeconds);
    await db.saveActiveElapsed(sessionId, elapsedBase);
    await db.updateSessionStatus(sessionId, 'active');
    return PlatformService.instance.startTracking(
      sessionId: sessionId,
      activityType: activityType.toLowerCase(),
      targetDurationSeconds: targetDurationSeconds,
      safetyBufferPct: safetyBufferPct,
      gpsIntervalMs: gpsIntervalMs ?? SettingsService.instance.gpsSamplingRateMs,
      googleMapsMode: googleMapsMode,
      elapsedBaseSeconds: elapsedBase.inSeconds,
    );
  }

  /// Reopens a completed session to append more GPS points.
  ///
  /// [resetTimer] starts a fresh countdown from zero; otherwise the previous elapsed time is kept.
  Future<bool> continueCompletedSession({
    required int sessionId,
    required String activityType,
    required int targetDurationSeconds,
    required double safetyBufferPct,
    required bool resetTimer,
  }) async {
    final session = await DbService.instance.getSession(sessionId);
    if (session == null) return false;

    Duration base = Duration.zero;
    if (!resetTimer) {
      final stored = (session['active_elapsed_ms'] as num?)?.toInt();
      final start = session['start_time'] as int;
      final end = session['end_time'] as int?;
      base = Duration(milliseconds: stored ?? (end != null ? max0(end - start) : 0));
    }

    await DbService.instance.reactivateSession(
      sessionId,
      newTargetDurationSeconds: targetDurationSeconds,
      resetTurnBack: resetTimer,
    );
    return resume(
      sessionId: sessionId,
      activityType: activityType,
      targetDurationSeconds: targetDurationSeconds,
      safetyBufferPct: safetyBufferPct,
      elapsedBase: base,
      resetTurnBack: resetTimer,
    );
  }

  /// Finishes a session: stops GPS, marks it completed and writes the GPX file.
  ///
  /// Returns the GPX file, or null if it could not be written (the session is still saved).
  Future<File?> finish(int sessionId, String activityType, {Duration? elapsed}) async {
    await PlatformService.instance.stopTracking();
    if (elapsed != null) {
      await DbService.instance.saveActiveElapsed(sessionId, elapsed);
    }
    await DbService.instance.updateSessionStatus(sessionId, 'completed');
    try {
      return await GpxService.instance.saveGpxFile(sessionId, '${activityType.toUpperCase()} - Out and Back');
    } catch (e, stack) {
      debugPrint('GPX save failed for session $sessionId: $e\n$stack');
      return null;
    }
  }

  /// Fires the turn-back alarm unless the native service (or another screen) already did.
  ///
  /// Returns true if this call sounded the alarm.
  Future<bool> fireTurnBackIfUnclaimed(int sessionId, String activityType) async {
    final claimed = await DbService.instance.markTurnBackTriggered(sessionId);
    if (claimed) {
      await PlatformService.instance.triggerTurnBackAlert(activityType: activityType);
    }
    return claimed;
  }

  /// Non-negative helper for millisecond differences.
  @visibleForTesting
  static int max0(int v) => v < 0 ? 0 : v;
}
