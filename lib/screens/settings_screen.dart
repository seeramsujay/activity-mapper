import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/backup_service.dart';
import '../services/ble_sensor_service.dart';
import '../services/db_service.dart';
import '../services/platform_service.dart';
import '../services/tile_cache_service.dart';
import 'offline_maps_screen.dart';

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

  int _cachedTileCount = 0;
  int _cachedTileBytes = 0;
  bool _isDownloadingTiles = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  @override
  void initState() {
    super.initState();
    _loadDbStats();
    _loadTileCacheStats();
  }

  Future<void> _loadTileCacheStats() async {
    final metrics = await TileCacheService.instance.getCacheMetrics();
    if (mounted) {
      setState(() {
        _cachedTileCount = metrics['count'] ?? 0;
        _cachedTileBytes = metrics['sizeBytes'] ?? 0;
      });
    }
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
    final textColor = theme.colorScheme.onSurface;
    final cardBg = theme.cardColor;
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
                _buildSectionHeader('DISPLAY & THEMES', Icons.palette_outlined, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.12), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('THEME PREFERENCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      _buildThemeOption(
                        title: 'Light Mode',
                        subtitle: 'Clean daylight layout with maximum daylight visibility',
                        mode: AppThemeMode.light,
                        icon: Icons.light_mode_rounded,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildThemeOption(
                        title: 'Dark Mode',
                        subtitle: 'High contrast dark palette engineered for endurance athletes',
                        mode: AppThemeMode.dark,
                        icon: Icons.dark_mode_rounded,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildThemeOption(
                        title: 'System Automatic',
                        subtitle: 'Synchronize automatically with Android OS light/dark schedule',
                        mode: AppThemeMode.system,
                        icon: Icons.brightness_auto_rounded,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),

                      const SizedBox(height: 16),
                      const Divider(height: 16),
                      _buildSwitchRow(
                        title: 'OLED Display Mode (True Pitch Black)',
                        subtitle: 'Enables pure #000000 black canvas for zero pixel emission and activates OLED battery saving dimming.',
                        value: _settings.isOled,
                        onChanged: (v) => _settings.setOledMode(v),
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

                      const SizedBox(height: 20),
                      Text('MEASUREMENT UNITS & COORDINATES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      _buildToggleRow(
                        title: 'Coordinate Format',
                        subtitle: _settings.coordFormat == CoordFormat.decimal ? 'Decimal Degrees (e.g. 12.9716° N, 77.5946° E)' : 'DMS (e.g. 12°58\'17"N, 77°35\'40"E)',
                        trailing: DropdownButton<CoordFormat>(
                          value: _settings.coordFormat,
                          dropdownColor: cardBg,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: CoordFormat.decimal, child: Text('Decimal (°)')),
                            DropdownMenuItem(value: CoordFormat.dms, child: Text('DMS (° \' ")')),
                          ],
                          onChanged: (val) {
                            if (val != null) _settings.setCoordFormat(val);
                          },
                        ),
                        textColor: textColor,
                      ),
                      const Divider(height: 16),
                      _buildToggleRow(
                        title: 'Default X-Axis for Charts',
                        subtitle: _settings.chartXAxis == ChartXAxis.distance ? 'Distance (Kilometers)' : 'Duration (Seconds / Minutes)',
                        trailing: DropdownButton<ChartXAxis>(
                          value: _settings.chartXAxis,
                          dropdownColor: cardBg,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: ChartXAxis.distance, child: Text('Distance')),
                            DropdownMenuItem(value: ChartXAxis.duration, child: Text('Duration')),
                          ],
                          onChanged: (val) {
                            if (val != null) _settings.setChartXAxis(val);
                          },
                        ),
                        textColor: textColor,
                      ),
                      const Divider(height: 16),
                      _buildSwitchRow(
                        title: 'Imperial Units (Miles / Feet)',
                        subtitle: _settings.useImperialUnits ? 'Miles, Feet, mph' : 'Kilometers, Meters, km/h',
                        value: _settings.useImperialUnits,
                        onChanged: (v) => _settings.setUseImperialUnits(v),
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 2. RECORDING PROFILES & GPS (Geo Tracker Inspired)
                _buildSectionHeader('RECORD PROFILE & GPS', Icons.gps_fixed, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.12), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RECORD PROFILE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: textColor.withValues(alpha: 0.15)),
                        ),
                        child: DropdownButton<RecordProfile>(
                          value: _settings.recordProfile,
                          isExpanded: true,
                          dropdownColor: cardBg,
                          underline: const SizedBox(),
                          items: RecordProfile.values.map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Text(
                                '${p.label} (${p.intervalMs ~/ 1000}s, ${p.minDistanceMeters.toInt()}m min dist)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor),
                              ),
                            );
                          }).toList(),
                          onChanged: (p) {
                            if (p != null) _settings.setRecordProfile(p);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      Text('GPS PARAMETERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      _buildToggleRow(
                        title: 'Record Frequency',
                        subtitle: 'GPS update interval',
                        trailing: DropdownButton<int>(
                          value: _settings.gpsSamplingRateMs,
                          dropdownColor: cardBg,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 1000, child: Text('1 sec')),
                            DropdownMenuItem(value: 2000, child: Text('2 sec')),
                            DropdownMenuItem(value: 5000, child: Text('5 sec')),
                            DropdownMenuItem(value: 15000, child: Text('15 sec')),
                          ],
                          onChanged: (val) {
                            if (val != null) _settings.setGpsSamplingRate(val);
                          },
                        ),
                        textColor: textColor,
                      ),
                      const Divider(height: 16),
                      _buildToggleRow(
                        title: 'Min Distance between points',
                        subtitle: 'Filters stationary jitter',
                        trailing: DropdownButton<double>(
                          value: _settings.minDistanceFilter,
                          dropdownColor: cardBg,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 5.0, child: Text('5 m')),
                            DropdownMenuItem(value: 10.0, child: Text('10 m')),
                            DropdownMenuItem(value: 20.0, child: Text('20 m')),
                            DropdownMenuItem(value: 50.0, child: Text('50 m')),
                          ],
                          onChanged: (val) {
                            if (val != null) _settings.setMinDistanceFilter(val);
                          },
                        ),
                        textColor: textColor,
                      ),
                      const Divider(height: 16),
                      _buildToggleRow(
                        title: 'Max GPS Accuracy Tolerance',
                        subtitle: 'Discard points worse than accuracy threshold',
                        trailing: DropdownButton<double>(
                          value: _settings.maxAccuracyFilter,
                          dropdownColor: cardBg,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 25.0, child: Text('25 m')),
                            DropdownMenuItem(value: 50.0, child: Text('50 m')),
                            DropdownMenuItem(value: 100.0, child: Text('100 m')),
                          ],
                          onChanged: (val) {
                            if (val != null) _settings.setMaxAccuracyFilter(val);
                          },
                        ),
                        textColor: textColor,
                      ),
                      const Divider(height: 16),
                      _buildSwitchRow(
                        title: 'Extra Kalman & RDP Filtering',
                        subtitle: 'Smoothes speed spikes and noisy GPS drift',
                        value: _settings.extraFiltering,
                        onChanged: (v) => _settings.setExtraFiltering(v),
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const Divider(height: 16),
                      _buildSwitchRow(
                        title: 'Stop Recording with Confirmation',
                        subtitle: 'Ask for confirmation before finishing track',
                        value: _settings.confirmStopRecording,
                        onChanged: (v) => _settings.setConfirmStopRecording(v),
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 3. OFFLINE MAP & OSM ASSETS
                _buildSectionHeader('MAP TILES & OFFLINE CACHE', Icons.map_outlined, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.12), width: 1.2),
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
                        title: 'Google Maps (Vector / Roadmap)',
                        url: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                        icon: Icons.map,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildMapTileOption(
                        title: 'Google Maps (Satellite & Hybrid)',
                        url: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                        icon: Icons.satellite_alt_rounded,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildMapTileOption(
                        title: 'Google Maps (Terrain / Elevation)',
                        url: 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}',
                        icon: Icons.terrain,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildMapTileOption(
                        title: 'OpenTopoMap (Topographic)',
                        url: 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
                        icon: Icons.filter_hdr_rounded,
                        textColor: textColor,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 8),
                      _buildMapTileOption(
                        title: 'Humanitarian OSM (HOT)',
                        url: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                        icon: Icons.explore_outlined,
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
                      const SizedBox(height: 16),

                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('OFFLINE MAPS DOWNLOAD (GOOGLE MAPS STYLE)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                          Text('$_cachedTileCount tiles (${(_cachedTileBytes / (1024 * 1024)).toStringAsFixed(1)} MB)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Download and manage custom offline map regions for 100% offline navigation in the backcountry without data or GPS lag.',
                        style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.7), height: 1.4),
                      ),
                      const SizedBox(height: 14),

                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const OfflineMapsScreen()),
                          ).then((_) => _loadTileCacheStats());
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.download_for_offline_rounded, color: accentColor, size: 22),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Manage & Download Offline Maps', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textColor)),
                                      Text('Select custom areas, view packs & manage storage', style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.6))),
                                    ],
                                  ),
                                ],
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: accentColor),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 4. MUSIC & MEDIA CONTROLLER INTEGRATION
                _buildSectionHeader('MUSIC & MEDIA INTEGRATION', Icons.headphones_rounded, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.12), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('IN-HUD & AUTOMATION CONTROLS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show In-HUD Media Controller', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
                        subtitle: Text('Glove-friendly overlay for play/pause, skip, prev, and volume controls during workouts.', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6))),
                        value: _settings.showHudMediaController,
                        activeColor: accentColor,
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          _settings.setShowHudMediaController(val);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Auto-Pause Music on Cycling Turn-Back', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
                        subtitle: Text('Automatically pauses Musicolet / active audio player and sounds an audible chime when turnaround is reached while cycling.', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6))),
                        value: _settings.autoPauseCyclingMusic,
                        activeColor: accentColor,
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          _settings.setAutoPauseCyclingMusic(val);
                        },
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cardBg,
                          foregroundColor: textColor,
                          side: BorderSide(color: textColor.withValues(alpha: 0.15)),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          final launched = await PlatformService.instance.launchMusicApp();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(launched ? 'Opened Music Player' : 'Could not find music player')),
                            );
                          }
                        },
                        icon: Icon(Icons.open_in_new_rounded, size: 16, color: accentColor),
                        label: const Text('LAUNCH MUSIC PLAYER (MUSICOLET / SYSTEM)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 5. BLE SENSORS & WEARABLES
                _buildSectionHeader('BLE SENSORS & WEARABLES', Icons.bluetooth_searching, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.12), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('BLUETOOTH SMART SENSORS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: BleSensorService.instance.isConnected ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              BleSensorService.instance.isConnected ? 'CONNECTED' : 'DISCONNECTED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: BleSensorService.instance.isConnected ? const Color(0xFF10B981) : textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Connect standard Heart Rate Straps (0x180D) and Cycling Cadence / Speed meters (0x1816) for real-time in-HUD telemetry.',
                        style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.7), height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: BleSensorService.instance.isConnected ? const Color(0xFFDC2626) : accentColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  if (BleSensorService.instance.isConnected) {
                                    BleSensorService.instance.disconnect();
                                  } else {
                                    BleSensorService.instance.startSimulation();
                                  }
                                });
                              },
                              icon: Icon(BleSensorService.instance.isConnected ? Icons.bluetooth_disabled : Icons.bluetooth_connected, size: 18),
                              label: Text(
                                BleSensorService.instance.isConnected ? 'DISCONNECT SENSORS' : 'PAIR / SIMULATE SENSOR',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                              ),
                            ),
                          ),
                        ],
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
                    border: Border.all(color: textColor.withValues(alpha: 0.12), width: 1.2),
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

                // 4. DATABASE & STORAGE MANAGEMENT
                _buildSectionHeader('DATABASE & DATA STORAGE', Icons.storage_rounded, textColor),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: textColor.withValues(alpha: 0.12), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LOCAL STORAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      Text(
                        'All your workout tracks and telemetry points are stored offline locally in an SQLite database on your device.',
                        style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.delete_forever_rounded, size: 20),
                          label: const Text('RESET DATABASE / ERASE ALL DATA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.6)),
                          onPressed: () => _confirmResetDatabase(context, textColor, cardBg),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmResetDatabase(BuildContext context, Color textColor, Color cardBg) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
              SizedBox(width: 8),
              Text('Reset Database?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFDC2626))),
            ],
          ),
          content: Text(
            'This will permanently delete all recorded workouts, GPS telemetry points, and history from your local SQLite database.\n\nThis action cannot be undone.',
            style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CANCEL', style: TextStyle(color: textColor.withValues(alpha: 0.6), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await PlatformService.instance.stopTracking();
                await DbService.instance.clearAllData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('DATABASE RESET: All sessions and points cleared.'),
                      backgroundColor: Color(0xFFDC2626),
                    ),
                  );
                }
              },
              child: const Text('ERASE EVERYTHING', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
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

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required Widget trailing,
    required Color textColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textColor)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6))),
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color textColor,
    required Color accentColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textColor)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6))),
            ],
          ),
        ),
        Switch(
          value: value,
          activeTrackColor: accentColor,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            onChanged(v);
          },
        ),
      ],
    );
  }

  void _showDownloadRegionDialog() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF242933) : const Color(0xFFE5E7EB);
    final accentColor = SettingsService.instance.accentColor.color;

    double selectedRadiusKm = 5.0;
    final nameController = TextEditingController(text: 'My Workout Area');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final metrics = TileCacheService.estimateAreaMetrics(selectedRadiusKm, const [13, 14, 15, 16]);
            final estimatedTiles = metrics['tileCount'] as int;
            final estimatedMb = (metrics['estimatedMb'] as double).toStringAsFixed(1);

            return Padding(
              padding: EdgeInsets.only(
                left: 20.0,
                right: 20.0,
                top: 20.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.offline_pin_rounded, color: accentColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DOWNLOAD OFFLINE MAP',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.8),
                            ),
                            Text(
                              'Google Maps-style full offline navigation',
                              style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Area Name Field
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'AREA NAME',
                      labelStyle: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.bold),
                      prefixIcon: Icon(Icons.label_outline, color: accentColor, size: 18),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E232B) : const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accentColor, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Radius Slider & Metrics Preview Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'DOWNLOAD RADIUS: ${selectedRadiusKm.toInt()} KM',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: accentColor),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '~$estimatedTiles TILES • ~$estimatedMb MB',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: accentColor),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: selectedRadiusKm,
                          min: 2.0,
                          max: 20.0,
                          divisions: 18,
                          activeColor: accentColor,
                          label: '${selectedRadiusKm.toInt()} km (~$estimatedMb MB)',
                          onChanged: (val) => setModalState(() => selectedRadiusKm = val),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('2 km (Quick Trail)', style: TextStyle(fontSize: 9.5, color: textColor.withValues(alpha: 0.5))),
                            Text('10 km (City/Park)', style: TextStyle(fontSize: 9.5, color: textColor.withValues(alpha: 0.5))),
                            Text('20 km (Region)', style: TextStyle(fontSize: 9.5, color: textColor.withValues(alpha: 0.5))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() {
                        _isDownloadingTiles = true;
                        _downloadProgress = 0.0;
                        _downloadStatus = 'Preparing offline map download...';
                      });

                      // Default to latest known track coordinates or city center
                      double centerLat = 37.7749;
                      double centerLng = -122.4194;

                      final latestSession = await DbService.instance.getCompletedSessions();
                      if (latestSession.isNotEmpty) {
                        final points = await DbService.instance.getPoints(latestSession.first['id'] as int);
                        if (points.isNotEmpty) {
                          centerLat = points.last['lat'] as double;
                          centerLng = points.last['lng'] as double;
                        }
                      }

                      final stream = TileCacheService.instance.downloadOfflineRegion(
                        centerLat: centerLat,
                        centerLng: centerLng,
                        radiusKm: selectedRadiusKm,
                        zoomLevels: const [13, 14, 15, 16],
                        tileUrlTemplate: SettingsService.instance.mapTileSource,
                      );

                      await for (final progress in stream) {
                        if (mounted) {
                          setState(() {
                            _downloadProgress = progress.progressRatio;
                            _downloadStatus = progress.status;
                            if (progress.isDone) {
                              _isDownloadingTiles = false;
                            }
                          });
                        }
                      }

                      await _loadTileCacheStats();
                    },
                    icon: const Icon(Icons.cloud_download_rounded, size: 20),
                    label: const Text('DOWNLOAD OFFLINE MAP', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

