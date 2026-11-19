package org.opensource.tracker.ui.mesh

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import org.opensource.tracker.data.mesh.MeshPing
import org.opensource.tracker.data.mesh.PingType

/** Round map marker in the rider's colour carrying their initial. */
fun teammateIcon(
    context: Context,
    colorArgb: Int,
    name: String,
): BitmapDrawable {
    val density = context.resources.displayMetrics.density
    val size = (36 * density).toInt()
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    val center = size / 2f

    paint.color = Color.WHITE
    canvas.drawCircle(center, center, center, paint)
    paint.color = colorArgb
    canvas.drawCircle(center, center, center - 3 * density, paint)

    paint.color = Color.WHITE
    paint.textAlign = Paint.Align.CENTER
    paint.textSize = 16 * density
    paint.isFakeBoldText = true
    val baseline = center - (paint.descent() + paint.ascent()) / 2f
    canvas.drawText(name.trim().take(1).uppercase().ifEmpty { "?" }, center, baseline, paint)
    return BitmapDrawable(context.resources, bitmap)
}

/** Distinct buzz for an incoming group message; SOS is long and insistent. */
fun vibrateForPing(
    context: Context,
    ping: MeshPing,
) {
    val vibrator: Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    val pattern =
        if (ping.type == PingType.SOS) {
            longArrayOf(0, 600, 200, 600, 200, 600)
        } else {
            longArrayOf(0, 200, 100, 200)
        }
    vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
}
