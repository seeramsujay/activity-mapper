import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/db_service.dart';
import '../services/export_service.dart';
import '../services/gpx_service.dart';
import '../services/platform_service.dart';
import '../services/settings_service.dart';
import '../screens/editor_screen.dart';
import '../screens/workout_summary_screen.dart';
import 'breadcrumb_painter.dart';
import 'strava_upload_dialog.dart';

/// Clean, unified modal action sheet that pops up when a track is long-pressed (or more menu tapped).
///
/// Provides quick access to all track operations ("all the magic"):
/// - View detailed workout stats & interactive telemetry graphs
/// - Resume / continue endurance run
/// - Fullscreen interactive breadcrumb route map preview
/// - Trim, crop, split, and merge in post-run editor
/// - 1-tap instant GPX sharing to native share sheet
/// - Multi-format export hub (GPX, KML, GeoJSON, CSV, Relive 3D, ZIP)
/// - 1-tap Strava sync
/// - Copy summary text to clipboard
/// - Secure delete with confirmation
class TrackMagicSheet extends StatelessWidget {
  final Map<String, dynamic> session;
  final double distanceKm;
  final Duration duration;
  final List<Point<double>> mapPoints;
  final VoidCallback? onContinue;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRefresh;

  const TrackMagicSheet({
    super.key,
    required this.session,
    required this.distanceKm,
    required this.duration,
    required this.mapPoints,
    this.onContinue,
    this.onEdit,
    this.onDelete,
    this.onRefresh,
  });

  /// Static helper to trigger haptic feedback and show the sheet.
  static Future<void> show({
    required BuildContext context,
    required Map<String, dynamic> session,
    required double distanceKm,
    required Duration duration,
    required List<Point<double>> mapPoints,
    VoidCallback? onContinue,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    VoidCallback? onRefresh,
  }) {
    HapticFeedback.heavyImpact();
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => TrackMagicSheet(
        session: session,
        distanceKm: distanceKm,
        duration: duration,
        mapPoints: mapPoints,
        onContinue: onContinue,
        onEdit: onEdit,
        onDelete: onDelete,
        onRefresh: onRefresh,
      ),
    );
  }

  IconData _getActivityIcon(String type) {
    switch (type.toLowerCase()) {
      case 'ride':
      case 'cycling':
      case 'bike':
        return Icons.directions_bike_rounded;
      case 'hike':
      case 'hiking':
        return Icons.hiking_rounded;
      case 'walk':
      case 'walking':
        return Icons.directions_walk_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  Color _getActivityColor(String type) {
    switch (type.toLowerCase()) {
      case 'ride':
      case 'cycling':
      case 'bike':
        return const Color(0xFF06B6D4); // Cyan
      case 'hike':
      case 'hiking':
        return const Color(0xFF10B981); // Emerald
      case 'walk':
      case 'walking':
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFFFF5722); // Deep Orange
    }
  }

  String _formatPace(double distKm, Duration dur) {
    if (distKm <= 0.05 || dur.inSeconds <= 0) return '--';
    final secPerKm = dur.inSeconds / distKm;
    if (secPerKm > 3600) return '>60m/km';
    final m = (secPerKm ~/ 60);
    final s = (secPerKm % 60).round().toString().padLeft(2, '0');
    return "$m'$s\"/km";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final surfaceBg = isDark ? const Color(0xFF1C212A) : const Color(0xFFF3F4F6);
    final borderColor = isDark ? const Color(0xFF282F3B) : const Color(0xFFE5E7EB);
    final accentColor = SettingsService.instance.accentColor.color;

    final int id = session['id'] as int;
    final String type = (session['activity_type'] as String? ?? 'run').toUpperCase();
    final int startMs = session['start_time'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final startDate = DateTime.fromMillisecondsSinceEpoch(startMs);
    final String dateString = '${startDate.day}/${startDate.month}/${startDate.year}';
    final String timeString = '${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}';
    final String durationString = '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    final bool triggered = session['turn_back_triggered_at'] != null;
    final Color activityColor = _getActivityColor(type);
    final paceString = _formatPace(distanceKm, duration);

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 20.0,
            right: 20.0,
            top: 14.0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 28.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top drag indicator
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Track identity banner
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: activityColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: activityColor.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Icon(_getActivityIcon(type), color: activityColor, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '$type #$id',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: (triggered ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                triggered ? 'TURN-BACK' : 'COMPLETED',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: triggered ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$dateString • $timeString',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: textColor.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: textColor.withValues(alpha: 0.5)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Metrics pill banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetricItem('DISTANCE', '${distanceKm.toStringAsFixed(2)} KM', textColor),
                    _buildDivider(textColor),
                    _buildMetricItem('DURATION', durationString, textColor),
                    _buildDivider(textColor),
                    _buildMetricItem('PACE', paceString, textColor),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Hero Quick Action Buttons (View Summary & Continue Run)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.insights_rounded, size: 20),
                      label: const Text(
                        'SUMMARY & CHARTS',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkoutSummaryScreen(
                              sessionId: id,
                              activityType: type.toLowerCase(),
                            ),
                          ),
                        ).then((_) => onRefresh?.call());
                      },
                    ),
                  ),
                  if (onContinue != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text(
                          'CONTINUE RUN',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          onContinue!();
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 22),

              // Section 1: Route & Adjustments
              _buildSectionLabel('ROUTE & VISUALIZATION', textColor),
              const SizedBox(height: 8),
              _buildActionTile(
                icon: Icons.map_rounded,
                iconColor: const Color(0xFF3B82F6),
                title: 'View Interactive Route Map',
                subtitle: 'Breadcrumb trail with start, turn-back, and finish pins',
                textColor: textColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
                onTap: () {
                  Navigator.pop(context);
                  _showRoutePreviewModal(context, id, type, isDark);
                },
              ),
              const SizedBox(height: 8),
              _buildActionTile(
                icon: Icons.tune_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: 'Edit & Trim Activity',
                subtitle: 'Post-run crop, split into intervals, or merge tracks',
                textColor: textColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditorScreen(sessionId: id, activityType: type.toLowerCase()),
                    ),
                  );
                  if (result == true) {
                    onRefresh?.call();
                  }
                },
              ),
              const SizedBox(height: 20),

              // Section 2: Sharing & Export Hub
              _buildSectionLabel('SHARE & EXPORT', textColor),
              const SizedBox(height: 8),
              _buildActionTile(
                icon: Icons.share_rounded,
                iconColor: const Color(0xFF3B82F6),
                title: 'Quick Share GPX File',
                subtitle: '1-tap native system share (AirDrop, WhatsApp, Garmin, Files)',
                textColor: textColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
                onTap: () => _handleShareGpx(context, id, type),
              ),
              const SizedBox(height: 8),
              _buildActionTile(
                icon: Icons.folder_zip_outlined,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Export Multi-Format Hub',
                subtitle: 'Choose from GPX, KML, GeoJSON, CSV, Relive 3D, or ZIP archive',
                textColor: textColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
                onTap: () => _showFormatExportSheet(context, id, type, isDark, textColor, surfaceBg, borderColor),
              ),
              const SizedBox(height: 8),
              _buildActionTile(
                icon: Icons.cloud_upload_outlined,
                iconColor: const Color(0xFFFF5722),
                title: 'Upload to Strava',
                subtitle: 'Sync GPS polyline, pace splits, and elevation directly',
                textColor: textColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (_) => StravaUploadDialog(
                      sessionId: id,
                      activityName: '$type #$id',
                      activityType: type.toLowerCase(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildActionTile(
                icon: Icons.copy_rounded,
                iconColor: textColor.withValues(alpha: 0.7),
                title: 'Copy Activity Summary',
                subtitle: 'Copy distance, time, and pace text to clipboard',
                textColor: textColor,
                surfaceBg: surfaceBg,
                borderColor: borderColor,
                onTap: () => _handleCopySummary(context, id, type, dateString, durationString, paceString),
              ),
              const SizedBox(height: 20),

              // Section 3: Danger Zone
              _buildSectionLabel('MANAGEMENT', textColor),
              const SizedBox(height: 8),
              _buildActionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: const Color(0xFFEF4444),
                title: 'Delete Activity',
                subtitle: 'Permanently erase this session and GPS points',
                textColor: const Color(0xFFEF4444),
                surfaceBg: const Color(0xFFEF4444).withValues(alpha: 0.06),
                borderColor: const Color(0xFFEF4444).withValues(alpha: 0.3),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(context, id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(String text, Color textColor) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: textColor.withValues(alpha: 0.5),
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor),
        ),
      ],
    );
  }

  Widget _buildDivider(Color textColor) {
    return Container(
      width: 1,
      height: 24,
      color: textColor.withValues(alpha: 0.12),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color surfaceBg,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: surfaceBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: textColor.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleShareGpx(BuildContext context, int sessionId, String type) async {
    Navigator.pop(context);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Exporting & opening GPX share sheet...'), duration: Duration(seconds: 1)),
    );
    try {
      await GpxService.instance.shareGpxFile(sessionId, type);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share GPX: $e')),
        );
      }
    }
  }

  void _handleCopySummary(
    BuildContext context,
    int id,
    String type,
    String dateString,
    String durationString,
    String paceString,
  ) {
    Navigator.pop(context);
    HapticFeedback.selectionClick();
    final summary = '🏃 TurnBack Activity #$id\n'
        '• Type: $type\n'
        '• Date: $dateString\n'
        '• Distance: ${distanceKm.toStringAsFixed(2)} km\n'
        '• Duration: $durationString\n'
        '• Pace: $paceString\n'
        'Logged offline via TurnBack Endurance Tracker.';

    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Activity summary copied to clipboard!'), duration: Duration(seconds: 2)),
    );
  }

  void _showRoutePreviewModal(BuildContext context, int sessionId, String type, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final cardBg = isDark ? const Color(0xFF14171C) : Colors.white;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$type ROUTE PREVIEW',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.8),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 340,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FA),
                child: mapPoints.isEmpty
                    ? Center(child: Text('No GPS points logged.', style: TextStyle(color: textColor.withValues(alpha: 0.5))))
                    : RepaintBoundary(
                        child: CustomPaint(
                          painter: BreadcrumbPainter(
                            points: mapPoints,
                            brightness: isDark ? Brightness.dark : Brightness.light,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CLOSE', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showFormatExportSheet(
    BuildContext context,
    int sessionId,
    String type,
    bool isDark,
    Color textColor,
    Color surfaceBg,
    Color borderColor,
  ) {
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF14171C) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
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
              Text(
                'EXPORT TELEMETRY FILE',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.8),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a format to save or share your activity record:',
                style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFormatBtn(ctx, 'GPX 1.1', Icons.file_present_rounded, () => _runExport(context, sessionId, type, 'gpx')),
                  _buildFormatBtn(ctx, 'KML (Earth)', Icons.public_rounded, () => _runExport(context, sessionId, type, 'kml')),
                  _buildFormatBtn(ctx, 'GeoJSON', Icons.data_object_rounded, () => _runExport(context, sessionId, type, 'geojson')),
                  _buildFormatBtn(ctx, 'CSV Table', Icons.table_chart_rounded, () => _runExport(context, sessionId, type, 'csv')),
                  _buildFormatBtn(ctx, 'Relive 3D', Icons.threed_rotation_rounded, () => _runExport(context, sessionId, type, 'relive')),
                  _buildFormatBtn(ctx, 'Full ZIP', Icons.archive_rounded, () => _runExport(context, sessionId, type, 'zip')),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormatBtn(BuildContext ctx, String label, IconData icon, VoidCallback onSelected) {
    return SizedBox(
      width: (MediaQuery.of(ctx).size.width - 56) / 2,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        onPressed: () {
          Navigator.pop(ctx);
          onSelected();
        },
      ),
    );
  }

  Future<void> _runExport(BuildContext context, int sessionId, String type, String format) async {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generating ${format.toUpperCase()} export...'), duration: const Duration(seconds: 1)),
    );
    try {
      final file = format == 'zip'
          ? await ExportService.instance.exportSessionZipBundle(sessionId, type)
          : await ExportService.instance.exportSingleFormat(
              sessionId: sessionId,
              activityName: type,
              format: format,
            );
      if (context.mounted) {
        await PlatformService.instance.shareFile(file.path, title: 'Share ${format.toUpperCase()}: $type');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, int sessionId) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : Colors.black;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF14171C) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Delete Activity?',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This will permanently delete this session and all its coordinate data.',
            style: TextStyle(color: textColor.withValues(alpha: 0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CANCEL', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                HapticFeedback.mediumImpact();
                await DbService.instance.deleteSession(sessionId);
                onRefresh?.call();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Activity deleted.'), duration: Duration(seconds: 2)),
                  );
                }
              },
              child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
