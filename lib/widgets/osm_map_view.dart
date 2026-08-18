import 'dart:math';
import 'package:flutter/material.dart';
import 'breadcrumb_painter.dart';

/// Interactive Map and Vector Trail visualizer.
///
/// Supports offline vector trail visualization and OpenStreetMap raster overlays,
/// with manual zoom controls, recenter trigger, and compass heading indicators.
class OsmMapView extends StatefulWidget {
  /// The list of track coordinate points.
  final List<Point<double>> points;

  /// Flag indicating whether to download and overlay OpenStreetMap raster tiles.
  final bool showOsmTiles;

  /// The active app theme brightness to adjust UI elements.
  final Brightness brightness;

  /// Optional callback when map tile mode toggle is pressed.
  final ValueChanged<bool>? onToggleMapTiles;

  /// Creates a new [OsmMapView] instance.
  const OsmMapView({
    super.key,
    required this.points,
    required this.showOsmTiles,
    required this.brightness,
    this.onToggleMapTiles,
  });

  @override
  State<OsmMapView> createState() => _OsmMapViewState();
}

class _OsmMapViewState extends State<OsmMapView> {
  int _zoomOffset = 0;

  int _lon2tileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  int _lat2tileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom)).floor();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE5E7EB);

    if (widget.points.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.satellite_alt_outlined, size: 32, color: textColor.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 12),
              Text(
                "AWAITING GPS FIX...",
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Go outdoors for faster satellite acquisition",
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Bounding Box
    double minLat = widget.points.map((p) => p.x).reduce(min);
    double maxLat = widget.points.map((p) => p.x).reduce(max);
    double minLng = widget.points.map((p) => p.y).reduce(min);
    double maxLng = widget.points.map((p) => p.y).reduce(max);

    // Zoom level calculation based on bounding box
    int baseZoom = 15;
    final latDiff = (maxLat - minLat).abs();
    final lngDiff = (maxLng - minLng).abs();
    final maxDiff = max(latDiff, lngDiff);

    if (maxDiff > 0.08) {
      baseZoom = 12;
    } else if (maxDiff > 0.04) {
      baseZoom = 13;
    } else if (maxDiff > 0.015) {
      baseZoom = 14;
    } else {
      baseZoom = 15;
    }

    int zoom = (baseZoom + _zoomOffset).clamp(10, 18);

    int startX = _lon2tileX(minLng, zoom);
    int endX = _lon2tileX(maxLng, zoom);
    int startY = _lat2tileY(maxLat, zoom);
    int endY = _lat2tileY(minLat, zoom);

    int xCount = (endX - startX).abs() + 1;
    int yCount = (endY - startY).abs() + 1;

    if (xCount * yCount > 16) {
      zoom = max(10, zoom - 1);
      startX = _lon2tileX(minLng, zoom);
      endX = _lon2tileX(maxLng, zoom);
      startY = _lat2tileY(maxLat, zoom);
      endY = _lat2tileY(minLat, zoom);
      xCount = (endX - startX).abs() + 1;
      yCount = (endY - startY).abs() + 1;
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.showOsmTiles) ...[
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
                    color: isDark ? const Color(0xFF1E232B) : const Color(0xFFE2E8F0),
                    child: Center(
                      child: Icon(Icons.wifi_off, size: 20, color: textColor.withValues(alpha: 0.2)),
                    ),
                  ),
                );
              },
            ),
            CustomPaint(
              painter: TileBreadcrumbPainter(
                points: widget.points,
                zoom: zoom,
                startX: startX,
                startY: startY,
                xCount: xCount,
                yCount: yCount,
                brightness: widget.brightness,
              ),
            ),
          ] else ...[
            // Offline High-Contrast Vector Map
            CustomPaint(
              painter: BreadcrumbPainter(
                points: widget.points,
                brightness: widget.brightness,
              ),
            ),
          ],

          // Top Status Indicator Tag
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: widget.showOsmTiles ? Colors.blueAccent : const Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.showOsmTiles ? 'OSM TILES' : 'OFFLINE VECTOR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${widget.points.length} pts)',
                    style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),

          // Floating Controls (Zoom & Recenter)
          Positioned(
            bottom: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMapButton(
                  icon: Icons.add,
                  onPressed: () => setState(() => _zoomOffset = min(3, _zoomOffset + 1)),
                  isDark: isDark,
                  textColor: textColor,
                  borderColor: borderColor,
                ),
                const SizedBox(height: 6),
                _buildMapButton(
                  icon: Icons.remove,
                  onPressed: () => setState(() => _zoomOffset = max(-3, _zoomOffset - 1)),
                  isDark: isDark,
                  textColor: textColor,
                  borderColor: borderColor,
                ),
                const SizedBox(height: 6),
                _buildMapButton(
                  icon: Icons.my_location,
                  onPressed: () => setState(() => _zoomOffset = 0),
                  isDark: isDark,
                  textColor: const Color(0xFFFF5722),
                  borderColor: borderColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDark,
    required Color textColor,
    required Color borderColor,
  }) {
    return Material(
      color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: textColor),
        ),
      ),
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

  double _getTileX(double lon, int zoom) {
    return (lon + 180.0) / 360.0 * (1 << zoom);
  }

  double _getTileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final Paint linePaint = Paint()
      ..color = const Color(0xFFFF4500)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();

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

    canvas.drawPath(path, linePaint);

    // Draw current position indicator dot
    final lastLat = points.last.x;
    final lastLng = points.last.y;
    final lastTileX = _getTileX(lastLng, zoom);
    final lastTileY = _getTileY(lastLat, zoom);
    final lastPx = ((lastTileX - startX) / xCount) * size.width;
    final lastPy = ((lastTileY - startY) / yCount) * size.height;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastPx, lastPy), 8.0, dotPaint);

    final innerDotPaint = Paint()
      ..color = const Color(0xFFFF4500)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastPx, lastPy), 5.0, innerDotPaint);
  }

  @override
  bool shouldRepaint(covariant TileBreadcrumbPainter oldDelegate) {
    return oldDelegate.points.length != points.length || oldDelegate.zoom != zoom;
  }
}


