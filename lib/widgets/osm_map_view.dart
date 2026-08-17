import 'dart:math';
import 'package:flutter/material.dart';
import 'breadcrumb_painter.dart';

/// Widget that renders either an offline vector trail or an online OSM tile grid map.
///
/// Toggles rendering modes based on network and configuration states to preserve device battery.
class OsmMapView extends StatelessWidget {
  /// The list of track coordinate points.
  final List<Point<double>> points;

  /// Flag indicating whether to download and overlay OpenStreetMap raster tiles.
  final bool showOsmTiles;

  /// The active app theme brightness to adjust UI elements.
  final Brightness brightness;

  /// Creates a new [OsmMapView] instance.
  const OsmMapView({
    super.key,
    required this.points,
    required this.showOsmTiles,
    required this.brightness,
  });

  /// Converts longitude and zoom level to OSM tile X coordinates.
  int _lon2tileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  /// Converts latitude and zoom level to OSM tile Y coordinates.
  int _lat2tileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom)).floor();
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          "AWAITING GPS SIGNAL...",
          style: TextStyle(
            color: brightness == Brightness.light ? Colors.black54 : Colors.white54,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // Bounding Box
    double minLat = points.map((p) => p.x).reduce(min);
    double maxLat = points.map((p) => p.x).reduce(max);
    double minLng = points.map((p) => p.y).reduce(min);
    double maxLng = points.map((p) => p.y).reduce(max);

    // Zoom level calculation based on bounding box
    int zoom = 15;
    final latDiff = (maxLat - minLat).abs();
    final lngDiff = (maxLng - minLng).abs();
    final maxDiff = max(latDiff, lngDiff);

    if (maxDiff > 0.08) zoom = 12;
    else if (maxDiff > 0.04) zoom = 13;
    else if (maxDiff > 0.015) zoom = 14;
    else zoom = 15;

    int startX = _lon2tileX(minLng, zoom);
    int endX = _lon2tileX(maxLng, zoom);
    int startY = _lat2tileY(maxLat, zoom);
    int endY = _lat2tileY(minLat, zoom);

    int xCount = (endX - startX).abs() + 1;
    int yCount = (endY - startY).abs() + 1;

    // Cap grid size to avoid heavy downloads
    if (xCount * yCount > 9) {
      zoom = max(10, zoom - 1);
      startX = _lon2tileX(minLng, zoom);
      endX = _lon2tileX(maxLng, zoom);
      startY = _lat2tileY(maxLat, zoom);
      endY = _lat2tileY(minLat, zoom);
      xCount = (endX - startX).abs() + 1;
      yCount = (endY - startY).abs() + 1;
    }

    final Color primaryColor = brightness == Brightness.light ? Colors.black : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (showOsmTiles) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Online OSM Tile Grid
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: xCount,
                  childAspectRatio: 1.0,
                ),
                itemCount: xCount * yCount,
                itemBuilder: (context, index) {
                  final xOffset = index % xCount;
                  final yOffset = index ~/ xCount;
                  final tileX = startX + xOffset;
                  final tileY = startY + yOffset;
                  return Image.network(
                    'https://tile.openstreetmap.org/$zoom/$tileX/$tileY.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, err, stack) => Container(
                      color: brightness == Brightness.light ? Colors.grey[200] : Colors.grey[900],
                      child: Icon(Icons.wifi_off, color: primaryColor.withOpacity(0.3)),
                    ),
                  );
                },
              ),
              // Overlaid breadcrumb trail mapped to tiles
              CustomPaint(
                painter: TileBreadcrumbPainter(
                  points: points,
                  zoom: zoom,
                  startX: startX,
                  startY: startY,
                  xCount: xCount,
                  yCount: yCount,
                  brightness: brightness,
                ),
              ),
            ],
          );
        } else {
          // Default: relative vector map
          return CustomPaint(
            painter: BreadcrumbPainter(points: points, brightness: brightness),
          );
        }
      },
    );
  }
}

/// Custom painter that maps geographic GPS coordinates to visual OSM grid pixels.
class TileBreadcrumbPainter extends CustomPainter {
  /// The list of GPS coordinate points.
  final List<Point<double>> points;

  /// The active zoom level.
  final int zoom;

  /// Starting grid X tile coordinate.
  final int startX;

  /// Starting grid Y tile coordinate.
  final int startY;

  /// Number of columns in tile grid.
  final int xCount;

  /// Number of rows in tile grid.
  final int yCount;

  /// Theme brightness state.
  final Brightness brightness;

  /// Creates a new [TileBreadcrumbPainter] instance.
  TileBreadcrumbPainter({
    required this.points,
    required this.zoom,
    required this.startX,
    required this.startY,
    required this.xCount,
    required this.yCount,
    required this.brightness,
  });

  /// Computes decimal OSM tile X projection coordinate from longitude.
  double _getTileX(double lon, int zoom) {
    return (lon + 180.0) / 360.0 * (1 << zoom);
  }

  /// Computes decimal OSM tile Y projection coordinate from latitude.
  double _getTileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // Map latitude/longitude directly to grid canvas pixels
    for (int i = 0; i < points.length; i++) {
      final lat = points[i].x;
      final lng = points[i].y;
      
      final tileX = _getTileX(lng, zoom);
      final tileY = _getTileY(lat, zoom);

      final xPct = (tileX - startX) / xCount;
      final yPct = (tileY - startY) / yCount;

      final px = xPct * size.width;
      final py = yPct * size.height;

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    canvas.drawPath(path, paint);

    // Draw current position indicator dot
    final lastLat = points.last.x;
    final lastLng = points.last.y;
    final lastTileX = _getTileX(lastLng, zoom);
    final lastTileY = _getTileY(lastLat, zoom);
    final lastPx = ((lastTileX - startX) / xCount) * size.width;
    final lastPy = ((lastTileY - startY) / yCount) * size.height;

    final dotPaint = Paint()
      ..color = brightness == Brightness.light ? Colors.black : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastPx, lastPy), 7.0, dotPaint);

    final innerDotPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastPx, lastPy), 4.0, innerDotPaint);
  }

  @override
  bool shouldRepaint(covariant TileBreadcrumbPainter oldDelegate) {
    return oldDelegate.points.length != points.length || oldDelegate.zoom != zoom;
  }
}

