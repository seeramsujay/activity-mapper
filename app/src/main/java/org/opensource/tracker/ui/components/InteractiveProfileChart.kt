package org.opensource.tracker.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.opensource.tracker.domain.model.TrackPoint
import java.util.Locale

/**
 * Interactive elevation & speed telemetry chart inspired by Geo Tracker & OfflineGPX.
 * Supports smooth touch scrubbing and live point inspection.
 */
@Composable
fun InteractiveProfileChart(
    points: List<TrackPoint>,
    modifier: Modifier = Modifier,
    elevationColor: Color = Color(0xFF10B981),
    speedColor: Color = Color(0xFF06B6D4),
) {
    if (points.size < 2) {
        Box(
            modifier =
                modifier
                    .fillMaxWidth()
                    .height(180.dp),
            contentAlignment = Alignment.center,
        ) {
            Text(
                text = "Logging GPS points to render elevation profile...",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    var scrubFraction by remember { mutableFloatStateOf(-1f) }
    var selectedIndex by remember { mutableStateOf<Int?>(null) }

    val minAlt = points.minOf { it.altitudeMeters }
    val maxAlt = points.maxOf { it.altitudeMeters }.coerceAtLeast(minAlt + 10.0)
    val maxSpeed = points.maxOf { it.speedKmh }.coerceAtLeast(5.0)

    val selectedPoint = selectedIndex?.let { points.getOrNull(it) }

    Column(modifier = modifier.fillMaxWidth()) {
        // Scrubber Telemetry Header
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (selectedPoint != null) {
                Text(
                    text = String.format(Locale.US, "Alt: %.0f m", selectedPoint.altitudeMeters),
                    color = elevationColor,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = String.format(Locale.US, "Spd: %.1f km/h", selectedPoint.speedKmh),
                    color = speedColor,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                )
            } else {
                Text(
                    text = String.format(Locale.US, "Range: %.0f – %.0f m", minAlt, maxAlt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = String.format(Locale.US, "Max Spd: %.1f km/h", maxSpeed),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // Canvas Graph
        Box(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .height(160.dp)
                    .background(
                        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                        RoundedCornerShape(12.dp),
                    ).pointerInput(points) {
                        detectTapGestures(
                            onPress = { offset ->
                                val frac = (offset.x / size.width).coerceIn(0f, 1f)
                                scrubFraction = frac
                                selectedIndex = (frac * (points.size - 1)).toInt()
                            },
                        )
                    }.pointerInput(points) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                val frac = (offset.x / size.width).coerceIn(0f, 1f)
                                scrubFraction = frac
                                selectedIndex = (frac * (points.size - 1)).toInt()
                            },
                            onDragEnd = {
                                scrubFraction = -1f
                                selectedIndex = null
                            },
                            onDragCancel = {
                                scrubFraction = -1f
                                selectedIndex = null
                            },
                            onDrag = { change, _ ->
                                change.consume()
                                val frac = (change.position.x / size.width).coerceIn(0f, 1f)
                                scrubFraction = frac
                                selectedIndex = (frac * (points.size - 1)).toInt()
                            },
                        )
                    },
        ) {
            Canvas(modifier = Modifier.fillMaxSize().padding(horizontal = 8.dp, vertical = 8.dp)) {
                val w = size.width
                val h = size.height
                val count = points.size

                val elevationPath = Path()
                val elevationFillPath = Path()
                val speedPath = Path()

                val altRange = (maxAlt - minAlt).coerceAtLeast(1.0)

                for (i in 0 until count) {
                    val p = points[i]
                    val x = (i.toFloat() / (count - 1).toFloat()) * w

                    // Elevation mapping (bottom to top)
                    val normAlt = ((p.altitudeMeters - minAlt) / altRange).coerceIn(0.0, 1.0).toFloat()
                    val yAlt = h - (normAlt * (h * 0.75f)) - (h * 0.1f)

                    // Speed mapping (faint upper overlay)
                    val normSpeed = (p.speedKmh / maxSpeed).coerceIn(0.0, 1.0).toFloat()
                    val ySpeed = h - (normSpeed * (h * 0.65f)) - (h * 0.1f)

                    if (i == 0) {
                        elevationPath.moveTo(x, yAlt)
                        elevationFillPath.moveTo(x, h)
                        elevationFillPath.lineTo(x, yAlt)
                        speedPath.moveTo(x, ySpeed)
                    } else {
                        elevationPath.lineTo(x, yAlt)
                        elevationFillPath.lineTo(x, yAlt)
                        speedPath.lineTo(x, ySpeed)
                    }

                    if (i == count - 1) {
                        elevationFillPath.lineTo(x, h)
                        elevationFillPath.close()
                    }
                }

                // 1. Elevation Gradient Fill
                drawPath(
                    path = elevationFillPath,
                    brush =
                        Brush.verticalGradient(
                            colors = listOf(elevationColor.copy(alpha = 0.35f), elevationColor.copy(alpha = 0.02f)),
                            startY = 0f,
                            endY = h,
                        ),
                )

                // 2. Speed Line (Subtle)
                drawPath(
                    path = speedPath,
                    color = speedColor.copy(alpha = 0.45f),
                    style = Stroke(width = 1.8f, cap = StrokeCap.Round),
                )

                // 3. Elevation Line (Bold)
                drawPath(
                    path = elevationPath,
                    color = elevationColor,
                    style = Stroke(width = 3.0f, cap = StrokeCap.Round),
                )

                // 4. Scrubbing Indicator Line
                if (scrubFraction >= 0f) {
                    val scrubX = scrubFraction * w
                    drawLine(
                        color = Color.White,
                        start = Offset(scrubX, 0f),
                        end = Offset(scrubX, h),
                        strokeWidth = 2.0f,
                    )
                    drawCircle(
                        color = elevationColor,
                        radius = 6.0f,
                        center =
                            Offset(
                                scrubX,
                                h - (((selectedPoint?.altitudeMeters ?: minAlt) - minAlt) / altRange).toFloat() * (h * 0.75f) - (h * 0.1f),
                            ),
                    )
                }
            }
        }
    }
}
