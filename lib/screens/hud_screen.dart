import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../services/platform_service.dart';
import '../services/gpx_service.dart';
import '../services/rally_service.dart';
import '../widgets/breadcrumb_painter.dart';
import '../widgets/osm_map_view.dart';

/// The active workout tracking screen displaying real-time metrics and HUD indicators.
///
/// Features:
/// - Real-time statistics tracking (speed, avg speed, max speed, distance, elevation, ascent/descent).
/// - 54% out-and-back turnaround alert notifications.
/// - Speed-to-pace hysteresis units switching.
/// - Interactive breadcrumb trail maps.
/// - Rally navigation roadbook overlays when guided by a past reference route.
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

/// State controller for [HudScreen], managing timers, sensors, and GPS streams.
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

  // Detailed Geo Tracker metrics
  double _maxSpeed = 0.0;
  double _minAltitude = double.maxFinite;
  double _maxAltitude = -double.maxFinite;
  double _totalAscent = 0.0;
  double _totalDescent = 0.0;
  double? _prevAltitude;

  // Multi-page HUD View
  final PageController _pageController = PageController();
  int _currentPageIndex = 0;
  bool _showOsmTiles = false; // toggleable reference map

  // Hysteresis configuration
  bool _isSpeedMode = false; // false = Pace, true = Speed
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

  // Animation for flashing warning bar
  bool _flashToggle = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _isSpeedMode = widget.activityType == 'ride'; // Start in Speed for cycling, Pace for runs

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
    } catch (e) {
      print("Failed to load reference route: $e");
    }
  }

  // Recover session coordinates from SQLite (WAL mode)
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
        _startFlashingAlert();
      }
    }
  }

  void _calculateSummaryMetrics(List<Map<String, dynamic>> rawPoints) {
    if (rawPoints.isEmpty) return;
    
    double totalSpeed = 0.0;
    double calculatedDist = 0.0;
    int activeMs = 0;

    for (int i = 0; i < rawPoints.length; i++) {
      final p = rawPoints[i];
      totalSpeed += p['speed'] as double;

      if (i > 0) {
        final prev = rawPoints[i - 1];
        calculatedDist += _distanceBetween(
          prev['lat'] as double,
          prev['lng'] as double,
          p['lat'] as double,
          p['lng'] as double,
        );
        
        final int diff = (p['timestamp'] as int) - (prev['timestamp'] as int);
        if (diff > 0 && diff < 15000 && (p['speed'] as double) > 0.2) {
          activeMs += diff;
        }
      }
    }

    _avgSpeed = totalSpeed / rawPoints.length;
    _distanceKm = calculatedDist;
    _altitude = rawPoints.last['altitude'] as double;
    _accuracy = rawPoints.last['accuracy'] as double;
    _elapsed = Duration(milliseconds: activeMs);
    _lastTimestamp = rawPoints.last['timestamp'] as int;
  }

  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
          cos(lat1 * p) * cos(lat2 * p) *
          (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // Haversine formula (km)
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) return;

      setState(() {
        _totalElapsed = _totalElapsed + const Duration(seconds: 1);
        if (_currentSpeed > 0.2) {
          _elapsed = _elapsed + const Duration(seconds: 1);
        }
      });

      // Turn-Back Threshold Calculation: (100 - B) / 200 of T
      final double outboundRatio = (100.0 - widget.safetyBufferPct) / 200.0;
      final int outboundLimitSeconds = (widget.targetDuration.inSeconds * outboundRatio).toInt();

      if (_elapsed.inSeconds >= outboundLimitSeconds && !_turnBackTriggered) {
        setState(() {
          _turnBackTriggered = true;
        });
        _startFlashingAlert();
      }
    });
  }

  void _startFlashingAlert() {
    _flashTimer?.cancel();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      setState(() {
        _flashToggle = !_flashToggle;
      });
    });
  }

  void _startTelemetryStream() {
    _telemetrySub = PlatformService.instance.telemetryStream.listen((event) {
      if (_isPaused) return;

      final double lat = event['lat'] as double;
      final double lng = event['lng'] as double;
      final double alt = event['altitude'] as double;
      final double acc = event['accuracy'] as double;
      final double speed = event['speed'] as double;
      final int timestamp = event['timestamp'] as int;

      setState(() {
        _points.add(Point(lat, lng));
        _currentSpeed = speed;
        _altitude = alt;
        _accuracy = acc;

        // Detailed Geo Tracker stats updates
        if (speed > _maxSpeed) {
          _maxSpeed = speed;
        }
        if (alt < _minAltitude) {
          _minAltitude = alt;
        }
        if (alt > _maxAltitude) {
          _maxAltitude = alt;
        }
        if (_prevAltitude != null) {
          final diff = alt - _prevAltitude!;
          if (diff > 0.5) {
            _totalAscent += diff;
          } else if (diff < -0.5) {
            _totalDescent += diff.abs();
          }
        }
        _prevAltitude = alt;

        // Synchronize _elapsed active duration with the precise coordinate timestamps from the DB
        if (_lastTimestamp != null) {
          final int diff = timestamp - _lastTimestamp!;
          if (diff > 0 && diff < 15000 && speed > 0.2) {
            _elapsed += Duration(milliseconds: diff);
          }
        }
        _lastTimestamp = timestamp;

        // Update rally engine navigation state (Haptics disabled)
        if (_rallyEngine != null) {
          final newState = _rallyEngine!.updateNavigation(lat, lng);
          _rallyState = newState;
        }

        // Cumulative stats update
        if (_points.length > 1) {
          final lastPoint = _points[_points.length - 2];
          _distanceKm += _distanceBetween(lastPoint.x, lastPoint.y, lat, lng);
        }

        // Rolling average update
        _avgSpeed = ((_avgSpeed * (_points.length - 1)) + speed) / _points.length;

        // 5-Second Speed/Pace Hysteresis Logic
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
    final String twoDigits(int n) => n.toString().padLeft(2, '0');
    final String minutes = twoDigits(d.inMinutes);
    final String seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // Convert speed (m/s) to Pace (min/km)
  String _formatSpeedOrPace(double mps) {
    if (mps <= 0.2) return _isSpeedMode ? '0.0' : '--:--';

    if (_isSpeedMode) {
      // Return Speed in km/h
      final double kmh = mps * 3.6;
      return kmh.toStringAsFixed(1);
    } else {
      // Return Pace in min/km
      final double secPerKm = 1000 / mps;
      final int min = secPerKm ~/ 60;
      final int sec = (secPerKm % 60).toInt();
      final String secStr = sec.toString().padLeft(2, '0');
      return '$min:$sec';
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

  Widget _buildTabDot(int idx, String name, Color primary) {
    final bool active = _currentPageIndex == idx;
    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(idx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: active ? primary : Colors.transparent, width: 1.5),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: active ? primary : primary.withOpacity(0.4),
          ),
        ),
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
        mainAxisAlignment: MainAxisAlignment.between,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: primaryColor.withOpacity(0.8))),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: primaryColor)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color primaryColor = brightness == Brightness.light ? Colors.black : Colors.white;
    final Color scaffoldBg = brightness == Brightness.light ? Colors.white : Colors.black;

    // Turnback threshold markers
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
                  setState(() {
                    _turnBackTriggered = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ALERT ACKNOWLEDGED')),
                  );
                },
                child: Container(
                  color: _flashToggle ? primaryColor : Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    '// TURN BACK NOW // (LONG PRESS TO DISMISS)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: _flashToggle ? scaffoldBg : Colors.white,
                    ),
                  ),
                ),
              ),

            // Rally Turn Navigation Panel
            if (_rallyState != null)
              Container(
                color: _rallyState!.isOffRoute ? Colors.red : primaryColor.withOpacity(0.08),
                padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: primaryColor, width: 2.0)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getTurnIcon(_rallyState!.nextCue?.type),
                      size: 40,
                      color: _rallyState!.isOffRoute ? Colors.white : primaryColor,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _rallyState!.isOffRoute ? 'OFF ROUTE!' : _rallyState!.nextCue?.description.toUpperCase() ?? 'FOLLOW ROUTE',
                            style: TextStyle(
                              fontSize: 20,
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

            // Swipable PageView Tab Indicators
            Padding(
              padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 12.0, bottom: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTabDot(0, 'HUD DASH', primaryColor),
                  const SizedBox(width: 16),
                  _buildTabDot(1, 'DETAILS', primaryColor),
                  const SizedBox(width: 16),
                  _buildTabDot(2, 'ROADBOOK', primaryColor),
                ],
              ),
            ),

            // Top Status Bar (Target & Timer details)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.between,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MOVING TIME', style: TextStyle(fontSize: 12, color: primaryColor.withOpacity(0.6))),
                      Text(
                        _formatDuration(_elapsed),
                        style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: primaryColor),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _turnBackTriggered ? 'RETURN TIMER' : 'OUTBOUND LIMIT',
                        style: TextStyle(fontSize: 12, color: primaryColor.withOpacity(0.6)),
                      ),
                      Text(
                        _turnBackTriggered
                            ? _formatDuration(Duration(seconds: max(0, widget.targetDuration.inSeconds - _elapsed.inSeconds)))
                            : _formatDuration(Duration(seconds: remainingSeconds)),
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: _turnBackTriggered ? Colors.red : primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Multi-page HUD View
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) {
                  setState(() {
                    _currentPageIndex = idx;
                  });
                },
                children: [
                  // Page 0: Main HUD Dash
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Outbound ratio progress bar (Garmin style)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                        child: LinearProgressIndicator(
                          value: min(1.0, _elapsed.inSeconds / outboundLimitSeconds),
                          backgroundColor: primaryColor.withOpacity(0.1),
                          color: _turnBackTriggered ? Colors.red : primaryColor,
                          minHeight: 8.0,
                        ),
                      ),

                      // Canvas Vector Map View or On-demand OSM View
                      Expanded(
                        flex: 3,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 6.0),
                          decoration: Border.all(color: primaryColor, width: 2.5),
                          child: ClipRect(
                            child: Stack(
                              children: [
                                OsmMapView(
                                  points: _points,
                                  showOsmTiles: _showOsmTiles,
                                  brightness: brightness,
                                ),
                                // Top Left: Map Label
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: Container(
                                    color: scaffoldBg,
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      _showOsmTiles ? 'MAP: ONLINE OSM' : 'MAP: OFFLINE VECTOR',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor.withOpacity(0.5)),
                                    ),
                                  ),
                                ),
                                // Top Right: Toggle Map Button
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    margin: const EdgeInsets.all(4.0),
                                    color: scaffoldBg.withOpacity(0.8),
                                    child: IconButton(
                                      icon: Icon(_showOsmTiles ? Icons.layers : Icons.layers_clear, color: primaryColor),
                                      tooltip: 'Toggle Reference Map On/Off',
                                      onPressed: () {
                                        setState(() {
                                          _showOsmTiles = !_showOsmTiles;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Bottom: Dashboard Grid
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: GridView.count(
                            crossAxisCount: 2,
                            childAspectRatio: 2.2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isSpeedMode = !_isSpeedMode;
                                  });
                                },
                                child: _buildMetricBox(
                                  _isSpeedMode ? 'SPEED (KM/H) [TAP]' : 'PACE (MIN/KM) [TAP]',
                                  _formatSpeedOrPace(_currentSpeed),
                                  primaryColor,
                                ),
                              ),
                              _buildMetricBox('DISTANCE (KM)', _distanceKm.toStringAsFixed(2), primaryColor),
                              _buildMetricBox('AVG SPEED (KM/H)', (_avgSpeed * 3.6).toStringAsFixed(1), primaryColor),
                              _buildMetricBox('ALTITUDE (M)', _altitude.toStringAsFixed(0), primaryColor),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Page 1: Geo Tracker Style Detailed Statistics
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '// DETAILED TRACK DESCRIPTION',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: primaryColor, letterSpacing: 1.0),
                        ),
                        const SizedBox(height: 16),
                        
                        _buildStatsHeader('TIME METRICS', primaryColor),
                        _buildStatsRow('Total Elapsed Time', _formatDuration(_totalElapsed), primaryColor),
                        _buildStatsRow('Active Moving Time', _formatDuration(_elapsed), primaryColor),
                        _buildStatsRow('Stationary Break Time', _formatDuration(_totalElapsed - _elapsed), primaryColor),
                        const SizedBox(height: 16),

                        _buildStatsHeader('SPEED METRICS', primaryColor),
                        _buildStatsRow('Current Speed', '${(_currentSpeed * 3.6).toStringAsFixed(1)} km/h', primaryColor),
                        _buildStatsRow(
                          'Average Moving Speed', 
                          _elapsed.inSeconds > 0 ? '${(_distanceKm / (_elapsed.inSeconds / 3600.0)).toStringAsFixed(1)} km/h' : '0.0 km/h',
                          primaryColor,
                        ),
                        _buildStatsRow('Max Speed Recorded', '${(_maxSpeed * 3.6).toStringAsFixed(1)} km/h', primaryColor),
                        _buildStatsRow(
                          'Average Total Speed', 
                          _totalElapsed.inSeconds > 0 ? '${(_distanceKm / (_totalElapsed.inSeconds / 3600.0)).toStringAsFixed(1)} km/h' : '0.0 km/h',
                          primaryColor,
                        ),
                        const SizedBox(height: 16),

                        _buildStatsHeader('ELEVATION PROFILE', primaryColor),
                        _buildStatsRow('Altitude Ascent (+)', '${_totalAscent.toStringAsFixed(1)} m', primaryColor),
                        _buildStatsRow('Altitude Descent (-)', '${_totalDescent.toStringAsFixed(1)} m', primaryColor),
                        _buildStatsRow('Max Elevation Height', _maxAltitude == -double.maxFinite ? '0.0 m' : '${_maxAltitude.toStringAsFixed(1)} m', primaryColor),
                        _buildStatsRow('Min Elevation Height', _minAltitude == double.maxFinite ? '0.0 m' : '${_minAltitude.toStringAsFixed(1)} m', primaryColor),
                      ],
                    ),
                  ),

                  // Page 2: Rally Navigation Roadbook
                  SingleChildScrollView(
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
                            final bool isPassed = _rallyState != null && 
                                _rallyState!.nextCue != null &&
                                cue.distanceKm < (_rallyEngine!.totalReferenceDistanceKm - (_rallyState!.distanceToNextCueMeters / 1000.0));
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12.0),
                              padding: const EdgeInsets.all(14.0),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isPassed ? primaryColor.withOpacity(0.2) : primaryColor,
                                  width: 1.5,
                                ),
                                color: isPassed ? Colors.transparent : primaryColor.withOpacity(0.02),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _getTurnIcon(cue.type),
                                    size: 32,
                                    color: isPassed ? primaryColor.withOpacity(0.3) : primaryColor,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cue.description.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            color: isPassed ? primaryColor.withOpacity(0.4) : primaryColor,
                                          ),
                                        ),
                                        Text(
                                          'AT POSITION: ${cue.distanceKm.toStringAsFixed(2)} KM',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: primaryColor.withOpacity(0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Secure Control Buttons (Physical Row)
            Padding(
              padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 20.0, top: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        side: BorderSide(color: primaryColor, width: 2.5),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        padding: const EdgeInsets.symmetric(vertical: 18.0),
                      ),
                      onPressed: _togglePause,
                      child: Text(
                        _isPaused ? 'RESUME RUN' : 'PAUSE RUN',
                        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: scaffoldBg,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        padding: const EdgeInsets.symmetric(vertical: 18.0),
                        elevation: 0,
                      ),
                      onPressed: _confirmStopSession,
                      child: const Text(
                        'STOP & SAVE',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox(String label, String value, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      decoration: BoxDecoration(
        border: Border.all(color: primaryColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor.withOpacity(0.5))),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: primaryColor, height: 1.0),
          ),
        ],
      ),
    );
  }

  void _togglePause() async {
    final dbHelper = DbService.instance;
    setState(() {
      _isPaused = !_isPaused;
    });

    if (_isPaused) {
      await dbHelper.updateSessionStatus(widget.sessionId, 'paused');
      await PlatformService.instance.stopTracking();
    } else {
      await dbHelper.updateSessionStatus(widget.sessionId, 'active');
      await PlatformService.instance.startTracking(
        sessionId: widget.sessionId,
        activityType: widget.activityType,
        targetDurationSeconds: widget.targetDuration.inSeconds,
        safetyBufferPct: widget.safetyBufferPct,
        gpsIntervalMs: 5000,
      );
    }
  }

  void _confirmStopSession() {
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
                Navigator.pop(context); // Close dialog
                _finishSession();
              },
              child: const Text('STOP & SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _finishSession() async {
    final dbHelper = DbService.instance;
    final gpxService = GpxService.instance;

    // 1. Stop background tracking
    await PlatformService.instance.stopTracking();

    // 2. Set database state to completed
    await dbHelper.updateSessionStatus(widget.sessionId, 'completed');

    // 3. Export GPX file natively
    final activityName = '${widget.activityType.toUpperCase()} - Out and Back';
    final exportedFile = await gpxService.saveGpxFile(widget.sessionId, activityName);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('GPX file exported to:\n${exportedFile.path}'),
          duration: const Duration(seconds: 6),
        ),
      );

      // Return back to setup configuration screen
      Navigator.pushReplacementNamed(context, '/');
    }
  }
}
