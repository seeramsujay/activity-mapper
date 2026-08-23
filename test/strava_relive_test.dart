import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/services/strava_service.dart';
import 'package:turnback/services/relive_service.dart';

void main() {
  group('StravaService Activity Upload Simulation Tests', () {
    test('simulates 1-tap OAuth2 upload in serverless mode', () async {
      final strava = StravaService.instance;
      strava.logout();

      const dummyGpx = '<?xml version="1.0"?><gpx version="1.1"></gpx>';
      final result = await strava.uploadActivity(
        fileContent: dummyGpx,
        fileName: 'session_10.gpx',
        activityName: 'Morning Ride',
        activityType: 'cycling',
      );

      expect(result.success, isTrue);
      expect(result.activityId, isNotNull);
      expect(result.stravaActivityUrl, contains('https://www.strava.com/activities/'));
      expect(strava.state, equals(StravaUploadState.completed));
    });
  });

  group('ReliveService 3D Route GPX Bridge Tests', () {
    test('generates Relive-compliant GPX with smoothed elevations and waypoints', () {
      final relive = ReliveService.instance;
      final rawPoints = [
        {
          'lat': 12.9716,
          'lng': 77.5946,
          'altitude': 900.0,
          'speed': 5.0,
          'timestamp': DateTime.utc(2026, 8, 22, 10, 0, 0).millisecondsSinceEpoch,
        },
        {
          'lat': 12.9750,
          'lng': 77.5980,
          'altitude': 1250.0, // Summit point
          'speed': 12.0, // Top speed point
          'timestamp': DateTime.utc(2026, 8, 22, 10, 25, 0).millisecondsSinceEpoch,
        },
        {
          'lat': 12.9780,
          'lng': 77.6010,
          'altitude': 1100.0,
          'speed': 6.0,
          'timestamp': DateTime.utc(2026, 8, 22, 10, 50, 0).millisecondsSinceEpoch,
        },
        {
          'lat': 12.9716,
          'lng': 77.5946,
          'altitude': 905.0,
          'speed': 4.0,
          'timestamp': DateTime.utc(2026, 8, 22, 11, 30, 0).millisecondsSinceEpoch,
        },
      ];

      final gpx = relive.generateReliveGpx(
        activityName: 'Mountain Climb',
        rawPoints: rawPoints,
        turnBackTriggeredAt: rawPoints[2]['timestamp'] as int,
      );

      expect(gpx, contains('creator="TurnBack - Relive 3D Video Bridge"'));
      expect(gpx, contains('<wpt lat="12.9716" lon="77.5946">'));
      expect(gpx, contains('<name>Start</name>'));
      expect(gpx, contains('<name>Summit'));
      expect(gpx, contains('<name>Finish</name>'));
      expect(gpx, contains('<trk>'));
      expect(gpx, contains('<ele>'));
      expect(gpx, contains('</gpx>'));
    });
  });
}
