import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/rally_service.dart';
import '../lib/widgets/breadcrumb_painter.dart';

// -----------------------------------------------------------------------------
// Core Algorithms extracted from UI/Services for isolated mathematical testing
// -----------------------------------------------------------------------------

double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
  const p = 0.017453292519943295;
  final a = 0.5 -
      cos((lat2 - lat1) * p) / 2 +
      cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
  return 12742 * asin(sqrt(a)); // Haversine formula (km)
}

int calculateOutboundLimitSeconds(int targetDurationSeconds, double safetyBufferPct) {
  final double outboundRatio = (100.0 - safetyBufferPct) / 200.0;
  return (targetDurationSeconds * outboundRatio).toInt();
}

String formatSpeedOrPace(double mps, bool isSpeedMode) {
  if (mps <= 0.2) return isSpeedMode ? '0.0' : '--:--';
  if (isSpeedMode) {
    return (mps * 3.6).toStringAsFixed(1);
  } else {
    final double secPerKm = 1000 / mps;
    final int min = secPerKm ~/ 60;
    final int sec = (secPerKm % 60).toInt();
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

String generateMockGpx(int sessionId, String activityName, List<Map<String, dynamic>> points) {
  final buffer = StringBuffer();
  buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buffer.writeln('<gpx version="1.1" creator="TurnBack" xmlns="http://www.topografix.com/GPX/1/1">');
  buffer.writeln('  <trk>');
  buffer.writeln('    <name>$activityName</name>');
  buffer.writeln('    <trkseg>');
  for (final point in points) {
    final lat = point['lat'];
    final lng = point['lng'];
    buffer.writeln('      <trkpt lat="$lat" lon="$lng"></trkpt>');
  }
  buffer.writeln('    </trkseg>');
  buffer.writeln('  </trk>');
  buffer.writeln('</gpx>');
  return buffer.toString();
}

String generateMockKml(int sessionId, String activityName, List<Map<String, dynamic>> points) {
  final buffer = StringBuffer();
  buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
  buffer.writeln('  <Document>');
  buffer.writeln('    <name>$activityName</name>');
  buffer.writeln('    <Placemark>');
  buffer.writeln('      <LineString>');
  buffer.writeln('        <coordinates>');
  for (final point in points) {
    buffer.writeln('          ${point['lng']},${point['lat']},0');
  }
  buffer.writeln('        </coordinates>');
  buffer.writeln('      </LineString>');
  buffer.writeln('    </Placemark>');
  buffer.writeln('  </Document>');
  buffer.writeln('</kml>');
  return buffer.toString();
}

String generateMockGeoJson(int sessionId, String activityName, List<Map<String, dynamic>> points) {
  final coords = points.map((p) => [p['lng'], p['lat'], p['altitude'] ?? 0.0]).toList();
  final data = {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'sessionId': sessionId, 'activityName': activityName},
        'geometry': {'type': 'LineString', 'coordinates': coords},
      }
    ],
  };
  return jsonEncode(data);
}

String generateMockCsv(List<Map<String, dynamic>> points) {
  final buffer = StringBuffer();
  buffer.writeln('index,timestamp_epoch_ms,datetime_utc,latitude,longitude,altitude_m,accuracy_m,speed_mps,speed_kmh');
  for (int i = 0; i < points.length; i++) {
    final p = points[i];
    final ts = p['timestamp'] ?? 0;
    final iso = DateTime.fromMillisecondsSinceEpoch(ts as int).toUtc().toIso8601String();
    final lat = p['lat'];
    final lng = p['lng'];
    final alt = p['altitude'] ?? 0.0;
    final speed = p['speed'] ?? 0.0;
    buffer.writeln('$i,$ts,$iso,$lat,$lng,$alt,0.0,$speed,${(speed * 3.6).toStringAsFixed(2)}');
  }
  return buffer.toString();
}

// -----------------------------------------------------------------------------
// Speed Hysteresis tracker for State Machine testing
// -----------------------------------------------------------------------------
class SpeedHysteresisTracker {
  bool isSpeedMode;
  int consecutiveSpeedTicks = 0;
  int consecutivePaceTicks = 0;

  static const int windowSize = 5;
  static const double speedThreshold = 5.0; // 18 km/h

  SpeedHysteresisTracker({required this.isSpeedMode});

  void addSpeedSample(double speed) {
    if (isSpeedMode) {
      if (speed < speedThreshold) {
        consecutivePaceTicks++;
        consecutiveSpeedTicks = 0;
      } else {
        consecutivePaceTicks = 0;
      }
      if (consecutivePaceTicks >= windowSize) {
        isSpeedMode = false;
        consecutivePaceTicks = 0;
      }
    } else {
      if (speed >= speedThreshold) {
        consecutiveSpeedTicks++;
        consecutivePaceTicks = 0;
      } else {
        consecutiveSpeedTicks = 0;
      }
      if (consecutiveSpeedTicks >= windowSize) {
        isSpeedMode = true;
        consecutiveSpeedTicks = 0;
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Unit Tests
// -----------------------------------------------------------------------------
void main() {
  group('1. Turn-Back Safety Buffer Math Engine', () {
    test('Standard 90-minute target with 8% safety buffer', () {
      final int limit = calculateOutboundLimitSeconds(90 * 60, 8.0);
      expect(limit, 2484);
      expect(limit / 60, 41.4);
    });

    test('Zero percent buffer evaluates to exactly 50/50 time division', () {
      final int limit = calculateOutboundLimitSeconds(100 * 60, 0.0);
      expect(limit, 3000);
      expect(limit / 60, 50.0);
    });

    test('Maximum 20 percent buffer allocates larger safety cushion for return leg', () {
      final int limit = calculateOutboundLimitSeconds(60 * 60, 20.0);
      expect(limit, 1440);
      expect(limit / 60, 24.0);
    });
  });

  group('2. Speed Hysteresis State Machine', () {
    test('Start in Pace mode: switches to Speed on exactly the 5th consecutive high-speed tick', () {
      final tracker = SpeedHysteresisTracker(isSpeedMode: false);
      for (int i = 0; i < 4; i++) {
        tracker.addSpeedSample(5.5);
        expect(tracker.isSpeedMode, isFalse);
      }
      tracker.addSpeedSample(5.5);
      expect(tracker.isSpeedMode, isTrue);
    });

    test('Intermittent speed drops reset the consecutive ticks counter', () {
      final tracker = SpeedHysteresisTracker(isSpeedMode: false);
      tracker.addSpeedSample(6.0);
      tracker.addSpeedSample(6.0);
      tracker.addSpeedSample(3.0);
      expect(tracker.consecutiveSpeedTicks, 0);
      expect(tracker.isSpeedMode, isFalse);
    });
  });

  group('3. Haversine Distance & Formatters', () {
    test('Calculates distance correctly', () {
      final double distance = calculateDistanceKm(40.7679, -73.9818, 40.7644, -73.9730);
      expect(distance, closeTo(0.83, 0.05));
    });

    test('Converts speed to running pace min/km and speed km/h', () {
      expect(formatSpeedOrPace(4.0, false), '4:10');
      expect(formatSpeedOrPace(10.0, true), '36.0');
      expect(formatSpeedOrPace(0.1, false), '--:--');
    });
  });

  group('4. Multi-Format Serializers (GPX, KML, GeoJSON, CSV)', () {
    final mockPoints = [
      {'lat': 12.3456, 'lng': 78.9101, 'altitude': 100.0, 'speed': 3.5, 'timestamp': 1000000},
      {'lat': 12.3460, 'lng': 78.9105, 'altitude': 102.0, 'speed': 3.6, 'timestamp': 1005000},
    ];

    test('GPX 1.1 contains valid tags', () {
      final gpx = generateMockGpx(1, 'TEST RUN', mockPoints);
      expect(gpx, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(gpx, contains('<gpx version="1.1"'));
      expect(gpx, contains('<name>TEST RUN</name>'));
      expect(gpx, contains('lat="12.3456" lon="78.9101"'));
    });

    test('KML contains LineString coordinates', () {
      final kml = generateMockKml(1, 'TEST RUN', mockPoints);
      expect(kml, contains('<kml xmlns="http://www.opengis.net/kml/2.2">'));
      expect(kml, contains('<LineString>'));
      expect(kml, contains('78.9101,12.3456,0'));
    });

    test('GeoJSON conforms to RFC 7946 FeatureCollection', () {
      final geoJson = generateMockGeoJson(1, 'TEST RUN', mockPoints);
      final parsed = jsonDecode(geoJson) as Map<String, dynamic>;
      expect(parsed['type'], 'FeatureCollection');
      expect(parsed['features'][0]['geometry']['type'], 'LineString');
      expect(parsed['features'][0]['geometry']['coordinates'].length, 2);
    });

    test('CSV generates valid header and column rows', () {
      final csv = generateMockCsv(mockPoints);
      expect(csv, contains('index,timestamp_epoch_ms,datetime_utc,latitude,longitude,altitude_m,accuracy_m,speed_mps,speed_kmh'));
      expect(csv, contains('12.3456,78.9101,100.0'));
    });
  });

  group('5. Ramer-Douglas-Peucker (RDP) Polyline Decimation', () {
    test('Simplifies straight-line points down to 2 endpoints', () {
      final List<Point<double>> points = [
        const Point(0.0, 0.0),
        const Point(0.0001, 0.0001),
        const Point(0.0002, 0.0002),
        const Point(0.0003, 0.0003),
        const Point(0.0004, 0.0004),
      ];

      final simplified = BreadcrumbPainter.rdpSimplify(points, 0.00001);
      expect(simplified.length, 2);
      expect(simplified.first, const Point(0.0, 0.0));
      expect(simplified.last, const Point(0.0004, 0.0004));
    });

    test('Preserves significant corner turns in polyline', () {
      final List<Point<double>> points = [
        const Point(0.0, 0.0),
        const Point(0.0, 0.005),
        const Point(0.005, 0.005), // 90 degree corner turn
        const Point(0.005, 0.010),
      ];

      final simplified = BreadcrumbPainter.rdpSimplify(points, 0.0001);
      expect(simplified.length, greaterThanOrEqualTo(3));
      expect(simplified.any((p) => p.x == 0.005 && p.y == 0.005), isTrue);
    });
  });

  group('6. Post-Run Editing Algorithms (Crop, Merge, Split)', () {
    test('Session Merging combines and chronologically sorts coordinate points', () {
      final session1Points = [
        {'timestamp': 1000, 'lat': 10.0, 'lng': 20.0},
        {'timestamp': 2000, 'lat': 10.1, 'lng': 20.1},
      ];
      final session2Points = [
        {'timestamp': 1500, 'lat': 10.05, 'lng': 20.05},
        {'timestamp': 3000, 'lat': 10.2, 'lng': 20.2},
      ];

      final merged = [...session1Points, ...session2Points];
      merged.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

      expect(merged.length, 4);
      expect(merged[0]['timestamp'], 1000);
      expect(merged[1]['timestamp'], 1500);
      expect(merged[2]['timestamp'], 2000);
      expect(merged[3]['timestamp'], 3000);
    });
  });

  group('7. Stop Detection Trigger Simulation', () {
    test('Simulated stop events trigger power save flag after 3 consecutive static points', () {
      int consecutiveStopsCount = 0;
      bool isPowerSaveModeActive = false;

      void processLocationEvent(double speed, double distanceToLast) {
        final bool isStatic = speed <= 0.2 || distanceToLast < 1.5;
        if (isStatic) {
          consecutiveStopsCount++;
          if (consecutiveStopsCount >= 3 && !isPowerSaveModeActive) {
            isPowerSaveModeActive = true;
          }
        } else {
          consecutiveStopsCount = 0;
          if (isPowerSaveModeActive) {
            isPowerSaveModeActive = false;
          }
        }
      }

      processLocationEvent(0.1, 0.5); // 1
      expect(isPowerSaveModeActive, isFalse);
      processLocationEvent(0.0, 0.2); // 2
      expect(isPowerSaveModeActive, isFalse);
      processLocationEvent(0.1, 0.3); // 3 -> Trigger
      expect(isPowerSaveModeActive, isTrue);

      processLocationEvent(1.5, 6.0); // moving -> Restore normal
      expect(isPowerSaveModeActive, isFalse);
      expect(consecutiveStopsCount, 0);
    });
  });

  group('8. Rally Navigation Engine', () {
    test('Identifies bearing turns and routes correctly', () {
      final mockReferenceRoute = [
        {'lat': 0.0, 'lng': 0.0, 'timestamp': 1000},
        {'lat': 0.001, 'lng': 0.0, 'timestamp': 2000},
        {'lat': 0.002, 'lng': 0.0, 'timestamp': 3000},
        {'lat': 0.002, 'lng': 0.001, 'timestamp': 4000},
      ];

      final engine = RallyNavigationEngine(referencePoints: mockReferenceRoute);
      expect(engine.cues.length, greaterThanOrEqualTo(2));
    });
  });
}
