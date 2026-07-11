/// Represents a single GPS coordinate telemetry point recorded during a session.
///
/// Contains position, altitude, speed, and accuracy metadata captured at a specific timestamp.
class LocationPoint {
  /// The unique identifier of this point in the database.
  final int? id;

  /// The parent session ID this point belongs to.
  final int sessionId;

  /// The timestamp of when this GPS location was captured.
  final DateTime timestamp;

  /// The latitude coordinate in degrees.
  final double lat;

  /// The longitude coordinate in degrees.
  final double lng;

  /// The elevation height above sea level in meters.
  final double altitude;

  /// The horizontal accuracy radius of this coordinate fix in meters.
  final double accuracy;

  /// The instant speed recorded at this coordinate point in meters per second.
  final double speed; // in m/s

  /// Creates a new [LocationPoint] instance.
  LocationPoint({
    this.id,
    required this.sessionId,
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.accuracy,
    required this.speed,
  });

  /// Converts this [LocationPoint] instance into an SQLite-compatible map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'lat': lat,
      'lng': lng,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
    };
  }

  /// Reconstructs a [LocationPoint] from an SQLite query database row map.
  factory LocationPoint.fromMap(Map<String, dynamic> map) {
    return LocationPoint(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      lat: map['lat'] as double,
      lng: map['lng'] as double,
      altitude: map['altitude'] as double,
      accuracy: map['accuracy'] as double,
      speed: map['speed'] as double,
    );
  }
}

