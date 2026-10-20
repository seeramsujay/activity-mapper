package org.opensource.tracker

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.KeyEvent
import java.util.Locale

/**
 * Activity-specific turn-back alarm shared by the GPS service and the Flutter method channel.
 *
 * - Cycling: pauses media playback so the tone is audible.
 * - Everything except walking/hiking: plays an alarm tone (ToneGenerator is released afterwards).
 * - Always: double-pulse haptic vibration.
 */
object TurnBackAlert {
    private const val TONE_DURATION_MS = 3500

    fun fire(
        context: Context,
        activityType: String,
        audioEnabled: Boolean = true,
        hapticsEnabled: Boolean = true,
        autoPauseMusic: Boolean = true
    ) {
        val type = activityType.lowercase(Locale.ROOT)
        val isWalking = type.contains("walk") || type.contains("hike")
        val isCycling = type.contains("ride") || type.contains("cycle") || type.contains("bike")

        if (isCycling && autoPauseMusic) {
            try {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                audioManager?.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PAUSE))
                audioManager?.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PAUSE))
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        if (!isWalking && audioEnabled) {
            try {
                val toneGen = ToneGenerator(AudioManager.STREAM_ALARM, 95)
                toneGen.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, TONE_DURATION_MS)
                Handler(Looper.getMainLooper()).postDelayed({ toneGen.release() }, TONE_DURATION_MS + 250L)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        if (!hapticsEnabled) return
        try {
            @Suppress("DEPRECATION")
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            val pattern = longArrayOf(0, 350, 150, 350)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, -1)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
