import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../services/exercise_stats_service.dart';
import '../services/export_service.dart';
import '../services/settings_service.dart';
import '../widgets/interactive_telemetry_graph.dart';
import '../widgets/vector_map_view.dart';

/// Dedicated post-workout summary layout featuring only Map View and Stats View with
/// interactive toggleable multi-series graphs and a multi-format export hub.
class WorkoutSummaryScreen extends StatefulWidget {
  final int sessionId;
  final String activityType;

  const WorkoutSummaryScreen({
    super.key,
    required this.sessionId,
    required this.activityType,
  });

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _points = [];
  ExerciseStats? _stats;
  List<GraphPoint> _graphPoints = [];
  String? _exportedFeedback;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadWorkoutData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkoutData() async {
    final db = DbService.instance;
    final session = await db.getSession(widget.sessionId);
    final points = await db.getPoints(widget.sessionId);

    if (session != null) {
      final start = session['start_time'] as int;
      final end = session['end_time'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      final totalDuration = Duration(milliseconds: end - start);

      int movingMs = 0;
      for (int i = 1; i < points.length; i++) {
        final speed = (points[i]['speed'] as num?)?.toDouble() ?? 0.0;
        final dt = (points[i]['timestamp'] as int) - (points[i - 1]['timestamp'] as int);
        if (speed > 0.2 && dt >= 1 && dt <= 15000) {
          movingMs += dt;
        }
      }
      final movingDuration = Duration(milliseconds: movingMs > 0 ? movingMs : (end - start));

      DateTime? turnBackTriggered;
      if (session['turn_back_triggered_at'] != null) {
        turnBackTriggered = DateTime.fromMillisecondsSinceEpoch(session['turn_back_triggered_at'] as int);
      }

      final stats = ExerciseStatsService.computeSessionStats(
        points: points,
        activityType: widget.activityType,
        totalDuration: totalDuration,
        movingDuration: movingDuration,
        turnBackTriggeredAt: turnBackTriggered,
      );

      // Build graph points
      double cumDist = 0.0;
      const p = 0.017453292519943295;
      final List<GraphPoint> gPoints = [];

      for (int i = 0; i < points.length; i++) {
        final pt = points[i];
        final lat = (pt['lat'] as num).toDouble();
        final lng = (pt['lng'] as num).toDouble();
        final alt = (pt['altitude'] as num?)?.toDouble() ?? 0.0;
        final spd = ((pt['speed'] as num?)?.toDouble() ?? 0.0) * 3.6;
        final ts = pt['timestamp'] as int;
        final elapsedSec = (ts - start) / 1000.0;

        if (i > 0) {
          final prevLat = (points[i - 1]['lat'] as num).toDouble();
          final prevLng = (points[i - 1]['lng'] as num).toDouble();
          final a = 0.5 -
              cos((lat - prevLat) * p) / 2 +
              cos(prevLat * p) * cos(lat * p) * (1 - cos((lng - prevLng) * p)) / 2;
          cumDist += 12742 * asin(sqrt(a));
        }

        gPoints.add(GraphPoint(
          distanceKm: cumDist,
          elapsedSeconds: elapsedSec.clamp(0.0, 864000.0),
          speedKmh: spd,
          altitudeMeters: alt,
        ));
      }

      if (mounted) {
        setState(() {
          _session = session;
          _points = points;
          _stats = stats;
          _graphPoints = gPoints;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportAs(String format) async {
    HapticFeedback.mediumImpact();
    setState(() => _exportedFeedback = 'Generating $format export...');
    try {
      final name = '${widget.activityType.toUpperCase()}_workout_${widget.sessionId}';
      File? file;

      if (format.toUpperCase() == 'ZIP') {
        file = await ExportService.instance.exportSessionZipBundle(widget.sessionId, name);
      } else {
        file = await ExportService.instance.exportSingleFormat(
          sessionId: widget.sessionId,
          activityName: name,
          format: format.toLowerCase(),
        );
      }

      if (mounted) {
        final filePath = file.path;
        setState(() {
          _exportedFeedback = '$format Exported: ${filePath.split('/').last}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_exportedFeedback!),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exportedFeedback = 'Export Failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = SettingsService.instance.accentColor.color;
    final bgColor = isDark ? const Color(0xFF090B0E) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFCBD5E1);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: CircularProgressIndicator(color: accentColor),
        ),
      );
    }

    if (_stats == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(title: const Text('Workout Summary')),
        body: const Center(child: Text('Activity session not found.')),
      );
    }

    final stats = _stats!;
    final pointList = _points.map((p) => Point<double>((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar / Title Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border(bottom: BorderSide(color: borderColor, width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getActivityIcon(widget.activityType),
                      color: accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.activityType.toUpperCase()} SUMMARY',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: textColor,
                          ),
                        ),
                        Text(
                          _formatDate(_session?['start_time'] as int?),
                          style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                  // Done Button
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                ],
              ),
            ),

            // Segmented 2-View Tab Selector (Map View vs Stats & Graphs)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: accentColor,
                unselectedLabelColor: textColor.withValues(alpha: 0.6),
                labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.6),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(icon: Icon(Icons.map_rounded, size: 18), text: 'MAP VIEW'),
                  Tab(icon: Icon(Icons.analytics_rounded, size: 18), text: 'STATS & GRAPHS'),
                ],
              ),
            ),

            // Tab View Body: 1. Map View | 2. Stats & Graphs
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // VIEW 1: Dedicated Map Canvas
                  _buildMapView(pointList, isDark),

                  // VIEW 2: Stats Cards + Toggleable Graphs + Detailed Breakdown + Exporter
                  _buildStatsAndGraphsView(stats, cardBg, textColor, borderColor, accentColor, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView(List<Point<double>> points, bool isDark) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: VectorMapView(
        points: points,
        brightness: isDark ? Brightness.dark : Brightness.light,
        isReturning: _session?['turn_back_triggered_at'] != null,
      ),
    );
  }

  Widget _buildStatsAndGraphsView(
    ExerciseStats stats,
    Color cardBg,
    Color textColor,
    Color borderColor,
    Color accentColor,
    bool isDark,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 1. Hero Metric Cards Grid (Distance, Duration, Calories, Avg Speed, Elev Gain)
        Row(
          children: [
            Expanded(
              child: _buildHeroMetricCard(
                title: 'DISTANCE',
                value: '${stats.distanceKm.toStringAsFixed(2)} km',
                icon: Icons.straighten_rounded,
                accentColor: accentColor,
                cardBg: cardBg,
                textColor: textColor,
                borderColor: borderColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildHeroMetricCard(
                title: 'DURATION',
                value: _formatDuration(stats.totalDuration),
                icon: Icons.timer_outlined,
                accentColor: Colors.amber,
                cardBg: cardBg,
                textColor: textColor,
                borderColor: borderColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildHeroMetricCard(
                title: 'CALORIES BURNT',
                value: '${stats.caloriesBurntKcal.toStringAsFixed(0)} kcal',
                icon: Icons.local_fire_department_rounded,
                accentColor: const Color(0xFFEF4444),
                cardBg: cardBg,
                textColor: textColor,
                borderColor: borderColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildHeroMetricCard(
                title: 'AVG SPEED',
                value: '${stats.avgSpeedKmh.toStringAsFixed(1)} km/h',
                icon: Icons.speed_rounded,
                accentColor: const Color(0xFF3B82F6),
                cardBg: cardBg,
                textColor: textColor,
                borderColor: borderColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Interactive Telemetry Graphs with Toggle Chips
        InteractiveTelemetryGraph(
          points: _graphPoints,
          brightness: isDark ? Brightness.dark : Brightness.light,
          initialShowSpeed: true,
          initialShowElevation: true,
        ),
        const SizedBox(height: 16),

        // 3. Detailed Exercise Breakdown Table
        _buildExerciseStatsTable(stats, cardBg, textColor, borderColor, accentColor),
        const SizedBox(height: 20),

        // 4. Multi-Format Exporter Hub
        _buildExportHub(cardBg, textColor, borderColor, accentColor),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildHeroMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required Color cardBg,
    required Color textColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: textColor.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseStatsTable(
    ExerciseStats stats,
    Color cardBg,
    Color textColor,
    Color borderColor,
    Color accentColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fitness_center_rounded, size: 16, color: accentColor),
              const SizedBox(width: 8),
              Text(
                'EXERCISE TELEMETRY BREAKDOWN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: textColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow('Calories Burnt', '${stats.caloriesBurntKcal.toStringAsFixed(0)} kcal', textColor),
          _buildDetailRow('Average Speed', '${stats.avgSpeedKmh.toStringAsFixed(1)} km/h', textColor),
          _buildDetailRow('Maximum Speed', '${stats.maxSpeedKmh.toStringAsFixed(1)} km/h', textColor),
          _buildDetailRow('Average Pace', '${stats.avgPaceMinKm} min/km', textColor),
          _buildDetailRow('Best Pace', '${stats.bestPaceMinKm} min/km', textColor),
          const Divider(height: 16),
          _buildDetailRow('Elevation Gain', '+${stats.elevationGainMeters.toStringAsFixed(0)} m', textColor),
          _buildDetailRow('Elevation Loss', '-${stats.elevationLossMeters.toStringAsFixed(0)} m', textColor),
          _buildDetailRow('Altitude Range', '${stats.minAltitudeMeters.toStringAsFixed(0)}m – ${stats.maxAltitudeMeters.toStringAsFixed(0)}m', textColor),
          _buildDetailRow('Average Altitude', '${stats.avgAltitudeMeters.toStringAsFixed(0)} m', textColor),
          const Divider(height: 16),
          _buildDetailRow('Active Moving Duration', _formatDuration(stats.movingDuration), textColor),
          _buildDetailRow('Total Elapsed Duration', _formatDuration(stats.totalDuration), textColor),
          _buildDetailRow('Active Moving Ratio', '${(stats.activeMovingRatio * 100).toStringAsFixed(0)}%', textColor),
          _buildDetailRow('Logged Trackpoints', '${stats.totalTrackpoints} nodes', textColor),
          if (stats.turnBackTriggeredAt != null)
            _buildDetailRow('Turn-Around Signal', 'TRIGGERED', const Color(0xFF10B981)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.7))),
          Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _buildExportHub(Color cardBg, Color textColor, Color borderColor, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ios_share_rounded, size: 16, color: accentColor),
              const SizedBox(width: 8),
              Text(
                'MULTI-FORMAT EXPORT HUB',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: textColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildExportButton('GPX 1.1', Icons.share_location, () => _exportAs('GPX')),
              _buildExportButton('TCX', Icons.fitness_center, () => _exportAs('TCX')),
              _buildExportButton('CSV', Icons.table_chart_outlined, () => _exportAs('CSV')),
              _buildExportButton('GeoJSON', Icons.code_rounded, () => _exportAs('GeoJSON')),
              _buildExportButton('KML', Icons.public, () => _exportAs('KML')),
              _buildExportButton('ZIP Archive', Icons.archive_outlined, () => _exportAs('ZIP'), isHighlight: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton(String label, IconData icon, VoidCallback onTap, {bool isHighlight = false}) {
    return Material(
      color: isHighlight
          ? SettingsService.instance.accentColor.color.withValues(alpha: 0.2)
          : (Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isHighlight ? SettingsService.instance.accentColor.color : null),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: isHighlight ? SettingsService.instance.accentColor.color : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getActivityIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('ride') || t.contains('cycle') || t.contains('bike')) return Icons.directions_bike;
    if (t.contains('walk')) return Icons.directions_walk;
    if (t.contains('hike')) return Icons.hiking;
    if (t.contains('vehicle') || t.contains('drive') || t.contains('car') || t.contains('motor')) return Icons.directions_car;
    return Icons.directions_run;
  }

  String _formatDate(int? epochMs) {
    if (epochMs == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${dt.day}/${dt.month}/${dt.year} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h}h ${m}m ${s}s';
    }
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
