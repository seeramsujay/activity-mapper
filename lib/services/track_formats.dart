import 'dart:convert';
import 'db_service.dart';

/// Pure serializers for recorded tracks (no I/O), shared by [ExportService] and [GpxService].
///
/// Input points are SQLite rows from the `points` table: `timestamp` (epoch ms), `lat`, `lng`,
/// `altitude` (m), `accuracy` (m) and `speed` (m/s).
class TrackFormats {
  TrackFormats._();

  /// Escapes text for use in XML element content and attribute values.
  static String xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _isoUtc(int epochMs) => DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toIso8601String();

  static double _num(Object? v) => (v as num?)?.toDouble() ?? 0.0;

  /// Coordinates are written with fixed precision (7 decimals ≈ 1 cm) so tiny values never use
  /// exponent notation, which GPX/KML parsers reject.
  static String _coord(Object? v) => _num(v).toStringAsFixed(7);

  /// GPX 1.1 with elevation, UTC time and speed in the Garmin TrackPointExtension namespace.
  ///
  /// [altitudes] optionally replaces the raw altitude per point (e.g. smoothed elevation).
  static String buildGpx(
    List<Map<String, dynamic>> points,
    String activityName, {
    List<double>? altitudes,
    DateTime? exportedAt,
  }) {
    final name = xmlEscape(activityName);
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="TurnBack - Serverless Endurance Tracker" '
          'xmlns="http://www.topografix.com/GPX/1/1" '
          'xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
          'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">')
      ..writeln('  <metadata>')
      ..writeln('    <name>$name</name>')
      ..writeln('    <time>${(exportedAt ?? DateTime.now()).toUtc().toIso8601String()}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>$name</name>')
      ..writeln('    <trkseg>');

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final ele = altitudes != null && i < altitudes.length ? altitudes[i] : _num(p['altitude']);
      buffer
        ..write('      <trkpt lat="${_coord(p['lat'])}" lon="${_coord(p['lng'])}">')
        ..write('<ele>${ele.toStringAsFixed(1)}</ele>')
        ..write('<time>${_isoUtc(p['timestamp'] as int)}</time>')
        ..write('<extensions><gpxtpx:TrackPointExtension>'
            '<gpxtpx:speed>${_num(p['speed']).toStringAsFixed(2)}</gpxtpx:speed>'
            '</gpxtpx:TrackPointExtension></extensions>')
        ..writeln('</trkpt>');
    }

    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  /// Google Earth KML with start/finish placemarks and the route LineString.
  static String buildKml(List<Map<String, dynamic>> points, String activityName) {
    final name = xmlEscape(activityName);
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
      ..writeln('  <Document>')
      ..writeln('    <name>$name</name>')
      ..writeln('    <Style id="trackLine">')
      ..writeln('      <LineStyle>')
      ..writeln('        <color>ff0000ff</color>') // Red line (AABBGGRR)
      ..writeln('        <width>4</width>')
      ..writeln('      </LineStyle>')
      ..writeln('    </Style>');

    String coord(Map<String, dynamic> p) =>
        '${_coord(p['lng'])},${_coord(p['lat'])},${_num(p['altitude']).toStringAsFixed(1)}';

    if (points.isNotEmpty) {
      for (final entry in [('Start', points.first), ('Finish', points.last)]) {
        buffer
          ..writeln('    <Placemark>')
          ..writeln('      <name>${entry.$1}</name>')
          ..writeln('      <Point>')
          ..writeln('        <coordinates>${coord(entry.$2)}</coordinates>')
          ..writeln('      </Point>')
          ..writeln('    </Placemark>');
      }
    }

    buffer
      ..writeln('    <Placemark>')
      ..writeln('      <name>$name Route</name>')
      ..writeln('      <styleUrl>#trackLine</styleUrl>')
      ..writeln('      <LineString>')
      ..writeln('        <tessellate>1</tessellate>')
      ..writeln('        <altitudeMode>clampToGround</altitudeMode>')
      ..writeln('        <coordinates>');
    for (final p in points) {
      buffer.writeln('          ${coord(p)}');
    }
    buffer
      ..writeln('        </coordinates>')
      ..writeln('      </LineString>')
      ..writeln('    </Placemark>')
      ..writeln('  </Document>')
      ..writeln('</kml>');
    return buffer.toString();
  }

  /// RFC 7946 GeoJSON FeatureCollection with per-point telemetry in the properties.
  static String buildGeoJson(
    List<Map<String, dynamic>> points,
    String activityName, {
    required int sessionId,
    DateTime? exportedAt,
  }) {
    final coordinates = <List<double>>[];
    final telemetry = <Map<String, dynamic>>[];
    for (final p in points) {
      coordinates.add([_num(p['lng']), _num(p['lat']), _num(p['altitude'])]);
      telemetry.add({
        'timestamp': p['timestamp'],
        'time_iso': _isoUtc(p['timestamp'] as int),
        'speed_mps': _num(p['speed']),
        'accuracy_m': _num(p['accuracy']),
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
            'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
            'telemetry': telemetry,
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

  /// Header row of [buildCsv].
  static const String csvHeader =
      'index,timestamp_epoch_ms,datetime_utc,latitude,longitude,altitude_m,accuracy_m,speed_mps,speed_kmh';

  /// Raw tabular telemetry, one row per point.
  static String buildCsv(List<Map<String, dynamic>> points) {
    final buffer = StringBuffer()..writeln(csvHeader);
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final ts = p['timestamp'] as int;
      final speed = _num(p['speed']);
      buffer.writeln([
        i,
        ts,
        _isoUtc(ts),
        _coord(p['lat']),
        _coord(p['lng']),
        _num(p['altitude']).toStringAsFixed(2),
        _num(p['accuracy']).toStringAsFixed(2),
        speed.toStringAsFixed(2),
        (speed * 3.6).toStringAsFixed(2),
      ].join(','));
    }
    return buffer.toString();
  }

  /// TCX `Sport` attribute for an activity type ("Running", "Biking" or "Other").
  static String tcxSport(String activityType) {
    final t = activityType.toLowerCase();
    if (t.contains('ride') || t.contains('cycl') || t.contains('bike')) return 'Biking';
    if (t.contains('run') || t.contains('walk') || t.contains('hike') || t.contains('freerun')) return 'Running';
    return 'Other';
  }

  /// Garmin Training Center Database (TCX v2) with cumulative distance per trackpoint, as
  /// required by Garmin Connect / Strava / TrainingPeaks imports.
  static String buildTcx(
    List<Map<String, dynamic>> points,
    String activityType, {
    int calories = 0,
    DateTime? fallbackStart,
  }) {
    final startIso = points.isNotEmpty
        ? _isoUtc(points.first['timestamp'] as int)
        : (fallbackStart ?? DateTime.now()).toUtc().toIso8601String();

    int totalSeconds = 0;
    if (points.length >= 2) {
      totalSeconds = (((points.last['timestamp'] as int) - (points.first['timestamp'] as int)) / 1000).round();
    }

    // Speeds are stored in m/s, which is also TCX's unit.
    double maxSpeedMps = 0.0;
    for (final p in points) {
      final v = _num(p['speed']);
      if (v > maxSpeedMps) maxSpeedMps = v;
    }

    final cumulativeMeters = <double>[];
    double running = 0.0;
    for (int i = 0; i < points.length; i++) {
      if (i > 0) {
        running += DbService.calculateDistanceKm(
              _num(points[i - 1]['lat']),
              _num(points[i - 1]['lng']),
              _num(points[i]['lat']),
              _num(points[i]['lng']),
            ) *
            1000.0;
      }
      cumulativeMeters.add(running);
    }

    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" '
          'xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
          'xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">')
      ..writeln('  <Activities>')
      ..writeln('    <Activity Sport="${tcxSport(activityType)}">')
      ..writeln('      <Id>$startIso</Id>')
      ..writeln('      <Lap StartTime="$startIso">')
      ..writeln('        <TotalTimeSeconds>$totalSeconds</TotalTimeSeconds>')
      ..writeln('        <DistanceMeters>${running.toStringAsFixed(1)}</DistanceMeters>')
      ..writeln('        <MaximumSpeed>${maxSpeedMps.toStringAsFixed(2)}</MaximumSpeed>')
      ..writeln('        <Calories>$calories</Calories>')
      ..writeln('        <Intensity>Active</Intensity>')
      ..writeln('        <TriggerMethod>Manual</TriggerMethod>')
      ..writeln('        <Track>');

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      buffer
        ..writeln('          <Trackpoint>')
        ..writeln('            <Time>${_isoUtc(p['timestamp'] as int)}</Time>')
        ..writeln('            <Position>')
        ..writeln('              <LatitudeDegrees>${_coord(p['lat'])}</LatitudeDegrees>')
        ..writeln('              <LongitudeDegrees>${_coord(p['lng'])}</LongitudeDegrees>')
        ..writeln('            </Position>')
        ..writeln('            <AltitudeMeters>${_num(p['altitude']).toStringAsFixed(1)}</AltitudeMeters>')
        ..writeln('            <DistanceMeters>${cumulativeMeters[i].toStringAsFixed(1)}</DistanceMeters>')
        ..writeln('            <Extensions>')
        ..writeln('              <ns3:TPX>')
        ..writeln('                <ns3:Speed>${_num(p['speed']).toStringAsFixed(2)}</ns3:Speed>')
        ..writeln('              </ns3:TPX>')
        ..writeln('            </Extensions>')
        ..writeln('          </Trackpoint>');
    }

    buffer
      ..writeln('        </Track>')
      ..writeln('      </Lap>')
      ..writeln('    </Activity>')
      ..writeln('  </Activities>')
      ..writeln('</TrainingCenterDatabase>');
    return buffer.toString();
  }
}
