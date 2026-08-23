import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/services/elevation_filter_service.dart';
import 'package:turnback/services/ble_sensor_service.dart';
import 'package:turnback/services/export_service.dart';

void main() {
  group('ElevationFilterService Kalman & Savitzky-Golay Tests', () {
    test('filters single noisy sample correctly', () {
      final filter = ElevationFilterService.instance;
      filter.reset();

      final first = filter.filterSample(100.0);
      expect(first, equals(100.0));

      final second = filter.filterSample(110.0);
      expect(second, lessThan(110.0));
      expect(second, greaterThan(100.0));
    });

    test('savitzkyGolaySmooth attenuates high-frequency altitude jitter', () {
      final filter = ElevationFilterService.instance;
      final rawAltitudes = [100.0, 108.0, 95.0, 107.0, 98.0, 104.0, 100.0];
      final smoothed = filter.savitzkyGolaySmooth(rawAltitudes);

      expect(smoothed.length, equals(rawAltitudes.length));
      expect(smoothed[0], equals(100.0));
      // Middle points should have reduced variance
      expect(smoothed[3], closeTo(101.5, 3.0));
    });

    test('filterFullElevationProfile runs forward-backward passes gracefully', () {
      final filter = ElevationFilterService.instance;
      final profile = List.generate(20, (i) => 150.0 + sin(i / 3.0) * 15.0 + (i % 2 == 0 ? 3.0 : -3.0));
      final clean = filter.filterFullElevationProfile(profile);

      expect(clean.length, equals(profile.length));
      expect(clean.first, closeTo(150.0, 10.0));
    });
  });

  group('BleSensorService GATT Byte Parsers', () {
    test('parses 8-bit Heart Rate Measurement GATT packet (0x2A37)', () {
      // Flags = 0x00 (8-bit BPM format), BPM = 142 (0x8E)
      final bytes = [0x00, 142];
      final bpm = BleSensorService.parseHeartRateGatt(bytes);
      expect(bpm, equals(142));
    });

    test('parses 16-bit Heart Rate Measurement GATT packet (0x2A37)', () {
      // Flags = 0x01 (16-bit format), BPM = 175 (0xAF, 0x00)
      final bytes = [0x01, 0xAF, 0x00];
      final bpm = BleSensorService.parseHeartRateGatt(bytes);
      expect(bpm, equals(175));
    });

    test('parses Cycling Speed & Cadence (CSC) GATT packet (0x2A5B)', () {
      // Flags = 0x02 (Crank revolution data present)
      // Crank Revs = 100 (0x64, 0x00), Crank Event Time = 1024 (0x00, 0x04 = 1.0 second)
      final bytes = [0x02, 0x64, 0x00, 0x00, 0x04];
      
      // Previous state: 98 revs, event time = 0 (0 seconds)
      final rpm = BleSensorService.parseCadenceGatt(
        bytes,
        previousCrankRevs: 98, // delta = 2 revs in 1 second
        previousCrankTime: 0,
      );

      // 2 revs / 1 second * 60 = 120 RPM
      expect(rpm, equals(120));
    });
  });
}
