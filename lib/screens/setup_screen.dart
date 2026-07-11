import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/platform_service.dart';
import 'hud_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String _activityType = 'run';
  int _targetDurationMinutes = 90;
  double _safetyBufferPct = 8.0;
  int _gpsIntervalMs = 5000;

  bool _isLaunching = false;
  List<Map<String, dynamic>> _completedSessions = [];
  int? _selectedReferenceSessionId;

  @override
  void initState() {
    super.initState();
    _loadCompletedSessions();
  }

  Future<void> _loadCompletedSessions() async {
    final dbHelper = DbService.instance;
    final sessions = await dbHelper.getSessions();
    setState(() {
      _completedSessions = sessions.where((s) => s['status'] == 'completed').toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color textColor = brightness == Brightness.light ? Colors.black : Colors.white;
    final Color cardBorderColor = brightness == Brightness.light ? Colors.black : Colors.grey[800]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('// TURNBACK', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.history_outlined, color: textColor),
            tooltip: 'View Session History',
            onPressed: () {
              Navigator.pushNamed(context, '/history');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Plan Your Session',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: textColor),
              ),
              const SizedBox(height: 6),
              Text(
                'Set parameters for fatigue-adjusted alerts.',
                style: TextStyle(fontSize: 16, color: textColor.withOpacity(0.6), height: 1.2),
              ),
              const SizedBox(height: 28),

              // Configuration Box
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: cardBorderColor, width: 2.5),
                      borderRadius: BorderRadius.zero, // Garmin style square cards
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Activity Type
                        _buildLabel('Activity Type', _activityType.toUpperCase()),
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
                            if (val != null) setState(() => _activityType = val);
                          },
                        ),
                        const SizedBox(height: 24),

                        // Target Duration
                        _buildLabel('Target Duration', '$_targetDurationMinutes min'),
                        Slider(
                          value: _targetDurationMinutes.toDouble(),
                          min: 10,
                          max: 240,
                          divisions: 46,
                          activeColor: textColor,
                          inactiveColor: textColor.withOpacity(0.2),
                          onChanged: (val) {
                            setState(() => _targetDurationMinutes = val.toInt());
                          },
                        ),
                        const SizedBox(height: 16),

                        // Safety Buffer
                        _buildLabel('Fatigue Safety Buffer', '${_safetyBufferPct.toStringAsFixed(1)}%'),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.between,
                          children: [
                            Text('Fresh (0%)', style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
                            Text('Tired (20%)', style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
                          ],
                        ),
                        Slider(
                          value: _safetyBufferPct,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          activeColor: textColor,
                          inactiveColor: textColor.withOpacity(0.2),
                          onChanged: (val) {
                            setState(() => _safetyBufferPct = val);
                          },
                        ),
                        const SizedBox(height: 16),

                        // GPS Query Interval
                        _buildLabel('GPS Sampling Rate', _gpsIntervalMs == 1000 ? '1s (High Accuracy)' : _gpsIntervalMs == 5000 ? '5s (Balanced)' : '15s (Power Save)'),
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
                            if (val != null) setState(() => _gpsIntervalMs = val);
                          },
                        ),
                        const SizedBox(height: 24),

                        // Reference Route Guidance
                        _buildLabel('Reference Route Guidance', _selectedReferenceSessionId != null ? 'Active' : 'None'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          value: _selectedReferenceSessionId,
                          dropdownColor: brightness == Brightness.light ? Colors.white : Colors.black,
                          decoration: InputDecoration(
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 2.0)),
                          ),
                          hint: const Text('SELECT A PAST RUN TO FOLLOW (OPTIONAL)'),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('NONE - FREE TRACKING')),
                            ..._completedSessions.map((s) {
                              final date = DateTime.fromMillisecondsSinceEpoch(s['start_time'] as int);
                              final type = (s['activity_type'] as String).toUpperCase();
                              final duration = (s['target_duration'] as int) ~/ 60;
                              return DropdownMenuItem<int?>(
                                value: s['id'] as int,
                                child: Text('$type - ${date.month}/${date.day} (${duration}m)'),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedReferenceSessionId = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Start button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: textColor,
                  foregroundColor: brightness == Brightness.light ? Colors.white : Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18.0),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  side: BorderSide(color: textColor, width: 2.0),
                ),
                onPressed: _isLaunching ? null : _launchSession,
                child: _isLaunching
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'START TRACKING SESSION',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String title, String value) {
    final Color textColor = Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textColor)),
      ],
    );
  }

  Future<void> _launchSession() async {
    setState(() => _isLaunching = true);

    try {
      final dbHelper = DbService.instance;
      
      // 1. Insert session into Shared SQLite DB
      final int sessionId = await dbHelper.createSession(
        activityType: _activityType,
        targetDurationSeconds: _targetDurationMinutes * 60,
        safetyBufferPct: _safetyBufferPct,
      );

      // 2. Start Native Telemetry Background Service (Kotlin FGS)
      final bool startSuccess = await PlatformService.instance.startTracking(
        sessionId: sessionId,
        activityType: _activityType,
        targetDurationSeconds: _targetDurationMinutes * 60,
        safetyBufferPct: _safetyBufferPct,
        gpsIntervalMs: _gpsIntervalMs,
      );

      if (startSuccess && mounted) {
        // Navigate directly to HUD Screen
        Navigator.pushReplacement(
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
        );
      } else {
        throw Exception("Failed to boot native tracking service channel.");
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
}
