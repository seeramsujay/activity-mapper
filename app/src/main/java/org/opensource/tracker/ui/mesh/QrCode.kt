package org.opensource.tracker.ui.mesh

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/** Draws [content] as a QR code (black modules on a white card with a quiet zone, so any camera can read it). */
@Composable
fun QrCode(
    content: String,
    modifier: Modifier = Modifier,
) {
    val matrix =
        remember(content) {
            runCatching {
                QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.MARGIN to 0))
            }.getOrNull()
        }
    Box(modifier = modifier.background(Color.White).padding(14.dp)) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val m = matrix ?: return@Canvas
            val cell = size.minDimension / m.width
            for (y in 0 until m.height) {
                for (x in 0 until m.width) {
                    if (m.get(x, y)) {
                        drawRect(
                            color = Color.Black,
                            topLeft = Offset(x * cell, y * cell),
                            size = Size(cell + 0.5f, cell + 0.5f),
                        )
                    }
                }
            }
        }
    }
}
