package org.opensource.tracker.ui.record

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddLocationAlt
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.EnergySavingsLeaf
import androidx.compose.material.icons.filled.LocalDrink
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.UTurnLeft
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import org.opensource.tracker.data.settings.AppSettings
import org.opensource.tracker.domain.model.TelemetryStats
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.ui.components.InteractiveProfileChart
import org.opensource.tracker.ui.util.UnitFormat
import java.time.Duration
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordingBottomSheetContent(
    currentPoint: TrackPoint?,
    smoothedSpeedKmh: Double,
    stats: TelemetryStats,
    points: List<TrackPoint>,
    isPaused: Boolean,
    breakDurationSeconds: Long,
    turnBackTriggered: Boolean,
    outboundRemainingSeconds: Long,
    onTogglePause: () -> Unit,
    onAddWaypoint: () -> Unit,
    onLogWaterBreak: () -> Unit,
    onToggleOled: () -> Unit,
    onFinish: () -> Unit,
) {
    val scrollState = rememberScrollState()
    var showFinishConfirmDialog by remember { mutableStateOf(false) }
    val appSettings = AppSettings.getInstance(LocalContext.current)
    val imperial = appSettings.useImperialUnits

    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp)
                .verticalScroll(scrollState),
    ) {
        // Dedicated Drinks Break Hero Banner when Paused
        if (isPaused) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFFF59E0B).copy(alpha = 0.15f)),
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.LocalDrink,
                            contentDescription = null,
                            tint = Color(0xFFF59E0B),
                            modifier = Modifier.size(24.dp),
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Column {
                            Text(
                                "DRINKS & TRAIL BREAK",
                                fontWeight = FontWeight.Black,
                                fontSize = 13.sp,
                                color = Color(0xFFF59E0B),
                            )
                            Text(
                                "GPS radio suspended • Battery saved",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    val breakMin = breakDurationSeconds / 60
                    val breakSec = breakDurationSeconds % 60
                    Text(
                        text = String.format(Locale.US, "%02d:%02d", breakMin, breakSec),
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Black,
                        color = Color(0xFFF59E0B),
                    )

                    Spacer(modifier = Modifier.height(10.dp))

                    Button(
                        onClick = onTogglePause,
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF59E0B)),
                        shape = RoundedCornerShape(12.dp),
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("RESUME WORKOUT", fontWeight = FontWeight.Bold)
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
        }

        // Hero Turn-Back Countdown Card (The Core Differentiator)
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(20.dp),
            colors =
                CardDefaults.cardColors(
                    containerColor =
                        if (turnBackTriggered) {
                            Color(0xFFEF4444).copy(alpha = 0.18f)
                        } else {
                            MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
                        },
                ),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.UTurnLeft,
                            contentDescription = null,
                            tint = if (turnBackTriggered) Color(0xFFEF4444) else MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(22.dp),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = if (turnBackTriggered) "HEAD BACK NOW" else "OUTBOUND WINDOW",
                            fontWeight = FontWeight.Black,
                            fontSize = 12.sp,
                            letterSpacing = 0.6.sp,
                            color = if (turnBackTriggered) Color(0xFFEF4444) else MaterialTheme.colorScheme.primary,
                        )
                    }

                    Text(
                        text = if (turnBackTriggered) "Turn-Around Alert" else "Fatigue β=0.12",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                val remHours = outboundRemainingSeconds / 3600
                val remMinutes = (outboundRemainingSeconds % 3600) / 60
                val remSecs = outboundRemainingSeconds % 60
                val timeRemainingStr =
                    if (turnBackTriggered) {
                        "00:00"
                    } else if (remHours > 0) {
                        String.format(Locale.US, "%02d:%02d:%02d", remHours, remMinutes, remSecs)
                    } else {
                        String.format(Locale.US, "%02d:%02d", remMinutes, remSecs)
                    }

                Text(
                    text = timeRemainingStr,
                    fontSize = 42.sp,
                    fontWeight = FontWeight.Black,
                    color = if (turnBackTriggered) Color(0xFFEF4444) else MaterialTheme.colorScheme.onSurface,
                )

                Text(
                    text =
                        if (turnBackTriggered) {
                            "You have reached your halfway threshold. Turn around now to complete your route within target time."
                        } else {
                            "Remaining outbound running time before return leg is required."
                        },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // High-Contrast Large Metrics Grid (Distance & Speed)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Card(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(
                        "DISTANCE",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = String.format(Locale.US, "%.2f", UnitFormat.distanceValue(stats.distanceKm, imperial)),
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Black,
                    )
                    Text(
                        UnitFormat.distanceUnit(imperial),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Card(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(
                        "SPEED",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = String.format(Locale.US, "%.1f", UnitFormat.speedValue(smoothedSpeedKmh, imperial)),
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Black,
                        color = Color(0xFF06B6D4),
                    )
                    Text(
                        UnitFormat.speedUnit(imperial),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Card(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(
                        "ELAPSED",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = formatDuration(stats.totalDuration),
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Black,
                    )
                    Text("time", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        // Secondary Metrics: Pace & Elevation
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Card(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Timer,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Column {
                        Text(
                            "PACE",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "${UnitFormat.pace(stats.avgPaceMinKm, imperial)} ${UnitFormat.paceUnit(imperial)}",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Black,
                        )
                    }
                }
            }

            Card(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Bolt,
                        contentDescription = null,
                        tint = Color(0xFF10B981),
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Column {
                        Text(
                            "ELEV GAIN",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            UnitFormat.elevation(stats.elevationGainM, imperial),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Black,
                            color = Color(0xFF10B981),
                        )
                    }
                }
            }
        }

        // Live Elevation Profile Chart
        if (points.size >= 3) {
            Spacer(modifier = Modifier.height(14.dp))
            InteractiveProfileChart(points = points)
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Trail Action Bar (Drop Waypoint, Water Stop, OLED toggle)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilledTonalButton(
                onClick = onAddWaypoint,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(Icons.Default.AddLocationAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("Waypoint", fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }

            FilledTonalButton(
                onClick = onLogWaterBreak,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(
                    Icons.Default.LocalDrink,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = Color(0xFF06B6D4),
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text("Water", fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }

            FilledTonalButton(
                onClick = onToggleOled,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(
                    Icons.Default.EnergySavingsLeaf,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = Color(0xFF10B981),
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text("OLED", fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Big Primary Pause & Finish Controls
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Button(
                onClick = onTogglePause,
                modifier = Modifier.weight(1f).height(54.dp),
                shape = RoundedCornerShape(16.dp),
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = if (isPaused) Color(0xFF10B981) else Color(0xFFF59E0B),
                    ),
            ) {
                Icon(if (isPaused) Icons.Default.PlayArrow else Icons.Default.Pause, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = if (isPaused) "RESUME" else "PAUSE",
                    fontWeight = FontWeight.Black,
                    fontSize = 15.sp,
                )
            }

            Button(
                onClick = {
                    if (appSettings.confirmStopRecording) showFinishConfirmDialog = true else onFinish()
                },
                modifier = Modifier.weight(1f).height(54.dp),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEF4444)),
            ) {
                Icon(Icons.Default.Stop, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("FINISH", fontWeight = FontWeight.Black, fontSize = 15.sp)
            }
        }

        Spacer(modifier = Modifier.height(10.dp))
    }

    if (showFinishConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showFinishConfirmDialog = false },
            title = { Text("Finish & Save Workout?", fontWeight = FontWeight.Black) },
            text = {
                Text(
                    "This will complete your workout recording, export a standard GPX file, and save detailed telemetry statistics to your local library.",
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        showFinishConfirmDialog = false
                        onFinish()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                ) {
                    Text("Save & Complete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showFinishConfirmDialog = false }) {
                    Text("Keep Recording")
                }
            },
        )
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
