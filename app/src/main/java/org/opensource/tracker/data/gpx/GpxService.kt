package org.opensource.tracker.data.gpx

import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.model.Waypoint
import org.opensource.tracker.domain.model.WaypointCategory
import org.w3c.dom.Document
import org.w3c.dom.Element
import org.w3c.dom.NodeList
import java.io.File
import java.io.InputStream
import java.io.StringWriter
import java.math.BigDecimal
import java.time.Instant
import java.time.format.DateTimeFormatter
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Standard GPX 1.1 Exporter and Importer.
 * Fully compatible with Strava, Garmin Connect, OsmAnd, and Organic Maps.
 */
object GpxExporter {
    private val ISO_FORMATTER: DateTimeFormatter = DateTimeFormatter.ISO_INSTANT

    fun formatDecimal(value: Double): String =
        if (value.isFinite()) {
            BigDecimal.valueOf(value).stripTrailingZeros().toPlainString()
        } else {
            "0"
        }

    fun buildGpxString(
        trackName: String,
        activityType: String,
        points: List<TrackPoint>,
        waypoints: List<Waypoint> = emptyList(),
        startTime: Instant = points.firstOrNull()?.timestamp ?: Instant.now(),
    ): String {
        val writer = StringWriter()
        writer.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        writer.write("<gpx version=\"1.1\" creator=\"TurnBack - Jetpack Compose\" ")
        writer.write("xmlns=\"http://www.topografix.com/GPX/1/1\" ")
        writer.write("xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" ")
        writer.write("xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v2\" ")
        writer.write("xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd ")
        writer.write(
            "http://www.garmin.com/xmlschemas/TrackPointExtension/v2 http://www.garmin.com/xmlschemas/TrackPointExtensionv2.xsd\">\n",
        )

        // Metadata
        writer.write("  <metadata>\n")
        writer.write("    <name>${escapeXml(trackName)}</name>\n")
        writer.write("    <time>${ISO_FORMATTER.format(startTime)}</time>\n")
        writer.write("  </metadata>\n")

        // Waypoints (<wpt>)
        for (w in waypoints) {
            if (!isValidCoord(w.latitude, w.longitude)) continue
            writer.write("  <wpt lat=\"${formatDecimal(w.latitude)}\" lon=\"${formatDecimal(w.longitude)}\">\n")
            if (w.altitudeMeters != 0.0) {
                writer.write("    <ele>${formatDecimal(w.altitudeMeters)}</ele>\n")
            }
            writer.write("    <time>${ISO_FORMATTER.format(w.timestamp)}</time>\n")
            writer.write("    <name>${escapeXml(w.name)}</name>\n")
            if (w.description.isNotBlank()) {
                writer.write("    <desc>${escapeXml(w.description)}</desc>\n")
            }
            writer.write("    <sym>${escapeXml(w.category.gpxSymbol)}</sym>\n")
            writer.write("  </wpt>\n")
        }

        // Track (<trk>)
        writer.write("  <trk>\n")
        writer.write("    <name>${escapeXml(trackName)}</name>\n")
        writer.write("    <type>${escapeXml(activityType)}</type>\n")
        writer.write("    <trkseg>\n")

        var wroteFirstPoint = false
        for (p in points) {
            if (!isValidCoord(p.latitude, p.longitude)) continue
            if (p.newSegment && wroteFirstPoint) {
                writer.write("    </trkseg>\n")
                writer.write("    <trkseg>\n")
            }
            wroteFirstPoint = true
            writer.write("      <trkpt lat=\"${formatDecimal(p.latitude)}\" lon=\"${formatDecimal(p.longitude)}\">\n")
            writer.write("        <ele>${formatDecimal(p.altitudeMeters)}</ele>\n")
            writer.write("        <time>${ISO_FORMATTER.format(p.timestamp)}</time>\n")
            if (p.speedMps > 0.0) {
                writer.write("        <extensions>\n")
                writer.write("          <gpxtpx:TrackPointExtension>\n")
                writer.write("            <gpxtpx:speed>${formatDecimal(p.speedMps)}</gpxtpx:speed>\n")
                writer.write("          </gpxtpx:TrackPointExtension>\n")
                writer.write("        </extensions>\n")
            }
            writer.write("      </trkpt>\n")
        }

        writer.write("    </trkseg>\n")
        writer.write("  </trk>\n")
        writer.write("</gpx>\n")

        return writer.toString()
    }

    fun exportToFile(
        file: File,
        trackName: String,
        activityType: String,
        points: List<TrackPoint>,
        waypoints: List<Waypoint> = emptyList(),
        startTime: Instant = points.firstOrNull()?.timestamp ?: Instant.now(),
    ) {
        file.parentFile?.mkdirs()
        val gpx = buildGpxString(trackName, activityType, points, waypoints, startTime)
        file.writeText(gpx, Charsets.UTF_8)
    }

    private fun isValidCoord(
        lat: Double,
        lon: Double,
    ): Boolean = lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0

    private fun escapeXml(input: String): String =
        input
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
}

object GpxImporter {
    fun parse(inputStream: InputStream): ParsedGpx {
        val factory =
            DocumentBuilderFactory.newInstance().apply {
                isNamespaceAware = true
            }
        val builder = factory.newDocumentBuilder()
        val doc = builder.parse(inputStream)

        var trackName = "Imported Track"
        val trkNodes = getElementsByLocalOrTagName(doc, "trk")
        if (trkNodes.length > 0) {
            val trk = trkNodes.item(0) as? Element
            val nameText = trk?.let { getChildText(it, "name") }
            if (!nameText.isNullOrBlank()) {
                trackName = nameText.trim()
            }
        }
        if (trackName == "Imported Track") {
            val metaNodes = getElementsByLocalOrTagName(doc, "metadata")
            if (metaNodes.length > 0) {
                val meta = metaNodes.item(0) as? Element
                val metaNameText = meta?.let { getChildText(it, "name") }
                if (!metaNameText.isNullOrBlank()) {
                    trackName = metaNameText.trim()
                }
            }
        }

        val waypoints = mutableListOf<Waypoint>()
        val wptNodes = getElementsByLocalOrTagName(doc, "wpt")
        for (i in 0 until wptNodes.length) {
            val el = wptNodes.item(i) as? Element ?: continue
            val lat = el.getAttribute("lat").toDoubleOrNull()
            val lon = el.getAttribute("lon").toDoubleOrNull()
            if (lat == null || lon == null || !isValidCoord(lat, lon)) continue

            val ele = getChildText(el, "ele")?.toDoubleOrNull() ?: 0.0
            val name = getChildText(el, "name")?.trim() ?: "Waypoint"
            val desc = getChildText(el, "desc")?.trim() ?: ""
            val sym = getChildText(el, "sym")?.trim() ?: ""
            val timeStr = getChildText(el, "time")?.trim()
            val time =
                try {
                    if (timeStr != null) Instant.parse(timeStr) else Instant.EPOCH
                } catch (_: Exception) {
                    Instant.EPOCH
                }

            val category =
                when {
                    sym.contains("water", ignoreCase = true) -> WaypointCategory.WATER
                    sym.contains("scenic", ignoreCase = true) ||
                        sym.contains(
                            "view",
                            ignoreCase = true,
                        ) -> WaypointCategory.VIEWPOINT

                    sym.contains("camp", ignoreCase = true) -> WaypointCategory.CAMP
                    sym.contains("danger", ignoreCase = true) ||
                        sym.contains(
                            "hazard",
                            ignoreCase = true,
                        ) -> WaypointCategory.HAZARD

                    else -> WaypointCategory.NOTE
                }

            waypoints.add(
                Waypoint(
                    sessionId = 0L,
                    name = name.ifBlank { "Waypoint" },
                    description = desc,
                    latitude = lat,
                    longitude = lon,
                    altitudeMeters = ele,
                    category = category,
                    timestamp = time,
                ),
            )
        }

        val points = mutableListOf<TrackPoint>()
        var lastValidTime = Instant.EPOCH
        var segmentBreakPending = false

        for ((el, startsSegment) in collectTrackPoints(doc)) {
            if (startsSegment) segmentBreakPending = true
            val lat = el.getAttribute("lat").toDoubleOrNull()
            val lon = el.getAttribute("lon").toDoubleOrNull()
            if (lat == null || lon == null || !isValidCoord(lat, lon)) continue

            val ele = getChildText(el, "ele")?.toDoubleOrNull() ?: 0.0
            val timeStr = getChildText(el, "time")?.trim()
            val time =
                try {
                    if (timeStr != null) {
                        val parsed = Instant.parse(timeStr)
                        lastValidTime = parsed
                        parsed
                    } else {
                        lastValidTime
                    }
                } catch (_: Exception) {
                    lastValidTime
                }

            var speed = getChildText(el, "speed")?.toDoubleOrNull() ?: 0.0
            if (speed == 0.0) {
                // Check Garmin TrackPointExtension
                val extChildren = el.childNodes
                for (c in 0 until extChildren.length) {
                    val child = extChildren.item(c)
                    if (child is Element && (child.localName == "extensions" || child.tagName.endsWith("extensions"))) {
                        val subSpeed = getChildText(child, "speed")?.toDoubleOrNull()
                        if (subSpeed != null && subSpeed > 0.0) {
                            speed = subSpeed
                            break
                        }
                        val tpxChildren = child.childNodes
                        for (tc in 0 until tpxChildren.length) {
                            val tpxEl = tpxChildren.item(tc)
                            if (tpxEl is Element) {
                                val tpxSpeed = getChildText(tpxEl, "speed")?.toDoubleOrNull()
                                if (tpxSpeed != null && tpxSpeed > 0.0) {
                                    speed = tpxSpeed
                                    break
                                }
                            }
                        }
                    }
                }
            }

            points.add(
                TrackPoint(
                    latitude = lat,
                    longitude = lon,
                    altitudeMeters = ele,
                    speedMps = speed,
                    timestamp = time,
                    // The first point of the whole track is never a "new" segment, only later segment starts.
                    newSegment = segmentBreakPending && points.isNotEmpty(),
                ),
            )
            segmentBreakPending = false
        }

        return ParsedGpx(trackName, points, waypoints)
    }

    /**
     * Track points in document order, each flagged `true` when it is the first element of its `trkseg`.
     * Falls back to a flat scan for malformed files that have `trkpt` outside any `trkseg`.
     */
    private fun collectTrackPoints(doc: Document): List<Pair<Element, Boolean>> {
        val result = mutableListOf<Pair<Element, Boolean>>()
        val segments = getElementsByLocalOrTagName(doc, "trkseg")
        for (s in 0 until segments.length) {
            val segment = segments.item(s) as? Element ?: continue
            var first = true
            val children = segment.childNodes
            for (c in 0 until children.length) {
                val child = children.item(c)
                if (child is Element && (child.localName == "trkpt" || child.tagName == "trkpt" || child.tagName.endsWith(":trkpt"))) {
                    result.add(child to first)
                    first = false
                }
            }
        }
        if (result.isEmpty()) {
            val flat = getElementsByLocalOrTagName(doc, "trkpt")
            for (i in 0 until flat.length) {
                (flat.item(i) as? Element)?.let { result.add(it to false) }
            }
        }
        return result
    }

    private fun isValidCoord(
        lat: Double,
        lon: Double,
    ): Boolean = lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0

    private fun getElementsByLocalOrTagName(
        doc: Document,
        name: String,
    ): NodeList {
        val nsList = doc.getElementsByTagNameNS("*", name)
        return if (nsList.length > 0) nsList else doc.getElementsByTagName(name)
    }

    private fun getChildText(
        el: Element,
        name: String,
    ): String? {
        val children = el.childNodes
        for (i in 0 until children.length) {
            val child = children.item(i)
            if (child is Element && (child.localName == name || child.tagName == name || child.tagName.endsWith(":$name"))) {
                return child.textContent?.trim()
            }
        }
        return null
    }
}

data class ParsedGpx(
    val name: String,
    val points: List<TrackPoint>,
    val waypoints: List<Waypoint>,
)
