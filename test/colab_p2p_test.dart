import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/models/location_point.dart';
import 'package:turnback/models/teammate.dart';
import 'package:turnback/services/p2p_mesh_service.dart';

void main() {
  group('P2pMeshService E2EE Crypto & URI Handshake Tests', () {
    test('generates valid 256-bit key and tunnel ID', () {
      final key = P2pMeshService.generate256BitKey();
      expect(key, isNotEmpty);
      expect(base64Url.decode(key).length, equals(32));

      final tunnelId = P2pMeshService.generateTunnelId();
      expect(tunnelId.length, equals(32));
    });

    test('encrypts and decrypts telemetry JSON payload correctly', () {
      final key = P2pMeshService.generate256BitKey();
      const payload = '{"user":"Alex","lat":12.9716,"lng":77.5946,"spd":28.5,"alt":920.0}';

      final encrypted = P2pMeshService.encryptPayload(payload, key);
      expect(encrypted, isNot(equals(payload)));

      final decrypted = P2pMeshService.decryptPayload(encrypted, key);
      expect(decrypted, equals(payload));
    });

    test('fails decryption gracefully on wrong key or corrupted ciphertext', () {
      final key1 = P2pMeshService.generate256BitKey();
      final key2 = P2pMeshService.generate256BitKey();
      const payload = '{"user":"Sam","lat":13.0827,"lng":80.2707}';

      final encrypted = P2pMeshService.encryptPayload(payload, key1);
      final wrongKeyAttempt = P2pMeshService.decryptPayload(encrypted, key2);
      expect(wrongKeyAttempt, isNull);

      final corrupted = P2pMeshService.decryptPayload('invalid_corrupted_base64!', key1);
      expect(corrupted, isNull);
    });

    test('MeshSessionConfig encodes and parses turnback:// and legacy activitymapper:// URI', () {
      const config = MeshSessionConfig(
        sessionId: 'tunnel-1234-abcd',
        sessionKey: 'test_base64_encryption_key_256_bit==',
        sessionName: 'Sunday Morning Mountain Ride',
      );

      final uri = config.toUri();
      expect(uri, startsWith('turnback://mesh?'));
      expect(uri, contains('id=tunnel-1234-abcd'));

      final parsed = MeshSessionConfig.fromUri(uri);
      expect(parsed, isNotNull);
      expect(parsed!.sessionId, equals('tunnel-1234-abcd'));
      expect(parsed.sessionKey, equals('test_base64_encryption_key_256_bit=='));
      expect(parsed.sessionName, equals('Sunday Morning Mountain Ride'));

      // Test legacy activitymapper:// backward compatibility
      final legacyParsed = MeshSessionConfig.fromUri(
        'activitymapper://mesh?id=tunnel-1234-abcd&key=test_base64_encryption_key_256_bit%3D%3D&name=Sunday%20Morning%20Mountain%20Ride',
      );
      expect(legacyParsed, isNotNull);
      expect(legacyParsed!.sessionId, equals('tunnel-1234-abcd'));
    });
  });

  group('Teammate Model & Multi-Track Group GPX Tests', () {
    test('Teammate model calculates formatted distance and display tags', () {
      final teammateClose = Teammate(
        peerId: 'peer1',
        username: 'Alex',
        colorValue: 0xFFFF5722,
        lastLat: 12.972,
        lastLng: 77.595,
        speedKmh: 28.4,
        altitude: 920.0,
        lastTimestamp: DateTime.now().millisecondsSinceEpoch,
        distanceToUserMeters: 450.0,
      );

      expect(teammateClose.formattedDistance, equals('450 m'));
      expect(teammateClose.displayTag, contains('Alex • 450 m • 28.4 km/h'));
      expect(teammateClose.isActive, isTrue);

      final teammateFar = teammateClose.copyWith(distanceToUserMeters: 2400.0);
      expect(teammateFar.formattedDistance, equals('2.4 km'));
    });

    test('generateMultiTrackGpx bundles multiple teammate trk segments', () {
      final meshService = P2pMeshService.instance;
      final localPoints = [
        LocationPoint(
          sessionId: 1,
          timestamp: DateTime.utc(2026, 8, 22, 10, 0, 0),
          lat: 12.9716,
          lng: 77.5946,
          altitude: 920.0,
          accuracy: 4.0,
          speed: 7.5,
        ),
        LocationPoint(
          sessionId: 1,
          timestamp: DateTime.utc(2026, 8, 22, 10, 5, 0),
          lat: 12.9730,
          lng: 77.5960,
          altitude: 925.0,
          accuracy: 4.0,
          speed: 8.0,
        ),
      ];

      final gpx = meshService.generateMultiTrackGpx(
        sessionName: 'Group Ride #4',
        localUserPoints: localPoints,
      );

      expect(gpx, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(gpx, contains('<gpx version="1.1"'));
      expect(gpx, contains('Group Ride #4 (Team Mesh Bundle)'));
      expect(gpx, contains('<trk>'));
      expect(gpx, contains('<trkpt lat="12.9716" lon="77.5946">'));
      expect(gpx, contains('</gpx>'));
    });
  });
}
