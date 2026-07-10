package org.opensource.tracker.db

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class DatabaseHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        const val DATABASE_NAME = "turnback.db"
        const val DATABASE_VERSION = 1
    }

    override fun onCreate(db: SQLiteDatabase) {
        // Enforce same schema as Flutter to ensure interoperability
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                activity_type TEXT NOT NULL DEFAULT 'run',
                target_duration INTEGER NOT NULL,
                safety_buffer REAL NOT NULL,
                start_time INTEGER NOT NULL,
                end_time INTEGER,
                turn_back_triggered_at INTEGER,
                status TEXT NOT NULL
            )
        """)

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL,
                timestamp INTEGER NOT NULL,
                lat REAL NOT NULL,
                lng REAL NOT NULL,
                altitude REAL NOT NULL,
                accuracy REAL NOT NULL,
                speed REAL NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
            )
        """)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Migration logic for future updates
    }

    fun markTurnBackTriggered(sessionId: Int, timestamp: Long) {
        val db = this.writableDatabase
        db.enableWriteAheadLogging()
        val values = ContentValues().apply {
            put("turn_back_triggered_at", timestamp)
        }
        db.update("sessions", values, "id = ?", arrayOf(sessionId.toString()))
    }

    fun insertPoint(
        sessionId: Int,
        timestamp: Long,
        lat: Double,
        lng: Double,
        altitude: Double,
        accuracy: Float,
        speed: Float
    ): Long {
        val db = this.writableDatabase
        db.enableWriteAheadLogging() // Ensures concurrent read/write locks are handled safely
        
        val values = ContentValues().apply {
            put("session_id", sessionId)
            put("timestamp", timestamp)
            put("lat", lat)
            put("lng", lng)
            put("altitude", altitude)
            put("accuracy", accuracy.toDouble())
            put("speed", speed.toDouble())
        }
        return db.insert("points", null, values)
    }

    fun getAccumulatedActiveTime(sessionId: Int): Long {
        val db = this.readableDatabase
        val cursor = db.query(
            "points",
            arrayOf("timestamp", "speed"),
            "session_id = ?",
            arrayOf(sessionId.toString()),
            null, null,
            "timestamp ASC"
        )
        
        var totalActiveMs = 0L
        if (cursor.moveToFirst()) {
            var prevTime = cursor.getLong(cursor.getColumnIndexOrThrow("timestamp"))
            while (cursor.moveToNext()) {
                val currTime = cursor.getLong(cursor.getColumnIndexOrThrow("timestamp"))
                val speed = cursor.getDouble(cursor.getColumnIndexOrThrow("speed"))
                val diff = currTime - prevTime
                if (diff in 1..15000 && speed > 0.2) {
                    totalActiveMs += diff
                }
                prevTime = currTime
            }
        }
        cursor.close()
        return totalActiveMs
    }
}
