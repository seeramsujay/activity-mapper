/// Represents a custom waypoint or POI pinned along a track (OsmAnd / GPSLogger style).
class Waypoint {
  final int? id;
  final int sessionId;
  final DateTime timestamp;
  final double lat;
  final double lng;
  final double? altitude;
  final String name;
  final String category; // 'water', 'view', 'camp', 'hazard', 'pin'
  final String? description;

  const Waypoint({
    this.id,
    required this.sessionId,
    required this.timestamp,
    required this.lat,
    required this.lng,
    this.altitude,
    required this.name,
    this.category = 'pin',
    this.description,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'lat': lat,
        'lng': lng,
        'altitude': altitude,
        'name': name,
        'category': category,
        'description': description,
      };

  factory Waypoint.fromMap(Map<String, dynamic> map) => Waypoint(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        altitude: (map['altitude'] as num?)?.toDouble(),
        name: (map['name'] as String?) ?? 'Waypoint',
        category: (map['category'] as String?) ?? 'pin',
        description: map['description'] as String?,
      );
}
