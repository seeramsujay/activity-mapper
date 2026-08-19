import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

/// Comprehensive multi-format telemetry exporter and ZIP packaging service.
///
/// Supports GPX 1.1, KML, GeoJSON (RFC 7946), CSV, and bundled ZIP archiving.
/// 100% offline-first and serverless.
class ExportService {
  /// The singleton instance of [ExportService].
  static final ExportService instance = ExportService._init();

  ExportService._init();

  /// Generates a standard GPX 1.1 XML string for the specified session.
  Future<String> generateGpxString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="TurnBack - Serverless Endurance Tracker" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">');

    final now = DateTime.now().toUtc().toIso8601String();
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name><![CDATA[$activityName]]></name>');
    buffer.writeln('    <time>$now</time>');
    buffer.writeln('  </metadata>');

    buffer.writeln('  <trk>');
    buffer.writeln('    <name><![CDATA[$activityName]]></name>');
    buffer.writeln('    <trkseg>');

    for (final point in points) {
      final lat = point['lat'];
      final lng = point['lng'];
      final altitude = point['altitude'] ?? 0.0;
      final speed = point['speed'] ?? 0.0;
      final timestamp = point['timestamp'] as int;
      final timeStr = DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc().toIso8601String();

      buffer.write('      <trkpt lat="$lat" lon="$lng">');
      buffer.write('<ele>$altitude</ele>');
      buffer.write('<time>$timeStr</time>');
      buffer.write('<extensions><speed>$speed</speed></extensions>');
      buffer.writeln('</trkpt>');
    }

    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  /// Generates a Google Earth compatible KML string for the session.
  Future<String> generateKmlString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buffer.writeln('  <Document>');
    buffer.writeln('    <name><![CDATA[$activityName]]></name>');
    buffer.writeln('    <Style id="trackLine">');
    buffer.writeln('      <LineStyle>');
    buffer.writeln('        <color>ff0000ff</color>'); // Red line (AABBGGRR)
    buffer.writeln('        <width>4</width>');
    buffer.writeln('      </LineStyle>');
    buffer.writeln('    </Style>');

    if (points.isNotEmpty) {
      final first = points.first;
      final last = points.last;

      // Start Placemark
      buffer.writeln('    <Placemark>');
      buffer.writeln('      <name>Start</name>');
      buffer.writeln('      <Point>');
      buffer.writeln('        <coordinates>${first['lng']},${first['lat']},${first['altitude'] ?? 0}</coordinates>');
      buffer.writeln('      </Point>');
      buffer.writeln('    </Placemark>');

      // Finish Placemark
      buffer.writeln('    <Placemark>');
      buffer.writeln('      <name>Finish</name>');
      buffer.writeln('      <Point>');
      buffer.writeln('        <coordinates>${last['lng']},${last['lat']},${last['altitude'] ?? 0}</coordinates>');
      buffer.writeln('      </Point>');
      buffer.writeln('    </Placemark>');
    }

    // Path LineString
    buffer.writeln('    <Placemark>');
    buffer.writeln('      <name><![CDATA[$activityName Route]]></name>');
    buffer.writeln('      <styleUrl>#trackLine</styleUrl>');
    buffer.writeln('      <LineString>');
    buffer.writeln('        <extrude>1</extrude>');
    buffer.writeln('        <tessellate>1</tessellate>');
    buffer.writeln('        <altitudeMode>clampToGround</altitudeMode>');
    buffer.writeln('        <coordinates>');

    for (final point in points) {
      final lat = point['lat'];
      final lng = point['lng'];
      final alt = point['altitude'] ?? 0.0;
      buffer.writeln('          $lng,$lat,$alt');
    }

    buffer.writeln('        </coordinates>');
    buffer.writeln('      </LineString>');
    buffer.writeln('    </Placemark>');

    buffer.writeln('  </Document>');
    buffer.writeln('</kml>');

    return buffer.toString();
  }

  /// Generates an RFC 7946 compliant GeoJSON string for the session.
  Future<String> generateGeoJsonString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);

    final List<List<dynamic>> coordinates = [];
    final List<Map<String, dynamic>> pointProperties = [];

    for (final p in points) {
      coordinates.add([
        p['lng'],
        p['lat'],
        p['altitude'] ?? 0.0,
      ]);
      pointProperties.add({
        'timestamp': p['timestamp'],
        'time_iso': DateTime.fromMillisecondsSinceEpoch(p['timestamp'] as int).toUtc().toIso8601String(),
        'speed_mps': p['speed'] ?? 0.0,
        'accuracy_m': p['accuracy'] ?? 0.0,
      });
    }

    final geoJson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {
            'sessionId': sessionId,
            'activityName': activityName,
            'pointCount': points.length,
            'exportedAt': DateTime.now().toUtc().toIso8601String(),
            'telemetry': pointProperties,
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': coordinates,
          },
        }
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(geoJson);
  }

  /// Generates a CSV string containing detailed point telemetry.
  Future<String> generateCsvString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);
    final buffer = StringBuffer();

    // CSV Header
    buffer.writeln('index,timestamp_epoch_ms,datetime_utc,latitude,longitude,altitude_m,accuracy_m,speed_mps,speed_kmh');

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final ts = p['timestamp'] as int;
      final iso = DateTime.fromMillisecondsSinceEpoch(ts).toUtc().toIso8601String();
      final lat = p['lat'];
      final lng = p['lng'];
      final alt = (p['altitude'] as num?)?.toStringAsFixed(2) ?? '0.00';
      final acc = (p['accuracy'] as num?)?.toStringAsFixed(2) ?? '0.00';
      final speedMps = (p['speed'] as num?)?.toDouble() ?? 0.0;
      final speedKmh = (speedMps * 3.6).toStringAsFixed(2);

      buffer.writeln('$i,$ts,$iso,$lat,$lng,$alt,$acc,${speedMps.toStringAsFixed(2)},$speedKmh');
    }

    return buffer.toString();
  }

  /// Creates a unified ZIP bundle containing GPX, KML, GeoJSON, and CSV files for a single session.
  Future<File> exportSessionZipBundle(int sessionId, String activityName) async {
    final archive = Archive();
    final sanitizedName = _sanitizeFilename(activityName);

    // 1. Generate GPX
    final gpxStr = await generateGpxString(sessionId, activityName);
    final gpxBytes = utf8.encode(gpxStr);
    archive.addFile(ArchiveFile('$sanitizedName.gpx', gpxBytes.length, gpxBytes));

    // 2. Generate KML
    final kmlStr = await generateKmlString(sessionId, activityName);
    final kmlBytes = utf8.encode(kmlStr);
    archive.addFile(ArchiveFile('$sanitizedName.kml', kmlBytes.length, kmlBytes));

    // 3. Generate GeoJSON
    final geoJsonStr = await generateGeoJsonString(sessionId, activityName);
    final geoJsonBytes = utf8.encode(geoJsonStr);
    archive.addFile(ArchiveFile('$sanitizedName.geojson', geoJsonBytes.length, geoJsonBytes));

    // 4. Generate CSV
    final csvStr = await generateCsvString(sessionId, activityName);
    final csvBytes = utf8.encode(csvStr);
    archive.addFile(ArchiveFile('$sanitizedName.csv', csvBytes.length, csvBytes));

    // 5. Compress
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('ZIP compression failed.');
    }

    final outDir = await _getExportDirectory();
    final zipFile = File(p.join(
      outDir.path,
      'turnback_session_${sessionId}_${sanitizedName}_${DateTime.now().millisecondsSinceEpoch}.zip',
    ));

    return await zipFile.writeAsBytes(zipData, flush: true);
  }

  /// Creates a complete lifetime backup ZIP archive including all sessions across all formats and SQLite DB.
  Future<File> exportLifetimeZipBackup() async {
    final archive = Archive();
    final dbHelper = DbService.instance;
    final sessions = await dbHelper.getSessions();

    // 1. Export all sessions in all formats
    for (final s in sessions) {
      final id = s['id'] as int;
      final type = (s['activity_type'] as String?) ?? 'run';
      final name = '${type}_session_$id';
      final sanitized = _sanitizeFilename(name);

      final gpx = await generateGpxString(id, name);
      final gpxBytes = utf8.encode(gpx);
      archive.addFile(ArchiveFile('sessions/gpx/$sanitized.gpx', gpxBytes.length, gpxBytes));

      final kml = await generateKmlString(id, name);
      final kmlBytes = utf8.encode(kml);
      archive.addFile(ArchiveFile('sessions/kml/$sanitized.kml', kmlBytes.length, kmlBytes));

      final geoJson = await generateGeoJsonString(id, name);
      final geoJsonBytes = utf8.encode(geoJson);
      archive.addFile(ArchiveFile('sessions/geojson/$sanitized.geojson', geoJsonBytes.length, geoJsonBytes));

      final csv = await generateCsvString(id, name);
      final csvBytes = utf8.encode(csv);
      archive.addFile(ArchiveFile('sessions/csv/$sanitized.csv', csvBytes.length, csvBytes));
    }

    // 2. Include SQLite database snapshot & WAL files
    String dbPath;
    if (Platform.isAndroid) {
      dbPath = p.join(await getDatabasesPath(), 'turnback.db');
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      dbPath = p.join(dbFolder.path, 'turnback.db');
    }

    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database/turnback.db', dbBytes.length, dbBytes));

      final walFile = File('$dbPath-wal');
      if (await walFile.exists()) {
        final walBytes = await walFile.readAsBytes();
        archive.addFile(ArchiveFile('database/turnback.db-wal', walBytes.length, walBytes));
      }

      final shmFile = File('$dbPath-shm');
      if (await shmFile.exists()) {
        final shmBytes = await shmFile.readAsBytes();
        archive.addFile(ArchiveFile('database/turnback.db-shm', shmBytes.length, shmBytes));
      }
    }

    // 3. Compress
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('Full ZIP backup compression failed.');
    }

    final outDir = await _getExportDirectory();
    final backupFile = File(p.join(
      outDir.path,
      'turnback_full_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
    ));

    return await backupFile.writeAsBytes(zipData, flush: true);
  }

  /// Generates a Garmin/Wahoo Training Center Database (TCX) XML file string.
  Future<String> generateTcxString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);

    final buffer = StringBuffer();
    final startTime = points.isNotEmpty
        ? DateTime.fromMillisecondsSinceEpoch(points.first['timestamp'] as int).toUtc().toIso8601String()
        : DateTime.now().toUtc().toIso8601String();

    int totalSeconds = 0;
    if (points.length >= 2) {
      final first = points.first['timestamp'] as int;
      final last = points.last['timestamp'] as int;
      totalSeconds = ((last - first) / 1000).round();
    }

    double maxSpeedMs = 0.0;
    for (final p in points) {
      final spdKmh = ((p['speed'] as num?)?.toDouble()) ?? 0.0;
      final ms = spdKmh / 3.6;
      if (ms > maxSpeedMs) maxSpeedMs = ms;
    }

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">');
    buffer.writeln('  <Activities>');
    buffer.writeln('    <Activity Sport="Running">');
    buffer.writeln('      <Id>$startTime</Id>');
    buffer.writeln('      <Lap StartTime="$startTime">');
    buffer.writeln('        <TotalTimeSeconds>$totalSeconds</TotalTimeSeconds>');
    buffer.writeln('        <MaximumSpeed>${maxSpeedMs.toStringAsFixed(2)}</MaximumSpeed>');
    buffer.writeln('        <Calories>0</Calories>');
    buffer.writeln('        <Intensity>Active</Intensity>');
    buffer.writeln('        <TriggerMethod>Manual</TriggerMethod>');
    buffer.writeln('        <Track>');

    double runningDistance = 0.0;
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final lat = point['lat'];
      final lng = point['lng'];
      final altitude = point['altitude'] ?? 0.0;
      final speedKmh = ((point['speed'] as num?)?.toDouble()) ?? 0.0;
      final speedMs = speedKmh / 3.6;
      final timestamp = point['timestamp'] as int;
      final timeStr = DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc().toIso8601String();

      buffer.writeln('          <Trackpoint>');
      buffer.writeln('            <Time>$timeStr</Time>');
      buffer.writeln('            <Position>');
      buffer.writeln('              <LatitudeDegrees>$lat</LatitudeDegrees>');
      buffer.writeln('              <LongitudeDegrees>$lng</LongitudeDegrees>');
      buffer.writeln('            </Position>');
      buffer.writeln('            <AltitudeMeters>$altitude</AltitudeMeters>');
      buffer.writeln('            <Extensions>');
      buffer.writeln('              <TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2">');
      buffer.writeln('                <Speed>${speedMs.toStringAsFixed(2)}</Speed>');
      buffer.writeln('              </TPX>');
      buffer.writeln('            </Extensions>');
      buffer.writeln('          </Trackpoint>');
    }

    buffer.writeln('        </Track>');
    buffer.writeln('      </Lap>');
    buffer.writeln('    </Activity>');
    buffer.writeln('  </Activities>');
    buffer.writeln('</TrainingCenterDatabase>');

    return buffer.toString();
  }

  /// Exports an individual single format file (GPX, TCX, KML, GeoJSON, or CSV).
  Future<File> exportSingleFormat({
    required int sessionId,
    required String activityName,
    required String format, // 'gpx', 'tcx', 'kml', 'geojson', 'csv'
  }) async {
    final sanitized = _sanitizeFilename(activityName);
    final outDir = await _getExportDirectory();
    String content;
    String ext;

    switch (format.toLowerCase()) {
      case 'tcx':
        content = await generateTcxString(sessionId, activityName);
        ext = 'tcx';
        break;
      case 'kml':
        content = await generateKmlString(sessionId, activityName);
        ext = 'kml';
        break;
      case 'geojson':
        content = await generateGeoJsonString(sessionId, activityName);
        ext = 'geojson';
        break;
      case 'csv':
        content = await generateCsvString(sessionId, activityName);
        ext = 'csv';
        break;
      case 'gpx':
      default:
        content = await generateGpxString(sessionId, activityName);
        ext = 'gpx';
        break;
    }

    final file = File(p.join(outDir.path, 'turnback_${sanitized}_$sessionId.$ext'));
    return await file.writeAsString(content, flush: true);
  }

  Future<Directory> _getExportDirectory() async {
    Directory? directory;
    if (Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final rootPath = extDir.path.split('/Android/data/')[0];
          directory = Directory(p.join(rootPath, 'Documents', 'TurnBack'));
        }
      } catch (_) {}
    }
    directory ??= await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_').toLowerCase();
  }
}
