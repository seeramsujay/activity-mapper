package org.opensource.tracker.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.opensource.tracker.MainActivity
import org.opensource.tracker.R
import org.opensource.tracker.data.db.AppDatabase
import org.opensource.tracker.data.db.TrackEntity
import org.opensource.tracker.data.db.WaypointEntity
import org.opensource.tracker.data.gpx.GpxExporter
import org.opensource.tracker.data.wal.RecordingWal
import org.opensource.tracker.domain.model.ActivityType
import org.opensource.tracker.domain.model.TelemetryStats
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.model.Waypoint
import org.opensource.tracker.domain.model.WaypointCategory
import org.opensource.tracker.domain.turnback.TurnBackEngine
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.Locale
import kotlin.math.floor

data class ReferenceTrack(
    val trackId: Long,
    val title: String,
    val points: List<TrackPoint>,
)

class TrackingService :
    Service(),
    LocationListener {
    private val binder = LocalBinder()
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private lateinit var locationManager: LocationManager
    private lateinit var notificationManager: NotificationManager
    private var vibrator: Vibrator? = null

    private var wal: RecordingWal? = null
    private var tickerJob: Job? = null

    // Tracking configuration
    private var targetDuration = Duration.ofHours(1)
    private var fatigueBeta = 0.12
    private var safetyBufferPercent = 15.0
    private var outboundLimitDuration = Duration.ZERO
    private var activityType = ActivityType.RUN

    private var startTime: Instant = Instant.now()
    private var movingTimeMs: Long = 0L
    private var lastFixTimeMs: Long = 0L
    private var breakStartTimeMs: Long = 0L
    private var lastAlertedKm: Int = 0

    // Recent speed smoothing window (last 5 fixes)
    private val speedHistory = ArrayDeque<Double>(5)

    // StateFlows exposed to Jetpack Compose UI
    private val _isTracking = MutableStateFlow(false)
    val isTracking: StateFlow<Boolean> = _isTracking.asStateFlow()

    private val _isPaused = MutableStateFlow(false)
    val isPaused: StateFlow<Boolean> = _isPaused.asStateFlow()

    private val _breakDurationSeconds = MutableStateFlow(0L)
    val breakDurationSeconds: StateFlow<Long> = _breakDurationSeconds.asStateFlow()

    private val _currentPoint = MutableStateFlow<TrackPoint?>(null)
    val currentPoint: StateFlow<TrackPoint?> = _currentPoint.asStateFlow()

    private val _smoothedSpeedKmh = MutableStateFlow(0.0)
    val smoothedSpeedKmh: StateFlow<Double> = _smoothedSpeedKmh.asStateFlow()

    private val _points = MutableStateFlow<List<TrackPoint>>(emptyList())
    val points: StateFlow<List<TrackPoint>> = _points.asStateFlow()

    private val _waypoints = MutableStateFlow<List<Waypoint>>(emptyList())
    val waypoints: StateFlow<List<Waypoint>> = _waypoints.asStateFlow()

    private val _stats = MutableStateFlow(TelemetryStats())
    val stats: StateFlow<TelemetryStats> = _stats.asStateFlow()

    private val _turnBackTriggered = MutableStateFlow(false)
    val turnBackTriggered: StateFlow<Boolean> = _turnBackTriggered.asStateFlow()

    private val _outboundRemainingSeconds = MutableStateFlow(0L)
    val outboundRemainingSeconds: StateFlow<Long> = _outboundRemainingSeconds.asStateFlow()

    // Ghost / Reference track overlay
    private val _referenceTrack = MutableStateFlow<ReferenceTrack?>(null)
    val referenceTrack: StateFlow<ReferenceTrack?> = _referenceTrack.asStateFlow()

    inner class LocalBinder : Binder() {
        fun getService(): TrackingService = this@TrackingService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        vibrator =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

        createNotificationChannel()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        when (intent?.action) {
            ACTION_START -> {
                val targetSec = intent.getLongExtra(EXTRA_TARGET_DURATION_SEC, 3600L)
                val beta = intent.getDoubleExtra(EXTRA_BETA, 0.12)
                val typeStr = intent.getStringExtra(EXTRA_ACTIVITY_TYPE) ?: "RUN"
                startTracking(
                    targetSec = targetSec,
                    beta = beta,
                    activityType =
                        try {
                            ActivityType.valueOf(typeStr)
                        } catch (_: Exception) {
                            ActivityType.RUN
                        },
                )
            }
            ACTION_PAUSE -> pauseTracking()
            ACTION_RESUME -> resumeTracking()
            ACTION_STOP -> stopTracking()
        }
        return START_STICKY
    }

    fun setReferenceTrack(
        trackId: Long,
        title: String,
        points: List<TrackPoint>,
    ) {
        _referenceTrack.value = ReferenceTrack(trackId, title, points)
    }

    fun clearReferenceTrack() {
        _referenceTrack.value = null
    }

    fun startTracking(
        targetSec: Long,
        beta: Double,
        activityType: ActivityType,
    ) {
        if (_isTracking.value) return

        this.targetDuration = Duration.ofSeconds(targetSec)
        this.fatigueBeta = beta
        this.activityType = activityType
        this.outboundLimitDuration = TurnBackEngine.computeOutboundLimit(targetDuration, fatigueBeta, safetyBufferPercent)
        this.startTime = Instant.now()
        this.movingTimeMs = 0L
        this.lastFixTimeMs = System.currentTimeMillis()
        this.breakStartTimeMs = 0L
        this.lastAlertedKm = 0
        this.speedHistory.clear()

        _points.value = emptyList()
        _waypoints.value = emptyList()
        _stats.value = TelemetryStats()
        _turnBackTriggered.value = false
        _isTracking.value = true
        _isPaused.value = false
        _breakDurationSeconds.value = 0L
        _smoothedSpeedKmh.value = 0.0

        // Initialize crash-proof WAL
        val walFile = File(filesDir, "active_recording.wal")
        if (walFile.exists()) walFile.delete()
        wal = RecordingWal.create(walFile)

        // Request GPS updates directly
        try {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000L,
                1.0f,
                this,
            )
        } catch (_: SecurityException) {
        }

        // Launch Foreground Service Notification
        val notification = buildNotification("Recording started...", "Calculating out-and-back threshold")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        startTicker()
    }

    fun pauseTracking() {
        if (!_isTracking.value || _isPaused.value) return
        _isPaused.value = true
        breakStartTimeMs = System.currentTimeMillis()
        wal?.appendBreak()

        // Battery Saver: Unregister GPS hardware listener during pause so GPS radio powers down
        try {
            locationManager.removeUpdates(this)
        } catch (_: Exception) {
        }

        updateNotification()
    }

    fun resumeTracking() {
        if (!_isTracking.value || !_isPaused.value) return
        _isPaused.value = false
        breakStartTimeMs = 0L
        _breakDurationSeconds.value = 0L
        lastFixTimeMs = System.currentTimeMillis()

        // Re-enable GPS hardware listener upon resuming
        try {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000L,
                1.0f,
                this,
            )
        } catch (_: SecurityException) {
        }

        updateNotification()
    }

    fun addWaypoint(
        name: String,
        description: String = "",
        category: WaypointCategory = WaypointCategory.NOTE,
    ) {
        val cur = _currentPoint.value ?: return
        val waypoint =
            Waypoint(
                sessionId = 0L,
                name = name.ifBlank { category.displayName },
                description = description,
                latitude = cur.latitude,
                longitude = cur.longitude,
                altitudeMeters = cur.altitudeMeters,
                category = category,
                timestamp = Instant.now(),
            )
        wal?.appendWaypoint(waypoint)
        _waypoints.update { it + waypoint }
    }

    fun logWaterBreakWaypoint() {
        addWaypoint(
            name = "Water Stop",
            description = "Hydration break on trail",
            category = WaypointCategory.WATER,
        )
    }

    fun stopAndSave(
        title: String? = null,
        onSaved: ((Long) -> Unit)? = null,
    ) {
        if (!_isTracking.value) return
        serviceScope.launch(Dispatchers.IO) {
            val finalPoints = _points.value
            val finalWaypoints = _waypoints.value
            val finalStats = TurnBackEngine.computeStats(finalPoints)
            val sessionTitle = title?.ifBlank { null } ?: "${activityType.displayName} ${System.currentTimeMillis()}"

            // 1. Export GPX file
            val gpxFile = File(filesDir, "tracks/track_${System.currentTimeMillis()}.gpx")
            GpxExporter.exportToFile(
                file = gpxFile,
                trackName = sessionTitle,
                activityType = activityType.name,
                points = finalPoints,
                waypoints = finalWaypoints,
            )

            // 2. Persist in Room Database
            val db = AppDatabase.getInstance(applicationContext)
            val trackEntity =
                TrackEntity(
                    title = sessionTitle,
                    activityType = activityType.name,
                    startTime = startTime.toEpochMilli(),
                    endTime = System.currentTimeMillis(),
                    targetDurationSeconds = targetDuration.seconds,
                    safetyBufferPercent = safetyBufferPercent,
                    turnBackTriggeredAt = if (_turnBackTriggered.value) System.currentTimeMillis() else null,
                    distanceKm = finalStats.distanceKm,
                    movingDurationSeconds = finalStats.movingDuration.seconds,
                    totalDurationSeconds = finalStats.totalDuration.seconds,
                    avgSpeedKmh = finalStats.avgSpeedKmh,
                    maxSpeedKmh = finalStats.maxSpeedKmh,
                    elevationGainMeters = finalStats.elevationGainM,
                    elevationLossMeters = finalStats.elevationLossM,
                    gpxFilePath = gpxFile.absolutePath,
                )
            val trackId = db.trackDao().insertTrack(trackEntity)

            val waypointEntities =
                finalWaypoints.map { w ->
                    WaypointEntity(
                        trackId = trackId,
                        name = w.name,
                        description = w.description,
                        latitude = w.latitude,
                        longitude = w.longitude,
                        altitudeMeters = w.altitudeMeters,
                        category = w.category.name,
                        timestamp = w.timestamp.toEpochMilli(),
                    )
                }
            db.waypointDao().insertWaypoints(waypointEntities)

            // 3. Clean up active WAL
            wal?.close()
            wal = null
            val walFile = File(filesDir, "active_recording.wal")
            if (walFile.exists()) walFile.delete()

            stopTracking()
            onSaved?.invoke(trackId)
        }
    }

    private fun stopTracking() {
        tickerJob?.cancel()
        tickerJob = null
        try {
            locationManager.removeUpdates(this)
        } catch (_: Exception) {
        }
        wal?.close()
        wal = null
        _isTracking.value = false
        _isPaused.value = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onLocationChanged(location: Location) {
        if (!_isTracking.value || _isPaused.value) return

        // 1. Accuracy Filter: discard fixes with poor horizontal accuracy (> 25m under heavy canopy)
        if (location.hasAccuracy() && location.accuracy > 25.0f) {
            return
        }

        // 2. Max Human Speed Sanity Filter: discard impossible sprint speeds (> 14 m/s ~ 50 km/h)
        if (location.hasSpeed() && location.speed > 14.0f) {
            return
        }

        val lastPoint = _points.value.lastOrNull()
        val now = System.currentTimeMillis()

        // 3. Teleportation / Multipath Jump Filter: discard jumps > 60m within 2 seconds
        if (lastPoint != null && now - lastPoint.timestamp.toEpochMilli() <= 2000L) {
            val dist =
                TurnBackEngine.haversineDistanceMeters(
                    lastPoint.latitude,
                    lastPoint.longitude,
                    location.latitude,
                    location.longitude,
                )
            if (dist > 60.0) {
                return
            }
        }

        val rawSpeedMps = if (location.hasSpeed()) location.speed.toDouble() else 0.0
        val point =
            TrackPoint(
                latitude = location.latitude,
                longitude = location.longitude,
                altitudeMeters = if (location.hasAltitude()) location.altitude else 0.0,
                speedMps = rawSpeedMps,
                accuracyMeters = if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0,
                bearingDegrees = if (location.hasBearing()) location.bearing else 0f,
                timestamp = Instant.ofEpochMilli(location.time),
            )

        // Smooth speed via rolling window (last 5 fixes)
        if (speedHistory.size >= 5) speedHistory.removeFirst()
        speedHistory.addLast(point.speedKmh)
        _smoothedSpeedKmh.value = speedHistory.average()

        // Write immediately to WAL (crash safety)
        wal?.appendPoint(point)

        // Update state
        _currentPoint.value = point
        _points.update { it + point }

        // Stationary Jitter Filter: only accumulate moving time if speed >= 0.4 m/s
        if (lastFixTimeMs > 0 && point.speedMps >= 0.4) {
            movingTimeMs += (now - lastFixTimeMs).coerceAtLeast(0)
        }
        lastFixTimeMs = now

        val updatedStats = TurnBackEngine.computeStats(_points.value, Duration.ofMillis(now - startTime.toEpochMilli()))
        _stats.value = updatedStats

        // Haptic 1-km Split Notification for Trail Runners
        val currentKm = floor(updatedStats.distanceKm).toInt()
        if (currentKm > lastAlertedKm) {
            lastAlertedKm = currentKm
            triggerSplitAlert()
        }
    }

    private fun startTicker() {
        tickerJob?.cancel()
        tickerJob =
            serviceScope.launch {
                while (isActive) {
                    if (_isTracking.value) {
                        if (_isPaused.value) {
                            if (breakStartTimeMs > 0L) {
                                _breakDurationSeconds.value = (System.currentTimeMillis() - breakStartTimeMs) / 1000L
                            }
                        } else {
                            val now = Instant.now()
                            val elapsedOutbound = Duration.between(startTime, now)
                            val remainingSec = (outboundLimitDuration.seconds - elapsedOutbound.seconds).coerceAtLeast(0L)
                            _outboundRemainingSeconds.value = remainingSec

                            // Check Turn-Back Trigger
                            if (!_turnBackTriggered.value && remainingSec == 0L && outboundLimitDuration.seconds > 0) {
                                _turnBackTriggered.value = true
                                triggerTurnBackAlert()
                            }
                        }
                        updateNotification()
                    }
                    delay(1000L)
                }
            }
    }

    private fun triggerTurnBackAlert() {
        // Haptic pulse alert (SOS pattern: 3 long pulses)
        val pattern = longArrayOf(0, 400, 200, 400, 200, 400)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, -1)
        }
    }

    private fun triggerSplitAlert() {
        // Double pulse for kilometer split
        val pattern = longArrayOf(0, 150, 100, 150)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, -1)
        }
    }

    private fun updateNotification() {
        val s = _stats.value
        val speedStr = String.format(Locale.US, "%.1f km/h", _smoothedSpeedKmh.value)
        val distStr = String.format(Locale.US, "%.2f km", s.distanceKm)
        val timeStr = formatDuration(s.totalDuration)

        val turnBackStatus =
            if (_turnBackTriggered.value) {
                "⚠️ TURN-AROUND TRIGGERED (Head Back)"
            } else if (_isPaused.value) {
                val breakMin = _breakDurationSeconds.value / 60
                val breakSec = _breakDurationSeconds.value % 60
                String.format(Locale.US, "Drinks Break: %02d:%02d (Tap to Continue)", breakMin, breakSec)
            } else {
                val remMin = _outboundRemainingSeconds.value / 60
                "Outbound Window: ${remMin}m remaining"
            }

        val content = "$distStr • $speedStr • $timeStr\n$turnBackStatus"
        val notification =
            buildNotification(
                title = if (_isPaused.value) "Workout Paused (Break)" else "Recording ${activityType.displayName}",
                text = content,
            )
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(
        title: String,
        text: String,
    ): Notification {
        val mainIntent =
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
        val pendingMainIntent =
            PendingIntent.getActivity(
                this,
                0,
                mainIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        // Action: Pause / Resume directly from Notification drawer
        val actionIntent =
            Intent(this, TrackingService::class.java).apply {
                action = if (_isPaused.value) ACTION_RESUME else ACTION_PAUSE
            }
        val pendingActionIntent =
            PendingIntent.getService(
                this,
                1,
                actionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val actionTitle = if (_isPaused.value) "Continue Run" else "Pause (Drink Break)"

        return NotificationCompat
            .Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSmallIcon(R.drawable.ic_foreground)
            .setContentIntent(pendingMainIntent)
            .addAction(0, actionTitle, pendingActionIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.tracking_notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = getString(R.string.tracking_notification_channel_desc)
                    setShowBadge(false)
                }
            notificationManager.createNotificationChannel(channel)
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

    override fun onDestroy() {
        serviceScope.cancel()
        wal?.close()
        super.onDestroy()
    }

    companion object {
        const val NOTIFICATION_ID = 4201
        const val CHANNEL_ID = "turnback_tracking_channel"

        const val ACTION_START = "org.opensource.tracker.ACTION_START"
        const val ACTION_PAUSE = "org.opensource.tracker.ACTION_PAUSE"
        const val ACTION_RESUME = "org.opensource.tracker.ACTION_RESUME"
        const val ACTION_STOP = "org.opensource.tracker.ACTION_STOP"

        const val EXTRA_TARGET_DURATION_SEC = "EXTRA_TARGET_DURATION_SEC"
        const val EXTRA_BETA = "EXTRA_BETA"
        const val EXTRA_ACTIVITY_TYPE = "EXTRA_ACTIVITY_TYPE"
    }
}
