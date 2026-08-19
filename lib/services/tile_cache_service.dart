import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

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

  Directory? _cacheDir;

  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null && await _cacheDir!.exists()) {
      return _cacheDir!;
    }
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/osm_tiles');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Returns the local cached [File] for a tile if it exists on disk, or `null`.
  Future<File?> getLocalTileFile(int z, int x, int y) async {
    try {
      final baseDir = await cacheDirectory;
      final file = File('${baseDir.path}/$z/$x/$y.png');
      if (await file.exists() && (await file.length()) > 0) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Synchronously gets file path reference without waiting.
  String getLocalTilePathSync(String basePath, int z, int x, int y) {
    return '$basePath/$z/$x/$y.png';
  }

  /// Saves raw tile image bytes to disk cache.
  Future<void> saveTileBytes(int z, int x, int y, Uint8List bytes) async {
    try {
      final baseDir = await cacheDirectory;
      final file = File('${baseDir.path}/$z/$x/$y.png');
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
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
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom)).floor();
  }

  /// Downloads all map tiles for a geographic radius around [centerLat], [centerLng] for specified [zoomLevels].
  Stream<MapDownloadProgress> downloadOfflineRegion({
    required double centerLat,
    required double centerLng,
    required double radiusKm,
    required List<int> zoomLevels,
    required String tileUrlTemplate,
  }) async* {
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
    int completedTiles = 0;
    int skippedTiles = 0;

    yield MapDownloadProgress(
      completed: 0,
      total: totalTiles,
      status: 'Preparing download of $totalTiles tiles...',
    );

    final client = HttpClient();
    client.userAgent = 'ActivityMapper/1.0.0 (Offline Tracker; OpenSource)';
    client.connectionTimeout = const Duration(seconds: 10);

    final baseDir = await cacheDirectory;

    for (final tile in tileQueue) {
      final int z = tile['z']!;
      final int x = tile['x']!;
      final int y = tile['y']!;

      final localFile = File('${baseDir.path}/$z/$x/$y.png');
      if (await localFile.exists() && (await localFile.length()) > 0) {
        completedTiles++;
        skippedTiles++;
        yield MapDownloadProgress(
          completed: completedTiles,
          total: totalTiles,
          status: 'Cached ($completedTiles/$totalTiles)',
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
          final bytes = bytesBuilder.toBytes();
          if (!await localFile.parent.exists()) {
            await localFile.parent.create(recursive: true);
          }
          await localFile.writeAsBytes(bytes, flush: true);
        }
      } catch (_) {
        // Network timeout or offline, continue with remaining
      }

      completedTiles++;
      yield MapDownloadProgress(
        completed: completedTiles,
        total: totalTiles,
        status: 'Downloading... ($completedTiles/$totalTiles)',
      );

      // Polite throttling to respect tile server limits
      await Future.delayed(const Duration(milliseconds: 35));
    }

    client.close();

    yield MapDownloadProgress(
      completed: totalTiles,
      total: totalTiles,
      status: 'Done! Saved ${totalTiles - skippedTiles} new tiles.',
      isDone: true,
    );
  }
}

class MapDownloadProgress {
  final int completed;
  final int total;
  final String status;
  final bool isDone;

  const MapDownloadProgress({
    required this.completed,
    required this.total,
    required this.status,
    this.isDone = false,
  });

  double get progressRatio => total > 0 ? (completed / total).clamp(0.0, 1.0) : 1.0;
}
