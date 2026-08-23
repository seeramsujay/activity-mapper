import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/tile_cache_service.dart';

/// Dedicated Google Maps-style Offline Maps management and download screen.
class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  int _cachedTileCount = 0;
  int _cachedTileBytes = 0;
  List<OfflineMapArea> _savedAreas = [];
  bool _isLoading = true;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  StreamSubscription<MapDownloadProgress>? _downloadSub;

  @override
  void initState() {
    super.initState();
    _loadMetricsAndAreas();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMetricsAndAreas() async {
    setState(() => _isLoading = true);
    final metrics = await TileCacheService.instance.getCacheMetrics();
    final areas = await TileCacheService.instance.getSavedOfflineAreas();
    if (mounted) {
      setState(() {
        _cachedTileCount = metrics['count'] ?? 0;
        _cachedTileBytes = metrics['sizeBytes'] ?? 0;
        _savedAreas = areas;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteArea(OfflineMapArea area) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E232B) : Colors.white,
        title: const Text('Delete Offline Area?'),
        content: Text('Are you sure you want to remove "${area.name}" from your offline areas?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TileCacheService.instance.deleteOfflineArea(area.id);
      _loadMetricsAndAreas();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${area.name}')),
        );
      }
    }
  }

  Future<void> _clearAllCache() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E232B) : Colors.white,
        title: const Text('Wipe All Tile Cache?'),
        content: const Text('This will delete all offline map tiles stored on your device. You will need an internet connection to view maps outside cached areas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLEAR ALL'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TileCacheService.instance.clearCache();
      _loadMetricsAndAreas();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All offline map cache wiped.')),
        );
      }
    }
  }

  void _showDownloadCustomAreaSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final accentColor = SettingsService.instance.accentColor.color;
    final cardBg = isDark ? const Color(0xFF161C24) : Colors.white;

    final nameController = TextEditingController(text: 'Area ${_savedAreas.length + 1}');
    final latController = TextEditingController(text: '37.7749');
    final lngController = TextEditingController(text: '-122.4194');
    double selectedRadius = 5.0;
    List<int> zoomLevels = [12, 13, 14, 15, 16];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final metrics = TileCacheService.estimateAreaMetrics(selectedRadius, zoomLevels);
          final estimatedTiles = metrics['tileCount'] as int;
          final estimatedMb = (metrics['estimatedMb'] as num).toDouble();

          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF12171E) : Colors.white,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.download_for_offline_rounded, color: accentColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'DOWNLOAD CUSTOM AREA',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Area Name
                  Text('AREA NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'e.g. Mountain Loop Trail',
                      hintStyle: TextStyle(color: textColor.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: textColor.withValues(alpha: 0.1))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Center Coordinates
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CENTER LATITUDE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                            const SizedBox(height: 6),
                            TextField(
                              controller: latController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: cardBg,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: textColor.withValues(alpha: 0.1))),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              onChanged: (_) => setSheetState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CENTER LONGITUDE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                            const SizedBox(height: 6),
                            TextField(
                              controller: lngController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: cardBg,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: textColor.withValues(alpha: 0.1))),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              onChanged: (_) => setSheetState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Radius Selector
                  Text('COVERAGE RADIUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1.0, 2.0, 5.0, 10.0, 20.0].map((r) {
                      final selected = selectedRadius == r;
                      return ChoiceChip(
                        label: Text('${r.toInt()} km ${r == 5.0 ? "(Standard)" : ""}'),
                        selected: selected,
                        selectedColor: accentColor.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: selected ? accentColor : textColor,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          if (val) setSheetState(() => selectedRadius = r);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Estimate Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.analytics_outlined, size: 20, color: accentColor),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Estimated Pack Size', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                                Text('Zoom levels 12 to 16', style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.5))),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('$estimatedTiles tiles', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: accentColor)),
                            Text('~${estimatedMb.toStringAsFixed(1)} MB', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.6))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Start Download Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        final lat = double.tryParse(latController.text) ?? 37.7749;
                        final lng = double.tryParse(lngController.text) ?? -122.4194;
                        final name = nameController.text.trim().isNotEmpty ? nameController.text.trim() : 'Custom Area';
                        Navigator.pop(modalCtx);
                        _startDownloadingArea(name, lat, lng, selectedRadius, zoomLevels);
                      },
                      icon: const Icon(Icons.cloud_download_rounded, size: 20),
                      label: const Text('DOWNLOAD NOW', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _startDownloadingArea(String name, double lat, double lng, double radiusKm, List<int> zoomLevels) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Initializing download...';
    });

    final stream = TileCacheService.instance.downloadOfflineRegion(
      centerLat: lat,
      centerLng: lng,
      radiusKm: radiusKm,
      zoomLevels: zoomLevels,
      tileUrlTemplate: SettingsService.instance.mapTileSource,
    );

    _downloadSub = stream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = progress.progressRatio;
          _downloadStatus = progress.status;
        });

        if (progress.isDone) {
          final area = OfflineMapArea(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: name,
            centerLat: lat,
            centerLng: lng,
            radiusKm: radiusKm,
            tileCount: progress.total,
            sizeMb: (progress.total * 25.0) / 1024.0,
            downloadedAt: DateTime.now(),
          );
          TileCacheService.instance.saveOfflineArea(area).then((_) {
            _loadMetricsAndAreas();
          });

          setState(() => _isDownloading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Offline Area "$name" downloaded successfully!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $err'), backgroundColor: const Color(0xFFDC2626)),
        );
      },
    );
  }

  void _cancelDownload() {
    _downloadSub?.cancel();
    setState(() {
      _isDownloading = false;
      _downloadStatus = 'Download cancelled';
    });
    _loadMetricsAndAreas();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final accentColor = SettingsService.instance.accentColor.color;
    final cardBg = isDark ? const Color(0xFF161C24) : Colors.white;
    final borderColor = textColor.withValues(alpha: 0.12);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Maps', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        actions: [
          if (_cachedTileCount > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear tile cache',
              onPressed: _clearAllCache,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Top Storage Footprint Hero Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.storage_rounded, size: 20, color: accentColor),
                              const SizedBox(width: 8),
                              Text('STORAGE USAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.6), letterSpacing: 0.8)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${(_cachedTileBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: accentColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$_cachedTileCount cached map tiles available for offline tracking without cellular data or GPS latency.',
                        style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.7), height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: (_cachedTileBytes / (100 * 1024 * 1024)).clamp(0.02, 1.0),
                        backgroundColor: textColor.withValues(alpha: 0.08),
                        color: accentColor,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Download Custom Area Call-to-Action Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor.withValues(alpha: 0.15),
                        accentColor.withValues(alpha: 0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select your own map',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Download high-res tiles around your home trail or workout zone.',
                              style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: _isDownloading ? null : _showDownloadCustomAreaSheet,
                        child: const Text('DOWNLOAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Active Download Progress Widget (if downloading)
                if (_isDownloading) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accentColor, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: accentColor),
                                ),
                                const SizedBox(width: 10),
                                Text('DOWNLOADING TILES...', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: accentColor)),
                              ],
                            ),
                            Text('${(_downloadProgress * 100).toInt()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: textColor)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: textColor.withValues(alpha: 0.08),
                          color: accentColor,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(_downloadStatus, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6)), overflow: TextOverflow.ellipsis),
                            ),
                            TextButton(
                              onPressed: _cancelDownload,
                              child: const Text('CANCEL', style: TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // Downloaded Offline Areas Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'DOWNLOADED AREAS (${_savedAreas.length})',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.6), letterSpacing: 0.8),
                      ),
                      if (_savedAreas.isNotEmpty)
                        Text(
                          'Auto-updated on Wi-Fi',
                          style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.4)),
                        ),
                    ],
                  ),
                ),

                if (_savedAreas.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.map_outlined, size: 48, color: textColor.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          'No offline areas downloaded yet',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Select your own map" above to download offline map regions for offline navigation.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  )
                else
                  ..._savedAreas.map((area) {
                    final dateStr = '${area.downloadedAt.year}-${area.downloadedAt.month.toString().padLeft(2, '0')}-${area.downloadedAt.day.toString().padLeft(2, '0')}';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.map_rounded, color: accentColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(area.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textColor)),
                                const SizedBox(height: 2),
                                Text(
                                  '${area.radiusKm.toInt()} km radius • ${area.tileCount} tiles • ${area.sizeMb.toStringAsFixed(1)} MB',
                                  style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.6)),
                                ),
                                Text(
                                  'Downloaded $dateStr',
                                  style: TextStyle(fontSize: 9, color: textColor.withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 20),
                            color: const Color(0xFFDC2626),
                            tooltip: 'Delete area',
                            onPressed: () => _deleteArea(area),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
