package org.opensource.tracker

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import org.opensource.tracker.db.DatabaseHelper

/**
 * Headless automation API (Tasker, MacroDroid, adb):
 *
 * - START_ACTIVITY extras: `duration_mins` (int) or `target_duration` (int seconds), `safety_buffer`
 *   (double percent, default 8.0), `activity_type` (string, default "run").
 * - STOP_ACTIVITY: stops tracking and marks the session completed.
 * - GET_CURRENT_STATS: replies with an `org.opensource.tracker.STATS_REPLY` broadcast carrying
 *   is_running, session_id, elapsed_seconds, distance_km, points_logged, target_duration, safety_buffer.
 */
class AutomationReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AutomationReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return

        val dbHelper = DatabaseHelper(context)

        when (intent.action) {
            "org.opensource.tracker.START_ACTIVITY" -> {
                if (GpsLoggingService.isRunning || hasOpenSession(dbHelper)) {
                    Log.i(TAG, "Activity already active or paused; ignoring START_ACTIVITY.")
                    return
                }

                val targetDurationSeconds = when {
                    intent.hasExtra("duration_mins") -> intent.getIntExtra("duration_mins", 90) * 60
                    else -> intent.getIntExtra("target_duration", 5400) // Default 90m
                }
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
                if (sessionId < 0) return

                val serviceIntent = Intent(context, GpsLoggingService::class.java).apply {
                    putExtra("sessionId", sessionId)
                    putExtra("activityType", activityType)
                    putExtra("targetDurationSeconds", targetDurationSeconds)
                    putExtra("safetyBufferPct", safetyBufferPct)
                    putExtra("gpsIntervalMs", 1000)
                }

                try {
                    ContextCompat.startForegroundService(context, serviceIntent)
                } catch (e: Exception) {
                    // Android 12+ blocks background FGS starts unless the app is exempt from battery
                    // optimisation. Remove the orphan session instead of leaving a ghost "active" row.
                    Log.e(TAG, "Could not start tracking service from background", e)
                    db.delete("sessions", "id = ?", arrayOf(sessionId.toString()))
                }
            }

            "org.opensource.tracker.STOP_ACTIVITY" -> {
                // Update database first so a sticky restart can't resurrect the session.
                val db = dbHelper.writableDatabase
                val values = ContentValues().apply {
                    put("status", "completed")
                    put("end_time", System.currentTimeMillis())
                }
                db.update("sessions", values, "status = ? OR status = ?", arrayOf("active", "paused"))

                context.stopService(Intent(context, GpsLoggingService::class.java))
            }

            "org.opensource.tracker.GET_CURRENT_STATS" -> {
                // Broadcast active tracking stats back (useful for Tasker display profiles)
                val db = dbHelper.readableDatabase
                val replyIntent = Intent("org.opensource.tracker.STATS_REPLY").apply {
                    putExtra("is_running", GpsLoggingService.isRunning)
                }

                db.rawQuery(
                    "SELECT id, start_time, target_duration, safety_buffer FROM sessions WHERE status = ? LIMIT 1",
                    arrayOf("active")
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        val sessionId = cursor.getInt(0)
                        val startTime = cursor.getLong(1)
                        val targetDuration = cursor.getInt(2)
                        val safetyBuffer = cursor.getDouble(3)

                        val pointsCount = db.rawQuery(
                            "SELECT COUNT(*) FROM points WHERE session_id = ?",
                            arrayOf(sessionId.toString())
                        ).use { if (it.moveToFirst()) it.getInt(0) else 0 }

                        val service = GpsLoggingService.current
                        val elapsedSeconds = if (service != null && service.sessionId == sessionId) {
                            service.activeElapsedMs() / 1000
                        } else {
                            (System.currentTimeMillis() - startTime) / 1000
                        }

                        replyIntent.apply {
                            putExtra("session_id", sessionId)
                            putExtra("elapsed_seconds", elapsedSeconds)
                            putExtra("distance_km", dbHelper.getAccumulatedDistanceMeters(sessionId) / 1000.0)
                            putExtra("points_logged", pointsCount)
                            putExtra("target_duration", targetDuration)
                            putExtra("safety_buffer", safetyBuffer)
                        }
                    }
                }
                context.sendBroadcast(replyIntent)
            }
        }
    }

    private fun hasOpenSession(dbHelper: DatabaseHelper): Boolean {
        dbHelper.readableDatabase.rawQuery(
            "SELECT 1 FROM sessions WHERE status = ? OR status = ? LIMIT 1",
            arrayOf("active", "paused")
        ).use { return it.moveToFirst() }
    }
}
