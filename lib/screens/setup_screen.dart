import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/db_service.dart';
import '../services/platform_service.dart';
import '../services/gpx_service.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../services/p2p_mesh_service.dart';
import '../widgets/breadcrumb_painter.dart';
import '../widgets/mesh_qr_widget.dart';
import 'editor_screen.dart';
import 'hud_screen.dart';

/// The onboarding, settings, and main dashboard screen of the application.
///
/// Functions:
/// - Displays lifetime tracking summaries (activities, distances, times).
/// - Exposes backup export controls (ZIP backup files).
/// - Offers session launchers via sliding widgets to configure activity parameters.
/// - Shows active session notifications and progress bars if tracking is running in the background.
class SetupScreen extends StatefulWidget {
  final bool isOfflineOnly;

  /// Creates a new [SetupScreen] instance.
  const SetupScreen({super.key, this.isOfflineOnly = false});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

/// State controller for the [SetupScreen], managing lifetime analytics.
class _SetupScreenState extends State<SetupScreen> {

  bool get isColab => !widget.isOfflineOnly && PlatformService.isColabMode;

  // Lifetime stats
  List<Map<String, dynamic>> _completedSessions = [];
  double _lifetimeDistance = 0.0;
  Duration _lifetimeDuration = Duration.zero;
  bool _isLoading = true;
  String _autoSyncPath = "Documents/TurnBack";

  // Active session tracking state (for home-screen return timer widget)
  Map<String, dynamic>? _activeSession;
  Duration _activeElapsed = Duration.zero;
  double _activeDistanceKm = 0.0;
  bool _activeTurnBackTriggered = false;
  Timer? _activeTimer;
  StreamSubscription? _activeTelemetrySub;

  // New tracking parameters (state held for bottom sheet)
  String _activityType = 'run';
  int _targetDurationMinutes = 90;
  double _safetyBufferPct = 8.0;
  int _gpsIntervalMs = 5000;
  int? _selectedReferenceSessionId;
  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _activeTimer?.cancel();
    _activeTelemetrySub?.cancel();
    super.dispose();
  }

  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const pVal = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * pVal) / 2 +
          cos(lat1 * pVal) * cos(lat2 * pVal) *
          (1 - cos((lon2 - lon1) * pVal)) / 2;
    return 12742 * asin(sqrt(a)); // Haversine formula (km)
  }

  Future<void> _loadDashboardData() async {
    final dbHelper = DbService.instance;
    
    // Check if there is an active session
    final active = await dbHelper.getActiveSession();
    if (active != null) {
      _startActiveTrackingTimer(active);
    } else {
      _activeTimer?.cancel();
      _activeTelemetrySub?.cancel();
      _activeSession = null;
    }

    final sessions = await dbHelper.getSessions();
    final completed = sessions.where((s) => s['status'] == 'completed').toList();

    double totalDist = 0.0;
    int totalTimeMs = 0;

    for (final s in completed) {
      final points = await dbHelper.getPoints(s['id'] as int);
      double sDist = 0.0;
      for (int i = 1; i < points.length; i++) {
        sDist += _distanceBetween(
          points[i-1]['lat'] as double,
          points[i-1]['lng'] as double,
          points[i]['lat'] as double,
          points[i]['lng'] as double,
        );
      }
      totalDist += sDist;

      final start = s['start_time'] as int;
      final end = s['end_time'] as int?;
      if (end != null) {
        totalTimeMs += (end - start);
      }
    }

    // Resolve public TurnBack folder for UI sync label
    String resolvedPath = "Documents/TurnBack";
    if (Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final rootPath = extDir.path.split('/Android/data/')[0];
          resolvedPath = p.join(rootPath, 'Documents', 'TurnBack');
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _completedSessions = completed;
        _lifetimeDistance = totalDist;
        _lifetimeDuration = Duration(milliseconds: totalTimeMs);
        _autoSyncPath = resolvedPath;
        _isLoading = false;
      });
    }
  }

  void _startActiveTrackingTimer(Map<String, dynamic> session) async {
    _activeTimer?.cancel();
    _activeTelemetrySub?.cancel();

    _activeSession = session;
    _activeTurnBackTriggered = session['turn_back_triggered_at'] != null;

    final dbHelper = DbService.instance;
    final points = await dbHelper.getPoints(session['id'] as int);
    
    double dist = 0.0;
    int activeMs = 0;
    for (int i = 1; i < points.length; i++) {
      dist += _distanceBetween(
        points[i-1]['lat'] as double,
        points[i-1]['lng'] as double,
        points[i]['lat'] as double,
        points[i]['lng'] as double,
      );
      final int diff = (points[i]['timestamp'] as num).toInt() - (points[i-1]['timestamp'] as num).toInt();
      final double spd = (points[i]['speed'] as num?)?.toDouble() ?? 0.0;
      if (diff > 0 && diff < 15000 && spd > 0.2) {
        activeMs += diff;
      }
    }

    _activeDistanceKm = dist;
    _activeElapsed = Duration(milliseconds: activeMs);

    _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeSession == null || _activeSession!['status'] == 'paused') return;

      setState(() {
        _activeElapsed += const Duration(seconds: 1);
        
        final double outboundRatio = (100.0 - (_activeSession!['safety_buffer'] as double)) / 200.0;
        final int outboundLimitSeconds = ((_activeSession!['target_duration'] as int) * outboundRatio).toInt();

        if (_activeElapsed.inSeconds >= outboundLimitSeconds && !_activeTurnBackTriggered) {
          _activeTurnBackTriggered = true;
          dbHelper.markTurnBackTriggered(_activeSession!['id'] as int);
        }
      });
    });

    _activeTelemetrySub = PlatformService.instance.telemetryStream.listen((event) {
      if (_activeSession == null || _activeSession!['status'] == 'paused') return;
      
      final double lat = ((event['lat'] ?? 0.0) as num).toDouble();
      final double lng = ((event['lng'] ?? 0.0) as num).toDouble();

      setState(() {
        if (points.isNotEmpty) {
          final lastPoint = points.last;
          _activeDistanceKm += _distanceBetween(lastPoint['lat'] as double, lastPoint['lng'] as double, lat, lng);
        }
      });
    });
  }

  void _toggleActivePause(int sessionId, String activityType, int targetSec, double buffer) async {
    final dbHelper = DbService.instance;
    final status = _activeSession!['status'] as String;
    final isPaused = status == 'paused';

    if (!isPaused) {
      await dbHelper.updateSessionStatus(sessionId, 'paused');
      await PlatformService.instance.stopTracking();
    } else {
      await dbHelper.updateSessionStatus(sessionId, 'active');
      await PlatformService.instance.startTracking(
        sessionId: sessionId,
        activityType: activityType.toLowerCase(),
        targetDurationSeconds: targetSec,
        safetyBufferPct: buffer,
        gpsIntervalMs: 5000,
      );
    }
    _loadDashboardData();
  }

  void _confirmStopActiveSession(int sessionId, String activityType) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final color = isDark ? Colors.white : Colors.black;
        return AlertDialog(
          backgroundColor: isDark ? Colors.black : Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text('Finish Session?', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          content: Text('This will stop GPS tracking and export your GPX activity file.', style: TextStyle(color: color)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: isDark ? Colors.black : Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () {
                Navigator.pop(context);
                _finishActiveSession(sessionId, activityType);
              },
              child: const Text('STOP & SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _finishActiveSession(int sessionId, String activityType) async {
    await PlatformService.instance.stopTracking();
    await DbService.instance.updateSessionStatus(sessionId, 'completed');
    final activityName = '${activityType.toUpperCase()} - Out and Back';
    final file = await GpxService.instance.saveGpxFile(sessionId, activityName);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPX saved to TurnBack folder:\n${file.path}'), duration: const Duration(seconds: 4)),
      );
    }
    _loadDashboardData();
  }

  void _confirmDelete(int sessionId) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final color = isDark ? Colors.white : Colors.black;
        return AlertDialog(
          backgroundColor: isDark ? Colors.black : Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text('Delete Session?', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          content: Text('This will delete this activity session and all its coordinate data permanently.', style: TextStyle(color: color)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await DbService.instance.deleteSession(sessionId);
                _loadDashboardData();
              },
              child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editActivity(int sessionId, String type) async {
    final bool? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditorScreen(sessionId: sessionId, activityType: type),
      ),
    );
    if (result == true) {
      _loadDashboardData();
    }
  }

  Future<void> _runZipBackup() async {
    try {
      final zipFile = await BackupService.instance.createZipBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ZIP Backup saved successfully:\n${zipFile.path}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup compilation failed: $e')),
        );
      }
    }
  }

  void _showRecordBottomSheet(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final bool isDark = brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF111827);
    final Color cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final Color surfaceBg = isDark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6);
    final Color accentColor = const Color(0xFFFF5722);
    final Color borderColor = isDark ? const Color(0xFF2D333F) : const Color(0xFFE5E7EB);

    final durationController = TextEditingController(text: '$_targetDurationMinutes');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Live math preview
            final double outboundRatio = (100.0 - _safetyBufferPct) / 200.0;
            final double returnRatio = 1.0 - outboundRatio;
            final int totalSeconds = _targetDurationMinutes * 60;
            final int outboundSeconds = (totalSeconds * outboundRatio).toInt();
            final int returnSeconds = totalSeconds - outboundSeconds;
            final int safetyCushionSeconds = (returnSeconds - outboundSeconds).clamp(0, 3600 * 24);

            return Padding(
              padding: EdgeInsets.only(
                left: 20.0,
                right: 20.0,
                top: 20.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sheet Drag Handle
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'START TRACKING',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              'Out-and-Back Turn-Back Engine',
                              style: TextStyle(
                                fontSize: 12,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: textColor.withValues(alpha: 0.6)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Activity Selector Chips (Run, Ride, Walk, Hike, Free Run)
                    Text(
                      'ACTIVITY TYPE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.6), letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildActivityChip(
                            label: 'RUN',
                            icon: Icons.directions_run,
                            selected: _activityType == 'run',
                            onTap: () {
                              setModalState(() => _activityType = 'run');
                              setState(() => _activityType = 'run');
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildActivityChip(
                            label: 'RIDE',
                            icon: Icons.directions_bike,
                            selected: _activityType == 'ride',
                            onTap: () {
                              setModalState(() => _activityType = 'ride');
                              setState(() => _activityType = 'ride');
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildActivityChip(
                            label: 'WALK',
                            icon: Icons.directions_walk,
                            selected: _activityType == 'walk',
                            onTap: () {
                              setModalState(() => _activityType = 'walk');
                              setState(() => _activityType = 'walk');
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildActivityChip(
                            label: 'HIKE',
                            icon: Icons.hiking,
                            selected: _activityType == 'hike',
                            onTap: () {
                              setModalState(() => _activityType = 'hike');
                              setState(() => _activityType = 'hike');
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildActivityChip(
                            label: 'FREE RUN',
                            icon: Icons.bolt_rounded,
                            selected: _activityType == 'freerun',
                            onTap: () {
                              setModalState(() => _activityType = 'freerun');
                              setState(() => _activityType = 'freerun');
                            },
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (_activityType == 'freerun') ...[
                      // Free Run Dynamic Real-Time Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.2),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.auto_mode_rounded, color: accentColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'FREE RUN (REAL-TIME PREDICTION)',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Run as far and long as you want. The HUD will continuously calculate your predicted return time and finish ETA. When you tap "RETURN NOW", the return countdown begins.',
                                    style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.75), height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Target Duration with Type + Quick Presets + Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'TOTAL WORKOUT DURATION',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.6), letterSpacing: 0.8),
                          ),
                          // Numeric Direct Typing Field
                          Container(
                            width: 88,
                            height: 38,
                            decoration: BoxDecoration(
                              color: surfaceBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderColor),
                            ),
                            child: TextField(
                              controller: durationController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textColor),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                border: InputBorder.none,
                                suffixText: 'm',
                                suffixStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onChanged: (val) {
                                final parsed = int.tryParse(val);
                                if (parsed != null && parsed >= 5 && parsed <= 360) {
                                  setModalState(() => _targetDurationMinutes = parsed);
                                  setState(() => _targetDurationMinutes = parsed);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Quick duration chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [30, 45, 60, 90, 120, 150].map((mins) {
                            final isSelected = _targetDurationMinutes == mins;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text('${mins}m', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : textColor)),
                                selected: isSelected,
                                selectedColor: accentColor,
                                backgroundColor: surfaceBg,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? accentColor : borderColor)),
                                showCheckmark: false,
                                onSelected: (_) {
                                  durationController.text = '$mins';
                                  setModalState(() => _targetDurationMinutes = mins);
                                  setState(() => _targetDurationMinutes = mins);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Synced Slider
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 6,
                          activeTrackColor: accentColor,
                          inactiveTrackColor: textColor.withValues(alpha: 0.1),
                          thumbColor: accentColor,
                          overlayColor: accentColor.withValues(alpha: 0.2),
                        ),
                        child: Slider(
                          value: _targetDurationMinutes.clamp(10, 240).toDouble(),
                          min: 10,
                          max: 240,
                          divisions: 46,
                          onChanged: (val) {
                            final mins = val.toInt();
                            durationController.text = '$mins';
                            setModalState(() => _targetDurationMinutes = mins);
                            setState(() => _targetDurationMinutes = mins);
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Live Mathematical Breakdown Card
                    Container(
                      padding: const EdgeInsets.all(14.0),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('OUTBOUND RUN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5))),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${outboundSeconds ~/ 60}m ${outboundSeconds % 60}s',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF3B82F6)),
                                  ),
                                  Text('(${(outboundRatio * 100).toStringAsFixed(0)}% time)', style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.5))),
                                ],
                              ),
                              Icon(Icons.sync_alt, color: textColor.withValues(alpha: 0.3)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('RETURN ALLOWANCE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5))),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${returnSeconds ~/ 60}m ${returnSeconds % 60}s',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: accentColor),
                                  ),
                                  Text('+${safetyCushionSeconds ~/ 60}m buffer', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Fatigue Buffer Preset Selector
                    Text(
                      'FATIGUE SAFETY BUFFER',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.6), letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [0.0, 5.0, 8.0, 10.0, 15.0].map((buf) {
                          final isSelected = (_safetyBufferPct - buf).abs() < 0.1;
                          final isDefault = buf == 8.0;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(
                                '${buf.toInt()}%${isDefault ? ' (Default)' : ''}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : textColor),
                              ),
                              selected: isSelected,
                              selectedColor: const Color(0xFF10B981),
                              backgroundColor: surfaceBg,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? const Color(0xFF10B981) : borderColor)),
                              showCheckmark: false,
                              onSelected: (_) {
                                setModalState(() => _safetyBufferPct = buf);
                                setState(() => _safetyBufferPct = buf);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Reference Track Selector
                    if (_completedSessions.isNotEmpty) ...[
                      Text(
                        'PAST ROUTE TO FOLLOW (OPTIONAL)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.6), letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: surfaceBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: _selectedReferenceSessionId,
                            isExpanded: true,
                            dropdownColor: cardBg,
                            hint: Text('Free Run (No route)', style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.6))),
                            items: [
                              DropdownMenuItem<int?>(
                                value: null,
                                child: Text('None - Free Tracking', style: TextStyle(fontSize: 13, color: textColor)),
                              ),
                              ..._completedSessions.map((s) {
                                final date = DateTime.fromMillisecondsSinceEpoch(s['start_time'] as int);
                                final type = (s['activity_type'] as String).toUpperCase();
                                return DropdownMenuItem<int?>(
                                  value: s['id'] as int,
                                  child: Text('$type #${s['id']} (${date.month}/${date.day})', style: TextStyle(fontSize: 13, color: textColor)),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setModalState(() => _selectedReferenceSessionId = val);
                              setState(() => _selectedReferenceSessionId = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Launch Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: _isLaunching ? null : () => _launchSession(context, setModalState),
                      child: _isLaunching
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.play_arrow_rounded, size: 24),
                                SizedBox(width: 8),
                                Text(
                                  'START RECORDING',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActivityChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final Color selectedColor = const Color(0xFFFF5722);
    final Color borderColor = isDark ? const Color(0xFF2D333F) : const Color(0xFFE5E7EB);
    final Color surfaceBg = isDark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6);

    return Material(
      color: selected ? selectedColor : surfaceBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? selectedColor : borderColor, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchSession(BuildContext modalContext, [StateSetter? setModalState]) async {
    if (setModalState != null) setModalState(() => _isLaunching = true);
    setState(() => _isLaunching = true);

    try {
      // 1. Dismiss modal bottom sheet FIRST so UI stays responsive
      if (Navigator.canPop(modalContext)) {
        Navigator.pop(modalContext);
      }

      // 2. Verify Location Permissions
      final hasPermission = await PlatformService.instance.checkPermissions();
      if (!hasPermission) {
        final granted = await PlatformService.instance.requestPermissions();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission is required for GPS tracking.'),
                backgroundColor: Color(0xFFEF4444),
              ),
            );
          }
          return;
        }
      }

      final dbHelper = DbService.instance;
      final bool isFreeRun = _activityType == 'freerun';
      final int targetSeconds = isFreeRun ? 0 : _targetDurationMinutes * 60;
      
      // 3. Create SQLite Tracking Instance
      final int sessionId = await dbHelper.createSession(
        activityType: _activityType,
        targetDurationSeconds: targetSeconds,
        safetyBufferPct: _safetyBufferPct,
      );

      // 4. Start Native Background Service Location Channel (Kotlin)
      final bool startSuccess = await PlatformService.instance.startTracking(
        sessionId: sessionId,
        activityType: _activityType,
        targetDurationSeconds: targetSeconds,
        safetyBufferPct: _safetyBufferPct,
        gpsIntervalMs: _gpsIntervalMs,
      );

      if (startSuccess && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HudScreen(
              sessionId: sessionId,
              targetDuration: Duration(seconds: targetSeconds),
              safetyBufferPct: _safetyBufferPct,
              activityType: _activityType,
              isFreeRun: isFreeRun,
              referenceSessionId: _selectedReferenceSessionId,
            ),
          ),
        ).then((_) => _loadDashboardData());
      } else {
        throw Exception("Could not verify GPS Telemetry Foreground channel.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting tracking: $e')),
        );
      }
    } finally {
      if (mounted) {
        if (setModalState != null) setModalState(() => _isLaunching = false);
        setState(() => _isLaunching = false);
      }
    }
  }

  Widget _buildColabMeshCard(Color textColor, Color cardBg, Color borderColor, bool isDark) {
    return AnimatedBuilder(
      animation: P2pMeshService.instance,
      builder: (context, _) {
        final mesh = P2pMeshService.instance;
        final bool isMeshActive = mesh.isActive;
        final activePeers = mesh.teammates.where((t) => t.isActive).toList();

        if (isMeshActive) {
          return Container(
            margin: const EdgeInsets.only(bottom: 20.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 1.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF10B981).withValues(alpha: isDark ? 0.15 : 0.08),
                  cardBg,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'MESH ACTIVE: "${mesh.sessionConfig?.sessionName ?? 'Group Ride'}"',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Color(0xFF10B981)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${activePeers.length} Online',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (activePeers.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: activePeers.map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: t.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(radius: 4, backgroundColor: t.color),
                          const SizedBox(width: 5),
                          Text(
                            t.username.isNotEmpty ? t.username : t.displayTag,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    if (mesh.sessionConfig != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code, size: 16),
                          label: const Text('Share QR / Code', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (qrCtx) => MeshQrDisplayDialog(config: mesh.sessionConfig!),
                            );
                          },
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 20),
                      tooltip: 'Leave Group',
                      onPressed: () async {
                        await P2pMeshService.instance.leaveSession();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 20.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3), width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2563EB).withValues(alpha: isDark ? 0.12 : 0.06),
                cardBg,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.groups_rounded, color: Color(0xFF3B82F6), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'P2P GROUP RIDE (COLAB)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Color(0xFF3B82F6)),
                        ),
                        Text(
                          'Private zero-server live tracking over Wi-Fi / Hotspot',
                          style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.wifi_tethering, size: 16),
                      label: const Text('Host Ride', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF3B82F6),
                        side: const BorderSide(color: Color(0xFF3B82F6), width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _showMeshSessionDialog(context, initialTab: 0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner, size: 16),
                      label: const Text('Join Ride', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _showMeshSessionDialog(context, initialTab: 1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMeshSessionDialog(BuildContext context, {int initialTab = 0}) {
    final theme = Theme.of(context);
    final nameCtrl = TextEditingController(text: 'Team Out-and-Back');
    final userCtrl = TextEditingController(text: 'Rider');
    final uriCtrl = TextEditingController();
    int selectedColor = 0xFFFF5722; // Ember Orange

    showDialog(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (sCtx, setModalState) {
            return DefaultTabController(
              initialIndex: initialTab,
              length: 2,
              child: AlertDialog(
                backgroundColor: theme.scaffoldBackgroundColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const TabBar(
                  tabs: [
                    Tab(text: 'Host Mesh'),
                    Tab(text: 'Join Mesh'),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: TabBarView(
                    children: [
                      // HOST TAB
                      SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Session Name',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: userCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Your Display Username',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Marker Color:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                0xFFFF5722, // Orange
                                0xFF2563EB, // Blue
                                0xFF10B981, // Green
                                0xFF8B5CF6, // Purple
                                0xFFF59E0B, // Gold
                              ].map((c) => GestureDetector(
                                onTap: () => setModalState(() => selectedColor = c),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Color(c),
                                  child: selectedColor == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                                ),
                              )).toList(),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.wifi_tethering, size: 18),
                                label: const Text('Host Session & Show QR', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () async {
                                  final config = await P2pMeshService.instance.startHostSession(
                                    sessionName: nameCtrl.text.trim(),
                                    username: userCtrl.text.trim(),
                                    colorValue: selectedColor,
                                  );

                                  if (dCtx.mounted) {
                                    Navigator.pop(dCtx);
                                    // Show QR Code dialog
                                    showDialog(
                                      context: context,
                                      builder: (qrCtx) => MeshQrDisplayDialog(config: config),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // JOIN TAB
                      SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            // Primary 1-Tap Camera Scanner Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                                label: const Text('Scan QR Code with Camera', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () async {
                                  final scannedUri = await MeshQrCameraScannerDialog.scan(context);
                                  if (scannedUri != null && scannedUri.isNotEmpty) {
                                    setModalState(() {
                                      uriCtrl.text = scannedUri;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Text('OR PASTE LINK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5))),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: uriCtrl,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Paste Mesh URI (turnback://...)',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.content_paste, size: 18),
                                  tooltip: 'Paste from Clipboard',
                                  onPressed: () async {
                                    final data = await Clipboard.getData('text/plain');
                                    if (data?.text != null) {
                                      setModalState(() {
                                        uriCtrl.text = data!.text!.trim();
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: userCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Your Display Username',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Marker Color:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                0xFFFF5722,
                                0xFF2563EB,
                                0xFF10B981,
                                0xFF8B5CF6,
                                0xFFF59E0B,
                              ].map((c) => GestureDetector(
                                onTap: () => setModalState(() => selectedColor = c),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Color(c),
                                  child: selectedColor == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                                ),
                              )).toList(),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.link, size: 18),
                                label: const Text('Join Mesh Session', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () async {
                                  final config = MeshSessionConfig.fromUri(uriCtrl.text.trim());
                                  if (config == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Invalid turnback:// mesh URI. Please scan QR or paste a valid link.')),
                                    );
                                    return;
                                  }

                                  await P2pMeshService.instance.joinSession(
                                    config: config,
                                    username: userCtrl.text.trim(),
                                    colorValue: selectedColor,
                                  );

                                  if (dCtx.mounted) {
                                    Navigator.pop(dCtx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Joined ${config.sessionName} mesh!')),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dCtx),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  Widget _buildActiveSessionCard(Color textColor, Brightness brightness) {
    if (_activeSession == null) return const SizedBox.shrink();

    final int id = _activeSession!['id'] as int;
    final String type = (_activeSession!['activity_type'] as String).toUpperCase();
    final double buffer = _activeSession!['safety_buffer'] as double;
    final int targetSec = _activeSession!['target_duration'] as int;
    final String status = _activeSession!['status'] as String;
    final bool isPaused = status == 'paused';

    final double outboundRatio = (100.0 - buffer) / 200.0;
    final int outboundLimitSeconds = (targetSec * outboundRatio).toInt();
    final int remainingSeconds = max(0, outboundLimitSeconds - _activeElapsed.inSeconds);

    final isDark = brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1212) : const Color(0xFFFEF2F2);
    final borderColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA);

    return Container(
      margin: const EdgeInsets.only(bottom: 20.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner header
          Container(
            color: const Color(0xFFDC2626),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radio_button_checked, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'ACTIVE $type (#$id)',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 13, letterSpacing: 0.8),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Realtime timers
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MOVING TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                        const SizedBox(height: 2),
                        Text(
                          _formatDuration(_activeElapsed),
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _activeTurnBackTriggered ? 'RETURN TIMER' : 'TIME TO TURN BACK',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: _activeTurnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _activeTurnBackTriggered
                              ? _formatDuration(Duration(seconds: max(0, targetSec - _activeElapsed.inSeconds)))
                              : _formatDuration(Duration(seconds: remainingSeconds)),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _activeTurnBackTriggered ? const Color(0xFFDC2626) : textColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: min(1.0, _activeElapsed.inSeconds / outboundLimitSeconds),
                    backgroundColor: textColor.withValues(alpha: 0.1),
                    color: _activeTurnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                    minHeight: 6.0,
                  ),
                ),
              ],
            ),
          ),

          // Controller Action Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.6),
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () => _toggleActivePause(id, type, targetSec, buffer),
                  child: Text(
                    isPaused ? 'RESUME' : 'PAUSE',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () => _confirmStopActiveSession(id, type),
                  child: const Text(
                    'STOP',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HudScreen(
                          sessionId: id,
                          targetDuration: Duration(seconds: targetSec),
                          safetyBufferPct: buffer,
                          activityType: type.toLowerCase(),
                          isFreeRun: type.toLowerCase() == 'freerun',
                        ),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('OPEN HUD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final bool isDark = brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF111827);
    final Color cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final Color borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE5E7EB);
    final Color accentColor = SettingsService.instance.accentColor.color;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: 32,
              height: 32,
              errorBuilder: (_, __, ___) => const Icon(Icons.directions_run_rounded, size: 30, color: Color(0xFFFF5722)),
            ),
            const SizedBox(width: 10),
            Text(
              isColab ? 'TURNBACK COLAB' : 'TURNBACK',
              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          if (isColab)
            AnimatedBuilder(
              animation: P2pMeshService.instance,
              builder: (context, _) {
                final isMeshActive = P2pMeshService.instance.isActive;
                final peerCount = P2pMeshService.instance.teammates.where((t) => t.isActive).length;
                return GestureDetector(
                  onTap: () => _showMeshSessionDialog(context),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (isMeshActive ? const Color(0xFF10B981) : const Color(0xFF2563EB)).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isMeshActive ? const Color(0xFF10B981) : const Color(0xFF2563EB)).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_tethering,
                          size: 16,
                          color: isMeshActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isMeshActive ? '$peerCount ONLINE' : 'GROUP',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: isMeshActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.tune_rounded, size: 20, color: textColor),
            ),
            tooltip: 'Settings, Themes & Preferences',
            onPressed: () {
              Navigator.pushNamed(context, '/settings').then((_) => setState(() {}));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.play_arrow_rounded, size: 28),
        label: const Text('RECORD RUN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 14)),
        onPressed: () => _showRecordBottomSheet(context),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Real-Time Active Session Banner (Ticking return countdown)
              _buildActiveSessionCard(textColor, brightness),

              // Intuitive Colab P2P Mesh Group Ride Card (Visible only in Colab flavor)
              if (isColab)
                _buildColabMeshCard(textColor, cardBg, borderColor, isDark),

              // Strava-Style Athletic Performance Summary Card
              Container(
                margin: const EdgeInsets.only(bottom: 20.0),
                padding: const EdgeInsets.all(18.0),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'LIFETIME TOTALS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.5), letterSpacing: 1.0),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'OFFLINE GPS',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatBox('ACTIVITIES', '${_completedSessions.length}', textColor),
                        _buildStatBox('DISTANCE', '${_lifetimeDistance.toStringAsFixed(1)} km', textColor),
                        _buildStatBox('MOVING TIME', '${_lifetimeDuration.inHours}h ${_lifetimeDuration.inMinutes % 60}m', textColor),
                      ],
                    ),
                  ],
                ),
              ),

              // Activity Feed Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ACTIVITY HISTORY',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.8),
                  ),
                  if (_completedSessions.isNotEmpty)
                    Text(
                      '${_completedSessions.length} total',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Completed Runs Listing Feed
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: accentColor))
                    : _completedSessions.isEmpty
                        ? _buildEmptyDashboard(textColor)
                        : ListView.builder(
                            itemCount: _completedSessions.length,
                            itemBuilder: (context, index) {
                              final session = _completedSessions[index];
                              return SessionFeedCard(
                                session: session,
                                textColor: textColor,
                                brightness: brightness,
                                onDelete: () => _confirmDelete(session['id'] as int),
                                onEdit: () => _editActivity(session['id'] as int, session['activity_type'] as String),
                                onContinue: () => _showContinueCompletedRunModal(session),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContinueCompletedRunModal(Map<String, dynamic> session) {
    HapticFeedback.selectionClick();
    final int sessionId = session['id'] as int;
    final String activityType = session['activity_type'] as String;
    final int originalTargetSec = session['target_duration'] as int;
    final double buffer = (session['safety_buffer'] as num).toDouble();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final surfaceBg = isDark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6);
    final borderColor = isDark ? const Color(0xFF2D333F) : const Color(0xFFE5E7EB);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        int targetMinutes = max(5, originalTargetSec ~/ 60);
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20.0,
                right: 20.0,
                top: 16.0,
                bottom: 20.0 + MediaQuery.of(ctx).viewInsets.bottom,
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
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF10B981), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CONTINUE WORKOUT #$sessionId',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.8),
                            ),
                            Text(
                              'Resume logging GPS track & append to this run',
                              style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Option 1: Continue with original target
                  _buildContinueModalCard(
                    title: 'CONTINUE EXISTING TIMER',
                    subtitle: 'Resume with original target (${originalTargetSec ~/ 60}m) and append new GPS points',
                    icon: Icons.fast_forward_rounded,
                    color: const Color(0xFF10B981),
                    textColor: textColor,
                    surfaceBg: surfaceBg,
                    borderColor: borderColor,
                    onTap: () => _executeContinueSession(sessionId, activityType, originalTargetSec, buffer),
                  ),
                  const SizedBox(height: 10),

                  // Option 2: Reset countdown to start fresh
                  _buildContinueModalCard(
                    title: 'RESET RETURN COUNTDOWN',
                    subtitle: 'Start a fresh ${originalTargetSec ~/ 60}m return countdown from now (preserves previous GPS trail)',
                    icon: Icons.restart_alt_rounded,
                    color: const Color(0xFF3B82F6),
                    textColor: textColor,
                    surfaceBg: surfaceBg,
                    borderColor: borderColor,
                    onTap: () => _executeContinueSession(sessionId, activityType, originalTargetSec, buffer),
                  ),
                  const SizedBox(height: 10),

                  // Option 3: Set whole new target duration
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surfaceBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.edit_calendar_rounded, size: 18, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 8),
                            Text(
                              'SET NEW RETURN TARGET: $targetMinutes MIN',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.6),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: targetMinutes.toDouble(),
                          min: 5,
                          max: 180,
                          divisions: 35,
                          activeColor: const Color(0xFFF59E0B),
                          label: '$targetMinutes min',
                          onChanged: (v) => setModalState(() => targetMinutes = v.round()),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final m in [15, 30, 45, 60, 90])
                              GestureDetector(
                                onTap: () => setModalState(() => targetMinutes = m),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: targetMinutes == m ? const Color(0xFFF59E0B) : (isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Text(
                                    '${m}m',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: targetMinutes == m ? Colors.white : textColor),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _executeContinueSession(sessionId, activityType, targetMinutes * 60, buffer),
                            child: const Text('APPLY NEW DURATION & CONTINUE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContinueModalCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color textColor,
    required Color surfaceBg,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: textColor.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

  void _executeContinueSession(int sessionId, String activityType, int targetSec, double buffer) async {
    Navigator.pop(context); // close modal

    await DbService.instance.reactivateSession(sessionId, newTargetDurationSeconds: targetSec);

    await PlatformService.instance.startTracking(
      sessionId: sessionId,
      activityType: activityType.toLowerCase(),
      targetDurationSeconds: targetSec,
      safetyBufferPct: buffer,
      gpsIntervalMs: 5000,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HudScreen(
            sessionId: sessionId,
            targetDuration: Duration(seconds: targetSec),
            safetyBufferPct: buffer,
            activityType: activityType.toLowerCase(),
            isFreeRun: activityType.toLowerCase() == 'freerun',
          ),
        ),
      ).then((_) => _loadDashboardData());
    }
  }

  Widget _buildStatBox(String label, String value, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5))),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor),
        ),
      ],
    );
  }

  Widget _buildEmptyDashboard(Color textColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.directions_run, size: 40, color: textColor.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 14),
          Text(
            'NO COMPLETED ACTIVITIES YET',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "RECORD RUN" below to track your first out-and-back.',
            style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}

class SessionFeedCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final Color textColor;
  final Brightness brightness;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onContinue;

  const SessionFeedCard({
    super.key,
    required this.session,
    required this.textColor,
    required this.brightness,
    required this.onDelete,
    required this.onEdit,
    this.onContinue,
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
    _loadPoints();
  }

  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const pVal = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * pVal) / 2 +
          cos(lat1 * pVal) * cos(lat2 * pVal) *
          (1 - cos((lon2 - lon1) * pVal)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Future<void> _loadPoints() async {
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
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final int id = session['id'] as int;
    final String type = (session['activity_type'] as String).toUpperCase();
    final int targetSec = session['target_duration'] as int;
    final int startMs = session['start_time'] as int;
    final int? endMs = session['end_time'] as int?;

    final startDate = DateTime.fromMillisecondsSinceEpoch(startMs);
    final duration = endMs != null ? Duration(milliseconds: endMs - startMs) : Duration.zero;

    final String dateString = '${startDate.day}/${startDate.month}/${startDate.year}';
    final String durationString = '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    final bool triggered = session['turn_back_triggered_at'] != null;

    final isDark = widget.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF23272F) : const Color(0xFFE5E7EB);

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1E24) : const Color(0xFFF3F4F6),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      type == 'RIDE' ? Icons.directions_bike : type == 'HIKE' ? Icons.hiking : Icons.directions_run,
                      size: 18,
                      color: const Color(0xFFFF5722),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$type #$id',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: widget.textColor,
                      ),
                    ),
                  ],
                ),
                Text(
                  dateString,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: widget.textColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

          // Main stats + Map Grid
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Stats details
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL DISTANCE',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: widget.textColor.withValues(alpha: 0.5)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isLoading ? '...' : '${_distanceKm.toStringAsFixed(2)} KM',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: widget.textColor),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('DURATION', style: TextStyle(fontSize: 9, color: widget.textColor.withValues(alpha: 0.5))),
                                    Text(durationString, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.textColor)),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('TARGET', style: TextStyle(fontSize: 9, color: widget.textColor.withValues(alpha: 0.5))),
                                    Text('${targetSec ~/ 60}m', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.textColor)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              triggered ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                              size: 14,
                              color: triggered ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              triggered ? 'Turned back on signal' : 'Completed outbound safely',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: triggered ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Map Thumbnail
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: borderColor)),
                      color: isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FA),
                    ),
                    child: _isLoading
                        ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0)))
                        : _mapPoints.isEmpty
                            ? Center(child: Text("NO GPS", style: TextStyle(fontSize: 10, color: widget.textColor.withValues(alpha: 0.4))))
                            : ClipRect(
                                child: CustomPaint(
                                  painter: BreadcrumbPainter(points: _mapPoints, brightness: widget.brightness),
                                ),
                              ),
                  ),
                ),
              ],
            ),
          ),

          // Actions row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1E24) : const Color(0xFFF8F9FA),
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (widget.onContinue != null) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      onPressed: widget.onContinue,
                      icon: const Icon(Icons.play_arrow_rounded, size: 15),
                      label: const Text('CONTINUE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: widget.onEdit,
                    icon: Icon(Icons.content_cut, size: 14, color: widget.textColor.withValues(alpha: 0.7)),
                    label: Text('EDIT', style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => _exportGpx(id, type, context),
                    icon: Icon(Icons.file_download_outlined, size: 14, color: widget.textColor.withValues(alpha: 0.7)),
                    label: Text('GPX', style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 18),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportGpx(int sessionId, String type, BuildContext context) async {
    try {
      final file = await GpxService.instance.saveGpxFile(sessionId, type);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPX saved to TurnBack folder:\n${file.path}'), duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}
