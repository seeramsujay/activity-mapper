import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../widgets/breadcrumb_painter.dart';

/// Screen widget that provides post-run adjustment tools:
/// - Visual Crop / Trimming
/// - Session Merging
/// - N-Equal Parts Chopping
/// - Time-Duration Segmenting
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

class _EditorScreenState extends State<EditorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _rawPoints = [];
  List<Map<String, dynamic>> _availableSessions = [];
  bool _isLoading = true;

  // Cropping variables
  RangeValues _cropRange = const RangeValues(0, 1);
  int _startIndex = 0;
  int _endIndex = 0;

  // Merging variables
  int? _selectedMergeSessionId;
  List<Map<String, dynamic>> _mergeCandidatePoints = [];
  bool _deleteSourceOnMerge = false;

  // N-parts chopper variables
  int _partsCount = 2;

  // Time chopper variables
  int _chunkMinutes = 10;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final points = await DbService.instance.getPoints(widget.sessionId);
    final allSessions = await DbService.instance.getCompletedSessions();
    final candidates = allSessions.where((s) => s['id'] != widget.sessionId).toList();

    setState(() {
      _rawPoints = points;
      _availableSessions = candidates;
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
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // km
  }

  double _calculateDistanceInRange(List<Map<String, dynamic>> pts, int start, int end) {
    if (pts.isEmpty || start >= end || end >= pts.length) return 0.0;
    double dist = 0.0;
    for (int i = start; i < end; i++) {
      dist += _distanceBetween(
        pts[i]['lat'] as double,
        pts[i]['lng'] as double,
        pts[i + 1]['lat'] as double,
        pts[i + 1]['lng'] as double,
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
        title: Text(
          '// TRIP ADJUSTMENTS #${widget.sessionId}',
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: textColor,
          unselectedLabelColor: textColor.withOpacity(0.4),
          indicatorColor: textColor,
          indicatorWeight: 3.0,
          isScrollable: true,
          tabs: const [
            Tab(text: 'CROP'),
            Tab(text: 'MERGE'),
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
                    _buildMergeTab(textColor, scaffoldBg),
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
  // TAB 1: Visual Crop / Trim
  // ----------------------------------------------------------------------------
  Widget _buildCropTab(Color textColor, Color scaffoldBg) {
    final croppedPoints = _rawPoints.sublist(_startIndex, _endIndex + 1);
    final mapPoints = croppedPoints.map((p) => Point(p['lat'] as double, p['lng'] as double)).toList();

    final double distance = _calculateDistanceInRange(_rawPoints, _startIndex, _endIndex);
    final int startMs = _rawPoints[_startIndex]['timestamp'] as int;
    final int endMs = _rawPoints[_endIndex]['timestamp'] as int;
    final int durationMs = endMs - startMs;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: textColor, width: 2.0)),
              child: ClipRect(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: BreadcrumbPainter(
                      points: mapPoints,
                      brightness: Theme.of(context).brightness,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPanelStat('CROPPED DISTANCE', '${distance.toStringAsFixed(2)} km', textColor),
              _buildPanelStat('CROPPED TIME', _formatDuration(durationMs), textColor),
              _buildPanelStat('POINTS', '${croppedPoints.length}', textColor),
            ],
          ),
          const SizedBox(height: 12),
          RangeSlider(
            values: _cropRange,
            min: 0,
            max: (_rawPoints.length - 1).toDouble(),
            activeColor: textColor,
            inactiveColor: textColor.withOpacity(0.2),
            onChanged: (val) {
              if (val.start.round() != _startIndex || val.end.round() != _endIndex) {
                HapticFeedback.selectionClick();
              }
              setState(() {
                _cropRange = val;
                _startIndex = val.start.round();
                _endIndex = val.end.round();
              });
            },
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: textColor,
              foregroundColor: scaffoldBg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _executeCrop(croppedPoints, startMs, endMs),
            child: const Text('SAVE CROPPED TRIP', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeCrop(List<Map<String, dynamic>> points, int startMs, int endMs) async {
    final int newId = await DbService.instance.cloneSessionWithPoints(
      activityType: widget.activityType,
      targetDuration: (endMs - startMs) ~/ 1000,
      safetyBuffer: 8.0,
      startTime: startMs,
      endTime: endMs,
      status: 'completed',
      points: points,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cropped trip saved as new session #$newId')),
      );
      Navigator.pop(context, true);
    }
  }

  // ----------------------------------------------------------------------------
  // TAB 2: Merge Sessions
  // ----------------------------------------------------------------------------
  Widget _buildMergeTab(Color textColor, Color scaffoldBg) {
    if (_availableSessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No other completed sessions available to merge with.',
            textAlign: TextAlign.center,
            style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 16),
          ),
        ),
      );
    }

    final combinedList = [..._rawPoints, ..._mergeCandidatePoints];
    combinedList.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
    final mapPoints = combinedList.map((p) => Point(p['lat'] as double, p['lng'] as double)).toList();
    final double combinedDist = _calculateDistanceInRange(combinedList, 0, max(0, combinedList.length - 1));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: textColor, width: 2.0)),
              child: ClipRect(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: BreadcrumbPainter(
                      points: mapPoints,
                      brightness: Theme.of(context).brightness,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPanelStat('COMBINED DISTANCE', '${combinedDist.toStringAsFixed(2)} km', textColor),
              _buildPanelStat('TOTAL POINTS', '${combinedList.length}', textColor),
            ],
          ),
          const SizedBox(height: 12),
          Text('Select session to merge with:', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            value: _selectedMergeSessionId,
            dropdownColor: scaffoldBg,
            decoration: InputDecoration(
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 2.0)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            hint: Text('Choose session...', style: TextStyle(color: textColor.withOpacity(0.5))),
            items: _availableSessions.map((s) {
              final id = s['id'] as int;
              final type = (s['activity_type'] as String).toUpperCase();
              final dt = DateTime.fromMillisecondsSinceEpoch(s['start_time'] as int);
              return DropdownMenuItem<int>(
                value: id,
                child: Text('Session #$id - $type (${dt.day}/${dt.month}/${dt.year})', style: TextStyle(color: textColor)),
              );
            }).toList(),
            onChanged: (val) async {
              if (val != null) {
                final pts = await DbService.instance.getPoints(val);
                setState(() {
                  _selectedMergeSessionId = val;
                  _mergeCandidatePoints = pts;
                });
              }
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _deleteSourceOnMerge,
                activeColor: textColor,
                checkColor: scaffoldBg,
                onChanged: (val) => setState(() => _deleteSourceOnMerge = val ?? false),
              ),
              Expanded(
                child: Text('Delete merged source session after combining', style: TextStyle(fontSize: 13, color: textColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: textColor,
              foregroundColor: scaffoldBg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _selectedMergeSessionId == null ? null : _executeMerge,
            child: const Text('MERGE SESSIONS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeMerge() async {
    if (_selectedMergeSessionId == null) return;

    final newId = await DbService.instance.mergeSessions(
      targetSessionId: widget.sessionId,
      sourceSessionId: _selectedMergeSessionId!,
      deleteSourceAfterMerge: _deleteSourceOnMerge,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sessions merged successfully into new Session #$newId')),
      );
      Navigator.pop(context, true);
    }
  }

  // ----------------------------------------------------------------------------
  // TAB 3: N-Parts Chopper
  // ----------------------------------------------------------------------------
  Widget _buildNChopTab(Color textColor, Color scaffoldBg) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Chop into N Equal Parts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 6),
          Text(
            'Splits coordinate trail into N equal segments and saves each as a separate activity.',
            style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.6)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Number of Parts (N):', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _partsCount,
                  dropdownColor: scaffoldBg,
                  decoration: InputDecoration(
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 2.0)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [2, 3, 4, 5, 6].map((n) {
                    return DropdownMenuItem<int>(
                      value: n,
                      child: Text('$n Parts', style: TextStyle(color: textColor)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _partsCount = val);
                  },
                ),
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: textColor,
              foregroundColor: scaffoldBg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _executeNChop,
            child: Text('EXECUTE N-CHOP (x$_partsCount)', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeNChop() async {
    final int pointsPerSegment = (_rawPoints.length / _partsCount).ceil();
    final List<int> createdIds = [];

    for (int i = 0; i < _partsCount; i++) {
      final int start = i * pointsPerSegment;
      final int end = min(start + pointsPerSegment, _rawPoints.length);

      if (start < _rawPoints.length) {
        final segment = _rawPoints.sublist(start, end);
        final startMs = segment.first['timestamp'] as int;
        final endMs = segment.last['timestamp'] as int;

        final newId = await DbService.instance.cloneSessionWithPoints(
          activityType: '${widget.activityType}_part_${i + 1}',
          targetDuration: (endMs - startMs) ~/ 1000,
          safetyBuffer: 8.0,
          startTime: startMs,
          endTime: endMs,
          status: 'completed',
          points: segment,
        );
        createdIds.add(newId);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${_partsCount} segmented sessions (${createdIds.join(", ")})')),
      );
      Navigator.pop(context, true);
    }
  }

  // ----------------------------------------------------------------------------
  // TAB 4: Time-Duration Chopper
  // ----------------------------------------------------------------------------
  Widget _buildTimeChopTab(Color textColor, Color scaffoldBg) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Chop by Duration Intervals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 6),
          Text(
            'Segments the workout into chunks of fixed minutes (e.g. 5m, 10m intervals).',
            style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.6)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Interval Size:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _chunkMinutes,
                  dropdownColor: scaffoldBg,
                  decoration: InputDecoration(
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: textColor, width: 2.0)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [2, 5, 10, 15, 30].map((m) {
                    return DropdownMenuItem<int>(
                      value: m,
                      child: Text('$m Minutes', style: TextStyle(color: textColor)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _chunkMinutes = val);
                  },
                ),
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: textColor,
              foregroundColor: scaffoldBg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _executeTimeChop,
            child: Text('EXECUTE TIME-CHOP (${_chunkMinutes}m)', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeTimeChop() async {
    final double chunkMs = _chunkMinutes * 60 * 1000.0;
    final int startMs = _rawPoints.first['timestamp'] as int;

    final List<int> createdIds = [];
    int index = 0;
    int chunkIdx = 1;

    while (index < _rawPoints.length) {
      final double segmentStartMs = startMs + (chunkIdx - 1) * chunkMs;
      final double segmentEndMs = segmentStartMs + chunkMs;
      final List<Map<String, dynamic>> segmentPoints = [];

      while (index < _rawPoints.length) {
        final int pointTime = _rawPoints[index]['timestamp'] as int;
        if (pointTime >= segmentStartMs && pointTime < segmentEndMs) {
          segmentPoints.add(_rawPoints[index]);
          index++;
        } else {
          break;
        }
      }

      if (segmentPoints.isNotEmpty) {
        final sStart = segmentPoints.first['timestamp'] as int;
        final sEnd = segmentPoints.last['timestamp'] as int;

        final newId = await DbService.instance.cloneSessionWithPoints(
          activityType: '${widget.activityType}_chunk_$chunkIdx',
          targetDuration: _chunkMinutes * 60,
          safetyBuffer: 8.0,
          startTime: sStart,
          endTime: sEnd,
          status: 'completed',
          points: segmentPoints,
        );
        createdIds.add(newId);
      }
      chunkIdx++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${createdIds.length} time chunks (${createdIds.join(", ")})')),
      );
      Navigator.pop(context, true);
    }
  }

  Widget _buildPanelStat(String label, String value, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textColor)),
      ],
    );
  }
}
