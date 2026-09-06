import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/services/adaptive_pacing_service.dart';
import 'package:turnback/services/exercise_stats_service.dart';

void main() {
  group('AdaptivePacingService - Curvature & Polling Engine', () {
    test('calculateCurvature returns 0 when displacement is too small', () {
      final k = AdaptivePacingService.calculateCurvature(
        deltaS: 0.2, // Below 0.5m threshold
        prevHeadingRad: 0.0,
        currHeadingRad: pi / 2,
      );
      expect(k, equals(0.0));
    });

    test('calculateCurvature returns 0 when heading does not change', () {
      final k = AdaptivePacingService.calculateCurvature(
        deltaS: 10.0,
        prevHeadingRad: pi / 4,
        currHeadingRad: pi / 4,
      );
      expect(k, equals(0.0));
    });

    test('calculateCurvature computes correct radians per meter on 90-degree turn', () {
      // 90 degrees = pi / 2 radians ≈ 1.570796 rad
      // Over 10 meters, curvature should be 1.570796 / 10 ≈ 0.157 rad/m
      final k = AdaptivePacingService.calculateCurvature(
        deltaS: 10.0,
        prevHeadingRad: 0.0,
        currHeadingRad: pi / 2,
      );
      expect(k, closeTo(pi / 2 / 10.0, 0.001));
      expect(k, greaterThanOrEqualTo(0.05)); // High curvature threshold
    });

    test('evaluatePollingProfile enforces strict 1s polling for motor vehicle', () {
      final profile = AdaptivePacingService.evaluatePollingProfile(
        activityType: 'motor_vehicle',
        speedKmh: 90.0,
        curvature: 0.01,
        consecutiveStationaryTicks: 0,
      );
      expect(profile.intervalMs, equals(1000));
      expect(profile.fastestIntervalMs, equals(500));
      expect(profile.smallestDisplacementMeters, equals(0.0));
    });

    test('evaluatePollingProfile activates sharp turn profile on high curvature', () {
      final profile = AdaptivePacingService.evaluatePollingProfile(
        activityType: 'run',
        speedKmh: 12.0,
        curvature: 0.06, // >= 0.05 threshold
        consecutiveStationaryTicks: 0,
      );
      expect(profile.intervalMs, equals(1000));
      expect(profile.fastestIntervalMs, equals(500));
      expect(profile.smallestDisplacementMeters, equals(2.0));
    });

    test('evaluatePollingProfile activates sharp turn profile when near maneuver point', () {
      final profile = AdaptivePacingService.evaluatePollingProfile(
        activityType: 'ride',
        speedKmh: 22.0,
        curvature: 0.01, // Straight road
        consecutiveStationaryTicks: 0,
        distanceToNextManeuverMeters: 50.0, // < 80m threshold
      );
      expect(profile.intervalMs, equals(1000));
      expect(profile.fastestIntervalMs, equals(500));
      expect(profile.smallestDisplacementMeters, equals(2.0));
    });

    test('evaluatePollingProfile uses stationary profile when stopped across 3 ticks', () {
      final profile = AdaptivePacingService.evaluatePollingProfile(
        activityType: 'walk',
        speedKmh: 0.5,
        curvature: 0.0,
        consecutiveStationaryTicks: 3,
      );
      expect(profile.intervalMs, equals(30000));
      expect(profile.fastestIntervalMs, equals(15000));
      expect(profile.smallestDisplacementMeters, equals(10.0));
    });

    test('evaluatePollingProfile uses fast cruise profile for high cycling speeds', () {
      final profile = AdaptivePacingService.evaluatePollingProfile(
        activityType: 'ride',
        speedKmh: 28.0, // > 15 km/h
        curvature: 0.01, // Straight
        consecutiveStationaryTicks: 0,
      );
      expect(profile.intervalMs, equals(10000));
      expect(profile.fastestIntervalMs, equals(5000));
      expect(profile.smallestDisplacementMeters, equals(15.0));
    });

    test('evaluatePollingProfile uses standard profile for normal run on straight road', () {
      final profile = AdaptivePacingService.evaluatePollingProfile(
        activityType: 'run',
        speedKmh: 11.0,
        curvature: 0.01,
        consecutiveStationaryTicks: 0,
      );
      expect(profile.intervalMs, equals(5000));
      expect(profile.fastestIntervalMs, equals(2500));
      expect(profile.smallestDisplacementMeters, equals(5.0));
    });
  });

  group('AdaptivePacingService - Asymmetric Fatigue & Hysteresis Math', () {
    test('calculateAsymmetricOutboundLimitSeconds accounts for 15% return fatigue', () {
      const targetSec = 5400; // 90 minutes
      const bufferPct = 8.0;

      final outboundSecHuman = AdaptivePacingService.calculateAsymmetricOutboundLimitSeconds(
        targetDurationSeconds: targetSec,
        safetyBufferPct: bufferPct,
        isMotorVehicle: false,
      );

      final outboundSecMotor = AdaptivePacingService.calculateAsymmetricOutboundLimitSeconds(
        targetDurationSeconds: targetSec,
        safetyBufferPct: bufferPct,
        isMotorVehicle: true,
      );

      // s = 1.0 + (8 / 100) = 1.08
      // Human: gamma = 1.15 -> divisor = 1.0 + (1.08 * 1.15) = 2.242 -> 5400 / 2.242 ≈ 2409 seconds
      expect(outboundSecHuman, equals(2409));

      // Motor: gamma = 1.0 -> divisor = 1.0 + (1.08 * 1.0) = 2.08 -> 5400 / 2.08 ≈ 2596 seconds
      expect(outboundSecMotor, equals(2596));

      // Human outbound must be strictly less than motor outbound due to fatigue penalty
      expect(outboundSecHuman, lessThan(outboundSecMotor));
    });

    test('calculateAdaptiveHysteresisTicks scales correctly across activity types and ratios', () {
      // Motor Vehicle: strictly 0 ticks regardless of ratio
      expect(
        AdaptivePacingService.calculateAdaptiveHysteresisTicks(
          activityType: 'motor_vehicle',
          ratio: 1.5,
        ),
        equals(0),
      );

      // Cycling: Short (<0.8): 2 | Standard (0.8-1.2): 5 | Stretch (>1.2): 8
      expect(
        AdaptivePacingService.calculateAdaptiveHysteresisTicks(
          activityType: 'ride',
          ratio: 0.6,
        ),
        equals(2),
      );
      expect(
        AdaptivePacingService.calculateAdaptiveHysteresisTicks(
          activityType: 'ride',
          ratio: 1.0,
        ),
        equals(5),
      );
      expect(
        AdaptivePacingService.calculateAdaptiveHysteresisTicks(
          activityType: 'ride',
          ratio: 1.5,
        ),
        equals(8),
      );

      // Running: Short: 1 | Standard: 3 | Stretch: 6
      expect(
        AdaptivePacingService.calculateAdaptiveHysteresisTicks(
          activityType: 'run',
          ratio: 0.5,
        ),
        equals(1),
      );
      expect(
        AdaptivePacingService.calculateAdaptiveHysteresisTicks(
          activityType: 'run',
          ratio: 1.0,
        ),
        equals(3),
      );
      expect(
        AdaptivePacingService.calculateAdaptiveHysteresisTicks(
          activityType: 'run',
          ratio: 2.0,
        ),
        equals(6),
      );
    });

    test('filterHeading applies low-pass smoothing across angle wrap-around', () {
      // Starting heading: 0.0 rad, target: 0.5 rad, alpha: 0.15
      final smoothed = AdaptivePacingService.filterHeading(
        currentSmoothedRad: 0.0,
        targetHeadingRad: 0.5,
        alpha: 0.15,
      );
      expect(smoothed, closeTo(0.075, 0.001));

      // Wrap-around across +/- pi
      final wrapSmoothed = AdaptivePacingService.filterHeading(
        currentSmoothedRad: 3.10, // ~177 deg
        targetHeadingRad: -3.10, // ~ -177 deg
        alpha: 0.5,
      );
      expect(wrapSmoothed, isNotNull);
    });
  });

  group('ExerciseStatsService - MET & Calorie Calculations', () {
    test('estimateMet returns accurate values across speeds and activities', () {
      expect(ExerciseStatsService.estimateMet(activityType: 'motor_vehicle', speedKmh: 60.0), equals(1.5));
      expect(ExerciseStatsService.estimateMet(activityType: 'walk', speedKmh: 4.0), equals(3.0));
      expect(ExerciseStatsService.estimateMet(activityType: 'walk', speedKmh: 5.5), equals(3.8));
      expect(ExerciseStatsService.estimateMet(activityType: 'run', speedKmh: 9.5), equals(9.8));
      expect(ExerciseStatsService.estimateMet(activityType: 'ride', speedKmh: 18.0), equals(8.0));
    });

    test('calculateCaloriesBurnt returns sedentary baseline (1.5 MET) for motor vehicle', () {
      final cal = ExerciseStatsService.calculateCaloriesBurnt(
        activityType: 'motor_vehicle',
        distanceKm: 50.0,
        movingDuration: const Duration(hours: 1),
        userWeightKg: 70.0,
      );
      // 1.5 MET * 70kg * 1 hr = 105 kcal
      expect(cal, equals(105.0));
    });

    test('calculateCaloriesBurnt factors in elevation gain and user weight', () {
      final flatCal = ExerciseStatsService.calculateCaloriesBurnt(
        activityType: 'run',
        distanceKm: 10.0,
        movingDuration: const Duration(hours: 1),
        userWeightKg: 70.0,
        elevationGainMeters: 0.0,
      );

      final hillyCal = ExerciseStatsService.calculateCaloriesBurnt(
        activityType: 'run',
        distanceKm: 10.0,
        movingDuration: const Duration(hours: 1),
        userWeightKg: 70.0,
        elevationGainMeters: 200.0,
      );

      expect(flatCal, greaterThan(600.0));
      expect(hillyCal, greaterThan(flatCal)); // Elevation increases burn
    });
  });
}
