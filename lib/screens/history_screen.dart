import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../services/export_service.dart';
import '../services/platform_service.dart';
import '../widgets/session_feed_card.dart';
import 'editor_screen.dart';
import 'hud_screen.dart';

/// Screen widget that displays the history list of completed activities.
///
/// Features:
/// - 1-Click Instant GPX Sharing & Downloads
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '// ACTIVITY LOGS',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 16),
            ),
            Text(
              'Tap to inspect • Long-press for magic menu',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal, color: textColor.withValues(alpha: 0.5)),
            ),
          ],
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
                      return SessionFeedCard(
                        session: session,
                        textColor: textColor,
                        brightness: brightness,
                        onDelete: () => _confirmDelete(session['id'] as int),
                        onEdit: () => _editActivity(session['id'] as int, session['activity_type'] as String),
                        onContinue: () => _showContinueRunModal(
                          session['id'] as int,
                          session['activity_type'] as String,
                          session['target_duration'] as int,
                          (session['safety_buffer'] as num).toDouble(),
                        ),
                        onRefresh: _loadSessions,
                      );
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
            Icon(Icons.history_toggle_off_outlined, size: 64, color: textColor.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'No Completed Activities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Record a session to view telemetry, export multi-format ZIP packages, or perform post-run crops and merges.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.5)),
            ),
          ],
        ),
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

    // Start Kotlin GPS foreground tracking service with high accuracy 1000ms
    await PlatformService.instance.startTracking(
      sessionId: sessionId,
      activityType: activityType.toLowerCase(),
      targetDurationSeconds: targetSec,
      safetyBufferPct: buffer,
      gpsIntervalMs: 1000,
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
            isFreeRun: activityType.toLowerCase() == 'freerun',
          ),
        ),
      ).then((_) => _loadSessions());
    }
  }

  Future<void> _runFullLifetimeZipBackup() async {
    try {
      final zipFile = await ExportService.instance.exportLifetimeZipBackup();
      if (mounted) {
        await PlatformService.instance.shareFile(zipFile.path, title: 'Lifetime Backup');
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
