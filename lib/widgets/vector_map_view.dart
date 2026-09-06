import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/adaptive_pacing_service.dart';
import '../services/platform_service.dart';
import '../services/settings_service.dart';
import '../services/tile_cache_service.dart';

/// In-memory LRU Tile Texture Cache strictly capped at 32 MB RAM.
class VectorTileTextureCache {
  static final VectorTileTextureCache instance = VectorTileTextureCache._(maxSizeBytes: 32 * 1024 * 1024);

  final int maxSizeBytes;
  int _currentSizeBytes = 0;
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap<String, Uint8List>();

  VectorTileTextureCache._({required this.maxSizeBytes});

  int get currentSizeBytes => _currentSizeBytes;
  int get count => _cache.length;
  double get usageMb => _currentSizeBytes / (1024 * 1024);

  Uint8List? get(String key) {
    final bytes = _cache.remove(key);
    if (bytes != null) {
      _cache[key] = bytes; // Re-insert at the end (MRU)
    }
    return bytes;
  }

  void put(String key, Uint8List bytes) {
    if (bytes.length > maxSizeBytes) return; // Single tile exceeds cache limit

    if (_cache.containsKey(key)) {
      final existing = _cache.remove(key)!;
      _currentSizeBytes -= existing.length;
    }

    // Evict oldest entries until within 32 MB ceiling
    while (_currentSizeBytes + bytes.length > maxSizeBytes && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final evicted = _cache.remove(oldestKey)!;
      _currentSizeBytes -= evicted.length;
    }

    _cache[key] = bytes;
    _currentSizeBytes += bytes.length;
  }

  void clear() {
    _cache.clear();
    _currentSizeBytes = 0;
  }
}

/// Camera mode state for the Vector Map Engine.
enum CameraMode {
  /// 55° camera pitch, course-up bearing alignment, anchored at bottom 30% center.
  navigation,

  /// 0° camera pitch (top-down orthographic), north-up, full route auto-bounding, auto-pan paused.
  skyView,
}

/// Vector Map Engine Canvas with Dual Camera View Modes and 32 MB RAM Texture Cache.
class VectorMapView extends StatefulWidget {
  final List<Point<double>> points;
  final Brightness brightness;
  final bool isReturning;
  final double returnPathRemainingKm;
  final bool showTiles;
  final ValueChanged<bool>? onToggleTiles;

  const VectorMapView({
    super.key,
    required this.points,
    required this.brightness,
    this.isReturning = false,
    this.returnPathRemainingKm = 0.0,
    this.showTiles = true,
    this.onToggleTiles,
  });

  @override
  State<VectorMapView> createState() => _VectorMapViewState();
}

class _VectorMapViewState extends State<VectorMapView> with SingleTickerProviderStateMixin {
  CameraMode _cameraMode = CameraMode.navigation;
  double _smoothedHeadingRad = 0.0;
  Offset _manualPanOffset = Offset.zero;
  double _zoomScale = 1.0;
  bool _isManualPanning = false;

  // Viewport bounds cache
  int _lastZoom = 16;
  int _lastStartX = 0;
  int _lastStartY = 0;
  int _lastXCount = 0;
  int _lastYCount = 0;

  @override
  void didUpdateWidget(covariant VectorMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points.isNotEmpty && _cameraMode == CameraMode.navigation && !_isManualPanning) {
      _updateSmoothedHeading();
    }
  }

  void _updateSmoothedHeading() {
    if (widget.points.length < 2) return;
    final p1 = widget.points[widget.points.length - 2];
    final p2 = widget.points.last;
    final double midLat = (p1.x + p2.x) / 2.0;
    final double cosLat = cos(midLat * pi / 180.0);
    final double dx = (p2.y - p1.y) * cosLat;
    final double dy = p2.x - p1.x;
    if (dx != 0 || dy != 0) {
      final targetHeading = atan2(dx, dy);
      _smoothedHeadingRad = AdaptivePacingService.filterHeading(
        currentSmoothedRad: _smoothedHeadingRad,
        targetHeadingRad: targetHeading,
        alpha: 0.15,
      );
    }
  }

  int _lon2tileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  int _lat2tileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom)).floor();
  }

  void _toggleSkyView() {
    HapticFeedback.heavyImpact();
    setState(() {
      if (_cameraMode == CameraMode.navigation) {
        _cameraMode = CameraMode.skyView;
        _isManualPanning = false;
        _manualPanOffset = Offset.zero;
      } else {
        _cameraMode = CameraMode.navigation;
        _isManualPanning = false;
        _manualPanOffset = Offset.zero;
      }
    });
  }

  void _recenterToNavigation() {
    HapticFeedback.mediumImpact();
    setState(() {
      _cameraMode = CameraMode.navigation;
      _isManualPanning = false;
      _manualPanOffset = Offset.zero;
      _zoomScale = 1.0;
      _updateSmoothedHeading();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final accentColor = SettingsService.instance.accentColor.color;
    final bgColor = isDark ? const Color(0xFF0D0F14) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);

    if (widget.points.isEmpty) {
      return Container(
        color: bgColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 2),
                ),
                child: Icon(Icons.satellite_alt_rounded, size: 36, color: accentColor),
              ),
              const SizedBox(height: 16),
              Text(
                'ACQUIRING GPS CONSTELLATION...',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'High-precision vector canvas standby (32MB RAM Cache ready)',
                style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      );
    }

    final pts = widget.points;
    final latestPoint = pts.last;

    // Viewport calculation
    if (_cameraMode == CameraMode.skyView) {
      // Sky View Mode: fit entire route
      double minLat = pts.first.x;
      double maxLat = pts.first.x;
      double minLng = pts.first.y;
      double maxLng = pts.first.y;

      for (final p in pts) {
        if (p.x < minLat) minLat = p.x;
        if (p.x > maxLat) maxLat = p.x;
        if (p.y < minLng) minLng = p.y;
        if (p.y > maxLng) maxLng = p.y;
      }

      final latSpan = (maxLat - minLat).abs();
      final lngSpan = (maxLng - minLng).abs();
      final maxSpan = max(latSpan, lngSpan);

      int zoom = 16;
      if (maxSpan > 0.12) {
        zoom = 11;
      } else if (maxSpan > 0.06) {
        zoom = 12;
      } else if (maxSpan > 0.03) {
        zoom = 13;
      } else if (maxSpan > 0.015) {
        zoom = 14;
      } else if (maxSpan > 0.007) {
        zoom = 15;
      } else {
        zoom = 16;
      }

      int startX = _lon2tileX(minLng, zoom);
      int endX = _lon2tileX(maxLng, zoom);
      int startY = _lat2tileY(maxLat, zoom);
      int endY = _lat2tileY(minLat, zoom);

      int xCount = (endX - startX).abs() + 1;
      int yCount = (endY - startY).abs() + 1;

      if (xCount * yCount > 36) {
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
    } else {
      // Navigation Mode: centered on user position
      const int zoom = 16;
      final curX = _lon2tileX(latestPoint.y, zoom);
      final curY = _lat2tileY(latestPoint.x, zoom);
      _lastZoom = zoom;
      _lastStartX = curX - 1;
      _lastStartY = curY - 1;
      _lastXCount = 3;
      _lastYCount = 3;
    }

    final int zoom = _lastZoom;
    final int startX = _lastStartX;
    final int startY = _lastStartY;
    final int xCount = _lastXCount;
    final int yCount = _lastYCount;
    final tileBaseUrl = SettingsService.instance.mapTileSource;

    return RepaintBoundary(
      child: Container(
        color: bgColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gesture detector for free pan & zoom
            GestureDetector(
              onScaleStart: (_) {
                setState(() => _isManualPanning = true);
              },
              onScaleUpdate: (details) {
                setState(() {
                  _manualPanOffset += details.focalPointDelta;
                  if (details.scale != 1.0) {
                    _zoomScale = (_zoomScale * details.scale).clamp(0.6, 6.0);
                  }
                });
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);

                  // 3D Perspective Matrix Setup
                  // Navigation: pitch 55° (0.9599 rad), rotation = -smoothedHeadingRad
                  // Sky View: pitch 0°, rotation = 0° (north-up)
                  final isNav = _cameraMode == CameraMode.navigation && !_isManualPanning;
                  final double pitchRad = isNav ? (55.0 * pi / 180.0) : 0.0;
                  final double rotationRad = isNav ? -_smoothedHeadingRad : 0.0;

                  // Anchor point: Bottom 30% center in Navigation Mode (Offset(width/2, height*0.70))
                  final Offset anchorPoint = isNav
                      ? Offset(size.width * 0.5, size.height * 0.70)
                      : Offset(size.width * 0.5, size.height * 0.50);

                  final Matrix4 cameraTransform = Matrix4.identity();
                  if (isNav) {
                    cameraTransform.setEntry(3, 2, 0.0015); // Perspective projection depth
                    cameraTransform.rotateX(pitchRad);
                  }

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Vector & Tile Canvas with Camera Transformation
                      Transform(
                        alignment: isNav ? Alignment(0.0, 0.4) : Alignment.center,
                        transform: cameraTransform,
                        child: Transform.rotate(
                          angle: rotationRad,
                          alignment: isNav ? Alignment(0.0, 0.4) : Alignment.center,
                          child: Transform.translate(
                            offset: _manualPanOffset,
                            child: Transform.scale(
                              scale: _zoomScale,
                              alignment: Alignment.center,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // 1. Vector Map Tiles Layer (with 32 MB RAM Texture Cache)
                                  if (widget.showTiles)
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
                                        final url = tileBaseUrl
                                            .replaceAll('{z}', '$zoom')
                                            .replaceAll('{x}', '$tileX')
                                            .replaceAll('{y}', '$tileY');
                                        return _VectorCachedTile(
                                          tileUrl: url,
                                          zoom: zoom,
                                          tileX: tileX,
                                          tileY: tileY,
                                          isDark: isDark,
                                        );
                                      },
                                    ),

                                  // 2. Vector Trail & Breadcrumbs Painter
                                  CustomPaint(
                                    size: size,
                                    painter: _VectorTrailPainter(
                                      points: pts,
                                      zoom: zoom,
                                      startX: startX,
                                      startY: startY,
                                      xCount: xCount,
                                      yCount: yCount,
                                      accentColor: accentColor,
                                      isReturning: widget.isReturning,
                                      isNavMode: isNav,
                                      isDark: isDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // User Position Puck & Heading Pointer (anchored at bottom 30% center in Navigation Mode)
                      if (isNav)
                        Positioned(
                          left: anchorPoint.dx - 22,
                          top: anchorPoint.dy - 22,
                          child: _buildNavigationPuck(accentColor),
                        ),
                    ],
                  );
                },
              ),
            ),

            // Top-Right Quick Status Indicator Pill
            Positioned(
              top: MediaQuery.of(context).padding.top + 58,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _cameraMode == CameraMode.navigation ? const Color(0xFF10B981) : Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _cameraMode == CameraMode.navigation
                          ? 'POINT MODE (55° COURSE-UP)'
                          : 'SKY VIEW (NORTH-UP)',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Heavy-Glove Floating Action Buttons (Minimum 68dp x 68dp Touch Target)
            Positioned(
              right: 16,
              bottom: 84,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Sky View Toggle Button (Bird Icon, 68dp x 68dp)
                  _buildErgonomicActionButton(
                    icon: _cameraMode == CameraMode.skyView
                        ? Icons.flight_takeoff_rounded
                        : Icons.flutter_dash_rounded,
                    tooltip: 'Toggle Sky View Mode (0° North-Up)',
                    isActive: _cameraMode == CameraMode.skyView,
                    activeColor: Colors.amber,
                    isDark: isDark,
                    onTap: _toggleSkyView,
                  ),
                  const SizedBox(height: 12),

                  // 2. Recenter / Point Mode Button (Point Icon, 68dp x 68dp)
                  _buildErgonomicActionButton(
                    icon: Icons.navigation_rounded,
                    tooltip: 'Recenter to Navigation Point Mode (55°)',
                    isActive: _cameraMode == CameraMode.navigation && !_isManualPanning,
                    activeColor: accentColor,
                    isDark: isDark,
                    onTap: _recenterToNavigation,
                  ),
                  const SizedBox(height: 12),

                  // 3. Tile Layer Toggle (68dp x 68dp)
                  _buildErgonomicActionButton(
                    icon: widget.showTiles ? Icons.layers_rounded : Icons.layers_clear_rounded,
                    tooltip: 'Toggle Offline Vector / OSM Tiles',
                    isActive: widget.showTiles,
                    activeColor: accentColor,
                    isDark: isDark,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onToggleTiles?.call(!widget.showTiles);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// High-visibility 68dp x 68dp ergonomic touch target engineered for cycling with thick gloves.
  Widget _buildErgonomicActionButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required Color activeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 68,
          height: 68,
          child: Material(
            color: isActive
                ? activeColor
                : (isDark ? const Color(0xFF1E232B) : Colors.white),
            shape: const CircleBorder(),
            elevation: isActive ? 8 : 4,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: Icon(
                  icon,
                  size: 32,
                  color: isActive
                      ? Colors.black
                      : (isDark ? Colors.white : const Color(0xFF1E293B)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 3D User Location Puck with Course-Up Directional Chevron.
  Widget _buildNavigationPuck(Color accentColor) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accentColor.withValues(alpha: 0.25),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.4),
            blurRadius: 14,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentColor,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: const Center(
            child: Icon(
              Icons.navigation,
              size: 13,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cached tile loader reading from local disk or downloading, stored in [VectorTileTextureCache].
class _VectorCachedTile extends StatefulWidget {
  final String tileUrl;
  final int zoom;
  final int tileX;
  final int tileY;
  final bool isDark;

  const _VectorCachedTile({
    required this.tileUrl,
    required this.zoom,
    required this.tileX,
    required this.tileY,
    required this.isDark,
  });

  @override
  State<_VectorCachedTile> createState() => _VectorCachedTileState();
}

class _VectorCachedTileState extends State<_VectorCachedTile> {
  Uint8List? _tileBytes;

  @override
  void initState() {
    super.initState();
    _loadTile();
  }

  @override
  void didUpdateWidget(covariant _VectorCachedTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tileUrl != widget.tileUrl) {
      _loadTile();
    }
  }

  Future<void> _loadTile() async {
    final key = '${widget.zoom}_${widget.tileX}_${widget.tileY}';

    // 1. Check 32 MB RAM Texture Cache
    final memoryHit = VectorTileTextureCache.instance.get(key);
    if (memoryHit != null) {
      if (mounted) setState(() => _tileBytes = memoryHit);
      return;
    }

    // 2. Check local disk cache (/osm_tiles/{z}/{x}/{y}.png)
    try {
      final baseDir = await TileCacheService.instance.cacheDirectory;
      final file = File('${baseDir.path}/${widget.zoom}/${widget.tileX}/${widget.tileY}.png');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        VectorTileTextureCache.instance.put(key, bytes);
        if (mounted) setState(() => _tileBytes = bytes);
        return;
      }
    } catch (_) {}

    // 3. Fallback to network tile fetch if online
    if (PlatformService.isColabMode || widget.tileUrl.contains('openstreetmap')) {
      try {
        final client = HttpClient();
        client.userAgent = 'TurnBack-Endurance-Tracker/1.2.4 (MapLibre-Vector; Android; offline-first)';
        final request = await client.getUrl(Uri.parse(widget.tileUrl));
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          VectorTileTextureCache.instance.put(key, bytes);
          if (mounted) setState(() => _tileBytes = bytes);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tileBytes != null) {
      return Image.memory(
        _tileBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        color: widget.isDark ? const Color(0xFF0F172A).withValues(alpha: 0.15) : null,
        colorBlendMode: widget.isDark ? BlendMode.darken : null,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF13171F) : const Color(0xFFE2E8F0),
        border: Border.all(
          color: widget.isDark ? const Color(0xFF1E232B) : const Color(0xFFCBD5E1),
          width: 0.5,
        ),
      ),
    );
  }
}

/// Custom painter rendering the 3D GPS route polyline, start point, and turnaround vectors.
class _VectorTrailPainter extends CustomPainter {
  final List<Point<double>> points;
  final int zoom;
  final int startX;
  final int startY;
  final int xCount;
  final int yCount;
  final Color accentColor;
  final bool isReturning;
  final bool isNavMode;
  final bool isDark;

  _VectorTrailPainter({
    required this.points,
    required this.zoom,
    required this.startX,
    required this.startY,
    required this.xCount,
    required this.yCount,
    required this.accentColor,
    required this.isReturning,
    required this.isNavMode,
    required this.isDark,
  });

  Offset _toScreenOffset(double lat, double lon, Size size) {
    final latRad = lat * pi / 180.0;
    final double worldX = (lon + 180.0) / 360.0 * (1 << zoom);
    final double worldY = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom);

    final double relX = (worldX - startX) / xCount;
    final double relY = (worldY - startY) / yCount;

    return Offset(relX * size.width, relY * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final path = Path();
    final first = _toScreenOffset(points.first.x, points.first.y, size);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final pt = _toScreenOffset(points[i].x, points[i].y, size);
      path.lineTo(pt.dx, pt.dy);
    }

    // Outer glow / shadow
    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.3)
      ..strokeWidth = isNavMode ? 10.0 : 7.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glowPaint);

    // Primary breadcrumb vector track
    final trackPaint = Paint()
      ..color = isReturning ? const Color(0xFFEF4444) : accentColor
      ..strokeWidth = isNavMode ? 5.5 : 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, trackPaint);

    // Start point marker (Green origin flag)
    final startPaint = Paint()..color = const Color(0xFF10B981);
    canvas.drawCircle(first, 6.0, startPaint);
    canvas.drawCircle(first, 8.0, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _VectorTrailPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.zoom != zoom ||
        oldDelegate.isReturning != isReturning ||
        oldDelegate.isNavMode != isNavMode;
  }
}
