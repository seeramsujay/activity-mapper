import 'package:flutter/material.dart';

/// Available tactical ping categories for instant group workout communication.
enum PingType {
  regroup,  // 🛑 Regroup / Stopping
  water,    // 🚰 Water / Fuel Break
  sprint,   // ⚡ Pacing Up / Sprint Attack
  hazard,   // ⚠️ Road / Trail Hazard
  sos,      // 🚨 SOS / Flat Tire / Mechanical
}

/// Represents an encrypted 1-tap tactical comms message sent across the mesh.
class MeshPing {
  final String id;
  final PingType type;
  final String senderId;
  final String senderName;
  final int senderColor;
  final int timestamp;
  final String? customText;

  const MeshPing({
    required this.id,
    required this.type,
    required this.senderId,
    required this.senderName,
    required this.senderColor,
    required this.timestamp,
    this.customText,
  });

  String get title {
    switch (type) {
      case PingType.regroup:
        return 'Regroup / Stopping';
      case PingType.water:
        return 'Water / Fuel Break';
      case PingType.sprint:
        return 'Pacing Up / Sprint';
      case PingType.hazard:
        return 'Hazard on Route';
      case PingType.sos:
        return 'SOS / Mechanical Alert!';
    }
  }

  String get iconEmoji {
    switch (type) {
      case PingType.regroup:
        return '🛑';
      case PingType.water:
        return '🚰';
      case PingType.sprint:
        return '⚡';
      case PingType.hazard:
        return '⚠️';
      case PingType.sos:
        return '🚨';
    }
  }

  Color get color {
    switch (type) {
      case PingType.regroup:
        return const Color(0xFFF97316); // Orange
      case PingType.water:
        return const Color(0xFF3B82F6); // Blue
      case PingType.sprint:
        return const Color(0xFF10B981); // Green
      case PingType.hazard:
        return const Color(0xFFFBBF24); // Amber
      case PingType.sos:
        return const Color(0xFFEF4444); // Red
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'sid': senderId,
    'name': senderName,
    'color': senderColor,
    'ts': timestamp,
    if (customText != null) 'txt': customText,
  };

  factory MeshPing.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'regroup';
    final pType = PingType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => PingType.regroup,
    );

    return MeshPing(
      id: json['id'] as String? ?? '',
      type: pType,
      senderId: json['sid'] as String? ?? '',
      senderName: json['name'] as String? ?? 'Rider',
      senderColor: json['color'] as int? ?? 0xFFFF5722,
      timestamp: json['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      customText: json['txt'] as String?,
    );
  }
}

/// Represents a shared Point of Interest (POI) dropped by any teammate on the map.
class SharedWaypoint {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String creatorId;
  final String creatorName;
  final int colorValue;
  final int timestamp;

  const SharedWaypoint({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.creatorId,
    required this.creatorName,
    required this.colorValue,
    required this.timestamp,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lng': lng,
    'cid': creatorId,
    'cname': creatorName,
    'col': colorValue,
    'ts': timestamp,
  };

  factory SharedWaypoint.fromJson(Map<String, dynamic> json) => SharedWaypoint(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Waypoint',
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    creatorId: json['cid'] as String? ?? '',
    creatorName: json['cname'] as String? ?? 'Rider',
    colorValue: json['col'] as int? ?? 0xFFFF5722,
    timestamp: json['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
  );
}
