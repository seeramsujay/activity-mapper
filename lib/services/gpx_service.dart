import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'db_service.dart';

/// Service responsible for serializing active session data into GPX XML formatted files.
class GpxService {
  /// The singleton instance of [GpxService].
  static final GpxService instance = GpxService._init();

  GpxService._init();

  /// Queries the database and compiles a GPX 1.1 compliant XML string for a session.
  ///
  /// Maps each location point coordinates, timestamps, and optional speed extensions.
  Future<String> generateGpxString(int sessionId, String activityName) async {
    final dbHelper = DbService.instance;
    final points = await dbHelper.getPoints(sessionId);

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="TurnBack" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">');

    // Meta segment
    final now = DateTime.now().toUtc().toIso8601String();
    buffer.writeln('  <metadata>');
    buffer.writeln('    <time>$now</time>');
    buffer.writeln('  </metadata>');

    // Track segment
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>$activityName</name>');
    buffer.writeln('    <trkseg>');

    for (final point in points) {
      final lat = point['lat'];
      final lng = point['lng'];
      final altitude = point['altitude'];
      final speed = point['speed'];
      final timeStr = DateTime.fromMillisecondsSinceEpoch(point['timestamp'] as int).toUtc().toIso8601String();

      buffer.write('      <trkpt lat="$lat" lon="$lng">');
      buffer.write('<ele>$altitude</ele>');
      buffer.write('<time>$timeStr</time>');
      // Optional speed extension
      buffer.write('<extensions><speed>$speed</speed></extensions>');
      buffer.writeln('</trkpt>');
    }

    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  /// Writes a GPX XML string to a file in the system's public Documents directory.
  ///
  /// On Android, resolves the external `/Documents/TurnBack` directory using path logic.
  /// Falls back to the sandboxed App Documents folder on failure or non-Android OS platforms.
  Future<File> saveGpxFile(int sessionId, String activityName) async {
    final gpxContent = await generateGpxString(sessionId, activityName);
    
    Directory? directory;
    if (Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final rootPath = extDir.path.split('/Android/data/')[0];
          directory = Directory(join(rootPath, 'Documents', 'TurnBack'));
        }
      } catch (e) {
        print("Failed to resolve external Documents directory: $e");
      }
    }
    
    // Fallback if not Android or path lookup failed
    directory ??= await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    final formattedName = activityName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_').toLowerCase();
    final fileName = 'turnback_${formattedName}_$sessionId.gpx';
    final file = File(join(directory.path, fileName));
    
    return await file.writeAsString(gpxContent, flush: true);
  }
}

