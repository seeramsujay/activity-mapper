import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/models/location_point.dart';
import 'package:turnback/services/track_gradient_service.dart';

void main() {
  group('TrackGradientService', () {
    test('speedToColor maps lowest speed to cyan and highest to red', () {
      final cMin = TrackGradientService.speedToColor(0.0,
          minSpeedMps: 0.0, maxSpeedMps: 10.0);
      final cMax = TrackGradientService.speedToColor(10.0,
          minSpeedMps: 0.0, maxSpeedMps: 10.0);

      expect(cMin, equals(TrackGradientService.speedColorLow));
      expect(cMax, equals(TrackGradientService.speedColorMax));
    });

    test('elevationToColor maps minimum to teal and maximum to summit peak',
        () {
      final cLow = TrackGradientService.elevationToColor(100.0,
          minAltMeters: 100.0, maxAltMeters: 1000.0);
      final cHigh = TrackGradientService.elevationToColor(1000.0,
          minAltMeters: 100.0, maxAltMeters: 1000.0);

      expect(cLow, equals(TrackGradientService.elevColorLow));
      expect(cHigh, equals(TrackGradientService.elevColorPeak));
    });

    test('computeSegmentColors returns matching number of segments', () {
      final points = [
        LocationPoint(
          sessionId: 1,
          timestamp: DateTime.now(),
          lat: 12.0,
          lng: 77.0,
          altitude: 100.0,
          accuracy: 5.0,
          speed: 2.0,
        ),
        LocationPoint(
          sessionId: 1,
          timestamp: DateTime.now().add(const Duration(seconds: 1)),
          lat: 12.01,
          lng: 77.01,
          altitude: 150.0,
          accuracy: 5.0,
          speed: 5.0,
        ),
        LocationPoint(
          sessionId: 1,
          timestamp: DateTime.now().add(const Duration(seconds: 2)),
          lat: 12.02,
          lng: 77.02,
          altitude: 200.0,
          accuracy: 5.0,
          speed: 8.0,
        ),
      ];

      final solidColors = TrackGradientService.computeSegmentColors(
        points: points,
        mode: TrackColorMode.solid,
        defaultColor: Colors.blue,
      );
      expect(solidColors.length, equals(2));
      expect(solidColors.every((c) => c == Colors.blue), isTrue);

      final speedColors = TrackGradientService.computeSegmentColors(
        points: points,
        mode: TrackColorMode.speed,
        defaultColor: Colors.blue,
      );
      expect(speedColors.length, equals(2));
      // First segment (avg speed 3.5) vs second segment (avg speed 6.5)
      expect(speedColors[0] != speedColors[1], isTrue);

      final elevColors = TrackGradientService.computeSegmentColors(
        points: points,
        mode: TrackColorMode.elevation,
        defaultColor: Colors.blue,
      );
      expect(elevColors.length, equals(2));
      expect(elevColors[0] != elevColors[1], isTrue);
    });
  });
}
