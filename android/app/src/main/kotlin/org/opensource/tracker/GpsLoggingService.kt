package org.opensource.tracker

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import org.opensource.tracker.db.DatabaseHelper
import org.opensource.tracker.filter.KalmanFilter
import java.util.Locale
import kotlin.math.*

/**
 * High-performance Android Foreground Service executing continuous background GPS tracking.
 *
 * Implements:
 * - FOREGROUND_SERVICE_TYPE_LOCATION enforcement (API 29+).
 * - CPU Partial WakeLock ('TurnBack::GpsWakeLock') with safe acquiring/releasing lifecycle hooks.
 * - Ongoing high-priority notification with live distance and duration.
 * - Adaptive speed and curvature-driven GPS polling engine (FusedLocationProviderClient with LocationManager fallback).
 * - Asymmetric fatigue turnaround logic: T_outbound = T_target / (1 + S * gamma).
 */
class GpsLoggingService : Service(), LocationListener {

    companion object {
        const val CHANNEL_ID = "GpsLoggingServiceChannel_HighPriority"
        const val NOTIFICATION_ID = 486
        
        var isRunning = false
            private set

        // Direct callback hook to MainActivity (fast, in-process telemetry stream)
        var telemetryListener: ((lat: Double, lng: Double, alt: Double, acc: Float, speed: Float, time: Long) -> Unit)? = null
    }

    private lateinit var locationManager: LocationManager
    private lateinit var dbHelper: DatabaseHelper
    private lateinit var kalmanFilter: KalmanFilter
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var wakeLock: PowerManager.WakeLock? = null
    
    private var sessionId: Int = -1
    private var activityType: String = "run"
    private var targetDurationSeconds: Int = 0
    private var safetyBufferPct: Double = 8.0
    private var startTimeMs: Long = 0
    private var turnBackAlerted = false

    // Telemetry accumulators
    private var totalDistanceMeters: Double = 0.0
    private var totalActiveMovingTimeMs: Long = 0L
    private var lastLocation: Location? = null
    private var previousHeadingRad: Double? = null

    // Adaptive GPS Polling Engine state
    private var currentIntervalMs: Long = 5000L
    private var currentFastestIntervalMs: Long = 2500L
    private var currentDisplacementMeters: Float = 5.0f
    private var consecutiveStationaryTicks: Int = 0
    private var isStationaryPowerSave: Boolean = false

    override fun onCreate() {
        super.onCreate()
        dbHelper = DatabaseHelper(this)
        kalmanFilter = KalmanFilter()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
            fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        } catch (e: Exception) {
            fusedLocationClient = null
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        sessionId = intent.getIntExtra("sessionId", -1)
        activityType = intent.getStringExtra("activityType") ?: "run"
        targetDurationSeconds = intent.getIntExtra("targetDurationSeconds", 0)
        safetyBufferPct = intent.getDoubleExtra("safetyBufferPct", 8.0)
        startTimeMs = intent.getLongExtra("startTimeMs", System.currentTimeMillis())
        turnBackAlerted = intent.getBooleanExtra("turnBackAlerted", false)

        val defaultInterval = intent.getIntExtra("gpsIntervalMs", 5000).toLong()
        currentIntervalMs = defaultInterval

        // Recover pre-existing moving time from DB (resuming paused sessions or post-reboot)
        totalActiveMovingTimeMs = dbHelper.getAccumulatedActiveTime(sessionId)

        createHighPriorityNotificationChannel()
        val notification = buildOngoingNotification("GPS Initializing...")

        // Android 10+ (API 29+) Strict Foreground Service Location Type Enforcement
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Safe CPU Partial WakeLock acquisition
        acquireWakeLock()

        // Start location updates based on activity profile
        val isMotorVehicle = isMotorVehicleProfile(activityType)
        if (isMotorVehicle) {
            // Motor Vehicle Profile: strictly locked to 1000ms / 500ms / 0m
            applyLocationUpdates(1000L, 500L, 0.0f)
        } else {
            applyLocationUpdates(currentIntervalMs, (currentIntervalMs / 2).coerceAtLeast(500L), 5.0f)
        }

        isRunning = true
        updateLiveNotification("GPS Active")
        return START_STICKY
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
    // Adaptive Polling Engine & FusedLocationProviderClient
    // -------------------------------------------------------------------------

    private fun isMotorVehicleProfile(type: String): Boolean {
        val t = type.lowercase(Locale.ROOT)
        return t.contains("vehicle") || t.contains("drive") || t.contains("car") || t.contains("motor")
    }

    private fun applyLocationUpdates(intervalMs: Long, fastestIntervalMs: Long, smallestDisplacement: Float) {
        currentIntervalMs = intervalMs
        currentFastestIntervalMs = fastestIntervalMs
        currentDisplacementMeters = smallestDisplacement

        if (fusedLocationClient != null) {
            try {
                locationCallback?.let { fusedLocationClient?.removeLocationUpdates(it) }

                val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalMs)
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
                updateLiveNotification("Error: Location Permission Denied")
                stopSelf()
                return
            } catch (e: Exception) {
                // Fall back to LocationManager on failure or missing Play Services
            }
        }

        // LocationManager fallback
        try {
            locationManager.removeUpdates(this)
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    intervalMs,
                    smallestDisplacement,
                    this
                )
            } else if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    intervalMs,
                    smallestDisplacement,
                    this
                )
            }
        } catch (e: SecurityException) {
            updateLiveNotification("Error: Location Permission Denied")
            stopSelf()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onLocationChanged(location: Location) {
        processLocationUpdate(location)
    }

    /**
     * Primary location ingest: evaluates speed, stationary rest, curvature, and turnback threshold.
     */
    private fun processLocationUpdate(location: Location) {
        val prev = lastLocation

        // 1. Distance accumulation & active moving duration
        var stepDistMeters = 0.0
        if (prev != null) {
            stepDistMeters = location.distanceTo(prev).toDouble()
            val timeDiff = location.time - prev.time
            // Filter noise spikes and stationary drift (0.2 m/s = 0.72 km/h)
            if (location.speed > 0.2f && stepDistMeters > 0.5) {
                totalDistanceMeters += stepDistMeters
                if (timeDiff in 1..15000) {
                    totalActiveMovingTimeMs += timeDiff
                }
            }
        }

        // 2. Adaptive GPS Polling Engine (Speed & Curvature Driven)
        val isMotorVehicle = isMotorVehicleProfile(activityType)
        if (isMotorVehicle) {
            // Motor Vehicle Profile: strictly lock to 1000ms / 500ms / 0m
            if (currentIntervalMs != 1000L || currentDisplacementMeters != 0.0f) {
                applyLocationUpdates(1000L, 500L, 0.0f)
            }
        } else {
            // Stationary rest check: v <= 0.72 km/h (0.2 m/s) across 3 consecutive ticks
            val isResting = location.speed <= 0.2f || (prev != null && stepDistMeters < 1.0)
            if (isResting) {
                consecutiveStationaryTicks++
                if (consecutiveStationaryTicks >= 3 && !isStationaryPowerSave) {
                    isStationaryPowerSave = true
                    applyLocationUpdates(30000L, 15000L, 10.0f)
                }
            } else {
                consecutiveStationaryTicks = 0
                if (isStationaryPowerSave) {
                    isStationaryPowerSave = false
                    applyLocationUpdates(5000L, 2500L, 5.0f)
                }

                // Curvature calculation: kappa = |delta_theta / delta_s|
                if (prev != null && stepDistMeters >= 1.0) {
                    val kappa = calculateCurvature(prev, location, stepDistMeters)
                    val speedKmh = location.speed * 3.6f

                    // Curved / Sharp Turns (kappa >= 0.05) -> 1000ms, 500ms, 2m
                    if (kappa >= 0.05) {
                        if (currentIntervalMs != 1000L || currentDisplacementMeters != 2.0f) {
                            applyLocationUpdates(1000L, 500L, 2.0f)
                        }
                    }
                    // Straight Fast Cruise (v > 15 km/h, kappa < 0.05) -> 10000ms, 15m
                    else if (speedKmh > 15.0f && kappa < 0.05) {
                        if (currentIntervalMs != 10000L || currentDisplacementMeters != 15.0f) {
                            applyLocationUpdates(10000L, 5000L, 15.0f)
                        }
                    }
                    // Standard cruising
                    else {
                        if (currentIntervalMs != 5000L && currentIntervalMs != 1000L) {
                            applyLocationUpdates(5000L, 2500L, 5.0f)
                        }
                    }
                }
            }
        }

        lastLocation = location

        // 3. Kalman filtering
        val (filteredLat, filteredLng) = kalmanFilter.filter(
            location.latitude,
            location.longitude,
            location.accuracy.toDouble(),
            location.time
        )

        // 4. Persistence to SQLite
        dbHelper.insertPoint(
            sessionId,
            location.time,
            filteredLat,
            filteredLng,
            location.altitude,
            location.accuracy,
            location.speed
        )

        // 5. In-process direct telemetry dispatch to UI
        telemetryListener?.invoke(
            filteredLat,
            filteredLng,
            location.altitude,
            location.accuracy,
            location.speed,
            location.time
        )

        // 6. Asymmetric Fatigue Turn-Back Logic
        checkTurnBackThreshold(isMotorVehicle)
    }

    /**
     * Curvature calculation: kappa = |delta_theta / delta_s| (rad / m).
     */
    private fun calculateCurvature(prevLoc: Location, currLoc: Location, deltaS: Double): Double {
        val lat1 = Math.toRadians(prevLoc.latitude)
        val lon1 = Math.toRadians(prevLoc.longitude)
        val lat2 = Math.toRadians(currLoc.latitude)
        val lon2 = Math.toRadians(currLoc.longitude)
        val dLon = lon2 - lon1

        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        val currentHeadingRad = atan2(y, x)

        val prevH = previousHeadingRad
        previousHeadingRad = currentHeadingRad
        if (prevH == null) return 0.0

        var deltaTheta = abs(atan2(sin(currentHeadingRad - prevH), cos(currentHeadingRad - prevH)))
        return deltaTheta / deltaS
    }

    /**
     * Asymmetric Fatigue Turn-Back Engine:
     * T_outbound = T_target / (1 + S * gamma)
     * where S = 1.0 + (bufferPct / 100.0) [default S = 1.08]
     * and gamma = 1.15 (15% fatigue decay) for human sports, or gamma = 1.0 for motor vehicle.
     * T_outbound is approximately 44.6% of elapsed time.
     */
    private fun checkTurnBackThreshold(isMotorVehicle: Boolean) {
        val elapsedSec = totalActiveMovingTimeMs / 1000

        if (targetDurationSeconds > 0) {
            val gamma = if (isMotorVehicle) 1.0 else 1.15
            val sBuffer = 1.0 + (safetyBufferPct / 100.0)
            val outboundLimitSeconds = (targetDurationSeconds / (1.0 + sBuffer * gamma)).toLong()

            if (elapsedSec >= outboundLimitSeconds && !turnBackAlerted) {
                turnBackAlerted = true
                dbHelper.markTurnBackTriggered(sessionId, System.currentTimeMillis())

                val type = activityType.lowercase(Locale.ROOT)
                val isWalking = type.contains("walk") || type.contains("hike")
                val isCycling = type.contains("ride") || type.contains("cycle") || type.contains("bike")

                // Auto-pause cycling media
                if (isCycling) {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        val downEvent = android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PAUSE)
                        val upEvent = android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_MEDIA_PAUSE)
                        audioManager?.dispatchMediaKeyEvent(downEvent)
                        audioManager?.dispatchMediaKeyEvent(upEvent)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }

                // Native Audio Tone: TONE_CDMA_ALERT_CALL_GUARD
                if (!isWalking) {
                    try {
                        val toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 95)
                        toneGenerator.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 3500)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }

                // Native Double-Pulse Haptic Pattern: [0, 350, 150, 350]
                try {
                    val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    val doublePulse = longArrayOf(0, 350, 150, 350)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator?.vibrate(VibrationEffect.createWaveform(doublePulse, -1))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator?.vibrate(doublePulse, -1)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }

                updateLiveNotification("TURN BACK NOW! Turnaround reached (~44.6% window)")
            } else {
                val distKm = totalDistanceMeters / 1000.0
                val remainingOutbound = (outboundLimitSeconds - elapsedSec).coerceAtLeast(0)
                val status = if (turnBackAlerted) "Returning" else "Outbound (${remainingOutbound / 60}m left)"
                updateLiveNotification(status)
            }
        } else {
            // Free Run Mode
            val predReturnMin = (elapsedSec * (1.0 + (safetyBufferPct / 100.0)) / 60.0).toInt()
            updateLiveNotification("Free Run: Est. Return +${predReturnMin}m")
        }
    }

    // -------------------------------------------------------------------------
    // High-Priority System Status Bar Notification
    // -------------------------------------------------------------------------

    private fun createHighPriorityNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "TurnBack Active Tracking",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Live high-frequency GPS tracking and turnaround telemetry updates"
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun buildOngoingNotification(statusText: String): Notification {
        val distKm = totalDistanceMeters / 1000.0
        val elapsedSec = totalActiveMovingTimeMs / 1000
        val distStr = String.format(Locale.US, "%.2f km", distKm)
        val durationStr = String.format(Locale.US, "%02d:%02d", elapsedSec / 60, elapsedSec % 60)

        val title = "TurnBack: $distStr • $durationStr"
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

    private fun updateLiveNotification(statusText: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildOngoingNotification(statusText))
    }

    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {
        updateLiveNotification("Warning: GPS Disabled")
    }

    override fun onDestroy() {
        super.onDestroy()
        locationCallback?.let { fusedLocationClient?.removeLocationUpdates(it) }
        locationManager.removeUpdates(this)
        releaseWakeLock()
        isRunning = false
        telemetryListener = null
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
