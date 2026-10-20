import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'settings_service.dart';

/// Ultra-lightweight offline OpenStreetMap raster/vector tile manager.
///
/// Features:
/// - Cache-first tile resolution (`/tiles/{z}/{x}/{y}.png`).
/// - Region / radius offline tile pack downloader (2km, 5km, 10km radius).
/// - Storage footprint tracking and cache clear utilities.
/// - Conforms strictly to OpenStreetMap tile usage policy (proper User-Agent & polite throttling).
class TileCacheService {
  static final TileCacheService instance = TileCacheService._init();

  TileCacheService._init();

  /// Hard cap per offline pack, in line with the OSM tile usage policy (no bulk scraping).
  static const int maxTilesPerDownload = 3000;

  /// Delay between sequential tile requests (single connection, ~4 req/s).
  static const Duration requestSpacing = Duration(milliseconds: 250);

  static const String userAgent = 'TurnBack-ActivityMapper/1.3 (Android; org.opensource.tracker; offline tile pack)';

  Directory? _cacheDir;

  /// Short stable id for a tile URL template, so tiles from different providers (OSM, Topo,
  /// satellite...) never overwrite or masquerade as each other on disk.
  static String sourceKey(String tileUrlTemplate) {
    int hash = 0x811c9dc5; // FNV-1a 32-bit
    for (final unit in utf8.encode(tileUrlTemplate)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 'src_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// On-disk location of a tile for a given source template.
  static File tileFile(Directory baseDir, String tileUrlTemplate, int z, int x, int y) {
    return File('${baseDir.path}/${sourceKey(tileUrlTemplate)}/$z/$x/$y.png');
  }

  /// Whether bulk pre-download is allowed for a tile source. Google's terms forbid it.
  static bool allowsBulkDownload(String tileUrlTemplate) => !tileUrlTemplate.contains('google.com');

  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null && await _cacheDir!.exists()) {
      return _cacheDir!;
    }
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/osm_tiles');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await migrateLegacyLayout(dir, SettingsService.instance.mapTileSource);
    _cacheDir = dir;
    return dir;
  }

  /// Older versions stored tiles as `<base>/{z}/{x}/{y}.png` regardless of provider. Move those
  /// zoom folders under the given source so they stay usable instead of being stranded.
  static Future<void> migrateLegacyLayout(Directory baseDir, String tileUrlTemplate) async {
    try {
      final zoomDir = RegExp(r'^\d+$');
      final legacy = <Directory>[];
      await for (final entity in baseDir.list(followLinks: false)) {
        if (entity is Directory && zoomDir.hasMatch(entity.uri.pathSegments.where((s) => s.isNotEmpty).last)) {
          legacy.add(entity);
        }
      }
      if (legacy.isEmpty) return;
      final target = Directory('${baseDir.path}/${sourceKey(tileUrlTemplate)}');
      await target.create(recursive: true);
      for (final z in legacy) {
        final name = z.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final dest = Directory('${target.path}/$name');
        if (await dest.exists()) {
          await z.delete(recursive: true); // already have this zoom level for the source
        } else {
          await z.rename(dest.path);
        }
      }
    } catch (_) {}
  }

  File _getMetadataFile(Directory baseDir) {
    return File('${baseDir.path}/offline_areas.json');
  }

  /// Retrieves list of saved offline map areas.
  Future<List<OfflineMapArea>> getSavedOfflineAreas() async {
    try {
      final baseDir = await cacheDirectory;
      final file = _getMetadataFile(baseDir);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((e) => OfflineMapArea.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Saves or updates an offline map area record.
  Future<void> saveOfflineArea(OfflineMapArea area) async {
    try {
      final baseDir = await cacheDirectory;
      final areas = await getSavedOfflineAreas();
      areas.removeWhere((a) => a.id == area.id);
      areas.insert(0, area);
      final file = _getMetadataFile(baseDir);
      await file.writeAsString(jsonEncode(areas.map((e) => e.toJson()).toList()), flush: true);
    } catch (_) {}
  }

  /// Deletes a saved offline area by ID.
  Future<void> deleteOfflineArea(String id) async {
    try {
      final baseDir = await cacheDirectory;
      final areas = await getSavedOfflineAreas();
      areas.removeWhere((a) => a.id == id);
      final file = _getMetadataFile(baseDir);
      await file.writeAsString(jsonEncode(areas.map((e) => e.toJson()).toList()), flush: true);
    } catch (_) {}
  }

  /// Returns the local cached [File] for a tile if it exists on disk, or `null`.
  ///
  /// [tileUrlTemplate] defaults to the currently selected map source.
  Future<File?> getLocalTileFile(int z, int x, int y, {String? tileUrlTemplate}) async {
    try {
      final baseDir = await cacheDirectory;
      final file = tileFile(baseDir, tileUrlTemplate ?? SettingsService.instance.mapTileSource, z, x, y);
      if (await file.exists() && (await file.length()) > 0) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Synchronously gets file path reference without waiting.
  String getLocalTilePathSync(String basePath, int z, int x, int y, {String? tileUrlTemplate}) {
    return '$basePath/${sourceKey(tileUrlTemplate ?? SettingsService.instance.mapTileSource)}/$z/$x/$y.png';
  }

  /// Saves raw tile image bytes to disk cache.
  Future<void> saveTileBytes(int z, int x, int y, Uint8List bytes, {String? tileUrlTemplate}) async {
    try {
      final baseDir = await cacheDirectory;
      await _writeAtomically(tileFile(baseDir, tileUrlTemplate ?? SettingsService.instance.mapTileSource, z, x, y), bytes);
    } catch (_) {}
  }

  /// Writes via a temp file + rename so a killed app never leaves a truncated tile that would
  /// then be treated as cached forever.
  static Future<void> _writeAtomically(File file, List<int> bytes) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  /// Fetches cache metrics: total cached tile images and total size on disk in bytes.
  Future<Map<String, int>> getCacheMetrics() async {
    try {
      final baseDir = await cacheDirectory;
      if (!await baseDir.exists()) {
        return {'count': 0, 'sizeBytes': 0};
      }

      int count = 0;
      int sizeBytes = 0;

      await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.png')) {
          count++;
          sizeBytes += await entity.length();
        }
      }

      return {'count': count, 'sizeBytes': sizeBytes};
    } catch (_) {
      return {'count': 0, 'sizeBytes': 0};
    }
  }

  /// Wipes all local tile cache files from storage.
  Future<void> clearCache() async {
    try {
      final baseDir = await cacheDirectory;
      if (await baseDir.exists()) {
        await baseDir.delete(recursive: true);
        await baseDir.create(recursive: true);
      }
    } catch (_) {}
  }

  int _lon2tileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  int _lat2tileY(double lat, int zoom) {
    // Web Mercator is undefined at the poles; clamp to its valid range.
    final latRad = lat.clamp(-85.0511, 85.0511) * pi / 180.0;
    final n = 1 << zoom;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * n).floor().clamp(0, n - 1);
  }

  /// Downloads all map tiles for a geographic radius around [centerLat], [centerLng] for specified [zoomLevels].
  Stream<MapDownloadProgress> downloadOfflineRegion({
    required double centerLat,
    required double centerLng,
    required double radiusKm,
    required List<int> zoomLevels,
    required String tileUrlTemplate,
  }) async* {
    if (centerLat.isNaN || centerLng.isNaN || centerLat.abs() > 85.0 || centerLng.abs() > 180.0) {
      yield const MapDownloadProgress(
        completed: 0,
        total: 0,
        status: 'Invalid coordinates (latitude must be within ±85°, longitude within ±180°).',
        isDone: true,
        failed: 1,
      );
      return;
    }
    if (!allowsBulkDownload(tileUrlTemplate)) {
      yield const MapDownloadProgress(
        completed: 0,
        total: 0,
        status: 'This map source does not permit offline bulk downloads. Switch to an OpenStreetMap-based source.',
        isDone: true,
        failed: 1,
      );
      return;
    }

    // 1 deg latitude is approx 111.32 km
    final double latDelta = radiusKm / 110.574;
    final double lngDelta = radiusKm / (111.320 * cos(centerLat * pi / 180.0));

    final double minLat = centerLat - latDelta;
    final double maxLat = centerLat + latDelta;
    final double minLng = centerLng - lngDelta;
    final double maxLng = centerLng + lngDelta;

    final List<Map<String, int>> tileQueue = [];

    for (final zoom in zoomLevels) {
      final int startX = _lon2tileX(minLng, zoom);
      final int endX = _lon2tileX(maxLng, zoom);
      final int startY = _lat2tileY(maxLat, zoom);
      final int endY = _lat2tileY(minLat, zoom);

      final int minX = min(startX, endX);
      final int maxX = max(startX, endX);
      final int minY = min(startY, endY);
      final int maxY = max(startY, endY);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tileQueue.add({'z': zoom, 'x': x, 'y': y});
        }
      }
    }

    final int totalTiles = tileQueue.length;
    if (totalTiles > maxTilesPerDownload) {
      yield MapDownloadProgress(
        completed: 0,
        total: totalTiles,
        status: 'Area too large ($totalTiles tiles, limit $maxTilesPerDownload). Reduce the radius or zoom levels.',
        isDone: true,
        failed: totalTiles,
      );
      return;
    }
    int completedTiles = 0;
    int skippedTiles = 0;
    int savedTiles = 0;
    int failedTiles = 0;

    yield MapDownloadProgress(
      completed: 0,
      total: totalTiles,
      status: 'Preparing download of $totalTiles tiles...',
    );

    final client = HttpClient();
    client.userAgent = userAgent;
    client.connectionTimeout = const Duration(seconds: 10);

    final baseDir = await cacheDirectory;
    String? abortReason;

    try {
      for (final tile in tileQueue) {
        final int z = tile['z']!;
        final int x = tile['x']!;
        final int y = tile['y']!;

        final localFile = tileFile(baseDir, tileUrlTemplate, z, x, y);
        if (await localFile.exists() && (await localFile.length()) > 0) {
          completedTiles++;
          skippedTiles++;
          yield MapDownloadProgress(
            completed: completedTiles,
            total: totalTiles,
            status: 'Cached ($completedTiles/$totalTiles)',
            saved: savedTiles,
            failed: failedTiles,
          );
          continue;
        }

        final url = tileUrlTemplate
            .replaceAll('{z}', '$z')
            .replaceAll('{x}', '$x')
            .replaceAll('{y}', '$y');

        try {
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          if (response.statusCode == 200) {
            final bytesBuilder = BytesBuilder();
            await for (final chunk in response) {
              bytesBuilder.add(chunk);
            }
            await _writeAtomically(localFile, bytesBuilder.toBytes());
            savedTiles++;
          } else {
            await response.drain<void>(); // release the connection
            failedTiles++;
            if (response.statusCode == 403 || response.statusCode == 429) {
              // Blocked or rate-limited: stop instead of hammering the tile server.
              abortReason = 'Tile server refused requests (HTTP ${response.statusCode}). Try again later.';
            }
          }
        } catch (_) {
          // Network timeout or offline, continue with remaining
          failedTiles++;
        }

        completedTiles++;
        yield MapDownloadProgress(
          completed: completedTiles,
          total: totalTiles,
          status: 'Downloading... ($completedTiles/$totalTiles)',
          saved: savedTiles,
          failed: failedTiles,
        );
        if (abortReason != null) break;

        // Polite throttling to respect tile server limits
        await Future.delayed(requestSpacing);
      }
    } finally {
      client.close(force: true);
    }

    yield MapDownloadProgress(
      completed: abortReason != null ? completedTiles : totalTiles,
      total: totalTiles,
      status: abortReason ??
          (failedTiles > 0
              ? 'Done with errors: saved $savedTiles new tiles, $failedTiles failed.'
              : 'Done! Saved ${totalTiles - skippedTiles} new tiles.'),
      isDone: true,
      saved: savedTiles,
      failed: failedTiles,
    );
  }

  /// Calculates estimated tile count and approximate download size in MB for given radius and zoom levels.
  static Map<String, dynamic> estimateAreaMetrics(double radiusKm, List<int> zoomLevels) {
    int totalTiles = 0;
    for (final z in zoomLevels) {
      final double latDelta = radiusKm / 110.574;
      final double lngDelta = radiusKm / 111.320;
      final int countX = max(1, (lngDelta * 2 / 360.0 * (1 << z)).ceil());
      final int countY = max(1, (latDelta * 2 / 180.0 * (1 << z)).ceil());
      totalTiles += (countX * countY);
    }
    final double estimatedMb = (totalTiles * 25.0) / 1024.0; // approx 25KB per PNG tile
    return {
      'tileCount': totalTiles,
      'estimatedMb': estimatedMb.clamp(0.1, 999.0),
    };
  }
}

class OfflineMapArea {
  final String id;
  final String name;
  final double centerLat;
  final double centerLng;
  final double radiusKm;
  final int tileCount;
  final double sizeMb;
  final DateTime downloadedAt;

  const OfflineMapArea({
    required this.id,
    required this.name,
    required this.centerLat,
    required this.centerLng,
    required this.radiusKm,
    required this.tileCount,
    required this.sizeMb,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'centerLat': centerLat,
    'centerLng': centerLng,
    'radiusKm': radiusKm,
    'tileCount': tileCount,
    'sizeMb': sizeMb,
    'downloadedAt': downloadedAt.toIso8601String(),
  };

  factory OfflineMapArea.fromJson(Map<String, dynamic> json) => OfflineMapArea(
    id: json['id'] as String,
    name: json['name'] as String,
    centerLat: (json['centerLat'] as num).toDouble(),
    centerLng: (json['centerLng'] as num).toDouble(),
    radiusKm: (json['radiusKm'] as num).toDouble(),
    tileCount: json['tileCount'] as int,
    sizeMb: (json['sizeMb'] as num).toDouble(),
    downloadedAt: DateTime.parse(json['downloadedAt'] as String),
  );
}

class MapDownloadProgress {
  final int completed;
  final int total;
  final String status;
  final bool isDone;

  /// Tiles newly written to disk.
  final int saved;

  /// Tiles that could not be downloaded.
  final int failed;

  const MapDownloadProgress({
    required this.completed,
    required this.total,
    required this.status,
    this.isDone = false,
    this.saved = 0,
    this.failed = 0,
  });

  /// True if the pack finished and every tile is available offline.
  bool get isComplete => isDone && failed == 0;

  double get progressRatio => total > 0 ? (completed / total).clamp(0.0, 1.0) : 1.0;
}

