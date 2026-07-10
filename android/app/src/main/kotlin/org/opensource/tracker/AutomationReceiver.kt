package org.opensource.tracker

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import org.opensource.tracker.db.DatabaseHelper

class AutomationReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return

        val dbHelper = DatabaseHelper(context)

        when (intent.action) {
            "org.opensource.tracker.START_ACTIVITY" -> {
                if (GpsLoggingService.isRunning) {
                    print("AutomationReceiver: Activity already active.")
                    return
                }

                val targetDurationSeconds = intent.getIntExtra("target_duration", 5400) // Default 90m
                val safetyBufferPct = intent.getDoubleExtra("safety_buffer", 8.0)
                val activityType = intent.getStringExtra("activity_type") ?: "run"
                val startTimeMs = System.currentTimeMillis()

                // Create and store session natively (since UI is closed)
                val db = dbHelper.writableDatabase
                val values = ContentValues().apply {
                    put("activity_type", activityType)
                    put("target_duration", targetDurationSeconds)
                    put("safety_buffer", safetyBufferPct)
                    put("start_time", startTimeMs)
                    put("status", "active")
                }
                
                val sessionId = db.insert("sessions", null, values).toInt()

                // Launch background FGS
                val serviceIntent = Intent(context, GpsLoggingService::class.java).apply {
                    putExtra("sessionId", sessionId)
                    putExtra("activityType", activityType)
                    putExtra("targetDurationSeconds", targetDurationSeconds)
                    putExtra("safetyBufferPct", safetyBufferPct)
                    putExtra("startTimeMs", startTimeMs)
                    putExtra("gpsIntervalMs", 5000)
                }

                ContextCompat.startForegroundService(context, serviceIntent)
            }

            "org.opensource.tracker.STOP_ACTIVITY" -> {
                // Terminate service loop
                val serviceIntent = Intent(context, GpsLoggingService::class.java)
                context.stopService(serviceIntent)

                // Update database
                val db = dbHelper.writableDatabase
                val values = ContentValues().apply {
                    put("status", "completed")
                    put("end_time", System.currentTimeMillis())
                }
                db.update("sessions", values, "status = ? OR status = ?", arrayOf("active", "paused"))
            }

            "org.opensource.tracker.GET_CURRENT_STATS" -> {
                // Broadcast active tracking stats back (useful for Tasker display profiles)
                val db = dbHelper.readableDatabase
                val cursor = db.rawQuery(
                    "SELECT id, start_time, target_duration, safety_buffer FROM sessions WHERE status = ? LIMIT 1",
                    arrayOf("active")
                )

                val replyIntent = Intent("org.opensource.tracker.STATS_REPLY").apply {
                    putExtra("is_running", GpsLoggingService.isRunning)
                }

                if (cursor.moveToFirst()) {
                    val sessionId = cursor.getInt(0)
                    val startTime = cursor.getLong(1)
                    val targetDuration = cursor.getInt(2)
                    val safetyBuffer = cursor.getDouble(3)

                    // Get point count as proxy for activity level
                    val pointsCursor = db.rawQuery(
                        "SELECT COUNT(*) FROM points WHERE session_id = ?",
                        arrayOf(sessionId.toString())
                    )
                    var pointsCount = 0
                    if (pointsCursor.moveToFirst()) {
                        pointsCount = pointsCursor.getInt(0)
                    }
                    pointsCursor.close()

                    val elapsedSeconds = dbHelper.getAccumulatedActiveTime(sessionId) / 1000

                    replyIntent.apply {
                        putExtra("session_id", sessionId)
                        putExtra("elapsed_seconds", elapsedSeconds)
                        putExtra("points_logged", pointsCount)
                        putExtra("target_duration", targetDuration)
                        putExtra("safety_buffer", safetyBuffer)
                    }
                }
                cursor.close()
                context.sendBroadcast(replyIntent)
            }
        }
    }
}
