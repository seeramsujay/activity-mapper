import 'dart:math';
import 'package:flutter/material.dart';

class TelemetrySample {
  final double distanceKm;
  final double elapsedSeconds;
  final double speedKmh;
  final double altitudeMeters;

  const TelemetrySample({
    required this.distanceKm,
    required this.elapsedSeconds,
    required this.speedKmh,
    required this.altitudeMeters,
  });
}

/// A high-performance, smooth CustomPainter chart for real-time speed & elevation profiles.
class TelemetryChart extends StatelessWidget {
  final List<TelemetrySample> samples;
  final bool plotByDuration;
  final Color speedColor;
  final Color elevationColor;
  final Color textColor;
  final Color gridColor;

  const TelemetryChart({
    super.key,
    required this.samples,
    this.plotByDuration = false,
    this.speedColor = const Color(0xFFFF5722),
    this.elevationColor = const Color(0xFF10B981),
    required this.textColor,
    required this.gridColor,
  });

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 36, color: textColor.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(
              'Awaiting telemetry data points...',
              style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    double maxSpd = 0.0;
    double minAlt = double.maxFinite;
    double maxAlt = -double.maxFinite;

    for (final s in samples) {
      if (s.speedKmh > maxSpd) maxSpd = s.speedKmh;
      if (s.altitudeMeters < minAlt) minAlt = s.altitudeMeters;
      if (s.altitudeMeters > maxAlt) maxAlt = s.altitudeMeters;
    }

    if (maxSpd < 10) maxSpd = 10;
    if (maxAlt - minAlt < 10) {
      maxAlt += 5;
      minAlt -= 5;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chart Metrics Legend Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: speedColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  'SPEED: max ${maxSpd.toStringAsFixed(1)} km/h',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: speedColor),
                ),
              ],
            ),
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: elevationColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  'ELEV: ${minAlt.toStringAsFixed(0)}m - ${maxAlt.toStringAsFixed(0)}m',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: elevationColor),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Custom Canvas Chart
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _TelemetryChartPainter(
              samples: samples,
              plotByDuration: plotByDuration,
              maxSpeed: maxSpd,
              minAltitude: minAlt,
              maxAltitude: maxAlt,
              speedColor: speedColor,
              elevationColor: elevationColor,
              textColor: textColor,
              gridColor: gridColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _TelemetryChartPainter extends CustomPainter {
  final List<TelemetrySample> samples;
  final bool plotByDuration;
  final double maxSpeed;
  final double minAltitude;
  final double maxAltitude;
  final Color speedColor;
  final Color elevationColor;
  final Color textColor;
  final Color gridColor;

  _TelemetryChartPainter({
    required this.samples,
    required this.plotByDuration,
    required this.maxSpeed,
    required this.minAltitude,
    required this.maxAltitude,
    required this.speedColor,
    required this.elevationColor,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double paddingLeft = 32.0;
    const double paddingRight = 32.0;
    const double paddingTop = 12.0;
    const double paddingBottom = 22.0;

    final double chartWidth = size.width - paddingLeft - paddingRight;
    final double chartHeight = size.height - paddingTop - paddingBottom;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw horizontal grid lines
    const int gridDivisions = 4;
    for (int i = 0; i <= gridDivisions; i++) {
      final y = paddingTop + (chartHeight / gridDivisions) * i;
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);

      // Speed Y-Axis Labels (Left)
      final speedVal = maxSpeed * (1 - (i / gridDivisions));
      final tpSpeed = TextPainter(
        text: TextSpan(text: '${speedVal.toStringAsFixed(0)}', style: TextStyle(color: speedColor, fontSize: 8, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tpSpeed.paint(canvas, Offset(paddingLeft - tpSpeed.width - 4, y - 5));

      // Elevation Y-Axis Labels (Right)
      final altVal = minAltitude + (maxAltitude - minAltitude) * (1 - (i / gridDivisions));
      final tpAlt = TextPainter(
        text: TextSpan(text: '${altVal.toStringAsFixed(0)}m', style: TextStyle(color: elevationColor, fontSize: 8, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tpAlt.paint(canvas, Offset(size.width - paddingRight + 4, y - 5));
    }

    final double maxX = plotByDuration
        ? max(1.0, samples.last.elapsedSeconds)
        : max(0.1, samples.last.distanceKm);

    // Compute Sample Points
    final List<Offset> speedPoints = [];
    final List<Offset> altPoints = [];

    for (final s in samples) {
      final double xVal = plotByDuration ? s.elapsedSeconds : s.distanceKm;
      final double x = paddingLeft + (xVal / maxX) * chartWidth;

      // Speed Y
      final double spdNorm = (s.speedKmh / maxSpeed).clamp(0.0, 1.0);
      final double ySpeed = paddingTop + chartHeight * (1.0 - spdNorm);
      speedPoints.add(Offset(x, ySpeed));

      // Alt Y
      final double altNorm = ((s.altitudeMeters - minAltitude) / (maxAltitude - minAltitude)).clamp(0.0, 1.0);
      final double yAlt = paddingTop + chartHeight * (1.0 - altNorm);
      altPoints.add(Offset(x, yAlt));
    }

    // 1. Draw Elevation Filled Area
    if (altPoints.isNotEmpty) {
      final altPath = Path()..moveTo(altPoints.first.dx, paddingTop + chartHeight);
      for (final p in altPoints) {
        altPath.lineTo(p.dx, p.dy);
      }
      altPath.lineTo(altPoints.last.dx, paddingTop + chartHeight);
      altPath.close();

      final altFillPaint = Paint()
        ..shader = LinearGradient(
          colors: [elevationColor.withValues(alpha: 0.25), elevationColor.withValues(alpha: 0.02)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(paddingLeft, paddingTop, chartWidth, chartHeight));

      canvas.drawPath(altPath, altFillPaint);

      final altStrokePaint = Paint()
        ..color = elevationColor.withValues(alpha: 0.8)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;

      final strokePath = Path()..moveTo(altPoints.first.dx, altPoints.first.dy);
      for (int i = 1; i < altPoints.length; i++) {
        strokePath.lineTo(altPoints[i].dx, altPoints[i].dy);
      }
      canvas.drawPath(strokePath, altStrokePaint);
    }

    // 2. Draw Speed Line with Accent
    if (speedPoints.isNotEmpty) {
      final speedStrokePaint = Paint()
        ..color = speedColor
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final speedPath = Path()..moveTo(speedPoints.first.dx, speedPoints.first.dy);
      for (int i = 1; i < speedPoints.length; i++) {
        speedPath.lineTo(speedPoints[i].dx, speedPoints[i].dy);
      }
      canvas.drawPath(speedPath, speedStrokePaint);

      // Pulse circle at current position
      final lastP = speedPoints.last;
      canvas.drawCircle(lastP, 4.0, Paint()..color = speedColor);
      canvas.drawCircle(lastP, 2.0, Paint()..color = Colors.white);
    }

    // X-Axis Labels
    final xLabel = plotByDuration ? 'TIME (MIN)' : 'DISTANCE (KM)';
    final tpX = TextPainter(
      text: TextSpan(
        text: '0.0',
        style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 9, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpX.paint(canvas, Offset(paddingLeft, size.height - paddingBottom + 4));

    final tpXMax = TextPainter(
      text: TextSpan(
        text: plotByDuration ? '${(maxX / 60).toStringAsFixed(1)}m' : '${maxX.toStringAsFixed(2)}km',
        style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 9, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpXMax.paint(canvas, Offset(size.width - paddingRight - tpXMax.width, size.height - paddingBottom + 4));

    final tpCenter = TextPainter(
      text: TextSpan(
        text: xLabel,
        style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.6),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpCenter.paint(canvas, Offset(paddingLeft + (chartWidth - tpCenter.width) / 2, size.height - paddingBottom + 4));
  }

  @override
  bool shouldRepaint(covariant _TelemetryChartPainter oldDelegate) {
    return oldDelegate.samples.length != samples.length ||
        oldDelegate.maxSpeed != maxSpeed ||
        oldDelegate.maxAltitude != maxAltitude;
  }
}
