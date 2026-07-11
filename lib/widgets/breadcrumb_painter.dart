import 'dart:math';
import 'package:flutter/material.dart';

/// A custom painter that draws an offline relative vector track trail on a canvas.
///
/// Auto-scales coordinates to fit the container bounds and displays starting markers
/// alongside a heading direction arrow indicator at the active position.
class BreadcrumbPainter extends CustomPainter {
  /// The list of coordinates in degrees representing the trail.
  final List<Point<double>> points; // Relative or projection coordinates (e.g. simple lat/lng)

  /// The active app theme brightness to adjust line colors for maximum contrast.
  final Brightness brightness;

  /// Creates a new [BreadcrumbPainter] instance.
  BreadcrumbPainter({required this.points, required this.brightness});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = brightness == Brightness.light ? Colors.black : Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint startPaint = Paint()
      ..color = brightness == Brightness.light ? Colors.black : Colors.white
      ..style = PaintingStyle.fill;

    final Paint currentPaint = Paint()
      ..color = brightness == Brightness.light ? Colors.black : Colors.white
      ..style = PaintingStyle.fill;

    final Paint gridPaint = Paint()
      ..color = (brightness == Brightness.light ? Colors.black : Colors.white).withOpacity(0.12)
      ..strokeWidth = 1.0;

    // 1. Draw high-contrast grid lines
    const int gridSpacing = 40;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.isEmpty) return;

    // 2. Compute path bounding box for auto-scaling
    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;

    for (final p in points) {
      minX = min(minX, p.x);
      maxX = max(maxX, p.x);
      minY = min(minY, p.y);
      maxY = max(maxY, p.y);
    }

    final double widthDelta = maxX - minX;
    final double heightDelta = maxY - minY;

    // Add padding to prevent rendering exactly on edges
    final double maxDelta = max(widthDelta, heightDelta);
    final double scale = maxDelta == 0 ? 1.0 : (min(size.width, size.height) - 30) / maxDelta;

    final double offsetX = (size.width - (widthDelta * scale)) / 2;
    final double offsetY = (size.height - (heightDelta * scale)) / 2;

    Offset toOffset(Point<double> p) {
      // Map coordinates to canvas space. Flip Y-axis since larger latitudes are higher
      final double cx = offsetX + (p.x - minX) * scale;
      final double cy = size.height - (offsetY + (p.y - minY) * scale);
      return Offset(cx, cy);
    }

    // 3. Draw connecting path lines
    final Path path = Path();
    path.moveTo(toOffset(points.first).dx, toOffset(points.first).dy);

    for (int i = 1; i < points.length; i++) {
      final offset = toOffset(points[i]);
      path.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(path, linePaint);

    // 4. Draw Start marker ("o")
    final startOffset = toOffset(points.first);
    canvas.drawCircle(startOffset, 6.0, startPaint);
    // Inner cutout to look like an "o"
    final Paint cutoutPaint = Paint()
      ..color = brightness == Brightness.light ? Colors.white : Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawCircle(startOffset, 3.0, cutoutPaint);

    // 5. Draw Current position arrow ("^")
    if (points.length > 1) {
      final currentOffset = toOffset(points.last);
      final prevOffset = toOffset(points[points.length - 2]);

      // Calculate path angle for pointing the arrowhead
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
      // Draw simple dot if only 1 point is present
      canvas.drawCircle(toOffset(points.first), 5.0, currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BreadcrumbPainter oldDelegate) {
    return oldDelegate.points.length != points.length || oldDelegate.brightness != brightness;
  }
}

