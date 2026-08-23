import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/platform_service.dart';

/// Compact, glove-friendly in-HUD media controller for active workouts.
///
/// Dispatches native Android `KeyEvent` actions to active media players (Spotify, Musicolet, etc.)
/// and allows one-tap opening of Musicolet or default media player.
class HudMediaController extends StatefulWidget {
  final Brightness brightness;
  final Color accentColor;

  const HudMediaController({
    super.key,
    required this.brightness,
    required this.accentColor,
  });

  @override
  State<HudMediaController> createState() => _HudMediaControllerState();
}

class _HudMediaControllerState extends State<HudMediaController> {
  bool _isPlaying = true;
  bool _isExpanded = false;

  void _handleAction(String action) {
    HapticFeedback.lightImpact();
    PlatformService.instance.sendMediaAction(action);
    if (action == 'play_pause' || action == 'toggle') {
      setState(() => _isPlaying = !_isPlaying);
    }
  }

  void _openMusicApp() async {
    HapticFeedback.mediumImpact();
    final launched = await PlatformService.instance.launchMusicApp();
    if (mounted && !launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active music player found')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE5E7EB);

    return Container(
      decoration: BoxDecoration(
        color: cardBg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Music icon / Toggle expander (Long press opens Musicolet/Music app)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isExpanded = !_isExpanded);
            },
            onLongPress: _openMusicApp,
            child: Tooltip(
              message: 'Tap: expand, Long-press: open Musicolet',
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isExpanded ? Icons.music_note : Icons.headphones_rounded,
                  size: 16,
                  color: widget.accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Previous Track
          _buildButton(
            icon: Icons.skip_previous_rounded,
            onTap: () => _handleAction('previous'),
            textColor: textColor,
            tooltip: 'Previous track',
          ),

          // Play / Pause
          _buildButton(
            icon: _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
            iconSize: 28,
            color: widget.accentColor,
            onTap: () => _handleAction('play_pause'),
            textColor: widget.accentColor,
            tooltip: _isPlaying ? 'Pause' : 'Play',
          ),

          // Next Track
          _buildButton(
            icon: Icons.skip_next_rounded,
            onTap: () => _handleAction('next'),
            textColor: textColor,
            tooltip: 'Next track',
          ),

          if (_isExpanded) ...[
            Container(
              height: 20,
              width: 1,
              color: borderColor,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // Volume Down
            _buildButton(
              icon: Icons.volume_down_rounded,
              onTap: () => _handleAction('volume_down'),
              textColor: textColor.withValues(alpha: 0.7),
              tooltip: 'Volume down',
            ),
            // Volume Up
            _buildButton(
              icon: Icons.volume_up_rounded,
              onTap: () => _handleAction('volume_up'),
              textColor: textColor.withValues(alpha: 0.7),
              tooltip: 'Volume up',
            ),
            // Open App Button
            _buildButton(
              icon: Icons.open_in_new_rounded,
              onTap: _openMusicApp,
              iconSize: 16,
              textColor: widget.accentColor,
              tooltip: 'Open Musicolet/Music app',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color textColor,
    double iconSize = 20,
    Color? color,
    String? tooltip,
  }) {
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(icon, size: iconSize, color: color ?? textColor),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }
}

