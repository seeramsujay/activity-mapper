package org.opensource.tracker

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Bind to tracking service
        val intent = Intent(this, TrackingService::class.java)
        bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)

        setContent {
            var isOled by remember { mutableStateOf(false) }
            var showRecoveryDialog by remember { mutableStateOf(false) }
            val walFile = File(filesDir, "active_recording.wal")

            if (RecordingWal.hasActiveRecording(walFile) && trackingService?.isTracking?.value != true) {
                showRecoveryDialog = true
            }

            TurnBackTheme(isOled = isOled) {
                TurnBackNavGraph(
                    service = serviceBoundState.value,
                    isOled = isOled,
                    onToggleOled = { isOled = !isOled }
                )

                if (showRecoveryDialog) {
                    AlertDialog(
                        onDismissRequest = { showRecoveryDialog = false },
                        title = { Text("Recover Previous Session") },
                        text = { Text("A recording was interrupted unexpectedly (battery loss or crash). Would you like to restore and save it to your library?") },
                        confirmButton = {
                            Button(
                                onClick = {
                                    showRecoveryDialog = false
                                    lifecycleScope.launch(Dispatchers.IO) {
                                        val recovered = RecordingWal.recover(walFile)
                                        if (recovered.points.isNotEmpty()) {
                                            val stats = TurnBackEngine.computeStats(recovered.points)
                                            val title = "Recovered Activity ${System.currentTimeMillis()}"
                                            val gpxFile = File(filesDir, "tracks/recovered_${System.currentTimeMillis()}.gpx")
                                            GpxExporter.exportToFile(
                                                file = gpxFile,
                                                trackName = title,
                                                activityType = "RUN",
                                                points = recovered.points,
                                                waypoints = recovered.waypoints
                                            )
                                            val db = AppDatabase.getInstance(applicationContext)
                                            val id = db.trackDao().insertTrack(
                                                TrackEntity(
                                                    title = title,
                                                    startTime = recovered.points.first().timestamp.toEpochMilli(),
                                                    endTime = recovered.points.last().timestamp.toEpochMilli(),
                                                    distanceKm = stats.distanceKm,
                                                    movingDurationSeconds = stats.movingDuration.seconds,
                                                    totalDurationSeconds = stats.totalDuration.seconds,
                                                    avgSpeedKmh = stats.avgSpeedKmh,
                                                    maxSpeedKmh = stats.maxSpeedKmh,
                                                    elevationGainMeters = stats.elevationGainM,
                                                    elevationLossMeters = stats.elevationLossM,
                                                    gpxFilePath = gpxFile.absolutePath
                                                )
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
                                                        timestamp = w.timestamp.toEpochMilli()
                                                    )
                                                }
                                            )
                                        }
                                        walFile.delete()
                                    }
                                }
                            ) {
                                Text("Restore & Save")
                            }
                        },
                        dismissButton = {
                            TextButton(
                                onClick = {
                                    showRecoveryDialog = false
                                    walFile.delete()
                                }
                            ) {
                                Text("Discard")
                            }
                        }
                    )
                }
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
