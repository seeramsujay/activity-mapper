package org.opensource.tracker

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import org.opensource.tracker.db.DatabaseHelper
import org.opensource.tracker.filter.KalmanFilter
import org.opensource.tracker.util.GeoidHelper
import android.os.Handler
import android.os.Looper
import java.util.Locale

/**
 * High-performance Android Foreground Service executing continuous background GPS tracking.
 *
 * Implements:
 * - FOREGROUND_SERVICE_TYPE_LOCATION enforcement (API 29+).
 * - CPU Partial WakeLock ('TurnBack::GpsWakeLock') with safe acquiring/releasing lifecycle hooks.
 * - Ongoing high-priority notification with live distance and duration.
 * - Continuous high-resolution GPS streaming, throttled while stationary (stop detection).
 * - Mean Sea Level (MSL) altitude correction via Android 14 API or EGM96 Geoid undulation model.
 * - Dimensionally correct metric Kalman filter coordinate smoothing.
 * - Asymmetric fatigue turnaround logic: T_outbound = T_target / (1 + S * gamma).
 * - Crash/kill recovery: session parameters are persisted so a START_STICKY restart resumes logging.
 *
 * Elapsed time is "active workout time": wall-clock time while the service runs, plus the
 * [EXTRA_ELAPSED_BASE_MS] carried over from previous segments (pauses stop the service).
 * The Flutter HUD uses the same definition, so both sides agree on when to turn back.
 */
class GpsLoggingService : Service(), LocationListener {

    companion object {
        const val CHANNEL_ID = "GpsLoggingServiceChannel_HighPriority"
        const val NOTIFICATION_ID = 486
        const val ACTION_SET_GOOGLE_MAPS_MODE = "org.opensource.tracker.SET_GOOGLE_MAPS_MODE"
        const val EXTRA_ELAPSED_BASE_MS = "elapsedBaseMs"

        private const val PREFS_NAME = "turnback_tracking_state"
        private const val TICK_INTERVAL_MS = 3000L
        private const val ELAPSED_SAVE_EVERY_TICKS = 10 // ~30 s

        // Default accuracy gate: worse fixes are cold-start / network noise and add distance spikes.
        private const val DEFAULT_MAX_ACCURACY_M = 50f

        // Stop detection: after this many consecutive resting fixes, poll GPS slowly until movement resumes.
        private const val RESTING_SPEED_MPS = 0.3
        private const val STATIONARY_TICKS_THRESHOLD = 5
        private const val STATIONARY_INTERVAL_MS = 10_000L

        var isRunning = false
            private set

        /** The running service instance (null when stopped). Used for in-process state queries. */
        @Volatile
        var current: GpsLoggingService? = null
            private set

        // Direct callback hook to MainActivity (fast, in-process telemetry stream)
        var telemetryListener: ((lat: Double, lng: Double, alt: Double, acc: Float, speed: Float, time: Long) -> Unit)? = null
    }

    private lateinit var locationManager: LocationManager
    private lateinit var dbHelper: DatabaseHelper
    private lateinit var kalmanFilter: KalmanFilter
    private lateinit var prefs: SharedPreferences
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var wakeLock: PowerManager.WakeLock? = null

    var sessionId: Int = -1
        private set
    private var activityType: String = "run"
    private var targetDurationSeconds: Int = 0
    private var safetyBufferPct: Double = 8.0
    var turnBackAlerted = false
        private set

    // User settings (Settings > Record Profile & GPS / alerts)
    private var maxAccuracyMeters: Float = DEFAULT_MAX_ACCURACY_M
    private var minDistanceMeters: Float = 0f
    private var audioAlarms = true
    private var hapticAlarms = true
    private var autoPauseMusic = true

    // Active elapsed time = elapsedBaseMs + (now - segmentStartWallMs)
    private var elapsedBaseMs: Long = 0L
    private var segmentStartWallMs: Long = 0L

    // Telemetry accumulators
    private var totalDistanceMeters: Double = 0.0
    private var lastLocation: Location? = null      // last accepted fix (speed / stop detection)
    private var lastStoredLocation: Location? = null // last fix written to the DB (distance filter)

    // GPS polling state
    private var baseIntervalMs: Long = 1000L
    private var currentIntervalMs: Long = 1000L
    private var currentFastestIntervalMs: Long = 1000L
    private var currentDisplacementMeters: Float = 0.0f
    private var consecutiveStationaryTicks: Int = 0
    private var isStationaryMode = false

    // Google Maps Passive Piggyback / Battery Saver mode
    private var googleMapsMode: Boolean = false
    private var isWatchdogFallbackActive: Boolean = false
    private var lastLocationFixTimestampMs: Long = System.currentTimeMillis()
    private var gpsStatusText: String = "GPS Active"
    private var ticksSinceElapsedSave = 0
    private val tickHandler = Handler(Looper.getMainLooper())
    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return
            if (googleMapsMode) {
                val timeSinceLastFix = System.currentTimeMillis() - lastLocationFixTimestampMs
                if (!isWatchdogFallbackActive && timeSinceLastFix > 7000L) {
                    // Google Maps may have stopped or was backgrounded. Fallback to active high-accuracy GPS!
                    isWatchdogFallbackActive = true
                    applyLocationUpdates(currentIntervalMs, currentFastestIntervalMs, currentDisplacementMeters)
                    gpsStatusText = "GPS Active (Standalone Fallback)"
                } else if (isWatchdogFallbackActive && timeSinceLastFix <= 3000L) {
                    // Fixes flowing again from Google Maps, resume eco passive mode
                    isWatchdogFallbackActive = false
                    applyLocationUpdates(currentIntervalMs, currentFastestIntervalMs, currentDisplacementMeters)
                    gpsStatusText = "GPS Co-Navigating (Battery Saver)"
                }
            }
            // Time-based check: the alarm must fire even if no GPS fix arrives (tunnel, passive mode).
            checkTurnBackThreshold()
            updateLiveNotification()
            if (++ticksSinceElapsedSave >= ELAPSED_SAVE_EVERY_TICKS) {
                ticksSinceElapsedSave = 0
                dbHelper.saveActiveElapsed(sessionId, activeElapsedMs())
            }
            tickHandler.postDelayed(this, TICK_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        dbHelper = DatabaseHelper(this)
        kalmanFilter = KalmanFilter()
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
            fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        } catch (e: Exception) {
            fusedLocationClient = null
        }
    }

    /** Active workout time in milliseconds (excludes paused periods). */
    fun activeElapsedMs(): Long {
        if (segmentStartWallMs == 0L) return elapsedBaseMs
        return elapsedBaseMs + (System.currentTimeMillis() - segmentStartWallMs).coerceAtLeast(0L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_SET_GOOGLE_MAPS_MODE) {
            if (!isRunning) {
                // Started only to deliver a mode change while no session is tracking.
                stopSelf()
                return START_NOT_STICKY
            }
            val enabled = intent.getBooleanExtra("googleMapsMode", false)
            if (googleMapsMode != enabled) {
                googleMapsMode = enabled
                isWatchdogFallbackActive = false
                lastLocationFixTimestampMs = System.currentTimeMillis()
                applyLocationUpdates(currentIntervalMs, currentFastestIntervalMs, currentDisplacementMeters)
                gpsStatusText = if (googleMapsMode) "GPS Co-Navigating (Battery Saver)" else "GPS Active"
                persistState()
                updateLiveNotification()
            }
            return START_STICKY
        }

        if (intent == null) {
            // START_STICKY restart after the OS killed our process: resume the persisted session.
            if (!restoreState()) {
                stopSelf()
                return START_NOT_STICKY
            }
        } else {
            sessionId = intent.getIntExtra("sessionId", -1)
            activityType = intent.getStringExtra("activityType") ?: "run"
            targetDurationSeconds = intent.getIntExtra("targetDurationSeconds", 0)
            safetyBufferPct = intent.getDoubleExtra("safetyBufferPct", 8.0)
            googleMapsMode = intent.getBooleanExtra("googleMapsMode", false)
            baseIntervalMs = intent.getIntExtra("gpsIntervalMs", 1000).toLong().coerceIn(1000L, 15_000L)
            maxAccuracyMeters = intent.getFloatExtra("maxAccuracyM", DEFAULT_MAX_ACCURACY_M).coerceIn(5f, 500f)
            minDistanceMeters = intent.getFloatExtra("minDistanceM", 0f).coerceIn(0f, 100f)
            audioAlarms = intent.getBooleanExtra("audioAlarms", true)
            hapticAlarms = intent.getBooleanExtra("hapticAlarms", true)
            autoPauseMusic = intent.getBooleanExtra("autoPauseMusic", true)
            elapsedBaseMs = intent.getLongExtra(EXTRA_ELAPSED_BASE_MS, 0L).coerceAtLeast(0L)
            segmentStartWallMs = System.currentTimeMillis()
        }

        if (sessionId < 0) {
            stopSelf()
            return START_NOT_STICKY
        }

        isWatchdogFallbackActive = false
        lastLocationFixTimestampMs = System.currentTimeMillis()
        lastLocation = null
        lastStoredLocation = null
        consecutiveStationaryTicks = 0
        isStationaryMode = false
        // The DB flag is shared with the Flutter HUD so only one side ever sounds the alarm.
        turnBackAlerted = dbHelper.isTurnBackTriggered(sessionId)
        totalDistanceMeters = dbHelper.getAccumulatedDistanceMeters(sessionId)
        persistState()

        createHighPriorityNotificationChannel()
        val notification = buildOngoingNotification("GPS Initializing...")

        try {
            // Android 10+ (API 29+) Strict Foreground Service Location Type Enforcement
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // e.g. ForegroundServiceStartNotAllowedException or missing location permission.
            e.printStackTrace()
            stopSelf()
            return START_NOT_STICKY
        }

        acquireWakeLock()

        // Continuous high-resolution GPS tracking (0.0m displacement to preserve satellite lock)
        applyLocationUpdates(baseIntervalMs, 1000L, 0.0f)

        isRunning = true
        current = this
        gpsStatusText = if (googleMapsMode) "GPS Co-Navigating (Battery Saver)" else "GPS Active"
        tickHandler.removeCallbacks(tickRunnable)
        tickHandler.postDelayed(tickRunnable, TICK_INTERVAL_MS)
        updateLiveNotification()
        return START_STICKY
    }

    // -------------------------------------------------------------------------
    // Persisted state (survives process death for START_STICKY restarts)
    // -------------------------------------------------------------------------

    private fun persistState() {
        prefs.edit()
            .putInt("sessionId", sessionId)
            .putString("activityType", activityType)
            .putInt("targetDurationSeconds", targetDurationSeconds)
            .putString("safetyBufferPct", safetyBufferPct.toString())
            .putBoolean("googleMapsMode", googleMapsMode)
            .putLong("baseIntervalMs", baseIntervalMs)
            .putFloat("maxAccuracyM", maxAccuracyMeters)
            .putFloat("minDistanceM", minDistanceMeters)
            .putBoolean("audioAlarms", audioAlarms)
            .putBoolean("hapticAlarms", hapticAlarms)
            .putBoolean("autoPauseMusic", autoPauseMusic)
            .putLong("elapsedBaseMs", elapsedBaseMs)
            .putLong("segmentStartWallMs", segmentStartWallMs)
            .apply()
    }

    private fun restoreState(): Boolean {
        val savedId = prefs.getInt("sessionId", -1)
        if (savedId < 0) return false
        // Only resume if the user has not finished or paused the session in the meantime.
        if (dbHelper.getSessionStatus(savedId) != "active") {
            clearPersistedState()
            return false
        }
        sessionId = savedId
        activityType = prefs.getString("activityType", "run") ?: "run"
        targetDurationSeconds = prefs.getInt("targetDurationSeconds", 0)
        safetyBufferPct = prefs.getString("safetyBufferPct", "8.0")?.toDoubleOrNull() ?: 8.0
        googleMapsMode = prefs.getBoolean("googleMapsMode", false)
        baseIntervalMs = prefs.getLong("baseIntervalMs", 1000L)
        maxAccuracyMeters = prefs.getFloat("maxAccuracyM", DEFAULT_MAX_ACCURACY_M)
        minDistanceMeters = prefs.getFloat("minDistanceM", 0f)
        audioAlarms = prefs.getBoolean("audioAlarms", true)
        hapticAlarms = prefs.getBoolean("hapticAlarms", true)
        autoPauseMusic = prefs.getBoolean("autoPauseMusic", true)
        elapsedBaseMs = prefs.getLong("elapsedBaseMs", 0L)
        segmentStartWallMs = prefs.getLong("segmentStartWallMs", System.currentTimeMillis())
        return true
    }

    private fun clearPersistedState() {
        prefs.edit().clear().apply()
    }

    // -------------------------------------------------------------------------
    // WakeLock Lifecycle Management
    // -------------------------------------------------------------------------

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TurnBack::GpsWakeLock").apply {
                setReferenceCounted(false)
            }
        }
        wakeLock?.let {
            if (!it.isHeld) {
                it.acquire(10 * 60 * 60 * 1000L) // 10 hour max safety cutoff
            }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }

    // -------------------------------------------------------------------------
    // GPS Polling & FusedLocationProviderClient
    // -------------------------------------------------------------------------

    private fun isMotorVehicleProfile(type: String): Boolean {
        val t = type.lowercase(Locale.ROOT)
        return t.contains("vehicle") || t.contains("drive") || t.contains("car") || t.contains("motor")
    }

    private fun applyLocationUpdates(intervalMs: Long, fastestIntervalMs: Long, smallestDisplacement: Float) {
        currentIntervalMs = intervalMs
        currentFastestIntervalMs = fastestIntervalMs
        currentDisplacementMeters = smallestDisplacement

        val isPassive = googleMapsMode && !isWatchdogFallbackActive
        val priority = if (isPassive) Priority.PRIORITY_PASSIVE else Priority.PRIORITY_HIGH_ACCURACY

        if (fusedLocationClient != null) {
            try {
                locationCallback?.let { fusedLocationClient?.removeLocationUpdates(it) }

                val locationRequest = LocationRequest.Builder(priority, intervalMs)
                    .setMinUpdateIntervalMillis(fastestIntervalMs)
                    .setMinUpdateDistanceMeters(smallestDisplacement)
                    .build()

                locationCallback = object : LocationCallback() {
                    override fun onLocationResult(result: LocationResult) {
                        for (loc in result.locations) {
                            processLocationUpdate(loc)
                        }
                    }
                }
                fusedLocationClient?.requestLocationUpdates(locationRequest, locationCallback!!, mainLooper)
                return
            } catch (e: SecurityException) {
                gpsStatusText = "Error: Location Permission Denied"
                updateLiveNotification()
                stopSelf()
                return
            } catch (e: Exception) {
                // Fall back to LocationManager on failure or missing Play Services
            }
        }

        // LocationManager fallback
        try {
            val provider = if (isPassive) LocationManager.PASSIVE_PROVIDER else LocationManager.GPS_PROVIDER
            locationManager.removeUpdates(this)
            locationManager.requestLocationUpdates(
                provider,
                intervalMs,
                smallestDisplacement,
                this,
                mainLooper
            )
        } catch (e: SecurityException) {
            gpsStatusText = "Error: Location Permission Denied"
            updateLiveNotification()
            stopSelf()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onLocationChanged(location: Location) {
        processLocationUpdate(location)
    }

    /**
     * Primary location ingest: filters, accumulates distance, persists and dispatches the fix.
     */
    private fun processLocationUpdate(location: Location) {
        lastLocationFixTimestampMs = System.currentTimeMillis()

        // 0. Reject low-quality fixes (cold start, network provider) that would create distance spikes.
        if (location.hasAccuracy() && location.accuracy > maxAccuracyMeters) return

        val prev = lastLocation

        // 1. Speed: prefer the receiver's Doppler speed, fall back to displacement / time.
        val speedMps = when {
            location.hasSpeed() -> location.speed.toDouble()
            prev != null && location.time > prev.time ->
                location.distanceTo(prev) / ((location.time - prev.time) / 1000.0)
            else -> 0.0
        }

        // 2. Stop detection: throttle GPS polling while resting, restore instantly on movement.
        val isResting = speedMps < RESTING_SPEED_MPS
        consecutiveStationaryTicks = if (isResting) consecutiveStationaryTicks + 1 else 0
        if (!googleMapsMode) {
            if (!isStationaryMode && consecutiveStationaryTicks >= STATIONARY_TICKS_THRESHOLD) {
                isStationaryMode = true
                applyLocationUpdates(STATIONARY_INTERVAL_MS, STATIONARY_INTERVAL_MS, 0.0f)
                gpsStatusText = "GPS Power Save (Stopped)"
            } else if (isStationaryMode && !isResting) {
                isStationaryMode = false
                applyLocationUpdates(baseIntervalMs, 1000L, 0.0f)
                gpsStatusText = "GPS Active"
            }
        }

        lastLocation = location

        // 3. Kalman coordinate smoothing with metric dynamics (fed every accepted fix)
        val (filteredLat, filteredLng) = kalmanFilter.filter(
            location.latitude,
            location.longitude,
            location.accuracy.toDouble(),
            location.time,
            speedMps
        )

        // 4. Minimum distance between stored points (filters stationary jitter, saves storage).
        val lastStored = lastStoredLocation
        if (lastStored != null) {
            val stepDistMeters = location.distanceTo(lastStored).toDouble()
            if (minDistanceMeters > 0f && stepDistMeters < minDistanceMeters) {
                checkTurnBackThreshold()
                return
            }
            // Distance accumulation (filter stationary drift: 0.2 m/s = 0.72 km/h)
            if (speedMps > 0.2 && stepDistMeters > 0.5) {
                totalDistanceMeters += stepDistMeters
            }
        }
        lastStoredLocation = location

        // 5. True MSL Altitude calculation (corrects WGS 84 ellipsoidal height)
        val mslAltitude = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && location.hasMslAltitude()) {
            location.mslAltitudeMeters
        } else if (location.hasAltitude()) {
            GeoidHelper.ellipsoidalToMsl(location.altitude, location.latitude, location.longitude)
        } else {
            // No altitude in this fix: carry the previous value instead of dropping to sea level.
            lastMslAltitude
        }
        lastMslAltitude = mslAltitude

        // 6. Persistence to SQLite
        dbHelper.insertPoint(
            sessionId,
            location.time,
            filteredLat,
            filteredLng,
            mslAltitude,
            location.accuracy,
            speedMps.toFloat()
        )

        // 7. In-process direct telemetry dispatch to UI
        telemetryListener?.invoke(
            filteredLat,
            filteredLng,
            mslAltitude,
            location.accuracy,
            speedMps.toFloat(),
            location.time
        )

        // 8. Asymmetric Fatigue Turn-Back Logic
        checkTurnBackThreshold()
    }

    private var lastMslAltitude: Double = 0.0

    /**
     * Asymmetric Fatigue Turn-Back Engine (mirrors AdaptivePacingService on the Flutter side):
     * T_outbound = T_target / (1 + S * gamma)
     * where S = 1.0 + (bufferPct / 100.0) [default S = 1.08]
     * and gamma = 1.15 (15% fatigue decay) for human sports, or gamma = 1.0 for motor vehicle.
     * With the defaults the alarm fires at ~44.6% of the target duration.
     */
    private fun checkTurnBackThreshold() {
        if (turnBackAlerted || targetDurationSeconds <= 0) return

        val gamma = if (isMotorVehicleProfile(activityType)) 1.0 else 1.15
        val sBuffer = 1.0 + (safetyBufferPct / 100.0)
        val outboundLimitSeconds = Math.round(targetDurationSeconds / (1.0 + sBuffer * gamma))
        if (activeElapsedMs() / 1000 < outboundLimitSeconds) return

        turnBackAlerted = true
        // The Flutter HUD may have fired already (it writes the same flag) - never double-alarm.
        if (dbHelper.isTurnBackTriggered(sessionId)) return
        dbHelper.markTurnBackTriggered(sessionId, System.currentTimeMillis())
        TurnBackAlert.fire(this, activityType, audioAlarms, hapticAlarms, autoPauseMusic)
        updateLiveNotification()
    }

    private fun createHighPriorityNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "TurnBack Endurance Tracker",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Live tracking telemetry and turn-back safety alerts"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun formatElapsed(elapsedSec: Long): String {
        val h = elapsedSec / 3600
        val m = (elapsedSec % 3600) / 60
        val s = elapsedSec % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        else String.format(Locale.US, "%02d:%02d", m, s)
    }

    private fun buildOngoingNotification(statusText: String): Notification {
        val distStr = String.format(Locale.US, "%.2f km", totalDistanceMeters / 1000.0)
        val durationStr = formatElapsed(activeElapsedMs() / 1000)

        val title = if (turnBackAlerted) "TURN BACK • $distStr • $durationStr" else "TurnBack: $distStr • $durationStr"
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun updateLiveNotification() {
        val status = if (turnBackAlerted) "RETURN LEG • $gpsStatusText" else gpsStatusText
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildOngoingNotification(status))
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {
        gpsStatusText = "Warning: GPS Disabled"
        updateLiveNotification()
    }

    override fun onDestroy() {
        super.onDestroy()
        tickHandler.removeCallbacks(tickRunnable)
        if (isRunning && sessionId >= 0) {
            try {
                dbHelper.saveActiveElapsed(sessionId, activeElapsedMs())
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        locationCallback?.let { fusedLocationClient?.removeLocationUpdates(it) }
        locationManager.removeUpdates(this)
        releaseWakeLock()
        // Explicit stop (finish/pause): do not resurrect this session on a sticky restart.
        clearPersistedState()
        isRunning = false
        if (current === this) current = null
        // telemetryListener belongs to MainActivity's EventChannel; leave it so a restarted
        // service keeps streaming to the open HUD.
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
