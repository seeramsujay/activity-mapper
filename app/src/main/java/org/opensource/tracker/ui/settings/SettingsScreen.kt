package org.opensource.tracker.ui.settings

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.DownloadForOffline
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Vibration
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.opensource.tracker.data.db.AppDatabase
import org.opensource.tracker.data.settings.AppSettings
import org.opensource.tracker.data.settings.ChartXAxis
import org.opensource.tracker.data.settings.CoordFormat
import org.opensource.tracker.data.settings.RecordProfile
import org.opensource.tracker.ui.components.OfflineMapsDialog
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    isOled: Boolean,
    onToggleOled: () -> Unit,
) {
    val context = LocalContext.current
    val settings = remember { AppSettings.getInstance(context) }
    val scope = rememberCoroutineScope()

    var showAdvancedSettings by remember { mutableStateOf(false) }
    var showOfflineMapsDialog by remember { mutableStateOf(false) }

    // Settings state
    var themeMode by remember { mutableStateOf(settings.themeMode) }
    var useImperial by remember { mutableStateOf(settings.useImperialUnits) }
    var coordFormat by remember { mutableStateOf(settings.coordFormat) }
    var chartXAxis by remember { mutableStateOf(settings.chartXAxis) }
    var beta by remember { mutableFloatStateOf(settings.beta) }
    var safetyBuffer by remember { mutableFloatStateOf(settings.safetyBuffer) }
    var hapticsEnabled by remember { mutableStateOf(settings.hapticsEnabled) }
    var audioAlarmsEnabled by remember { mutableStateOf(settings.audioAlarmsEnabled) }
    var autoPauseMusic by remember { mutableStateOf(settings.autoPauseMusic) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings & Preferences", fontWeight = FontWeight.Black) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
    ) { padding ->
        val scrollState = rememberScrollState()

        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(scrollState)
                    .padding(16.dp),
        ) {
            // 1. ADVANCED SETTINGS HERO SHORTCUT
            Card(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .clickable { showAdvancedSettings = true },
                shape = RoundedCornerShape(18.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.6f)),
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.Tune,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(28.dp),
                    )
                    Spacer(modifier = Modifier.width(14.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "ADVANCED SETTINGS",
                            fontWeight = FontWeight.Black,
                            fontSize = 14.sp,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            text = "GPS intervals, recording profiles, database WAL & backup",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Icon(
                        Icons.Default.ChevronRight,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // 2. DISPLAY & UNITS
            SectionTitle("DISPLAY & UNITS", Icons.Default.Palette)

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    // OLED Toggle
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Pure-Black OLED Mode", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text(
                                "Maximizes battery life on OLED displays by turning off dark pixels",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = isOled,
                            onCheckedChange = {
                                settings.isOled = !isOled
                                onToggleOled()
                            },
                        )
                    }

                    Divider(modifier = Modifier.padding(vertical = 12.dp))

                    // Imperial / Metric Units
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Imperial Units", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text(
                                if (useImperial) "Miles, mph, feet" else "Kilometers, km/h, meters",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = useImperial,
                            onCheckedChange = {
                                useImperial = it
                                settings.useImperialUnits = it
                            },
                        )
                    }

                    Divider(modifier = Modifier.padding(vertical = 12.dp))

                    // Coordinate Format
                    Text("Coordinate Display Format", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(6.dp))
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        SegmentedButton(
                            selected = coordFormat == CoordFormat.DECIMAL,
                            onClick = {
                                coordFormat = CoordFormat.DECIMAL
                                settings.coordFormat = CoordFormat.DECIMAL
                            },
                            shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                        ) {
                            Text("Decimal (37.77)")
                        }
                        SegmentedButton(
                            selected = coordFormat == CoordFormat.DMS,
                            onClick = {
                                coordFormat = CoordFormat.DMS
                                settings.coordFormat = CoordFormat.DMS
                            },
                            shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                        ) {
                            Text("DMS (37° 46' N)")
                        }
                    }

                    Divider(modifier = Modifier.padding(vertical = 12.dp))

                    // Chart X-Axis
                    Text("Elevation Chart X-Axis", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(6.dp))
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        SegmentedButton(
                            selected = chartXAxis == ChartXAxis.DISTANCE,
                            onClick = {
                                chartXAxis = ChartXAxis.DISTANCE
                                settings.chartXAxis = ChartXAxis.DISTANCE
                            },
                            shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                        ) {
                            Text("Distance (km)")
                        }
                        SegmentedButton(
                            selected = chartXAxis == ChartXAxis.DURATION,
                            onClick = {
                                chartXAxis = ChartXAxis.DURATION
                                settings.chartXAxis = ChartXAxis.DURATION
                            },
                            shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                        ) {
                            Text("Duration (time)")
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // 3. TURNBACK PACING FORMULA
            SectionTitle("TURNBACK PACING & FATIGUE", Icons.Default.Speed)

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = String.format(Locale.US, "Fatigue Compensation Factor (β): %.2f", beta),
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                    )
                    Text(
                        "Accounts for return fatigue on out-and-back trail sessions. 0.00 = symmetric 50%, 0.12 = standard endurance.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Slider(
                        value = beta,
                        onValueChange = {
                            beta = it
                            settings.beta = it
                        },
                        valueRange = 0.0f..0.35f,
                        steps = 6,
                    )

                    Spacer(modifier = Modifier.height(10.dp))

                    Text(
                        text = String.format(Locale.US, "Contingency Safety Buffer: %.0f%%", safetyBuffer),
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                    )
                    Text(
                        "Reserve cushion for unexpected headwinds, terrain changes, or water stops.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Slider(
                        value = safetyBuffer,
                        onValueChange = {
                            safetyBuffer = it
                            settings.safetyBuffer = it
                        },
                        valueRange = 5.0f..25.0f,
                        steps = 3,
                    )
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // 4. AUDIO, HAPTICS & ALARMS
            SectionTitle("ALERTS & SENSORY", Icons.Default.Vibration)

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Haptic Feedback Pulses", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text(
                                "Vibrate on 1-km splits and Turn-Back SOS pattern",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = hapticsEnabled,
                            onCheckedChange = {
                                hapticsEnabled = it
                                settings.hapticsEnabled = it
                            },
                        )
                    }

                    Divider(modifier = Modifier.padding(vertical = 12.dp))

                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Audio Alarms", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text(
                                "Sound high-priority audio alert when out-and-back limit is reached",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = audioAlarmsEnabled,
                            onCheckedChange = {
                                audioAlarmsEnabled = it
                                settings.audioAlarmsEnabled = it
                            },
                        )
                    }

                    Divider(modifier = Modifier.padding(vertical = 12.dp))

                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Auto-Pause Media", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text(
                                "Pause media playback when workout is paused or stopped",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = autoPauseMusic,
                            onCheckedChange = {
                                autoPauseMusic = it
                                settings.autoPauseMusic = it
                            },
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // 5. OFFLINE MAPS & STORAGE
            SectionTitle("OFFLINE MAPS & TILE STORAGE", Icons.Default.DownloadForOffline)

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        "Download regional map tiles for complete offline outdoor trail navigation or import Mapsforge .map vector files directly.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Button(
                        onClick = { showOfflineMapsDialog = true },
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                    ) {
                        Icon(
                            Icons.Default.DownloadForOffline,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Manage Offline Maps & Vectors (.map)", fontWeight = FontWeight.Bold)
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // 6. ABOUT & CREATOR
            SectionTitle("ABOUT & DEVELOPER", Icons.Default.Info)

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier =
                                Modifier
                                    .size(44.dp)
                                    .background(
                                        MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                                        RoundedCornerShape(12.dp),
                                    ),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Default.Person,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(24.dp),
                            )
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text("TurnBack Activity Mapper", fontWeight = FontWeight.Black, fontSize = 16.sp)
                            Text(
                                "Created & Maintained by Sujay Seeram",
                                fontWeight = FontWeight.Bold,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Text(
                        "TurnBack is an ultra-lightweight, 100% serverless, battery-optimized GPS activity tracker designed for runners, cyclists, and hikers with fatigue-asymmetric pacing.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    Divider()

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column {
                            Text("GitHub Repository", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            Text(
                                "seeramsujay/activity-mapper",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        FilledTonalButton(
                            onClick = {
                                try {
                                    val browserIntent =
                                        Intent(
                                            Intent.ACTION_VIEW,
                                            Uri.parse("https://github.com/seeramsujay/activity-mapper"),
                                        )
                                    context.startActivity(browserIntent)
                                } catch (_: Exception) {
                                }
                            },
                            shape = RoundedCornerShape(10.dp),
                        ) {
                            Icon(Icons.Default.Code, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("View Repo", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "License",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "GNU AGPL v3.0 (Copyleft Open Source)",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold,
                        )
                    }

                    Spacer(modifier = Modifier.height(4.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "Architecture",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "Native Jetpack Compose + Room + WAL",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold,
                        )
                    }

                    Spacer(modifier = Modifier.height(4.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "Privacy",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "100% On-Device & Zero Tracking",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF10B981),
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }

    if (showOfflineMapsDialog) {
        OfflineMapsDialog(onDismiss = { showOfflineMapsDialog = false })
    }

    if (showAdvancedSettings) {
        AdvancedSettingsDialog(
            settings = settings,
            onDismiss = { showAdvancedSettings = false },
        )
    }
}

@Composable
private fun SectionTitle(
    title: String,
    icon: ImageVector,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            title,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Black,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    Spacer(modifier = Modifier.height(8.dp))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AdvancedSettingsDialog(
    settings: AppSettings,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selectedProfile by remember { mutableStateOf(settings.recordProfile) }
    var samplingRateMs by remember { mutableLongStateOf(settings.gpsSamplingRateMs) }
    var minDistanceM by remember { mutableFloatStateOf(settings.minDistanceFilterM) }
    var maxAccuracyM by remember { mutableFloatStateOf(settings.maxAccuracyFilterM) }
    var extraFiltering by remember { mutableStateOf(settings.extraFiltering) }
    var autoMarkStops by remember { mutableStateOf(settings.autoMarkStops) }
    var confirmStop by remember { mutableStateOf(settings.confirmStopRecording) }

    var totalPointsInDb by remember { mutableStateOf(0) }
    var isBackingUp by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) {
            val db = AppDatabase.getInstance(context)
            val tracks = db.trackDao().getAllTracksList()
            totalPointsInDb = tracks.sumOf { it.totalDurationSeconds.toInt() }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Advanced Settings", fontWeight = FontWeight.Black) },
        text = {
            val scrollState = rememberScrollState()
            Column(modifier = Modifier.verticalScroll(scrollState).padding(vertical = 4.dp)) {
                // Record Profile
                Text(
                    "RECORDING PROFILE PRESET",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.height(6.dp))
                RecordProfile.values().forEach { profile ->
                    val isSel = selectedProfile == profile
                    Card(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .padding(vertical = 3.dp)
                                .clickable {
                                    selectedProfile = profile
                                    samplingRateMs = profile.intervalMs
                                    minDistanceM = profile.minDistanceMeters
                                    maxAccuracyM = profile.maxAccuracyMeters
                                    settings.recordProfile = profile
                                    settings.gpsSamplingRateMs = profile.intervalMs
                                    settings.minDistanceFilterM = profile.minDistanceMeters
                                    settings.maxAccuracyFilterM = profile.maxAccuracyMeters
                                },
                        shape = RoundedCornerShape(10.dp),
                        colors =
                            CardDefaults.cardColors(
                                containerColor =
                                    if (isSel) {
                                        MaterialTheme.colorScheme.primaryContainer
                                    } else {
                                        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                                    },
                            ),
                    ) {
                        Row(modifier = Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                profile.displayName,
                                fontWeight = FontWeight.Bold,
                                fontSize = 13.sp,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                "${profile.intervalMs / 1000}s • ${profile.minDistanceMeters.toInt()}m",
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                Divider(modifier = Modifier.padding(vertical = 12.dp))

                // GPS Hardware Fine Tuning
                Text(
                    "GPS HARDWARE TUNING",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.height(6.dp))

                Text("GPS Sampling Interval: ${samplingRateMs / 1000}s", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Slider(
                    value = (samplingRateMs / 1000).toFloat(),
                    onValueChange = {
                        val s = it.toLong() * 1000L
                        samplingRateMs = s
                        settings.gpsSamplingRateMs = s
                    },
                    valueRange = 1f..15f,
                    steps = 13,
                )

                Text(
                    "Min Distance Filter: ${minDistanceM.toInt()} meters",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                )
                Slider(
                    value = minDistanceM,
                    onValueChange = {
                        minDistanceM = it
                        settings.minDistanceFilterM = it
                    },
                    valueRange = 1f..30f,
                    steps = 5,
                )

                Text(
                    "Max Accuracy Threshold: ${maxAccuracyM.toInt()} meters",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                )
                Slider(
                    value = maxAccuracyM,
                    onValueChange = {
                        maxAccuracyM = it
                        settings.maxAccuracyFilterM = it
                    },
                    valueRange = 10f..100f,
                    steps = 8,
                )

                Divider(modifier = Modifier.padding(vertical = 12.dp))

                // Filters & Dialogs
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Extra Speed & Jump Filtering",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f),
                    )
                    Switch(
                        checked = extraFiltering,
                        onCheckedChange = {
                            extraFiltering = it
                            settings.extraFiltering = it
                        },
                    )
                }

                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Auto-Detect Stops & Pauses",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f),
                    )
                    Switch(
                        checked = autoMarkStops,
                        onCheckedChange = {
                            autoMarkStops = it
                            settings.autoMarkStops = it
                        },
                    )
                }

                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Confirm Stop Recording",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f),
                    )
                    Switch(
                        checked = confirmStop,
                        onCheckedChange = {
                            confirmStop = it
                            settings.confirmStopRecording = it
                        },
                    )
                }

                Divider(modifier = Modifier.padding(vertical = 12.dp))

                // Database WAL & Archive
                Text(
                    "DATABASE & ARCHIVE",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    "Crash-Proof WAL Mode: Active",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "Total GPS Track Database: Room SQLite",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Spacer(modifier = Modifier.height(10.dp))

                Button(
                    onClick = {
                        isBackingUp = true
                        scope.launch(Dispatchers.IO) {
                            try {
                                val backupDir = File(context.filesDir, "backups")
                                backupDir.mkdirs()
                                val backupZip = File(backupDir, "backup_${System.currentTimeMillis()}.zip")
                                ZipOutputStream(FileOutputStream(backupZip)).use { zipOut ->
                                    val tracksDir = File(context.filesDir, "tracks")
                                    if (tracksDir.exists()) {
                                        tracksDir.listFiles()?.forEach { file ->
                                            zipOut.putNextEntry(ZipEntry("tracks/${file.name}"))
                                            file.inputStream().use { it.copyTo(zipOut) }
                                            zipOut.closeEntry()
                                        }
                                    }
                                }
                                withContext(Dispatchers.Main) {
                                    isBackingUp = false
                                    Toast
                                        .makeText(context, "Backup saved to: ${backupZip.name}", Toast.LENGTH_LONG)
                                        .show()
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    isBackingUp = false
                                    Toast.makeText(context, "Backup failed: ${e.message}", Toast.LENGTH_SHORT).show()
                                }
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(44.dp),
                    shape = RoundedCornerShape(10.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                ) {
                    Icon(Icons.Default.Storage, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        if (isBackingUp) "Backing Up..." else "Create Database Backup (.zip)",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        },
        confirmButton = {
            Button(onClick = onDismiss) {
                Text("Done")
            }
        },
    )
}
