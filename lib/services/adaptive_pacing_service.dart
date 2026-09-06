import 'dart:math';

/// Adaptive Battery GPS Polling Profile parameters.
class GpsPollingProfile {
  final int intervalMs;
  final int fastestIntervalMs;
  final double smallestDisplacementMeters;
  final String profileName;

  const GpsPollingProfile({
    required this.intervalMs,
    required this.fastestIntervalMs,
    required this.smallestDisplacementMeters,
    required this.profileName,
  });
}

/// Service implementing speed and curvature-driven GPS polling adjustments,
/// asymmetric fatigue turn-back math, and historical hysteresis scaling.
class AdaptivePacingService {
  static final AdaptivePacingService instance = AdaptivePacingService._();
  AdaptivePacingService._();

  /// Calculates route curvature kappa = |delta_theta / delta_s| (radians / meter).
  ///
  /// [deltaS] is distance in meters between consecutive GPS coordinates.
  /// [prevHeadingRad] is the bearing in radians from the preceding tick.
  /// [currHeadingRad] is the bearing in radians of the current tick.
  static double calculateCurvature({
    required double deltaS,
    required double prevHeadingRad,
    required double currHeadingRad,
  }) {
    if (deltaS <= 0.5) return 0.0;
    final double diff = atan2(sin(currHeadingRad - prevHeadingRad), cos(currHeadingRad - prevHeadingRad));
    return diff.abs() / deltaS;
  }

  /// Evaluates current state and returns the optimal [GpsPollingProfile].
  ///
  /// Rules:
  /// - Motor Vehicle: strictly 1000ms / 500ms / 0m
  /// - Stationary Rest (v <= 0.72 km/h across 3 ticks): 30000ms / 15000ms / 10m
  /// - Curved / Sharp Turns (kappa >= 0.05 OR distanceToManeuver < 80m): 1000ms / 500ms / 2m
  /// - Straight Fast Cruise (v > 15 km/h, kappa < 0.05): 10000ms / 5000ms / 15m
  /// - Standard: 5000ms / 2500ms / 5m
  static GpsPollingProfile evaluatePollingProfile({
    required String activityType,
    required double speedKmh,
    required double curvature,
    required int consecutiveStationaryTicks,
    double? distanceToNextManeuverMeters,
  }) {
    final type = activityType.toLowerCase();
    final bool isMotorVehicle = type.contains('vehicle') ||
        type.contains('drive') ||
        type.contains('car') ||
        type.contains('motor');

    if (isMotorVehicle) {
      return const GpsPollingProfile(
        intervalMs: 1000,
        fastestIntervalMs: 500,
        smallestDisplacementMeters: 0.0,
        profileName: 'Motor Vehicle (Locked 1s)',
      );
    }

    // Stationary Rest: v <= 0.72 km/h across 3 consecutive ticks
    if (consecutiveStationaryTicks >= 3 || (speedKmh <= 0.72 && consecutiveStationaryTicks >= 2)) {
      return const GpsPollingProfile(
        intervalMs: 30000,
        fastestIntervalMs: 15000,
        smallestDisplacementMeters: 10.0,
        profileName: 'Stationary Rest (30s Power Saver)',
      );
    }

    // Curved / Sharp Turns (kappa >= 0.05 OR Distance to Next Maneuver < 80m)
    final bool isCurved = curvature >= 0.05;
    final bool nearManeuver = distanceToNextManeuverMeters != null && distanceToNextManeuverMeters < 80.0;
    if (isCurved || nearManeuver) {
      return const GpsPollingProfile(
        intervalMs: 1000,
        fastestIntervalMs: 500,
        smallestDisplacementMeters: 2.0,
        profileName: 'Curved / Sharp Turn (1s High Frequency)',
      );
    }

    // Straight Fast Cruise (v > 15 km/h, kappa < 0.05)
    if (speedKmh > 15.0 && curvature < 0.05) {
      return const GpsPollingProfile(
        intervalMs: 10000,
        fastestIntervalMs: 5000,
        smallestDisplacementMeters: 15.0,
        profileName: 'Straight Fast Cruise (10s Economy)',
      );
    }

    // Standard activity tracking
    return const GpsPollingProfile(
      intervalMs: 5000,
      fastestIntervalMs: 2500,
      smallestDisplacementMeters: 5.0,
      profileName: 'Standard Adaptive GPS',
    );
  }

  /// Calculates the asymmetric fatigue turn-back outbound limit in seconds:
  ///
  /// T_outbound = T_target / (1 + S * gamma)
  /// where S = 1.0 + (safetyBufferPct / 100.0) [default 8% buffer => S = 1.08]
  /// and gamma = 1.15 (15% fatigue decay) for athletic activities, or gamma = 1.0 for motor vehicles.
  ///
  /// For S = 1.08, gamma = 1.15: 1 + S * gamma = 2.242 => ~44.603% of total target duration.
  static int calculateAsymmetricOutboundLimitSeconds({
    required int targetDurationSeconds,
    double safetyBufferPct = 8.0,
    bool isMotorVehicle = false,
  }) {
    if (targetDurationSeconds <= 0) return 0;
    final double s = 1.0 + (safetyBufferPct / 100.0);
    final double gamma = isMotorVehicle ? 1.0 : 1.15;
    final double divisor = 1.0 + (s * gamma);
    return (targetDurationSeconds / divisor).round();
  }

  /// Dynamically scales unit switching hysteresis window ticks based on activity type
  /// and the ratio R = D_target / D_base (where D_base is rolling median distance over last 10 activities).
  ///
  /// - Cycling: Short (R < 0.8): 2 Ticks | Standard (0.8 <= R <= 1.2): 5 Ticks | Stretch (R > 1.2): 8 Ticks
  /// - Running: Short: 1 Tick | Standard: 3 Ticks | Stretch: 6 Ticks
  /// - Walking / Hiking: Short: 1 Tick | Standard: 3 Ticks | Stretch: 6 Ticks
  /// - Motor Vehicle: Locked strictly to 0 Ticks (Zero Hysteresis)
  static int calculateAdaptiveHysteresisTicks({
    required String activityType,
    required double ratio,
  }) {
    final type = activityType.toLowerCase();

    // Motor Vehicle: strictly 0 ticks (instantaneous unit switching)
    if (type.contains('vehicle') || type.contains('drive') || type.contains('car') || type.contains('motor')) {
      return 0;
    }

    // Cycling
    if (type.contains('ride') || type.contains('cycle') || type.contains('bike')) {
      if (ratio < 0.8) return 2;
      if (ratio <= 1.2) return 5;
      return 8;
    }

    // Running
    if (type.contains('run') || type.contains('jog')) {
      if (ratio < 0.8) return 1;
      if (ratio <= 1.2) return 3;
      return 6;
    }

    // Walking / Hiking
    if (ratio < 0.8) return 1;
    if (ratio <= 1.2) return 3;
    return 6;
  }

  /// Smooths heading transitions for course-up map alignment using a rolling low-pass filter (alpha = 0.15).
  ///
  /// theta_next = theta_prev + alpha * delta_theta (wrapping across -pi to pi).
  static double filterHeading({
    required double currentSmoothedRad,
    required double targetHeadingRad,
    double alpha = 0.15,
  }) {
    final double delta = atan2(sin(targetHeadingRad - currentSmoothedRad), cos(targetHeadingRad - currentSmoothedRad));
    return currentSmoothedRad + (alpha * delta);
  }
}
