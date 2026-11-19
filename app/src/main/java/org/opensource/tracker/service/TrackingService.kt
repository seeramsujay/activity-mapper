package org.opensource.tracker.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.room.withTransaction
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
import kotlinx.coroutines.withContext
import org.opensource.tracker.MainActivity
import org.opensource.tracker.R
import org.opensource.tracker.TurnBackApplication
import org.opensource.tracker.data.db.AppDatabase
import org.opensource.tracker.data.db.TrackEntity
import org.opensource.tracker.data.db.WaypointEntity
import org.opensource.tracker.data.gpx.GpxExporter
import org.opensource.tracker.data.mesh.MeshManager
import org.opensource.tracker.data.settings.AppSettings
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

/** Live health of the GPS pipeline, surfaced in the UI so a silent failure is never invisible. */
enum class GpsStatus {
    IDLE,
    NO_PERMISSION,
    GPS_DISABLED,
    WAITING_FOR_FIX,
    WEAK_SIGNAL,
    ACTIVE,
}

class TrackingService :
    Service(),
    LocationListener {
    private val binder = LocalBinder()
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private lateinit var locationManager: LocationManager
    private lateinit var notificationManager: NotificationManager
    private lateinit var settings: AppSettings
    private var mesh: MeshManager? = null
    private var vibrator: Vibrator? = null

    private var wal: RecordingWal? = null
    private var tickerJob: Job? = null
    private var wakeLock: PowerManager.WakeLock? = null

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
    private var totalBreakDurationMs: Long = 0L
    private var lastAlertedKm: Int = 0
    private var pendingPoint: TrackPoint? = null

    // Recent speed smoothing window (last 5 fixes)
    private val speedHistory = ArrayDeque<Double>(5)

    // StateFlows exposed to Jetpack Compose UI
    private val _isTracking = MutableStateFlow(false)
    val isTracking: StateFlow<Boolean> = _isTracking.asStateFlow()

    private val _isPaused = MutableStateFlow(false)
    val isPaused: StateFlow<Boolean> = _isPaused.asStateFlow()

    private val _gpsStatus = MutableStateFlow(GpsStatus.IDLE)
    val gpsStatus: StateFlow<GpsStatus> = _gpsStatus.asStateFlow()

    private val _lastAccuracyMeters = MutableStateFlow<Float?>(null)
    val lastAccuracyMeters: StateFlow<Float?> = _lastAccuracyMeters.asStateFlow()

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
        settings = AppSettings.getInstance(this)
        mesh = (application as TurnBackApplication).mesh

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

        // Foreground-service type "location" throws on Android 14+ without the runtime permission.
        if (!hasLocationPermission()) {
            _gpsStatus.value = GpsStatus.NO_PERMISSION
            stopSelf()
            return
        }

        // Must be promoted to foreground promptly after startForegroundService().
        val notification = buildNotification("Recording started...", "Waiting for GPS fix")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: SecurityException) {
            _gpsStatus.value = GpsStatus.NO_PERMISSION
            stopSelf()
            return
        }

        this.targetDuration = Duration.ofSeconds(targetSec)
        this.activityType = activityType

        // Car mode has 0 return fatigue and symmetric 50% split
        // Fatigue factor and safety margin come from Settings (the intent extra is only a fallback default).
        val effectiveBeta = if (activityType == ActivityType.CAR) 0.0 else settings.beta.toDouble().takeIf { it > 0.0 } ?: beta
        val effectiveSafetyBuffer = if (activityType == ActivityType.CAR) 0.0 else settings.safetyBuffer.toDouble()
        this.fatigueBeta = effectiveBeta
        this.safetyBufferPercent = effectiveSafetyBuffer
        this.outboundLimitDuration =
            TurnBackEngine.computeOutboundLimit(targetDuration, effectiveBeta, effectiveSafetyBuffer)

        this.startTime = Instant.now()
        this.movingTimeMs = 0L
        this.lastFixTimeMs = System.currentTimeMillis()
        this.breakStartTimeMs = 0L
        this.totalBreakDurationMs = 0L
        this.lastAlertedKm = 0
        this.pendingPoint = null
        this.speedHistory.clear()

        _points.value = emptyList()
        _waypoints.value = emptyList()
        _stats.value = TelemetryStats(totalDuration = Duration.ZERO)
        _turnBackTriggered.value = false
        _isTracking.value = true
        _isPaused.value = false
        _breakDurationSeconds.value = 0L
        _smoothedSpeedKmh.value = 0.0
        _lastAccuracyMeters.value = null
        _gpsStatus.value =
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                GpsStatus.WAITING_FOR_FIX
            } else {
                GpsStatus.GPS_DISABLED
            }
        acquireWakeLock()

        // Initialize crash-proof WAL
        val walFile = File(filesDir, "active_recording.wal")
        if (walFile.exists()) walFile.delete()
        wal = RecordingWal.create(walFile)

        requestGpsUpdates()
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
        if (breakStartTimeMs > 0L) {
            totalBreakDurationMs += (System.currentTimeMillis() - breakStartTimeMs)
            breakStartTimeMs = 0L
        }
        _breakDurationSeconds.value = 0L
        lastFixTimeMs = System.currentTimeMillis()

        // Re-enable GPS hardware listener upon resuming
        _gpsStatus.value = GpsStatus.WAITING_FOR_FIX
        requestGpsUpdates()

        updateNotification()
    }

    /**
     * Registers for GPS fixes at the Settings sampling interval. The distance threshold is left at 0 on
     * purpose: the minimum-distance setting only decides which fixes are *stored*, while every fix still
     * refreshes live speed, position and the "my location" state.
     */
    private fun requestGpsUpdates() {
        try {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                settings.gpsSamplingRateMs.coerceIn(1000L, 60_000L),
                0f,
                this,
                mainLooper,
            )
        } catch (_: SecurityException) {
            _gpsStatus.value = GpsStatus.NO_PERMISSION
        }
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
        onFailed: ((String) -> Unit)? = null,
        onSaved: ((Long) -> Unit)? = null,
    ) {
        if (!_isTracking.value) return
        serviceScope.launch(Dispatchers.IO) {
            val finalPoints = _points.value
            val finalWaypoints = _waypoints.value

            if (finalPoints.isEmpty()) {
                // Nothing to save: don't write an empty track, just end the session cleanly.
                File(filesDir, "active_recording.wal").delete()
                withContext(Dispatchers.Main) {
                    stopTracking()
                    onFailed?.invoke("No GPS points were recorded, so nothing was saved.")
                }
                return@launch
            }

            val trackId =
                try {
                    saveSession(title, finalPoints, finalWaypoints)
                } catch (e: Exception) {
                    // Keep tracking state and the WAL intact so no data is lost; the user can retry.
                    withContext(Dispatchers.Main) {
                        onFailed?.invoke("Couldn't save activity (${e.message ?: "unknown error"}). Your data is safe, try again.")
                    }
                    return@launch
                }

            // Callbacks drive navigation/UI, so they must run on the main thread.
            withContext(Dispatchers.Main) {
                stopTracking() // closes the WAL; only then is it safe to delete it
                File(filesDir, "active_recording.wal").delete()
                onSaved?.invoke(trackId)
            }
        }
    }

    private suspend fun saveSession(
        title: String?,
        finalPoints: List<TrackPoint>,
        finalWaypoints: List<Waypoint>,
    ): Long {
        val nowMs = System.currentTimeMillis()
        val totalElapsed =
            Duration.ofMillis(((nowMs - startTime.toEpochMilli()) - totalBreakDurationMs).coerceAtLeast(0L))
        val finalStats = TurnBackEngine.computeStats(finalPoints, totalElapsed)
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
        return try {
            // One transaction: a failed attempt leaves no track row, so a retry can't create a duplicate.
            db.withTransaction {
                val trackId = db.trackDao().insertTrack(trackEntity)
                db.waypointDao().insertWaypoints(
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
                    },
                )
                trackId
            }
        } catch (e: Exception) {
            gpxFile.delete() // no orphaned export from a failed attempt
            throw e
        }
    }

    private fun stopTracking() {
        tickerJob?.cancel()
        tickerJob = null
        releaseWakeLock()
        _gpsStatus.value = GpsStatus.IDLE
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

        // 1. Accuracy Filter: discard fixes worse than the Settings tolerance (record profile / GPS filters)
        if (location.hasAccuracy()) _lastAccuracyMeters.value = location.accuracy
        if (location.hasAccuracy() && location.accuracy > settings.maxAccuracyFilterM) {
            _gpsStatus.value = GpsStatus.WEAK_SIGNAL
            return
        }
        _gpsStatus.value = GpsStatus.ACTIVE

        val extraFiltering = settings.extraFiltering

        // 2. Speed Sanity Filter: CAR allows up to 70 m/s (~250 km/h), foot activities capped at 14 m/s (~50 km/h)
        val maxSpeedMps = if (activityType == ActivityType.CAR) 70.0f else 14.0f
        if (extraFiltering && location.hasSpeed() && location.speed > maxSpeedMps) {
            return
        }

        val lastPoint = _points.value.lastOrNull()
        val now = System.currentTimeMillis()

        // 3. Teleportation / Multipath Jump Filter: discard jumps > 60m (250m for CAR) within 2 seconds
        val maxJumpMeters = if (activityType == ActivityType.CAR) 250.0 else 60.0
        if (extraFiltering && lastPoint != null && now - lastPoint.timestamp.toEpochMilli() <= 2000L) {
            val dist =
                TurnBackEngine.haversineDistanceMeters(
                    lastPoint.latitude,
                    lastPoint.longitude,
                    location.latitude,
                    location.longitude,
                )
            if (dist > maxJumpMeters) {
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
        _currentPoint.value = point
        mesh?.updateLocalPosition(point.latitude, point.longitude, point.speedKmh, point.altitudeMeters)

        // Stationary Jitter Filter: only accumulate moving time if speed >= 0.4 m/s
        if (lastFixTimeMs > 0 && point.speedMps >= 0.4) {
            movingTimeMs += (now - lastFixTimeMs).coerceAtLeast(0)
        }
        lastFixTimeMs = now

        // Minimum-distance filter: a fix that barely moved still refreshed live speed/position above, but
        // is not stored, which keeps tracks (and the WAL) small and removes standing-still jitter.
        val minDistanceM = settings.minDistanceFilterM.toDouble()
        if (lastPoint != null && minDistanceM > 0.0) {
            val moved =
                TurnBackEngine.haversineDistanceMeters(
                    lastPoint.latitude,
                    lastPoint.longitude,
                    point.latitude,
                    point.longitude,
                )
            if (moved < minDistanceM) {
                // Remember the latest skipped fix. Stats attribute each interval to the *later* fix's speed, so when
                // movement resumes we store this one first: the stationary stretch ends at a low-speed fix instead
                // of being counted as moving time by the next stored point.
                pendingPoint = point
                return
            }
        }

        pendingPoint?.let { pending ->
            wal?.appendPoint(pending)
            _points.update { it + pending }
        }
        pendingPoint = null

        // Write immediately to WAL (crash safety)
        wal?.appendPoint(point)
        _points.update { it + point }

        val activeElapsed =
            Duration.ofMillis(((now - startTime.toEpochMilli()) - totalBreakDurationMs).coerceAtLeast(0L))
        val updatedStats = TurnBackEngine.computeStats(_points.value, activeElapsed)
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
                            val nowMs = System.currentTimeMillis()
                            val totalElapsedMs = (nowMs - startTime.toEpochMilli()) - totalBreakDurationMs
                            val activeDuration = Duration.ofMillis(totalElapsedMs.coerceAtLeast(0L))

                            // Continuous 1-second elapsed time update so stopwatch ticks immediately
                            _stats.update { it.copy(totalDuration = activeDuration) }

                            val remainingSec =
                                (outboundLimitDuration.seconds - activeDuration.seconds).coerceAtLeast(0L)
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
        // Audible alarm (skipped for walks/hikes, where a loud tone is unwelcome), if enabled in Settings.
        if (settings.audioAlarmsEnabled && activityType != ActivityType.WALK && activityType != ActivityType.HIKE) {
            try {
                val tone = ToneGenerator(AudioManager.STREAM_ALARM, 90)
                tone.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 1500)
                serviceScope.launch {
                    delay(2000L)
                    tone.release()
                }
            } catch (_: RuntimeException) {
                // No audio route available; the haptic pulse below still fires.
            }
        }
        if (!settings.hapticsEnabled) return

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
        if (!settings.hapticsEnabled) return

        // Double pulse for kilometer split
        val pattern = longArrayOf(0, 150, 100, 150)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, -1)
        }
    }

    override fun onProviderEnabled(provider: String) {
        if (provider == LocationManager.GPS_PROVIDER && _isTracking.value && !_isPaused.value) {
            _gpsStatus.value = GpsStatus.WAITING_FOR_FIX
        }
    }

    override fun onProviderDisabled(provider: String) {
        if (provider == LocationManager.GPS_PROVIDER && _isTracking.value) {
            _gpsStatus.value = GpsStatus.GPS_DISABLED
        }
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock =
            pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "turnback:tracking").apply {
                setReferenceCounted(false)
                acquire(WAKE_LOCK_TIMEOUT_MS)
            }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
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
        releaseWakeLock()
        serviceScope.cancel()
        wal?.close()
        super.onDestroy()
    }

    companion object {
        const val WAKE_LOCK_TIMEOUT_MS = 12L * 60 * 60 * 1000
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
