import 'dart:math';
import 'package:flutter/material.dart';
import '../models/teammate.dart';
import '../models/colab_models.dart';

/// A custom painter that draws an offline relative vector track trail on a canvas.
///
/// Features:
/// - Auto-scales coordinates to fit container bounds.
/// - Built-in Ramer-Douglas-Peucker (RDP) polyline decimation for 60 FPS rendering on 2GB RAM phones.
/// - Start marker ("O") and active heading direction arrow ("^").
/// - Live P2P Mesh Teammate position pucks, color-coded breadcrumbs, and status tags.
/// - Shared Group Waypoints & Meeting Points.
/// - High-contrast light and dark mode styling.
class BreadcrumbPainter extends CustomPainter {
  final List<Point<double>> points;
  final List<Teammate> teammates;
  final List<SharedWaypoint> sharedWaypoints;
  final Brightness brightness;
  final double simplificationEpsilon;
  final Offset panOffset;
  final double zoomScale;
  final bool isHeadingUp;
  final double headingRad;
  final bool isReturning;
  final Point<double>? turnaroundPoint;
  late final List<Point<double>> _renderPoints;

  BreadcrumbPainter({
    required this.points,
    this.teammates = const [],
    this.sharedWaypoints = const [],
    required this.brightness,
    this.simplificationEpsilon = 0.00005,
    this.panOffset = Offset.zero,
    this.zoomScale = 1.0,
    this.isHeadingUp = false,
    this.headingRad = 0.0,
    this.isReturning = false,
    this.turnaroundPoint,
  }) {
    if (points.length > 100 && simplificationEpsilon > 0) {
      _renderPoints = rdpSimplify(points, simplificationEpsilon);
    } else {
      _renderPoints = points;
    }
  }

  static List<Point<double>> rdpSimplify(List<Point<double>> pts, double epsilon) {
    if (pts.length < 3) return pts;

    int maxIndex = 0;
    double maxDist = 0.0;

    final Point<double> first = pts.first;
    final Point<double> last = pts.last;

    for (int i = 1; i < pts.length - 1; i++) {
      final dist = _perpendicularDistance(pts[i], first, last);
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }

    if (maxDist > epsilon) {
      final left = rdpSimplify(pts.sublist(0, maxIndex + 1), epsilon);
      final right = rdpSimplify(pts.sublist(maxIndex), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  static double _perpendicularDistance(Point<double> p, Point<double> lineStart, Point<double> lineEnd) {
    final double dx = lineEnd.x - lineStart.x;
    final double dy = lineEnd.y - lineStart.y;

    if (dx == 0.0 && dy == 0.0) {
      return sqrt(pow(p.x - lineStart.x, 2) + pow(p.y - lineStart.y, 2));
    }

    final double num = ((dy * p.x) - (dx * p.y) + (lineEnd.x * lineStart.y) - (lineEnd.y * lineStart.x)).abs();
    final double den = sqrt(pow(dy, 2) + pow(dx, 2));
    return num / den;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bool isDark = brightness == Brightness.dark;
    
    // Background subtle grid
    final Paint gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    const int gridSpacing = 36;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (_renderPoints.isEmpty) return;

    final double midLat = _renderPoints.map((p) => p.x).reduce((a, b) => a + b) / _renderPoints.length;
    final double cosLat = cos(midLat * pi / 180.0);

    double minLat = _renderPoints.first.x;
    double maxLat = _renderPoints.first.x;
    double minLng = _renderPoints.first.y;
    double maxLng = _renderPoints.first.y;

    for (final p in _renderPoints) {
      minLat = min(minLat, p.x);
      maxLat = max(maxLat, p.x);
      minLng = min(minLng, p.y);
      maxLng = max(maxLng, p.y);
    }

    final double latSpan = max(0.0001, maxLat - minLat);
    final double lngSpan = max(0.0001, (maxLng - minLng) * cosLat);

    final double padding = 28.0;
    final double availWidth = size.width - (padding * 2);
    final double availHeight = size.height - (padding * 2);

    final double scale = min(availWidth / lngSpan, availHeight / latSpan) * zoomScale;

    final double cx = (minLng + maxLng) / 2.0;
    final double cy = (minLat + maxLat) / 2.0;

    Offset toCanvasOffset(Point<double> p) {
      final double x = size.width / 2.0 + (p.y - cx) * cosLat * scale + panOffset.dx;
      final double y = size.height / 2.0 - (p.x - cy) * scale + panOffset.dy;
      return Offset(x, y);
    }

    final currentOff = toCanvasOffset(_renderPoints.last);

    // Compute live heading angle in screen space
    double activeHeading = headingRad;
    if (_renderPoints.length >= 2) {
      final prevOff = toCanvasOffset(_renderPoints[_renderPoints.length - 2]);
      final double dx = currentOff.dx - prevOff.dx;
      final double dy = currentOff.dy - prevOff.dy;
      if (dx != 0 || dy != 0) {
        activeHeading = atan2(dy, dx);
      }
    }

    final bool applyHeadingUp = isHeadingUp && _renderPoints.length >= 2;
    if (applyHeadingUp) {
      canvas.save();
      canvas.translate(currentOff.dx, currentOff.dy);
      canvas.rotate(-(activeHeading + (pi / 2)));
      canvas.translate(-currentOff.dx, -currentOff.dy);
    }

    // 1. Draw Teammates' Breadcrumb Trails
    for (final t in teammates) {
      if (!t.isActive || t.breadcrumbTrail.length < 2) continue;
      final tColor = t.color;
      final tPath = Path();
      final firstPt = toCanvasOffset(Point(t.breadcrumbTrail.first.lat, t.breadcrumbTrail.first.lng));
      tPath.moveTo(firstPt.dx, firstPt.dy);

      for (int i = 1; i < t.breadcrumbTrail.length; i++) {
        final pt = toCanvasOffset(Point(t.breadcrumbTrail[i].lat, t.breadcrumbTrail[i].lng));
        tPath.lineTo(pt.dx, pt.dy);
      }

      canvas.drawPath(
        tPath,
        Paint()
          ..color = tColor.withValues(alpha: 0.6)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // 2. Draw Local User Track Trail Shadow/Glow
    final Paint glowPaint = Paint()
      ..color = const Color(0xFFFF5722).withValues(alpha: 0.35)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint linePaint = Paint()
      ..color = const Color(0xFFFF4500)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();
    path.moveTo(toCanvasOffset(_renderPoints.first).dx, toCanvasOffset(_renderPoints.first).dy);

    for (int i = 1; i < _renderPoints.length; i++) {
      final off = toCanvasOffset(_renderPoints[i]);
      path.lineTo(off.dx, off.dy);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    // 2.5 Draw Return Route Guidance Polyline (if returning)
    if (isReturning && _renderPoints.length >= 2) {
      final Paint returnGlow = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.45)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final Paint returnLine = Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final Path returnPath = Path();
      returnPath.moveTo(currentOff.dx, currentOff.dy);

      for (int i = _renderPoints.length - 2; i >= 0; i--) {
        final pt = toCanvasOffset(_renderPoints[i]);
        returnPath.lineTo(pt.dx, pt.dy);
      }

      canvas.drawPath(returnPath, returnGlow);
      canvas.drawPath(returnPath, returnLine);

      // Draw Turnaround Marker
      final turnPt = turnaroundPoint != null ? toCanvasOffset(turnaroundPoint!) : currentOff;
      canvas.drawCircle(turnPt, 8.0, Paint()..color = const Color(0xFF3B82F6));
      canvas.drawCircle(turnPt, 8.0, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8);
      
      final turnSpan = const TextSpan(
        text: '🔄 U-TURN',
        style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
      );
      final turnTp = TextPainter(text: turnSpan, textDirection: TextDirection.ltr)..layout();
      final turnRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(turnPt.dx, turnPt.dy + 16.0), width: turnTp.width + 8.0, height: turnTp.height + 4.0),
        const Radius.circular(5.0),
      );
      canvas.drawRRect(turnRect, Paint()..color = Colors.black.withValues(alpha: 0.85));
      canvas.drawRRect(turnRect, Paint()..color = const Color(0xFF3B82F6)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      turnTp.paint(canvas, Offset(turnRect.left + 4.0, turnRect.top + 2.0));
    }

    // Draw Start / Finish Flag
    final startOff = toCanvasOffset(_renderPoints.first);
    final Paint startBgPaint = Paint()..color = isReturning ? const Color(0xFF3B82F6) : const Color(0xFF10B981);
    canvas.drawCircle(startOff, 7.5, startBgPaint);
    canvas.drawCircle(startOff, 7.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8);

    final String labelText = isReturning ? '🏁 FINISH' : '🚩 START';
    final TextSpan startSpan = TextSpan(
      text: labelText,
      style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
    );
    final TextPainter startTp = TextPainter(text: startSpan, textDirection: TextDirection.ltr)..layout();
    final startRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(startOff.dx, startOff.dy - 16.0), width: startTp.width + 8.0, height: startTp.height + 4.0),
      const Radius.circular(5.0),
    );
    canvas.drawRRect(startRect, Paint()..color = Colors.black.withValues(alpha: 0.85));
    canvas.drawRRect(startRect, Paint()..color = (isReturning ? const Color(0xFF3B82F6) : const Color(0xFF10B981))..style = PaintingStyle.stroke..strokeWidth = 1.0);
    startTp.paint(canvas, Offset(startRect.left + 4.0, startRect.top + 2.0));

    // 3. Draw Teammate Location Pucks & Badges
    for (final t in teammates) {
      if (!t.isActive) continue;
      final tColor = t.color;
      final tOff = toCanvasOffset(Point(t.lastLat, t.lastLng));

      canvas.drawCircle(tOff, 14.0, Paint()..color = tColor.withValues(alpha: 0.25));
      canvas.drawCircle(tOff, 6.5, Paint()..color = tColor);
      canvas.drawCircle(tOff, 6.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8);

      final labelText = '${t.username.isNotEmpty ? t.username : t.displayTag} • ${t.speedKmh.toStringAsFixed(0)}km/h';
      final textSpan = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(tOff.dx, tOff.dy - 16.0),
          width: tp.width + 10.0,
          height: tp.height + 4.0,
        ),
        const Radius.circular(6.0),
      );
      canvas.drawRRect(badgeRect, Paint()..color = Colors.black.withValues(alpha: 0.82));
      canvas.drawRRect(badgeRect, Paint()..color = tColor.withValues(alpha: 0.85)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      tp.paint(canvas, Offset(badgeRect.left + 5.0, badgeRect.top + 2.0));
    }

    // 3.5 Draw Shared Group Waypoints & POIs
    for (final wpt in sharedWaypoints) {
      final wptOff = toCanvasOffset(Point(wpt.lat, wpt.lng));
      final wptColor = wpt.color;

      canvas.drawCircle(wptOff, 12.0, Paint()..color = wptColor.withValues(alpha: 0.28));
      canvas.drawCircle(wptOff, 5.5, Paint()..color = wptColor);
      canvas.drawCircle(wptOff, 5.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);

      final textSpan = TextSpan(
        text: '📍 ${wpt.name}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(wptOff.dx, wptOff.dy - 14.0),
          width: tp.width + 8.0,
          height: tp.height + 4.0,
        ),
        const Radius.circular(4.0),
      );
      canvas.drawRRect(badgeRect, Paint()..color = Colors.black.withValues(alpha: 0.85));
      canvas.drawRRect(badgeRect, Paint()..color = wptColor.withValues(alpha: 0.85)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      tp.paint(canvas, Offset(badgeRect.left + 4.0, badgeRect.top + 2.0));
    }

    // 4. Draw Local User Current Position with Sleek Directional Navigation Vector Puck
    // Outer pulsating radar halo
    final Paint haloPaint = Paint()..color = const Color(0xFFFF5722).withValues(alpha: 0.25);
    canvas.drawCircle(currentOff, 18.0, haloPaint);

    // Draw Directional Navigation Vector Arrow
    canvas.save();
    canvas.translate(currentOff.dx, currentOff.dy);
    canvas.rotate(activeHeading + (pi / 2));

    // Vector Arrow Path
    final Path arrowPath = Path()
      ..moveTo(0, -14)
      ..lineTo(9, 10)
      ..lineTo(0, 5)
      ..lineTo(-9, 10)
      ..close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = const Color(0xFFFF4500)
        ..style = PaintingStyle.fill,
    );

    canvas.restore();

    if (applyHeadingUp) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant BreadcrumbPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.teammates.length != teammates.length ||
        oldDelegate.brightness != brightness ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.zoomScale != zoomScale ||
        oldDelegate.isHeadingUp != isHeadingUp ||
        oldDelegate.headingRad != headingRad ||
        oldDelegate.isReturning != isReturning ||
        oldDelegate.turnaroundPoint != turnaroundPoint;
  }
}

/// A custom painter that draws a GPS breadcrumb polyline aligned with an OSM raster tile grid.
class TileBreadcrumbPainter extends CustomPainter {
  final List<Point<double>> points;
  final List<Teammate> teammates;
  final List<SharedWaypoint> sharedWaypoints;
  final int zoom;
  final int startX;
  final int startY;
  final int xCount;
  final int yCount;
  final Brightness brightness;
  final Offset panOffset;
  final bool isHeadingUp;
  final double headingRad;
  final bool isReturning;
  final Point<double>? turnaroundPoint;

  TileBreadcrumbPainter({
    required this.points,
    this.teammates = const [],
    this.sharedWaypoints = const [],
    required this.zoom,
    required this.startX,
    required this.startY,
    required this.xCount,
    required this.yCount,
    required this.brightness,
    this.panOffset = Offset.zero,
    this.isHeadingUp = false,
    this.headingRad = 0.0,
    this.isReturning = false,
    this.turnaroundPoint,
  });

  double _lon2tileX(double lon, int zoom) {
    return (lon + 180.0) / 360.0 * (1 << zoom);
  }

  double _lat2tileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || xCount <= 0 || yCount <= 0) return;

    final double tileWidthPx = size.width / xCount;
    final double tileHeightPx = size.height / yCount;

    Offset toPixelOffset(Point<double> p) {
      final double tileX = _lon2tileX(p.y, zoom);
      final double tileY = _lat2tileY(p.x, zoom);
      final double x = (tileX - startX) * tileWidthPx + panOffset.dx;
      final double y = (tileY - startY) * tileHeightPx + panOffset.dy;
      return Offset(x, y);
    }

    final lastOff = toPixelOffset(points.last);

    double activeHeading = headingRad;
    if (points.length >= 2) {
      final prevOff = toPixelOffset(points[points.length - 2]);
      final double dx = lastOff.dx - prevOff.dx;
      final double dy = lastOff.dy - prevOff.dy;
      if (dx != 0 || dy != 0) {
        activeHeading = atan2(dy, dx);
      }
    }

    final bool applyHeadingUp = isHeadingUp && points.length >= 2;
    if (applyHeadingUp) {
      canvas.save();
      canvas.translate(lastOff.dx, lastOff.dy);
      canvas.rotate(-(activeHeading + (pi / 2)));
      canvas.translate(-lastOff.dx, -lastOff.dy);
    }

    // 1. Draw Teammate Breadcrumb Trails on OSM
    for (final t in teammates) {
      if (!t.isActive || t.breadcrumbTrail.length < 2) continue;
      final tColor = t.color;
      final tGlow = Paint()
        ..color = tColor.withValues(alpha: 0.3)
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final tLine = Paint()
        ..color = tColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final tPath = Path();
      final tFirst = toPixelOffset(Point(t.breadcrumbTrail.first.lat, t.breadcrumbTrail.first.lng));
      tPath.moveTo(tFirst.dx, tFirst.dy);
      for (int i = 1; i < t.breadcrumbTrail.length; i++) {
        final off = toPixelOffset(Point(t.breadcrumbTrail[i].lat, t.breadcrumbTrail[i].lng));
        tPath.lineTo(off.dx, off.dy);
      }
      canvas.drawPath(tPath, tGlow);
      canvas.drawPath(tPath, tLine);

      canvas.drawCircle(
        tFirst,
        4.0,
        Paint()
          ..color = tColor
          ..style = PaintingStyle.fill
          ..strokeCap = StrokeCap.round,
      );
    }

    // 2. Draw Local User Track
    final Paint glowPaint = Paint()
      ..color = const Color(0xFFFF5722).withValues(alpha: 0.35)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint linePaint = Paint()
      ..color = const Color(0xFFFF4500)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();
    final firstOff = toPixelOffset(points.first);
    path.moveTo(firstOff.dx, firstOff.dy);

    for (int i = 1; i < points.length; i++) {
      final off = toPixelOffset(points[i]);
      path.lineTo(off.dx, off.dy);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    // 2.5 Draw Return Guidance Path (if returning)
    if (isReturning && points.length >= 2) {
      final Paint returnGlow = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.45)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final Paint returnLine = Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final Path returnPath = Path();
      returnPath.moveTo(lastOff.dx, lastOff.dy);

      for (int i = points.length - 2; i >= 0; i--) {
        final off = toPixelOffset(points[i]);
        returnPath.lineTo(off.dx, off.dy);
      }

      canvas.drawPath(returnPath, returnGlow);
      canvas.drawPath(returnPath, returnLine);

      // Turnaround pin
      final turnPt = turnaroundPoint != null ? toPixelOffset(turnaroundPoint!) : lastOff;
      canvas.drawCircle(turnPt, 8.0, Paint()..color = const Color(0xFF3B82F6));
      canvas.drawCircle(turnPt, 8.0, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8);
      
      final turnSpan = const TextSpan(
        text: '🔄 U-TURN',
        style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
      );
      final turnTp = TextPainter(text: turnSpan, textDirection: TextDirection.ltr)..layout();
      final turnRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(turnPt.dx, turnPt.dy + 16.0), width: turnTp.width + 8.0, height: turnTp.height + 4.0),
        const Radius.circular(5.0),
      );
      canvas.drawRRect(turnRect, Paint()..color = Colors.black.withValues(alpha: 0.85));
      canvas.drawRRect(turnRect, Paint()..color = const Color(0xFF3B82F6)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      turnTp.paint(canvas, Offset(turnRect.left + 4.0, turnRect.top + 2.0));
    }

    // Start / Finish Flag Pin
    final Paint startBgPaint = Paint()..color = isReturning ? const Color(0xFF3B82F6) : const Color(0xFF10B981);
    canvas.drawCircle(firstOff, 7.5, startBgPaint);
    canvas.drawCircle(firstOff, 7.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8);

    final String startLabelText = isReturning ? '🏁 FINISH' : '🚩 START';
    final TextSpan startSpan = TextSpan(
      text: startLabelText,
      style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
    );
    final TextPainter startTp = TextPainter(text: startSpan, textDirection: TextDirection.ltr)..layout();
    final startRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(firstOff.dx, firstOff.dy - 16.0), width: startTp.width + 8.0, height: startTp.height + 4.0),
      const Radius.circular(5.0),
    );
    canvas.drawRRect(startRect, Paint()..color = Colors.black.withValues(alpha: 0.85));
    canvas.drawRRect(startRect, Paint()..color = (isReturning ? const Color(0xFF3B82F6) : const Color(0xFF10B981))..style = PaintingStyle.stroke..strokeWidth = 1.0);
    startTp.paint(canvas, Offset(startRect.left + 4.0, startRect.top + 2.0));

    // 3. Draw Teammate Location Pucks & Badges on OSM
    for (final t in teammates) {
      if (!t.isActive) continue;
      final tColor = t.color;
      final tOff = toPixelOffset(Point(t.lastLat, t.lastLng));

      canvas.drawCircle(tOff, 14.0, Paint()..color = tColor.withValues(alpha: 0.25));
      canvas.drawCircle(tOff, 6.5, Paint()..color = tColor);
      canvas.drawCircle(tOff, 6.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8);

      final labelText = '${t.username.isNotEmpty ? t.username : t.displayTag} • ${t.speedKmh.toStringAsFixed(0)}km/h';
      final textSpan = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(tOff.dx, tOff.dy - 16.0),
          width: tp.width + 10.0,
          height: tp.height + 4.0,
        ),
        const Radius.circular(6.0),
      );
      canvas.drawRRect(badgeRect, Paint()..color = Colors.black.withValues(alpha: 0.82));
      canvas.drawRRect(badgeRect, Paint()..color = tColor.withValues(alpha: 0.85)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      tp.paint(canvas, Offset(badgeRect.left + 5.0, badgeRect.top + 2.0));
    }

    // 3.5 Draw Shared Group Waypoints & POIs on OSM
    for (final wpt in sharedWaypoints) {
      final wptOff = toPixelOffset(Point(wpt.lat, wpt.lng));
      final wptColor = wpt.color;

      canvas.drawCircle(wptOff, 12.0, Paint()..color = wptColor.withValues(alpha: 0.28));
      canvas.drawCircle(wptOff, 5.5, Paint()..color = wptColor);
      canvas.drawCircle(wptOff, 5.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);

      final textSpan = TextSpan(
        text: '📍 ${wpt.name}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(wptOff.dx, wptOff.dy - 14.0),
          width: tp.width + 8.0,
          height: tp.height + 4.0,
        ),
        const Radius.circular(4.0),
      );
      canvas.drawRRect(badgeRect, Paint()..color = Colors.black.withValues(alpha: 0.85));
      canvas.drawRRect(badgeRect, Paint()..color = wptColor.withValues(alpha: 0.85)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      tp.paint(canvas, Offset(badgeRect.left + 4.0, badgeRect.top + 2.0));
    }

    // 4. Current position directional vector puck
    canvas.drawCircle(lastOff, 18.0, Paint()..color = const Color(0xFFFF5722).withValues(alpha: 0.25));

    canvas.save();
    canvas.translate(lastOff.dx, lastOff.dy);
    canvas.rotate(activeHeading + (pi / 2));

    final Path arrowPath = Path()
      ..moveTo(0, -14)
      ..lineTo(9, 10)
      ..lineTo(0, 5)
      ..lineTo(-9, 10)
      ..close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = const Color(0xFFFF4500)
        ..style = PaintingStyle.fill,
    );

    canvas.restore();

    if (applyHeadingUp) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant TileBreadcrumbPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.teammates.length != teammates.length ||
        oldDelegate.zoom != zoom ||
        oldDelegate.startX != startX ||
        oldDelegate.startY != startY ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.isHeadingUp != isHeadingUp ||
        oldDelegate.headingRad != headingRad ||
        oldDelegate.isReturning != isReturning ||
        oldDelegate.turnaroundPoint != turnaroundPoint;
  }
}
