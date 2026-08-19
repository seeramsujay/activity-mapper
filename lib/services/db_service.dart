import 'dart:io';
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

  DbService._init();

  /// Returns the active SQLite [Database] connection, initializing it if necessary.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('turnback.db');
    return _database!;
  }

  /// Resolves the filesystem database path and opens the SQLite database.
  Future<Database> _initDB(String filePath) async {
    String path;
    if (Platform.isAndroid) {
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
      onCreate: _createDB,
      onOpen: (db) async {
        // Enable Write-Ahead Logging for safe concurrent reads/writes
        await db.rawQuery('PRAGMA journal_mode=WAL;');
      },
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
        status TEXT NOT NULL
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
    final db = await database;
    await db.update(
      'sessions',
      {'status': status, if (status == 'completed') 'end_time': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Sets the timestamp flag indicating that the turnback threshold has been triggered.
  Future<void> markTurnBackTriggered(int sessionId) async {
    final db = await database;
    await db.update(
      'sessions',
      {'turn_back_triggered_at': DateTime.now().millisecondsSinceEpoch},
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

  /// Deletes a tracking session and cascadingly deletes all its points.
  Future<void> deleteSession(int sessionId) async {
    final db = await database;
    await db.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
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
    await db.transaction((txn) async {
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
    });
  }

  /// Clones a tracking session configuration and inserts its coordinate points batch.
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
    final int newSessionId = await db.insert('sessions', {
      'activity_type': activityType,
      'target_duration': targetDuration,
      'safety_buffer': safetyBuffer,
      'start_time': startTime,
      'end_time': endTime,
      'status': status,
    });

    await insertPointsBatch(newSessionId, points);
    return newSessionId;
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

    final targetSession = (await db.query('sessions', where: 'id = ?', whereArgs: [targetSessionId])).first;
    final sourceSession = (await db.query('sessions', where: 'id = ?', whereArgs: [sourceSessionId])).first;

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
    final double safetyBuffer = (targetSession['safety_buffer'] as double);
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
  }

  /// Reactivates a completed session so the user can continue logging GPS points to it.
  Future<void> reactivateSession(int sessionId, {int? newTargetDurationSeconds}) async {
    final db = await database;
    final Map<String, dynamic> values = {
      'status': 'active',
      'end_time': null,
    };
    if (newTargetDurationSeconds != null) {
      values['target_duration'] = newTargetDurationSeconds;
    }
    await db.update(
      'sessions',
      values,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}

