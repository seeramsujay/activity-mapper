import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../services/export_service.dart';
import '../services/platform_service.dart';
import '../widgets/breadcrumb_painter.dart';
import 'editor_screen.dart';
import 'hud_screen.dart';

/// Screen widget that displays the history list of completed activities.
///
/// Features:
/// - Direct multi-format export (.ZIP, GPX, KML, GeoJSON, CSV)
/// - Post-run editing (Crop, Merge, Split)
/// - Offline vector map preview with RDP simplification
/// - Full database lifetime ZIP backup
class HistoryScreen extends StatefulWidget {
  /// Creates a new [HistoryScreen] instance.
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
    final Color scaffoldBg = brightness == Brightness.light ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text(
          '// ACTIVITY LOGS',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.archive_outlined, color: textColor),
            tooltip: 'Export Full Backup (.ZIP)',
            onPressed: _runFullLifetimeZipBackup,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: textColor))
            : _sessions.isEmpty
                ? _buildEmptyState(textColor)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
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
              'Record a session to view telemetry, export multi-format ZIP packages, or perform post-run crops and merges.',
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
    final double buffer = (session['safety_buffer'] as num).toDouble();
    final int startMs = session['start_time'] as int;
    final int? endMs = session['end_time'] as int?;

    final startDate = DateTime.fromMillisecondsSinceEpoch(startMs);
    final duration = endMs != null ? Duration(milliseconds: endMs - startMs) : Duration.zero;

    final String dateString = '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year}';
    final String timeString = '${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}';
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$type #$id',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: brightness == Brightness.light ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  '$dateString - $timeString',
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSubstat('DURATION', durationString, textColor),
                    _buildSubstat('TARGET', '${targetSec ~/ 60}m', textColor),
                    _buildSubstat('BUFFER', '${buffer.toStringAsFixed(0)}%', textColor),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      triggered ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      size: 16,
                      color: triggered ? Colors.orangeAccent : Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      triggered ? 'Turn-Back Threshold Reached' : 'Out-and-Back Completed Safely',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: triggered ? Colors.orangeAccent : Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions Row
          Divider(color: textColor.withValues(alpha: 0.15), height: 1, thickness: 1),
          Container(
            color: textColor.withValues(alpha: 0.03),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Prominent Continue Completed Run Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('CONTINUE RUN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                    onPressed: () => _showContinueRunModal(id, type, targetSec, buffer),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: textColor.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.map_outlined, size: 14),
                    label: const Text('VIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: () => _viewActivityMap(id, type, brightness),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: textColor.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 14),
                    label: const Text('ADJUST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: () => _editActivity(id, type),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: textColor.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.file_download_outlined, size: 14),
                    label: const Text('EXPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: () => _showExportOptionsSheet(id, type),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 18),
                    tooltip: 'Delete Session',
                    onPressed: () => _confirmDelete(id),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showContinueRunModal(int sessionId, String activityType, int originalTargetSec, double buffer) {
    HapticFeedback.selectionClick();
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;
    final surfaceBg = isDark ? const Color(0xFF1E232B) : const Color(0xFFF3F4F6);
    final borderColor = isDark ? const Color(0xFF2D333F) : const Color(0xFFE5E7EB);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        int targetMinutes = max(5, originalTargetSec ~/ 60);
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
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF10B981), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CONTINUE WORKOUT #$sessionId',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.8),
                            ),
                            Text(
                              'Resume logging GPS track & append to this run',
                              style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Option 1: Continue with original target
                  _buildContinueActionCard(
                    title: 'CONTINUE EXISTING TIMER',
                    subtitle: 'Resume with original target (${originalTargetSec ~/ 60}m) and append new GPS telemetry',
                    icon: Icons.fast_forward_rounded,
                    color: const Color(0xFF10B981),
                    textColor: textColor,
                    surfaceBg: surfaceBg,
                    borderColor: borderColor,
                    onTap: () => _launchContinuedSession(sessionId, activityType, originalTargetSec, buffer, resetTimer: false),
                  ),
                  const SizedBox(height: 10),

                  // Option 2: Reset countdown to start fresh
                  _buildContinueActionCard(
                    title: 'RESET RETURN COUNTDOWN',
                    subtitle: 'Start a fresh ${originalTargetSec ~/ 60}m return countdown from now (preserves previous GPS points)',
                    icon: Icons.restart_alt_rounded,
                    color: const Color(0xFF3B82F6),
                    textColor: textColor,
                    surfaceBg: surfaceBg,
                    borderColor: borderColor,
                    onTap: () => _launchContinuedSession(sessionId, activityType, originalTargetSec, buffer, resetTimer: true),
                  ),
                  const SizedBox(height: 10),

                  // Option 3: Set whole new target duration
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
                              'SET NEW RETURN TARGET: $targetMinutes MIN',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.6),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: targetMinutes.toDouble(),
                          min: 5,
                          max: 180,
                          divisions: 35,
                          activeColor: const Color(0xFFF59E0B),
                          label: '$targetMinutes min',
                          onChanged: (v) => setModalState(() => targetMinutes = v.round()),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final m in [15, 30, 45, 60, 90])
                              GestureDetector(
                                onTap: () => setModalState(() => targetMinutes = m),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: targetMinutes == m ? const Color(0xFFF59E0B) : (isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Text(
                                    '${m}m',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: targetMinutes == m ? Colors.white : textColor),
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
                            onPressed: () => _launchContinuedSession(sessionId, activityType, targetMinutes * 60, buffer, resetTimer: true),
                            child: const Text('APPLY NEW DURATION & CONTINUE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
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

  Widget _buildContinueActionCard({
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

  void _launchContinuedSession(int sessionId, String activityType, int targetSec, double buffer, {required bool resetTimer}) async {
    Navigator.pop(context); // close modal

    // Reactivate session in SQLite
    await DbService.instance.reactivateSession(sessionId, newTargetDurationSeconds: targetSec);

    // Start Kotlin GPS foreground tracking service
    await PlatformService.instance.startTracking(
      sessionId: sessionId,
      activityType: activityType.toLowerCase(),
      targetDurationSeconds: targetSec,
      safetyBufferPct: buffer,
      gpsIntervalMs: 5000,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HudScreen(
            sessionId: sessionId,
            targetDuration: Duration(seconds: targetSec),
            safetyBufferPct: buffer,
            activityType: activityType.toLowerCase(),
          ),
        ),
      ).then((_) => _loadSessions());
    }
  }

  void _showExportOptionsSheet(int sessionId, String activityType) {
    final textColor = Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white;
    final scaffoldBg = Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.black;

    showModalBottomSheet(
      context: context,
      backgroundColor: scaffoldBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'EXPORT SESSION #$sessionId',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: textColor, letterSpacing: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  '100% serverless, local file generation.',
                  style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.6)),
                ),
                const SizedBox(height: 16),

                // Primary ZIP Export
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text(
                    'EXPORT ALL IN ONE (.ZIP)',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: textColor,
                    foregroundColor: scaffoldBg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _exportZipBundle(sessionId, activityType);
                  },
                ),
                const SizedBox(height: 12),

                // Individual formats
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: textColor),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _exportSingleFormat(sessionId, activityType, 'gpx');
                        },
                        child: const Text('GPX 1.1', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: textColor),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _exportSingleFormat(sessionId, activityType, 'kml');
                        },
                        child: const Text('KML', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: textColor),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _exportSingleFormat(sessionId, activityType, 'geojson');
                        },
                        child: const Text('GeoJSON', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: textColor),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _exportSingleFormat(sessionId, activityType, 'csv');
                        },
                        child: const Text('CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportZipBundle(int sessionId, String type) async {
    try {
      final file = await ExportService.instance.exportSessionZipBundle(sessionId, type);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ZIP Package Exported:\n${file.path}'),
            duration: const Duration(seconds: 5),
          ),
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

  Future<void> _exportSingleFormat(int sessionId, String type, String format) async {
    try {
      final file = await ExportService.instance.exportSingleFormat(
        sessionId: sessionId,
        activityName: type,
        format: format,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${format.toUpperCase()} Exported:\n${file.path}'), duration: const Duration(seconds: 4)),
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

  Future<void> _runFullLifetimeZipBackup() async {
    try {
      final zipFile = await ExportService.instance.exportLifetimeZipBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Full Lifetime Backup (.ZIP) Generated:\n${zipFile.path}'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
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
    final points = await DbService.instance.getPoints(sessionId);

    if (points.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No coordinates logged for this activity.')),
        );
      }
      return;
    }

    final List<Point<double>> mapPoints = points.map((p) => Point(p['lat'] as double, p['lng'] as double)).toList();

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
              '$type - BREADCRUMB ROUTE',
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.0),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: color, width: 2.0)),
                child: ClipRect(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: BreadcrumbPainter(points: mapPoints, brightness: brightness),
                    ),
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
}
