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
    final Paint linePaint = Paint()
      ..color = brightness == Brightness.light ? Colors.black : Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint startPaint = Paint()
      ..color = brightness == Brightness.light ? Colors.black : Colors.white
      ..style = PaintingStyle.fill;

    final Paint currentPaint = Paint()
      ..color = brightness == Brightness.light ? Colors.black : Colors.white
      ..style = PaintingStyle.fill;

    final Paint gridPaint = Paint()
      ..color = (brightness == Brightness.light ? Colors.black : Colors.white).withOpacity(0.10)
      ..strokeWidth = 1.0;

    // 1. Draw high-contrast grid lines
    const int gridSpacing = 40;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (_renderPoints.isEmpty) return;

    // 2. Compute path bounding box for auto-scaling
    double minX = _renderPoints.first.x;
    double maxX = _renderPoints.first.x;
    double minY = _renderPoints.first.y;
    double maxY = _renderPoints.first.y;

    for (final p in _renderPoints) {
      minX = min(minX, p.x);
      maxX = max(maxX, p.x);
      minY = min(minY, p.y);
      maxY = max(maxY, p.y);
    }

    final double widthDelta = maxX - minX;
    final double heightDelta = maxY - minY;

    final double maxDelta = max(widthDelta, heightDelta);
    final double scale = maxDelta == 0 ? 1.0 : (min(size.width, size.height) - 36) / maxDelta;

    final double offsetX = (size.width - (widthDelta * scale)) / 2;
    final double offsetY = (size.height - (heightDelta * scale)) / 2;

    Offset toOffset(Point<double> p) {
      final double cx = offsetX + (p.x - minX) * scale;
      final double cy = size.height - (offsetY + (p.y - minY) * scale);
      return Offset(cx, cy);
    }

    // 3. Draw connecting path lines
    final Path path = Path();
    path.moveTo(toOffset(_renderPoints.first).dx, toOffset(_renderPoints.first).dy);

    for (int i = 1; i < _renderPoints.length; i++) {
      final offset = toOffset(_renderPoints[i]);
      path.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(path, linePaint);

    // 4. Draw Start marker ("O")
    final startOffset = toOffset(_renderPoints.first);
    canvas.drawCircle(startOffset, 6.0, startPaint);
    final Paint cutoutPaint = Paint()
      ..color = brightness == Brightness.light ? Colors.white : Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawCircle(startOffset, 3.0, cutoutPaint);

    // 5. Draw Current position arrow ("^")
    if (_renderPoints.length > 1) {
      final currentOffset = toOffset(_renderPoints.last);
      final prevOffset = toOffset(_renderPoints[_renderPoints.length - 2]);

      final double angle = atan2(currentOffset.dy - prevOffset.dy, currentOffset.dx - prevOffset.dx);
      final arrowPath = Path();
      const double arrowSize = 10.0;

      arrowPath.moveTo(
        currentOffset.dx + arrowSize * cos(angle),
        currentOffset.dy + arrowSize * sin(angle),
      );
      arrowPath.lineTo(
        currentOffset.dx + arrowSize * cos(angle + 2.3),
        currentOffset.dy + arrowSize * sin(angle + 2.3),
      );
      arrowPath.lineTo(
        currentOffset.dx + arrowSize * cos(angle - 2.3),
        currentOffset.dy + arrowSize * sin(angle - 2.3),
      );
      arrowPath.close();

      canvas.drawPath(arrowPath, currentPaint);
    } else {
      canvas.drawCircle(toOffset(_renderPoints.first), 5.0, currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BreadcrumbPainter oldDelegate) {
    return oldDelegate.points.length != points.length || oldDelegate.brightness != brightness;
  }
}
