import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ble_sensor_service.dart';
import '../services/db_service.dart';
import '../services/elevation_filter_service.dart';
import '../services/platform_service.dart';
import '../services/rally_service.dart';
import '../services/settings_service.dart';
import '../services/p2p_mesh_service.dart';
import '../widgets/hud_media_controller.dart';
import '../widgets/musicolet_4x1_widget.dart';
import '../widgets/osm_map_view.dart';
import '../widgets/telemetry_chart.dart';
import '../widgets/mesh_radar_widget.dart';
import '../widgets/mesh_qr_widget.dart';
import '../widgets/strava_upload_dialog.dart';


/// Ultra-high performance HUD Activity Screen.
class HudScreen extends StatefulWidget {
  final int sessionId;
  final Duration targetDuration;
  final double safetyBufferPct;
  final String activityType;
  final bool isFreeRun;
  final int? referenceSessionId;

  const HudScreen({
    super.key,
    required this.sessionId,
    required this.targetDuration,
    required this.safetyBufferPct,
    required this.activityType,
    this.isFreeRun = false,
    this.referenceSessionId,
  });

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  // Telemetry list
  final List<Point<double>> _points = [];
  final List<TelemetrySample> _chartSamples = [];

  // Real-time metrics
  double _currentSpeed = 0.0; // m/s
  double _avgSpeed = 0.0; // m/s
  double _distanceKm = 0.0;
  double _altitude = 0.0;
  double _accuracy = 0.0;

  late DateTime _startTime;
  Duration _elapsed = Duration.zero; // moving time
  Duration _totalElapsed = Duration.zero; // total time
  Timer? _timer;
  StreamSubscription? _telemetrySub;

  // Detailed metrics
  double _maxSpeed = 0.0;
  double _minAltitude = double.maxFinite;
  double _maxAltitude = -double.maxFinite;
  double _totalAscent = 0.0;
  double _totalDescent = 0.0;
  double? _prevAltitude;

  // Multi-page HUD View
  final PageController _pageController = PageController();
  int _currentPageIndex = 0;
  bool _showOsmTiles = false;
  bool _isMapFullScreen = false;

  // Dynamic unit switching hysteresis
  bool _isSpeedMode = false;
  int _consecutiveSpeedTicks = 0;
  int _consecutivePaceTicks = 0;
  static const int _hysteresisWindowSeconds = 5;
  static const double _speedThresholdMps = 5.0; // 18 km/h

  // Tracking control state
  bool _isPaused = false;
  bool _turnBackTriggered = false;
  bool _freeRunReturning = false;
  Duration _outboundFreeRunDuration = Duration.zero;
  int? _lastTimestamp;

  // Rally navigation state variables
  RallyNavigationEngine? _rallyEngine;
  RallyNavigationState? _rallyState;

  // Flashing turn-back indicator
  bool _flashToggle = false;
  Timer? _flashTimer;

  late Duration _activeTargetDuration;

  // BLE Sensor State & OLED Power Saving
  BleSensorData _sensorData = const BleSensorData();
  StreamSubscription<BleSensorData>? _bleSensorSub;
  bool _isOledDimmed = false;
  Timer? _inactivityTimer;

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_isOledDimmed) {
      setState(() => _isOledDimmed = false);
    }
    _inactivityTimer = Timer(const Duration(seconds: 25), () {
      if (mounted && !_isPaused) {
        setState(() => _isOledDimmed = true);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _activeTargetDuration = widget.targetDuration;
    _startTime = DateTime.now();
    _isSpeedMode = widget.activityType == 'ride';

    // Clamp display refresh rate to 30Hz or lowest hardware mode for ultra-low battery drain
    PlatformService.instance.setPowerSaveDisplay(true);

    // Listen to BLE heart rate and cadence sensors
    _sensorData = BleSensorService.instance.currentData;
    _bleSensorSub = BleSensorService.instance.sensorStream.listen((data) {
      if (mounted) {
        setState(() => _sensorData = data);
      }
    });

    _resetInactivityTimer();
    _loadExistingData();
    _loadReferenceRoute();
    _startTimer();
    _startTelemetryStream();
  }

  void _showResumeOptionsDialog() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final surfaceBg = isDark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6);
    final borderColor = isDark ? const Color(0xFF2D333F) : const Color(0xFFE5E7EB);
    final accentColor = SettingsService.instance.accentColor.color;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        int tempMinutes = _activeTargetDuration.inMinutes;
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
                  // Drag handle
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
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.play_circle_filled_rounded, color: accentColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RESUME WORKOUT / BREAK ENDED',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              'Choose how to handle your return timer',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Option 1: Continue Existing Timer
                  _buildResumeActionCard(
                    title: 'CONTINUE EXISTING TIMER',
                    subtitle: 'Keep current elapsed time (${_formatDuration(_elapsed)}) and continue return countdown',
                    icon: Icons.fast_forward_rounded,
                    color: const Color(0xFF10B981),
                    textColor: textColor,
                    surfaceBg: surfaceBg,
                    borderColor: borderColor,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _isPaused = false);
                    },
                  ),
                  const SizedBox(height: 10),

                  // Option 2: Reset Return Countdown (Fresh Start for Outbound)
                  _buildResumeActionCard(
                    title: 'RESET RETURN COUNTDOWN',
                    subtitle: 'Reset return timer to full ${_activeTargetDuration.inMinutes}m (preserves all logged GPS track & distance)',
                    icon: Icons.restart_alt_rounded,
                    color: const Color(0xFF3B82F6),
                    textColor: textColor,
                    surfaceBg: surfaceBg,
                    borderColor: borderColor,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _elapsed = Duration.zero;
                        _turnBackTriggered = false;
                        _isPaused = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('RETURN TIMER RESET TO START')),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // Option 3: Set Whole New Target Duration
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
                              'SET NEW RETURN TARGET: $tempMinutes MIN',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.6),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFFF59E0B),
                            thumbColor: const Color(0xFFF59E0B),
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: tempMinutes.toDouble(),
                            min: 5,
                            max: 180,
                            divisions: 35,
                            label: '$tempMinutes min',
                            onChanged: (v) => setModalState(() => tempMinutes = v.round()),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final m in [15, 30, 45, 60, 90])
                              GestureDetector(
                                onTap: () => setModalState(() => tempMinutes = m),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: tempMinutes == m ? const Color(0xFFF59E0B) : (isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Text(
                                    '${m}m',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: tempMinutes == m ? Colors.white : textColor,
                                    ),
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
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _activeTargetDuration = Duration(minutes: tempMinutes);
                                _elapsed = Duration.zero;
                                _turnBackTriggered = false;
                                _isPaused = false;
                              });
                              // Update SQLite session target duration
                              DbService.instance.updateSessionTargetDuration(widget.sessionId, tempMinutes * 60);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('NEW TARGET SET TO $tempMinutes MINUTES')),
                              );
                            },
                            child: const Text('APPLY NEW DURATION & RESUME', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
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

  Widget _buildResumeActionCard({
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

  Future<void> _loadReferenceRoute() async {
    if (widget.referenceSessionId == null) return;
    try {
      final dbHelper = DbService.instance;
      final refPoints = await dbHelper.getPoints(widget.referenceSessionId!);
      if (refPoints.isNotEmpty) {
        setState(() {
          _rallyEngine = RallyNavigationEngine(referencePoints: refPoints);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadExistingData() async {
    final dbHelper = DbService.instance;
    final storedPoints = await dbHelper.getPoints(widget.sessionId);
    final activeSession = await dbHelper.getActiveSession();

    if (activeSession != null) {
      final storedStartTime = activeSession['start_time'] as int;
      final storedTurnBackTriggered = activeSession['turn_back_triggered_at'] != null;

      setState(() {
        _startTime = DateTime.fromMillisecondsSinceEpoch(storedStartTime);
        _turnBackTriggered = storedTurnBackTriggered;
        _points.clear();
        _chartSamples.clear();
        for (final p in storedPoints) {
          final lat = ((p['lat'] ?? 0.0) as num).toDouble();
          final lng = ((p['lng'] ?? 0.0) as num).toDouble();
          final spd = ((p['speed'] ?? 0.0) as num).toDouble();
          final alt = ((p['altitude'] ?? 0.0) as num).toDouble();
          _points.add(Point(lat, lng));
          _chartSamples.add(TelemetrySample(
            distanceKm: _distanceKm,
            elapsedSeconds: _elapsed.inSeconds.toDouble(),
            speedKmh: spd * 3.6,
            altitudeMeters: alt,
          ));
        }
        _calculateSummaryMetrics(storedPoints);
      });

      if (_turnBackTriggered) {
        _startFlashingTimer();
      }
    }
  }

  void _calculateSummaryMetrics(List<Map<String, dynamic>> points) {
    if (points.isEmpty) return;
    double dist = 0.0;
    double ascent = 0.0;
    double descent = 0.0;
    double maxSpd = 0.0;
    double minAlt = double.maxFinite;
    double maxAlt = -double.maxFinite;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final speed = (p['speed'] as num?)?.toDouble() ?? 0.0;
      final alt = (p['altitude'] as num?)?.toDouble() ?? 0.0;

      if (speed > maxSpd) maxSpd = speed;
      if (alt < minAlt) minAlt = alt;
      if (alt > maxAlt) maxAlt = alt;

      if (i > 0) {
        final prev = points[i - 1];
        dist += _distanceBetween(
          prev['lat'] as double,
          prev['lng'] as double,
          p['lat'] as double,
          p['lng'] as double,
        );

        final prevAlt = (prev['altitude'] as num?)?.toDouble() ?? 0.0;
        final altDiff = alt - prevAlt;
        if (altDiff > 0) ascent += altDiff;
        if (altDiff < 0) descent += altDiff.abs();
      }
    }

    _distanceKm = dist;
    _maxSpeed = maxSpd;
    _totalAscent = ascent;
    _totalDescent = descent;
    _minAltitude = minAlt;
    _maxAltitude = maxAlt;
    if (points.isNotEmpty) {
      _altitude = (points.last['altitude'] as num?)?.toDouble() ?? 0.0;
      _currentSpeed = (points.last['speed'] as num?)?.toDouble() ?? 0.0;
    }
  }

  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _totalElapsed = DateTime.now().difference(_startTime);
        if (!_isPaused) {
          _elapsed += const Duration(seconds: 1);
        }

        // Live Turn-Back Outbound Threshold Check (Foreground)
        if (!widget.isFreeRun && !_turnBackTriggered && _activeTargetDuration.inSeconds > 0) {
          final double outboundRatio = (100.0 - widget.safetyBufferPct) / 200.0;
          final int outboundLimitSeconds = (_activeTargetDuration.inSeconds * outboundRatio).toInt();
          if (_elapsed.inSeconds >= outboundLimitSeconds) {
            _turnBackTriggered = true;
            _startFlashingTimer();
            PlatformService.instance.triggerTurnBackAlert(activityType: widget.activityType);
          }
        }
      });
    });
  }

  void _startFlashingTimer() {
    _flashTimer?.cancel();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted) return;
      setState(() {
        _flashToggle = !_flashToggle;
      });
    });
  }

  void _startTelemetryStream() {
    _telemetrySub = PlatformService.instance.telemetryStream.listen((data) {
      if (!mounted || _isPaused) return;

      final double lat = ((data['lat'] ?? 0.0) as num).toDouble();
      final double lng = ((data['lng'] ?? 0.0) as num).toDouble();
      final double alt = ((data['alt'] ?? data['altitude'] ?? 0.0) as num).toDouble();
      final double acc = ((data['acc'] ?? data['accuracy'] ?? 0.0) as num).toDouble();
      final double speed = ((data['speed'] ?? 0.0) as num).toDouble();
      final int timestamp = ((data['time'] ?? data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch) as num).toInt();

      setState(() {
        if (_points.isNotEmpty) {
          final lastPoint = _points.last;
          final d = _distanceBetween(lastPoint.x, lastPoint.y, lat, lng);
          _distanceKm += d;

          if (_prevAltitude != null) {
            final diff = alt - _prevAltitude!;
            if (diff > 0) _totalAscent += diff;
            if (diff < 0) _totalDescent += diff.abs();
          }
        }

        _points.add(Point(lat, lng));
        _currentSpeed = speed;
        _altitude = alt;
        _accuracy = acc;
        _prevAltitude = alt;

        _chartSamples.add(TelemetrySample(
          distanceKm: _distanceKm,
          elapsedSeconds: _elapsed.inSeconds.toDouble(),
          speedKmh: speed * 3.6,
          altitudeMeters: alt,
        ));

        if (speed > _maxSpeed) _maxSpeed = speed;
        if (alt < _minAltitude) _minAltitude = alt;
        if (alt > _maxAltitude) _maxAltitude = alt;

        _lastTimestamp = timestamp;

        if (_elapsed.inSeconds > 0) {
          _avgSpeed = (_distanceKm * 1000) / _elapsed.inSeconds;
        }

        // Rally engine update
        if (_rallyEngine != null) {
          _rallyState = _rallyEngine!.updateNavigation(lat, lng);
        }

        // P2P Mesh Telemetry Broadcast (Active only in Colab flavor)
        if (PlatformService.isColabMode && P2pMeshService.instance.isActive) {
          P2pMeshService.instance.updateLocalPosition(
            lat: lat,
            lng: lng,
            speedKmh: speed * 3.6,
            altitude: alt,
          );
        }

        // Turn-back check on GPS point arrival
        if (!widget.isFreeRun && !_turnBackTriggered && _activeTargetDuration.inSeconds > 0) {
          final double outboundRatio = (100.0 - widget.safetyBufferPct) / 200.0;
          final int outboundLimitSeconds = (_activeTargetDuration.inSeconds * outboundRatio).toInt();
          if (_elapsed.inSeconds >= outboundLimitSeconds) {
            _turnBackTriggered = true;
            _startFlashingTimer();
            PlatformService.instance.triggerTurnBackAlert(activityType: widget.activityType);
          }
        }

        // Speed/Pace Hysteresis (5-second threshold at 18 km/h)
        if (_isSpeedMode) {
          if (speed < _speedThresholdMps) {
            _consecutivePaceTicks++;
            _consecutiveSpeedTicks = 0;
          } else {
            _consecutivePaceTicks = 0;
          }
          if (_consecutivePaceTicks >= _hysteresisWindowSeconds) {
            _isSpeedMode = false;
            _consecutivePaceTicks = 0;
          }
        } else {
          if (speed >= _speedThresholdMps) {
            _consecutiveSpeedTicks++;
            _consecutivePaceTicks = 0;
          } else {
            _consecutiveSpeedTicks = 0;
          }
          if (_consecutiveSpeedTicks >= _hysteresisWindowSeconds) {
            _isSpeedMode = true;
            _consecutiveSpeedTicks = 0;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    PlatformService.instance.setPowerSaveDisplay(false);
    _bleSensorSub?.cancel();
    _inactivityTimer?.cancel();
    _timer?.cancel();
    _flashTimer?.cancel();
    _telemetrySub?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final String minutes = twoDigits(d.inMinutes);
    final String seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _formatEta(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  String _formatSpeedOrPace(double mps) {
    if (mps <= 0.2) return _isSpeedMode ? '0.0' : '--:--';
    if (_isSpeedMode) {
      final double kmh = mps * 3.6;
      return kmh.toStringAsFixed(1);
    } else {
      final double secPerKm = 1000 / mps;
      final int min = secPerKm ~/ 60;
      final int sec = (secPerKm % 60).toInt();
      return '$min:${sec.toString().padLeft(2, '0')}';
    }
  }

  IconData _getTurnIcon(TurnType? type) {
    if (type == null) return Icons.navigation_outlined;
    switch (type) {
      case TurnType.left:
        return Icons.arrow_back;
      case TurnType.sharpLeft:
        return Icons.keyboard_double_arrow_left;
      case TurnType.right:
        return Icons.arrow_forward;
      case TurnType.sharpRight:
        return Icons.keyboard_double_arrow_right;
      case TurnType.uTurn:
        return Icons.settings_backup_restore;
      case TurnType.arrival:
        return Icons.flag;
      case TurnType.offRoute:
        return Icons.warning_amber_rounded;
      default:
        return Icons.navigation_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final bool isDark = brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF111827);
    final Color scaffoldBg = isDark ? const Color(0xFF0F1115) : const Color(0xFFF9FAFB);
    final Color cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final Color surfaceBg = isDark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6);
    final Color borderColor = isDark ? const Color(0xFF2D333F) : const Color(0xFFE5E7EB);
    final Color accentColor = SettingsService.instance.accentColor.color;

    final double outboundRatio = (100.0 - widget.safetyBufferPct) / 200.0;
    final int outboundLimitSeconds = (_activeTargetDuration.inSeconds * outboundRatio).toInt();
    final int remainingOutboundSeconds = max(0, outboundLimitSeconds - _elapsed.inSeconds);
    final int remainingTotalSeconds = max(0, _activeTargetDuration.inSeconds - _elapsed.inSeconds);

    // ------------------------------------------------------------------------
    // FULLSCREEN IMMERSIVE MAP MODE
    // ------------------------------------------------------------------------
    if (_isMapFullScreen) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Map receives 100% uninterrupted touch gestures (pan, zoom)
            OsmMapView(
              points: _points,
              showOsmTiles: _showOsmTiles,
              brightness: brightness,
            ),

            // Top Translucent Telemetry Header
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF14171C) : Colors.white).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Collapse / Back button
                      IconButton(
                        icon: const Icon(Icons.fullscreen_exit_rounded, size: 24),
                        tooltip: 'Exit Fullscreen Map',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isMapFullScreen = false);
                        },
                      ),
                      const SizedBox(width: 6),
                      // Quick Glance Metrics
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _formatSpeedOrPace(_currentSpeed),
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor),
                                ),
                                Text(
                                  _isSpeedMode ? ' km/h' : ' /km',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6)),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${_distanceKm.toStringAsFixed(2)} km',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: accentColor),
                                ),
                              ],
                            ),
                            Text(
                              'Return in: ${_turnBackTriggered ? _formatDuration(Duration(seconds: remainingTotalSeconds)) : _formatDuration(Duration(seconds: remainingOutboundSeconds))}',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textColor.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      ),
                      // Layer toggle button
                      IconButton(
                        icon: Icon(_showOsmTiles ? Icons.layers : Icons.layers_outlined, size: 20),
                        tooltip: 'Toggle OSM Layer',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _showOsmTiles = !_showOsmTiles);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom "Swipe Right on Button to Restore HUD" Slider
            Positioned(
              bottom: 16,
              left: 24,
              right: 24,
              child: SafeArea(
                child: Dismissible(
                  key: const Key('swipe-restore-hud-button'),
                  direction: DismissDirection.startToEnd,
                  confirmDismiss: (direction) async {
                    HapticFeedback.mediumImpact();
                    setState(() => _isMapFullScreen = false);
                    return false; // don't remove widget tree
                  },
                  background: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'RESTORING HUD...',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.8),
                        ),
                      ],
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF14171C) : Colors.white).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderColor, width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'SWIPE RIGHT TO RESTORE HUD  ➔',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ------------------------------------------------------------------------
    // STANDARD ATHLETIC HUD LAYOUT
    // ------------------------------------------------------------------------
    return Scaffold(
      backgroundColor: scaffoldBg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _resetInactivityTimer,
        onPanDown: (_) => _resetInactivityTimer(),
        child: Stack(
          children: [
            AnimatedOpacity(
              opacity: _isOledDimmed ? 0.35 : 1.0,
              duration: const Duration(milliseconds: 250),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top App Bar: Minimalist Back, Active Run Indicator & Map Layer Switch
                    Padding(
                      padding: const EdgeInsets.only(left: 14.0, right: 14.0, top: 4.0, bottom: 2.0),
                      child: Row(
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: Icon(Icons.arrow_back_ios_new, size: 16, color: textColor),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          // Active Run Status Indicator
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _isPaused ? Colors.amber : const Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isPaused ? Colors.amber : const Color(0xFF10B981)).withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${widget.activityType.toUpperCase()} #${widget.sessionId}',
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: textColor, letterSpacing: 0.8),
                                  ),
                                ],
                              ),
                              Text(
                                _isPaused ? 'PAUSED' : 'LIVE GPS ACTIVE',
                                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Map layer toggle
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: surfaceBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderColor),
                              ),
                              child: Icon(_showOsmTiles ? Icons.layers : Icons.layers_outlined, size: 15, color: textColor),
                            ),
                            tooltip: 'Toggle Vector / Satellite OSM',
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _showOsmTiles = !_showOsmTiles);
                            },
                          ),
                        ],
                      ),
                    ),

            // Flashing turn-back alarm banner
            if (_turnBackTriggered)
              GestureDetector(
                onLongPress: () {
                  HapticFeedback.selectionClick();
                  setState(() => _turnBackTriggered = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('TURN-BACK ALERT ACKNOWLEDGED')),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 14.0),
                  decoration: BoxDecoration(
                    color: _flashToggle ? const Color(0xFFDC2626) : const Color(0xFF991B1B),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'TURN BACK NOW (Hold to dismiss)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
              ),

            // Compact Reverse Countdown / Free Run Real-Time Prediction Hero Header Card
            Builder(
              builder: (context) {
                // Free Run Real-time Prediction Calculations
                if (widget.isFreeRun) {
                  final int outboundSec = _freeRunReturning ? _outboundFreeRunDuration.inSeconds : _elapsed.inSeconds;
                  final int predReturnSec = (outboundSec * (1.0 + (widget.safetyBufferPct / 100.0))).toInt();
                  final Duration predReturnDuration = Duration(seconds: predReturnSec);
                  final DateTime predictedEta = DateTime.now().add(predReturnDuration);
                  final int returnElapsedSec = max(0, _elapsed.inSeconds - _outboundFreeRunDuration.inSeconds);
                  final int remainingReturnSec = max(0, predReturnSec - returnElapsedSec);

                  if (!_freeRunReturning) {
                    // Free Run Outbound: Real-time Return ETA and Return Now Button
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 1.4),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Moving / Outbound Time
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.bolt_rounded, size: 13, color: accentColor),
                                      const SizedBox(width: 4),
                                      Text('FREE RUN (OUTBOUND)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: accentColor, letterSpacing: 0.6)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDuration(_elapsed),
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor),
                                  ),
                                  Text(
                                    'Total: ${_formatDuration(_totalElapsed)}',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                                  ),
                                ],
                              ),

                              // Real-Time Return Prediction ETA
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.auto_mode_rounded, size: 12, color: accentColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        'PREDICTED RETURN ETA',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: accentColor, letterSpacing: 0.5),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatEta(predictedEta),
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: accentColor),
                                  ),
                                  Text(
                                    'Est. Return: +${_formatDuration(predReturnDuration)}',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Prominent Interactive "RETURN NOW" Button
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              onPressed: () {
                                HapticFeedback.heavyImpact();
                                setState(() {
                                  _freeRunReturning = true;
                                  _outboundFreeRunDuration = _elapsed;
                                  _activeTargetDuration = Duration(seconds: (_elapsed.inSeconds * 2.0).toInt());
                                  _turnBackTriggered = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('RETURN INITIATED! Inbound countdown active.'),
                                    backgroundColor: Color(0xFF10B981),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.u_turn_left_rounded, size: 18),
                              label: const Text(
                                'TURN AROUND / RETURN NOW',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    // Free Run Inbound: Return Countdown
                    final double returnRatio = predReturnSec > 0 ? (returnElapsedSec / predReturnSec).clamp(0.0, 1.0) : 1.0;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF10B981), width: 1.6),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.flag_rounded, size: 12, color: Color(0xFF10B981)),
                                      const SizedBox(width: 4),
                                      Text('RETURN LEG (INBOUND)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: const Color(0xFF10B981), letterSpacing: 0.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDuration(_elapsed),
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor),
                                  ),
                                  Text(
                                    'Outbound: ${_formatDuration(_outboundFreeRunDuration)}',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF10B981)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'COUNTDOWN TO START',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: const Color(0xFF10B981), letterSpacing: 0.5),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDuration(Duration(seconds: remainingReturnSec)),
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                                  ),
                                  Text(
                                    'Return Limit: ${_formatDuration(predReturnDuration)}',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: returnRatio,
                              backgroundColor: textColor.withValues(alpha: 0.08),
                              color: const Color(0xFF10B981),
                              minHeight: 5.0,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                }

                // Standard Out-and-Back Dynamic Countdown Card
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _turnBackTriggered ? const Color(0xFFDC2626) : borderColor,
                      width: _turnBackTriggered ? 2.0 : 1.2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Workout Duration / Moving Time
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.timer_outlined, size: 12, color: textColor.withValues(alpha: 0.5)),
                                  const SizedBox(width: 4),
                                  Text('WORKOUT DURATION', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.5), letterSpacing: 0.5)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDuration(_totalElapsed),
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor),
                              ),
                              Text(
                                'Moving: ${_formatDuration(_elapsed)}',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                              ),
                            ],
                          ),

                          // Dedicated Reverse Countdown Timer (Smooth 1s updates)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _turnBackTriggered ? Icons.run_circle : Icons.hourglass_top_rounded,
                                    size: 12,
                                    color: _turnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _turnBackTriggered ? 'COUNTDOWN TO FINISH' : 'COUNTDOWN TO TURN BACK',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: _turnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _turnBackTriggered ? _formatDuration(Duration(seconds: remainingTotalSeconds)) : _formatDuration(Duration(seconds: remainingOutboundSeconds)),
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: _turnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                                ),
                              ),
                              Text(
                                _turnBackTriggered ? 'Target: ${widget.targetDuration.inMinutes}m' : 'Outbound: ${outboundLimitSeconds ~/ 60}m',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: outboundLimitSeconds > 0 ? min(1.0, _elapsed.inSeconds / outboundLimitSeconds) : 1.0,
                          backgroundColor: textColor.withValues(alpha: 0.08),
                          color: _turnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                          minHeight: 5.0,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Segmented Navigation Tab Control (Smooth explicit tab switcher)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    _buildTabPill(0, 'METRICS', textColor, surfaceBg, cardBg),
                    _buildTabPill(1, 'MAP', textColor, surfaceBg, cardBg),
                    _buildTabPill(2, 'CHART', textColor, surfaceBg, cardBg),
                    _buildTabPill(3, 'STATS', textColor, surfaceBg, cardBg),
                  ],
                ),
              ),
            ),

            // Main Content Area with NeverScrollableScrollPhysics (eliminates swipe conflict!)
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (idx) => setState(() => _currentPageIndex = idx),
                children: [
                  // TAB 0: Big Metric Grid + Mini Map
                  _buildMetricsTabPage(
                    textColor: textColor,
                    cardBg: cardBg,
                    borderColor: borderColor,
                    brightness: brightness,
                    accentColor: accentColor,
                  ),

                  // TAB 1: Full Interactive Map
                  _buildFullMapTabPage(brightness: brightness, borderColor: borderColor, accentColor: accentColor),

                  // TAB 2: Live Speed & Elevation Chart
                  _buildChartTabPage(textColor: textColor, cardBg: cardBg, borderColor: borderColor, accentColor: accentColor),

                  // TAB 3: Detailed Statistics
                  _buildDetailedStatisticsPage(textColor, cardBg, borderColor),
                ],
              ),
            ),

            // Dedicated 4x1 Modular Widget Space (3 Rectangular Glove-Friendly Buttons for Cycling)
            Modular4x1WidgetSpace(
              brightness: brightness,
              accentColor: accentColor,
              currentSpeedKmh: _currentSpeed * 3.6,
              currentAltitudeMeters: _altitude,
              heartRateBpm: _sensorData.heartRateBpm,
              cadenceRpm: _sensorData.cadenceRpm,
              elapsed: _elapsed,
            ),

            // Live GPS Coordinates & Searching Ticker Bar (Placed directly below music controls)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              color: isDark ? Colors.black.withValues(alpha: 0.3) : const Color(0xFFF1F5F9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _points.isEmpty
                          ? 'GPS: SEARCHING SATELLITES...'
                          : 'GPS: ${SettingsService.instance.formatCoordinates(_points.last.x, _points.last.y)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.0,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: _points.isEmpty ? Colors.amber : textColor.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  Text(
                    'ALT: ${_altitude.toStringAsFixed(0)}m • ACC: ±${_accuracy.toStringAsFixed(0)}m • ${_points.length}pts',
                    style: TextStyle(
                      fontSize: 9.0,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: textColor.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Action Bar
            _buildBottomControlBar(textColor, scaffoldBg, cardBg, borderColor, accentColor),
          ],
        ),
      ),
    ),
    if (PlatformService.isColabMode && P2pMeshService.instance.isActive)
      const MeshRadarHudWidget(),
    if (_isOledDimmed)
      Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.energy_savings_leaf, size: 14, color: Color(0xFF10B981)),
                SizedBox(width: 6),
                Text(
                  'OLED BATTERY SAVER (Tap to wake)',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
  ],
),
),
);
}

  Widget _buildTabPill(int idx, String title, Color textColor, Color surfaceBg, Color cardBg) {
    final active = _currentPageIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _pageController.animateToPage(idx, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? cardBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: active ? textColor : textColor.withValues(alpha: 0.5),
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 0: METRICS PAGE (2x2 Grid + Mini Map)
  // --------------------------------------------------------------------------
  Widget _buildMetricsTabPage({
    required Color textColor,
    required Color cardBg,
    required Color borderColor,
    required Brightness brightness,
    required Color accentColor,
  }) {
    final isDark = brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Single-Row Primary Metric Strip (Pace/Speed + Avg Speed + Total Distance)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.2),
            ),
            child: Row(
              children: [
                // Left: Pace / Current Speed + Avg Speed below
                Expanded(
                  flex: 5,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isSpeedMode = !_isSpeedMode);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.speed_rounded, size: 12, color: accentColor),
                            const SizedBox(width: 4),
                            Text(
                              _isSpeedMode ? 'SPEED [TAP]' : 'PACE [TAP]',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: textColor.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _formatSpeedOrPace(_currentSpeed),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _isSpeedMode
                              ? 'AVG: ${(_avgSpeed * 3.6).toStringAsFixed(1)} km/h'
                              : 'AVG: ${_formatSpeedOrPace(_avgSpeed)}',
                          style: TextStyle(
                            fontSize: 10.0,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  height: 44,
                  width: 1.0,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: borderColor,
                ),

                // Right: Total Distance
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.straighten_rounded, size: 12, color: Color(0xFF3B82F6)),
                          const SizedBox(width: 4),
                          Text(
                            'DISTANCE',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: textColor.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_distanceKm.toStringAsFixed(2)} km',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'ACTIVE MOVING',
                        style: TextStyle(
                          fontSize: 9.0,
                          fontWeight: FontWeight.w700,
                          color: textColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Mini Map Container (Expands into remaining vertical space)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OsmMapView(
                    points: _points,
                    showOsmTiles: _showOsmTiles,
                    brightness: brightness,
                  ),
                  // Floating Fullscreen Expand Pill
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isMapFullScreen = true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen_rounded, size: 16),
                            SizedBox(width: 3),
                            Text('EXPAND', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 1: FULL INTERACTIVE MAP
  // --------------------------------------------------------------------------
  Widget _buildFullMapTabPage({
    required Brightness brightness,
    required Color borderColor,
    required Color accentColor,
  }) {
    final isDark = brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OsmMapView(
              points: _points,
              showOsmTiles: _showOsmTiles,
              brightness: brightness,
            ),
            // Floating Fullscreen Expand Pill
            Positioned(
              top: 10,
              right: 10,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isMapFullScreen = true);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fullscreen_rounded, size: 18),
                      SizedBox(width: 4),
                      Text('FULLSCREEN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: LIVE SPEED & ELEVATION CHART
  // --------------------------------------------------------------------------
  Widget _buildChartTabPage({
    required Color textColor,
    required Color cardBg,
    required Color borderColor,
    required Color accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'REAL-TIME TELEMETRY PROFILE',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.6), letterSpacing: 0.8),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    final cur = SettingsService.instance.chartXAxis;
                    SettingsService.instance.setChartXAxis(cur == ChartXAxis.distance ? ChartXAxis.duration : ChartXAxis.distance);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      SettingsService.instance.chartXAxis == ChartXAxis.distance ? 'X: DIST (KM)' : 'X: TIME',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: accentColor),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TelemetryChart(
                samples: _chartSamples,
                plotByDuration: SettingsService.instance.chartXAxis == ChartXAxis.duration,
                speedColor: accentColor,
                elevationColor: const Color(0xFF10B981),
                textColor: textColor,
                gridColor: borderColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color textColor,
    required Color cardBg,
    required Color borderColor,
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: accentColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: textColor.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 3: DETAILED STATISTICS
  // --------------------------------------------------------------------------
  Widget _buildDetailedStatisticsPage(Color textColor, Color cardBg, Color borderColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsHeader('TIME BREAKDOWN', textColor),
                _buildStatsRow('Total Elapsed Time', _formatDuration(_totalElapsed), textColor),
                _buildStatsRow('Active Moving Time', _formatDuration(_elapsed), textColor),
                _buildStatsRow('Stationary Pause Time', _formatDuration(_totalElapsed - _elapsed), textColor),
                const SizedBox(height: 16),
                _buildStatsHeader('SPEED & VELOCITY', textColor),
                _buildStatsRow('Current Speed', '${(_currentSpeed * 3.6).toStringAsFixed(1)} km/h', textColor),
                _buildStatsRow('Average Moving Speed', _elapsed.inSeconds > 0 ? '${(_distanceKm / (_elapsed.inSeconds / 3600.0)).toStringAsFixed(1)} km/h' : '0.0 km/h', textColor),
                _buildStatsRow('Max Speed Recorded', '${(_maxSpeed * 3.6).toStringAsFixed(1)} km/h', textColor),
                const SizedBox(height: 16),
                _buildStatsHeader('ELEVATION GAIN & PROFILE', textColor),
                _buildStatsRow('Current Altitude', '${_altitude.toStringAsFixed(0)} m', textColor),
                _buildStatsRow('Total Ascent Gain', '+${_totalAscent.toStringAsFixed(0)} m', textColor),
                _buildStatsRow('Max Elevation Reached', '${_maxAltitude.toStringAsFixed(0)} m', textColor),
                _buildStatsRow('Min Elevation Recorded', '${_minAltitude == 99999.0 ? 0 : _minAltitude.toStringAsFixed(0)} m', textColor),
                const SizedBox(height: 16),
                _buildStatsHeader('GPS TELEMETRY ACCURACY', textColor),
                _buildStatsRow('Current Signal Accuracy', '±${_accuracy.toStringAsFixed(1)} m', textColor),
                _buildStatsRow('Total Clean Breadcrumbs', '${_points.length} points', textColor),
                _buildStatsRow('Sampling Rate Profile', '${SettingsService.instance.gpsSamplingRateMs} ms', textColor),
                const SizedBox(height: 16),
                _buildStatsHeader('OUT-AND-BACK TURNAROUND', textColor),
                _buildStatsRow('Target Session Goal', widget.isFreeRun ? 'Free Run (Dynamic)' : '${widget.targetDuration.inMinutes} minutes', textColor),
                _buildStatsRow('Safety Buffer Margin', '${widget.safetyBufferPct.toStringAsFixed(0)}%', textColor),
                _buildStatsRow('Turn-Around Status', _turnBackTriggered ? 'TRIGGERED (Returning)' : 'Outbound Tracking', textColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(String title, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: textColor.withValues(alpha: 0.15), width: 1.0)),
      ),
      child: Text(
        title,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.5), letterSpacing: 0.8),
      ),
    );
  }

  Widget _buildStatsRow(String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.8))),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // BOTTOM ACTION BAR (BLE Sensors, Pause / Resume / Finish)
  // --------------------------------------------------------------------------
  Widget _buildBottomControlBar(Color textColor, Color scaffoldBg, Color cardBg, Color borderColor, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Row(
        children: [
          // BLE Heart Rate & Cadence Indicator Pill
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              if (BleSensorService.instance.isConnected) {
                BleSensorService.instance.disconnect();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('BLE Sensors Disconnected')),
                );
              } else {
                BleSensorService.instance.startSimulation();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('BLE Sensors Connected (Polar H10 Simulated)')),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _sensorData.isConnected ? const Color(0xFFEF4444) : borderColor,
                  width: _sensorData.isConnected ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite,
                    size: 13,
                    color: _sensorData.isConnected ? const Color(0xFFEF4444) : textColor.withValues(alpha: 0.4),
                  ),
                  if (_sensorData.isConnected) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${_sensorData.heartRateBpm}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFFEF4444)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Pause / Resume Button
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 18),
              label: Text(
                _isPaused ? 'RESUME' : 'PAUSE',
                style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 12.5),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: textColor,
                side: BorderSide(color: borderColor, width: 1.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                if (_isPaused) {
                  _showResumeOptionsDialog();
                } else {
                  setState(() => _isPaused = true);
                }
              },
            ),
          ),
          const SizedBox(width: 8),

          // Finish & Save Button
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text(
                'FINISH',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 12.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                elevation: 0,
              ),
              onPressed: _showFinishConfirmDialog,
            ),
          ),
        ],
      ),
    );
  }

  void _showFinishConfirmDialog() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final bg = isDark ? const Color(0xFF14171C) : Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Finish Activity?', style: TextStyle(fontWeight: FontWeight.w900, color: color, letterSpacing: 0.8)),
          content: Text(
            'This will complete tracking and store your out-and-back session in the local SQLite database.',
            style: TextStyle(color: color.withValues(alpha: 0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CONTINUE', style: TextStyle(color: color.withValues(alpha: 0.6), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _finalizeSession();
              },
              child: const Text('FINISH & SAVE', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _finalizeSession() async {
    await PlatformService.instance.stopTracking();
    await DbService.instance.updateSessionStatus(widget.sessionId, 'completed');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Activity #${widget.sessionId} saved!')),
      );
      Navigator.pop(context);
    }
  }
}
