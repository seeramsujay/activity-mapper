package org.opensource.tracker.data.mesh

import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder

/** Credentials for a collaborative mesh session; shared as a `turnback://mesh?...` link / QR code. */
data class MeshSessionConfig(
    val sessionId: String,
    val sessionKey: String,
    val sessionName: String,
    val isHost: Boolean = false,
    val publicIp: String? = null,
    val publicPort: Int? = null,
) {
    fun toUri(): String {
        val builder =
            StringBuilder("turnback://mesh?id=${encode(sessionId)}&key=${encode(sessionKey)}&name=${encode(sessionName)}")
        if (publicIp != null && publicPort != null) {
            builder.append("&ip=${encode(publicIp)}&port=$publicPort")
        }
        return builder.toString()
    }

    companion object {
        private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

        /** Parses a `turnback://` or `activitymapper://` mesh link. Returns null for anything else. */
        fun fromUri(uriString: String): MeshSessionConfig? =
            try {
                val uri = URI(uriString.trim())
                if ((uri.scheme != "turnback" && uri.scheme != "activitymapper") || uri.host != "mesh") {
                    null
                } else {
                    val params =
                        (uri.rawQuery ?: "")
                            .split("&")
                            .filter { it.contains("=") }
                            .associate {
                                val (k, v) = it.split("=", limit = 2)
                                URLDecoder.decode(k, "UTF-8") to URLDecoder.decode(v, "UTF-8")
                            }
                    val id = params["id"]
                    val key = params["key"]
                    if (id.isNullOrEmpty() || key.isNullOrEmpty() || !MeshCrypto.isValidKey(key)) {
                        null
                    } else {
                        MeshSessionConfig(
                            sessionId = id,
                            sessionKey = key,
                            sessionName = params["name"] ?: "Group Ride",
                            publicIp = params["ip"],
                            publicPort = params["port"]?.toIntOrNull(),
                        )
                    }
                }
            } catch (_: Exception) {
                null
            }
    }
}

/** One-tap tactical messages sent to the whole group. */
enum class PingType(
    val title: String,
    val emoji: String,
    val colorArgb: Int,
) {
    REGROUP("Regroup / Stopping", "🛑", 0xFFF97316.toInt()),
    WATER("Water / Fuel Break", "🚰", 0xFF3B82F6.toInt()),
    SPRINT("Pacing Up / Sprint", "⚡", 0xFF10B981.toInt()),
    HAZARD("Hazard on Route", "⚠️", 0xFFFBBF24.toInt()),
    SOS("SOS / Mechanical Alert!", "🚨", 0xFFEF4444.toInt()),
}

data class MeshPing(
    val id: String,
    val type: PingType,
    val senderId: String,
    val senderName: String,
    val senderColor: Int,
    val timestamp: Long,
    val customText: String? = null,
) {
    fun toJson(): JSONObject =
        JSONObject()
            .put("id", id)
            // Flutter peers use the lowercase enum name on the wire.
            .put("type", type.name.lowercase())
            .put("sid", senderId)
            .put("name", senderName)
            .put("color", senderColor.toLong() and 0xFFFFFFFFL)
            .put("ts", timestamp)
            .also { if (customText != null) it.put("txt", customText) }

    companion object {
        fun fromJson(json: JSONObject): MeshPing {
            val typeName = json.optString("type", "regroup")
            return MeshPing(
                id = json.optString("id", ""),
                type = PingType.entries.firstOrNull { it.name.equals(typeName, ignoreCase = true) } ?: PingType.REGROUP,
                senderId = json.optString("sid", ""),
                senderName = json.optString("name", "Rider"),
                senderColor = json.optLong("color", 0xFFFF5722L).toInt(),
                timestamp = json.optLong("ts", System.currentTimeMillis()),
                customText = if (json.has("txt")) json.optString("txt") else null,
            )
        }
    }
}

/** A point of interest dropped by any teammate and synced to every map. */
data class SharedWaypoint(
    val id: String,
    val name: String,
    val lat: Double,
    val lng: Double,
    val creatorId: String,
    val creatorName: String,
    val colorValue: Int,
    val timestamp: Long,
) {
    fun toJson(): JSONObject =
        JSONObject()
            .put("id", id)
            .put("name", name)
            .put("lat", lat)
            .put("lng", lng)
            .put("cid", creatorId)
            .put("cname", creatorName)
            .put("col", colorValue.toLong() and 0xFFFFFFFFL)
            .put("ts", timestamp)

    companion object {
        fun fromJson(json: JSONObject): SharedWaypoint =
            SharedWaypoint(
                id = json.optString("id", ""),
                name = json.optString("name", "Pin"),
                lat = json.optDouble("lat", 0.0),
                lng = json.optDouble("lng", 0.0),
                creatorId = json.optString("cid", ""),
                creatorName = json.optString("cname", "Rider"),
                colorValue = json.optLong("col", 0xFFFF5722L).toInt(),
                timestamp = json.optLong("ts", System.currentTimeMillis()),
            )
    }
}

data class TrailPoint(
    val lat: Double,
    val lng: Double,
)

data class Teammate(
    val peerId: String,
    val username: String,
    val colorValue: Int,
    val lat: Double,
    val lng: Double,
    val speedKmh: Double,
    val altitude: Double,
    /** Local receive time (not the sender's clock, which may be skewed). */
    val lastSeenMs: Long,
    val trail: List<TrailPoint> = emptyList(),
    val distanceToUserMeters: Double = 0.0,
) {
    val hasFix: Boolean get() = !(lat == 0.0 && lng == 0.0)

    fun isActive(nowMs: Long = System.currentTimeMillis()): Boolean = nowMs - lastSeenMs < ACTIVE_WINDOW_MS

    companion object {
        const val ACTIVE_WINDOW_MS = 60_000L
        const val PRUNE_AFTER_MS = 120_000L
        const val MAX_TRAIL_POINTS = 500
    }
}
