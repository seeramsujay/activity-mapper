import 'dart:math';
import 'package:flutter/material.dart';
import 'location_point.dart';

/// Represents a connected peer/teammate in a collaborative P2P tracking session.
class Teammate {
  /// Unique identifier of the peer device.
  final String peerId;

  /// Display name of the teammate (e.g. "Alex", "Sam").
  final String username;

  /// Custom marker color integer (0xAARRGGBB).
  final int colorValue;

  /// Latest known latitude in degrees.
  final double lastLat;

  /// Latest known longitude in degrees.
  final double lastLng;

  /// Latest recorded speed in km/h.
  final double speedKmh;

  /// Latest recorded altitude in meters.
  final double altitude;

  /// Timestamp of the last received telemetry packet (epoch ms).
  final int lastTimestamp;

  /// Breadcrumb coordinate history for this teammate.
  final List<LocationPoint> breadcrumbTrail;

  /// Calculated distance to the local user in meters.
  final double distanceToUserMeters;

  /// Relative direction or status string (e.g. "1.2 km ahead • 28 km/h").
  final String relativeStatus;

  /// Creates a new [Teammate] instance.
  Teammate({
    required this.peerId,
    required this.username,
    required this.colorValue,
    required this.lastLat,
    required this.lastLng,
    required this.speedKmh,
    required this.altitude,
    required this.lastTimestamp,
    List<LocationPoint>? breadcrumbTrail,
    this.distanceToUserMeters = 0.0,
    this.relativeStatus = '',
  }) : breadcrumbTrail = breadcrumbTrail ?? [];

  /// Helper getter to obtain the [Color] object.
  Color get color => Color(colorValue);

  /// Checks if teammate is currently active (packet received within last 60 seconds).
  bool get isActive {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastTimestamp) < 60000;
  }

  /// Copies this instance with updated telemetry values.
  Teammate copyWith({
    String? peerId,
    String? username,
    int? colorValue,
    double? lastLat,
    double? lastLng,
    double? speedKmh,
    double? altitude,
    int? lastTimestamp,
    List<LocationPoint>? breadcrumbTrail,
    double? distanceToUserMeters,
    String? relativeStatus,
  }) {
    return Teammate(
      peerId: peerId ?? this.peerId,
      username: username ?? this.username,
      colorValue: colorValue ?? this.colorValue,
      lastLat: lastLat ?? this.lastLat,
      lastLng: lastLng ?? this.lastLng,
      speedKmh: speedKmh ?? this.speedKmh,
      altitude: altitude ?? this.altitude,
      lastTimestamp: lastTimestamp ?? this.lastTimestamp,
      breadcrumbTrail: breadcrumbTrail ?? this.breadcrumbTrail,
      distanceToUserMeters: distanceToUserMeters ?? this.distanceToUserMeters,
      relativeStatus: relativeStatus ?? this.relativeStatus,
    );
  }

  /// Converts this teammate instance to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'id': peerId,
      'user': username,
      'color': colorValue,
      'lat': lastLat,
      'lng': lastLng,
      'spd': speedKmh,
      'alt': altitude,
      'ts': lastTimestamp,
    };
  }

  /// Deserializes a teammate telemetry packet.
  factory Teammate.fromJson(Map<String, dynamic> json) {
    return Teammate(
      peerId: json['id'] as String? ?? 'unknown',
      username: json['user'] as String? ?? 'Rider',
      colorValue: json['color'] as int? ?? 0xFFFF5722,
      lastLat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lastLng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (json['spd'] as num?)?.toDouble() ?? 0.0,
      altitude: (json['alt'] as num?)?.toDouble() ?? 0.0,
      lastTimestamp: json['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Formats distance to user in human-readable metric (meters or kilometers).
  String get formattedDistance {
    if (distanceToUserMeters < 1000) {
      return '${distanceToUserMeters.toStringAsFixed(0)} m';
    } else {
      return '${(distanceToUserMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Generates a comprehensive summary label (e.g. "Alex • 1.2 km • 28 km/h").
  String get displayTag {
    final distStr = formattedDistance;
    final spdStr = '${speedKmh.toStringAsFixed(1)} km/h';
    return '$username • $distStr • $spdStr';
  }
}
