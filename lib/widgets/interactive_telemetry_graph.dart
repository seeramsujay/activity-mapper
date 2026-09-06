import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Single telemetry point for graph plotting.
class GraphPoint {
  final double distanceKm;
  final double elapsedSeconds;
  final double speedKmh;
  final double altitudeMeters;
  final int? heartRateBpm;
  final int? cadenceRpm;

  const GraphPoint({
    required this.distanceKm,
    required this.elapsedSeconds,
    required this.speedKmh,
    required this.altitudeMeters,
    this.heartRateBpm,
    this.cadenceRpm,
  });
}

/// Rich, interactive multi-series telemetry graph with independent series toggles,
/// dual X-axis modes (distance vs time), and touch-scrubbing crosshair tooltips.
class InteractiveTelemetryGraph extends StatefulWidget {
  final List<GraphPoint> points;
  final Brightness brightness;
  final bool initialShowSpeed;
  final bool initialShowElevation;
  final bool initialShowHeartRate;
  final bool initialShowCadence;
  final bool initialPlotByDuration;

  const InteractiveTelemetryGraph({
    super.key,
    required this.points,
    required this.brightness,
    this.initialShowSpeed = true,
    this.initialShowElevation = true,
    this.initialShowHeartRate = false,
    this.initialShowCadence = false,
    this.initialPlotByDuration = false,
  });

  @override
  State<InteractiveTelemetryGraph> createState() => _InteractiveTelemetryGraphState();
}

class _InteractiveTelemetryGraphState extends State<InteractiveTelemetryGraph> {
  late bool _showSpeed;
  late bool _showElevation;
  late bool _showHeartRate;
  late bool _showCadence;
  late bool _plotByDuration;

  int? _scrubIndex;

  @override
  void initState() {
    super.initState();
    _showSpeed = widget.initialShowSpeed;
    _showElevation = widget.initialShowElevation;
    _showHeartRate = widget.initialShowHeartRate;
    _showCadence = widget.initialShowCadence;
    _plotByDuration = widget.initialPlotByDuration;
  }

  void _onScrub(Offset localPos, Size size) {
    if (widget.points.length < 2) return;
    const paddingLeft = 40.0;
    const paddingRight = 16.0;
    final chartWidth = size.width - paddingLeft - paddingRight;
    if (chartWidth <= 0) return;

    final x = (localPos.dx - paddingLeft).clamp(0.0, chartWidth);
    final ratio = x / chartWidth;
    final index = (ratio * (widget.points.length - 1)).round().clamp(0, widget.points.length - 1);

    if (index != _scrubIndex) {
      HapticFeedback.selectionClick();
      setState(() {
        _scrubIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE2E8F0);

    const speedColor = Color(0xFFFF5722);
    const elevationColor = Color(0xFF10B981);
    const hrColor = Color(0xFFEF4444);
    const cadenceColor = Color(0xFF3B82F6);

    final hasHr = widget.points.any((p) => p.heartRateBpm != null && p.heartRateBpm! > 0);
    final hasCadence = widget.points.any((p) => p.cadenceRpm != null && p.cadenceRpm! > 0);

    if (widget.points.length < 2) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, size: 40, color: textColor.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                'Waiting for activity telemetry data...',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Graph Toggle Filter Bar
          Row(
            children: [
              Text(
                'TELEMETRY GRAPHS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              // X-Axis Switcher (Dist vs Time)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _plotByDuration = !_plotByDuration);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _plotByDuration ? 'X: DURATION' : 'X: DISTANCE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: textColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Independent Series Toggle Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildToggleChip(
                  label: 'SPEED',
                  color: speedColor,
                  isSelected: _showSpeed,
                  onTap: () => setState(() => _showSpeed = !_showSpeed),
                ),
                const SizedBox(width: 8),
                _buildToggleChip(
                  label: 'ELEVATION',
                  color: elevationColor,
                  isSelected: _showElevation,
                  onTap: () => setState(() => _showElevation = !_showElevation),
                ),
                if (hasHr) ...[
                  const SizedBox(width: 8),
                  _buildToggleChip(
                    label: 'HEART RATE',
                    color: hrColor,
                    isSelected: _showHeartRate,
                    onTap: () => setState(() => _showHeartRate = !_showHeartRate),
                  ),
                ],
                if (hasCadence) ...[
                  const SizedBox(width: 8),
                  _buildToggleChip(
                    label: 'CADENCE',
                    color: cadenceColor,
                    isSelected: _showCadence,
                    onTap: () => setState(() => _showCadence = !_showCadence),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Active Scrubber Tooltip Strip
          if (_scrubIndex != null && _scrubIndex! < widget.points.length)
            _buildScrubberTooltip(widget.points[_scrubIndex!], textColor, isDark),

          const SizedBox(height: 8),

          // Main Graph CustomPaint Canvas with Gesture Touch Listener
          SizedBox(
            height: 180,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chartSize = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onPanDown: (d) => _onScrub(d.localPosition, chartSize),
                  onPanUpdate: (d) => _onScrub(d.localPosition, chartSize),
                  onPanEnd: (_) => setState(() => _scrubIndex = null),
                  onPanCancel: () => setState(() => _scrubIndex = null),
                  child: CustomPaint(
                    size: chartSize,
                    painter: _MultiSeriesChartPainter(
                      points: widget.points,
                      showSpeed: _showSpeed,
                      showElevation: _showElevation,
                      showHeartRate: _showHeartRate,
                      showCadence: _showCadence,
                      plotByDuration: _plotByDuration,
                      speedColor: speedColor,
                      elevationColor: elevationColor,
                      hrColor: hrColor,
                      cadenceColor: cadenceColor,
                      textColor: textColor,
                      isDark: isDark,
                      scrubIndex: _scrubIndex,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: isSelected ? color : color.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrubberTooltip(GraphPoint p, Color textColor, bool isDark) {
    final xStr = _plotByDuration
        ? '${(p.elapsedSeconds ~/ 60)}m ${(p.elapsedSeconds % 60).toInt()}s'
        : '${p.distanceKm.toStringAsFixed(2)} km';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.grey.shade100).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withValues(alpha: 0.15)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(
            'AT: $xStr',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: textColor),
          ),
          if (_showSpeed)
            Text(
              'SPD: ${p.speedKmh.toStringAsFixed(1)} km/h',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFFF5722)),
            ),
          if (_showElevation)
            Text(
              'ALT: ${p.altitudeMeters.toStringAsFixed(0)} m',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
            ),
          if (_showHeartRate && p.heartRateBpm != null)
            Text(
              'HR: ${p.heartRateBpm} bpm',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFEF4444)),
            ),
          if (_showCadence && p.cadenceRpm != null)
            Text(
              'CAD: ${p.cadenceRpm} rpm',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF3B82F6)),
            ),
        ],
      ),
    );
  }
}

/// CustomPainter rendering multi-series curves with vertical scrub crosshair.
class _MultiSeriesChartPainter extends CustomPainter {
  final List<GraphPoint> points;
  final bool showSpeed;
  final bool showElevation;
  final bool showHeartRate;
  final bool showCadence;
  final bool plotByDuration;
  final Color speedColor;
  final Color elevationColor;
  final Color hrColor;
  final Color cadenceColor;
  final Color textColor;
  final bool isDark;
  final int? scrubIndex;

  _MultiSeriesChartPainter({
    required this.points,
    required this.showSpeed,
    required this.showElevation,
    required this.showHeartRate,
    required this.showCadence,
    required this.plotByDuration,
    required this.speedColor,
    required this.elevationColor,
    required this.hrColor,
    required this.cadenceColor,
    required this.textColor,
    required this.isDark,
    this.scrubIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 40.0;
    const rightPad = 12.0;
    const topPad = 10.0;
    const bottomPad = 24.0;

    final w = size.width - leftPad - rightPad;
    final h = size.height - topPad - bottomPad;
    if (w <= 0 || h <= 0) return;

    // Determine min/max domains
    double maxSpeed = 0.0;
    double minAlt = double.maxFinite;
    double maxAlt = -double.maxFinite;
    double maxHr = 0.0;
    double maxCad = 0.0;

    for (final p in points) {
      if (p.speedKmh > maxSpeed) maxSpeed = p.speedKmh;
      if (p.altitudeMeters < minAlt) minAlt = p.altitudeMeters;
      if (p.altitudeMeters > maxAlt) maxAlt = p.altitudeMeters;
      if (p.heartRateBpm != null && p.heartRateBpm! > maxHr) maxHr = p.heartRateBpm!.toDouble();
      if (p.cadenceRpm != null && p.cadenceRpm! > maxCad) maxCad = p.cadenceRpm!.toDouble();
    }

    if (maxSpeed < 10) maxSpeed = 10;
    if (maxAlt - minAlt < 10) {
      maxAlt += 5;
      minAlt -= 5;
    }
    if (maxHr < 100) maxHr = 180;
    if (maxCad < 60) maxCad = 120;

    // Draw horizontal gridlines
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final y = topPad + (h / 3) * i;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
    }

    final int len = points.length;

    // Helper: X Coordinate calculation
    double getX(int index) {
      return leftPad + (index / (len - 1)) * w;
    }

    // 1. Draw Elevation Series (Filled area below)
    if (showElevation) {
      final altPath = Path();
      final altFillPath = Path();

      for (int i = 0; i < len; i++) {
        final x = getX(i);
        final ratio = (points[i].altitudeMeters - minAlt) / (maxAlt - minAlt);
        final y = topPad + h - (ratio * h);

        if (i == 0) {
          altPath.moveTo(x, y);
          altFillPath.moveTo(x, topPad + h);
          altFillPath.lineTo(x, y);
        } else {
          altPath.lineTo(x, y);
          altFillPath.lineTo(x, y);
        }
      }

      altFillPath.lineTo(leftPad + w, topPad + h);
      altFillPath.close();

      canvas.drawPath(
        altFillPath,
        Paint()
          ..color = elevationColor.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );

      canvas.drawPath(
        altPath,
        Paint()
          ..color = elevationColor
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }

    // 2. Draw Speed Series
    if (showSpeed) {
      final spdPath = Path();
      for (int i = 0; i < len; i++) {
        final x = getX(i);
        final ratio = (points[i].speedKmh / maxSpeed).clamp(0.0, 1.0);
        final y = topPad + h - (ratio * h);

        if (i == 0) {
          spdPath.moveTo(x, y);
        } else {
          spdPath.lineTo(x, y);
        }
      }

      canvas.drawPath(
        spdPath,
        Paint()
          ..color = speedColor
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke,
      );
    }

    // 3. Draw Heart Rate Series
    if (showHeartRate) {
      final hrPath = Path();
      for (int i = 0; i < len; i++) {
        final x = getX(i);
        final hr = (points[i].heartRateBpm ?? 0).toDouble();
        final ratio = (hr / maxHr).clamp(0.0, 1.0);
        final y = topPad + h - (ratio * h);

        if (i == 0) {
          hrPath.moveTo(x, y);
        } else {
          hrPath.lineTo(x, y);
        }
      }

      canvas.drawPath(
        hrPath,
        Paint()
          ..color = hrColor
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
    }

    // 4. Draw Cadence Series
    if (showCadence) {
      final cadPath = Path();
      for (int i = 0; i < len; i++) {
        final x = getX(i);
        final cad = (points[i].cadenceRpm ?? 0).toDouble();
        final ratio = (cad / maxCad).clamp(0.0, 1.0);
        final y = topPad + h - (ratio * h);

        if (i == 0) {
          cadPath.moveTo(x, y);
        } else {
          cadPath.lineTo(x, y);
        }
      }

      canvas.drawPath(
        cadPath,
        Paint()
          ..color = cadenceColor
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
    }

    // 5. Draw Interactive Scrub Indicator
    if (scrubIndex != null && scrubIndex! >= 0 && scrubIndex! < len) {
      final scrubX = getX(scrubIndex!);
      final scrubPaint = Paint()
        ..color = textColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.5;

      canvas.drawLine(Offset(scrubX, topPad), Offset(scrubX, topPad + h), scrubPaint);
      canvas.drawCircle(Offset(scrubX, topPad + h / 2), 4.0, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(scrubX, topPad + h / 2), 2.5, Paint()..color = Colors.black);
    }

    // 6. Draw X-Axis Labels (Start & End)
    final textStyle = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      color: textColor.withValues(alpha: 0.5),
    );

    final startLabel = plotByDuration ? '0:00' : '0.0 km';
    final endLabel = plotByDuration
        ? '${points.last.elapsedSeconds ~/ 60}m'
        : '${points.last.distanceKm.toStringAsFixed(1)} km';

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    textPainter.text = TextSpan(text: startLabel, style: textStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(leftPad, topPad + h + 6));

    textPainter.text = TextSpan(text: endLabel, style: textStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - rightPad - textPainter.width, topPad + h + 6));
  }

  @override
  bool shouldRepaint(covariant _MultiSeriesChartPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.showSpeed != showSpeed ||
        oldDelegate.showElevation != showElevation ||
        oldDelegate.showHeartRate != showHeartRate ||
        oldDelegate.showCadence != showCadence ||
        oldDelegate.plotByDuration != plotByDuration ||
        oldDelegate.scrubIndex != scrubIndex;
  }
}
