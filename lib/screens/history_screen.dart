import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/gpx_service.dart';
import '../services/backup_service.dart';
import '../widgets/breadcrumb_painter.dart';
import 'editor_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final completed = await DbService.instance.getCompletedSessions();
    setState(() {
      _sessions = completed;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color textColor = brightness == Brightness.light ? Colors.black : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('// HISTORY', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.archive_outlined, color: textColor),
            tooltip: 'Export ZIP Backup',
            onPressed: _runZipBackup,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: textColor))
            : _sessions.isEmpty
                ? _buildEmptyState(textColor)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      return _buildSessionCard(session, textColor, brightness);
                    },
                  ),
      ),
    );
  }

  Widget _buildEmptyState(Color textColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_outlined, size: 64, color: textColor.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'No Completed Activities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Record and complete a tracking session to view your activity history logs.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, Color textColor, Brightness brightness) {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        border: Border.all(color: textColor, width: 2.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header banner
          Container(
            color: textColor,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                Text(
                  '$type - SESSION #$id',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: brightness == Brightness.light ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  dateString,
                  style: TextStyle(
                    fontSize: 12,
                    color: (brightness == Brightness.light ? Colors.white : Colors.black).withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),

          // Content body
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.between,
                  children: [
                    _buildSubstat('DURATION', durationString, textColor),
                    _buildSubstat('TARGET', '${targetSec ~/ 60} min', textColor),
                    _buildSubstat('BUFFER', '${buffer.toStringAsFixed(0)}%', textColor),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      triggered ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      size: 16,
                      color: triggered ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      triggered ? 'Turn-Back Threshold Alert Fired' : 'Completed Out-and-Back Safely',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: triggered ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions Row
          Divider(color: textColor.withOpacity(0.3), height: 1, thickness: 1),
          Container(
            color: textColor.withOpacity(0.04),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _viewActivityMap(id, type, brightness),
                  child: Text('VIEW PATH', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _editActivity(id, type),
                  child: Text('EDIT/CHOP', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _exportGpx(id, type),
                  child: Text('GPX', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => _confirmDelete(id),
                ),
              ],
            ),
          ),
        ],
      ),
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
      _loadSessions();
    }
  }

  Widget _buildSubstat(String label, String value, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textColor)),
      ],
    );
  }

  Future<void> _viewActivityMap(int sessionId, String type, Brightness brightness) async {
    final dbHelper = DbService.instance;
    final points = await dbHelper.getPoints(sessionId);

    if (points.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No coordinates logged for this activity.')),
        );
      }
      return;
    }

    final List<Point<double>> mapPoints = [];
    for (final p in points) {
      mapPoints.add(Point(p['lat'] as double, p['lng'] as double));
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) {
          final color = brightness == Brightness.light ? Colors.black : Colors.white;
          final bg = brightness == Brightness.light ? Colors.white : Colors.black;
          return AlertDialog(
            backgroundColor: bg,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            title: Text(
              '$type - BREADCRUMB MAP',
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.0),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: Container(
                decoration: Border.all(color: color, width: 2.0),
                child: ClipRect(
                  child: CustomPaint(
                    painter: BreadcrumbPainter(points: mapPoints, brightness: brightness),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CLOSE', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _exportGpx(int sessionId, String type) async {
    try {
      final file = await GpxService.instance.saveGpxFile(sessionId, type);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPX file exported to:\n${file.path}'), duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
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
                _loadSessions();
              },
              child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runZipBackup() async {
    try {
      final zipFile = await BackupService.instance.createZipBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ZIP Backup generated successfully:\n${zipFile.path}'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
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
}
