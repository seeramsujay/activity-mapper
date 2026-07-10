class LocationPoint {
  final int? id;
  final int sessionId;
  final DateTime timestamp;
  final double lat;
  final double lng;
  final double altitude;
  final double accuracy;
  final double speed; // in m/s

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
