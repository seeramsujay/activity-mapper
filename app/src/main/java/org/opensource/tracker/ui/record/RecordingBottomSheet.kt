package org.opensource.tracker.ui.record

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.opensource.tracker.domain.model.TelemetryStats
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.ui.components.InteractiveProfileChart
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

    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp)
                .verticalScroll(scrollState),
    ) {
        // Drag Handle
        Box(
            modifier =
                Modifier
                    .align(Alignment.CenterHorizontally)
                    .width(44.dp)
                    .height(4.dp)
                    .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f), RoundedCornerShape(2.dp)),
        )

        Spacer(modifier = Modifier.height(12.dp))

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
                        Spacer(modifier = Modifier.width(8.dp))
                        Column {
                            Text(
                                text = "DRINKS BREAK IN PROGRESS",
                                fontWeight = FontWeight.Black,
                                fontSize = 13.sp,
                                color = Color(0xFFF59E0B),
                            )
                            val breakMin = breakDurationSeconds / 60
                            val breakSec = breakDurationSeconds % 60
                            Text(
                                text = String.format(Locale.US, "Stationary for %02d:%02d • GPS drift blocked", breakMin, breakSec),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        // Big Glove-Friendly Continue Button
                        Button(
                            onClick = onTogglePause,
                            modifier =
                                Modifier
                                    .weight(1.4f)
                                    .height(52.dp),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF10B981)),
                        ) {
                            Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(22.dp))
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("CONTINUE RUN", fontWeight = FontWeight.Black, fontSize = 13.sp, color = Color.White)
                        }

                        // Quick 1-tap Water Waypoint logger
                        OutlinedButton(
                            onClick = onLogWaterBreak,
                            modifier =
                                Modifier
                                    .weight(1.0f)
                                    .height(52.dp),
                            shape = RoundedCornerShape(14.dp),
                        ) {
                            Icon(
                                Icons.Default.LocalDrink,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                                tint = Color(0xFF06B6D4),
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("💧 LOG WATER", fontWeight = FontWeight.Bold, fontSize = 11.sp)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
        }

        // 1. Peek Header: Glanceable Hero Readouts (Speed/Pace, Distance, Time)
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Smoothed Speed / Pace
            Column(modifier = Modifier.weight(1.3f)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    val displaySpeed = if (smoothedSpeedKmh > 0.0) smoothedSpeedKmh else (currentPoint?.speedKmh ?: 0.0)
                    Text(
                        text = String.format(Locale.US, "%.1f", displaySpeed),
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = (-0.5).sp,
                    )
                    Spacer(modifier = Modifier.width(3.dp))
                    Text(
                        text = "km/h",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 4.dp),
                    )
                }
                Text(
                    text = "PACE: ${stats.avgPaceMinKm}/km",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.primary,
                    letterSpacing = 0.5.sp,
                )
            }

            // Distance
            Column(modifier = Modifier.weight(1.0f)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text = String.format(Locale.US, "%.2f", stats.distanceKm),
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Black,
                    )
                    Spacer(modifier = Modifier.width(3.dp))
                    Text(
                        text = "km",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 3.dp),
                    )
                }
                Text(
                    text = "DISTANCE",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    letterSpacing = 0.8.sp,
                )
            }

            // Time
            Column(modifier = Modifier.weight(1.0f)) {
                Text(
                    text = formatDuration(stats.totalDuration),
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Black,
                )
                Text(
                    text = "TIME",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    letterSpacing = 0.8.sp,
                )
            }

            // Pause / Resume Puck
            FilledIconButton(
                onClick = onTogglePause,
                modifier = Modifier.size(52.dp),
                shape = CircleShape,
                colors =
                    IconButtonDefaults.filledIconButtonColors(
                        containerColor = if (isPaused) Color(0xFF10B981) else MaterialTheme.colorScheme.surfaceVariant,
                    ),
            ) {
                Icon(
                    imageVector = if (isPaused) Icons.Default.PlayArrow else Icons.Default.Pause,
                    contentDescription = if (isPaused) "Resume" else "Pause",
                    tint = if (isPaused) Color.White else MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(28.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // 2. Action Buttons (Marker, OLED, Finish with Confirmation)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedButton(
                onClick = onAddWaypoint,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(Icons.Default.AddLocationAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("MARKER", fontWeight = FontWeight.Bold, fontSize = 11.sp)
            }

            FilledTonalButton(
                onClick = onToggleOled,
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(
                    Icons.Default.EnergySavingsLeaf,
                    contentDescription = "OLED Eco",
                    tint = Color(0xFF10B981),
                    modifier = Modifier.size(18.dp),
                )
            }

            // Finish button triggers confirmation dialog to prevent accidental sweat/pocket finishes
            Button(
                onClick = { showFinishConfirmDialog = true },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEF4444)),
            ) {
                Icon(Icons.Default.Stop, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("FINISH", fontWeight = FontWeight.Black, fontSize = 12.sp, color = Color.White)
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // 3. TurnBack Out-and-Back Threshold Card
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors =
                CardDefaults.cardColors(
                    containerColor =
                        if (turnBackTriggered) {
                            Color(
                                0xFFEF4444,
                            ).copy(alpha = 0.15f)
                        } else {
                            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.7f)
                        },
                ),
        ) {
            Column(modifier = Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.UTurnLeft,
                        contentDescription = null,
                        tint = if (turnBackTriggered) Color(0xFFEF4444) else MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = if (turnBackTriggered) "TURN-AROUND TRIGGERED!" else "SAFE OUTBOUND PHASE",
                        fontWeight = FontWeight.Black,
                        fontSize = 12.sp,
                        color = if (turnBackTriggered) Color(0xFFEF4444) else MaterialTheme.colorScheme.onSurface,
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    if (!turnBackTriggered) {
                        Text(
                            text = "${outboundRemainingSeconds / 60}m remaining",
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text =
                        if (turnBackTriggered) {
                            "You have reached your safe turn-back window. Begin returning to finish within your target time."
                        } else {
                            "Physics pacing: accounts for return fatigue (beta = 0.12) & headwind reserve."
                        },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // 4. Moving Time vs Stopped Time Metrics
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Card(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("MOVING TIME", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(formatDuration(stats.movingDuration), fontSize = 15.sp, fontWeight = FontWeight.Black)
                }
            }
            Card(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("STOPPED TIME", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(formatDuration(stats.stoppedDuration), fontSize = 15.sp, fontWeight = FontWeight.Black)
                }
            }
            Card(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("ELEV GAIN", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        String.format(Locale.US, "+%.0fm", stats.elevationGainM),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Black,
                        color = Color(0xFF10B981),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // 5. Interactive Elevation Profile Chart
        Text(
            text = "ELEVATION PROFILE",
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.ExtraBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(6.dp))
        InteractiveProfileChart(points = points)

        Spacer(modifier = Modifier.height(16.dp))

        // 6. Lap Splits Table & Fastest Split Spotlight
        if (stats.splits.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.Timer,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "LAP SPLITS (1 KM)",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(modifier = Modifier.height(8.dp))

            // Fastest Split Spotlight Banner
            stats.fastestSplit?.let { fast ->
                Card(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFFF59E0B).copy(alpha = 0.15f)),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Default.Bolt, contentDescription = null, tint = Color(0xFFF59E0B), modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "FASTEST SPLIT: Lap ${fast.lapNumber} (${fast.paceMinKm}/km)",
                            fontWeight = FontWeight.Black,
                            fontSize = 11.sp,
                            color = Color(0xFFD97706),
                        )
                        Spacer(modifier = Modifier.weight(1f))
                        Text(
                            text = String.format(Locale.US, "%.1f km/h", fast.avgSpeedKmh),
                            fontWeight = FontWeight.Bold,
                            fontSize = 11.sp,
                            color = Color(0xFFD97706),
                        )
                    }
                }
            }

            stats.splits.forEach { split ->
                Row(
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier =
                            Modifier
                                .size(24.dp)
                                .background(
                                    if (split.isFastest) Color(0xFFF59E0B) else MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                                    CircleShape,
                                ),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (split.isFastest) {
                            Text("⚡", fontSize = 11.sp)
                        } else {
                            Text(
                                "${split.lapNumber}",
                                fontSize = 11.sp,
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
                            Text("FASTEST", fontSize = 9.sp, fontWeight = FontWeight.Black, color = Color(0xFFD97706))
                        }
                    }
                    Text(
                        formatDuration(split.duration),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = String.format(Locale.US, "+%.0fm / -%.0fm", split.elevationGainM, split.elevationLossM),
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
    }

    // Accidental finish confirmation dialog
    if (showFinishConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showFinishConfirmDialog = false },
            title = { Text("Finish & Save Workout?", fontWeight = FontWeight.Black) },
            text = {
                Text(
                    "You have covered ${String.format(
                        Locale.US,
                        "%.2f km",
                        stats.distanceKm,
                    )} in ${formatDuration(stats.totalDuration)}. Are you sure you want to stop recording and save this activity?",
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        showFinishConfirmDialog = false
                        onFinish()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEF4444)),
                ) {
                    Text("Finish & Save", fontWeight = FontWeight.Bold, color = Color.White)
                }
            },
            dismissButton = {
                TextButton(onClick = { showFinishConfirmDialog = false }) {
                    Text("Keep Running")
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
