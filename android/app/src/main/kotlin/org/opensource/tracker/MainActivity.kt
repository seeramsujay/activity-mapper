package org.opensource.tracker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.KeyEvent
import android.view.WindowManager

class MainActivity : FlutterActivity() {

    private val CONTROL_CHANNEL = "org.opensource.tracker/control"
    private val TELEMETRY_CHANNEL = "org.opensource.tracker/telemetry"
    private val PERMISSION_REQUEST_CODE = 1001

    private var eventSink: EventChannel.EventSink? = null
    private var pendingStartTrackingCall: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null

    private fun hasLocationPermissions(): Boolean {
        val fineLocation = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarseLocation = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        return (fineLocation || coarseLocation) && notification
    }

    private fun requestRequiredPermissions() {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                pendingStartTrackingCall?.invoke()
            } else {
                pendingResult?.error("PERMISSION_DENIED", "Location permissions are required for GPS tracking", null)
            }
            pendingStartTrackingCall = null
            pendingResult = null
        }
    }

    private fun dispatchMediaKey(keyCode: Int): Boolean {
        val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return false
        val downEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
        val upEvent = KeyEvent(KeyEvent.ACTION_UP, keyCode)
        audioManager.dispatchMediaKeyEvent(downEvent)
        audioManager.dispatchMediaKeyEvent(upEvent)
        return true
    }

    private fun setAdaptiveRefreshRate(targetFps: Float) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.attributes.preferredRefreshRate = targetFps
            window.attributes = window.attributes
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            val modes = display?.supportedModes
            if (modes != null) {
                val matchedMode = modes.minByOrNull { kotlin.math.abs(it.refreshRate - targetFps) }
                if (matchedMode != null) {
                    val params = window.attributes
                    params.preferredDisplayModeId = matchedMode.modeId
                    window.attributes = params
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel: Start/Stop Tracking, Media Control, and Hardware Power Management
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermissions" -> {
                    result.success(hasLocationPermissions())
                }
                "requestPermissions" -> {
                    if (hasLocationPermissions()) {
                        result.success(true)
                    } else {
                        pendingResult = result
                        requestRequiredPermissions()
                    }
                }
                "startTracking" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: -1
                    val activityType = call.argument<String>("activityType") ?: "run"
                    val targetDurationSeconds = call.argument<Int>("targetDurationSeconds") ?: 0
                    val safetyBufferPct = call.argument<Double>("safetyBufferPct") ?: 8.0
                    val gpsIntervalMs = call.argument<Int>("gpsIntervalMs") ?: 5000

                    val startAction = {
                        val serviceIntent = Intent(this, GpsLoggingService::class.java).apply {
                            putExtra("sessionId", sessionId)
                            putExtra("activityType", activityType)
                            putExtra("targetDurationSeconds", targetDurationSeconds)
                            putExtra("safetyBufferPct", safetyBufferPct)
                            putExtra("gpsIntervalMs", gpsIntervalMs)
                        }

                        try {
                            ContextCompat.startForegroundService(this, serviceIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE_START_FAILED", e.message, null)
                        }
                    }

                    if (hasLocationPermissions()) {
                        startAction()
                    } else {
                        pendingStartTrackingCall = startAction
                        pendingResult = result
                        requestRequiredPermissions()
                    }
                }
                "stopTracking" -> {
                    val serviceIntent = Intent(this, GpsLoggingService::class.java)
                    val stopped = stopService(serviceIntent)
                    result.success(stopped)
                }
                "sendMediaAction" -> {
                    val action = call.argument<String>("action") ?: ""
                    val success = when (action) {
                        "play_pause", "toggle" -> dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
                        "play" -> dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY)
                        "pause" -> dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PAUSE)
                        "next" -> dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
                        "previous" -> dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
                        "volume_up" -> {
                            val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager
                            audioManager?.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
                            true
                        }
                        "volume_down" -> {
                            val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager
                            audioManager?.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
                            true
                        }
                        else -> false
                    }
                    result.success(success)
                }
                "triggerTurnBackAlert" -> {
                    val activityType = (call.argument<String>("activityType") ?: "run").lowercase()
                    val isWalking = activityType.contains("walk") || activityType.contains("hike")
                    val isCycling = activityType.contains("ride") || activityType.contains("cycle") || activityType.contains("bike")

                    // 1. Cycling: Auto-pause media playback
                    if (isCycling) {
                        try {
                            dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PAUSE)
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }

                    // 2. Audio Tone: small alarm for cycling/running, none for walking
                    if (!isWalking) {
                        try {
                            val toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, if (isCycling) 85 else 100)
                            toneGenerator.startTone(
                                if (isCycling) ToneGenerator.TONE_PROP_BEEP2 else ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD,
                                3500
                            )
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }

                    // 3. Vibration pattern for all activities
                    try {
                        val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
                        val pattern = if (isWalking) {
                            longArrayOf(0, 600, 300, 600)
                        } else {
                            longArrayOf(0, 800, 200, 800, 200, 800)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
                        } else {
                            @Suppress("DEPRECATION")
                            vibrator?.vibrate(pattern, -1)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }

                    result.success(true)
                }
                "launchMusicApp" -> {
                    val requestedPkg = call.argument<String>("packageName") ?: "in.krosbits.musicolet"
                    var launchIntent = packageManager.getLaunchIntentForPackage(requestedPkg)
                    
                    if (launchIntent == null) {
                        // Fallback 1: Intent for Music category app
                        launchIntent = Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_APP_MUSIC)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                    }

                    if (launchIntent.resolveActivity(packageManager) != null) {
                        startActivity(launchIntent)
                        result.success(true)
                    } else {
                        // Fallback 2: MediaStore music player action
                        try {
                            val mediaIntent = Intent(android.provider.MediaStore.INTENT_ACTION_MUSIC_PLAYER).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            if (mediaIntent.resolveActivity(packageManager) != null) {
                                startActivity(mediaIntent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "setPowerSaveDisplay" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    // Clamps to 30Hz or lowest supported mode when power saver is active, 0f restores default
                    val targetFps = if (enable) 30f else 0f
                    try {
                        setAdaptiveRefreshRate(targetFps)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // EventChannel: Real-time location stream back to Flutter HUD
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TELEMETRY_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    
                    // Bind native telemetry listener
                    GpsLoggingService.telemetryListener = { lat, lng, alt, acc, speed, time ->
                        // Ensure we post updates back to the UI thread main looper
                        runOnUiThread {
                            eventSink?.success(mapOf(
                                "lat" to lat,
                                "lng" to lng,
                                "alt" to alt,
                                "altitude" to alt,
                                "acc" to acc.toDouble(),
                                "accuracy" to acc.toDouble(),
                                "speed" to speed.toDouble(),
                                "time" to time,
                                "timestamp" to time
                            ))
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    GpsLoggingService.telemetryListener = null
                }
            }
        )
    }
}

