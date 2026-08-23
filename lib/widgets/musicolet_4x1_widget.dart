import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/platform_service.dart';

/// Available modes for the dedicated 4x1 HUD Widget Space.
enum Hud4x1WidgetMode {
  musicoletMedia('Music Controller', Icons.headphones_rounded),
  telemetryMetrics('Telemetry Glance', Icons.speed_rounded),
  paceElevation('Pace & Elevation', Icons.terrain_rounded);

  final String title;
  final IconData icon;
  const Hud4x1WidgetMode(this.title, this.icon);
}

/// A dedicated full-width 4x1 modular widget container designed for cycling & athletic HUD.
///
/// Features 3 centered, large rectangular buttons for PREV / PLAY-PAUSE / NEXT with zero text clutter.
class Modular4x1WidgetSpace extends StatefulWidget {
  final Brightness brightness;
  final Color accentColor;
  final double currentSpeedKmh;
  final double currentAltitudeMeters;
  final int heartRateBpm;
  final int cadenceRpm;
  final Duration elapsed;

  const Modular4x1WidgetSpace({
    super.key,
    required this.brightness,
    required this.accentColor,
    required this.currentSpeedKmh,
    required this.currentAltitudeMeters,
    required this.heartRateBpm,
    required this.cadenceRpm,
    required this.elapsed,
  });

  @override
  State<Modular4x1WidgetSpace> createState() => _Modular4x1WidgetSpaceState();
}

class _Modular4x1WidgetSpaceState extends State<Modular4x1WidgetSpace> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      child: Musicolet4x1MediaWidget(
        brightness: widget.brightness,
        accentColor: widget.accentColor,
      ),
    );
  }
}

/// Glove-friendly, High-Accessibility 3-Button Rectangular Media Controller for HUD & Cycling.
///
/// Has 3 big rectangular buttons for Previous, Play/Pause, Next in the center with no text.
class Musicolet4x1MediaWidget extends StatefulWidget {
  final Brightness brightness;
  final Color accentColor;

  const Musicolet4x1MediaWidget({
    super.key,
    required this.brightness,
    required this.accentColor,
  });

  @override
  State<Musicolet4x1MediaWidget> createState() => _Musicolet4x1MediaWidgetState();
}

class _Musicolet4x1MediaWidgetState extends State<Musicolet4x1MediaWidget> {
  bool _isPlaying = true;

  void _sendMediaAction(String action) {
    HapticFeedback.heavyImpact();
    PlatformService.instance.sendMediaAction(action);
    if (action == 'play_pause' || action == 'toggle') {
      setState(() => _isPlaying = !_isPlaying);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE5E7EB);
    final accent = widget.accentColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: cardBg.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. RECTANGULAR PREVIOUS BUTTON
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _sendMediaAction('previous'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C222B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 1.0),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.skip_previous_rounded,
                      size: 28,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. RECTANGULAR PLAY / PAUSE BUTTON (High Contrast Accent)
          Expanded(
            flex: 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _sendMediaAction('play_pause'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 3. RECTANGULAR NEXT BUTTON
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _sendMediaAction('next'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C222B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 1.0),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.skip_next_rounded,
                      size: 28,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
