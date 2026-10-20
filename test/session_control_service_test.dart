import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:turnback/services/db_service.dart';
import 'package:turnback/services/session_control_service.dart';

/// Verifies pause/resume/continue/turn-back flows end to end against a real SQLite database and
/// a recorded native method channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.opensource.tracker/control');
  final db = DbService.instance;
  final control = SessionControlService.instance;

  late List<MethodCall> calls;
  Map<String, dynamic> nativeState = {'isRunning': false};

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.resetForTesting();
    DbService.debugDatabasePathOverride = inMemoryDatabasePath;
    calls = [];
    nativeState = {'isRunning': false};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getTrackingState':
          return nativeState;
        default:
          return true;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  tearDownAll(() async {
    await db.resetForTesting();
    DbService.debugDatabasePathOverride = null;
  });

  Iterable<MethodCall> callsTo(String method) => calls.where((c) => c.method == method);

  group('Turn-back threshold (single formula shared with GpsLoggingService.kt)', () {
    test('90 min run with 8% buffer turns back at T / (1 + 1.08 * 1.15)', () {
      final limit = SessionControlService.outboundLimitSeconds(
        targetDurationSeconds: 5400,
        safetyBufferPct: 8.0,
        activityType: 'run',
      );
      expect(limit, 2409); // 44.6% of the target
    });

    test('motor vehicles have no fatigue asymmetry (gamma = 1.0)', () {
      final limit = SessionControlService.outboundLimitSeconds(
        targetDurationSeconds: 5400,
        safetyBufferPct: 8.0,
        activityType: 'drive',
      );
      expect(limit, 2596);
    });

    test('larger safety buffer turns back earlier', () {
      int limitFor(double buffer) => SessionControlService.outboundLimitSeconds(
            targetDurationSeconds: 3600,
            safetyBufferPct: buffer,
            activityType: 'hike',
          );
      expect(limitFor(20.0), lessThan(limitFor(8.0)));
      expect(limitFor(0.0), lessThan(1800)); // always earlier than a naive 50/50 split
    });

    test('free runs (no target) never trigger', () {
      expect(
        SessionControlService.outboundLimitSeconds(targetDurationSeconds: 0, safetyBufferPct: 8, activityType: 'run'),
        0,
      );
    });
  });

  group('Pause / resume', () {
    test('pause stops native logging and persists elapsed time and status', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);

      await control.pause(id, const Duration(minutes: 7));

      expect(callsTo('stopTracking'), hasLength(1));
      final s = (await db.getSession(id))!;
      expect(s['status'], 'paused');
      expect(s['active_elapsed_ms'], 7 * 60 * 1000);
    });

    test('resume restarts native logging from the paused elapsed time with user GPS settings', () async {
      final id = await db.createSession(activityType: 'ride', targetDurationSeconds: 3600, safetyBufferPct: 8.0);
      await control.pause(id, const Duration(minutes: 7));

      final ok = await control.resume(
        sessionId: id,
        activityType: 'Ride',
        targetDurationSeconds: 3600,
        safetyBufferPct: 8.0,
        elapsedBase: const Duration(minutes: 7),
      );

      expect(ok, isTrue);
      final args = callsTo('startTracking').single.arguments as Map;
      expect(args['sessionId'], id);
      expect(args['activityType'], 'ride');
      expect(args['elapsedBaseSeconds'], 420);
      expect(args.keys, containsAll(['maxAccuracyM', 'minDistanceM', 'audioAlarms', 'hapticAlarms', 'autoPauseMusic']));
      expect((await db.getSession(id))!['status'], 'active');
    });

    test('resume with a new countdown re-arms the alarm and applies the new target', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);
      await db.markTurnBackTriggered(id);

      await control.resume(
        sessionId: id,
        activityType: 'run',
        targetDurationSeconds: 1800,
        safetyBufferPct: 8.0,
        elapsedBase: Duration.zero,
        resetTurnBack: true,
      );

      final s = (await db.getSession(id))!;
      expect(s['turn_back_triggered_at'], isNull);
      expect(s['target_duration'], 1800);
      expect((callsTo('startTracking').single.arguments as Map)['elapsedBaseSeconds'], 0);
    });
  });

  group('Continue a completed session', () {
    Future<int> completed() async {
      final id = await db.cloneSessionWithPoints(
        activityType: 'run',
        targetDuration: 3600,
        safetyBuffer: 8.0,
        startTime: 0,
        endTime: 30 * 60 * 1000,
        status: 'completed',
        points: [
          {'timestamp': 0, 'lat': 1.0, 'lng': 1.0},
        ],
      );
      await db.saveActiveElapsed(id, const Duration(minutes: 25));
      await db.markTurnBackTriggered(id);
      return id;
    }

    test('"continue existing timer" keeps the elapsed time and the alarm state', () async {
      final id = await completed();
      await control.continueCompletedSession(
        sessionId: id,
        activityType: 'run',
        targetDurationSeconds: 3600,
        safetyBufferPct: 8.0,
        resetTimer: false,
      );
      expect((callsTo('startTracking').single.arguments as Map)['elapsedBaseSeconds'], 25 * 60);
      expect((await db.getSession(id))!['turn_back_triggered_at'], isNotNull);
    });

    test('"reset return countdown" starts from zero and re-arms the alarm', () async {
      final id = await completed();
      await control.continueCompletedSession(
        sessionId: id,
        activityType: 'run',
        targetDurationSeconds: 3600,
        safetyBufferPct: 8.0,
        resetTimer: true,
      );
      expect((callsTo('startTracking').single.arguments as Map)['elapsedBaseSeconds'], 0);
      final s = (await db.getSession(id))!;
      expect(s['turn_back_triggered_at'], isNull);
      expect(s['status'], 'active');
    });
  });

  group('Turn-back alarm de-duplication', () {
    test('only the first claimant sounds the alarm', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);

      expect(await control.fireTurnBackIfUnclaimed(id, 'run'), isTrue);
      expect(await control.fireTurnBackIfUnclaimed(id, 'run'), isFalse);
      expect(callsTo('triggerTurnBackAlert'), hasLength(1));
    });

    test('no alarm when the native service already claimed it', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);
      final database = await db.database;
      await database.update('sessions', {'turn_back_triggered_at': 123}, where: 'id = ?', whereArgs: [id]);

      expect(await control.fireTurnBackIfUnclaimed(id, 'run'), isFalse);
      expect(callsTo('triggerTurnBackAlert'), isEmpty);
    });
  });

  group('Recovery after app restart', () {
    test('elapsed time comes from the live native service when it runs this session', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);
      nativeState = {'isRunning': true, 'sessionId': id, 'elapsedMs': 600000, 'turnBackAlerted': false};

      final elapsed = await control.recoverElapsed((await db.getSession(id))!);
      expect(elapsed, const Duration(minutes: 10));
    });

    test('falls back to the persisted elapsed time when the service is not running', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);
      await db.saveActiveElapsed(id, const Duration(minutes: 3));

      final elapsed = await control.recoverElapsed((await db.getSession(id))!);
      expect(elapsed, const Duration(minutes: 3));
    });

    test('restarts native logging for an active session whose service died', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);
      final session = (await db.getSession(id))!;

      final running = await control.ensureNativeTracking(session, const Duration(minutes: 4));

      expect(running, isTrue);
      expect((callsTo('startTracking').single.arguments as Map)['elapsedBaseSeconds'], 240);
    });

    test('does not restart a paused session', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);
      await db.updateSessionStatus(id, 'paused');

      expect(await control.ensureNativeTracking((await db.getSession(id))!, Duration.zero), isFalse);
      expect(callsTo('startTracking'), isEmpty);
    });
  });

  test('finish completes the session even if the GPX file cannot be written', () async {
    final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);

    // No path_provider plugin in unit tests, so the GPX write fails; the session must still save.
    final file = await control.finish(id, 'run', elapsed: const Duration(minutes: 30));

    expect(file, isNull);
    expect(callsTo('stopTracking'), hasLength(1));
    final s = (await db.getSession(id))!;
    expect(s['status'], 'completed');
    expect(s['end_time'], isNotNull);
    expect(s['active_elapsed_ms'], 30 * 60 * 1000);
  });
}
