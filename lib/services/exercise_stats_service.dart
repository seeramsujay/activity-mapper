import 'dart:math';

/// Immutable model holding comprehensive exercise and telemetry statistics.
class ExerciseStats {
  final double distanceKm;
  final Duration totalDuration;
  final Duration movingDuration;
  final double activeMovingRatio; // 0.0 to 1.0
  final double caloriesBurntKcal;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final String avgPaceMinKm;
  final String bestPaceMinKm;
  final double bestMovingSpeedKmh;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final double minAltitudeMeters;
  final double maxAltitudeMeters;
  final double avgAltitudeMeters;
  final int? avgHeartRateBpm;
  final int? maxHeartRateBpm;
  final int? avgCadenceRpm;
  final int totalTrackpoints;
  final double? turnBackDistanceKm;
  final DateTime? turnBackTriggeredAt;

  const ExerciseStats({
    required this.distanceKm,
    required this.totalDuration,
    required this.movingDuration,
    required this.activeMovingRatio,
    required this.caloriesBurntKcal,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.avgPaceMinKm,
    required this.bestPaceMinKm,
    this.bestMovingSpeedKmh = 0.0,
    required this.elevationGainMeters,
    required this.elevationLossMeters,
    required this.minAltitudeMeters,
    required this.maxAltitudeMeters,
    required this.avgAltitudeMeters,
    this.avgHeartRateBpm,
    this.maxHeartRateBpm,
    this.avgCadenceRpm,
    required this.totalTrackpoints,
    this.turnBackDistanceKm,
    this.turnBackTriggeredAt,
  });

  /// Duration spent paused or stationary.
  Duration get stoppedDuration {
    final diff = totalDuration - movingDuration;
    return diff.isNegative ? Duration.zero : diff;
  }
}

/// Represents a fixed-distance interval split (e.g. 1.0 km or 1.0 mile).
class SplitLap {
  final int number;
  final double distanceKm;
  final Duration duration;
  final double avgSpeedKmh;
  final String paceMinKm;
  final double elevationGainMeters;
  final double elevationLossMeters;

  const SplitLap({
    required this.number,
    required this.distanceKm,
    required this.duration,
    required this.avgSpeedKmh,
    required this.paceMinKm,
    this.elevationGainMeters = 0.0,
    this.elevationLossMeters = 0.0,
  });

  Map<String, dynamic> toMap() => {
        'number': number,
        'distanceKm': distanceKm,
        'durationMs': duration.inMilliseconds,
        'avgSpeedKmh': avgSpeedKmh,
        'paceMinKm': paceMinKm,
        'elevationGainMeters': elevationGainMeters,
        'elevationLossMeters': elevationLossMeters,
      };
}

/// Service computing energy expenditure (MET calories) and endurance metrics.
class ExerciseStatsService {
  static final ExerciseStatsService instance = ExerciseStatsService._();
  ExerciseStatsService._();

  /// Calculates metabolic calories burnt (kcal) based on activity type, distance, moving time,
  /// elevation gain, and user weight.
  static double calculateCaloriesBurnt({
    required String activityType,
    required double distanceKm,
    required Duration movingDuration,
    double elevationGainMeters = 0.0,
    double userWeightKg = 70.0,
  }) {
    if (distanceKm <= 0.0 && movingDuration.inSeconds <= 0) return 0.0;
    final hours = movingDuration.inSeconds / 3600.0;
    final type = activityType.toLowerCase();

    // 1. Motor Vehicle / Driving: Low baseline sedentary MET (~1.5)
    if (type.contains('vehicle') ||
        type.contains('drive') ||
        type.contains('car') ||
        type.contains('motor')) {
      return (1.5 * userWeightKg * hours).clamp(0.0, 10000.0);
    }

    // 2. Running: Net energy expenditure ~1.036 kcal per kg per km
    if (type.contains('run') || type.contains('jog')) {
      final baseKcal = distanceKm * userWeightKg * 1.036;
      final verticalKcal = elevationGainMeters * userWeightKg * 0.0015;
      return (baseKcal + verticalKcal).clamp(0.0, 20000.0);
    }

    // 3. Cycling: Speed-dependent aerodynamic power MET formulation
    if (type.contains('ride') ||
        type.contains('cycle') ||
        type.contains('bike')) {
      final avgSpeed = hours > 0 ? (distanceKm / hours) : 0.0;
      double met;
      if (avgSpeed < 16.0) {
        met = 6.0;
      } else if (avgSpeed < 20.0) {
        met = 8.0;
      } else if (avgSpeed < 25.0) {
        met = 10.0;
      } else if (avgSpeed < 30.0) {
        met = 12.0;
      } else {
        met = 15.0;
      }
      final baseKcal = met * userWeightKg * hours;
      final verticalKcal = elevationGainMeters * userWeightKg * 0.0018;
      return (baseKcal + verticalKcal).clamp(0.0, 25000.0);
    }

    // 4. Walking / Hiking: Baseline 0.75 kcal/kg/km with strong elevation work component
    final baseKcal = distanceKm * userWeightKg * 0.75;
    final verticalKcal = elevationGainMeters * userWeightKg * 0.0025;
    return (baseKcal + verticalKcal).clamp(0.0, 15000.0);
  }

  /// Estimates metabolic equivalent of task (MET) from speed and activity type.
  static double estimateMet({
    required String activityType,
    required double speedKmh,
  }) {
    final type = activityType.toLowerCase();
    if (type.contains('vehicle') ||
        type.contains('drive') ||
        type.contains('car') ||
        type.contains('motor')) {
      return 1.5;
    }
    if (type.contains('run') || type.contains('jog')) {
      if (speedKmh <= 8.0) return 8.3;
      if (speedKmh <= 9.7) return 9.8;
      if (speedKmh <= 11.3) return 11.0;
      if (speedKmh <= 12.9) return 11.8;
      if (speedKmh <= 14.5) return 12.8;
      return 14.5;
    }
    if (type.contains('ride') ||
        type.contains('cycle') ||
        type.contains('bike')) {
      if (speedKmh < 16.0) return 6.0;
      if (speedKmh < 20.0) return 8.0;
      if (speedKmh < 25.0) return 10.0;
      if (speedKmh < 30.0) return 12.0;
      return 15.0;
    }
    if (speedKmh <= 4.0) return 3.0;
    if (speedKmh <= 5.5) return 3.8;
    if (speedKmh <= 7.0) return 5.0;
    return 7.0;
  }

  /// Formats speed in m/s into running pace string (mm:ss min/km).
  static String formatPaceFromMps(double mps) {
    if (mps <= 0.2) return '--:--';
    final secPerKm = 1000.0 / mps;
    final min = secPerKm ~/ 60;
    final sec = (secPerKm % 60).round();
    if (min > 99) return '--:--';
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  /// Helper to extract epoch milliseconds from diverse timestamp types (int, String, DateTime).
  static int _extractTimestampMs(dynamic ts) {
    if (ts is int) return ts;
    if (ts is num) return ts.toInt();
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    if (ts is String) {
      final parsedInt = int.tryParse(ts);
      if (parsedInt != null) return parsedInt;
      final parsedDate = DateTime.tryParse(ts);
      if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
    }
    return 0;
  }

  /// Divides [points] into sequential distance splits (default 1.0 km interval).
  static List<SplitLap> computeSplits(
    List<Map<String, dynamic>> points, {
    double splitIntervalKm = 1.0,
  }) {
    if (points.length < 2 || splitIntervalKm <= 0.0) return [];

    final splits = <SplitLap>[];
    int currentLapNumber = 1;
    double currentLapDist = 0.0;
    double currentLapDurationMs = 0.0;
    double currentLapGain = 0.0;
    double currentLapLoss = 0.0;

    const p = 0.017453292519943295;

    for (int i = 1; i < points.length; i++) {
      final pPrev = points[i - 1];
      final pCur = points[i];

      final lat1 = (pPrev['lat'] as num).toDouble();
      final lon1 = (pPrev['lng'] as num).toDouble();
      final lat2 = (pCur['lat'] as num).toDouble();
      final lon2 = (pCur['lng'] as num).toDouble();

      final a = 0.5 -
          cos((lat2 - lat1) * p) / 2 +
          cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
      double segDist = 12742 * asin(sqrt(a));

      final t1 = _extractTimestampMs(pPrev['timestamp']);
      final t2 = _extractTimestampMs(pCur['timestamp']);
      double segDt = (t2 > t1) ? (t2 - t1).toDouble() : 0.0;

      final alt1 = (pPrev['altitude'] as num?)?.toDouble() ?? 0.0;
      final alt2 = (pCur['altitude'] as num?)?.toDouble() ?? 0.0;
      final dAlt = alt2 - alt1;

      while (segDist > 0 && (currentLapDist + segDist) >= splitIntervalKm) {
        final needed = splitIntervalKm - currentLapDist;
        final ratio = (segDist > 0) ? (needed / segDist).clamp(0.0, 1.0) : 1.0;
        final dtPart = segDt * ratio;

        currentLapDist += needed;
        currentLapDurationMs += dtPart;
        if (dAlt > 0) {
          currentLapGain += dAlt * ratio;
        } else if (dAlt < 0) {
          currentLapLoss += (-dAlt) * ratio;
        }

        final dur = Duration(milliseconds: currentLapDurationMs.round());
        final durHours = currentLapDurationMs / 3600000.0;
        final speedKmh = durHours > 0 ? (currentLapDist / durHours) : 0.0;
        final paceMps = currentLapDurationMs > 0
            ? (currentLapDist * 1000.0) / (currentLapDurationMs / 1000.0)
            : 0.0;

        splits.add(SplitLap(
          number: currentLapNumber++,
          distanceKm: currentLapDist,
          duration: dur,
          avgSpeedKmh: speedKmh,
          paceMinKm: formatPaceFromMps(paceMps),
          elevationGainMeters: currentLapGain,
          elevationLossMeters: currentLapLoss,
        ));

        segDist -= needed;
        segDt -= dtPart;
        currentLapDist = 0.0;
        currentLapDurationMs = 0.0;
        currentLapGain = 0.0;
        currentLapLoss = 0.0;
      }

      if (segDist > 0) {
        currentLapDist += segDist;
        currentLapDurationMs += segDt;
        if (dAlt > 0) {
          currentLapGain += dAlt;
        } else if (dAlt < 0) {
          currentLapLoss += (-dAlt);
        }
      }
    }

    if (currentLapDist >= 0.05) {
      final dur = Duration(milliseconds: currentLapDurationMs.round());
      final durHours = currentLapDurationMs / 3600000.0;
      final speedKmh = durHours > 0 ? (currentLapDist / durHours) : 0.0;
      final paceMps = currentLapDurationMs > 0
          ? (currentLapDist * 1000.0) / (currentLapDurationMs / 1000.0)
          : 0.0;

      splits.add(SplitLap(
        number: currentLapNumber,
        distanceKm: currentLapDist,
        duration: dur,
        avgSpeedKmh: speedKmh,
        paceMinKm: formatPaceFromMps(paceMps),
        elevationGainMeters: currentLapGain,
        elevationLossMeters: currentLapLoss,
      ));
    }

    return splits;
  }

  /// Computes full [ExerciseStats] from a list of raw point maps from SQLite.
  static ExerciseStats computeSessionStats({
    required List<Map<String, dynamic>> points,
    required String activityType,
    required Duration totalDuration,
    required Duration movingDuration,
    double userWeightKg = 70.0,
    DateTime? turnBackTriggeredAt,
    double? turnBackDistanceKm,
  }) {
    if (points.isEmpty) {
      return ExerciseStats(
        distanceKm: 0.0,
        totalDuration: totalDuration,
        movingDuration: movingDuration,
        activeMovingRatio: 0.0,
        caloriesBurntKcal: 0.0,
        avgSpeedKmh: 0.0,
        maxSpeedKmh: 0.0,
        avgPaceMinKm: '--:--',
        bestPaceMinKm: '--:--',
        elevationGainMeters: 0.0,
        elevationLossMeters: 0.0,
        minAltitudeMeters: 0.0,
        maxAltitudeMeters: 0.0,
        avgAltitudeMeters: 0.0,
        totalTrackpoints: 0,
        turnBackDistanceKm: turnBackDistanceKm,
        turnBackTriggeredAt: turnBackTriggeredAt,
      );
    }

    double totalDistanceKm = 0.0;
    double maxSpeedMps = 0.0;
    double bestMovingMps = 0.0;
    double elevationGain = 0.0;
    final elevation = ElevationAccumulator();
    double elevationLoss = 0.0;
    double minAlt = double.maxFinite;
    double maxAlt = -double.maxFinite;
    double totalAlt = 0.0;

    const p = 0.017453292519943295;

    for (int i = 0; i < points.length; i++) {
      final pCur = points[i];
      final alt = (pCur['altitude'] as num?)?.toDouble() ?? 0.0;
      final speed = (pCur['speed'] as num?)?.toDouble() ?? 0.0;

      if (alt < minAlt) minAlt = alt;
      if (alt > maxAlt) maxAlt = alt;
      totalAlt += alt;

      if (speed > maxSpeedMps) maxSpeedMps = speed;
      if (speed > 0.5 && speed > bestMovingMps) bestMovingMps = speed;

      if (i > 0) {
        final pPrev = points[i - 1];
        final lat1 = (pPrev['lat'] as num).toDouble();
        final lon1 = (pPrev['lng'] as num).toDouble();
        final lat2 = (pCur['lat'] as num).toDouble();
        final lon2 = (pCur['lng'] as num).toDouble();

        final a = 0.5 -
            cos((lat2 - lat1) * p) / 2 +
            cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
        final d = 12742 * asin(sqrt(a));
        totalDistanceKm += d;
      }
      elevation.add(alt);
    }
    elevationGain = elevation.gain;
    elevationLoss = elevation.loss;

    final avgAlt = points.isNotEmpty ? (totalAlt / points.length) : 0.0;
    final movingHours = movingDuration.inSeconds / 3600.0;
    final avgSpeedKmh = movingHours > 0 ? (totalDistanceKm / movingHours) : 0.0;
    final avgMps = totalDistanceKm > 0 && movingDuration.inSeconds > 0
        ? (totalDistanceKm * 1000.0) / movingDuration.inSeconds
        : 0.0;

    final ratio = totalDuration.inSeconds > 0
        ? (movingDuration.inSeconds / totalDuration.inSeconds).clamp(0.0, 1.0)
        : 1.0;

    final calories = calculateCaloriesBurnt(
      activityType: activityType,
      distanceKm: totalDistanceKm,
      movingDuration: movingDuration,
      elevationGainMeters: elevationGain,
      userWeightKg: userWeightKg,
    );

    return ExerciseStats(
      distanceKm: totalDistanceKm,
      totalDuration: totalDuration,
      movingDuration: movingDuration,
      activeMovingRatio: ratio,
      caloriesBurntKcal: calories,
      avgSpeedKmh: avgSpeedKmh,
      maxSpeedKmh: maxSpeedMps * 3.6,
      avgPaceMinKm: formatPaceFromMps(avgMps),
      bestPaceMinKm: formatPaceFromMps(bestMovingMps),
      bestMovingSpeedKmh: bestMovingMps * 3.6,
      elevationGainMeters: elevationGain,
      elevationLossMeters: elevationLoss,
      minAltitudeMeters: minAlt.isFinite ? minAlt : 0.0,
      maxAltitudeMeters: maxAlt.isFinite ? maxAlt : 0.0,
      avgAltitudeMeters: avgAlt,
      totalTrackpoints: points.length,
      turnBackDistanceKm: turnBackDistanceKm,
      turnBackTriggeredAt: turnBackTriggeredAt,
    );
  }
}

/// Accumulates elevation gain/loss with a hysteresis threshold.
///
/// GPS altitude jitters by several metres; summing every positive step turns a flat route into
/// hundreds of metres of "climbing". A change only counts once it moves [thresholdMeters] away
/// from the last reference altitude.
class ElevationAccumulator {
  /// Minimum sustained change (m) before a climb or descent is counted.
  final double thresholdMeters;

  double _reference = double.nan;
  double _gain = 0.0;
  double _loss = 0.0;

  ElevationAccumulator({this.thresholdMeters = 3.0});

  /// Total counted ascent in metres.
  double get gain => _gain;

  /// Total counted descent in metres.
  double get loss => _loss;

  /// Feeds the next altitude sample.
  void add(double altitude) {
    if (altitude.isNaN) return;
    if (_reference.isNaN) {
      _reference = altitude;
      return;
    }
    final delta = altitude - _reference;
    if (delta >= thresholdMeters) {
      _gain += delta;
      _reference = altitude;
    } else if (delta <= -thresholdMeters) {
      _loss += -delta;
      _reference = altitude;
    }
  }
}
