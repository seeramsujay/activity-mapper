package org.opensource.tracker.ui.detail

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import org.opensource.tracker.data.db.AppDatabase
import org.opensource.tracker.data.db.TrackEntity
import org.opensource.tracker.data.db.WaypointEntity
import org.opensource.tracker.data.gpx.GpxImporter
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.turnback.TurnBackEngine
import org.opensource.tracker.service.TrackingService
import org.opensource.tracker.ui.components.InteractiveProfileChart
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.time.Duration
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrackDetailScreen(
    trackId: Long,
    service: TrackingService? = null,
    onBack: () -> Unit,
    onOverlayOnMap: () -> Unit = {},
) {
    val context = LocalContext.current
    var track by remember { mutableStateOf<TrackEntity?>(null) }
    var waypoints by remember { mutableStateOf<List<WaypointEntity>>(emptyList()) }
    var points by remember { mutableStateOf<List<TrackPoint>>(emptyList()) }

    LaunchedEffect(trackId) {
        val db = AppDatabase.getInstance(context)
        val t = db.trackDao().getTrackById(trackId)
        track = t
        waypoints = db.waypointDao().getWaypointsList(trackId)

        t?.gpxFilePath?.let { path ->
            val file = File(path)
            if (file.exists()) {
                val parsed = GpxImporter.parse(FileInputStream(file))
                points = parsed.points
            }
        }
    }

    val currentTrack = track
    val stats = remember(points) { TurnBackEngine.computeStats(points) }
    val isCurrentlyOverlaid =
        service
            ?.referenceTrack
            ?.collectAsState()
            ?.value
            ?.trackId == trackId

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(currentTrack?.title ?: "Activity Summary", fontWeight = FontWeight.Black) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    currentTrack?.gpxFilePath?.let { path ->
                        IconButton(
                            onClick = {
                                val file = File(path)
                                if (file.exists()) {
                                    val uri =
                                        FileProvider.getUriForFile(
                                            context,
                                            "${context.packageName}.fileprovider",
                                            file,
                                        )
                                    val shareIntent =
                                        Intent(Intent.ACTION_SEND).apply {
                                            type = "application/gpx+xml"
                                            putExtra(Intent.EXTRA_STREAM, uri)
                                            putExtra(Intent.EXTRA_SUBJECT, currentTrack.title)
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        }
                                    context.startActivity(Intent.createChooser(shareIntent, "Share GPX Track"))
                                }
                            },
                        ) {
                            Icon(Icons.Default.Share, contentDescription = "Share GPX")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
    ) { padding ->
        if (currentTrack == null) {
            Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Loading activity...")
            }
            return@Scaffold
        }

        val scrollState = rememberScrollState()

        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(scrollState)
                    .padding(16.dp),
        ) {
            // Activity Title & Date Header Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Text(
                        text = currentTrack.title,
                        fontWeight = FontWeight.Black,
                        fontSize = 20.sp,
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    val dateFormatted =
                        SimpleDateFormat("EEEE, MMMM d, yyyy • HH:mm", Locale.getDefault()).format(
                            Date(currentTrack.startTime),
                        )
                    Text(
                        text = "$dateFormatted • ${currentTrack.activityType}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Export GPX Action Button
            Button(
                onClick = {
                    currentTrack.gpxFilePath?.let { path ->
                        val file = File(path)
                        if (file.exists()) {
                            val uri =
                                FileProvider.getUriForFile(
                                    context,
                                    "${context.packageName}.fileprovider",
                                    file,
                                )
                            val shareIntent =
                                Intent(Intent.ACTION_SEND).apply {
                                    type = "application/gpx+xml"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_SUBJECT, currentTrack.title)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                            context.startActivity(Intent.createChooser(shareIntent, "Export GPX Track"))
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().height(48.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
            ) {
                Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("EXPORT AS GPX", fontWeight = FontWeight.Black, fontSize = 13.sp)
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Ghost Route Action Card: Overlay past track on map while currently running
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors =
                    CardDefaults.cardColors(
                        containerColor =
                            if (isCurrentlyOverlaid) {
                                Color(
                                    0xFF8B5CF6,
                                ).copy(alpha = 0.15f)
                            } else {
                                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
                            },
                    ),
            ) {
                Row(
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.Route,
                        contentDescription = null,
                        tint = if (isCurrentlyOverlaid) Color(0xFF8B5CF6) else MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(24.dp),
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = if (isCurrentlyOverlaid) "GHOST TRACK ACTIVE ON MAP" else "OVERLAY ON RUN AS GHOST TRACK",
                            fontWeight = FontWeight.Black,
                            fontSize = 12.sp,
                            color = if (isCurrentlyOverlaid) Color(0xFF8B5CF6) else MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            text = "Follow this route & compare real-time pacing",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Button(
                        onClick = {
                            if (isCurrentlyOverlaid) {
                                service?.clearReferenceTrack()
                            } else {
                                service?.setReferenceTrack(currentTrack.id, currentTrack.title, points)
                                onOverlayOnMap()
                            }
                        },
                        shape = RoundedCornerShape(12.dp),
                        colors =
                            ButtonDefaults.buttonColors(
                                containerColor = if (isCurrentlyOverlaid) Color(0xFF6B7280) else Color(0xFF8B5CF6),
                            ),
                    ) {
                        Text(
                            text = if (isCurrentlyOverlaid) "Remove" else "Overlay",
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp,
                            color = Color.White,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(14.dp))

            // Hero Metric Cards (Distance, Duration, Pace, Calories)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MetricCard(
                    title = "DISTANCE",
                    value = String.format(Locale.US, "%.2f km", currentTrack.distanceKm),
                    modifier = Modifier.weight(1f),
                )
                MetricCard(
                    title = "DURATION",
                    value = formatDuration(Duration.ofSeconds(currentTrack.totalDurationSeconds)),
                    modifier = Modifier.weight(1f),
                )
            }

            Spacer(modifier = Modifier.height(10.dp))

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MetricCard(
                    title = "AVG SPEED",
                    value = String.format(Locale.US, "%.1f km/h", currentTrack.avgSpeedKmh),
                    modifier = Modifier.weight(1f),
                )
                MetricCard(
                    title = "ELEV GAIN",
                    value = String.format(Locale.US, "+%.0f m", currentTrack.elevationGainMeters),
                    valueColor = Color(0xFF10B981),
                    modifier = Modifier.weight(1f),
                )
            }

            // Fastest Split Hero Highlight
            stats.fastestSplit?.let { fast ->
                Spacer(modifier = Modifier.height(10.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MetricCard(
                        title = "⚡ FASTEST SPLIT",
                        value = "Lap ${fast.lapNumber} (${fast.paceMinKm}/km)",
                        valueColor = Color(0xFFD97706),
                        modifier = Modifier.weight(1.3f),
                    )
                    MetricCard(
                        title = "TOP SPLIT SPEED",
                        value = String.format(Locale.US, "%.1f km/h", fast.avgSpeedKmh),
                        valueColor = Color(0xFFD97706),
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Interactive Elevation Chart
            Text(
                text = "ELEVATION & SPEED PROFILE",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(8.dp))
            InteractiveProfileChart(points = points)

            Spacer(modifier = Modifier.height(20.dp))

            // Detailed Exercise Telemetry Breakdown Table
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.FitnessCenter,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("TELEMETRY BREAKDOWN", fontWeight = FontWeight.Black, fontSize = 12.sp)
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    DetailRow("Average Speed", String.format(Locale.US, "%.1f km/h", currentTrack.avgSpeedKmh))
                    DetailRow("Maximum Speed", String.format(Locale.US, "%.1f km/h", currentTrack.maxSpeedKmh))
                    DetailRow("Average Pace", stats.avgPaceMinKm + " /km")
                    DetailRow("Best Pace", stats.bestPaceMinKm + " /km")

                    stats.fastestSplit?.let { fast ->
                        DetailRow(
                            "⚡ Fastest 1-km Split",
                            "Lap ${fast.lapNumber} • ${fast.paceMinKm} /km (${
                                String.format(
                                    Locale.US,
                                    "%.1f km/h",
                                    fast.avgSpeedKmh,
                                )
                            })",
                            Color(0xFFD97706),
                        )
                    }
                    stats.slowestSplit?.let { slow ->
                        DetailRow(
                            "Slowest 1-km Split",
                            "Lap ${slow.lapNumber} • ${slow.paceMinKm} /km",
                            MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    Divider(modifier = Modifier.padding(vertical = 10.dp))

                    DetailRow("Elevation Gain", String.format(Locale.US, "+%.0f m", currentTrack.elevationGainMeters))
                    DetailRow("Elevation Loss", String.format(Locale.US, "-%.0f m", currentTrack.elevationLossMeters))
                    DetailRow(
                        "Altitude Range",
                        String.format(Locale.US, "%.0fm – %.0fm", stats.minAltitudeM, stats.maxAltitudeM),
                    )

                    Divider(modifier = Modifier.padding(vertical = 10.dp))

                    DetailRow("Out-and-Back Threshold", "${currentTrack.targetDurationSeconds / 60}m target")
                    DetailRow(
                        "Turn-Around Triggered",
                        if (currentTrack.turnBackTriggeredAt != null) "Yes (Turned back)" else "Completed Outbound",
                    )
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Lap Splits Table (1-km / 1-mi endurance splits)
            if (stats.splits.isNotEmpty()) {
                Text(
                    text = "KILOMETER SPLITS",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(8.dp))

                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp),
                    colors =
                        CardDefaults.cardColors(
                            containerColor =
                                MaterialTheme.colorScheme.surfaceVariant.copy(
                                    alpha = 0.5f,
                                ),
                        ),
                ) {
                    Column(modifier = Modifier.padding(14.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                "KM",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "PACE",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "TIME",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "ELEV",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Divider()

                        for (split in stats.splits) {
                            Row(
                                modifier =
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 8.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Box(
                                    modifier =
                                        Modifier
                                            .size(24.dp)
                                            .background(
                                                if (split.isFastest) {
                                                    Color(0xFFD97706).copy(alpha = 0.2f)
                                                } else {
                                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                                                },
                                                CircleShape,
                                            ),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (split.isFastest) {
                                        Text("⚡", fontSize = 11.sp)
                                    } else {
                                        Text(
                                            "${split.lapNumber}",
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Black,
                                            color = MaterialTheme.colorScheme.primary,
                                        )
                                    }
                                }
                                Spacer(modifier = Modifier.width(10.dp))
                                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.weight(1.2f)) {
                                    Text(
                                        text = "${split.paceMinKm} /km",
                                        fontSize = 12.sp,
                                        fontWeight = if (split.isFastest) FontWeight.Black else FontWeight.Bold,
                                        color = if (split.isFastest) Color(0xFFD97706) else MaterialTheme.colorScheme.onSurface,
                                    )
                                    if (split.isFastest) {
                                        Spacer(modifier = Modifier.width(4.dp))
                                        Text(
                                            "FASTEST",
                                            fontSize = 9.sp,
                                            fontWeight = FontWeight.Black,
                                            color = Color(0xFFD97706),
                                        )
                                    }
                                }
                                Text(
                                    formatDuration(split.duration),
                                    fontSize = 12.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    text =
                                        String.format(
                                            Locale.US,
                                            "+%.0fm / -%.0fm",
                                            split.elevationGainM,
                                            split.elevationLossM,
                                        ),
                                    fontSize = 11.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun MetricCard(
    title: String,
    value: String,
    valueColor: Color = MaterialTheme.colorScheme.onSurface,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                title,
                fontSize = 9.sp,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(value, fontSize = 18.sp, fontWeight = FontWeight.Black, color = valueColor)
        }
    }
}

@Composable
private fun DetailRow(
    label: String,
    value: String,
    color: Color = MaterialTheme.colorScheme.onSurface,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold, color = color)
    }
}

private fun formatDuration(d: Duration): String {
    val h = d.toHours()
    val m = (d.toMinutes() % 60)
    val s = (d.seconds % 60)
    return if (h > 0) {
        String.format("%d:%02d:%02d", h, m, s)
    } else {
        String.format("%02d:%02d", m, s)
    }
}
