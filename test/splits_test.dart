import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/services/exercise_stats_service.dart';

void main() {
  test('computeSplits divides track into 1-km splits', () {
    // 3 points creating ~2.5 km of distance
    final points = <Map<String, dynamic>>[
      {
        'lat': 12.0,
        'lng': 77.0,
        'timestamp': 0,
        'speed': 3.5,
        'altitude': 100.0
      },
      {
        'lat': 12.01,
        'lng': 77.0,
        'timestamp': 300000,
        'speed': 3.5,
        'altitude': 110.0
      }, // ~1.11 km, 5 min
      {
        'lat': 12.02,
        'lng': 77.0,
        'timestamp': 600000,
        'speed': 3.5,
        'altitude': 120.0
      }, // ~2.22 km, 10 min
    ];

    final splits = ExerciseStatsService.computeSplits(points);
    expect(splits.length, greaterThanOrEqualTo(2));
    expect(splits[0].number, equals(1));
    expect(splits[1].number, equals(2));
    expect(splits[0].distanceKm, closeTo(1.0, 0.2));
  });
}
