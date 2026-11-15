package org.opensource.tracker.data.gpx

import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.model.Waypoint
import org.opensource.tracker.domain.model.WaypointCategory
import org.w3c.dom.Element
import java.io.File
import java.io.InputStream
import java.io.StringWriter
import java.time.Instant
import java.time.format.DateTimeFormatter
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Standard GPX 1.1 Exporter and Importer.
 * Fully compatible with Strava, Garmin Connect, OsmAnd, and Organic Maps.
 */
object GpxExporter {
    private val ISO_FORMATTER: DateTimeFormatter = DateTimeFormatter.ISO_INSTANT

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
        writer.write("xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\" ")
        writer.write("xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd ")
        writer.write(
            "http://www.garmin.com/xmlschemas/TrackPointExtension/v1 http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd\">\n",
        )

        // Metadata
        writer.write("  <metadata>\n")
        writer.write("    <name>${escapeXml(trackName)}</name>\n")
        writer.write("    <time>${ISO_FORMATTER.format(startTime)}</time>\n")
        writer.write("  </metadata>\n")

        // Waypoints (<wpt>)
        for (w in waypoints) {
            writer.write("  <wpt lat=\"${w.latitude}\" lon=\"${w.longitude}\">\n")
            if (w.altitudeMeters != 0.0) {
                writer.write("    <ele>${w.altitudeMeters}</ele>\n")
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

        for (p in points) {
            writer.write("      <trkpt lat=\"${p.latitude}\" lon=\"${p.longitude}\">\n")
            writer.write("        <ele>${p.altitudeMeters}</ele>\n")
            writer.write("        <time>${ISO_FORMATTER.format(p.timestamp)}</time>\n")
            if (p.speedMps > 0.0) {
                writer.write("        <extensions>\n")
                writer.write("          <gpxtpx:TrackPointExtension>\n")
                writer.write("            <gpxtpx:speed>${p.speedMps}</gpxtpx:speed>\n")
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
        val gpx = buildGpxString(trackName, activityType, points, waypoints, startTime)
        file.writeText(gpx, Charsets.UTF_8)
    }

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
        val trkNodes = doc.getElementsByTagName("trk")
        if (trkNodes.length > 0) {
            val trk = trkNodes.item(0) as? Element
            val nameEl = trk?.getElementsByTagName("name")?.item(0)
            if (nameEl != null && nameEl.textContent.isNotBlank()) {
                trackName = nameEl.textContent.trim()
            }
        }
        if (trackName == "Imported Track") {
            val metaNodes = doc.getElementsByTagName("metadata")
            if (metaNodes.length > 0) {
                val meta = metaNodes.item(0) as? Element
                val metaNameEl = meta?.getElementsByTagName("name")?.item(0)
                if (metaNameEl != null && metaNameEl.textContent.isNotBlank()) {
                    trackName = metaNameEl.textContent.trim()
                }
            }
        }

        val waypoints = mutableListOf<Waypoint>()
        val wptNodes = doc.getElementsByTagName("wpt")
        for (i in 0 until wptNodes.length) {
            val el = wptNodes.item(i) as? Element ?: continue
            val lat = el.getAttribute("lat").toDoubleOrNull() ?: 0.0
            val lon = el.getAttribute("lon").toDoubleOrNull() ?: 0.0
            val ele =
                el
                    .getElementsByTagName("ele")
                    .item(0)
                    ?.textContent
                    ?.toDoubleOrNull() ?: 0.0
            val name =
                el
                    .getElementsByTagName("name")
                    .item(0)
                    ?.textContent
                    ?.trim() ?: "Waypoint"
            val desc =
                el
                    .getElementsByTagName("desc")
                    .item(0)
                    ?.textContent
                    ?.trim() ?: ""
            val sym =
                el
                    .getElementsByTagName("sym")
                    .item(0)
                    ?.textContent
                    ?.trim() ?: ""
            val timeStr =
                el
                    .getElementsByTagName("time")
                    .item(0)
                    ?.textContent
                    ?.trim()
            val time =
                try {
                    if (timeStr != null) Instant.parse(timeStr) else Instant.now()
                } catch (_: Exception) {
                    Instant.now()
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
        val trkptNodes = doc.getElementsByTagName("trkpt")
        for (i in 0 until trkptNodes.length) {
            val el = trkptNodes.item(i) as? Element ?: continue
            val lat = el.getAttribute("lat").toDoubleOrNull() ?: 0.0
            val lon = el.getAttribute("lon").toDoubleOrNull() ?: 0.0
            val ele =
                el
                    .getElementsByTagName("ele")
                    .item(0)
                    ?.textContent
                    ?.toDoubleOrNull() ?: 0.0
            val timeStr =
                el
                    .getElementsByTagName("time")
                    .item(0)
                    ?.textContent
                    ?.trim()
            val time =
                try {
                    if (timeStr != null) Instant.parse(timeStr) else Instant.now()
                } catch (_: Exception) {
                    Instant.now()
                }

            var speed =
                el
                    .getElementsByTagName("speed")
                    .item(0)
                    ?.textContent
                    ?.toDoubleOrNull() ?: 0.0
            if (speed == 0.0) {
                speed = el
                    .getElementsByTagNameNS("*", "speed")
                    .item(0)
                    ?.textContent
                    ?.toDoubleOrNull() ?: 0.0
            }

            points.add(
                TrackPoint(
                    latitude = lat,
                    longitude = lon,
                    altitudeMeters = ele,
                    speedMps = speed,
                    timestamp = time,
                ),
            )
        }

        return ParsedGpx(trackName, points, waypoints)
    }
}

data class ParsedGpx(
    val name: String,
    val points: List<TrackPoint>,
    val waypoints: List<Waypoint>,
)
