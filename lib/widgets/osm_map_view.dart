import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'breadcrumb_painter.dart';
import '../services/platform_service.dart';
import '../services/p2p_mesh_service.dart';
import '../services/settings_service.dart';
import '../services/tile_cache_service.dart';


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
    if (!_isFreePanning && (_lastPointsLength == 0 || (pts.length - _lastPointsLength).abs() > 3 || _zoomOffset != 0)) {
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
                          child: _CachedTileImage(
                            zoom: zoom,
                            tileX: tileX,
                            tileY: tileY,
                            url: url,
                            isDark: isDark,
                            textColor: textColor,
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
                      teammates: PlatformService.isColabMode
                          ? P2pMeshService.instance.teammates.where((t) => t.isActive).toList()
                          : const [],
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
                      teammates: PlatformService.isColabMode
                          ? P2pMeshService.instance.teammates.where((t) => t.isActive).toList()
                          : const [],
                      brightness: widget.brightness,
                      panOffset: _userPanOffset,
                      zoomScale: _zoomScale,
                    ),
                  ),
                ),
              ],

              // Top-Left Status Pill & Intuitive Recenter Vector Chip (16dp corner padding)
              Positioned(
                top: 16,
                left: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
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
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _recenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [accentColor, accentColor.withValues(alpha: 0.85)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.rotate(
                                angle: atan2(-_userPanOffset.dy, -_userPanOffset.dx) - (pi / 2),
                                child: const Icon(Icons.navigation_rounded, size: 13, color: Colors.white),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'RECENTER TO GPS',
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

              // Floating Controls (Zoom & Directional Recenter Vector) (16dp corner padding)
              Positioned(
                bottom: 16,
                right: 16,
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
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
                    // Intuitive GPS Vector Recenter Button
                    Material(
                      color: (_isFreePanning ? accentColor : (isDark ? Colors.black : Colors.white)).withValues(alpha: 0.9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: _isFreePanning ? accentColor : borderColor, width: 1.4),
                      ),
                      elevation: _isFreePanning ? 4 : 0,
                      shadowColor: accentColor.withValues(alpha: 0.4),
                      child: InkWell(
                        onTap: _recenter,
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: Center(
                            child: _isFreePanning
                                ? Transform.rotate(
                                    angle: atan2(-_userPanOffset.dy, -_userPanOffset.dx) - (pi / 2),
                                    child: const Icon(Icons.navigation_rounded, size: 20, color: Colors.white),
                                  )
                                : Icon(Icons.my_location_rounded, size: 18, color: textColor.withValues(alpha: 0.6)),
                          ),
                        ),
                      ),
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

class _CachedTileImage extends StatefulWidget {
  final int zoom;
  final int tileX;
  final int tileY;
  final String url;
  final bool isDark;
  final Color textColor;

  const _CachedTileImage({
    required this.zoom,
    required this.tileX,
    required this.tileY,
    required this.url,
    required this.isDark,
    required this.textColor,
  });

  @override
  State<_CachedTileImage> createState() => _CachedTileImageState();
}

class _CachedTileImageState extends State<_CachedTileImage> {
  File? _localFile;
  bool _checkedCache = false;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  @override
  void didUpdateWidget(covariant _CachedTileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom != widget.zoom || oldWidget.tileX != widget.tileX || oldWidget.tileY != widget.tileY) {
      _checkedCache = false;
      _localFile = null;
      _checkCache();
    }
  }

  Future<void> _checkCache() async {
    final file = await TileCacheService.instance.getLocalTileFile(widget.zoom, widget.tileX, widget.tileY);
    if (mounted) {
      setState(() {
        _localFile = file;
        _checkedCache = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedCache) {
      return Container(
        color: widget.isDark ? const Color(0xFF1E232B) : const Color(0xFFE2E8F0),
      );
    }

    if (_localFile != null) {
      return Image.file(
        _localFile!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, err, stack) => _buildPlaceholder(),
      );
    }

    return Image(
      image: ResizeImage(
        NetworkImage(
          widget.url,
          headers: const {
            'User-Agent': 'TurnBack-ActivityMapper/1.0.0 (Android; org.opensource.tracker; contact@turnback.app)',
          },
        ),
        width: 256,
        height: 256,
      ),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null && wasSynchronouslyLoaded == false) {
          // Asynchronously trigger caching for network tiles
          _cacheNetworkTile();
        }
        return child;
      },
      errorBuilder: (context, err, stack) => _buildPlaceholder(),
    );
  }

  void _cacheNetworkTile() async {
    try {
      final client = HttpClient();
      client.userAgent = 'TurnBack-ActivityMapper/1.0.0 (Android; org.opensource.tracker; contact@turnback.app)';
      final request = await client.getUrl(Uri.parse(widget.url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final bytesBuilder = BytesBuilder();
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
        }
        await TileCacheService.instance.saveTileBytes(widget.zoom, widget.tileX, widget.tileY, bytesBuilder.toBytes());
      }
      client.close();
    } catch (_) {}
  }

  Widget _buildPlaceholder() {
    return Container(
      color: widget.isDark ? const Color(0xFF1E232B) : const Color(0xFFE2E8F0),
      child: Center(
        child: Icon(Icons.wifi_off, size: 20, color: widget.textColor.withValues(alpha: 0.2)),
      ),
    );
  }
}

