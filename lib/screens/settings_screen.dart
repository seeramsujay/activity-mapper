import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';

/// Comprehensive application settings, themes, and map customization screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;
  bool _isBackingUp = false;
  int _pointCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDbStats();
  }

  Future<void> _loadDbStats() async {
    final sessions = await DbService.instance.getCompletedSessions();
    int count = 0;
    for (final s in sessions) {
      final points = await DbService.instance.getPoints(s['id'] as int);
      count += points.length;
    }
    if (mounted) setState(() => _pointCount = count);
  }

  Future<void> _triggerBackup() async {
    setState(() => _isBackingUp = true);
    HapticFeedback.mediumImpact();
    try {
      final zip = await BackupService.instance.createZipBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup archive created:\n${zip.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final cardBg = theme.colorScheme.surface;
    final accentColor = _settings.accentColor.color;

    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('SETTINGS & PREFERENCES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              children: [
                // 1. DISPLAY THEMES & NIGHT MODE
                _buildSectionHeader('DISPLAY & NIGHT MODE', Icons.palette_outlined, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.1), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('THEME STYLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      _buildThemeOption(
                        title: 'Soft Night Mode (Recommended)',
                        subtitle: 'Warm, low-contrast slate (#0E1318) - easier on the eyes',
                        mode: AppThemeMode.softNight,
                        icon: Icons.nightlight_round,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildThemeOption(
                        title: 'High Contrast OLED',
                        subtitle: 'True deep black (#000000) with neon markers',
                        mode: AppThemeMode.highContrast,
                        icon: Icons.contrast,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildThemeOption(
                        title: 'Daylight Bright',
                        subtitle: 'Clean white background for direct sunlight visibility',
                        mode: AppThemeMode.light,
                        icon: Icons.wb_sunny_outlined,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildThemeOption(
                        title: 'System Automatic',
                        subtitle: 'Follow device day/night schedule',
                        mode: AppThemeMode.system,
                        icon: Icons.brightness_auto,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),

                      const SizedBox(height: 20),
                      Text('ACCENT COLOR PALETTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: AccentColorChoice.values.map((choice) {
                          final selected = _settings.accentColor == choice;
                          return ChoiceChip(
                            avatar: CircleAvatar(backgroundColor: choice.color, radius: 8),
                            label: Text(
                              choice.displayName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: selected ? Colors.white : textColor,
                              ),
                            ),
                            selected: selected,
                            selectedColor: choice.color,
                            backgroundColor: cardBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: selected ? choice.color : textColor.withValues(alpha: 0.15)),
                            ),
                            showCheckmark: false,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              _settings.setAccentColor(choice);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 2. OFFLINE MAP & OSM ASSETS
                _buildSectionHeader('MAP ASSETS & CACHE', Icons.map_outlined, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.1), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ONLINE / OFFLINE TILE SOURCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      _buildMapTileOption(
                        title: 'Standard OpenStreetMap',
                        url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        icon: Icons.public,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildMapTileOption(
                        title: 'Humanitarian / Topo (HOT)',
                        url: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                        icon: Icons.terrain,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildMapTileOption(
                        title: 'CartoDB Dark Matter (Night Maps)',
                        url: 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                        icon: Icons.dark_mode_outlined,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 3. GPS ACCURACY & POWER PROFILES
                _buildSectionHeader('GPS & PERFORMANCE', Icons.gps_fixed, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.1), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SAMPLING RATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      _buildGpsOption(
                        title: '1s - High Precision Track',
                        subtitle: 'Best for running and cycling turn-back precision',
                        ms: 1000,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildGpsOption(
                        title: '5s - Balanced Outdoor Mode',
                        subtitle: 'Recommended for longer trail activities',
                        ms: 5000,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildGpsOption(
                        title: '15s - Ultra Battery Saver',
                        subtitle: 'Extends battery life for full-day hikes',
                        ms: 15000,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 4. BACKUP & DATABASE MANAGEMENT
                _buildSectionHeader('DATABASE & ARCHIVE', Icons.inventory_2_outlined, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.1), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('SQLITE DATABASE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                          Text('$_pointCount points logged', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'TurnBack writes all raw GPS points, speed, and elevation locally with SQLite WAL. You can export complete zip backups containing the DB and GPX logs anytime.',
                        style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.7), height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _isBackingUp ? null : _triggerBackup,
                        icon: _isBackingUp
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.archive_outlined, size: 20),
                        label: Text(
                          _isBackingUp ? 'GENERATING ARCHIVE...' : 'EXPORT LIFETIME BACKUP (.ZIP)',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 5. ARCHITECTURE & SIZE FOOTPRINT EXPLAINED
                _buildSectionHeader('BUILD FOOTPRINT & PERFORMANCE', Icons.memory, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF13181F) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFF3B82F6), size: 18),
                          SizedBox(width: 8),
                          Text('Why Debug APK was 157 MB vs Release', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF3B82F6))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'During development (`flutter run`), the app bundles all 4 CPU architectures (arm64-v8a, armeabi-v7a, x86_64, x86), unstripped debug symbols, Impeller shader profilers, and the Dart JIT VM. \n\nA production release APK built with `--release --split-per-abi` drops down to ~14–18 MB with zero unneeded overhead.',
                        style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.8), height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 10.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: textColor.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.6), letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required String title,
    required String subtitle,
    required AppThemeMode mode,
    required IconData icon,
    required Color textColor,
    required Color accentColor,
  }) {
    final isSelected = _settings.themeMode == mode;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _settings.setThemeMode(mode);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? accentColor : textColor.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? accentColor : textColor.withValues(alpha: 0.5), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6))),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMapTileOption({
    required String title,
    required String url,
    required IconData icon,
    required Color textColor,
    required Color accentColor,
  }) {
    final isSelected = _settings.mapTileSource == url;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _settings.setMapTileSource(url);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? accentColor : textColor.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? accentColor : textColor.withValues(alpha: 0.5), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textColor)),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsOption({
    required String title,
    required String subtitle,
    required int ms,
    required Color textColor,
    required Color accentColor,
  }) {
    final isSelected = _settings.gpsSamplingRateMs == ms;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _settings.setGpsSamplingRate(ms);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? accentColor : textColor.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(Icons.radar, color: isSelected ? accentColor : textColor.withValues(alpha: 0.5), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6))),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
          ],
        ),
      ),
    );
  }
}
