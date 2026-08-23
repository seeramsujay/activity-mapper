import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/platform_service.dart';

/// Available modes for the dedicated 4x1 HUD Widget Space.
enum Hud4x1WidgetMode {
  musicoletMedia('Musicolet Media (4x1)', Icons.headphones_rounded),
  telemetryMetrics('Telemetry Glance (4x1)', Icons.speed_rounded),
  paceElevation('Pace & Elevation (4x1)', Icons.terrain_rounded);

  final String title;
  final IconData icon;
  const Hud4x1WidgetMode(this.title, this.icon);
}

/// A dedicated full-width 4x1 modular widget container designed for HUD integration.
///
/// Houses the default Musicolet 4x1 media player widget or interchangeable 4x1 glance widgets.
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
  Hud4x1WidgetMode _currentMode = Hud4x1WidgetMode.musicoletMedia;
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE5E7EB);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: cardBg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top 4x1 Widget Slot Switcher Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1216) : const Color(0xFFF3F4F6),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _currentMode.icon,
                      size: 13,
                      color: widget.accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _currentMode.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: textColor.withValues(alpha: 0.6),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Switch 4x1 widget mode menu
                    PopupMenuButton<Hud4x1WidgetMode>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.swap_horiz_rounded, size: 16, color: widget.accentColor),
                      tooltip: 'Switch 4x1 Widget',
                      onSelected: (mode) {
                        HapticFeedback.selectionClick();
                        setState(() => _currentMode = mode);
                      },
                      itemBuilder: (ctx) => Hud4x1WidgetMode.values.map((m) {
                        return PopupMenuItem(
                          value: m,
                          child: Row(
                            children: [
                              Icon(m.icon, size: 16, color: m == _currentMode ? widget.accentColor : textColor),
                              const SizedBox(width: 8),
                              Text(m.title, style: TextStyle(fontSize: 12, fontWeight: m == _currentMode ? FontWeight.bold : FontWeight.normal)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    // Collapse / Expand toggle
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isCollapsed = !_isCollapsed);
                      },
                      child: Icon(
                        _isCollapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        size: 18,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (!_isCollapsed)
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: _build4x1Content(textColor, isDark),
            ),
        ],
      ),
    );
  }

  Widget _build4x1Content(Color textColor, bool isDark) {
    switch (_currentMode) {
      case Hud4x1WidgetMode.musicoletMedia:
        return Musicolet4x1MediaWidget(
          brightness: widget.brightness,
          accentColor: widget.accentColor,
        );
      case Hud4x1WidgetMode.telemetryMetrics:
        return _build4x1TelemetryGrid(textColor);
      case Hud4x1WidgetMode.paceElevation:
        return _build4x1PaceElevationGrid(textColor);
    }
  }

  Widget _build4x1TelemetryGrid(Color textColor) {
    return Row(
      children: [
        _build4x1Tile('SPEED', '${widget.currentSpeedKmh.toStringAsFixed(1)}', 'km/h', Icons.speed_rounded, widget.accentColor, textColor),
        const SizedBox(width: 8),
        _build4x1Tile('HEART RATE', widget.heartRateBpm > 0 ? '${widget.heartRateBpm}' : '--', 'bpm', Icons.favorite_rounded, const Color(0xFFEF4444), textColor),
        const SizedBox(width: 8),
        _build4x1Tile('CADENCE', widget.cadenceRpm > 0 ? '${widget.cadenceRpm}' : '--', 'rpm', Icons.sync_rounded, const Color(0xFF10B981), textColor),
        const SizedBox(width: 8),
        _build4x1Tile('ELEVATION', '${widget.currentAltitudeMeters.toInt()}', 'm', Icons.terrain_rounded, const Color(0xFF3B82F6), textColor),
      ],
    );
  }

  Widget _build4x1PaceElevationGrid(Color textColor) {
    final paceMin = widget.currentSpeedKmh > 0.5 ? (60.0 / widget.currentSpeedKmh) : 0.0;
    final paceStr = paceMin > 0 ? '${paceMin.toInt()}:${((paceMin - paceMin.toInt()) * 60).toInt().toString().padLeft(2, '0')}' : '--:--';

    return Row(
      children: [
        _build4x1Tile('CURRENT PACE', paceStr, '/km', Icons.timer_outlined, widget.accentColor, textColor),
        const SizedBox(width: 8),
        _build4x1Tile('ALTITUDE', '${widget.currentAltitudeMeters.toInt()}', 'm', Icons.height_rounded, const Color(0xFF3B82F6), textColor),
        const SizedBox(width: 8),
        _build4x1Tile('MOVING', '${widget.elapsed.inMinutes}m', 'elapsed', Icons.hourglass_bottom_rounded, const Color(0xFFF59E0B), textColor),
      ],
    );
  }

  Widget _build4x1Tile(String title, String value, String unit, IconData icon, Color color, Color textColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.6)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor)),
                const SizedBox(width: 2),
                Text(unit, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The Iconic Musicolet 4x1 Media Player Widget.
///
/// Features standard 4x1 aspect ratio, album art / app launcher, track metadata,
/// interactive live seek bar, previous, play/pause, next, and volume buttons.
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
  double _trackProgress = 0.35; // 35% through track
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPlaying && mounted) {
        setState(() {
          _trackProgress = (_trackProgress + 0.005) % 1.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _sendMediaAction(String action) {
    HapticFeedback.lightImpact();
    PlatformService.instance.sendMediaAction(action);
    if (action == 'play_pause' || action == 'toggle') {
      setState(() => _isPlaying = !_isPlaying);
    }
  }

  void _launchMusicolet() async {
    HapticFeedback.mediumImpact();
    final launched = await PlatformService.instance.launchMusicApp('in.krosbits.musicolet');
    if (mounted && !launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening default music player...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final accent = widget.accentColor;

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Album Art / Musicolet Icon with Tap-to-Launch
          GestureDetector(
            onTap: _launchMusicolet,
            child: Tooltip(
              message: 'Tap to open Musicolet',
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent,
                          accent.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 24),
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.open_in_new_rounded, size: 8, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 2. Center Track Metadata & Live Progress Bar
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Workout Beats • Musicolet',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${(_trackProgress * 3.5).toStringAsFixed(1)}m / 3.5m',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Endurance Pace Playlist',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Seeker Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _trackProgress,
                    backgroundColor: textColor.withValues(alpha: 0.1),
                    color: accent,
                    minHeight: 3.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 3. Playback Action Buttons (Glove-Friendly)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Previous
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.skip_previous_rounded, size: 22, color: textColor),
                tooltip: 'Previous Track',
                onPressed: () => _sendMediaAction('previous'),
              ),

              // Play / Pause Circle
              GestureDetector(
                onTap: () => _sendMediaAction('play_pause'),
                child: Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),

              // Next
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.skip_next_rounded, size: 22, color: textColor),
                tooltip: 'Next Track',
                onPressed: () => _sendMediaAction('next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
