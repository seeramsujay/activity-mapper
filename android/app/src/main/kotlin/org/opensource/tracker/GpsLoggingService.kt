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
import org.opensource.tracker.db.DatabaseHelper
import org.opensource.tracker.filter.KalmanFilter

class GpsLoggingService : Service(), LocationListener {

    companion object {
        const val CHANNEL_ID = "GpsLoggingServiceChannel"
        const val NOTIFICATION_ID = 486
        
        var isRunning = false
            private set

        // Direct callback hook to MainActivity (fast, in-process, no binder serialization)
        var telemetryListener: ((lat: Double, lng: Double, alt: Double, acc: Float, speed: Float, time: Long) -> Unit)? = null
    }

    private lateinit var locationManager: LocationManager
    private lateinit var dbHelper: DatabaseHelper
    private lateinit var kalmanFilter: KalmanFilter
    private var wakeLock: PowerManager.WakeLock? = null
    
    private var sessionId: Int = -1
    private var activityType: String = "run"
    private var targetDurationSeconds: Int = 0
    private var safetyBufferPct: Double = 8.0
    private var startTimeMs: Long = 0
    private var turnBackAlerted = false

    // Battery-saving Stop Detection and Dynamic GPS Frequency variables
    private var originalGpsIntervalMs: Long = 5000
    private var currentGpsIntervalMs: Long = 5000
    private var consecutiveStopsCount = 0
    private var isPowerSaveModeActive = false
    private var lastLocation: Location? = null
    private var totalActiveMovingTimeMs: Long = 0L

    override fun onCreate() {
        super.onCreate();
        dbHelper = DatabaseHelper(this)
        kalmanFilter = KalmanFilter()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        sessionId = intent.getIntExtra("sessionId", -1)
        activityType = intent.getStringExtra("activityType") ?: "run"
        targetDurationSeconds = intent.getIntExtra("targetDurationSeconds", 0)
        safetyBufferPct = intent.getDoubleExtra("safetyBufferPct", 8.0)
        startTimeMs = intent.getLongExtra("startTimeMs", System.currentTimeMillis())
        turnBackAlerted = intent.getBooleanExtra("turnBackAlerted", false)
        
        val gpsIntervalMs = intent.getIntExtra("gpsIntervalMs", 5000).toLong()
        originalGpsIntervalMs = gpsIntervalMs
        currentGpsIntervalMs = gpsIntervalMs

        // Recover pre-existing moving time from DB (supports resuming paused runs & headless crashes)
        totalActiveMovingTimeMs = dbHelper.getAccumulatedActiveTime(sessionId)

        createNotificationChannel()
        val notification = buildNotification("Starting GPS tracking...")

        // Android 14+ FGS Location Type Enforcement
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Acquire CPU WakeLock to prevent sleep mode
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TurnBack::GpsLoggingWakeLock").apply {
            acquire(10 * 60 * 60 * 1000L) // 10 hours max safety limit
        }

        try {
            val minDistanceMeters = intent.getDoubleExtra("minDistanceMeters", 5.0).toFloat()
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    currentGpsIntervalMs,
                    minDistanceMeters,
                    this
                )
            } else if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    currentGpsIntervalMs,
                    minDistanceMeters,
                    this
                )
            }
            isRunning = true
            updateNotification("GPS Signal Active")
        } catch (e: SecurityException) {
            updateNotification("Error: GPS Permission Denied")
            stopSelf()
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return START_STICKY
    }

    private fun adjustGpsSamplingRate(intervalMs: Long) {
        try {
            locationManager.removeUpdates(this)
            val minDistance = if (isPowerSaveModeActive) 15.0f else 5.0f
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    intervalMs,
                    minDistance,
                    this
                )
            } else if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    intervalMs,
                    minDistance,
                    this
                )
            }
            currentGpsIntervalMs = intervalMs
        } catch (e: SecurityException) {
            e.printStackTrace()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onLocationChanged(location: Location) {
        // Battery-Saving Stop Detection: Check speed & distance to last location
        val isStatic = if (lastLocation != null) {
            val dist = location.distanceTo(lastLocation!!)
            location.speed <= 0.2f || dist < 1.5f
        } else {
            location.speed <= 0.2f
        }

        if (isStatic) {
            consecutiveStopsCount++
            if (consecutiveStopsCount >= 3 && !isPowerSaveModeActive) {
                isPowerSaveModeActive = true
                adjustGpsSamplingRate(30000L) // Reduce frequency to 30s updates
                updateNotification("Stationary detected. Power save active (30s sampling).")
            }
        } else {
            consecutiveStopsCount = 0
            if (isPowerSaveModeActive) {
                isPowerSaveModeActive = false
                adjustGpsSamplingRate(originalGpsIntervalMs) // Restore standard frequency
                updateNotification("Motion detected. Standard tracking active.")
            }
        }
        
        // Accumulate active moving duration (disregarding stationary breaks or pause gap delays)
        val last = lastLocation
        if (last != null) {
            val diff = location.time - last.time
            if (diff in 1..15000 && location.speed > 0.2f) {
                totalActiveMovingTimeMs += diff
            }
        }

        lastLocation = location

        // Apply coordinate-wise Kalman filtering
        val (filteredLat, filteredLng) = kalmanFilter.filter(
            location.latitude,
            location.longitude,
            location.accuracy.toDouble(),
            location.time
        )

        // Native SQL persistence (safe recovery checkpoint)
        dbHelper.insertPoint(
            sessionId,
            location.time,
            filteredLat,
            filteredLng,
            location.altitude,
            location.accuracy,
            location.speed
        )

        // Stream coordinate node to active UI if running
        telemetryListener?.invoke(
            filteredLat,
            filteredLng,
            location.altitude,
            location.accuracy,
            location.speed,
            location.time
        )

        // Safety-critical Turn-Back calculation (Active Moving Time vs Outbound Limit)
        val outboundLimitSeconds = (targetDurationSeconds * (100.0 - safetyBufferPct) / 200.0).toLong()
        val elapsedSeconds = totalActiveMovingTimeMs / 1000

        if (elapsedSeconds >= outboundLimitSeconds && !turnBackAlerted) {
            turnBackAlerted = true
            
            // 1. Persist state natively to database
            dbHelper.markTurnBackTriggered(sessionId, System.currentTimeMillis())

            // 2. Play loud alarm beep (system alarm stream, 5-second CDMA alert tone)
            try {
                val toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
                toneGenerator.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 5000)
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // 3. Trigger haptic pattern (Vibrate, pause, repeat)
            try {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 200, 800, 200, 800), -1))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(longArrayOf(0, 800, 200, 800, 200, 800), -1)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // 4. Update ongoing notification to high urgency state
            updateNotification("TURN BACK NOW! Safety window reached.")
        } else {
            // Update ongoing tracking notification description
            if (isPowerSaveModeActive) {
                updateNotification("Power Save Active (Stationary). Limit: ${outboundLimitSeconds / 60}m")
            } else {
                updateNotification("Tracking active. Elapsed: ${elapsedSeconds / 60}m / Limit: ${outboundLimitSeconds / 60}m")
            }
        }
    }

    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {
        updateNotification("Warning: GPS Provider Disabled")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Out-and-Back Telemetry Tracker",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("TurnBack Tracking Running")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    override fun onDestroy() {
        super.onDestroy()
        locationManager.removeUpdates(this)
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        isRunning = false
        telemetryListener = null
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
