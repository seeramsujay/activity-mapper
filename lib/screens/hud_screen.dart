import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/platform_service.dart';
import '../services/gpx_service.dart';
import '../widgets/breadcrumb_painter.dart';

class HudScreen extends StatefulWidget {
  final int sessionId;
  final Duration targetDuration;
  final double safetyBufferPct;
  final String activityType;

  const HudScreen({
    super.key,
    required this.sessionId,
    required this.targetDuration,
    required this.safetyBufferPct,
    required this.activityType,
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
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  StreamSubscription? _telemetrySub;

  // Hysteresis configuration
  bool _isSpeedMode = false; // false = Pace, true = Speed
  int _consecutiveSpeedTicks = 0;
  int _consecutivePaceTicks = 0;
  static const int _hysteresisWindowSeconds = 5;
  static const double _speedThresholdMps = 5.0; // 18 km/h

  // Tracking control state
  bool _isPaused = false;
  bool _turnBackTriggered = false;
  int? _lastTimestamp;

  // Animation for flashing warning bar
  bool _flashToggle = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _isSpeedMode = widget.activityType == 'ride'; // Start in Speed for cycling, Pace for runs

    _loadExistingData();
    _startTimer();
    _startTelemetryStream();
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

      // Increment _elapsed by 1 second only if user is active (not taking a stationary break)
      if (_currentSpeed > 0.2) {
        setState(() {
          _elapsed = _elapsed + const Duration(seconds: 1);
        });
      }

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

        // Synchronize _elapsed active duration with the precise coordinate timestamps from the DB
        if (_lastTimestamp != null) {
          final int diff = timestamp - _lastTimestamp!;
          if (diff > 0 && diff < 15000 && speed > 0.2) {
            _elapsed += Duration(milliseconds: diff);
          }
        }
        _lastTimestamp = timestamp;

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
              Container(
                color: _flashToggle ? primaryColor : Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  '// TURN BACK NOW //',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: _flashToggle ? scaffoldBg : Colors.white,
                  ),
                ),
              ),

            // Top Status Bar (Target & Timer details)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.between,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ELAPSED', style: TextStyle(fontSize: 12, color: primaryColor.withOpacity(0.6))),
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

            // Center: Canvas Vector Map View
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 6.0),
                decoration: Border.all(color: primaryColor, width: 2.5),
                child: ClipRect(
                  child: CustomPaint(
                    painter: BreadcrumbPainter(points: _points, brightness: brightness),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        color: scaffoldBg,
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'MAP: OFFLINE VECTOR (BREADCRUMB)',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor.withOpacity(0.5)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom: Sunlight-Readable Dashboard Grid
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
                    _buildMetricBox(
                      _isSpeedMode ? 'SPEED (KM/H)' : 'PACE (MIN/KM)',
                      _formatSpeedOrPace(_currentSpeed),
                      primaryColor,
                    ),
                    _buildMetricBox('DISTANCE (KM)', _distanceKm.toStringAsFixed(2), primaryColor),
                    _buildMetricBox('AVG SPEED (KM/H)', (_avgSpeed * 3.6).toStringAsFixed(1), primaryColor),
                    _buildMetricBox('ALTITUDE (M)', _altitude.toStringAsFixed(0), primaryColor),
                  ],
                ),
              ),
            ),

            // Control Buttons
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
                        'STOP & EXPORT',
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
