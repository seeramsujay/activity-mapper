import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:turnback/services/db_service.dart';

/// Runs DbService against a real SQLite engine (FFI) to verify schema, transactions and
/// the turn-back / elapsed-time bookkeeping shared with the native GPS service.
void main() {
  final db = DbService.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.resetForTesting();
    DbService.debugDatabasePathOverride = inMemoryDatabasePath;
  });

  tearDownAll(() async {
    await db.resetForTesting();
    DbService.debugDatabasePathOverride = null;
  });

  Map<String, dynamic> pt(int ts, double lat, double lng, {double alt = 100.0, double speed = 3.0}) =>
      {'timestamp': ts, 'lat': lat, 'lng': lng, 'altitude': alt, 'accuracy': 5.0, 'speed': speed};

  Future<int> completedSession(List<Map<String, dynamic>> points, {String type = 'run'}) {
    return db.cloneSessionWithPoints(
      activityType: type,
      targetDuration: 3600,
      safetyBuffer: 8.0,
      startTime: points.isEmpty ? 0 : points.first['timestamp'] as int,
      endTime: points.isEmpty ? 0 : points.last['timestamp'] as int,
      status: 'completed',
      points: points,
    );
  }

  Future<int> pointRowCount() async {
    final raw = await (await db.database).rawQuery('SELECT COUNT(*) AS c FROM points');
    return raw.first['c'] as int;
  }

  group('Schema', () {
    test('foreign keys are enforced so deleting a session cascades to its points', () async {
      final id = await completedSession([pt(1000, 12.0, 77.0), pt(2000, 12.001, 77.0)]);
      final database = await db.database;
      final fk = await database.rawQuery('PRAGMA foreign_keys');
      expect(fk.first.values.first, 1);

      await database.delete('sessions', where: 'id = ?', whereArgs: [id]);
      expect(await pointRowCount(), 0);
    });

    test('points index on (session_id, timestamp) exists', () async {
      final database = await db.database;
      final idx = await database.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
      expect(idx.map((r) => r['name']), contains('idx_points_session_time'));
    });

    test('legacy databases gain the active_elapsed_ms column without a version bump', () async {
      final dir = await Directory.systemTemp.createTemp('turnback_legacy');
      final path = '${dir.path}/turnback.db';
      final legacy = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (d, v) async {
              await d.execute('CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, activity_type TEXT NOT NULL, '
                  'target_duration INTEGER NOT NULL, safety_buffer REAL NOT NULL, start_time INTEGER NOT NULL, '
                  'end_time INTEGER, turn_back_triggered_at INTEGER, status TEXT NOT NULL)');
              await d.execute('CREATE TABLE points (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id INTEGER NOT NULL, '
                  'timestamp INTEGER NOT NULL, lat REAL NOT NULL, lng REAL NOT NULL, altitude REAL NOT NULL, '
                  'accuracy REAL NOT NULL, speed REAL NOT NULL, '
                  'FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE)');
            },
          ));
      await legacy.close();

      DbService.debugDatabasePathOverride = path;
      final database = await db.database;
      final cols = await database.rawQuery('PRAGMA table_info(sessions)');
      expect(cols.map((c) => c['name']), contains('active_elapsed_ms'));
      expect(await database.getVersion(), 1);

      await db.resetForTesting();
      await dir.delete(recursive: true);
    });
  });

  group('Session lifecycle', () {
    test('deleteSession removes the session and all of its points', () async {
      final keep = await completedSession([pt(1000, 1, 1), pt(2000, 1.001, 1)]);
      final gone = await completedSession([pt(3000, 2, 2), pt(4000, 2.001, 2), pt(5000, 2.002, 2)]);

      await db.deleteSession(gone);

      expect(await db.getSession(gone), isNull);
      expect(await db.getPoints(gone), isEmpty);
      expect(await db.getPoints(keep), hasLength(2));
      expect(await db.getTotalPointCount(), 2);
    });

    test('purgeOrphanPoints removes points left behind by older versions', () async {
      await completedSession([pt(1000, 1, 1)]);
      final database = await db.database;
      await database.execute('PRAGMA foreign_keys = OFF');
      await database.insert('points', {...pt(9000, 5, 5), 'session_id': 999});
      await database.execute('PRAGMA foreign_keys = ON');

      expect(await db.purgeOrphanPoints(), 1);
      expect(await db.getTotalPointCount(), 1);
    });

    test('cloneSessionWithPoints is atomic: a bad point leaves no half-written session', () async {
      final before = (await db.getSessions()).length;
      final bad = [pt(1000, 1, 1), {'timestamp': 2000, 'lat': null, 'lng': 1.0}];

      await expectLater(completedSession(bad), throwsA(anything));

      expect((await db.getSessions()).length, before);
      expect(await db.getTotalPointCount(), 0);
    });

    test('mergeSessions creates a chronologically sorted session and keeps sources unless asked', () async {
      final a = await completedSession([pt(1000, 1, 1), pt(3000, 1.002, 1)]);
      final b = await completedSession([pt(2000, 1.001, 1), pt(4000, 1.003, 1)]);

      final merged = await db.mergeSessions(targetSessionId: a, sourceSessionId: b, deleteSourceAfterMerge: true);

      final times = (await db.getPoints(merged)).map((p) => p['timestamp']).toList();
      expect(times, [1000, 2000, 3000, 4000]);
      final session = (await db.getSession(merged))!;
      expect(session['target_duration'], 7200);
      expect(session['start_time'], 1000);
      expect(session['end_time'], 4000);
      expect(await db.getSession(b), isNull);
      expect(await db.getSession(a), isNotNull);
    });

    test('mergeSessions fails cleanly when a session no longer exists', () async {
      final a = await completedSession([pt(1000, 1, 1)]);
      expect(db.mergeSessions(targetSessionId: a, sourceSessionId: 12345), throwsStateError);
    });
  });

  group('Turn-back flag shared with the native service', () {
    test('markTurnBackTriggered claims the alarm exactly once', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);

      expect(await db.markTurnBackTriggered(id), isTrue);
      expect(await db.markTurnBackTriggered(id), isFalse);

      await db.clearTurnBackTriggered(id);
      expect(await db.markTurnBackTriggered(id), isTrue);
    });

    test('reactivateSession re-arms the alarm only when asked', () async {
      final id = await completedSession([pt(1000, 1, 1)]);
      await db.markTurnBackTriggered(id);

      await db.reactivateSession(id);
      expect((await db.getSession(id))!['turn_back_triggered_at'], isNotNull);
      expect((await db.getSession(id))!['status'], 'active');

      await db.reactivateSession(id, newTargetDurationSeconds: 1800, resetTurnBack: true);
      final s = (await db.getSession(id))!;
      expect(s['turn_back_triggered_at'], isNull);
      expect(s['target_duration'], 1800);
      expect(s['end_time'], isNull);
    });

    test('saveActiveElapsed persists elapsed workout time', () async {
      final id = await db.createSession(activityType: 'run', targetDurationSeconds: 3600, safetyBufferPct: 8.0);
      await db.saveActiveElapsed(id, const Duration(minutes: 12, seconds: 5));
      expect((await db.getSession(id))!['active_elapsed_ms'], 725000);
    });
  });

  group('Distance', () {
    test('getSessionDistanceKm matches the Haversine track length', () async {
      // ~111.2 m per 0.001° of latitude
      final id = await completedSession([pt(1000, 10.000, 20), pt(2000, 10.001, 20), pt(3000, 10.002, 20)]);
      expect(await db.getSessionDistanceKm(id), closeTo(0.2224, 0.001));
    });

    test('cached distance is invalidated when a completed session is continued', () async {
      final id = await completedSession([pt(1000, 10.000, 20), pt(2000, 10.001, 20)]);
      final before = await db.getSessionDistanceKm(id);

      await db.reactivateSession(id);
      await db.insertPointsBatch(id, [pt(3000, 10.002, 20)]);
      await db.updateSessionStatus(id, 'completed');

      expect(await db.getSessionDistanceKm(id), greaterThan(before + 0.1));
    });

    test('rolling median ignores other activity types', () async {
      await completedSession([pt(1000, 0, 0), pt(2000, 0.01, 0)], type: 'run'); // ~1.11 km
      await completedSession([pt(1000, 0, 0), pt(2000, 0.03, 0)], type: 'run'); // ~3.34 km
      await completedSession([pt(1000, 0, 0), pt(2000, 0.50, 0)], type: 'ride');

      expect(await db.getRollingMedianDistance('run'), closeTo((1.112 + 3.336) / 2, 0.01));
    });
  });
}
