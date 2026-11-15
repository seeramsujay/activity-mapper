package org.opensource.tracker.data.gpx

import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.model.Waypoint
import org.opensource.tracker.domain.model.WaypointCategory
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import java.io.File
import java.io.InputStream
import java.io.StringWriter
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale

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
        startTime: Instant = points.firstOrNull()?.timestamp ?: Instant.now()
    ): String {
        val writer = StringWriter()
        writer.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        writer.write("<gpx version=\"1.1\" creator=\"TurnBack - Jetpack Compose\" ")
        writer.write("xmlns=\"http://www.topografix.com/GPX/1/1\" ")
        writer.write("xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" ")
        writer.write("xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\" ")
        writer.write("xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd ")
        writer.write("http://www.garmin.com/xmlschemas/TrackPointExtension/v1 http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd\">\n")

        // Metadata
        writer.write("  <metadata>\n")
        writer.write("    <name>${escapeXml(trackName)}</name>\n")
        writer.write("    <time>${ISO_FORMATTER.format(startTime)}</time>\n")
        writer.write("  </metadata>\n")

        // Waypoints (<wpt>)
        for (w in waypoints) {
            writer.write(String.format(Locale.US, "  <wpt lat=\"%.7f\" lon=\"%.7f\">\n", w.latitude, w.longitude))
            if (w.altitudeMeters != 0.0) {
                writer.write(String.format(Locale.US, "    <ele>%.2f</ele>\n", w.altitudeMeters))
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
        writer.write("    <type>${escapeXml(activityType.lowercase(Locale.ROOT))}</type>\n")
        writer.write("    <trkseg>\n")

        for (p in points) {
            writer.write(String.format(Locale.US, "      <trkpt lat=\"%.7f\" lon=\"%.7f\">\n", p.latitude, p.longitude))
            writer.write(String.format(Locale.US, "        <ele>%.2f</ele>\n", p.altitudeMeters))
            writer.write("        <time>${ISO_FORMATTER.format(p.timestamp)}</time>\n")
            if (p.speedMps > 0.0) {
                writer.write("        <extensions>\n")
                writer.write("          <gpxtpx:TrackPointExtension>\n")
                writer.write(String.format(Locale.US, "            <gpxtpx:speed>%.2f</gpxtpx:speed>\n", p.speedMps))
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
        waypoints: List<Waypoint> = emptyList()
    ): File {
        file.parentFile?.mkdirs()
        file.writeText(buildGpxString(trackName, activityType, points, waypoints))
        return file
    }

    private fun escapeXml(str: String): String {
        return str.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }
}

object GpxImporter {

    fun parse(inputStream: InputStream): ParsedGpx {
        val factory = XmlPullParserFactory.newInstance()
        factory.isNamespaceAware = true
        val parser = factory.newPullParser()
        parser.setInput(inputStream, "UTF-8")

        var trackName = "Imported Track"
        val points = mutableListOf<TrackPoint>()
        val waypoints = mutableListOf<Waypoint>()

        var inTrk = false
        var inWpt = false
        var curLat = 0.0
        var curLon = 0.0
        var curEle = 0.0
        var curSpeed = 0.0
        var curTime = Instant.now()
        var curName = ""
        var curDesc = ""
        var curSym = ""

        var eventType = parser.eventType
        while (eventType != XmlPullParser.END_DOCUMENT) {
            val tag = parser.name
            when (eventType) {
                XmlPullParser.START_TAG -> {
                    when (tag) {
                        "wpt" -> {
                            inWpt = true
                            curLat = parser.getAttributeValue(null, "lat")?.toDoubleOrNull() ?: 0.0
                            curLon = parser.getAttributeValue(null, "lon")?.toDoubleOrNull() ?: 0.0
                            curEle = 0.0
                            curTime = Instant.now()
                            curName = ""
                            curDesc = ""
                            curSym = ""
                        }
                        "trk" -> inTrk = true
                        "trkpt" -> {
                            curLat = parser.getAttributeValue(null, "lat")?.toDoubleOrNull() ?: 0.0
                            curLon = parser.getAttributeValue(null, "lon")?.toDoubleOrNull() ?: 0.0
                            curEle = 0.0
                            curSpeed = 0.0
                            curTime = Instant.now()
                        }
                        "name" -> {
                            val text = parser.nextText()
                            if (inWpt) curName = text
                            else if (inTrk && trackName == "Imported Track") trackName = text
                        }
                        "desc" -> if (inWpt) curDesc = parser.nextText()
                        "sym" -> if (inWpt) curSym = parser.nextText()
                        "ele" -> curEle = parser.nextText()?.toDoubleOrNull() ?: 0.0
                        "time" -> {
                            val timeStr = parser.nextText()
                            try {
                                curTime = Instant.parse(timeStr)
                            } catch (_: Exception) {}
                        }
                        "speed" -> curSpeed = parser.nextText()?.toDoubleOrNull() ?: 0.0
                    }
                }
                XmlPullParser.END_TAG -> {
                    when (tag) {
                        "wpt" -> {
                            inWpt = false
                            val category = when {
                                curSym.contains("water", ignoreCase = true) -> WaypointCategory.WATER
                                curSym.contains("scenic", ignoreCase = true) || curSym.contains("view", ignoreCase = true) -> WaypointCategory.VIEWPOINT
                                curSym.contains("camp", ignoreCase = true) -> WaypointCategory.CAMP
                                curSym.contains("danger", ignoreCase = true) || curSym.contains("hazard", ignoreCase = true) -> WaypointCategory.HAZARD
                                else -> WaypointCategory.NOTE
                            }
                            waypoints.add(
                                Waypoint(
                                    sessionId = 0L,
                                    name = curName.ifBlank { "Waypoint" },
                                    description = curDesc,
                                    latitude = curLat,
                                    longitude = curLon,
                                    altitudeMeters = curEle,
                                    category = category,
                                    timestamp = curTime
                                )
                            )
                        }
                        "trkpt" -> {
                            points.add(
                                TrackPoint(
                                    latitude = curLat,
                                    longitude = curLon,
                                    altitudeMeters = curEle,
                                    speedMps = curSpeed,
                                    timestamp = curTime
                                )
                            )
                        }
                        "trk" -> inTrk = false
                    }
                }
            }
            eventType = parser.next()
        }

        return ParsedGpx(trackName, points, waypoints)
    }
}

data class ParsedGpx(
    val name: String,
    val points: List<TrackPoint>,
    val waypoints: List<Waypoint>
)
