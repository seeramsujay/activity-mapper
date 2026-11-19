package org.opensource.tracker.data.settings

import android.content.Context
import android.content.SharedPreferences

enum class AppThemeMode { LIGHT, DARK, SYSTEM }

enum class CoordFormat { DECIMAL, DMS }

enum class ChartXAxis { DISTANCE, DURATION }

enum class RecordProfile(
    val displayName: String,
    val intervalMs: Long,
    val minDistanceMeters: Float,
    val maxAccuracyMeters: Float,
) {
    GENERAL("General", 1000L, 10.0f, 50.0f),
    RUNNING("Running / Fitness", 1000L, 5.0f, 30.0f),
    CYCLING("Cycling / Fast", 1000L, 15.0f, 50.0f),
    HIKING("Hiking / Trek", 5000L, 20.0f, 75.0f),
    BATTERY_SAVE("Ultra Battery Save", 15000L, 30.0f, 100.0f),
}

class AppSettings private constructor(
    context: Context,
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("turnback_app_settings", Context.MODE_PRIVATE)

    var themeMode: AppThemeMode
        get() =
            try {
                AppThemeMode.valueOf(prefs.getString(KEY_THEME_MODE, AppThemeMode.DARK.name) ?: AppThemeMode.DARK.name)
            } catch (_: Exception) {
                AppThemeMode.DARK
            }
        set(v) = prefs.edit().putString(KEY_THEME_MODE, v.name).apply()

    var isOled: Boolean
        get() = prefs.getBoolean(KEY_IS_OLED, false)
        set(v) = prefs.edit().putBoolean(KEY_IS_OLED, v).apply()

    var useImperialUnits: Boolean
        get() = prefs.getBoolean(KEY_USE_IMPERIAL, false)
        set(v) = prefs.edit().putBoolean(KEY_USE_IMPERIAL, v).apply()

    var coordFormat: CoordFormat
        get() =
            try {
                CoordFormat.valueOf(prefs.getString(KEY_COORD_FORMAT, CoordFormat.DECIMAL.name) ?: CoordFormat.DECIMAL.name)
            } catch (_: Exception) {
                CoordFormat.DECIMAL
            }
        set(v) = prefs.edit().putString(KEY_COORD_FORMAT, v.name).apply()

    var chartXAxis: ChartXAxis
        get() =
            try {
                ChartXAxis.valueOf(prefs.getString(KEY_CHART_X_AXIS, ChartXAxis.DISTANCE.name) ?: ChartXAxis.DISTANCE.name)
            } catch (_: Exception) {
                ChartXAxis.DISTANCE
            }
        set(v) = prefs.edit().putString(KEY_CHART_X_AXIS, v.name).apply()

    var beta: Float
        get() = prefs.getFloat(KEY_BETA, 0.12f)
        set(v) = prefs.edit().putFloat(KEY_BETA, v).apply()

    var safetyBuffer: Float
        get() = prefs.getFloat(KEY_SAFETY_BUFFER, 15.0f)
        set(v) = prefs.edit().putFloat(KEY_SAFETY_BUFFER, v).apply()

    var hapticsEnabled: Boolean
        get() = prefs.getBoolean(KEY_HAPTICS_ENABLED, true)
        set(v) = prefs.edit().putBoolean(KEY_HAPTICS_ENABLED, v).apply()

    var audioAlarmsEnabled: Boolean
        get() = prefs.getBoolean(KEY_AUDIO_ALARMS_ENABLED, true)
        set(v) = prefs.edit().putBoolean(KEY_AUDIO_ALARMS_ENABLED, v).apply()

    var autoPauseMusic: Boolean
        get() = prefs.getBoolean(KEY_AUTO_PAUSE_MUSIC, true)
        set(v) = prefs.edit().putBoolean(KEY_AUTO_PAUSE_MUSIC, v).apply()

    var recordProfile: RecordProfile
        get() =
            try {
                RecordProfile.valueOf(
                    prefs.getString(KEY_RECORD_PROFILE, RecordProfile.GENERAL.name) ?: RecordProfile.GENERAL.name,
                )
            } catch (_: Exception) {
                RecordProfile.GENERAL
            }
        set(v) = prefs.edit().putString(KEY_RECORD_PROFILE, v.name).apply()

    var gpsSamplingRateMs: Long
        get() = prefs.getLong(KEY_GPS_SAMPLING_MS, 1000L)
        set(v) = prefs.edit().putLong(KEY_GPS_SAMPLING_MS, v).apply()

    var minDistanceFilterM: Float
        get() = prefs.getFloat(KEY_MIN_DISTANCE_M, 10.0f)
        set(v) = prefs.edit().putFloat(KEY_MIN_DISTANCE_M, v).apply()

    var maxAccuracyFilterM: Float
        get() = prefs.getFloat(KEY_MAX_ACCURACY_M, 50.0f)
        set(v) = prefs.edit().putFloat(KEY_MAX_ACCURACY_M, v).apply()

    var extraFiltering: Boolean
        get() = prefs.getBoolean(KEY_EXTRA_FILTERING, true)
        set(v) = prefs.edit().putBoolean(KEY_EXTRA_FILTERING, v).apply()

    var autoMarkStops: Boolean
        get() = prefs.getBoolean(KEY_AUTO_MARK_STOPS, true)
        set(v) = prefs.edit().putBoolean(KEY_AUTO_MARK_STOPS, v).apply()

    var meshUsername: String
        get() = prefs.getString(KEY_MESH_USERNAME, "") ?: ""
        set(v) = prefs.edit().putString(KEY_MESH_USERNAME, v).apply()

    var meshColor: Int
        get() = prefs.getInt(KEY_MESH_COLOR, 0xFFFF5722.toInt())
        set(v) = prefs.edit().putInt(KEY_MESH_COLOR, v).apply()

    var keepScreenOn: Boolean
        get() = prefs.getBoolean(KEY_KEEP_SCREEN_ON, false)
        set(v) = prefs.edit().putBoolean(KEY_KEEP_SCREEN_ON, v).apply()

    var confirmStopRecording: Boolean
        get() = prefs.getBoolean(KEY_CONFIRM_STOP_RECORDING, true)
        set(v) = prefs.edit().putBoolean(KEY_CONFIRM_STOP_RECORDING, v).apply()

    companion object {
        private const val KEY_THEME_MODE = "KEY_THEME_MODE"
        private const val KEY_IS_OLED = "KEY_IS_OLED"
        private const val KEY_USE_IMPERIAL = "KEY_USE_IMPERIAL"
        private const val KEY_COORD_FORMAT = "KEY_COORD_FORMAT"
        private const val KEY_CHART_X_AXIS = "KEY_CHART_X_AXIS"
        private const val KEY_BETA = "KEY_BETA"
        private const val KEY_SAFETY_BUFFER = "KEY_SAFETY_BUFFER"
        private const val KEY_HAPTICS_ENABLED = "KEY_HAPTICS_ENABLED"
        private const val KEY_AUDIO_ALARMS_ENABLED = "KEY_AUDIO_ALARMS_ENABLED"
        private const val KEY_AUTO_PAUSE_MUSIC = "KEY_AUTO_PAUSE_MUSIC"
        private const val KEY_RECORD_PROFILE = "KEY_RECORD_PROFILE"
        private const val KEY_GPS_SAMPLING_MS = "KEY_GPS_SAMPLING_MS"
        private const val KEY_MIN_DISTANCE_M = "KEY_MIN_DISTANCE_M"
        private const val KEY_MAX_ACCURACY_M = "KEY_MAX_ACCURACY_M"
        private const val KEY_EXTRA_FILTERING = "KEY_EXTRA_FILTERING"
        private const val KEY_AUTO_MARK_STOPS = "KEY_AUTO_MARK_STOPS"
        private const val KEY_CONFIRM_STOP_RECORDING = "KEY_CONFIRM_STOP_RECORDING"
        private const val KEY_MESH_USERNAME = "KEY_MESH_USERNAME"
        private const val KEY_MESH_COLOR = "KEY_MESH_COLOR"
        private const val KEY_KEEP_SCREEN_ON = "KEY_KEEP_SCREEN_ON"

        @Volatile
        private var instance: AppSettings? = null

        fun getInstance(context: Context): AppSettings =
            instance ?: synchronized(this) {
                instance ?: AppSettings(context.applicationContext).also { instance = it }
            }
    }
}
