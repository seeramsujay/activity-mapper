import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../services/platform_service.dart';
import '../services/export_service.dart';
import '../services/rally_service.dart';
import '../widgets/breadcrumb_painter.dart';
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

      final double lat = (data['lat'] as num).toDouble();
      final double lng = (data['lng'] as num).toDouble();
      final double alt = (data['alt'] as num).toDouble();
      final double acc = (data['acc'] as num).toDouble();
      final double speed = (data['speed'] as num).toDouble();
      final int timestamp = (data['time'] as num).toInt();

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
    final Color primaryColor = brightness == Brightness.light ? Colors.black : Colors.white;
    final Color scaffoldBg = brightness == Brightness.light ? Colors.white : Colors.black;

    final double outboundRatio = (100.0 - widget.safetyBufferPct) / 200.0;
    final int outboundLimitSeconds = (widget.targetDuration.inSeconds * outboundRatio).toInt();
    final int remainingSeconds = max(0, outboundLimitSeconds - _elapsed.inSeconds);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Flashing turn-back alarm header
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
                  color: _flashToggle ? primaryColor : Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    '// TURN BACK NOW // (LONG PRESS TO DISMISS)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: _flashToggle ? scaffoldBg : Colors.white,
                    ),
                  ),
                ),
              ),

            // Rally Turn Navigation Panel
            if (_rallyState != null)
              Container(
                color: _rallyState!.isOffRoute ? Colors.red : primaryColor.withOpacity(0.06),
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: primaryColor, width: 2.0)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getTurnIcon(_rallyState!.nextCue?.type),
                      size: 36,
                      color: _rallyState!.isOffRoute ? Colors.white : primaryColor,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _rallyState!.isOffRoute ? 'OFF ROUTE!' : _rallyState!.nextCue?.description.toUpperCase() ?? 'FOLLOW ROUTE',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _rallyState!.isOffRoute ? Colors.white : primaryColor,
                            ),
                          ),
                          Text(
                            _rallyState!.isOffRoute ? 'DRIFTED FROM PAST TRACK' : 'IN ${_rallyState!.distanceToNextCueMeters} METERS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _rallyState!.isOffRoute ? Colors.white.withOpacity(0.8) : primaryColor.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Top Tab Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTabButton(0, 'HUD GRID', primaryColor),
                  _buildTabButton(1, 'STATISTICS', primaryColor),
                  _buildTabButton(2, 'ROADBOOK', primaryColor),
                  IconButton(
                    icon: Icon(_showOsmTiles ? Icons.layers : Icons.layers_outlined, color: primaryColor, size: 20),
                    tooltip: 'Toggle OSM/Vector',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showOsmTiles = !_showOsmTiles);
                    },
                  ),
                ],
              ),
            ),

            // Main Content Area
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPageIndex = idx),
                children: [
                  // PAGE 0: OpenTracks / Bike Computer 2x3 Grid wrapped in RepaintBoundary
                  RepaintBoundary(
                    child: _buildBikeComputerGrid(
                      primaryColor: primaryColor,
                      scaffoldBg: scaffoldBg,
                      brightness: brightness,
                      outboundLimitSeconds: outboundLimitSeconds,
                      remainingSeconds: remainingSeconds,
                    ),
                  ),

                  // PAGE 1: Detailed GeoTracker statistics
                  _buildDetailedStatisticsPage(primaryColor),

                  // PAGE 2: Rally Roadbook
                  _buildRoadbookPage(primaryColor),
                ],
              ),
            ),

            // Floating Bottom Action Control Bar
            _buildBottomControlBar(primaryColor, scaffoldBg),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int idx, String title, Color primary) {
    final active = _currentPageIndex == idx;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _pageController.animateToPage(idx, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: active ? primary : Colors.transparent, width: 1.5),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: active ? primary : primary.withOpacity(0.4),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // DETERMINISTIC 2x3 BIKE COMPUTER / OPENTRACKS HUD GRID
  // --------------------------------------------------------------------------
  Widget _buildBikeComputerGrid({
    required Color primaryColor,
    required Color scaffoldBg,
    required Brightness brightness,
    required int outboundLimitSeconds,
    required int remainingSeconds,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress bar for 54% outbound split
          LinearProgressIndicator(
            value: min(1.0, _elapsed.inSeconds / outboundLimitSeconds),
            backgroundColor: primaryColor.withOpacity(0.1),
            color: _turnBackTriggered ? Colors.red : primaryColor,
            minHeight: 6.0,
          ),
          const SizedBox(height: 10),

          // 2x2 Top/Mid Metric Grid
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // Left Column: Big Pace/Speed + Total Distance
                Expanded(
                  child: Column(
                    children: [
                      // Top Left: Speed/Pace
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isSpeedMode = !_isSpeedMode);
                          },
                          child: _buildGridCell(
                            label: _isSpeedMode ? 'SPEED (KM/H) [TAP]' : 'PACE (MIN/KM) [TAP]',
                            value: _formatSpeedOrPace(_currentSpeed),
                            primaryColor: primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Mid Left: Total Distance
                      Expanded(
                        child: _buildGridCell(
                          label: 'TOTAL DISTANCE',
                          value: '${_distanceKm.toStringAsFixed(2)} km',
                          primaryColor: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Right Column: 54% Target Countdown + Current Elevation/Gain
                Expanded(
                  child: Column(
                    children: [
                      // Top Right: Target Countdown
                      Expanded(
                        child: _buildGridCell(
                          label: _turnBackTriggered ? 'RETURN TIMER' : 'OUTBOUND LIMIT (54%)',
                          value: _turnBackTriggered
                              ? _formatDuration(Duration(seconds: max(0, widget.targetDuration.inSeconds - _elapsed.inSeconds)))
                              : _formatDuration(Duration(seconds: remainingSeconds)),
                          primaryColor: _turnBackTriggered ? Colors.red : primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Mid Right: Elevation & Gain
                      Expanded(
                        child: _buildGridCell(
                          label: 'ELEVATION / GAIN',
                          value: '${_altitude.toStringAsFixed(0)}m (+${_totalAscent.toStringAsFixed(0)}m)',
                          primaryColor: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Bottom Row: Sub-millisecond Vector Breadcrumb Polyline (<5MB RAM)
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: primaryColor, width: 2.0),
              ),
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OsmMapView(
                      points: _points,
                      showOsmTiles: _showOsmTiles,
                      brightness: brightness,
                    ),
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        color: scaffoldBg,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          _showOsmTiles ? 'OSM TILES' : 'OFFLINE VECTOR (<5MB RAM)',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: primaryColor.withOpacity(0.5)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCell({
    required String label,
    required String value,
    required Color primaryColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border.all(color: primaryColor, width: 2.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: primaryColor.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // PAGE 1: DETAILED STATISTICS
  // --------------------------------------------------------------------------
  Widget _buildDetailedStatisticsPage(Color primaryColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '// DETAILED TELEMETRY',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: primaryColor, letterSpacing: 1.0),
          ),
          const SizedBox(height: 16),
          _buildStatsHeader('TIME METRICS', primaryColor),
          _buildStatsRow('Total Elapsed Time', _formatDuration(_totalElapsed), primaryColor),
          _buildStatsRow('Active Moving Time', _formatDuration(_elapsed), primaryColor),
          _buildStatsRow('Stationary Break Time', _formatDuration(_totalElapsed - _elapsed), primaryColor),
          const SizedBox(height: 16),
          _buildStatsHeader('SPEED & VELOCITY', primaryColor),
          _buildStatsRow('Current Speed', '${(_currentSpeed * 3.6).toStringAsFixed(1)} km/h', primaryColor),
          _buildStatsRow('Average Moving Speed', _elapsed.inSeconds > 0 ? '${(_distanceKm / (_elapsed.inSeconds / 3600.0)).toStringAsFixed(1)} km/h' : '0.0 km/h', primaryColor),
          _buildStatsRow('Max Speed Recorded', '${(_maxSpeed * 3.6).toStringAsFixed(1)} km/h', primaryColor),
          const SizedBox(height: 16),
          _buildStatsHeader('ELEVATION PROFILE', primaryColor),
          _buildStatsRow('Total Ascent (+)', '${_totalAscent.toStringAsFixed(1)} m', primaryColor),
          _buildStatsRow('Total Descent (-)', '${_totalDescent.toStringAsFixed(1)} m', primaryColor),
          _buildStatsRow('Max Elevation Height', _maxAltitude == -double.maxFinite ? '0.0 m' : '${_maxAltitude.toStringAsFixed(1)} m', primaryColor),
          _buildStatsRow('Min Elevation Height', _minAltitude == double.maxFinite ? '0.0 m' : '${_minAltitude.toStringAsFixed(1)} m', primaryColor),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(String title, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: primaryColor.withOpacity(0.3), width: 1.0)),
      ),
      child: Text(
        title,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor.withOpacity(0.6), letterSpacing: 0.8),
      ),
    );
  }

  Widget _buildStatsRow(String label, String value, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: primaryColor.withOpacity(0.8))),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: primaryColor)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // PAGE 2: ROADBOOK
  // --------------------------------------------------------------------------
  Widget _buildRoadbookPage(Color primaryColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '// RALLY ROADBOOK CUES',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: primaryColor, letterSpacing: 1.0),
          ),
          const SizedBox(height: 16),
          if (_rallyEngine == null || _rallyEngine!.cues.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Text(
                  'NO REFERENCE ROUTE SELECTED\n\nChoose a past route during setup to generate roadbook cues.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: primaryColor.withOpacity(0.5), height: 1.4),
                ),
              ),
            )
          else
            ..._rallyEngine!.cues.map((cue) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  border: Border.all(color: primaryColor, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(_getTurnIcon(cue.type), size: 28, color: primaryColor),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cue.description.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
                          Text('KM ${cue.distanceKm.toStringAsFixed(2)}', style: TextStyle(fontSize: 11, color: primaryColor.withOpacity(0.6))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // BOTTOM ACTION BAR (Pause / Resume / Finish & Save)
  // --------------------------------------------------------------------------
  Widget _buildBottomControlBar(Color primaryColor, Color scaffoldBg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: primaryColor.withOpacity(0.2), width: 1.0)),
      ),
      child: Row(
        children: [
          // Pause / Resume Button
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 20),
              label: Text(
                _isPaused ? 'RESUME' : 'PAUSE',
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor, width: 2.0),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                setState(() => _isPaused = !_isPaused);
              },
            ),
          ),
          const SizedBox(width: 10),

          // Finish & Save Button
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.stop, size: 20),
              label: const Text(
                'FINISH',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: scaffoldBg,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(vertical: 14),
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
    final bg = isDark ? Colors.black : Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text('Finish Activity?', style: TextStyle(fontWeight: FontWeight.w900, color: color, letterSpacing: 1.0)),
          content: Text(
            'This will complete tracking, mark the session completed in the local database, and allow exporting multi-format ZIP packages.',
            style: TextStyle(color: color),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CONTINUE RUN', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: bg,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _finalizeSession();
              },
              child: const Text('FINISH & SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
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
        SnackBar(content: Text('Session #${widget.sessionId} completed successfully!')),
      );
      Navigator.pushReplacementNamed(context, '/history');
    }
  }
}
