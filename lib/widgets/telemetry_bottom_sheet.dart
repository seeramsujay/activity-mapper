import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/exercise_stats_service.dart';
import '../services/unit_format.dart';
import 'interactive_telemetry_graph.dart';

/// Modern expandable telemetry bottom sheet inspired by Geo Tracker & Apple Maps.
///
/// Features:
/// - Collapsed state: glanceable outdoor dashboard with large high-contrast Speed, Distance, and Time.
/// - Expanded state: interactive scrubbable elevation/speed profile, ascent/descent metrics, and action controls.
class TelemetryBottomSheet extends StatefulWidget {
  final double currentSpeedMps;
  final double avgSpeedMps;
  final double maxSpeedMps;
  final double distanceKm;
  final Duration elapsed;
  final Duration? movingDuration;
  final double altitude;
  final double totalAscent;
  final double totalDescent;
  final String activityType;
  final bool isSpeedMode;
  final bool isPaused;
  final bool isReturning;
  final Duration? remainingReturnDuration;
  final List<GraphPoint> graphPoints;
  final List<SplitLap>? splits;
  final VoidCallback onTogglePause;
  final VoidCallback onFinish;
  final VoidCallback onAddWaypoint;
  final VoidCallback? onToggleOled;
  final VoidCallback? onToggleGoogleMaps;
  final bool googleMapsMode;
  final Brightness brightness;
  final Color accentColor;

  const TelemetryBottomSheet({
    super.key,
    required this.currentSpeedMps,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    required this.distanceKm,
    required this.elapsed,
    this.movingDuration,
    required this.altitude,
    required this.totalAscent,
    required this.totalDescent,
    required this.activityType,
    required this.isSpeedMode,
    required this.isPaused,
    this.isReturning = false,
    this.remainingReturnDuration,
    required this.graphPoints,
    this.splits,
    required this.onTogglePause,
    required this.onFinish,
    required this.onAddWaypoint,
    this.onToggleOled,
    this.onToggleGoogleMaps,
    this.googleMapsMode = false,
    required this.brightness,
    required this.accentColor,
  });

  @override
  State<TelemetryBottomSheet> createState() => _TelemetryBottomSheetState();
}

class _TelemetryBottomSheetState extends State<TelemetryBottomSheet> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetScrolled);
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetScrolled);
    _sheetController.dispose();
    super.dispose();
  }

  void _onSheetScrolled() {
    final size = _sheetController.size;
    final expanded = size > 0.30;
    if (expanded != _isExpanded) {
      setState(() => _isExpanded = expanded);
    }
  }

  String _formatElapsed(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    final secs = d.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final surfaceBg =
        isDark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6);
    final borderColor =
        isDark ? const Color(0xFF2D333F) : const Color(0xFFE5E7EB);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final subtextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.18,
      minChildSize: 0.15,
      maxChildSize: 0.88,
      snap: true,
      snapSizes: const [0.18, 0.55, 0.88],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.20),
                blurRadius: 20,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // 1. Drag Handle Pill
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // 2. Primary Glanceable Driving / Running Dashboard (Always visible)
              _buildGlanceableHeader(
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: widget.accentColor,
                isDark: isDark,
              ),

              const SizedBox(height: 16),

              // 3. Quick Action Button Row (Waypoint, Eco, Finish)
              _buildActionToolbar(
                textColor: textColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
                isDark: isDark,
              ),

              const SizedBox(height: 18),

              // 4. Elevation Profile Card (Geo Tracker interactive graph)
              _buildElevationCard(
                textColor: textColor,
                subtextColor: subtextColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
                isDark: isDark,
              ),

              const SizedBox(height: 14),

              // 5. Extended Performance Telemetry (Moving/Stopped time & 4-card grid)
              _buildPerformanceGrid(
                textColor: textColor,
                subtextColor: subtextColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
              ),

              // 6. Lap Splits Card (Geo Tracker & Strava style)
              if (widget.splits != null && widget.splits!.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildSplitsCard(
                  textColor: textColor,
                  subtextColor: subtextColor,
                  surfaceBg: surfaceBg,
                  borderColor: borderColor,
                  accentColor: widget.accentColor,
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  /// Large, high-visibility glancing metrics designed for running and biking.
  Widget _buildGlanceableHeader({
    required Color textColor,
    required Color subtextColor,
    required Color accentColor,
    required bool isDark,
  }) {
    final speedKmh = widget.currentSpeedMps * 3.6;
    final speedStr = widget.isSpeedMode
        ? UnitFormat.speedValue(speedKmh).toStringAsFixed(1)
        : UnitFormat.paceFromMps(widget.currentSpeedMps);
    final speedUnit =
        widget.isSpeedMode ? UnitFormat.speedUnit : UnitFormat.paceUnit;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Metric 1: Speed / Pace (Hero)
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    speedStr,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    speedUnit,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: subtextColor,
                    ),
                  ),
                ],
              ),
              Text(
                widget.isSpeedMode ? 'SPEED' : 'PACE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: subtextColor,
                ),
              ),
            ],
          ),
        ),

        // Metric 2: Distance
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    UnitFormat.distanceValue(widget.distanceKm)
                        .toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    UnitFormat.distanceUnit,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: subtextColor,
                    ),
                  ),
                ],
              ),
              Text(
                'DISTANCE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: subtextColor,
                ),
              ),
            ],
          ),
        ),

        // Metric 3: Time
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatElapsed(widget.elapsed),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'TIME',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: subtextColor,
                ),
              ),
            ],
          ),
        ),

        // Pause / Resume Quick Action Button
        Material(
          color: widget.isPaused
              ? const Color(0xFF10B981)
              : (isDark ? const Color(0xFF222731) : const Color(0xFFE2E8F0)),
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.heavyImpact();
              widget.onTogglePause();
            },
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                widget.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                color: widget.isPaused ? Colors.white : textColor,
                size: 28,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Action buttons row inside the sheet.
  Widget _buildActionToolbar({
    required Color textColor,
    required Color surfaceBg,
    required Color borderColor,
    required bool isDark,
  }) {
    return Row(
      children: [
        // Drop Waypoint button
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
            label: const Text('MARKER',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: textColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: borderColor),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              backgroundColor: surfaceBg,
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              widget.onAddWaypoint();
            },
          ),
        ),
        const SizedBox(width: 8),

        // OLED Dimmer button
        if (widget.onToggleOled != null) ...[
          IconButton(
            tooltip: 'OLED Battery Saver',
            style: IconButton.styleFrom(
              backgroundColor: surfaceBg,
              side: BorderSide(color: borderColor),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.all(12),
            ),
            icon: const Icon(Icons.energy_savings_leaf_rounded,
                size: 20, color: Color(0xFF10B981)),
            onPressed: () {
              HapticFeedback.selectionClick();
              widget.onToggleOled?.call();
            },
          ),
          const SizedBox(width: 8),
        ],

        // Finish Session button
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.stop_rounded, size: 20, color: Colors.white),
            label: const Text('FINISH',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              HapticFeedback.heavyImpact();
              widget.onFinish();
            },
          ),
        ),
      ],
    );
  }

  /// Interactive elevation chart and climb statistics card.
  Widget _buildElevationCard({
    required Color textColor,
    required Color subtextColor,
    required Color surfaceBg,
    required Color borderColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.terrain_rounded,
                      size: 20, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text(
                    'ELEVATION & INCLINE',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: 0.6),
                  ),
                ],
              ),
              Text(
                UnitFormat.elevation(widget.altitude),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Ascent & Descent row
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.arrow_upward_rounded,
                        size: 14, color: Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    Text(
                      'Gain ${UnitFormat.elevation(widget.totalAscent, sign: '+')}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: textColor),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.arrow_downward_rounded,
                        size: 14, color: Color(0xFFF97316)),
                    const SizedBox(width: 4),
                    Text(
                      'Loss ${UnitFormat.elevation(widget.totalDescent, sign: '-')}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: textColor),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Mini interactive graph if points exist
          if (widget.graphPoints.length >= 2) ...[
            SizedBox(
              height: 310,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveTelemetryGraph(
                  points: widget.graphPoints,
                  brightness: widget.brightness,
                  initialShowSpeed: true,
                  initialShowElevation: true,
                ),
              ),
            ),
          ] else ...[
            Container(
              height: 80,
              alignment: Alignment.center,
              child: Text(
                'Logging GPS points to render elevation chart...',
                style: TextStyle(
                    fontSize: 11,
                    color: subtextColor,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 6-box grid of secondary metrics: Max Speed, Avg Speed, Moving Time, Stopped Time, Altitude, Outbound/Return.
  Widget _buildPerformanceGrid({
    required Color textColor,
    required Color subtextColor,
    required Color surfaceBg,
    required Color borderColor,
  }) {
    final avgKmh = widget.avgSpeedMps * 3.6;
    final maxKmh = widget.maxSpeedMps * 3.6;
    final movingDur = widget.movingDuration ?? widget.elapsed;
    final stoppedDur = (widget.elapsed - movingDur).isNegative
        ? Duration.zero
        : widget.elapsed - movingDur;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildStatCard(
          title: 'AVG SPEED',
          value: UnitFormat.speedKmh(avgKmh),
          icon: Icons.speed_rounded,
          iconColor: const Color(0xFF3B82F6),
          textColor: textColor,
          subtextColor: subtextColor,
          surfaceBg: surfaceBg,
          borderColor: borderColor,
        ),
        _buildStatCard(
          title: 'MAX SPEED',
          value: UnitFormat.speedKmh(maxKmh),
          icon: Icons.flash_on_rounded,
          iconColor: const Color(0xFFF59E0B),
          textColor: textColor,
          subtextColor: subtextColor,
          surfaceBg: surfaceBg,
          borderColor: borderColor,
        ),
        _buildStatCard(
          title: 'MOVING TIME',
          value: _formatElapsed(movingDur),
          icon: Icons.directions_run_rounded,
          iconColor: const Color(0xFF10B981),
          textColor: textColor,
          subtextColor: subtextColor,
          surfaceBg: surfaceBg,
          borderColor: borderColor,
        ),
        _buildStatCard(
          title: 'STOPPED TIME',
          value: _formatElapsed(stoppedDur),
          icon: Icons.pause_circle_outline_rounded,
          iconColor: const Color(0xFFF97316),
          textColor: textColor,
          subtextColor: subtextColor,
          surfaceBg: surfaceBg,
          borderColor: borderColor,
        ),
        _buildStatCard(
          title: 'ALTITUDE',
          value: UnitFormat.elevation(widget.altitude),
          icon: Icons.landscape_rounded,
          iconColor: const Color(0xFF10B981),
          textColor: textColor,
          subtextColor: subtextColor,
          surfaceBg: surfaceBg,
          borderColor: borderColor,
        ),
        _buildStatCard(
          title: widget.isReturning ? 'RETURN PHASE' : 'OUTBOUND',
          value: widget.remainingReturnDuration != null
              ? _formatElapsed(widget.remainingReturnDuration!)
              : _formatElapsed(widget.elapsed),
          icon: widget.isReturning
              ? Icons.u_turn_left_rounded
              : Icons.explore_rounded,
          iconColor: widget.isReturning
              ? const Color(0xFFEF4444)
              : const Color(0xFF8B5CF6),
          textColor: textColor,
          subtextColor: subtextColor,
          surfaceBg: surfaceBg,
          borderColor: borderColor,
        ),
      ],
    );
  }

  /// Split lap breakdown card inspired by Strava & Geo Tracker.
  Widget _buildSplitsCard({
    required Color textColor,
    required Color subtextColor,
    required Color surfaceBg,
    required Color borderColor,
    required Color accentColor,
  }) {
    final splits = widget.splits!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Text(
                    'LAP SPLITS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              Text(
                '${splits.length} Laps',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: subtextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Split table header
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '#',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: subtextColor),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'PACE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: subtextColor),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'TIME',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: subtextColor),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'ELEVATION',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: subtextColor),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: borderColor, height: 1),
          const SizedBox(height: 4),
          ...splits.map((s) {
            final gainStr =
                UnitFormat.elevation(s.elevationGainMeters, sign: '+');
            final lossStr =
                UnitFormat.elevation(s.elevationLossMeters, sign: '-');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${s.number}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${s.paceMinKm} /km',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      _formatElapsed(s.duration),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: subtextColor,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '$gainStr / $lossStr',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: subtextColor,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color textColor,
    required Color subtextColor,
    required Color surfaceBg,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: subtextColor,
                      letterSpacing: 0.6),
                ),
                Text(
                  value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: textColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
