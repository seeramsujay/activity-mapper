import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:turnback/models/waypoint.dart';
import 'package:turnback/services/db_service.dart';

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

  test('insertWaypoint and getWaypoints persist and retrieve waypoints',
      () async {
    final sessionId = await db.createSession(
      activityType: 'hike',
      targetDurationSeconds: 7200,
      safetyBufferPct: 10.0,
    );

    final wp1 = Waypoint(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      lat: 12.9716,
      lng: 77.5946,
      altitude: 920.0,
      name: 'Spring 1',
      category: 'water',
      description: 'Potable water source',
    );

    final wp2 = Waypoint(
      sessionId: sessionId,
      timestamp: DateTime.now().add(const Duration(minutes: 10)),
      lat: 12.9750,
      lng: 77.5980,
      altitude: 980.0,
      name: 'Scenic Cliff',
      category: 'view',
    );

    final id1 = await db.insertWaypoint(wp1);
    final id2 = await db.insertWaypoint(wp2);
    expect(id1, greaterThan(0));
    expect(id2, greaterThan(id1));

    final waypoints = await db.getWaypoints(sessionId);
    expect(waypoints.length, equals(2));
    expect(waypoints[0].name, equals('Spring 1'));
    expect(waypoints[0].category, equals('water'));
    expect(waypoints[0].altitude, equals(920.0));
    expect(waypoints[1].name, equals('Scenic Cliff'));
    expect(waypoints[1].category, equals('view'));

    // Test deletion
    await db.deleteWaypoint(id1);
    final remaining = await db.getWaypoints(sessionId);
    expect(remaining.length, equals(1));
    expect(remaining.first.name, equals('Scenic Cliff'));
  });

  test('deleting a session cascades and deletes its waypoints', () async {
    final sessionId = await db.createSession(
      activityType: 'run',
      targetDurationSeconds: 3600,
      safetyBufferPct: 5.0,
    );

    await db.insertWaypoint(Waypoint(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      lat: 12.0,
      lng: 77.0,
      name: 'P1',
      category: 'pin',
    ));

    expect((await db.getWaypoints(sessionId)).length, equals(1));

    await db.deleteSession(sessionId);
    expect((await db.getWaypoints(sessionId)).length, equals(0));
  });
}
