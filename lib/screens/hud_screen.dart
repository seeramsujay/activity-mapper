import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../services/platform_service.dart';
import '../services/rally_service.dart';
import '../widgets/osm_map_view.dart';

/// Ultra-high performance HUD Activity Screen.
///
/// Layout:
/// - Deterministic 2x3 Bike Computer Grid (OpenTracks / Track-Your-Walk inspired)
///   * Top Left: Big Pace/Speed (Auto-switching unit min/km vs km/h)
///   * Top Right: Remaining Countdown / 54% Target
///   * Mid Left: Total Distance
///   * Mid Right: Current Elevation / Total Gain
///   * Bottom Row: Compact Vector Breadcrumb Polyline (sub-millisecond CustomPainter)
/// - Encapsulated in RepaintBoundary for maximum frame-rate and lowest CPU/RAM consumption
/// - Tactile haptic feedback on state changes
class HudScreen extends StatefulWidget {
  /// The SQLite session ID of the current active run.
  final int sessionId;

  /// The total time allocated for the entire workout.
  final Duration targetDuration;

  /// The safety buffer percentage used for turn-back alert checks.
  final double safetyBufferPct;

  /// The activity type category (e.g. run, ride, kayak).
  final String activityType;

  /// Optional session ID of a past completed run to use as a guidance route.
  final int? referenceSessionId;

  /// Creates a new [HudScreen] instance.
  const HudScreen({
    super.key,
    required this.sessionId,
    required this.targetDuration,
    required this.safetyBufferPct,
    required this.activityType,
    this.referenceSessionId,
  });

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  // Telemetry list
  final List<Point<double>> _points = [];

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

  // Dynamic unit switching hysteresis
  bool _isSpeedMode = false;
  int _consecutiveSpeedTicks = 0;
  int _consecutivePaceTicks = 0;
  static const int _hysteresisWindowSeconds = 5;
  static const double _speedThresholdMps = 5.0; // 18 km/h

  // Tracking control state
  bool _isPaused = false;
  bool _turnBackTriggered = false;
  bool _confirmSaveState = false;
  int? _lastTimestamp;

  // Rally navigation state variables
  RallyNavigationEngine? _rallyEngine;
  RallyNavigationState? _rallyState;

  // Flashing turn-back indicator
  bool _flashToggle = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _isSpeedMode = widget.activityType == 'ride';

    _loadExistingData();
    _loadReferenceRoute();
    _startTimer();
    _startTelemetryStream();
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
        for (final p in storedPoints) {
          _points.add(Point(p['lat'] as double, p['lng'] as double));
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
        if (!_isPaused && _currentSpeed > 0.2) {
          _elapsed += const Duration(seconds: 1);
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

        if (speed > _maxSpeed) _maxSpeed = speed;
        if (alt < _minAltitude) _minAltitude = alt;
        if (alt > _maxAltitude) _maxAltitude = alt;

        if (_lastTimestamp != null && speed > 0.2) {
          final delta = timestamp - _lastTimestamp!;
          if (delta > 0 && delta < 15000) {
            _elapsed += Duration(milliseconds: delta);
          }
        }
        _lastTimestamp = timestamp;

        if (_elapsed.inSeconds > 0) {
          _avgSpeed = (_distanceKm * 1000) / _elapsed.inSeconds;
        }

        // Rally engine update
        if (_rallyEngine != null) {
          _rallyState = _rallyEngine!.updateNavigation(lat, lng);
        }

        // 54% Outbound Limit trigger
        final double outboundRatio = (100.0 - widget.safetyBufferPct) / 200.0;
        final int outboundLimitSeconds = (widget.targetDuration.inSeconds * outboundRatio).toInt();

        if (_elapsed.inSeconds >= outboundLimitSeconds && !_turnBackTriggered) {
          _turnBackTriggered = true;
          _startFlashingTimer();
          HapticFeedback.heavyImpact();
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
    final Color accentColor = const Color(0xFFFF5722);

    final double outboundRatio = (100.0 - widget.safetyBufferPct) / 200.0;
    final int outboundLimitSeconds = (widget.targetDuration.inSeconds * outboundRatio).toInt();
    final int remainingOutboundSeconds = max(0, outboundLimitSeconds - _elapsed.inSeconds);
    final int remainingTotalSeconds = max(0, widget.targetDuration.inSeconds - _elapsed.inSeconds);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top App Bar & Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new, size: 18, color: textColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isPaused ? Colors.amber : const Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${widget.activityType.toUpperCase()} #${widget.sessionId}',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textColor, letterSpacing: 0.8),
                          ),
                        ],
                      ),
                      Text(
                        _isPaused ? 'TRACKING PAUSED' : 'LIVE GPS RECORDING',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Map layer toggle
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Icon(_showOsmTiles ? Icons.layers : Icons.layers_outlined, size: 18, color: textColor),
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
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                  decoration: BoxDecoration(
                    color: _flashToggle ? const Color(0xFFDC2626) : const Color(0xFF991B1B),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'TURN BACK NOW (Hold to dismiss)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
              ),

            // Reverse Countdown & Duration Hero Header Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _turnBackTriggered ? const Color(0xFFDC2626) : borderColor,
                  width: _turnBackTriggered ? 2.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
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
                              Icon(Icons.timer_outlined, size: 13, color: textColor.withValues(alpha: 0.5)),
                              const SizedBox(width: 4),
                              Text('WORKOUT DURATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.5), letterSpacing: 0.5)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDuration(_totalElapsed),
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: textColor),
                          ),
                          Text(
                            'Moving: ${_formatDuration(_elapsed)}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),

                      // Dedicated Reverse Countdown Timer
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _turnBackTriggered ? Icons.run_circle : Icons.hourglass_top_rounded,
                                size: 13,
                                color: _turnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _turnBackTriggered ? 'RETURN LIMIT' : 'TIME TO TURN BACK',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: _turnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _turnBackTriggered ? _formatDuration(Duration(seconds: remainingTotalSeconds)) : _formatDuration(Duration(seconds: remainingOutboundSeconds)),
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: _turnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                            ),
                          ),
                          Text(
                            _turnBackTriggered ? 'Target: ${widget.targetDuration.inMinutes}m' : 'Outbound: ${outboundLimitSeconds ~/ 60}m',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Progress Bar with rounded caps
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: min(1.0, _elapsed.inSeconds / outboundLimitSeconds),
                      backgroundColor: textColor.withValues(alpha: 0.08),
                      color: _turnBackTriggered ? const Color(0xFFDC2626) : const Color(0xFF3B82F6),
                      minHeight: 6.0,
                    ),
                  ),
                ],
              ),
            ),

            // Rally Navigation Cue Panel
            if (_rallyState != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
                decoration: BoxDecoration(
                  color: _rallyState!.isOffRoute ? const Color(0xFFDC2626) : surfaceBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _rallyState!.isOffRoute ? const Color(0xFFDC2626) : borderColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getTurnIcon(_rallyState!.nextCue?.type),
                      size: 28,
                      color: _rallyState!.isOffRoute ? Colors.white : accentColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _rallyState!.isOffRoute ? 'OFF ROUTE!' : _rallyState!.nextCue?.description.toUpperCase() ?? 'FOLLOW ROUTE',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: _rallyState!.isOffRoute ? Colors.white : textColor,
                            ),
                          ),
                          Text(
                            _rallyState!.isOffRoute ? 'Return toward reference line' : 'In ${_rallyState!.distanceToNextCueMeters} meters',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _rallyState!.isOffRoute ? Colors.white.withValues(alpha: 0.8) : textColor.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Segmented Navigation Tab Control (Smooth, non-sensitive switching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    _buildTabPill(0, 'METRICS', textColor, surfaceBg, cardBg),
                    _buildTabPill(1, 'MAP & TRAIL', textColor, surfaceBg, cardBg),
                    _buildTabPill(2, 'STATS', textColor, surfaceBg, cardBg),
                  ],
                ),
              ),
            ),

            // Main Content Area with Clamping Scroll Physics
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const ClampingScrollPhysics(),
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
                  _buildFullMapTabPage(brightness: brightness, borderColor: borderColor),

                  // TAB 2: Detailed Statistics
                  _buildDetailedStatisticsPage(textColor, cardBg, borderColor),
                ],
              ),
            ),

            // Bottom Action Bar
            _buildBottomControlBar(textColor, scaffoldBg, cardBg, borderColor, accentColor),
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
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: active ? textColor : textColor.withValues(alpha: 0.5),
              letterSpacing: 0.5,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 2x2 Metric Grid
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // Column 1: Speed/Pace + Total Distance
                Expanded(
                  child: Column(
                    children: [
                      // Speed/Pace
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isSpeedMode = !_isSpeedMode);
                          },
                          child: _buildMetricTile(
                            label: _isSpeedMode ? 'SPEED (KM/H) [TAP]' : 'PACE (MIN/KM) [TAP]',
                            value: _formatSpeedOrPace(_currentSpeed),
                            icon: Icons.speed,
                            textColor: textColor,
                            cardBg: cardBg,
                            borderColor: borderColor,
                            accentColor: accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Distance
                      Expanded(
                        child: _buildMetricTile(
                          label: 'TOTAL DISTANCE',
                          value: '${_distanceKm.toStringAsFixed(2)} km',
                          icon: Icons.straighten,
                          textColor: textColor,
                          cardBg: cardBg,
                          borderColor: borderColor,
                          accentColor: const Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Column 2: Elevation + Average Pace
                Expanded(
                  child: Column(
                    children: [
                      // Elevation / Gain
                      Expanded(
                        child: _buildMetricTile(
                          label: 'ALTITUDE / GAIN',
                          value: '${_altitude.toStringAsFixed(0)}m (+${_totalAscent.toStringAsFixed(0)}m)',
                          icon: Icons.terrain,
                          textColor: textColor,
                          cardBg: cardBg,
                          borderColor: borderColor,
                          accentColor: const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Average Pace / Speed
                      Expanded(
                        child: _buildMetricTile(
                          label: _isSpeedMode ? 'AVG SPEED' : 'AVG PACE',
                          value: _isSpeedMode
                              ? '${(_avgSpeed * 3.6).toStringAsFixed(1)} km/h'
                              : _formatSpeedOrPace(_avgSpeed),
                          icon: Icons.trending_up,
                          textColor: textColor,
                          cardBg: cardBg,
                          borderColor: borderColor,
                          accentColor: const Color(0xFF8B5CF6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Mini Map Container
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
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
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _showOsmTiles ? 'OSM TILES' : 'OFFLINE VECTOR GPS',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: OsmMapView(
          points: _points,
          showOsmTiles: _showOsmTiles,
          brightness: brightness,
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
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: accentColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: textColor.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: DETAILED STATISTICS
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
                _buildStatsRow('Total Ascent (+)', '${_totalAscent.toStringAsFixed(1)} m', textColor),
                _buildStatsRow('Total Descent (-)', '${_totalDescent.toStringAsFixed(1)} m', textColor),
                _buildStatsRow('Max Elevation Height', _maxAltitude == -double.maxFinite ? '0.0 m' : '${_maxAltitude.toStringAsFixed(1)} m', textColor),
                _buildStatsRow('Min Elevation Height', _minAltitude == double.maxFinite ? '0.0 m' : '${_minAltitude.toStringAsFixed(1)} m', textColor),
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
  // BOTTOM ACTION BAR (Pause / Resume / Finish & Save)
  // --------------------------------------------------------------------------
  Widget _buildBottomControlBar(Color textColor, Color scaffoldBg, Color cardBg, Color borderColor, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Row(
        children: [
          // Pause / Resume Button
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 22),
              label: Text(
                _isPaused ? 'RESUME' : 'PAUSE',
                style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: textColor,
                side: BorderSide(color: borderColor, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                setState(() => _isPaused = !_isPaused);
              },
            ),
          ),
          const SizedBox(width: 12),

          // Finish & Save Button
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.stop_rounded, size: 22),
              label: const Text(
                'FINISH',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
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
