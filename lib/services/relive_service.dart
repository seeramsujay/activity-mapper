import 'dart:math';
import 'elevation_filter_service.dart';
import '../models/location_point.dart';

/// Service generating specialized GPX 1.1 tracks formatted for the Relive 3D Aerial Route Video Engine.
///
/// Features:
/// - 1D Kalman & Savitzky-Golay polynomial elevation smoothing for photorealistic 3D flyovers.
/// - Milestone `<wpt>` waypoint markers for Start, Summit (Peak Elevation), Max Speed, Turn-Back, and Finish.
class ReliveService {
  static final ReliveService instance = ReliveService._internal();
  ReliveService._internal();

  /// Generates a Relive 3D compliant GPX 1.1 XML string.
  String generateReliveGpx({
    required String activityName,
    required List<Map<String, dynamic>> rawPoints,
    int? turnBackTriggeredAt,
  }) {
    if (rawPoints.isEmpty) {
      return _generateEmptyGpx(activityName);
    }

    // 1. Extract raw elevations and smooth with Kalman & Savitzky-Golay filter
    final rawElevations = rawPoints.map((p) => (p['altitude'] as num?)?.toDouble() ?? 0.0).toList();
    final smoothedElevations = ElevationFilterService.instance.filterFullElevationProfile(rawElevations);

    // 2. Identify key waypoints / milestones
    int maxEleIdx = 0;
    double maxEleVal = -double.maxFinite;

    int maxSpeedIdx = 0;
    double maxSpeedVal = -1.0;

    int turnBackIdx = -1;

    for (int i = 0; i < rawPoints.length; i++) {
      final ele = smoothedElevations[i];
      if (ele > maxEleVal) {
        maxEleVal = ele;
        maxEleIdx = i;
      }

      final spd = (rawPoints[i]['speed'] as num?)?.toDouble() ?? 0.0;
      if (spd > maxSpeedVal) {
        maxSpeedVal = spd;
        maxSpeedIdx = i;
      }

      if (turnBackTriggeredAt != null && turnBackIdx == -1) {
        final ts = rawPoints[i]['timestamp'] as int;
        if (ts >= turnBackTriggeredAt) {
          turnBackIdx = i;
        }
      }
    }

    // If no explicit turn_back timestamp was logged, estimate at middle point
    if (turnBackIdx == -1 && rawPoints.length > 4) {
      turnBackIdx = rawPoints.length ~/ 2;
    }

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="TurnBack - Relive 3D Video Bridge" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">');

    final nowIso = DateTime.now().toUtc().toIso8601String();
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name><![CDATA[$activityName (Relive 3D Route)]]></name>');
    buffer.writeln('    <desc>Optimized 3D flyover video track with smoothed elevations and waypoints.</desc>');
    buffer.writeln('    <time>$nowIso</time>');
    buffer.writeln('  </metadata>');

    // 3. Add Waypoints (<wpt>) for Relive 3D callouts
    final startPt = rawPoints.first;
    final startEle = smoothedElevations.first;
    final startTime = DateTime.fromMillisecondsSinceEpoch(startPt['timestamp'] as int).toUtc().toIso8601String();
    buffer.writeln('  <wpt lat="${startPt['lat']}" lon="${startPt['lng']}">');
    buffer.writeln('    <ele>${startEle.toStringAsFixed(1)}</ele>');
    buffer.writeln('    <time>$startTime</time>');
    buffer.writeln('    <name>Start</name>');
    buffer.writeln('    <sym>flag</sym>');
    buffer.writeln('  </wpt>');

    if (maxEleIdx > 0 && maxEleIdx < rawPoints.length - 1) {
      final summitPt = rawPoints[maxEleIdx];
      final summitTime = DateTime.fromMillisecondsSinceEpoch(summitPt['timestamp'] as int).toUtc().toIso8601String();
      buffer.writeln('  <wpt lat="${summitPt['lat']}" lon="${summitPt['lng']}">');
      buffer.writeln('    <ele>${maxEleVal.toStringAsFixed(1)}</ele>');
      buffer.writeln('    <time>$summitTime</time>');
      buffer.writeln('    <name>Summit (${maxEleVal.toStringAsFixed(0)}m)</name>');
      buffer.writeln('    <sym>summit</sym>');
      buffer.writeln('  </wpt>');
    }

    if (turnBackIdx > 0 && turnBackIdx < rawPoints.length - 1 && turnBackIdx != maxEleIdx) {
      final tbPt = rawPoints[turnBackIdx];
      final tbEle = smoothedElevations[turnBackIdx];
      final tbTime = DateTime.fromMillisecondsSinceEpoch(tbPt['timestamp'] as int).toUtc().toIso8601String();
      buffer.writeln('  <wpt lat="${tbPt['lat']}" lon="${tbPt['lng']}">');
      buffer.writeln('    <ele>${tbEle.toStringAsFixed(1)}</ele>');
      buffer.writeln('    <time>$tbTime</time>');
      buffer.writeln('    <name>Turn-Back Point</name>');
      buffer.writeln('    <sym>turnaround</sym>');
      buffer.writeln('  </wpt>');
    }

    if (maxSpeedIdx > 0 && maxSpeedIdx < rawPoints.length - 1 && maxSpeedIdx != maxEleIdx && maxSpeedIdx != turnBackIdx) {
      final spdPt = rawPoints[maxSpeedIdx];
      final spdEle = smoothedElevations[maxSpeedIdx];
      final spdTime = DateTime.fromMillisecondsSinceEpoch(spdPt['timestamp'] as int).toUtc().toIso8601String();
      final kmh = (maxSpeedVal * 3.6).toStringAsFixed(1);
      buffer.writeln('  <wpt lat="${spdPt['lat']}" lon="${spdPt['lng']}">');
      buffer.writeln('    <ele>${spdEle.toStringAsFixed(1)}</ele>');
      buffer.writeln('    <time>$spdTime</time>');
      buffer.writeln('    <name>Top Speed ($kmh km/h)</name>');
      buffer.writeln('    <sym>speed</sym>');
      buffer.writeln('  </wpt>');
    }

    final finishPt = rawPoints.last;
    final finishEle = smoothedElevations.last;
    final finishTime = DateTime.fromMillisecondsSinceEpoch(finishPt['timestamp'] as int).toUtc().toIso8601String();
    buffer.writeln('  <wpt lat="${finishPt['lat']}" lon="${finishPt['lng']}">');
    buffer.writeln('    <ele>${finishEle.toStringAsFixed(1)}</ele>');
    buffer.writeln('    <time>$finishTime</time>');
    buffer.writeln('    <name>Finish</name>');
    buffer.writeln('    <sym>finish</sym>');
    buffer.writeln('  </wpt>');

    // 4. Write Main Smoothed Track Segment
    buffer.writeln('  <trk>');
    buffer.writeln('    <name><![CDATA[$activityName]]></name>');
    buffer.writeln('    <trkseg>');

    for (int i = 0; i < rawPoints.length; i++) {
      final pt = rawPoints[i];
      final lat = pt['lat'];
      final lng = pt['lng'];
      final ele = smoothedElevations[i].toStringAsFixed(1);
      final spd = pt['speed'] ?? 0.0;
      final ts = pt['timestamp'] as int;
      final timeStr = DateTime.fromMillisecondsSinceEpoch(ts).toUtc().toIso8601String();

      buffer.writeln('      <trkpt lat="$lat" lon="$lng">');
      buffer.writeln('        <ele>$ele</ele>');
      buffer.writeln('        <time>$timeStr</time>');
      buffer.writeln('        <extensions><speed>$spd</speed></extensions>');
      buffer.writeln('      </trkpt>');
    }

    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  String _generateEmptyGpx(String name) {
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="TurnBack"><metadata><name>$name</name></metadata></gpx>';
  }
}
