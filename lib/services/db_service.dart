import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local database helper class using SQLite.
///
/// Configures tables, controls transaction WAL journal modes, and runs all
/// session, coordinate telemetry, crop, and merge database operations.
class DbService {
  /// The singleton instance of [DbService].
  static final DbService instance = DbService._init();

  static Database? _database;
  static Future<Database>? _opening;

  /// Overrides the on-disk location of the database (tests use an in-memory path).
  @visibleForTesting
  static String? debugDatabasePathOverride;

  /// Cached track lengths of completed sessions (their points never change in place).
  final Map<int, double> _distanceCacheKm = {};

  DbService._init();

  /// Returns the active SQLite [Database] connection, initializing it if necessary.
  Future<Database> get database async {
    if (_database != null) return _database!;
    // Concurrent first callers share one open instead of racing to open twice.
    _opening ??= _initDB('turnback.db');
    _database = await _opening!;
    return _database!;
  }

  /// Closes the connection and forgets cached state so tests start from a clean database.
  @visibleForTesting
  Future<void> resetForTesting() async {
    await _database?.close();
    _database = null;
    _opening = null;
    _distanceCacheKm.clear();
  }

  /// Resolves the filesystem database path and opens the SQLite database.
  ///
  /// The schema version must stay in sync with the native DatabaseHelper.kt, which opens the
  /// same file and refuses to downgrade.
  Future<Database> _initDB(String filePath) async {
    String path;
    if (debugDatabasePathOverride != null) {
      path = debugDatabasePathOverride!;
    } else if (Platform.isAndroid) {
      // Matches Android context.getDatabasePath("turnback.db")
      path = join(await getDatabasesPath(), filePath);
    } else {
      // Matches iOS Documents directory appendingPathComponent("turnback.db")
      final dbFolder = await getApplicationDocumentsDirectory();
      path = join(dbFolder.path, filePath);
    }

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        // Required for ON DELETE CASCADE on points.session_id to actually fire.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
      onOpen: (db) async {
        // Enable Write-Ahead Logging for safe concurrent reads/writes
        await db.rawQuery('PRAGMA journal_mode=WAL;');
        // Idempotent (no version bump, so the native helper stays compatible).
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_points_session_time ON points(session_id, timestamp)');
        await _ensureColumn(db, 'sessions', 'active_elapsed_ms', 'INTEGER');
      },
    );
  }

  /// Adds a nullable column to databases created by older app versions (no version bump needed,
  /// so the native DatabaseHelper, which applies the same check, stays compatible).
  static Future<void> _ensureColumn(Database db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == column)) return;
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    } on DatabaseException catch (e) {
      // The native side may have added it concurrently.
      if (!e.toString().contains('duplicate column')) rethrow;
    }
  }

  /// Persists the active workout time (excluding pauses) of a session.
  Future<void> saveActiveElapsed(int sessionId, Duration elapsed) async {
    final db = await database;
    await db.update(
      'sessions',
      {'active_elapsed_ms': elapsed.inMilliseconds},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Creates database tables for sessions and coordinate points.
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        activity_type TEXT NOT NULL,
        target_duration INTEGER NOT NULL,
        safety_buffer REAL NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        turn_back_triggered_at INTEGER,
        status TEXT NOT NULL,
        active_elapsed_ms INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        altitude REAL NOT NULL,
        accuracy REAL NOT NULL,
        speed REAL NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');
  }

  /// Inserts a new session configuration row.
  ///
  /// Returns the newly created session auto-increment integer ID.
  Future<int> createSession({
    required String activityType,
    required int targetDurationSeconds,
    required double safetyBufferPct,
  }) async {
    final db = await database;
    return await db.insert('sessions', {
      'activity_type': activityType,
      'target_duration': targetDurationSeconds,
      'safety_buffer': safetyBufferPct,
      'start_time': DateTime.now().millisecondsSinceEpoch,
      'status': 'active',
    });
  }

  /// Updates the target duration of an active tracking session.
  Future<int> updateSessionTargetDuration(int id, int targetDurationSeconds) async {
    final db = await database;
    return await db.update(
      'sessions',
      {'target_duration': targetDurationSeconds},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Queries the database for any active or paused tracking session.
  ///
  /// Used during startup crash recovery. Returns the session map or null.
  Future<Map<String, dynamic>?> getActiveSession() async {
    final db = await database;
    final results = await db.query(
      'sessions',
      where: 'status = ? OR status = ?',
      whereArgs: ['active', 'paused'],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Updates the tracking status flag of a session (e.g. active, paused, completed).
  Future<void> updateSessionStatus(int sessionId, String status) async {
    _distanceCacheKm.remove(sessionId);
    final db = await database;
    await db.update(
      'sessions',
      {'status': status, if (status == 'completed') 'end_time': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Atomically claims the turn-back alarm for a session.
  ///
  /// Returns true if this call set the flag, false if it was already set (e.g. the native GPS
  /// service fired first). Callers should only sound the alarm when this returns true.
  Future<bool> markTurnBackTriggered(int sessionId) async {
    final db = await database;
    final changed = await db.update(
      'sessions',
      {'turn_back_triggered_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND turn_back_triggered_at IS NULL',
      whereArgs: [sessionId],
    );
    return changed > 0;
  }

  /// Clears the turn-back flag so the alarm can fire again (countdown reset / new target).
  Future<void> clearTurnBackTriggered(int sessionId) async {
    final db = await database;
    await db.update(
      'sessions',
      {'turn_back_triggered_at': null},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Returns a specific tracking session by ID.
  Future<Map<String, dynamic>?> getSession(int sessionId) async {
    final db = await database;
    final res = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Returns a list of all tracking sessions ordered by start time descending.
  Future<List<Map<String, dynamic>>> getSessions() async {
    final db = await database;
    return await db.query('sessions', orderBy: 'start_time DESC');
  }

  /// Returns a list of all completed tracking sessions.
  Future<List<Map<String, dynamic>>> getCompletedSessions() async {
    final db = await database;
    return await db.query(
      'sessions',
      where: 'status = ?',
      whereArgs: ['completed'],
      orderBy: 'start_time DESC',
    );
  }

  /// Calculates planimetric Haversine distance in km between two coordinate points.
  static double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  /// Queries SQLite for the rolling median distance (D_base) over the last [limit]
  /// activities of the selected [activityType] to dynamically scale hysteresis filters.
  Future<double> getRollingMedianDistance(String activityType, {int limit = 10}) async {
    final db = await database;
    final type = activityType.toLowerCase();
    final results = await db.query(
      'sessions',
      where: 'LOWER(activity_type) = ? AND status = ?',
      whereArgs: [type, 'completed'],
      orderBy: 'start_time DESC',
      limit: limit,
    );

    if (results.isEmpty) return 0.0;

    final List<double> distances = [];
    for (final session in results) {
      final dist = await getSessionDistanceKm(session['id'] as int);
      if (dist > 0) distances.add(dist);
    }

    if (distances.isEmpty) return 0.0;
    distances.sort();
    final mid = distances.length ~/ 2;
    if (distances.length % 2 == 1) {
      return distances[mid];
    } else {
      return (distances[mid - 1] + distances[mid]) / 2.0;
    }
  }

  /// Returns the track length of a session in km.
  ///
  /// Completed sessions are cached because their points are never modified in place; editing
  /// operations always create new sessions.
  Future<double> getSessionDistanceKm(int sessionId) async {
    final cached = _distanceCacheKm[sessionId];
    if (cached != null) return cached;

    final db = await database;
    final rows = await db.query(
      'points',
      columns: ['lat', 'lng'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
    final dist = trackDistanceKm(rows);

    final status = await db.query('sessions',
        columns: ['status'], where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (status.isNotEmpty && status.first['status'] == 'completed') {
      _distanceCacheKm[sessionId] = dist;
    }
    return dist;
  }

  /// Sums the Haversine length (km) of an ordered list of `lat`/`lng` point rows.
  static double trackDistanceKm(List<Map<String, dynamic>> points) {
    double dist = 0.0;
    for (int i = 1; i < points.length; i++) {
      dist += calculateDistanceKm(
        (points[i - 1]['lat'] as num).toDouble(),
        (points[i - 1]['lng'] as num).toDouble(),
        (points[i]['lat'] as num).toDouble(),
        (points[i]['lng'] as num).toDouble(),
      );
    }
    return dist;
  }

  /// Returns the total number of stored GPS points across all sessions.
  Future<int> getTotalPointCount() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM points')) ?? 0;
  }

  /// Deletes a tracking session and all its points in one transaction.
  ///
  /// Points are deleted explicitly as well, so databases created before foreign keys were
  /// enabled don't keep orphaned rows.
  Future<void> deleteSession(int sessionId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('points', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    });
    _distanceCacheKm.remove(sessionId);
  }

  /// Removes points whose session no longer exists (left behind by older app versions).
  Future<int> purgeOrphanPoints() async {
    final db = await database;
    return db.rawDelete('DELETE FROM points WHERE session_id NOT IN (SELECT id FROM sessions)');
  }

  /// Retrieves all logged coordinate points for a specific session ordered by timestamp.
  Future<List<Map<String, dynamic>>> getPoints(int sessionId) async {
    final db = await database;
    return await db.query(
      'points',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  /// Inserts a batch of coordinate points within a single SQL transaction.
  Future<void> insertPointsBatch(int sessionId, List<Map<String, dynamic>> points) async {
    final db = await database;
    await db.transaction((txn) => _insertPoints(txn, sessionId, points));
    _distanceCacheKm.remove(sessionId);
  }

  Future<void> _insertPoints(Transaction txn, int sessionId, List<Map<String, dynamic>> points) async {
    final batch = txn.batch();
    for (final p in points) {
      batch.insert('points', {
        'session_id': sessionId,
        'timestamp': p['timestamp'],
        'lat': p['lat'],
        'lng': p['lng'],
        'altitude': p['altitude'] ?? 0.0,
        'accuracy': p['accuracy'] ?? 0.0,
        'speed': p['speed'] ?? 0.0,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Clones a tracking session configuration and inserts its coordinate points.
  ///
  /// The session row and its points are written in one transaction, so a crash can never leave
  /// a half-copied activity behind.
  Future<int> cloneSessionWithPoints({
    required String activityType,
    required int targetDuration,
    required double safetyBuffer,
    required int startTime,
    required int endTime,
    required String status,
    required List<Map<String, dynamic>> points,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final int newSessionId = await txn.insert('sessions', {
        'activity_type': activityType,
        'target_duration': targetDuration,
        'safety_buffer': safetyBuffer,
        'start_time': startTime,
        'end_time': endTime,
        'status': status,
      });
      await _insertPoints(txn, newSessionId, points);
      return newSessionId;
    });
  }

  /// Merges two sessions chronologically into a new unified session.
  ///
  /// Combines all points from [targetSessionId] and [sourceSessionId],
  /// sorted by timestamp, and creates a consolidated session. Optionally deletes the source session.
  Future<int> mergeSessions({
    required int targetSessionId,
    required int sourceSessionId,
    bool deleteSourceAfterMerge = false,
  }) async {
    final db = await database;

    final targetRows = await db.query('sessions', where: 'id = ?', whereArgs: [targetSessionId]);
    final sourceRows = await db.query('sessions', where: 'id = ?', whereArgs: [sourceSessionId]);
    if (targetRows.isEmpty || sourceRows.isEmpty) {
      throw StateError('Cannot merge: session $targetSessionId or $sourceSessionId no longer exists');
    }
    final targetSession = targetRows.first;
    final sourceSession = sourceRows.first;

    final targetPoints = await getPoints(targetSessionId);
    final sourcePoints = await getPoints(sourceSessionId);

    final List<Map<String, dynamic>> combinedPoints = [...targetPoints, ...sourcePoints];
    combinedPoints.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

    final int startTime = combinedPoints.isNotEmpty
        ? (combinedPoints.first['timestamp'] as int)
        : (targetSession['start_time'] as int);
    final int endTime = combinedPoints.isNotEmpty
        ? (combinedPoints.last['timestamp'] as int)
        : (targetSession['end_time'] as int? ?? DateTime.now().millisecondsSinceEpoch);

    final int targetDuration = (targetSession['target_duration'] as int) + (sourceSession['target_duration'] as int);
    final double safetyBuffer = (targetSession['safety_buffer'] as num).toDouble();
    final String activityType = targetSession['activity_type'] as String;

    final int newSessionId = await cloneSessionWithPoints(
      activityType: activityType,
      targetDuration: targetDuration,
      safetyBuffer: safetyBuffer,
      startTime: startTime,
      endTime: endTime,
      status: 'completed',
      points: combinedPoints,
    );

    if (deleteSourceAfterMerge) {
      await deleteSession(sourceSessionId);
    }

    return newSessionId;
  }

  /// Closes the database connection.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }

  /// Wipes all sessions and points from SQLite, resetting the database completely.
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('points');
      await txn.delete('sessions');
    });
    _distanceCacheKm.clear();
  }

  /// Reactivates a completed session so the user can continue logging GPS points to it.
  ///
  /// With [resetTurnBack] the turn-back alarm is re-armed for the new countdown.
  Future<void> reactivateSession(int sessionId, {int? newTargetDurationSeconds, bool resetTurnBack = false}) async {
    final db = await database;
    final Map<String, dynamic> values = {
      'status': 'active',
      'end_time': null,
    };
    if (newTargetDurationSeconds != null) {
      values['target_duration'] = newTargetDurationSeconds;
    }
    if (resetTurnBack) {
      values['turn_back_triggered_at'] = null;
    }
    _distanceCacheKm.remove(sessionId);
    await db.update(
      'sessions',
      values,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}

