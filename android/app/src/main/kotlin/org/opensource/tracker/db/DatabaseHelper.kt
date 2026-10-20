package org.opensource.tracker.db

import android.content.ContentValues
import android.content.Context
import android.location.Location
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class DatabaseHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        const val DATABASE_NAME = "turnback.db"
        // Must stay in sync with the Flutter side (DbService) - SQLiteOpenHelper refuses to downgrade.
        const val DATABASE_VERSION = 1
    }

    init {
        // Enable WAL once, before the connection is opened, instead of on every write.
        setWriteAheadLoggingEnabled(true)
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        // Required for ON DELETE CASCADE on points.session_id to actually fire.
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        // Idempotent; also created by the Flutter side. Keeps per-session point queries O(log n).
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_points_session_time ON points(session_id, timestamp)")
        ensureColumn(db, "sessions", "active_elapsed_ms", "INTEGER")
    }

    /** Adds a nullable column to older databases; mirrors DbService._ensureColumn on the Flutter side. */
    private fun ensureColumn(db: SQLiteDatabase, table: String, column: String, type: String) {
        db.rawQuery("PRAGMA table_info($table)", null).use { c ->
            val nameIdx = c.getColumnIndexOrThrow("name")
            while (c.moveToNext()) {
                if (c.getString(nameIdx) == column) return
            }
        }
        try {
            db.execSQL("ALTER TABLE $table ADD COLUMN $column $type")
        } catch (e: android.database.sqlite.SQLiteException) {
            // The Flutter side may have added it concurrently.
            if (e.message?.contains("duplicate column") != true) throw e
        }
    }

    /** Persists the active workout time so it survives the service being stopped or killed. */
    fun saveActiveElapsed(sessionId: Int, elapsedMs: Long) {
        val values = ContentValues().apply { put("active_elapsed_ms", elapsedMs) }
        writableDatabase.update("sessions", values, "id = ?", arrayOf(sessionId.toString()))
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
                status TEXT NOT NULL,
                active_elapsed_ms INTEGER
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

    /** True if either the Flutter HUD or this service already fired the turn-back alarm. */
    fun isTurnBackTriggered(sessionId: Int): Boolean {
        readableDatabase.rawQuery(
            "SELECT turn_back_triggered_at FROM sessions WHERE id = ?",
            arrayOf(sessionId.toString())
        ).use { c ->
            return c.moveToFirst() && !c.isNull(0)
        }
    }

    /** Returns the session status ("active", "paused", "completed") or null if it no longer exists. */
    fun getSessionStatus(sessionId: Int): String? {
        readableDatabase.rawQuery(
            "SELECT status FROM sessions WHERE id = ?",
            arrayOf(sessionId.toString())
        ).use { c ->
            return if (c.moveToFirst()) c.getString(0) else null
        }
    }

    /** Sums the stored track length so a restarted service resumes its distance counter. */
    fun getAccumulatedDistanceMeters(sessionId: Int): Double {
        val result = FloatArray(1)
        var total = 0.0
        readableDatabase.rawQuery(
            "SELECT lat, lng FROM points WHERE session_id = ? ORDER BY timestamp ASC",
            arrayOf(sessionId.toString())
        ).use { c ->
            var prevLat = Double.NaN
            var prevLng = Double.NaN
            while (c.moveToNext()) {
                val lat = c.getDouble(0)
                val lng = c.getDouble(1)
                if (!prevLat.isNaN()) {
                    Location.distanceBetween(prevLat, prevLng, lat, lng, result)
                    total += result[0]
                }
                prevLat = lat
                prevLng = lng
            }
        }
        return total
    }
}
