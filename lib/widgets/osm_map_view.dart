import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'breadcrumb_painter.dart';
import '../services/settings_service.dart';

/// Interactive, 60-120 FPS Pan-and-Zoom Map & Vector Trail Visualizer.
///
/// Features:
/// - Smooth 2D touch drag / panning across the entire map canvas.
/// - Pinch-to-zoom & step zoom (+ / -).
/// - Instant 1-tap "Recenter / Follow Live GPS" with pulsing status badge.
/// - Isolated GPU texture rendering with [RepaintBoundary].
class OsmMapView extends StatefulWidget {
  final List<Point<double>> points;
  final bool showOsmTiles;
  final Brightness brightness;
  final ValueChanged<bool>? onToggleMapTiles;

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
  Offset _userPanOffset = Offset.zero;
  double _zoomScale = 1.0;
  bool _isFreePanning = false;

  // Viewport bounds cache
  int _lastZoom = 15;
  int _lastStartX = 0;
  int _lastStartY = 0;
  int _lastXCount = 0;
  int _lastYCount = 0;
  int _lastPointsLength = 0;

  int _lon2tileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  int _lat2tileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom)).floor();
  }

  void _recenter() {
    HapticFeedback.selectionClick();
    setState(() {
      _userPanOffset = Offset.zero;
      _zoomOffset = 0;
      _zoomScale = 1.0;
      _isFreePanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE5E7EB);
    final accentColor = SettingsService.instance.accentColor.color;

    if (widget.points.isEmpty) {
      return RepaintBoundary(
        child: Container(
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
        ),
      );
    }

    final pts = widget.points;
    if (_lastPointsLength == 0 || (pts.length - _lastPointsLength).abs() > 3 || _zoomOffset != 0) {
      double minLat = pts.first.x;
      double maxLat = pts.first.x;
      double minLng = pts.first.y;
      double maxLng = pts.first.y;

      for (int i = 0; i < pts.length; i++) {
        final p = pts[i];
        if (p.x < minLat) minLat = p.x;
        if (p.x > maxLat) maxLat = p.x;
        if (p.y < minLng) minLng = p.y;
        if (p.y > maxLng) maxLng = p.y;
      }

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

      _lastZoom = zoom;
      _lastStartX = startX;
      _lastStartY = startY;
      _lastXCount = xCount;
      _lastYCount = yCount;
      _lastPointsLength = pts.length;
    }

    final int zoom = _lastZoom;
    final int startX = _lastStartX;
    final int startY = _lastStartY;
    final int xCount = _lastXCount;
    final int yCount = _lastYCount;
    final tileBaseUrl = SettingsService.instance.mapTileSource;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onScaleStart: (_) {
            setState(() => _isFreePanning = true);
          },
          onScaleUpdate: (details) {
            setState(() {
              _userPanOffset += details.focalPointDelta;
              if (details.scale != 1.0) {
                _zoomScale = (_zoomScale * details.scale).clamp(0.5, 4.0);
              }
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.showOsmTiles) ...[
                // Transformable Tile Grid Layer
                Transform.translate(
                  offset: _userPanOffset,
                  child: Transform.scale(
                    scale: _zoomScale,
                    child: GridView.builder(
                      key: ValueKey('grid-$zoom-$startX-$startY-$xCount-$yCount'),
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
                        final url = tileBaseUrl
                            .replaceAll('{z}', '$zoom')
                            .replaceAll('{x}', '$tileX')
                            .replaceAll('{y}', '$tileY');

                        return RepaintBoundary(
                          key: ValueKey(url),
                          child: Image(
                            image: ResizeImage(
                              NetworkImage(url),
                              width: 256,
                              height: 256,
                            ),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (context, err, stack) => Container(
                              color: isDark ? const Color(0xFF1E232B) : const Color(0xFFE2E8F0),
                              child: Center(
                                child: Icon(Icons.wifi_off, size: 20, color: textColor.withValues(alpha: 0.2)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: TileBreadcrumbPainter(
                      points: widget.points,
                      zoom: zoom,
                      startX: startX,
                      startY: startY,
                      xCount: xCount,
                      yCount: yCount,
                      brightness: widget.brightness,
                      panOffset: _userPanOffset,
                    ),
                  ),
                ),
              ] else ...[
                // Offline High-Contrast Vector Map with 2D Pan Support
                RepaintBoundary(
                  child: CustomPaint(
                    painter: BreadcrumbPainter(
                      points: widget.points,
                      brightness: widget.brightness,
                      panOffset: _userPanOffset,
                      zoomScale: _zoomScale,
                    ),
                  ),
                ),
              ],

              // Top Status Indicator Tag & Pan Status
              Positioned(
                top: 12,
                left: 12,
                child: Row(
                  children: [
                    Container(
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
                        ],
                      ),
                    ),
                    if (_isFreePanning) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _recenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gps_fixed, size: 11, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'RECENTER',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.8),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
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
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _zoomOffset = min(3, _zoomOffset + 1);
                          _zoomScale = min(4.0, _zoomScale * 1.25);
                        });
                      },
                      isDark: isDark,
                      textColor: textColor,
                      borderColor: borderColor,
                    ),
                    const SizedBox(height: 6),
                    _buildMapButton(
                      icon: Icons.remove,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _zoomOffset = max(-3, _zoomOffset - 1);
                          _zoomScale = max(0.5, _zoomScale / 1.25);
                        });
                      },
                      isDark: isDark,
                      textColor: textColor,
                      borderColor: borderColor,
                    ),
                    const SizedBox(height: 6),
                    _buildMapButton(
                      icon: Icons.my_location,
                      onPressed: _recenter,
                      isDark: isDark,
                      textColor: _isFreePanning ? accentColor : textColor.withValues(alpha: 0.5),
                      borderColor: _isFreePanning ? accentColor : borderColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
