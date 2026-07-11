import 'dart:math';
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../widgets/breadcrumb_painter.dart';

/// Screen widget that provides tools to edit and chop GPS track paths.
///
/// Supports cropping coordinate ranges via visual range sliders, splitting into
/// N-equal segments, or dividing into segments based on time duration chunks.
class EditorScreen extends StatefulWidget {
  /// The SQLite session ID of the activity to edit.
  final int sessionId;

  /// The activity type category (e.g. run, ride, kayak).
  final String activityType;

  /// Creates a new [EditorScreen] instance.
  const EditorScreen({
    super.key,
    required this.sessionId,
    required this.activityType,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

/// State controller for the [EditorScreen], managing tabs and coordinates.
class _EditorScreenState extends State<EditorScreen> with SingleTickerProviderStateMixin {

  late TabController _tabController;
  List<Map<String, dynamic>> _rawPoints = [];
  bool _isLoading = true;

  // Cropping variables
  RangeValues _cropRange = const RangeValues(0, 1);
  int _startIndex = 0;
  int _endIndex = 0;

  // N-parts chopper variables
  int _partsCount = 2;

  // Time chopper variables
  int _chunkMinutes = 10;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    final points = await DbService.instance.getPoints(widget.sessionId);
    setState(() {
      _rawPoints = points;
      _isLoading = false;
      if (points.isNotEmpty) {
        _cropRange = RangeValues(0, (points.length - 1).toDouble());
        _startIndex = 0;
        _endIndex = points.length - 1;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
          cos(lat1 * p) * cos(lat2 * p) *
          (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // km
  }

  double _calculateDistanceInRange(int start, int end) {
    if (_rawPoints.isEmpty || start >= end) return 0.0;
    double dist = 0.0;
    for (int i = start; i < end; i++) {
      dist += _distanceBetween(
        _rawPoints[i]['lat'] as double,
        _rawPoints[i]['lng'] as double,
        _rawPoints[i + 1]['lat'] as double,
        _rawPoints[i + 1]['lng'] as double,
      );
    }
    return dist;
  }

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white;
    final Color scaffoldBg = Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('// TRIP EDITOR', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: textColor,
          unselectedLabelColor: textColor.withOpacity(0.5),
          indicatorColor: textColor,
          indicatorWeight: 3.0,
          tabs: const [
            Tab(text: 'CROP'),
            Tab(text: 'N-CHOP'),
            Tab(text: 'TIME-CHOP'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: textColor))
          : _rawPoints.isEmpty
              ? _buildEmptyState(textColor)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCropTab(textColor, scaffoldBg),
                    _buildNChopTab(textColor, scaffoldBg),
                    _buildTimeChopTab(textColor, scaffoldBg),
                  ],
                ),
    );
  }

  Widget _buildEmptyState(Color textColor) {
    return Center(
      child: Text('No coordinates found for this trip.', style: TextStyle(color: textColor)),
    );
  }

  // ----------------------------------------------------------------------------
  // TAB 1: Visual Crop Trip
  // ----------------------------------------------------------------------------
  Widget _buildCropTab(Color textColor, Color scaffoldBg) {
    final croppedPoints = _rawPoints.sublist(_startIndex, _endIndex + 1);
    final mapPoints = croppedPoints.map((p) => Point(p['lat'] as double, p['lng'] as double)).toList();
    
    final double distance = _calculateDistanceInRange(_startIndex, _endIndex);
    final int startMs = _rawPoints[_startIndex]['timestamp'] as int;
    final int endMs = _rawPoints[_endIndex]['timestamp'] as int;
    final int durationMs = endMs - startMs;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Visual path preview
          Expanded(
            child: Container(
              decoration: Border.all(color: textColor, width: 2.0),
              child: ClipRect(
                child: CustomPaint(
                  painter: BreadcrumbPainter(
                    points: mapPoints,
                    brightness: Theme.of(context).brightness,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Statistics panel
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPanelStat('CROPPED DISTANCE', '${distance.toStringAsFixed(2)} km', textColor),
              _buildPanelStat('CROPPED TIME', _formatDuration(durationMs), textColor),
            ],
          ),
          const SizedBox(height: 16),

          // Range Slider
          RangeSlider(
            values: _cropRange,
            min: 0,
            max: (_rawPoints.length - 1).toDouble(),
            activeColor: textColor,
            inactiveColor: textColor.withOpacity(0.2),
            onChanged: (val) {
              setState(() {
                _cropRange = val;
                _startIndex = val.start.round();
                _endIndex = val.end.round();
              });
            },
          ),
          const SizedBox(height: 12),

          // Action Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: textColor,
              foregroundColor: scaffoldBg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => _executeCrop(croppedPoints, startMs, endMs),
            child: const Text('SAVE CROPPED TRIP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------------
  // TAB 2: N-Parts Chopper
  // ----------------------------------------------------------------------------
  Widget _buildNChopTab(Color textColor, Color scaffoldBg) {
    final int totalPoints = _rawPoints.length;
    final int pointsPerSegment = (totalPoints / _partsCount).ceil();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Chop into N Equal Parts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 8),
          Text(
            'This splits the coordinate array into N parts of equal length and saves each as a separate activity.',
            style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.6), height: 1.3),
          ),
          const SizedBox(height: 28),

          Row(
            children: [
              Text('Number of Parts (N):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _partsCount,
                  dropdownColor: scaffoldBg,
                  decoration: InputDecoration(
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
                  ),
                  items: List.generate(9, (index) => index + 2).map((n) {
                    return DropdownMenuItem(value: n, child: Text('$n Parts'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _partsCount = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Live calculation summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: textColor, width: 1.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CHOP PREVIEW:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5))),
                const SizedBox(height: 8),
                Text('• Total Coordinates: $totalPoints pts', style: TextStyle(color: textColor)),
                Text('• Segments Created: $_partsCount', style: TextStyle(color: textColor)),
                Text('• Points per Segment: ~$pointsPerSegment pts', style: TextStyle(color: textColor)),
              ],
            ),
          ),
          const Spacer(),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: textColor,
              foregroundColor: scaffoldBg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _executeNSplit,
            child: const Text('EXECUTE N-CHOP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------------
  // TAB 3: Time-Duration Chopper
  // ----------------------------------------------------------------------------
  Widget _buildTimeChopTab(Color textColor, Color scaffoldBg) {
    final int startMs = _rawPoints.first['timestamp'] as int;
    final int endMs = _rawPoints.last['timestamp'] as int;
    final int totalDurationMs = endMs - startMs;
    final double chunkMs = _chunkMinutes * 60 * 1000.0;
    final int chunksCount = (totalDurationMs / chunkMs).ceil();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Split into Time Durations', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 8),
          Text(
            'Divides the activity log into pieces based on time intervals. Every segment represents a specified duration block.',
            style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.6), height: 1.3),
          ),
          const SizedBox(height: 28),

          Row(
            children: [
              Text('Duration per Chunk:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _chunkMinutes,
                  dropdownColor: scaffoldBg,
                  decoration: InputDecoration(
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
                  ),
                  items: [5, 10, 15, 20, 30, 45, 60].map((m) {
                    return DropdownMenuItem(value: m, child: Text('$m Minutes'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _chunkMinutes = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Live calculation summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: textColor, width: 1.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SPLIT PREVIEW:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5))),
                const SizedBox(height: 8),
                Text('• Total Trip Duration: ${_formatDuration(totalDurationMs)}', style: TextStyle(color: textColor)),
                Text('• Target Chunk Size: $_chunkMinutes minutes', style: TextStyle(color: textColor)),
                Text('• Segments Created: $chunksCount', style: TextStyle(color: textColor)),
              ],
            ),
          ),
          const Spacer(),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: textColor,
              foregroundColor: scaffoldBg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _executeTimeSplit,
            child: const Text('EXECUTE TIME-CHOP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelStat(String label, String value, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
      ],
    );
  }

  // ----------------------------------------------------------------------------
  // Execution Logic
  // ----------------------------------------------------------------------------
  Future<void> _executeCrop(List<Map<String, dynamic>> points, int startTime, int endTime) async {
    final dbHelper = DbService.instance;
    
    // Create new cropped activity log
    await dbHelper.cloneSessionWithPoints(
      activityType: '${widget.activityType} (Cropped)',
      targetDuration: points.length, // use coordinate count or fallback duration
      safetyBuffer: 8.0,
      startTime: startTime,
      endTime: endTime,
      status: 'completed',
      points: points,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cropped trip saved as a new activity log!')),
      );
      Navigator.pop(context, true); // Return success to reload list
    }
  }

  Future<void> _executeNSplit() async {
    final dbHelper = DbService.instance;
    final int totalPoints = _rawPoints.length;
    final int pointsPerSegment = (totalPoints / _partsCount).ceil();

    for (int i = 0; i < _partsCount; i++) {
      final int start = i * pointsPerSegment;
      final int end = min(start + pointsPerSegment, totalPoints);
      
      if (start >= totalPoints) break;

      final segmentPoints = _rawPoints.sublist(start, end);
      if (segmentPoints.isEmpty) continue;

      final startMs = segmentPoints.first['timestamp'] as int;
      final endMs = segmentPoints.last['timestamp'] as int;

      await dbHelper.cloneSessionWithPoints(
        activityType: '${widget.activityType} [Part ${i + 1}/$_partsCount]',
        targetDuration: segmentPoints.length,
        safetyBuffer: 8.0,
        startTime: startMs,
        endTime: endMs,
        status: 'completed',
        points: segmentPoints,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Split successfully into $_partsCount activities!')),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _executeTimeSplit() async {
    final dbHelper = DbService.instance;
    final int startMs = _rawPoints.first['timestamp'] as int;
    final double chunkMs = _chunkMinutes * 60 * 1000.0;
    
    int index = 0;
    int chunkIdx = 1;

    while (index < _rawPoints.length) {
      final double segmentStartMs = startMs + (chunkIdx - 1) * chunkMs;
      final double segmentEndMs = segmentStartMs + chunkMs;

      final List<Map<String, dynamic>> segmentPoints = [];
      while (index < _rawPoints.length) {
        final pointTime = _rawPoints[index]['timestamp'] as int;
        if (pointTime >= segmentStartMs && pointTime < segmentEndMs) {
          segmentPoints.add(_rawPoints[index]);
          index++;
        } else if (pointTime >= segmentEndMs) {
          // Exceeds this segment window. Move to next chunk loop.
          break;
        } else {
          // Timestamp anomaly, skip
          index++;
        }
      }

      if (segmentPoints.isNotEmpty) {
        final startM = segmentPoints.first['timestamp'] as int;
        final endM = segmentPoints.last['timestamp'] as int;

        await dbHelper.cloneSessionWithPoints(
          activityType: '${widget.activityType} [Chunk $chunkIdx (${_chunkMinutes}m)]',
          targetDuration: segmentPoints.length,
          safetyBuffer: 8.0,
          startTime: startM,
          endTime: endM,
          status: 'completed',
          points: segmentPoints,
        );
      }
      chunkIdx++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chop completed! Created chunks of $_chunkMinutes minutes.')),
      );
      Navigator.pop(context, true);
    }
  }
}
