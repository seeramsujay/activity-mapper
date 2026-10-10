import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../screens/workout_summary_screen.dart';
import 'breadcrumb_painter.dart';
import 'track_magic_sheet.dart';

/// Clean, uncluttered activity track card.
///
/// Features:
/// - Pure, modern visual design without cluttered inline action button rows
/// - Single-tap: Opens detailed workout view with charts and splits
/// - Long-press: Triggers haptic feedback and opens the "Track Magic Menu" action sheet
/// - Discoverable "..." menu button in card header
/// - Live breadcrumb mini-route thumbnail
class SessionFeedCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final Color textColor;
  final Brightness brightness;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onContinue;
  final VoidCallback? onRefresh;
  final double? initialDistanceKm;
  final List<Point<double>>? initialPoints;

  const SessionFeedCard({
    super.key,
    required this.session,
    required this.textColor,
    required this.brightness,
    required this.onDelete,
    required this.onEdit,
    this.onContinue,
    this.onRefresh,
    this.initialDistanceKm,
    this.initialPoints,
  });

  @override
  State<SessionFeedCard> createState() => _SessionFeedCardState();
}

class _SessionFeedCardState extends State<SessionFeedCard> {
  List<Point<double>> _mapPoints = [];
  double _distanceKm = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialPoints != null || widget.initialDistanceKm != null) {
      _mapPoints = widget.initialPoints ?? [];
      _distanceKm = widget.initialDistanceKm ?? 0.0;
      _isLoading = false;
    } else {
      _loadPoints();
    }
  }

  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const pVal = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * pVal) / 2 +
          cos(lat1 * pVal) * cos(lat2 * pVal) *
          (1 - cos((lon2 - lon1) * pVal)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Future<void> _loadPoints() async {
    try {
      final dbHelper = DbService.instance;
      final points = await dbHelper.getPoints(widget.session['id'] as int);
      
      double dist = 0.0;
      List<Point<double>> parsed = [];
      
      for (int i = 0; i < points.length; i++) {
        final lat = ((points[i]['lat'] ?? 0.0) as num).toDouble();
        final lng = ((points[i]['lng'] ?? 0.0) as num).toDouble();
        parsed.add(Point(lat, lng));
        
        if (i > 0) {
          dist += _distanceBetween(parsed[i-1].x, parsed[i-1].y, lat, lng);
        }
      }

      if (mounted) {
        setState(() {
          _mapPoints = parsed;
          _distanceKm = dist;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  IconData _getActivityIcon(String type) {
    switch (type.toLowerCase()) {
      case 'ride':
      case 'cycling':
      case 'bike':
        return Icons.directions_bike_rounded;
      case 'hike':
      case 'hiking':
        return Icons.hiking_rounded;
      case 'walk':
      case 'walking':
        return Icons.directions_walk_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  Color _getActivityColor(String type) {
    switch (type.toLowerCase()) {
      case 'ride':
      case 'cycling':
      case 'bike':
        return const Color(0xFF06B6D4);
      case 'hike':
      case 'hiking':
        return const Color(0xFF10B981);
      case 'walk':
      case 'walking':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFFFF5722);
    }
  }

  String _formatPace(double distKm, Duration dur) {
    if (distKm <= 0.05 || dur.inSeconds <= 0) return '--';
    final secPerKm = dur.inSeconds / distKm;
    if (secPerKm > 3600) return '>60m/km';
    final m = (secPerKm ~/ 60);
    final s = (secPerKm % 60).round().toString().padLeft(2, '0');
    return "$m'$s\"/km";
  }

  void _openMagicMenu() {
    final startMs = widget.session['start_time'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final endMs = widget.session['end_time'] as int?;
    final duration = endMs != null ? Duration(milliseconds: endMs - startMs) : Duration.zero;

    TrackMagicSheet.show(
      context: context,
      session: widget.session,
      distanceKm: _distanceKm,
      duration: duration,
      mapPoints: _mapPoints,
      onContinue: widget.onContinue,
      onEdit: widget.onEdit,
      onDelete: widget.onDelete,
      onRefresh: widget.onRefresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final int id = session['id'] as int;
    final String type = (session['activity_type'] as String? ?? 'run').toUpperCase();
    final int targetSec = session['target_duration'] as int? ?? 5400;
    final int startMs = session['start_time'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final int? endMs = session['end_time'] as int?;

    final startDate = DateTime.fromMillisecondsSinceEpoch(startMs);
    final duration = endMs != null ? Duration(milliseconds: endMs - startMs) : Duration.zero;

    final String dateString = '${startDate.day}/${startDate.month}/${startDate.year}';
    final String timeString = '${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}';
    final String durationString = '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    final bool triggered = session['turn_back_triggered_at'] != null;

    final isDark = widget.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE5E7EB);
    final activityColor = _getActivityColor(type);
    final paceString = _formatPace(_distanceKm, duration);

    return Container(
      margin: const EdgeInsets.only(bottom: 14.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkoutSummaryScreen(
                  sessionId: id,
                  activityType: type.toLowerCase(),
                ),
              ),
            ).then((_) => widget.onRefresh?.call());
          },
          onLongPress: _openMagicMenu,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Clean Header: Icon, Type #id, Date, Status chip & More Button (...)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF191D24) : const Color(0xFFF8F9FA),
                  border: Border(bottom: BorderSide(color: borderColor, width: 1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: activityColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_getActivityIcon(type), size: 18, color: activityColor),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$type #$id',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                                color: widget.textColor,
                                letterSpacing: 0.4,
                              ),
                            ),
                            Text(
                              '$dateString • $timeString',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: widget.textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (triggered ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                triggered ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                                size: 12,
                                color: triggered ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                triggered ? 'TURN-BACK' : 'SAFE OUT-BACK',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                  color: triggered ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(Icons.more_horiz_rounded, size: 20, color: widget.textColor.withValues(alpha: 0.5)),
                          tooltip: 'Track actions (Long-press)',
                          onPressed: _openMagicMenu,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Content Body: Stats + Breadcrumb route thumbnail
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Stats details
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL DISTANCE',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: widget.textColor.withValues(alpha: 0.45), letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isLoading ? '...' : '${_distanceKm.toStringAsFixed(2)} KM',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: widget.textColor, letterSpacing: -0.5),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('DURATION', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: widget.textColor.withValues(alpha: 0.45))),
                                  const SizedBox(height: 1),
                                  Text(durationString, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: widget.textColor)),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('AVG PACE', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: widget.textColor.withValues(alpha: 0.45))),
                                  const SizedBox(height: 1),
                                  Text(paceString, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: widget.textColor)),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('TARGET', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: widget.textColor.withValues(alpha: 0.45))),
                                  const SizedBox(height: 1),
                                  Text('${targetSec ~/ 60}m', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: widget.textColor)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Clean Route Thumbnail Box
                    Container(
                      width: 90,
                      height: 82,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F1116) : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor, width: 1.2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _isLoading
                          ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.0)))
                          : _mapPoints.isEmpty
                              ? Center(child: Text("NO GPS", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: widget.textColor.withValues(alpha: 0.4))))
                              : RepaintBoundary(
                                  child: CustomPaint(
                                    painter: BreadcrumbPainter(points: _mapPoints, brightness: widget.brightness),
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
}
