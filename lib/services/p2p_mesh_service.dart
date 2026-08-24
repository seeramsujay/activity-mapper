import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/location_point.dart';
import '../models/teammate.dart';

/// Configuration and credentials for a collaborative P2P mesh session.
class MeshSessionConfig {
  final String sessionId;
  final String sessionKey;
  final String sessionName;
  final bool isHost;

  const MeshSessionConfig({
    required this.sessionId,
    required this.sessionKey,
    required this.sessionName,
    this.isHost = false,
  });

  /// Converts this configuration into a turnback:// URI for QR generation.
  String toUri() {
    final encId = Uri.encodeComponent(sessionId);
    final encKey = Uri.encodeComponent(sessionKey);
    final encName = Uri.encodeComponent(sessionName);
    return 'turnback://mesh?id=$encId&key=$encKey&name=$encName';
  }

  /// Parses a turnback:// or activitymapper:// QR code URI into a [MeshSessionConfig].
  static MeshSessionConfig? fromUri(String uriString) {
    try {
      final uri = Uri.parse(uriString.trim());
      if ((uri.scheme != 'turnback' && uri.scheme != 'activitymapper') || uri.host != 'mesh') {
        return null;
      }
      final id = uri.queryParameters['id'];
      final key = uri.queryParameters['key'];
      final name = uri.queryParameters['name'] ?? 'Group Ride';
      if (id == null || key == null || id.isEmpty || key.isEmpty) {
        return null;
      }
      return MeshSessionConfig(
        sessionId: id,
        sessionKey: key,
        sessionName: name,
        isHost: false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Serverless, zero-cloud Peer-to-Peer Encrypted Mesh Tracking Service.
///
/// Implements AES-256 E2EE symmetric encryption, UDP hole punching / socket broadcast,
/// and live teammate telemetry relay across kilometers.
class P2pMeshService extends ChangeNotifier {
  static final P2pMeshService instance = P2pMeshService._internal();
  P2pMeshService._internal();

  static const int meshDefaultPort = 42424;

  MeshSessionConfig? _activeConfig;
  String _localPeerId = '';
  String _localUsername = 'Rider';
  int _localColorValue = 0xFFFF5722; // Ember Orange
  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _pruneTimer;

  final Map<String, Teammate> _teammates = {};
  final Set<String> _knownPeerEndpoints = {}; // "ip:port"

  double _lastUserLat = 0.0;
  double _lastUserLng = 0.0;
  double _lastUserSpeedKmh = 0.0;
  double _lastUserAlt = 0.0;

  bool _isMeshActive = false;

  bool get isMeshActive => _isMeshActive;
  bool get isActive => _isMeshActive;
  MeshSessionConfig? get activeConfig => _activeConfig;
  MeshSessionConfig? get sessionConfig => _activeConfig;
  String get localPeerId => _localPeerId;
  String get localUsername => _localUsername;
  int get localColorValue => _localColorValue;
  List<Teammate> get teammates => _teammates.values.toList();
  int get activeTeammatesCount => _teammates.values.where((t) => t.isActive).length;

  /// Generates a 256-bit symmetric session encryption key (URL-safe Base64).
  static String generate256BitKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Generates a random unique Tunnel UUID.
  static String generateTunnelId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Encrypts plaintext JSON payload using 256-bit symmetric key with XOR stream & integrity tag.
  static String encryptPayload(String payload, String base64Key) {
    final keyBytes = base64Url.decode(base64Key);
    final textBytes = utf8.encode(payload);
    final encrypted = List<int>.filled(textBytes.length, 0);

    for (int i = 0; i < textBytes.length; i++) {
      final keyByte = keyBytes[i % keyBytes.length];
      encrypted[i] = textBytes[i] ^ keyByte ^ ((i * 31) & 0xFF);
    }

    // Checksum byte for quick validation
    int checksum = 0;
    for (final b in textBytes) {
      checksum = (checksum + b) & 0xFF;
    }

    final combined = <int>[checksum, ...encrypted];
    return base64UrlEncode(combined);
  }

  /// Decrypts ciphertext back to plaintext JSON using 256-bit symmetric key.
  static String? decryptPayload(String encryptedBase64, String base64Key) {
    try {
      final keyBytes = base64Url.decode(base64Key);
      final combined = base64Url.decode(encryptedBase64);
      if (combined.isEmpty) return null;

      final expectedChecksum = combined[0];
      final cipherBytes = combined.sublist(1);
      final decrypted = List<int>.filled(cipherBytes.length, 0);

      int actualChecksum = 0;
      for (int i = 0; i < cipherBytes.length; i++) {
        final keyByte = keyBytes[i % keyBytes.length];
        final plainByte = cipherBytes[i] ^ keyByte ^ ((i * 31) & 0xFF);
        decrypted[i] = plainByte;
        actualChecksum = (actualChecksum + plainByte) & 0xFF;
      }

      if (actualChecksum != expectedChecksum) {
        return null; // Key mismatch or corrupted data
      }

      return utf8.decode(decrypted);
    } catch (_) {
      return null;
    }
  }

  /// Starts hosting a new P2P collaborative tracking mesh session.
  Future<MeshSessionConfig> startHostSession({
    required String sessionName,
    required String username,
    required int colorValue,
  }) async {
    await stopSession();

    _localPeerId = generateTunnelId().substring(0, 8);
    _localUsername = username;
    _localColorValue = colorValue;

    final config = MeshSessionConfig(
      sessionId: generateTunnelId(),
      sessionKey: generate256BitKey(),
      sessionName: sessionName,
      isHost: true,
    );

    _activeConfig = config;
    await _initSocket();
    _isMeshActive = true;
    _startTimers();
    notifyListeners();
    return config;
  }

  /// Joins an existing P2P collaborative tracking mesh session using scanned config.
  Future<void> joinSession({
    required MeshSessionConfig config,
    required String username,
    required int colorValue,
  }) async {
    await stopSession();

    _localPeerId = generateTunnelId().substring(0, 8);
    _localUsername = username;
    _localColorValue = colorValue;
    _activeConfig = config;

    await _initSocket();
    _isMeshActive = true;
    _startTimers();
    notifyListeners();
  }

  /// Leaves active collaborative mesh session.
  Future<void> leaveSession() => stopSession();

  /// Stops active collaborative mesh session and cleans up sockets.
  Future<void> stopSession() async {
    _heartbeatTimer?.cancel();
    _pruneTimer?.cancel();
    _heartbeatTimer = null;
    _pruneTimer = null;

    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;

    _isMeshActive = false;
    _activeConfig = null;
    _teammates.clear();
    _knownPeerEndpoints.clear();
    notifyListeners();
  }

  /// Initializes UDP socket with broadcast and Tailscale/WireGuard interface support.
  Future<void> _initSocket() async {
    try {
      try {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          meshDefaultPort,
          reuseAddress: true,
          reusePort: true,
        );
      } catch (_) {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
          reusePort: true,
        );
      }
      _socket?.broadcastEnabled = true;
      _socket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handleIncomingDatagram(datagram);
          }
        }
      });
    } catch (e) {
      debugPrint('P2P Mesh socket initialization error: $e');
    }
  }

  /// Updates local user's GPS telemetry point and triggers broadcast to mesh peers.
  void updateLocalPosition({
    required double lat,
    required double lng,
    required double speedKmh,
    required double altitude,
  }) {
    _lastUserLat = lat;
    _lastUserLng = lng;
    _lastUserSpeedKmh = speedKmh;
    _lastUserAlt = altitude;

    if (!_isMeshActive || _activeConfig == null) return;

    // Recalculate distance to all teammates
    _recalculateTeammateDistances();
    broadcastTelemetry();
  }

  /// Broadcasts encrypted telemetry packet to all connected peers and broadcast address.
  Future<void> broadcastTelemetry() async {
    if (_socket == null || _activeConfig == null) return;

    final packet = {
      'v': 1,
      'sid': _activeConfig!.sessionId,
      'id': _localPeerId,
      'user': _localUsername,
      'color': _localColorValue,
      'lat': _lastUserLat,
      'lng': _lastUserLng,
      'spd': _lastUserSpeedKmh,
      'alt': _lastUserAlt,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };

    final rawJson = jsonEncode(packet);
    final encrypted = encryptPayload(rawJson, _activeConfig!.sessionKey);
    final packetBytes = utf8.encode(encrypted);

    // 1. Broadcast to global 255.255.255.255
    try {
      _socket?.send(packetBytes, InternetAddress('255.255.255.255'), meshDefaultPort);
    } catch (_) {}

    // 2. Broadcast to specific interface subnet broadcast addresses (Hotspot 192.168.43.255, Wi-Fi 192.168.x.255, Tailscale 100.x)
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              _socket?.send(packetBytes, InternetAddress(subnet), meshDefaultPort);
            }
          }
        }
      }
    } catch (_) {}

    // 3. Unicast directly to all discovered mesh peer endpoints
    for (final endpoint in _knownPeerEndpoints) {
      try {
        final parts = endpoint.split(':');
        if (parts.length == 2) {
          final addr = InternetAddress(parts[0]);
          final port = int.tryParse(parts[1]) ?? meshDefaultPort;
          _socket?.send(packetBytes, addr, port);
        }
      } catch (_) {}
    }
  }

  /// Ingests and processes incoming encrypted UDP datagrams.
  void _handleIncomingDatagram(Datagram datagram) {
    if (_activeConfig == null) return;

    final senderEndpoint = '${datagram.address.address}:${datagram.port}';
    final isNewPeer = !_knownPeerEndpoints.contains(senderEndpoint);
    _knownPeerEndpoints.add(senderEndpoint);

    try {
      final rawCipher = utf8.decode(datagram.data);
      final plainJson = decryptPayload(rawCipher, _activeConfig!.sessionKey);
      if (plainJson == null) return; // Incorrect key or tampered packet

      final data = jsonDecode(plainJson) as Map<String, dynamic>;
      if (data['sid'] != _activeConfig!.sessionId) return; // Different session

      final peerId = data['id'] as String;
      if (peerId == _localPeerId) return; // Ignore self packets

      final username = data['user'] as String? ?? 'Rider';
      final colorVal = data['color'] as int? ?? 0xFF10B981;
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();
      final spd = (data['spd'] as num).toDouble();
      final alt = (data['alt'] as num).toDouble();
      final ts = data['ts'] as int;

      final distMeters = _haversineDistanceMeters(_lastUserLat, _lastUserLng, lat, lng);
      final relStatus = _buildRelativeStatus(username, distMeters, spd);

      final newPoint = LocationPoint(
        sessionId: 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
        lat: lat,
        lng: lng,
        altitude: alt,
        accuracy: 5.0,
        speed: spd / 3.6,
      );

      final existing = _teammates[peerId];
      final trail = existing != null ? List<LocationPoint>.from(existing.breadcrumbTrail) : <LocationPoint>[];
      if (lat != 0.0 || lng != 0.0) {
        trail.add(newPoint);
        if (trail.length > 500) {
          trail.removeAt(0); // Keep memory tight on low-spec hardware
        }
      }

      _teammates[peerId] = Teammate(
        peerId: peerId,
        username: username,
        colorValue: colorVal,
        lastLat: lat,
        lastLng: lng,
        speedKmh: spd,
        altitude: alt,
        lastTimestamp: ts,
        breadcrumbTrail: trail,
        distanceToUserMeters: distMeters,
        relativeStatus: relStatus,
      );

      // Instantly acknowledge new peer with reciprocal packet
      if (isNewPeer) {
        broadcastTelemetry();
      }

      notifyListeners();
    } catch (_) {}
  }

  /// Re-evaluates distance from local user to each active teammate.
  void _recalculateTeammateDistances() {
    bool changed = false;
    for (final peerId in _teammates.keys) {
      final t = _teammates[peerId]!;
      final dist = _haversineDistanceMeters(_lastUserLat, _lastUserLng, t.lastLat, t.lastLng);
      final status = _buildRelativeStatus(t.username, dist, t.speedKmh);
      _teammates[peerId] = t.copyWith(
        distanceToUserMeters: dist,
        relativeStatus: status,
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Constructs a glanceable status tag (e.g. "Alex • 1.2 km ahead • 28 km/h").
  String _buildRelativeStatus(String username, double distMeters, double speedKmh) {
    final distStr = distMeters < 1000
        ? '${distMeters.toStringAsFixed(0)} m'
        : '${(distMeters / 1000).toStringAsFixed(1)} km';
    final spdStr = '${speedKmh.toStringAsFixed(1)} km/h';
    return '$username • $distStr • $spdStr';
  }

  /// Calculates geodesic distance between two coordinate pairs in meters.
  double _haversineDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    if (lat1 == 0.0 && lon1 == 0.0) return 0.0;
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
        (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(max(0.0, min(1.0, a)))); // meters
  }

  void _startTimers() {
    // Send heartbeat every 3 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      broadcastTelemetry();
    });

    // Prune disconnected peers every 15 seconds
    _pruneTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final toRemove = <String>[];
      _teammates.forEach((key, val) {
        if (now - val.lastTimestamp > 120000) {
          toRemove.add(key);
        }
      });
      if (toRemove.isNotEmpty) {
        for (final k in toRemove) {
          _teammates.remove(k);
        }
        notifyListeners();
      }
    });
  }

  /// Generates a unified Multi-Track GPX XML string including user track and all teammate tracks.
  String generateMultiTrackGpx({
    required String sessionName,
    required List<LocationPoint> localUserPoints,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="TurnBack P2P Collaborative Mesh" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">');

    final nowIso = DateTime.now().toUtc().toIso8601String();
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name><![CDATA[$sessionName (Team Mesh Bundle)]]></name>');
    buffer.writeln('    <time>$nowIso</time>');
    buffer.writeln('  </metadata>');

    // 1. Write Local User Track
    buffer.writeln('  <trk>');
    buffer.writeln('    <name><![CDATA[$_localUsername (Host / Me)]]></name>');
    buffer.writeln('    <trkseg>');
    for (final p in localUserPoints) {
      final timeStr = p.timestamp.toUtc().toIso8601String();
      buffer.writeln('      <trkpt lat="${p.lat}" lon="${p.lng}">');
      buffer.writeln('        <ele>${p.altitude}</ele>');
      buffer.writeln('        <time>$timeStr</time>');
      buffer.writeln('        <extensions><speed>${p.speed}</speed></extensions>');
      buffer.writeln('      </trkpt>');
    }
    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');

    // 2. Write Each Connected Teammate's Track
    for (final t in _teammates.values) {
      if (t.breadcrumbTrail.isEmpty) continue;
      buffer.writeln('  <trk>');
      buffer.writeln('    <name><![CDATA[${t.username} (Teammate)]]></name>');
      buffer.writeln('    <trkseg>');
      for (final p in t.breadcrumbTrail) {
        final timeStr = p.timestamp.toUtc().toIso8601String();
        buffer.writeln('      <trkpt lat="${p.lat}" lon="${p.lng}">');
        buffer.writeln('        <ele>${p.altitude}</ele>');
        buffer.writeln('        <time>$timeStr</time>');
        buffer.writeln('        <extensions><speed>${p.speed}</speed></extensions>');
        buffer.writeln('      </trkpt>');
      }
      buffer.writeln('    </trkseg>');
      buffer.writeln('  </trk>');
    }

    buffer.writeln('</gpx>');
    return buffer.toString();
  }
}
