import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/services/p2p_mesh_service.dart';
import 'package:turnback/services/settings_service.dart';
import 'package:turnback/services/tile_cache_service.dart';
import 'package:turnback/services/unit_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnitFormat', () {
    tearDown(() => SettingsService.instance.setUseImperialUnits(false));

    test('metric formatting', () {
      SettingsService.instance.setUseImperialUnits(false);
      expect(UnitFormat.distance(5.25), '5.25 km');
      expect(UnitFormat.speedKmh(12.0), '12.0 km/h');
      expect(UnitFormat.paceFromMps(1000 / 300), '5:00'); // 5:00 /km
      expect(UnitFormat.elevation(120.4, sign: '+'), '+120 m');
      expect(UnitFormat.paceFromDistance(10, const Duration(minutes: 50)), "5'00\"/km");
    });

    test('imperial formatting', () {
      SettingsService.instance.setUseImperialUnits(true);
      expect(UnitFormat.distance(1.609344), '1.00 mi');
      expect(UnitFormat.distance(10, upper: true), '6.21 MI');
      expect(UnitFormat.speedKmh(16.09344), '10.0 mph');
      expect(UnitFormat.paceFromMps(1609.344 / 480), '8:00'); // 8:00 /mi
      expect(UnitFormat.elevation(100), '328 ft');
      expect(UnitFormat.shortDistance(100), '328 ft');
      expect(UnitFormat.paceUnit, '/mi');
    });

    test('stationary pace shows a placeholder', () {
      expect(UnitFormat.paceFromMps(0.1), '--:--');
      expect(UnitFormat.paceFromDistance(0.01, const Duration(minutes: 1)), '--');
    });
  });

  group('Tile cache legacy layout migration', () {
    test('moves z/x/y tiles under the current source key', () async {
      final base = await Directory.systemTemp.createTemp('tiles');
      const source = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      final legacyTile = File('${base.path}/15/100/200.png');
      await legacyTile.create(recursive: true);
      await legacyTile.writeAsBytes([1, 2, 3]);
      final metadata = File('${base.path}/offline_areas.json');
      await metadata.writeAsString('[]');

      await TileCacheService.migrateLegacyLayout(base, source);

      final moved = TileCacheService.tileFile(base, source, 15, 100, 200);
      expect(await moved.readAsBytes(), [1, 2, 3]);
      expect(await Directory('${base.path}/15').exists(), isFalse);
      expect(await metadata.exists(), isTrue); // non-tile files untouched

      await base.delete(recursive: true);
    });
  });

  group('Mesh QR rendezvous', () {
    test('ignores teammate QRs when no group is active', () {
      const cfg = MeshSessionConfig(
        sessionId: 'abc',
        sessionKey: 'k',
        sessionName: 'n',
        isHost: false,
        publicIp: '203.0.113.7',
        publicPort: 40000,
      );
      expect(P2pMeshService.instance.addPeerFromConfig(cfg), isFalse);
    });
  });
}
