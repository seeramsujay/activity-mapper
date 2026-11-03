import 'dart:math';
import 'package:flutter/material.dart';
import '../models/location_point.dart';

/// Supported track color visualizers inspired by Geo Tracker & OsmAnd.
enum TrackColorMode {
  /// Single solid accent color (or returning red).
  solid,

  /// Dynamic speed gradient (Cyan -> Lime -> Amber -> Coral Red).
  speed,

  /// Dynamic elevation gradient (Forest Teal -> Ochre -> Bright Amber -> Summit White).
  elevation,
}

/// Service that computes multi-color gradient palettes for route polylines.
class TrackGradientService {
  TrackGradientService._();

  // Speed gradient keyframes:
  // 0.0 -> Vibrant Cyan (idle / walk)
  // 0.33 -> Emerald Lime (steady jog / base pace)
  // 0.66 -> Amber Gold (fast run / cycling)
  // 1.0 -> Coral Crimson (sprint / high velocity)
  static const Color speedColorLow = Color(0xFF06B6D4);
  static const Color speedColorMid = Color(0xFF10B981);
  static const Color speedColorFast = Color(0xFFF59E0B);
  static const Color speedColorMax = Color(0xFFEF4444);

  // Elevation gradient keyframes:
  // 0.0 -> Deep Pine Teal (valley / trailhead)
  // 0.5 -> Ochre Amber (mid-mountain / hills)
  // 1.0 -> Summit Rose White (peak / high altitude)
  static const Color elevColorLow = Color(0xFF0D9488);
  static const Color elevColorMid = Color(0xFFEAB308);
  static const Color elevColorHigh = Color(0xFFF43F5E);
  static const Color elevColorPeak = Color(0xFFF8FAFC);

  /// Interpolates a color along the speed spectrum for a given speed in m/s.
  static Color speedToColor(
    double speedMps, {
    double minSpeedMps = 0.0,
    double maxSpeedMps = 10.0, // ~36 km/h default ceiling
  }) {
    if (maxSpeedMps <= minSpeedMps) return speedColorMid;
    final double t = ((speedMps - minSpeedMps) / (maxSpeedMps - minSpeedMps))
        .clamp(0.0, 1.0);
    return interpolateMultiStop([
      speedColorLow,
      speedColorMid,
      speedColorFast,
      speedColorMax,
    ], t);
  }

  /// Interpolates a color along the elevation spectrum for an altitude in meters.
  static Color elevationToColor(
    double altitudeMeters, {
    required double minAltMeters,
    required double maxAltMeters,
  }) {
    if (maxAltMeters <= minAltMeters) return elevColorMid;
    final double t =
        ((altitudeMeters - minAltMeters) / (maxAltMeters - minAltMeters))
            .clamp(0.0, 1.0);
    return interpolateMultiStop([
      elevColorLow,
      elevColorMid,
      elevColorHigh,
      elevColorPeak,
    ], t);
  }

  /// Multi-stop linear color interpolation along [0.0, 1.0].
  static Color interpolateMultiStop(List<Color> colors, double t) {
    if (colors.isEmpty) return Colors.blue;
    if (colors.length == 1) return colors.first;
    final clampedT = t.clamp(0.0, 1.0);
    if (clampedT >= 1.0) return colors.last;

    final double scaled = clampedT * (colors.length - 1);
    final int index = scaled.floor();
    final double fraction = scaled - index;

    return Color.lerp(colors[index], colors[min(index + 1, colors.length - 1)],
            fraction) ??
        colors[index];
  }

  /// Generates a list of segment colors for an array of points based on the active mode.
  static List<Color> computeSegmentColors({
    required List<LocationPoint> points,
    required TrackColorMode mode,
    required Color defaultColor,
  }) {
    if (points.length < 2 || mode == TrackColorMode.solid) {
      return List.filled(max(0, points.length - 1), defaultColor);
    }

    if (mode == TrackColorMode.speed) {
      double minSpeed = double.infinity;
      double maxSpeed = -double.infinity;
      for (final p in points) {
        if (p.speed < minSpeed) minSpeed = p.speed;
        if (p.speed > maxSpeed) maxSpeed = p.speed;
      }
      if (maxSpeed <= minSpeed) maxSpeed = minSpeed + 5.0;

      final List<Color> colors = [];
      for (int i = 0; i < points.length - 1; i++) {
        final avgSpeed = (points[i].speed + points[i + 1].speed) / 2.0;
        colors.add(speedToColor(avgSpeed,
            minSpeedMps: minSpeed, maxSpeedMps: maxSpeed));
      }
      return colors;
    }

    if (mode == TrackColorMode.elevation) {
      double minAlt = double.infinity;
      double maxAlt = -double.infinity;
      for (final p in points) {
        if (p.altitude < minAlt) minAlt = p.altitude;
        if (p.altitude > maxAlt) maxAlt = p.altitude;
      }
      if (maxAlt - minAlt < 5.0) {
        maxAlt = minAlt + 10.0;
      }

      final List<Color> colors = [];
      for (int i = 0; i < points.length - 1; i++) {
        final avgAlt = (points[i].altitude + points[i + 1].altitude) / 2.0;
        colors.add(elevationToColor(avgAlt,
            minAltMeters: minAlt, maxAltMeters: maxAlt));
      }
      return colors;
    }

    return List.filled(points.length - 1, defaultColor);
  }
}
