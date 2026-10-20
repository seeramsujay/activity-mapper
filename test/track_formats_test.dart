import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/services/exercise_stats_service.dart';
import 'package:turnback/services/tile_cache_service.dart';
import 'package:turnback/services/track_formats.dart';
import 'package:xml/xml.dart';

void main() {
  // Two points ~111 m apart (0.001° latitude), 30 s apart, 3.7 m/s (~13.3 km/h).
  final points = <Map<String, dynamic>>[
    {'timestamp': 1700000000000, 'lat': 12.9716, 'lng': 77.5946, 'altitude': 920.0, 'accuracy': 4.0, 'speed': 3.7},
    {'timestamp': 1700000030000, 'lat': 12.9726, 'lng': 77.5946, 'altitude': 921.5, 'accuracy': 4.0, 'speed': 3.7},
  ];
  const trickyName = 'Run & Ride <"Hills"> \'26';

  group('GPX', () {
    test('is well-formed XML and escapes the activity name', () {
      final gpx = TrackFormats.buildGpx(points, trickyName);
      final doc = XmlDocument.parse(gpx);
      expect(doc.findAllElements('name').first.innerText, trickyName);
      expect(doc.findAllElements('trkpt'), hasLength(2));
    });

    test('uses UTC timestamps and namespaced speed extension', () {
      final doc = XmlDocument.parse(TrackFormats.buildGpx(points, 'x'));
      final trkpt = doc.findAllElements('trkpt').first;
      expect(trkpt.getAttribute('lat'), '12.9716000');
      expect(trkpt.findElements('time').first.innerText, '2023-11-14T22:13:20.000Z');
      final speed = trkpt.findAllElements('speed', namespace: 'http://www.garmin.com/xmlschemas/TrackPointExtension/v2');
      expect(speed.single.innerText, '3.70');
    });

    test('tiny coordinates never use exponent notation', () {
      final gpx = TrackFormats.buildGpx([
        {'timestamp': 0, 'lat': 0.0000001, 'lng': -0.0000002, 'altitude': 0, 'speed': 0},
      ], 'x');
      expect(gpx, isNot(contains('e-')));
      expect(gpx, contains('lat="0.0000001"'));
    });

    test('optional smoothed altitudes replace raw elevation', () {
      final doc = XmlDocument.parse(TrackFormats.buildGpx(points, 'x', altitudes: [1.0, 2.0]));
      expect(doc.findAllElements('ele').map((e) => e.innerText), ['1.0', '2.0']);
    });
  });

  group('TCX', () {
    test('speed stays in m/s (stored unit) instead of being divided by 3.6 again', () {
      final doc = XmlDocument.parse(TrackFormats.buildTcx(points, 'run'));
      expect(doc.findAllElements('MaximumSpeed').single.innerText, '3.70');
      final speeds = doc.findAllElements('ns3:Speed').map((e) => e.innerText).toList();
      expect(speeds, ['3.70', '3.70']);
    });

    test('includes lap and cumulative per-trackpoint DistanceMeters', () {
      final doc = XmlDocument.parse(TrackFormats.buildTcx(points, 'run'));
      final lap = doc.findAllElements('Lap').single;
      expect(double.parse(lap.findElements('DistanceMeters').single.innerText), closeTo(111.2, 0.5));
      expect(lap.findElements('TotalTimeSeconds').single.innerText, '30');
      final perPoint = doc.findAllElements('Trackpoint').map((t) => t.findElements('DistanceMeters').single.innerText);
      expect(perPoint.first, '0.0');
      expect(double.parse(perPoint.last), closeTo(111.2, 0.5));
    });

    test('maps the activity type to the right TCX sport', () {
      expect(TrackFormats.tcxSport('ride'), 'Biking');
      expect(TrackFormats.tcxSport('cycling'), 'Biking');
      expect(TrackFormats.tcxSport('run'), 'Running');
      expect(TrackFormats.tcxSport('hike'), 'Running');
      expect(TrackFormats.tcxSport('kayak'), 'Other');
      final doc = XmlDocument.parse(TrackFormats.buildTcx(points, 'ride'));
      expect(doc.findAllElements('Activity').single.getAttribute('Sport'), 'Biking');
    });

    test('Lap children follow the schema order', () {
      final lap = XmlDocument.parse(TrackFormats.buildTcx(points, 'run')).findAllElements('Lap').single;
      final names = lap.childElements.map((e) => e.name.local).toList();
      expect(names, ['TotalTimeSeconds', 'DistanceMeters', 'MaximumSpeed', 'Calories', 'Intensity', 'TriggerMethod', 'Track']);
    });
  });

  group('KML / GeoJSON / CSV', () {
    test('KML is well-formed with start/finish placemarks and lon,lat order', () {
      final doc = XmlDocument.parse(TrackFormats.buildKml(points, trickyName));
      expect(doc.findAllElements('Placemark'), hasLength(3));
      expect(doc.findAllElements('coordinates').first.innerText, '77.5946000,12.9716000,920.0');
    });

    test('GeoJSON is an RFC 7946 FeatureCollection with [lon, lat, ele]', () {
      final json = jsonDecode(TrackFormats.buildGeoJson(points, 'x', sessionId: 7)) as Map<String, dynamic>;
      expect(json['type'], 'FeatureCollection');
      final feature = (json['features'] as List).single as Map<String, dynamic>;
      expect(feature['geometry']['type'], 'LineString');
      expect(feature['geometry']['coordinates'][0], [77.5946, 12.9716, 920.0]);
      expect(feature['properties']['sessionId'], 7);
    });

    test('CSV has a header and one row per point', () {
      final lines = const LineSplitter().convert(TrackFormats.buildCsv(points));
      expect(lines.first, TrackFormats.csvHeader);
      expect(lines, hasLength(3));
      expect(lines[1].split(','), hasLength(9));
      expect(lines[1], contains('12.9716000,77.5946000,920.00,4.00,3.70,13.32'));
    });
  });

  group('ElevationAccumulator', () {
    test('ignores GPS altitude jitter below the threshold', () {
      final acc = ElevationAccumulator();
      for (final a in [100.0, 101.5, 99.0, 100.8, 99.5, 101.9, 100.2]) {
        acc.add(a);
      }
      expect(acc.gain, 0);
      expect(acc.loss, 0);
    });

    test('counts sustained climbs and descents', () {
      final acc = ElevationAccumulator();
      for (final a in [100.0, 104.0, 110.0, 115.0, 108.0, 100.0]) {
        acc.add(a);
      }
      expect(acc.gain, 15.0);
      expect(acc.loss, 15.0);
    });
  });

  group('Tile cache source keys', () {
    test('different providers never share a cache directory', () {
      const osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      const topo = 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      expect(TileCacheService.sourceKey(osm), isNot(TileCacheService.sourceKey(topo)));
      expect(TileCacheService.sourceKey(osm), TileCacheService.sourceKey(osm));
    });

    test('Google tiles are excluded from bulk download', () {
      expect(TileCacheService.allowsBulkDownload('https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}'), isFalse);
      expect(TileCacheService.allowsBulkDownload('https://tile.openstreetmap.org/{z}/{x}/{y}.png'), isTrue);
    });
  });
}
