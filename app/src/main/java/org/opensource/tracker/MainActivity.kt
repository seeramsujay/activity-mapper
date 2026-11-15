package org.opensource.tracker

import android.Manifest
import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.opensource.tracker.data.db.AppDatabase
import org.opensource.tracker.data.db.TrackEntity
import org.opensource.tracker.data.db.WaypointEntity
import org.opensource.tracker.data.gpx.GpxExporter
import org.opensource.tracker.data.wal.RecordingWal
import org.opensource.tracker.domain.turnback.TurnBackEngine
import org.opensource.tracker.service.TrackingService
import org.opensource.tracker.ui.navigation.TurnBackNavGraph
import org.opensource.tracker.ui.theme.TurnBackTheme
import java.io.File

class MainActivity : ComponentActivity() {
    private var trackingService: TrackingService? = null
    private var isServiceBound = false

    private val serviceConnection =
        object : ServiceConnection {
            override fun onServiceConnected(
                name: ComponentName?,
                service: IBinder?,
            ) {
                val binder = service as TrackingService.LocalBinder
                trackingService = binder.getService()
                isServiceBound = true
                serviceBoundState.value = trackingService
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                trackingService = null
                isServiceBound = false
                serviceBoundState.value = null
            }
        }

    private val serviceBoundState = mutableStateOf<TrackingService?>(null)

    @SuppressLint("BatteryLife")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Bind to tracking service
        val intent = Intent(this, TrackingService::class.java)
        bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)

        setContent {
            var isOled by remember { mutableStateOf(false) }
            var showRecoveryDialog by remember { mutableStateOf(false) }
            var showBatteryOptimizationDialog by remember { mutableStateOf(false) }
            val walFile = File(filesDir, "active_recording.wal")

            // Global permission launcher for GPS and Notifications
            val permissionLauncher =
                rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.RequestMultiplePermissions(),
                ) {
                    checkBatteryOptimization { showBatteryOptimizationDialog = true }
                }

            LaunchedEffect(Unit) {
                val perms =
                    mutableListOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                    )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    perms.add(Manifest.permission.POST_NOTIFICATIONS)
                }
                val needsPerms =
                    perms.any {
                        ContextCompat.checkSelfPermission(this@MainActivity, it) != PackageManager.PERMISSION_GRANTED
                    }
                if (needsPerms) {
                    permissionLauncher.launch(perms.toTypedArray())
                } else {
                    checkBatteryOptimization { showBatteryOptimizationDialog = true }
                }
            }

            if (RecordingWal.hasActiveRecording(walFile) && trackingService?.isTracking?.value != true) {
                showRecoveryDialog = true
            }

            TurnBackTheme(isOled = isOled) {
                TurnBackNavGraph(
                    service = serviceBoundState.value,
                    isOled = isOled,
                    onToggleOled = { isOled = !isOled },
                )

                if (showBatteryOptimizationDialog) {
                    AlertDialog(
                        onDismissRequest = { showBatteryOptimizationDialog = false },
                        title = { Text("Disable Battery Optimization") },
                        text = {
                            Text(
                                "To ensure background GPS tracking, turn-back audio/haptic alerts, and continuous workout timing are not killed when your screen turns off, please grant battery optimization exemption.",
                            )
                        },
                        confirmButton = {
                            Button(
                                onClick = {
                                    showBatteryOptimizationDialog = false
                                    try {
                                        val batteryIntent =
                                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                                data = Uri.parse("package:$packageName")
                                            }
                                        startActivity(batteryIntent)
                                    } catch (_: Exception) {
                                        try {
                                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                        } catch (_: Exception) {
                                        }
                                    }
                                },
                            ) {
                                Text("Allow / Settings")
                            }
                        },
                        dismissButton = {
                            TextButton(onClick = { showBatteryOptimizationDialog = false }) {
                                Text("Later")
                            }
                        },
                    )
                }

                if (showRecoveryDialog) {
                    AlertDialog(
                        onDismissRequest = { showRecoveryDialog = false },
                        title = { Text("Recover Previous Session") },
                        text = {
                            Text(
                                "A recording was interrupted unexpectedly (battery loss or crash). Would you like to restore and save it to your library?",
                            )
                        },
                        confirmButton = {
                            Button(
                                onClick = {
                                    showRecoveryDialog = false
                                    lifecycleScope.launch(Dispatchers.IO) {
                                        val recovered = RecordingWal.recover(walFile)
                                        if (recovered.points.isNotEmpty()) {
                                            val stats = TurnBackEngine.computeStats(recovered.points)
                                            val title = "Recovered Activity ${System.currentTimeMillis()}"
                                            val gpxFile =
                                                File(filesDir, "tracks/recovered_${System.currentTimeMillis()}.gpx")
                                            GpxExporter.exportToFile(
                                                file = gpxFile,
                                                trackName = title,
                                                activityType = "RUN",
                                                points = recovered.points,
                                                waypoints = recovered.waypoints,
                                            )
                                            val db = AppDatabase.getInstance(applicationContext)
                                            val id =
                                                db.trackDao().insertTrack(
                                                    TrackEntity(
                                                        title = title,
                                                        startTime =
                                                            recovered.points
                                                                .first()
                                                                .timestamp
                                                                .toEpochMilli(),
                                                        endTime =
                                                            recovered.points
                                                                .last()
                                                                .timestamp
                                                                .toEpochMilli(),
                                                        distanceKm = stats.distanceKm,
                                                        movingDurationSeconds = stats.movingDuration.seconds,
                                                        totalDurationSeconds = stats.totalDuration.seconds,
                                                        avgSpeedKmh = stats.avgSpeedKmh,
                                                        maxSpeedKmh = stats.maxSpeedKmh,
                                                        elevationGainMeters = stats.elevationGainM,
                                                        elevationLossMeters = stats.elevationLossM,
                                                        gpxFilePath = gpxFile.absolutePath,
                                                    ),
                                                )
                                            db.waypointDao().insertWaypoints(
                                                recovered.waypoints.map { w ->
                                                    WaypointEntity(
                                                        trackId = id,
                                                        name = w.name,
                                                        description = w.description,
                                                        latitude = w.latitude,
                                                        longitude = w.longitude,
                                                        altitudeMeters = w.altitudeMeters,
                                                        category = w.category.name,
                                                        timestamp = w.timestamp.toEpochMilli(),
                                                    )
                                                },
                                            )
                                        }
                                        walFile.delete()
                                    }
                                },
                            ) {
                                Text("Restore & Save")
                            }
                        },
                        dismissButton = {
                            TextButton(
                                onClick = {
                                    showRecoveryDialog = false
                                    walFile.delete()
                                },
                            ) {
                                Text("Discard")
                            }
                        },
                    )
                }
            }
        }
    }

    private fun checkBatteryOptimization(onNeedsPrompt: () -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (pm != null && !pm.isIgnoringBatteryOptimizations(packageName)) {
                onNeedsPrompt()
            }
        }
    }

    override fun onDestroy() {
        if (isServiceBound) {
            unbindService(serviceConnection)
            isServiceBound = false
        }
        super.onDestroy()
    }
}
