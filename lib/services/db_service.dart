import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DbService {
  static final DbService instance = DbService._init();
  static Database? _database;

  DbService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('turnback.db');
    return _database!;
  }

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
        await db.execute('PRAGMA journal_mode=WAL;');
      },
    );
  }

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

  // Session operations
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

  Future<void> updateSessionStatus(int sessionId, String status) async {
    final db = await database;
    await db.update(
      'sessions',
      {'status': status, if (status == 'completed') 'end_time': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> markTurnBackTriggered(int sessionId) async {
    final db = await database;
    await db.update(
      'sessions',
      {'turn_back_triggered_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<Map<String, dynamic>>> getCompletedSessions() async {
    final db = await database;
    return await db.query(
      'sessions',
      where: 'status = ?',
      whereArgs: ['completed'],
      orderBy: 'start_time DESC',
    );
  }

  Future<void> deleteSession(int sessionId) async {
    final db = await database;
    await db.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // Points operations
  Future<List<Map<String, dynamic>>> getPoints(int sessionId) async {
    final db = await database;
    return await db.query(
      'points',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

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
          'altitude': p['altitude'],
          'accuracy': p['accuracy'],
          'speed': p['speed'],
        });
      }
      await batch.commit(noResult: true);
    });
  }

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

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}
