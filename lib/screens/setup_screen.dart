import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/db_service.dart';
import '../services/platform_service.dart';
import '../services/gpx_service.dart';
import '../services/backup_service.dart';
import '../widgets/breadcrumb_painter.dart';
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
  /// Creates a new [SetupScreen] instance.
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

/// State controller for the [SetupScreen], managing lifetime analytics.
class _SetupScreenState extends State<SetupScreen> {

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
      final diff = points[i]['timestamp'] - points[i-1]['timestamp'];
      if (diff > 0 && diff < 15000 && (points[i]['speed'] as double) > 0.2) {
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
      
      final double lat = event['lat'] as double;
      final double lng = event['lng'] as double;

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
    final Color textColor = brightness == Brightness.light ? Colors.black : Colors.white;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brightness == Brightness.light ? Colors.white : Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                top: 24.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.between,
                      children: [
                        Text(
                          'RECORD ACTIVITY',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 1.0),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: textColor),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                    const Divider(thickness: 1.5),
                    const SizedBox(height: 16),

                    // Activity Type Choice
                    _buildModalLabel('ACTIVITY TYPE', _activityType.toUpperCase(), textColor),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _activityType,
                      dropdownColor: brightness == Brightness.light ? Colors.white : Colors.black,
                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 2.0)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'run', child: Text('RUN / WALK')),
                        DropdownMenuItem(value: 'ride', child: Text('CYCLING / RIDE')),
                        DropdownMenuItem(value: 'kayak', child: Text('KAYAK / ROW')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _activityType = val);
                          setState(() => _activityType = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Target Duration Slider
                    _buildModalLabel('TARGET DURATION', '$_targetDurationMinutes MIN', textColor),
                    Slider(
                      value: _targetDurationMinutes.toDouble(),
                      min: 10,
                      max: 240,
                      divisions: 46,
                      activeColor: textColor,
                      inactiveColor: textColor.withOpacity(0.2),
                      onChanged: (val) {
                        setModalState(() => _targetDurationMinutes = val.toInt());
                        setState(() => _targetDurationMinutes = val.toInt());
                      },
                    ),
                    const SizedBox(height: 16),

                    // Fatigue Safety Buffer Slider
                    _buildModalLabel('FATIGUE SAFETY BUFFER', '${_safetyBufferPct.toStringAsFixed(1)}%', textColor),
                    Slider(
                      value: _safetyBufferPct,
                      min: 0,
                      max: 20,
                      divisions: 20,
                      activeColor: textColor,
                      inactiveColor: textColor.withOpacity(0.2),
                      onChanged: (val) {
                        setModalState(() => _safetyBufferPct = val);
                        setState(() => _safetyBufferPct = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // GPS Sampling Interval
                    _buildModalLabel('GPS SAMPLING RATE', _gpsIntervalMs == 1000 ? '1S (HIGH ACCURACY)' : _gpsIntervalMs == 5000 ? '5S (BALANCED)' : '15S (POWER SAVE)', textColor),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _gpsIntervalMs,
                      dropdownColor: brightness == Brightness.light ? Colors.white : Colors.black,
                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 2.0)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1000, child: Text('High Accuracy (1s)')),
                        DropdownMenuItem(value: 5000, child: Text('Balanced (5s)')),
                        DropdownMenuItem(value: 15000, child: Text('Power Save (15s)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _gpsIntervalMs = val);
                          setState(() => _gpsIntervalMs = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Reference Track Selector
                    _buildModalLabel('REFERENCE ROUTE GUIDANCE', _selectedReferenceSessionId != null ? 'ACTIVE' : 'NONE', textColor),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int?>(
                      value: _selectedReferenceSessionId,
                      dropdownColor: brightness == Brightness.light ? Colors.white : Colors.black,
                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 2.0)),
                      ),
                      hint: const Text('FOLLOW A COMPLETED SESSION (OPTIONAL)'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('NONE - FREE TRACKING')),
                        ..._completedSessions.map((s) {
                          final date = DateTime.fromMillisecondsSinceEpoch(s['start_time'] as int);
                          final type = (s['activity_type'] as String).toUpperCase();
                          return DropdownMenuItem<int?>(
                            value: s['id'] as int,
                            child: Text('$type - ${date.month}/${date.day} (ID: ${s['id']})'),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setModalState(() => _selectedReferenceSessionId = val);
                        setState(() => _selectedReferenceSessionId = val);
                      },
                    ),
                    const SizedBox(height: 28),

                    // Launch Session Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: textColor,
                        foregroundColor: brightness == Brightness.light ? Colors.white : Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18.0),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        side: BorderSide(color: textColor, width: 2.0),
                      ),
                      onPressed: _isLaunching ? null : () => _launchSession(context),
                      child: _isLaunching
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'START TRACKING NOW',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2),
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

  Widget _buildModalLabel(String title, String value, Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.between,
      children: [
        Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.6))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textColor)),
      ],
    );
  }

  Future<void> _launchSession(BuildContext modalContext) async {
    setState(() => _isLaunching = true);

    try {
      final dbHelper = DbService.instance;
      
      // 1. Create SQLite Tracking Instance
      final int sessionId = await dbHelper.createSession(
        activityType: _activityType,
        targetDurationSeconds: _targetDurationMinutes * 60,
        safetyBufferPct: _safetyBufferPct,
      );

      // 2. Start Native Background Service Location Channel (Kotlin)
      final bool startSuccess = await PlatformService.instance.startTracking(
        sessionId: sessionId,
        activityType: _activityType,
        targetDurationSeconds: _targetDurationMinutes * 60,
        safetyBufferPct: _safetyBufferPct,
        gpsIntervalMs: _gpsIntervalMs,
      );

      if (startSuccess && mounted) {
        Navigator.pop(modalContext); // Close modal sheet
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HudScreen(
              sessionId: sessionId,
              targetDuration: Duration(minutes: _targetDurationMinutes),
              safetyBufferPct: _safetyBufferPct,
              activityType: _activityType,
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
      if (mounted) setState(() => _isLaunching = false);
    }
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

    final cardBg = brightness == Brightness.light ? Colors.red[50] : Colors.red[950]!.withOpacity(0.2);

    return Container(
      margin: const EdgeInsets.only(bottom: 24.0),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: Colors.red, width: 2.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner header
          Container(
            color: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radio_button_checked, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'ACTIVE SESSION (#$id) - $type',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
                Text(
                  status.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
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
                  mainAxisAlignment: MainAxisAlignment.between,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MOVING TIME', style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.6))),
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
                          _activeTurnBackTriggered ? 'RETURN TIMER' : 'OUTBOUND LIMIT',
                          style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.6)),
                        ),
                        Text(
                          _activeTurnBackTriggered
                              ? _formatDuration(Duration(seconds: max(0, targetSec - _activeElapsed.inSeconds)))
                              : _formatDuration(Duration(seconds: remainingSeconds)),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _activeTurnBackTriggered ? Colors.red : textColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: min(1.0, _activeElapsed.inSeconds / outboundLimitSeconds),
                  backgroundColor: textColor.withOpacity(0.1),
                  color: _activeTurnBackTriggered ? Colors.red : Colors.redAccent,
                  minHeight: 6.0,
                ),
              ],
            ),
          ),

          // Controller Action Buttons
          Divider(color: Colors.red.withOpacity(0.3), height: 1, thickness: 1),
          Container(
            color: Colors.red.withOpacity(0.04),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
    final Color textColor = brightness == Brightness.light ? Colors.black : Colors.white;
    final Color scaffoldBg = brightness == Brightness.light ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('// TURNBACK', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.archive_outlined, color: textColor),
            tooltip: 'Export ZIP Database Backup',
            onPressed: _runZipBackup,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: textColor,
        foregroundColor: brightness == Brightness.light ? Colors.white : Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        icon: const Icon(Icons.play_arrow_outlined),
        label: const Text('RECORD RUN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        onPressed: () => _showRecordBottomSheet(context),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Real-Time Active Session Banner (Ticking return countdown)
              _buildActiveSessionCard(textColor, brightness),

              // Premium Strava-Style Stats Card
              Container(
                margin: const EdgeInsets.only(bottom: 24.0),
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: brightness == Brightness.light
                        ? [Colors.grey[200]!, Colors.grey[300]!]
                        : [Colors.grey[900]!, Colors.grey[850]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: textColor, width: 2.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LIFETIME PERFORMANCE SUMMARY',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.between,
                      children: [
                        _buildStatBox('ACTIVITIES', '${_completedSessions.length}', textColor),
                        _buildStatBox('DISTANCE', '${_lifetimeDistance.toStringAsFixed(1)} km', textColor),
                        _buildStatBox('ACTIVE TIME', '${_lifetimeDuration.inHours} hrs', textColor),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, thickness: 1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.folder_shared_outlined, size: 14, color: textColor.withOpacity(0.6)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'SYNC DIR: $_autoSyncPath',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.6)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Activity Feed Title
              Text(
                'YOUR ACTIVITY FEED',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 1.0),
              ),
              const SizedBox(height: 12),

              // Completed Runs Listing Feed
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: textColor))
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

  Widget _buildStatBox(String label, String value, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5))),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor),
        ),
      ],
    );
  }

  Widget _buildEmptyDashboard(Color textColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_run, size: 48, color: textColor.withOpacity(0.3)),
          const SizedBox(height: 14),
          Text(
            'NO COMPLETED ACTIVITIES YET',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.6)),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "RECORD RUN" at the bottom right to begin.',
            style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.4)),
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

  const SessionFeedCard({
    super.key,
    required this.session,
    required this.textColor,
    required this.brightness,
    required this.onDelete,
    required this.onEdit,
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
    return 12742 * asin(sqrt(a)); // Haversine formula (km)
  }

  Future<void> _loadPoints() async {
    final dbHelper = DbService.instance;
    final points = await dbHelper.getPoints(widget.session['id'] as int);
    
    double dist = 0.0;
    List<Point<double>> parsed = [];
    
    for (int i = 0; i < points.length; i++) {
      final lat = points[i]['lat'] as double;
      final lng = points[i]['lng'] as double;
      parsed.add(Point(lat, lng));
      
      if (i > 0) {
        dist += _distanceBetween(points[i-1]['lat'] as double, points[i-1]['lng'] as double, lat, lng);
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
    final double buffer = session['safety_buffer'] as double;
    final int startMs = session['start_time'] as int;
    final int? endMs = session['end_time'] as int?;

    final startDate = DateTime.fromMillisecondsSinceEpoch(startMs);
    final duration = endMs != null ? Duration(milliseconds: endMs - startMs) : Duration.zero;

    final String dateString = '${startDate.day}/${startDate.month}/${startDate.year}';
    final String durationString = '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    final bool triggered = session['turn_back_triggered_at'] != null;

    final cardBg = widget.brightness == Brightness.light ? Colors.grey[100] : Colors.grey[900];

    return Container(
      margin: const EdgeInsets.only(bottom: 20.0),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: widget.textColor, width: 2.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Container(
            color: widget.textColor,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                Text(
                  '$type - ACTIVITY #$id',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: widget.brightness == Brightness.light ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  dateString,
                  style: TextStyle(
                    fontSize: 12,
                    color: (widget.brightness == Brightness.light ? Colors.white : Colors.black).withOpacity(0.8),
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
                              'DISTANCE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: widget.textColor.withOpacity(0.5)),
                            ),
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
                                    Text('DURATION', style: TextStyle(fontSize: 9, color: widget.textColor.withOpacity(0.5))),
                                    Text(durationString, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.textColor)),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('TARGET', style: TextStyle(fontSize: 9, color: widget.textColor.withOpacity(0.5))),
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
                              color: triggered ? Colors.red : Colors.green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              triggered ? 'Safety alarm triggered' : 'Outbound return safe',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: triggered ? Colors.red : Colors.green),
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
                      border: Border(left: BorderSide(color: widget.textColor, width: 2.0)),
                    ),
                    child: _isLoading
                        ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0)))
                        : _mapPoints.isEmpty
                            ? Center(child: Text("NO GPS", style: TextStyle(fontSize: 10, color: widget.textColor.withOpacity(0.4))))
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

          Divider(color: widget.textColor.withOpacity(0.3), height: 1, thickness: 1),

          // Actions row
          Container(
            color: widget.textColor.withOpacity(0.03),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: widget.onEdit,
                  child: Text('EDIT/CHOP', style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _exportGpx(id, type, context),
                  child: Text('EXPORT GPX', style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportGpx(int sessionId, String type, BuildContext context) async {
    try {
      final file = await GpxService.instance.saveGpxFile(sessionId, type);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPX saved to TurnBack folder:\n${file.path}'), duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
}
