import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';
import 'relive_service.dart';
import 'track_formats.dart';

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
    return TrackFormats.buildGpx(points, activityName);
  }

  /// Generates a Google Earth compatible KML string for the session.
  Future<String> generateKmlString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);
    return TrackFormats.buildKml(points, activityName);
  }

  /// Generates an RFC 7946 compliant GeoJSON string for the session.
  Future<String> generateGeoJsonString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);
    return TrackFormats.buildGeoJson(points, activityName, sessionId: sessionId);
  }

  /// Generates a CSV string containing detailed point telemetry.
  Future<String> generateCsvString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);
    return TrackFormats.buildCsv(points);
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

    // Fold the WAL into the main file first so the copied database is a consistent snapshot.
    try {
      final db = await dbHelper.database;
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}

    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database/turnback.db', dbBytes.length, dbBytes));

      // Only present if a writer raced the checkpoint; restore it alongside the DB file.
      final walFile = File('$dbPath-wal');
      if (await walFile.exists() && await walFile.length() > 0) {
        final walBytes = await walFile.readAsBytes();
        archive.addFile(ArchiveFile('database/turnback.db-wal', walBytes.length, walBytes));
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
    final session = await DbService.instance.getSession(sessionId);
    final activityType = session?['activity_type'] as String? ?? activityName;
    return TrackFormats.buildTcx(points, activityType);
  }

  /// Generates a Relive 3D compliant GPX file string with Kalman-smoothed elevations and waypoints.
  Future<String> generateReliveGpxString(int sessionId, String activityName) async {
    final points = await DbService.instance.getPoints(sessionId);
    final session = await DbService.instance.getSession(sessionId);
    final turnBackTriggeredAt = session?['turn_back_triggered_at'] as int?;

    return ReliveService.instance.generateReliveGpx(
      activityName: activityName,
      rawPoints: points,
      turnBackTriggeredAt: turnBackTriggeredAt,
    );
  }

  /// Exports an individual single format file (GPX, TCX, KML, GeoJSON, CSV, or Relive 3D GPX).
  Future<File> exportSingleFormat({
    required int sessionId,
    required String activityName,
    required String format, // 'gpx', 'tcx', 'kml', 'geojson', 'csv', 'relive'
  }) async {
    final sanitized = _sanitizeFilename(activityName);
    final outDir = await _getExportDirectory();
    String content;
    String ext;

    switch (format.toLowerCase()) {
      case 'relive':
        content = await generateReliveGpxString(sessionId, activityName);
        ext = 'relive.gpx';
        break;
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
          final exportDir = Directory(p.join(extDir.path, 'Exports'));
          if (!await exportDir.exists()) {
            await exportDir.create(recursive: true);
          }
          return exportDir;
        }
      } catch (_) {}
    }
    directory = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory(p.join(directory.path, 'exports'));
    if (!await fallbackDir.exists()) {
      await fallbackDir.create(recursive: true);
    }
    return fallbackDir;
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_').toLowerCase();
  }
}
