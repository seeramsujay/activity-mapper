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
  final bool isReturning;
  final double returnPathRemainingKm;

  const OsmMapView({
    super.key,
    required this.points,
    required this.showOsmTiles,
    required this.brightness,
    this.onToggleMapTiles,
    this.isReturning = false,
    this.returnPathRemainingKm = 0.0,
  });

  @override
  State<OsmMapView> createState() => _OsmMapViewState();
}

class _OsmMapViewState extends State<OsmMapView> {
  int _zoomOffset = 0;
  Offset _userPanOffset = Offset.zero;
  double _zoomScale = 1.0;
  bool _isFreePanning = false;
  late bool _isHeadingUp;

  // Viewport bounds cache
  int _lastZoom = 15;
  int _lastStartX = 0;
  int _lastStartY = 0;
  int _lastXCount = 0;
  int _lastYCount = 0;
  int _lastPointsLength = 0;

  @override
  void initState() {
    super.initState();
    _isHeadingUp = SettingsService.instance.isHeadingUp;
  }

  int _lon2tileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  int _lat2tileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom)).floor();
  }

  double _calculateHeadingRad() {
    if (widget.points.length < 2) return 0.0;
    final p1 = widget.points[widget.points.length - 2];
    final p2 = widget.points.last;
    final double midLat = (p1.x + p2.x) / 2.0;
    final double cosLat = cos(midLat * pi / 180.0);
    final double dx = (p2.y - p1.y) * cosLat;
    final double dy = p2.x - p1.x;
    if (dx == 0 && dy == 0) return 0.0;
    return atan2(dx, dy);
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

  void _toggleHeadingUp() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isHeadingUp = !_isHeadingUp;
    });
    SettingsService.instance.setHeadingUp(_isHeadingUp);
  }

  void _enableGuidanceZoom() {
    HapticFeedback.heavyImpact();
    setState(() {
      _userPanOffset = Offset.zero;
      _zoomOffset = 3;
      _zoomScale = 2.5;
      _isFreePanning = false;
      _isHeadingUp = true;
    });
  }

  void _showTileSourcePicker(BuildContext context, bool isDark, Color textColor, Color accentColor) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF14171C) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'SELECT MAP TILE PROVIDER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: textColor.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 12),
                _buildTileSourceTile('Standard OpenStreetMap', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', Icons.public, textColor, accentColor),
                _buildTileSourceTile('Google Maps (Roadmap)', 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', Icons.map, textColor, accentColor),
                _buildTileSourceTile('Google Maps (Satellite & Hybrid)', 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}', Icons.satellite_alt_rounded, textColor, accentColor),
                _buildTileSourceTile('Google Maps (Terrain)', 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}', Icons.terrain, textColor, accentColor),
                _buildTileSourceTile('OpenTopoMap (Topographic)', 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png', Icons.filter_hdr_rounded, textColor, accentColor),
                _buildTileSourceTile('CartoDB Dark Matter', 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png', Icons.dark_mode_outlined, textColor, accentColor),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTileSourceTile(String title, String url, IconData icon, Color textColor, Color accentColor) {
    final isSelected = SettingsService.instance.mapTileSource == url;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(icon, color: isSelected ? accentColor : textColor.withValues(alpha: 0.6)),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? accentColor : textColor,
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
          fontSize: 13,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check_circle_rounded, color: accentColor, size: 20) : null,
      onTap: () {
        SettingsService.instance.setMapTileSource(url);
        setState(() {});
        Navigator.pop(context);
      },
    );
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

      int baseZoom = 16;
      final latDiff = (maxLat - minLat).abs();
      final lngDiff = (maxLng - minLng).abs();
      final maxDiff = max(latDiff, lngDiff);

      if (maxDiff > 0.08) {
        baseZoom = 12;
      } else if (maxDiff > 0.04) {
        baseZoom = 13;
      } else if (maxDiff > 0.015) {
        baseZoom = 14;
      } else if (maxDiff > 0.005) {
        baseZoom = 15;
      } else {
        baseZoom = 16;
      }

      int zoom = (baseZoom + _zoomOffset).clamp(10, 20);

      int startX = _lon2tileX(minLng, zoom);
      int endX = _lon2tileX(maxLng, zoom);
      int startY = _lat2tileY(maxLat, zoom);
      int endY = _lat2tileY(minLat, zoom);

      int xCount = (endX - startX).abs() + 1;
      int yCount = (endY - startY).abs() + 1;

      if (xCount * yCount > 25) {
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
    final headingRad = _calculateHeadingRad();

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
                _zoomScale = (_zoomScale * details.scale).clamp(0.5, 8.0);
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
                      sharedWaypoints: PlatformService.isColabMode
                          ? P2pMeshService.instance.sharedWaypoints
                          : const [],
                      zoom: zoom,
                      startX: startX,
                      startY: startY,
                      xCount: xCount,
                      yCount: yCount,
                      brightness: widget.brightness,
                      panOffset: _userPanOffset,
                      isHeadingUp: _isHeadingUp,
                      headingRad: headingRad,
                      isReturning: widget.isReturning,
                    ),
                  ),
                ),
              ] else ...[
                // Offline High-Contrast Vector Map with 2D Pan & Heading-Up Rotation
                RepaintBoundary(
                  child: CustomPaint(
                    painter: BreadcrumbPainter(
                      points: widget.points,
                      teammates: PlatformService.isColabMode
                          ? P2pMeshService.instance.teammates.where((t) => t.isActive).toList()
                          : const [],
                      sharedWaypoints: PlatformService.isColabMode
                          ? P2pMeshService.instance.sharedWaypoints
                          : const [],
                      brightness: widget.brightness,
                      panOffset: _userPanOffset,
                      zoomScale: _zoomScale,
                      isHeadingUp: _isHeadingUp,
                      headingRad: headingRad,
                      isReturning: widget.isReturning,
                    ),
                  ),
                ),
              ],

              // Top Guidance Banner when Returning
              if (widget.isReturning) ...[
                Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.6), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.turn_left_rounded, size: 20, color: Color(0xFF00E5FF)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'RETURNING TO START',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                  color: Color(0xFF00E5FF),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.returnPathRemainingKm.toStringAsFixed(2)} km remaining on trace route',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'TRACE NAV',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Top-Left Status & Control Pills (16dp corner padding)
              Positioned(
                top: widget.isReturning ? 76 : 16,
                left: 16,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => _showTileSourcePicker(context, isDark, textColor, accentColor),
                      child: Container(
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
                              widget.showOsmTiles ? 'TILES (TAP TO CHANGE)' : 'OFFLINE VECTOR',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_drop_down_rounded, size: 14, color: textColor.withValues(alpha: 0.6)),
                          ],
                        ),
                      ),
                    ),
                    if (_isFreePanning) ...[
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
                                'RECENTER GPS',
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

              // Floating Controls (Orientation, High-Zoom, Zoom +/- & GPS Recenter)
              Positioned(
                bottom: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🧭 Orientation Button (NORTH-UP / HEADING-UP)
                    _buildMapButton(
                      icon: _isHeadingUp ? Icons.navigation_rounded : Icons.explore_outlined,
                      label: _isHeadingUp ? 'HEAD-UP' : 'NORTH',
                      iconColor: _isHeadingUp ? accentColor : textColor.withValues(alpha: 0.7),
                      onPressed: _toggleHeadingUp,
                      isDark: isDark,
                      textColor: textColor,
                      borderColor: borderColor,
                    ),
                    const SizedBox(height: 8),
                    // 🔍 Guidance Mode Quick Zoom Button
                    _buildMapButton(
                      icon: Icons.alt_route_rounded,
                      label: 'GUIDE',
                      iconColor: const Color(0xFF10B981),
                      onPressed: _enableGuidanceZoom,
                      isDark: isDark,
                      textColor: textColor,
                      borderColor: borderColor,
                    ),
                    const SizedBox(height: 8),
                    // Zoom IN (+1)
                    _buildMapButton(
                      icon: Icons.add,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _zoomOffset = min(6, _zoomOffset + 1);
                          _zoomScale = min(8.0, _zoomScale * 1.35);
                        });
                      },
                      isDark: isDark,
                      textColor: textColor,
                      borderColor: borderColor,
                    ),
                    const SizedBox(height: 8),
                    // Zoom OUT (-1)
                    _buildMapButton(
                      icon: Icons.remove,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _zoomOffset = max(-4, _zoomOffset - 1);
                          _zoomScale = max(0.4, _zoomScale / 1.35);
                        });
                      },
                      isDark: isDark,
                      textColor: textColor,
                      borderColor: borderColor,
                    ),
                    const SizedBox(height: 8),
                    // GPS Recenter Puck Button
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
                          width: 42,
                          height: 42,
                          child: Center(
                            child: _isFreePanning
                                ? Transform.rotate(
                                    angle: atan2(-_userPanOffset.dy, -_userPanOffset.dx) - (pi / 2),
                                    child: const Icon(Icons.navigation_rounded, size: 20, color: Colors.white),
                                  )
                                : Icon(Icons.my_location_rounded, size: 20, color: textColor.withValues(alpha: 0.7)),
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
    String? label,
    Color? iconColor,
    required VoidCallback onPressed,
    required bool isDark,
    required Color textColor,
    required Color borderColor,
  }) {
    return Material(
      color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: label != null ? 17 : 20, color: iconColor ?? textColor),
              if (label != null) ...[
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: iconColor ?? textColor,
                  ),
                ),
              ],
            ],
          ),
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

