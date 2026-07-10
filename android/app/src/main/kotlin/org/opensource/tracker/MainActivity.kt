package org.opensource.tracker

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CONTROL_CHANNEL = "org.opensource.tracker/control"
    private val TELEMETRY_CHANNEL = "org.opensource.tracker/telemetry"

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel: Start and Stop Tracking Control
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTracking" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: -1
                    val activityType = call.argument<String>("activityType") ?: "run"
                    val targetDurationSeconds = call.argument<Int>("targetDurationSeconds") ?: 0
                    val safetyBufferPct = call.argument<Double>("safetyBufferPct") ?: 8.0
                    val gpsIntervalMs = call.argument<Int>("gpsIntervalMs") ?: 5000

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
                                "altitude" to alt,
                                "accuracy" to acc.toDouble(),
                                "speed" to speed.toDouble(),
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
