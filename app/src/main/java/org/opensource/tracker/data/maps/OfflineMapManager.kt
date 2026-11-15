package org.opensource.tracker.data.maps

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.osmdroid.config.Configuration
import org.osmdroid.util.GeoPoint
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.tan

data class OfflineAreaItem(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val centerLat: Double,
    val centerLon: Double,
    val radiusKm: Double,
    val tileCount: Int,
    val sizeBytes: Long,
    val isVector: Boolean = false,
    val formatDescription: String = "OSM Raster",
    val filePath: String? = null,
    val dateAdded: Long = System.currentTimeMillis(),
)

class OfflineMapManager private constructor(
    private val context: Context,
) {
    private val prefs = context.getSharedPreferences("offline_maps_prefs", Context.MODE_PRIVATE)

    private val _areas = MutableStateFlow<List<OfflineAreaItem>>(emptyList())
    val areas: StateFlow<List<OfflineAreaItem>> = _areas.asStateFlow()

    private val _totalCacheSizeBytes = MutableStateFlow(0L)
    val totalCacheSizeBytes: StateFlow<Long> = _totalCacheSizeBytes.asStateFlow()

    init {
        loadSavedAreas()
        recomputeCacheSize()
    }

    private fun loadSavedAreas() {
        val jsonStr = prefs.getString(KEY_SAVED_AREAS, "[]") ?: "[]"
        val list = mutableListOf<OfflineAreaItem>()
        try {
            val jsonArray = JSONArray(jsonStr)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                list.add(
                    OfflineAreaItem(
                        id = obj.optString("id", UUID.randomUUID().toString()),
                        name = obj.optString("name", "Offline Area"),
                        centerLat = obj.optDouble("centerLat", 0.0),
                        centerLon = obj.optDouble("centerLon", 0.0),
                        radiusKm = obj.optDouble("radiusKm", 5.0),
                        tileCount = obj.optInt("tileCount", 0),
                        sizeBytes = obj.optLong("sizeBytes", 0L),
                        isVector = obj.optBoolean("isVector", false),
                        formatDescription = obj.optString("formatDescription", "OSM Raster"),
                        filePath = if (obj.has("filePath")) obj.getString("filePath") else null,
                        dateAdded = obj.optLong("dateAdded", System.currentTimeMillis()),
                    ),
                )
            }
        } catch (_: Exception) {
        }
        _areas.value = list
    }

    private fun persistAreas() {
        val jsonArray = JSONArray()
        for (item in _areas.value) {
            val obj =
                JSONObject().apply {
                    put("id", item.id)
                    put("name", item.name)
                    put("centerLat", item.centerLat)
                    put("centerLon", item.centerLon)
                    put("radiusKm", item.radiusKm)
                    put("tileCount", item.tileCount)
                    put("sizeBytes", item.sizeBytes)
                    put("isVector", item.isVector)
                    put("formatDescription", item.formatDescription)
                    item.filePath?.let { put("filePath", it) }
                    put("dateAdded", item.dateAdded)
                }
            jsonArray.put(obj)
        }
        prefs.edit().putString(KEY_SAVED_AREAS, jsonArray.toString()).apply()
    }

    fun recomputeCacheSize() {
        var total = 0L
        val osmdroidDir = Configuration.getInstance().osmdroidTileCache
        if (osmdroidDir != null && osmdroidDir.exists()) {
            total += getDirectorySize(osmdroidDir)
        }
        val customDir = File(context.filesDir, "offline_maps")
        if (customDir.exists()) {
            total += getDirectorySize(customDir)
        }
        _totalCacheSizeBytes.value = total
    }

    private fun getDirectorySize(dir: File): Long {
        var size = 0L
        val files = dir.listFiles() ?: return 0L
        for (f in files) {
            size += if (f.isDirectory) getDirectorySize(f) else f.length()
        }
        return size
    }

    suspend fun downloadArea(
        name: String,
        center: GeoPoint,
        radiusKm: Double,
        tileServerUrl: String = "https://tile.openstreetmap.org",
        onProgress: (current: Int, total: Int, status: String) -> Unit,
    ): Boolean =
        withContext(Dispatchers.IO) {
            val latDelta = radiusKm / 111.0
            val lonDelta = radiusKm / (111.0 * cos(Math.toRadians(center.latitude)).coerceAtLeast(0.01))

            val north = min(85.0511, center.latitude + latDelta)
            val south = max(-85.0511, center.latitude - latDelta)
            val west = max(-180.0, center.longitude - lonDelta)
            val east = min(180.0, center.longitude + lonDelta)

            val minZoom = 12
            val maxZoom = 15

            // Compute tiles across zoom levels
            val tiles = mutableListOf<Triple<Int, Int, Int>>() // zoom, x, y
            for (z in minZoom..maxZoom) {
                val minX = lon2tile(west, z)
                val maxX = lon2tile(east, z)
                val minY = lat2tile(north, z)
                val maxY = lat2tile(south, z)

                for (x in min(minX, maxX)..max(minX, maxX)) {
                    for (y in min(minY, maxY)..max(minY, maxY)) {
                        tiles.add(Triple(z, x, y))
                    }
                }
            }

            val total = tiles.size
            if (total == 0) return@withContext false

            val cacheBase = Configuration.getInstance().osmdroidTileCache ?: File(context.cacheDir, "osmdroid/tiles")
            var downloadedCount = 0
            var downloadedBytes = 0L

            for (i in tiles.indices) {
                val (z, x, y) = tiles[i]
                val tileFile = File(cacheBase, "Mapnik/$z/$x/$y.png")
                if (tileFile.exists()) {
                    downloadedCount++
                    downloadedBytes += tileFile.length()
                    onProgress(downloadedCount, total, "Cached ($downloadedCount/$total)")
                    continue
                }

                try {
                    tileFile.parentFile?.mkdirs()
                    val url = URL("$tileServerUrl/$z/$x/$y.png")
                    val conn = url.openConnection() as HttpURLConnection
                    conn.setRequestProperty("User-Agent", context.packageName)
                    conn.connectTimeout = 5000
                    conn.readTimeout = 5000

                    if (conn.responseCode == 200) {
                        conn.inputStream.use { input ->
                            FileOutputStream(tileFile).use { output ->
                                val buffer = ByteArray(4096)
                                var bytesRead: Int
                                while (input.read(buffer).also { bytesRead = it } != -1) {
                                    output.write(buffer, 0, bytesRead)
                                    downloadedBytes += bytesRead
                                }
                            }
                        }
                    }
                } catch (_: Exception) {
                }

                downloadedCount++
                onProgress(downloadedCount, total, "Downloading tiles ($downloadedCount/$total)")
            }

            val newArea =
                OfflineAreaItem(
                    name = name,
                    centerLat = center.latitude,
                    centerLon = center.longitude,
                    radiusKm = radiusKm,
                    tileCount = downloadedCount,
                    sizeBytes = downloadedBytes,
                    isVector = false,
                    formatDescription = "OSM Raster (Zoom $minZoom-$maxZoom)",
                )
            _areas.value = _areas.value + newArea
            persistAreas()
            recomputeCacheSize()
            true
        }

    suspend fun importVectorOrArchive(
        uri: Uri,
        fileName: String,
        contentResolver: android.content.ContentResolver,
    ): Boolean =
        withContext(Dispatchers.IO) {
            try {
                val mapsDir = File(context.filesDir, "offline_maps")
                mapsDir.mkdirs()
                val targetFile = File(mapsDir, fileName)

                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                }

                val ext = fileName.substringAfterLast('.', "").lowercase()
                val isVector = ext == "map"
                val format =
                    when (ext) {
                        "map" -> "Mapsforge Vector (.map)"
                        "mbtiles" -> "MBTiles Vector/Raster (.mbtiles)"
                        "sqlite" -> "Osmdroid SQLite (.sqlite)"
                        "zip" -> "Osmdroid Tile Archive (.zip)"
                        else -> "Offline Map ($ext)"
                    }

                val item =
                    OfflineAreaItem(
                        name = fileName.substringBeforeLast('.').replace('_', ' ').replace('-', ' '),
                        centerLat = 0.0,
                        centerLon = 0.0,
                        radiusKm = 0.0,
                        tileCount = 1,
                        sizeBytes = targetFile.length(),
                        isVector = isVector,
                        formatDescription = format,
                        filePath = targetFile.absolutePath,
                    )

                _areas.value = _areas.value + item
                persistAreas()
                recomputeCacheSize()
                true
            } catch (_: Exception) {
                false
            }
        }

    fun deleteArea(item: OfflineAreaItem) {
        item.filePath?.let {
            val file = File(it)
            if (file.exists()) file.delete()
        }
        _areas.value = _areas.value.filter { it.id != item.id }
        persistAreas()
        recomputeCacheSize()
    }

    suspend fun clearAllCache(): Unit =
        withContext(Dispatchers.IO) {
            val osmdroidDir = Configuration.getInstance().osmdroidTileCache
            if (osmdroidDir != null && osmdroidDir.exists()) {
                osmdroidDir.deleteRecursively()
            }
            val customDir = File(context.filesDir, "offline_maps")
            if (customDir.exists()) {
                customDir.deleteRecursively()
            }
            _areas.value = emptyList()
            persistAreas()
            recomputeCacheSize()
        }

    companion object {
        private const val KEY_SAVED_AREAS = "KEY_SAVED_AREAS"

        @Volatile
        private var instance: OfflineMapManager? = null

        fun getInstance(context: Context): OfflineMapManager =
            instance ?: synchronized(this) {
                instance ?: OfflineMapManager(context.applicationContext).also { instance = it }
            }

        private fun lon2tile(
            lon: Double,
            zoom: Int,
        ): Int = floor((lon + 180.0) / 360.0 * (1 shl zoom)).toInt()

        private fun lat2tile(
            lat: Double,
            zoom: Int,
        ): Int =
            floor(
                (1.0 - ln(tan(Math.toRadians(lat)) + 1.0 / cos(Math.toRadians(lat))) / Math.PI) / 2.0 * (1 shl zoom),
            ).toInt()
    }
}
