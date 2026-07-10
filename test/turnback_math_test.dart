import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

// -----------------------------------------------------------------------------
// Core Algorithms extracted from UI/Services for isolated mathematical testing
// -----------------------------------------------------------------------------

double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
  const p = 0.017453292519943295;
  final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
        (1 - cos((lon2 - lon1) * p)) / 2;
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
      // 5400s * (92/200) = 2484s (41.4m elapsed / 48.6m remaining)
      expect(limit, 2484);
      expect(limit / 60, 41.4);
    });

    test('Zero percent buffer evaluates to exactly 50/50 time division', () {
      final int limit = calculateOutboundLimitSeconds(100 * 60, 0.0);
      // 6000s * (100/200) = 3000s (50m elapsed)
      expect(limit, 3000);
      expect(limit / 60, 50.0);
    });

    test('Maximum 20 percent buffer allocates larger safety cushion for return leg', () {
      final int limit = calculateOutboundLimitSeconds(60 * 60, 20.0);
      // 3600s * (80/200) = 1440s (24m elapsed / 36m remaining)
      expect(limit, 1440);
      expect(limit / 60, 24.0);
    });

    test('Short target duration boundary checks', () {
      final int limit = calculateOutboundLimitSeconds(10 * 60, 10.0);
      // 600s * (90/200) = 270s (4.5m elapsed)
      expect(limit, 270);
    });
  });

  group('2. Speed Hysteresis State Machine', () {
    test('Start in Pace mode: stays in Pace for less than 5 high-speed ticks', () {
      final tracker = SpeedHysteresisTracker(isSpeedMode: false);
      
      // Feed 4 consecutive speed samples exceeding 18km/h (5.0 m/s)
      for (int i = 0; i < 4; i++) {
        tracker.addSpeedSample(5.5);
        expect(tracker.isSpeedMode, isFalse, reason: 'Tick ${i + 1} should not trigger change');
      }
    });

    test('Start in Pace mode: switches to Speed on exactly the 5th consecutive high-speed tick', () {
      final tracker = SpeedHysteresisTracker(isSpeedMode: false);
      
      for (int i = 0; i < 4; i++) {
        tracker.addSpeedSample(5.5);
      }
      
      // 5th tick
      tracker.addSpeedSample(5.5);
      expect(tracker.isSpeedMode, isTrue, reason: '5th consecutive tick must trigger mode swap');
    });

    test('Intermittent speed drops reset the consecutive ticks counter', () {
      final tracker = SpeedHysteresisTracker(isSpeedMode: false);
      
      tracker.addSpeedSample(6.0); // T1
      tracker.addSpeedSample(6.0); // T2
      tracker.addSpeedSample(6.0); // T3
      tracker.addSpeedSample(3.0); // Drops below threshold!
      
      expect(tracker.consecutiveSpeedTicks, 0, reason: 'Counter must be reset to zero on threshold breach');
      expect(tracker.isSpeedMode, isFalse);
    });

    test('Start in Speed mode: reverts to Pace on exactly the 5th low-speed tick', () {
      final tracker = SpeedHysteresisTracker(isSpeedMode: true);
      
      // Feed 4 slow speed samples
      for (int i = 0; i < 4; i++) {
        tracker.addSpeedSample(2.5);
        expect(tracker.isSpeedMode, isTrue);
      }

      // 5th tick
      tracker.addSpeedSample(2.5);
      expect(tracker.isSpeedMode, isFalse, reason: 'Must revert to Pace mode after 5 consecutive slow ticks');
    });
  });

  group('3. Haversine Distance Calculator', () {
    test('Calculates distance between coordinates correctly (Sanity verification)', () {
      // Coordinates of Central Park South-West to South-East corners (~0.8 km)
      final double distance = calculateDistanceKm(40.7679, -73.9818, 40.7644, -73.9730);
      expect(distance, closeTo(0.83, 0.05));
    });

    test('Zero distance calculation for identical coordinates', () {
      final double distance = calculateDistanceKm(37.7749, -122.4194, 37.7749, -122.4194);
      expect(distance, 0.0);
    });
  });

  group('4. Metrics Speed & Pace Formatter', () {
    test('Displays --:-- or 0.0 for near-stationary movements', () {
      expect(formatSpeedOrPace(0.0, true), '0.0');
      expect(formatSpeedOrPace(0.1, false), '--:--');
    });

    test('Converts speed to running pace min/km correctly', () {
      // 4.0 m/s = 14.4 km/h -> Pace: 1000m / 4m/s = 250 seconds = 4m 10s
      expect(formatSpeedOrPace(4.0, false), '4:10');
      
      // 2.78 m/s = 10.0 km/h -> Pace: 1000m / 2.78m/s = 360 seconds = 6m 00s
      expect(formatSpeedOrPace(2.778, false), '6:00');
    });

    test('Converts speed to cycling km/h correctly', () {
      // 10.0 m/s = 36 km/h
      expect(formatSpeedOrPace(10.0, true), '36.0');
      
      // 5.5 m/s = 19.8 km/h
      expect(formatSpeedOrPace(5.5, true), '19.8');
    });
  });

  group('5. GPX Serializer Output validation', () {
    test('GPX output contains valid XML structure and metadata nodes', () {
      final mockPoints = [
        {'lat': 12.3456, 'lng': 78.9101, 'speed': 3.5},
        {'lat': 12.3460, 'lng': 78.9105, 'speed': 3.6},
      ];
      
      final String gpx = generateMockGpx(1, 'TEST RUN', mockPoints);
      
      expect(gpx, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(gpx, contains('<gpx version="1.1"'));
      expect(gpx, contains('<name>TEST RUN</name>'));
      expect(gpx, contains('lat="12.3456" lon="78.9101"'));
      expect(gpx, contains('lat="12.346" lon="78.9105"'));
      expect(gpx, contains('</trkseg>'));
    });
  });

  group('6. Equal Parts N-Chopper math calculations', () {
    test('Calculates start/end index boundaries for N=3 parts from 10 points', () {
      final List<int> points = List.generate(10, (i) => i);
      const int partsCount = 3;
      final int pointsPerSegment = (points.length / partsCount).ceil(); // 4
      
      expect(pointsPerSegment, 4);
      
      final List<List<int>> segments = [];
      for (int i = 0; i < partsCount; i++) {
        final int start = i * pointsPerSegment;
        final int end = min(start + pointsPerSegment, points.length);
        if (start < points.length) {
          segments.add(points.sublist(start, end));
        }
      }
      
      expect(segments.length, 3);
      expect(segments[0], [0, 1, 2, 3]);
      expect(segments[1], [4, 5, 6, 7]);
      expect(segments[2], [8, 9]);
    });
  });

  group('7. Time-Duration Chopper calculator test', () {
    test('Splits 9 coordinate points into 2-minute time chunks', () {
      final List<Map<String, dynamic>> mockPoints = List.generate(9, (i) => {
        'timestamp': i * 30 * 1000, // 30s steps
        'lat': 10.0 + i,
        'lng': 20.0 + i
      });
      
      const double chunkMs = 2.0 * 60 * 1000; // 120000ms
      final int startMs = mockPoints.first['timestamp'] as int;
      
      final List<List<Map<String, dynamic>>> chunks = [];
      int index = 0;
      int chunkIdx = 1;
      
      while (index < mockPoints.length) {
        final double segmentStartMs = startMs + (chunkIdx - 1) * chunkMs;
        final double segmentEndMs = segmentStartMs + chunkMs;
        final List<Map<String, dynamic>> segmentPoints = [];
        
        while (index < mockPoints.length) {
          final int pointTime = mockPoints[index]['timestamp'] as int;
          if (pointTime >= segmentStartMs && pointTime < segmentEndMs) {
            segmentPoints.add(mockPoints[index]);
            index++;
          } else {
            break;
          }
        }
        if (segmentPoints.isNotEmpty) {
          chunks.add(segmentPoints);
        }
        chunkIdx++;
      }
      
      expect(chunks.length, 3);
      expect(chunks[0].length, 4); // 0s, 30s, 60s, 90s
      expect(chunks[1].length, 4); // 120s, 150s, 180s, 210s
      expect(chunks[2].length, 1); // 240s
    });
  });

  group('8. Stop Detection trigger simulation', () {
    test('Simulated stop events trigger power save flags on 3 consecutive static points', () {
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
      
      // Tick 1: stationary
      processLocationEvent(0.1, 0.5);
      expect(isPowerSaveModeActive, isFalse);
      expect(consecutiveStopsCount, 1);
      
      // Tick 2: stationary
      processLocationEvent(0.0, 0.2);
      expect(isPowerSaveModeActive, isFalse);
      expect(consecutiveStopsCount, 2);
      
      // Tick 3: stationary -> Trigger Power Save
      processLocationEvent(0.1, 0.3);
      expect(isPowerSaveModeActive, isTrue);
      expect(consecutiveStopsCount, 3);
      
      // Tick 4: moving -> Restore standard mode
      processLocationEvent(1.2, 5.8);
      expect(isPowerSaveModeActive, isFalse);
      expect(consecutiveStopsCount, 0);
    });
  });
}
