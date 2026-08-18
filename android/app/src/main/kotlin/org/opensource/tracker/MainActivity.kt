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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel: Start and Stop Tracking Control
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

