package org.opensource.tracker.ui.components

import android.graphics.Color
import android.graphics.Paint
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import org.opensource.tracker.data.db.WaypointEntity
import org.opensource.tracker.domain.model.TrackPoint
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline

/**
 * Static route map for a finished activity: the full track, start/finish pins and waypoints,
 * framed to fit. Shown on the activity detail screen.
 */
@Composable
fun RouteMapCard(
    points: List<TrackPoint>,
    waypoints: List<WaypointEntity>,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val mapView =
        remember {
            MapView(context).apply {
                setTileSource(TileSourceFactory.MAPNIK)
                setMultiTouchControls(true)
                isTilesScaledToDpi = true
                controller.setZoom(15.0)
                // The map sits inside a vertically scrolling column: keep pan/zoom gestures for the map.
                setOnTouchListener { view, _ ->
                    view.parent?.requestDisallowInterceptTouchEvent(true)
                    false
                }
            }
        }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, mapView) {
        val observer =
            LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_RESUME -> mapView.onResume()
                    Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                    else -> Unit
                }
            }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            mapView.onPause()
            mapView.onDetach()
        }
    }

    Card(modifier = modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp)) {
        AndroidView(
            modifier = Modifier.fillMaxWidth().height(280.dp),
            factory = { mapView },
            update = { map ->
                map.overlays.clear()
                if (points.isEmpty()) return@AndroidView

                val geoPoints = points.map { GeoPoint(it.latitude, it.longitude) }
                // One line per segment, so a pause/gap between segments is never drawn as a straight connector.
                val segments = mutableListOf<MutableList<GeoPoint>>()
                points.forEachIndexed { index, point ->
                    if (index == 0 || point.newSegment) segments.add(mutableListOf())
                    segments.last().add(GeoPoint(point.latitude, point.longitude))
                }
                segments.forEach { segment ->
                    map.overlays.add(
                        Polyline(map).apply {
                            setPoints(segment)
                            outlinePaint.strokeWidth = 12f
                            outlinePaint.color = Color.parseColor("#06B6D4")
                            outlinePaint.strokeCap = Paint.Cap.ROUND
                            outlinePaint.strokeJoin = Paint.Join.ROUND
                        },
                    )
                }
                map.overlays.add(
                    Marker(map).apply {
                        position = geoPoints.first()
                        title = "Start"
                        setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                    },
                )
                if (geoPoints.size > 1) {
                    map.overlays.add(
                        Marker(map).apply {
                            position = geoPoints.last()
                            title = "Finish"
                            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                        },
                    )
                }
                waypoints.forEach { w ->
                    map.overlays.add(
                        Marker(map).apply {
                            position = GeoPoint(w.latitude, w.longitude)
                            title = w.name
                            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                        },
                    )
                }

                // Frame the route once the view has a size (post runs after layout).
                map.post {
                    if (geoPoints.size > 1) {
                        map.zoomToBoundingBox(BoundingBox.fromGeoPoints(geoPoints), false, 72)
                    } else {
                        map.controller.setZoom(16.0)
                        map.controller.setCenter(geoPoints.first())
                    }
                }
                map.invalidate()
            },
        )
    }
}
