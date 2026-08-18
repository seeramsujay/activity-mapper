import 'dart:math';
import 'package:flutter/material.dart';

/// A custom painter that draws an offline relative vector track trail on a canvas.
///
/// Features:
/// - Auto-scales coordinates to fit container bounds.
/// - Built-in Ramer-Douglas-Peucker (RDP) polyline decimation for 60 FPS rendering on 2GB RAM phones.
/// - Start marker ("O") and active heading direction arrow ("^").
/// - High-contrast light and dark mode styling.
class BreadcrumbPainter extends CustomPainter {
  /// The list of coordinates in degrees representing the trail.
  final List<Point<double>> points;

  /// The active app theme brightness to adjust line colors for maximum contrast.
  final Brightness brightness;

  /// Epsilon tolerance for RDP polyline simplification. Set to 0.0 to disable.
  final double simplificationEpsilon;

  /// Cached simplified points list.
  late final List<Point<double>> _renderPoints;

  /// Creates a new [BreadcrumbPainter] instance.
  BreadcrumbPainter({
    required this.points,
    required this.brightness,
    this.simplificationEpsilon = 0.00005, // ~5 meters tolerance
  }) {
    if (points.length > 100 && simplificationEpsilon > 0) {
      _renderPoints = rdpSimplify(points, simplificationEpsilon);
    } else {
      _renderPoints = points;
    }
  }

  /// Ramer-Douglas-Peucker algorithm for polyline decimation.
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

    // Geographic Mercator/Equirectangular aspect ratio correction
    final double midLat = _renderPoints.map((p) => p.x).reduce((a, b) => a + b) / _renderPoints.length;
    final double cosLat = cos(midLat * pi / 180.0);

    // Compute bounding box
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

    final double scale = min(availWidth / lngSpan, availHeight / latSpan);

    final double cx = (minLng + maxLng) / 2.0;
    final double cy = (minLat + maxLat) / 2.0;

    Offset toCanvasOffset(Point<double> p) {
      final double x = size.width / 2.0 + (p.y - cx) * cosLat * scale;
      final double y = size.height / 2.0 - (p.x - cy) * scale;
      return Offset(x, y);
    }

    // Draw Track Trail Shadow/Glow
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

    // Draw Start point ("S")
    final startOff = toCanvasOffset(_renderPoints.first);
    final Paint startBgPaint = Paint()..color = const Color(0xFF10B981);
    canvas.drawCircle(startOff, 7.0, startBgPaint);
    final Paint startCenterPaint = Paint()..color = Colors.white;
    canvas.drawCircle(startOff, 3.5, startCenterPaint);

    // Draw Current Position with pulsing radar halo
    final currentOff = toCanvasOffset(_renderPoints.last);
    final Paint haloPaint = Paint()..color = const Color(0xFFFF5722).withValues(alpha: 0.25);
    canvas.drawCircle(currentOff, 14.0, haloPaint);

    final Paint currentBgPaint = Paint()..color = isDark ? Colors.white : Colors.black;
    canvas.drawCircle(currentOff, 7.5, currentBgPaint);

    final Paint currentCenterPaint = Paint()..color = const Color(0xFFFF5722);
    canvas.drawCircle(currentOff, 4.5, currentCenterPaint);
  }

  @override
  bool shouldRepaint(covariant BreadcrumbPainter oldDelegate) {
    return oldDelegate.points.length != points.length || oldDelegate.brightness != brightness;
  }
}

/// A custom painter that draws a GPS breadcrumb polyline aligned with an OSM raster tile grid.
class TileBreadcrumbPainter extends CustomPainter {
  final List<Point<double>> points;
  final int zoom;
  final int startX;
  final int startY;
  final int xCount;
  final int yCount;
  final Brightness brightness;

  TileBreadcrumbPainter({
    required this.points,
    required this.zoom,
    required this.startX,
    required this.startY,
    required this.xCount,
    required this.yCount,
    required this.brightness,
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
      final double px = (tileX - startX) * tileWidthPx;
      final double py = (tileY - startY) * tileHeightPx;
      return Offset(px, py);
    }

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

    // Start circle
    canvas.drawCircle(firstOff, 6.0, Paint()..color = const Color(0xFF10B981));
    canvas.drawCircle(firstOff, 3.0, Paint()..color = Colors.white);

    // Current position circle
    final lastOff = toPixelOffset(points.last);
    canvas.drawCircle(lastOff, 12.0, Paint()..color = const Color(0xFFFF5722).withValues(alpha: 0.25));
    canvas.drawCircle(lastOff, 7.0, Paint()..color = Colors.white);
    canvas.drawCircle(lastOff, 4.0, Paint()..color = const Color(0xFFFF5722));
  }

  @override
  bool shouldRepaint(covariant TileBreadcrumbPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.zoom != zoom ||
        oldDelegate.startX != startX ||
        oldDelegate.startY != startY;
  }
}
