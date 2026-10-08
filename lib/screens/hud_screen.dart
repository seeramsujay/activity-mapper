import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'workout_summary_screen.dart';
import '../services/adaptive_pacing_service.dart';
import '../services/ble_sensor_service.dart';
import '../services/db_service.dart';
import '../services/exercise_stats_service.dart';
import '../services/gpx_service.dart';
import '../services/platform_service.dart';
import '../services/rally_service.dart';
import '../services/settings_service.dart';
import '../services/p2p_mesh_service.dart';
import '../widgets/musicolet_4x1_widget.dart';
import '../widgets/interactive_telemetry_graph.dart';
import '../widgets/vector_map_view.dart';
import '../widgets/telemetry_chart.dart';
import '../widgets/mesh_radar_widget.dart';
import '../widgets/colab_comms_sheet.dart';

/// Ultra-high performance HUD Activity Screen.
class HudScreen extends StatefulWidget {
  final int sessionId;
  final Duration targetDuration;
  final double safetyBufferPct;
  final String activityType;
  final bool isFreeRun;
  final int? referenceSessionId;
  final double fatigueGamma;
  final bool hasReturnElevationPenalty;
  final bool initialGoogleMapsMode;

  const HudScreen({
    super.key,
    required this.sessionId,
    required this.targetDuration,
    required this.safetyBufferPct,
    required this.activityType,
    this.isFreeRun = false,
    this.referenceSessionId,
    this.fatigueGamma = 0.08,
    this.hasReturnElevationPenalty = false,
    this.initialGoogleMapsMode = false,
  });

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  // Google Maps Co-Navigation Passive Piggyback Mode
  late bool _googleMapsMode;

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

  // Dynamic unit switching hysteresis
  bool _isSpeedMode = false;
  int _consecutiveSpeedTicks = 0;
  int _consecutivePaceTicks = 0;
  int _adaptiveHysteresisTicks = 5;
  static const double _speedThresholdMps = 5.0; // 18 km/h

  double get _liveCalories => ExerciseStatsService.calculateCaloriesBurnt(
    activityType: widget.activityType,
    distanceKm: _distanceKm,
    movingDuration: _elapsed,
    elevationGainMeters: _totalAscent,
  );

  bool get _isMotorVehicle {
    final type = widget.activityType.toLowerCase();
    return type.contains('vehicle') || type.contains('drive') || type.contains('car') || type.contains('motor');
  }

  // Tracking control state
  bool _isPaused = false;
  bool _turnBackTriggered = false;
  bool _userDismissedTurnBack = false;
  bool _arrivedAtFinishLine = false;
  bool _freeRunReturning = false;

  // Rally navigation state variables
  RallyNavigationEngine? _rallyEngine;

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
    if (SettingsService.instance.isOled) {
      _inactivityTimer = Timer(const Duration(seconds: 25), () {
        if (mounted && !_isPaused && SettingsService.instance.isOled) {
          setState(() => _isOledDimmed = true);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _activeTargetDuration = widget.targetDuration;
    _googleMapsMode = widget.initialGoogleMapsMode;
    _startTime = DateTime.now();
    _isSpeedMode = widget.activityType == 'ride';

    PlatformService.instance.setPowerSaveDisplay(true);

    _sensorData = BleSensorService.instance.currentData;
    _bleSensorSub = BleSensorService.instance.sensorStream.listen((data) {
      if (mounted) {
        setState(() => _sensorData = data);
      }
    });

    _resetInactivityTimer();
    _loadExistingData();
    _loadReferenceRoute();
    _initRollingMedianHysteresis();
    _startTimer();
    _startTelemetryStream();
  }

  Future<void> _toggleGoogleMapsMode() async {
    HapticFeedback.heavyImpact();
    final newMode = !_googleMapsMode;
    setState(() => _googleMapsMode = newMode);
    await PlatformService.instance.setGoogleMapsMode(newMode);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                newMode ? Icons.battery_charging_full_rounded : Icons.gps_fixed_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      newMode ? 'GOOGLE MAPS ECO ACTIVE' : 'STANDALONE GPS ACTIVE',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                    Text(
                      newMode
                          ? 'Passively sampling Google Maps GPS stream (Battery Saver)'
                          : 'TurnBack directly powering high-precision GNSS',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: newMode ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _initRollingMedianHysteresis() async {
    try {
      final medianDist = await DbService.instance.getRollingMedianDistance(widget.activityType);
      if (mounted) {
        final double targetDist = (widget.targetDuration.inMinutes / 60.0) * (_isSpeedMode ? 20.0 : 10.0);
        final double ratio = medianDist > 0 ? targetDist / medianDist : 1.0;
        setState(() {
          _adaptiveHysteresisTicks = AdaptivePacingService.calculateAdaptiveHysteresisTicks(
            activityType: widget.activityType,
            ratio: ratio,
          );
        });
      }
    } catch (_) {}
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

  double get _returnPathRemainingKm {
    if (_points.length < 2) return 0.0;
    double dist = 0.0;
    for (int i = 0; i < _points.length - 1; i++) {
      dist += _distanceBetween(_points[i].x, _points[i].y, _points[i + 1].x, _points[i + 1].y);
    }
    return dist;
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
        if (!widget.isFreeRun && !_turnBackTriggered && !_userDismissedTurnBack && _activeTargetDuration.inSeconds > 0) {
          final int outboundLimitSeconds = AdaptivePacingService.calculateAsymmetricOutboundLimitSeconds(
            targetDurationSeconds: _activeTargetDuration.inSeconds,
            safetyBufferPct: widget.safetyBufferPct,
            isMotorVehicle: _isMotorVehicle,
          );
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

        if (_elapsed.inSeconds > 0) {
          _avgSpeed = (_distanceKm * 1000) / _elapsed.inSeconds;
        }

        // Rally engine update
        if (_rallyEngine != null) {
          _rallyEngine!.updateNavigation(lat, lng);
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
        if (!widget.isFreeRun && !_turnBackTriggered && !_userDismissedTurnBack && _activeTargetDuration.inSeconds > 0) {
          final int outboundLimitSeconds = AdaptivePacingService.calculateAsymmetricOutboundLimitSeconds(
            targetDurationSeconds: _activeTargetDuration.inSeconds,
            safetyBufferPct: widget.safetyBufferPct,
            isMotorVehicle: _isMotorVehicle,
          );
          if (_elapsed.inSeconds >= outboundLimitSeconds) {
            _turnBackTriggered = true;
            _startFlashingTimer();
            PlatformService.instance.triggerTurnBackAlert(activityType: widget.activityType);
          }
        }

        // Finish Line Arrival Check (Within 30 meters of Start Point after turning back)
        if ((_freeRunReturning || _userDismissedTurnBack) && !_arrivedAtFinishLine && _points.length > 15 && _distanceKm > 0.15) {
          final startPoint = _points.first;
          final distToStartKm = _distanceBetween(startPoint.x, startPoint.y, lat, lng);
          if (distToStartKm <= 0.03) { // 30 meters
            _arrivedAtFinishLine = true;
            _flashTimer?.cancel();
            PlatformService.instance.triggerTurnBackAlert(activityType: widget.activityType);
            _showFinishLineArrivalDialog();
          }
        }

        // Speed/Pace Hysteresis (Scaled by rolling median distance)
        final hysteresisTicks = _adaptiveHysteresisTicks;
        if (_isSpeedMode) {
          if (speed < _speedThresholdMps) {
            _consecutivePaceTicks++;
            _consecutiveSpeedTicks = 0;
          } else {
            _consecutivePaceTicks = 0;
          }
          if (_consecutivePaceTicks >= hysteresisTicks) {
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
          if (_consecutiveSpeedTicks >= hysteresisTicks) {
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

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final bool isDark = brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF111827);
    final Color scaffoldBg = isDark ? const Color(0xFF0F1115) : const Color(0xFFF9FAFB);
    final Color cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final Color borderColor = isDark ? const Color(0xFF2D333F) : const Color(0xFFE5E7EB);
    final Color accentColor = SettingsService.instance.accentColor.color;

    final int outboundLimitSeconds = AdaptivePacingService.calculateAsymmetricOutboundLimitSeconds(
      targetDurationSeconds: _activeTargetDuration.inSeconds,
      safetyBufferPct: widget.safetyBufferPct,
      isMotorVehicle: _isMotorVehicle,
    );
    final int remainingOutboundSeconds = max(0, outboundLimitSeconds - _elapsed.inSeconds);
    final int remainingTotalSeconds = max(0, _activeTargetDuration.inSeconds - _elapsed.inSeconds);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _showExitConfirmDialog();
      },
      child: Scaffold(
        backgroundColor: scaffoldBg,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _resetInactivityTimer,
          onPanDown: (_) => _resetInactivityTimer(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Fullscreen Vector Tile Map Canvas (>90% screen area)
              VectorMapView(
                points: _points,
                brightness: brightness,
                isReturning: _freeRunReturning,
                returnPathRemainingKm: _returnPathRemainingKm,
              ),

              // 2. Top 1-Line Glassmorphism Status Strip
              _buildTopGlassmorphismStrip(
                textColor: textColor,
                cardBg: cardBg,
                borderColor: borderColor,
                accentColor: accentColor,
                isDark: isDark,
                remainingOutboundSeconds: remainingOutboundSeconds,
                remainingTotalSeconds: remainingTotalSeconds,
              ),

              // 3. Flashing Turn-Back Banner (if triggered)
              if (_turnBackTriggered)
                _buildFlashingTurnBackBanner(),

              // 4. OLED Battery Saver Pill (if dimmed)
              if (_isOledDimmed)
                _buildOledSaverOverlay(),

              // 5. Tactical Colab Radar (if active)
              if (PlatformService.isColabMode && P2pMeshService.instance.isActive)
                MeshRadarHudWidget(
                  currentLat: _points.isNotEmpty ? _points.last.x : 0.0,
                  currentLng: _points.isNotEmpty ? _points.last.y : 0.0,
                ),

              // 6. Collapsed Floating Bottom Control Bar (Heavy-Glove >=68dp touch targets)
              _buildCollapsedBottomControlBar(
                textColor: textColor,
                cardBg: cardBg,
                borderColor: borderColor,
                accentColor: accentColor,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopGlassmorphismStrip({
    required Color textColor,
    required Color cardBg,
    required Color borderColor,
    required Color accentColor,
    required bool isDark,
    required int remainingOutboundSeconds,
    required int remainingTotalSeconds,
  }) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF14171C) : Colors.white).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(Icons.arrow_back_ios_new, size: 18, color: textColor),
                tooltip: 'Exit Session',
                onPressed: _showExitConfirmDialog,
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
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
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: textColor, letterSpacing: 0.6),
                      ),
                    ],
                  ),
                  Text(
                    _isPaused ? 'PAUSED' : (_googleMapsMode ? 'G-MAPS ECO' : 'LIVE GPS'),
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: _googleMapsMode ? const Color(0xFF10B981) : textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleGoogleMapsMode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _googleMapsMode
                        ? const Color(0xFF10B981).withValues(alpha: 0.2)
                        : (isDark ? Colors.white10 : Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _googleMapsMode ? const Color(0xFF10B981) : borderColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _googleMapsMode ? Icons.battery_charging_full_rounded : Icons.navigation_outlined,
                        size: 11,
                        color: _googleMapsMode ? const Color(0xFF10B981) : textColor.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _googleMapsMode ? 'G-MAPS' : 'GPS',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: _googleMapsMode ? const Color(0xFF10B981) : textColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isSpeedMode = !_isSpeedMode);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatSpeedOrPace(_currentSpeed),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor),
                        ),
                        Text(
                          _isSpeedMode ? ' km/h' : ' /km',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_distanceKm.toStringAsFixed(2)} km',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: accentColor),
                        ),
                      ],
                    ),
                    Text(
                      _turnBackTriggered
                          ? 'Return: ${_formatDuration(Duration(seconds: remainingTotalSeconds))}'
                          : 'Turn Back: ${_formatDuration(Duration(seconds: remainingOutboundSeconds))}',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: _turnBackTriggered ? const Color(0xFFDC2626) : textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openStatsAndGraphsModal(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF97316), size: 14),
                      const SizedBox(width: 3),
                      Text(
                        '${_liveCalories.toStringAsFixed(0)} kcal',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFFF97316)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlashingTurnBackBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 58,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _flashTimer?.cancel();
          setState(() {
            _turnBackTriggered = false;
            _userDismissedTurnBack = true;
            _freeRunReturning = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('TURN-BACK ACKNOWLEDGED - RETURN ROUTE GUIDE ACTIVE'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
          decoration: BoxDecoration(
            color: _flashToggle ? const Color(0xFFDC2626) : const Color(0xFF991B1B),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDC2626).withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'TURN BACK NOW (Tap to Acknowledge)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOledSaverOverlay() {
    return Positioned(
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
    );
  }

  Widget _buildCollapsedBottomControlBar({
    required Color textColor,
    required Color cardBg,
    required Color borderColor,
    required Color accentColor,
    required bool isDark,
  }) {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF14171C) : Colors.white).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // 1. STATS & GRAPHS Button (68dp x 68dp touch target)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _openStatsAndGraphsModal(context);
                  },
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart_rounded, color: accentColor, size: 24),
                        const SizedBox(height: 2),
                        Text(
                          'STATS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: accentColor, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 2. Google Maps Passive Piggyback Toggle (Heavy-Glove >=68dp touch target)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _toggleGoogleMapsMode,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _googleMapsMode
                          ? const Color(0xFF10B981).withValues(alpha: 0.18)
                          : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _googleMapsMode ? const Color(0xFF10B981) : borderColor,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _googleMapsMode ? Icons.battery_charging_full_rounded : Icons.navigation_outlined,
                          color: _googleMapsMode ? const Color(0xFF10B981) : textColor.withValues(alpha: 0.7),
                          size: 24,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _googleMapsMode ? 'G-MAPS' : 'GPS',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: _googleMapsMode ? const Color(0xFF10B981) : textColor.withValues(alpha: 0.7),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 2. Colab COMMS Button (if Colab active, 68dp touch target)
              if (PlatformService.isColabMode && P2pMeshService.instance.isActive) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      ColabCommsSheet.show(
                        context,
                        currentLat: _points.isNotEmpty ? _points.last.x : 0.0,
                        currentLng: _points.isNotEmpty ? _points.last.y : 0.0,
                      );
                    },
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF10B981)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_rounded, color: Color(0xFF10B981), size: 24),
                          SizedBox(height: 2),
                          Text(
                            'COMMS',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF10B981), letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // 3. Pause / Resume Button (68dp min height)
              Expanded(
                child: SizedBox(
                  height: 68,
                  child: OutlinedButton.icon(
                    icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 26),
                    label: Text(
                      _isPaused ? 'RESUME' : 'PAUSE',
                      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: borderColor, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              ),
              const SizedBox(width: 8),

              // 4. Finish Button (68dp min height)
              Expanded(
                child: SizedBox(
                  height: 68,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.stop_rounded, size: 26),
                    label: const Text(
                      'FINISH',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      elevation: 0,
                    ),
                    onPressed: _showFinishConfirmDialog,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openStatsAndGraphsModal(BuildContext context) {
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (sheetContext, scrollController) {
            return StatefulBuilder(
              builder: (sheetContext, setModalState) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: borderColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.insights_rounded, color: accentColor, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EXERCISE TELEMETRY & STATS',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: textColor,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                Text(
                                  '${widget.activityType.toUpperCase()} #${widget.sessionId} • LIVE TELEMETRY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: textColor.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Calories Burnt Card (Hero)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFF97316).withValues(alpha: 0.22),
                            surfaceBg,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.4), width: 1.4),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF97316),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TOTAL CALORIES BURNT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: textColor.withValues(alpha: 0.6),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_liveCalories.toStringAsFixed(0)} kcal',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  'Est. MET: ${ExerciseStatsService.estimateMet(activityType: widget.activityType, speedKmh: _currentSpeed * 3.6).toStringAsFixed(1)} • Burn Rate: ${_elapsed.inSeconds > 0 ? (_liveCalories / (_elapsed.inSeconds / 3600.0)).toStringAsFixed(0) : "0"} kcal/h',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF97316),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // BLE Sensor Status Chips
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: surfaceBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 20),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('HEART RATE', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.5))),
                                    Text(
                                      _sensorData.isConnected && _sensorData.heartRateBpm > 0 ? '${_sensorData.heartRateBpm} BPM' : '-- BPM',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: surfaceBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.directions_bike_rounded, color: Color(0xFF06B6D4), size: 20),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('CADENCE', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.5))),
                                    Text(
                                      _sensorData.isConnected && _sensorData.cadenceRpm > 0 ? '${_sensorData.cadenceRpm} RPM' : '-- RPM',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Interactive Telemetry Graph with Independent Toggles
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'LIVE TELEMETRY PROFILES',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.8),
                              ),
                              Text(
                                '${_chartSamples.length} samples',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 220,
                            child: InteractiveTelemetryGraph(
                              points: _chartSamples.map((s) => GraphPoint(
                                distanceKm: s.distanceKm,
                                elapsedSeconds: s.elapsedSeconds,
                                speedKmh: s.speedKmh,
                                altitudeMeters: s.altitudeMeters,
                                heartRateBpm: _sensorData.heartRateBpm > 0 ? _sensorData.heartRateBpm : null,
                                cadenceRpm: _sensorData.cadenceRpm > 0 ? _sensorData.cadenceRpm : null,
                              )).toList(),
                              brightness: Theme.of(context).brightness,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Exercise Breakdown Grid
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DETAILED METRICS BREAKDOWN',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 12),
                          _buildModalMetricRow('Total Distance', '${_distanceKm.toStringAsFixed(2)} km', textColor),
                          _buildModalMetricRow('Moving Time', _formatDuration(_elapsed), textColor),
                          _buildModalMetricRow('Total Elapsed Time', _formatDuration(_totalElapsed), textColor),
                          _buildModalMetricRow('Current Speed', '${(_currentSpeed * 3.6).toStringAsFixed(1)} km/h', textColor),
                          _buildModalMetricRow('Average Moving Speed', '${(_avgSpeed * 3.6).toStringAsFixed(1)} km/h', textColor),
                          _buildModalMetricRow('Max Speed Recorded', '${(_maxSpeed * 3.6).toStringAsFixed(1)} km/h', textColor),
                          _buildModalMetricRow('Current Altitude', '${_altitude.toStringAsFixed(0)} m', textColor),
                          _buildModalMetricRow('Total Ascent Gain', '+${_totalAscent.toStringAsFixed(0)} m', textColor),
                          _buildModalMetricRow('Total Descent Loss', '-${_totalDescent.toStringAsFixed(0)} m', textColor),
                          _buildModalMetricRow('Max Elevation Reached', '${_maxAltitude <= -9999 ? 0 : _maxAltitude.toStringAsFixed(0)} m', textColor),
                          _buildModalMetricRow('GPS Accuracy', '±${_accuracy.toStringAsFixed(1)} m', textColor),
                          _buildModalMetricRow('Clean Breadcrumbs', '${_points.length} pts', textColor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Modular 4x1 Widget / Music Controller
                    Modular4x1WidgetSpace(
                      brightness: Theme.of(context).brightness,
                      accentColor: accentColor,
                      currentSpeedKmh: _currentSpeed * 3.6,
                      currentAltitudeMeters: _altitude,
                      heartRateBpm: _sensorData.heartRateBpm,
                      cadenceRpm: _sensorData.cadenceRpm,
                      elapsed: _elapsed,
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildModalMetricRow(String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6)),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: textColor),
          ),
        ],
      ),
    );
  }

  void _showFinishLineArrivalDialog() {
    HapticFeedback.heavyImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final bg = isDark ? const Color(0xFF14171C) : Colors.white;
    final accentColor = SettingsService.instance.accentColor.color;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'FINISH LINE REACHED!',
                  style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Congratulations! You have completed your out-and-back route and returned to your starting origin.',
                style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 13),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('DISTANCE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color.withValues(alpha: 0.5))),
                        Text('${_distanceKm.toStringAsFixed(2)} km', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: accentColor)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('DURATION', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color.withValues(alpha: 0.5))),
                        Text(_formatDuration(_elapsed), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('KEEP RECORDING', style: TextStyle(color: color.withValues(alpha: 0.6), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
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

  void _showExitConfirmDialog() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final bg = isDark ? const Color(0xFF14171C) : Colors.white;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Exit Activity Session?', style: TextStyle(fontWeight: FontWeight.w900, color: color, letterSpacing: 0.8)),
          content: Text(
            'Do you want to finish & save your activity to history, or leave it running in the background?',
            style: TextStyle(color: color.withValues(alpha: 0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                Navigator.pop(context); // Exit HUD screen, keeping tracking active in background
              },
              child: Text('KEEP RUNNING', style: TextStyle(color: color.withValues(alpha: 0.6), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(dialogContext); // Close dialog
                await _finalizeSession(); // Finalize, save to SQLite DB, and exit cleanly
              },
              child: const Text('FINISH & SAVE', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
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
    final activityName = '${widget.activityType.toUpperCase()} - Out and Back';
    final file = await GpxService.instance.saveGpxFile(widget.sessionId, activityName);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Activity #${widget.sessionId} finished & saved: ${file.path.split('/').last}'),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WorkoutSummaryScreen(
            sessionId: widget.sessionId,
            activityType: widget.activityType,
          ),
        ),
      );
    }
  }
}
