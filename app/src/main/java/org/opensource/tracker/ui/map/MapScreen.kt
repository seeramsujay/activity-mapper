package org.opensource.tracker.ui.map

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.DashPathEffect
import android.location.Location
import android.location.LocationManager
import android.provider.Settings
import android.view.MotionEvent
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddLocationAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Route
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import org.opensource.tracker.domain.model.ActivityType
import org.opensource.tracker.domain.model.TelemetryStats
import org.opensource.tracker.domain.model.TrackPoint
import org.opensource.tracker.domain.turnback.TurnBackEngine
import org.opensource.tracker.service.GpsStatus
import org.opensource.tracker.service.TrackingService
import org.opensource.tracker.ui.components.MapLayersDialog
import org.opensource.tracker.ui.components.MapTileSource
import org.opensource.tracker.ui.components.OfflineMapsDialog
import org.opensource.tracker.ui.components.TrackColorMode
import org.opensource.tracker.ui.components.WaypointDialog
import org.opensource.tracker.ui.record.RecordingBottomSheetContent
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import org.osmdroid.views.overlay.mylocation.GpsMyLocationProvider
import org.osmdroid.views.overlay.mylocation.MyLocationNewOverlay
import java.time.Duration

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapScreen(
    service: TrackingService?,
    onNavigateToSummary: (Long) -> Unit,
    onNavigateToLibrary: () -> Unit,
    isOled: Boolean,
    onToggleOled: () -> Unit,
) {
    val context = LocalContext.current
    var hasLocationPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED,
        )
    }

    val permissionLauncher =
        rememberLauncherForActivityResult(
            contract = ActivityResultContracts.RequestMultiplePermissions(),
        ) { permissions ->
            hasLocationPermission = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true
        }

    LaunchedEffect(Unit) {
        if (!hasLocationPermission) {
            permissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
    }

    val scaffoldState = rememberBottomSheetScaffoldState()
    var showLayersDialog by remember { mutableStateOf(false) }
    var showOfflineMapsDialog by remember { mutableStateOf(false) }
    var showWaypointDialog by remember { mutableStateOf(false) }
    var selectedTileSource by remember { mutableStateOf(MapTileSource.OSM) }
    var trackColorMode by remember { mutableStateOf(TrackColorMode.SPEED) }
    var isCourseUpMode by remember { mutableStateOf(false) }

    val isTracking = service?.isTracking?.collectAsState()?.value ?: false
    val isPaused = service?.isPaused?.collectAsState()?.value ?: false
    val breakDuration = service?.breakDurationSeconds?.collectAsState()?.value ?: 0L
    val currentPoint = service?.currentPoint?.collectAsState()?.value
    val smoothedSpeed = service?.smoothedSpeedKmh?.collectAsState()?.value ?: 0.0
    val points = service?.points?.collectAsState()?.value ?: emptyList()
    val waypoints = service?.waypoints?.collectAsState()?.value ?: emptyList()
    val stats = service?.stats?.collectAsState()?.value ?: TelemetryStats()
    val turnBackTriggered = service?.turnBackTriggered?.collectAsState()?.value ?: false
    val outboundRemaining = service?.outboundRemainingSeconds?.collectAsState()?.value ?: 0L
    val referenceTrack = service?.referenceTrack?.collectAsState()?.value
    val gpsStatus = service?.gpsStatus?.collectAsState()?.value ?: GpsStatus.IDLE
    val lastAccuracy = service?.lastAccuracyMeters?.collectAsState()?.value

    var mapViewRef by remember { mutableStateOf<MapView?>(null) }

    // Everything osmdroid-related that must survive recomposition lives here, so the 1 Hz stats tick
    // can never trigger a tile-source reset or a full overlay rebuild.
    val render = remember { MapRenderState() }
    val followModeState = remember { mutableStateOf(true) }
    var followMode by followModeState

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, mapViewRef) {
        val mapView = mapViewRef
        val observer =
            LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_RESUME -> {
                        mapView?.onResume()
                        render.myLocation?.enableMyLocation()
                    }

                    Lifecycle.Event.ON_PAUSE -> {
                        mapView?.onPause()
                        render.myLocation?.disableMyLocation()
                    }

                    else -> Unit
                }
            }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            render.myLocation?.disableMyLocation()
            mapView?.onPause()
            mapView?.onDetach()
        }
    }

    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        sheetPeekHeight =
            if (isTracking) {
                if (isPaused) 200.dp else 125.dp
            } else {
                260.dp
            },
        sheetShape = MaterialTheme.shapes.extraLarge,
        sheetContent = {
            if (isTracking) {
                RecordingBottomSheetContent(
                    currentPoint = currentPoint,
                    smoothedSpeedKmh = smoothedSpeed,
                    stats = stats,
                    points = points,
                    isPaused = isPaused,
                    breakDurationSeconds = breakDuration,
                    turnBackTriggered = turnBackTriggered,
                    outboundRemainingSeconds = outboundRemaining,
                    onTogglePause = {
                        if (isPaused) service?.resumeTracking() else service?.pauseTracking()
                    },
                    onAddWaypoint = { showWaypointDialog = true },
                    onLogWaterBreak = { service?.logWaterBreakWaypoint() },
                    onToggleOled = onToggleOled,
                    onFinish = {
                        service?.stopAndSave(
                            onFailed = { message -> Toast.makeText(context, message, Toast.LENGTH_LONG).show() },
                            onSaved = { savedId -> onNavigateToSummary(savedId) },
                        )
                    },
                )
            } else {
                StartActivityLaunchpad(
                    onStartWorkout = { targetMinutes, activityType ->
                        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                        if (!hasLocationPermission) {
                            // Starting a location foreground service without permission crashes on Android 14+.
                            Toast
                                .makeText(context, "Location permission is required to record.", Toast.LENGTH_LONG)
                                .show()
                            permissionLauncher.launch(
                                arrayOf(
                                    Manifest.permission.ACCESS_FINE_LOCATION,
                                    Manifest.permission.ACCESS_COARSE_LOCATION,
                                ),
                            )
                        } else if (locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == false) {
                            Toast
                                .makeText(context, "Turn on GPS / Location to record.", Toast.LENGTH_LONG)
                                .show()
                            runCatching { context.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)) }
                        } else {
                            // Single start path: the service promotes itself to foreground in onStartCommand.
                            val serviceIntent =
                                Intent(context, TrackingService::class.java).apply {
                                    action = TrackingService.ACTION_START
                                    putExtra(TrackingService.EXTRA_TARGET_DURATION_SEC, targetMinutes * 60L)
                                    putExtra(
                                        TrackingService.EXTRA_BETA,
                                        if (activityType == ActivityType.CAR) 0.0 else 0.12,
                                    )
                                    putExtra(TrackingService.EXTRA_ACTIVITY_TYPE, activityType.name)
                                }
                            followMode = true
                            ContextCompat.startForegroundService(context, serviceIntent)
                        }
                    },
                )
            }
        },
    ) { paddingValues ->
        Box(
            modifier =
                Modifier
                    .fillMaxSize()
                    .padding(paddingValues),
        ) {
            // 1. Map Canvas with GPS Location Overlay
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    // osmdroid configuration (cache path + user agent) is initialised once in TurnBackApplication.
                    MapView(ctx).apply {
                        setMultiTouchControls(true)
                        controller.setZoom(17.0)
                        isTilesScaledToDpi = true

                        // Start on the user, not on (0,0) in the ocean: use the last known fix if we have one.
                        lastKnownLocation(ctx)?.let {
                            controller.setCenter(GeoPoint(it.latitude, it.longitude))
                            render.centeredOnce = true
                        }

                        // A drag means the user wants to look around: stop auto-following until Recenter.
                        setOnTouchListener { _, event ->
                            if (event.action == MotionEvent.ACTION_MOVE) followMode = false
                            false
                        }

                        mapViewRef = this
                    }
                },
                update = { mapView ->
                    // This block re-runs on every recomposition (the service ticks stats at 1 Hz), so every
                    // step below must be a cheap no-op unless its input actually changed.

                    // "My location" dot: (re)create once permission exists. Creating it in the factory meant it
                    // silently never worked when permission was granted after the map was first composed.
                    if (hasLocationPermission && render.myLocation == null) {
                        val overlay = MyLocationNewOverlay(GpsMyLocationProvider(mapView.context), mapView)
                        overlay.enableMyLocation()
                        overlay.runOnFirstFix {
                            mapView.post {
                                val fix = overlay.myLocation
                                if (fix != null && !render.centeredOnce && followModeState.value) {
                                    render.centeredOnce = true
                                    mapView.controller.animateTo(fix)
                                }
                            }
                        }
                        mapView.overlays.add(overlay)
                        render.myLocation = overlay
                    }

                    // Tile source: only swap when the user picks a different layer (a swap flushes the tile cache).
                    if (render.tileSource != selectedTileSource) {
                        mapView.setTileSource(tileSourceFor(selectedTileSource))
                        render.tileSource = selectedTileSource
                    }

                    // Dynamic Course-Up vs North-Up orientation for trail navigation
                    val targetOrientation =
                        if (isCourseUpMode && currentPoint != null && currentPoint.bearingDegrees > 0f) {
                            -currentPoint.bearingDegrees
                        } else {
                            0f
                        }
                    if (render.orientation != targetOrientation) {
                        mapView.setMapOrientation(targetOrientation, false)
                        render.orientation = targetOrientation
                    }

                    // Ghost / reference track: rebuilt only when the reference changes.
                    val ghostId = referenceTrack?.trackId
                    if (render.ghostTrackId != ghostId) {
                        render.ghostOverlay?.let { mapView.overlays.remove(it) }
                        render.ghostOverlay = null
                        if (referenceTrack != null && referenceTrack.points.isNotEmpty()) {
                            val ghost =
                                Polyline(mapView).apply {
                                    setPoints(referenceTrack.points.map { GeoPoint(it.latitude, it.longitude) })
                                    outlinePaint.strokeWidth = 11f
                                    outlinePaint.color = android.graphics.Color.parseColor("#8B5CF6")
                                    outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND
                                    outlinePaint.pathEffect = DashPathEffect(floatArrayOf(24f, 16f), 0f)
                                }
                            mapView.overlays.add(render.insertIndex(mapView), ghost)
                            render.ghostOverlay = ghost
                        }
                        render.ghostTrackId = ghostId
                    }

                    // Active recording polyline: append only the new fixes instead of rebuilding N points per tick.
                    if (points.size < render.trackRendered) {
                        // A new session started.
                        render.trackOverlay?.let { mapView.overlays.remove(it) }
                        render.trackOverlay = null
                        render.trackRendered = 0
                    }
                    if (points.isNotEmpty()) {
                        var track = render.trackOverlay
                        if (track == null) {
                            track =
                                Polyline(mapView).apply {
                                    outlinePaint.strokeWidth = 14f
                                    outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND
                                    outlinePaint.strokeJoin = android.graphics.Paint.Join.ROUND
                                }
                            mapView.overlays.add(render.insertIndex(mapView), track)
                            render.trackOverlay = track
                            render.trackColorMode = null // force colour to be applied to the new overlay
                        }
                        if (render.trackColorMode != trackColorMode) {
                            track.outlinePaint.color =
                                when (trackColorMode) {
                                    TrackColorMode.SPEED -> android.graphics.Color.parseColor("#06B6D4")
                                    TrackColorMode.ELEVATION -> android.graphics.Color.parseColor("#EAB308")
                                    TrackColorMode.SOLID -> android.graphics.Color.parseColor("#10B981")
                                }
                            render.trackColorMode = trackColorMode
                        }
                        for (i in render.trackRendered until points.size) {
                            track.addPoint(GeoPoint(points[i].latitude, points[i].longitude))
                        }
                        render.trackRendered = points.size
                    }

                    // Waypoint pins: rebuilt only when one is added/removed.
                    if (render.markersRendered != waypoints.size) {
                        render.markers.forEach { mapView.overlays.remove(it) }
                        render.markers.clear()
                        for (w in waypoints) {
                            val marker =
                                Marker(mapView).apply {
                                    position = GeoPoint(w.latitude, w.longitude)
                                    title = w.name
                                    snippet = w.category.displayName
                                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                                }
                            mapView.overlays.add(render.insertIndex(mapView), marker)
                            render.markers.add(marker)
                        }
                        render.markersRendered = waypoints.size
                    }

                    // Follow the runner, but only while the user hasn't panned away, and only on a new fix.
                    val latest = points.lastOrNull() ?: currentPoint
                    if (followMode && latest != null && latest !== render.lastFollowed) {
                        mapView.controller.animateTo(GeoPoint(latest.latitude, latest.longitude))
                        render.lastFollowed = latest
                        render.centeredOnce = true
                    }

                    mapView.invalidate()
                },
            )

            // GPS health banner: recording must never fail silently.
            val gpsMessage =
                if (!isTracking || isPaused) {
                    null
                } else {
                    when (gpsStatus) {
                        GpsStatus.NO_PERMISSION -> "Location permission missing. No track is being recorded."
                        GpsStatus.GPS_DISABLED -> "GPS is turned off. Enable Location to record."
                        GpsStatus.WAITING_FOR_FIX -> "Searching for GPS signal…"
                        GpsStatus.WEAK_SIGNAL ->
                            "Weak GPS signal" + (lastAccuracy?.let { " (±${it.toInt()} m)" } ?: "") + ", waiting for a better fix…"

                        GpsStatus.ACTIVE, GpsStatus.IDLE -> null
                    }
                }
            if (gpsMessage != null) {
                Card(
                    modifier =
                        Modifier
                            .align(Alignment.BottomCenter)
                            .padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors =
                        CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer,
                            contentColor = MaterialTheme.colorScheme.onErrorContainer,
                        ),
                ) {
                    Text(
                        text = gpsMessage,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }

            // 2. Active Ghost Track Badge (if reference route overlaid)
            if (referenceTrack != null) {
                Card(
                    modifier =
                        Modifier
                            .align(Alignment.TopStart)
                            .padding(top = 16.dp, start = 16.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f)),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.Route,
                            contentDescription = null,
                            tint = Color(0xFF8B5CF6),
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "Ghost: ${referenceTrack.title}",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF8B5CF6),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        IconButton(
                            onClick = { service?.clearReferenceTrack() },
                            modifier = Modifier.size(20.dp),
                        ) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Clear Ghost",
                                modifier = Modifier.size(14.dp),
                            )
                        }
                    }
                }
            }

            // 3. Glove-Friendly Floating Action Controls
            Column(
                modifier =
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 16.dp, end = 16.dp),
            ) {
                // Recenter
                FloatingActionButton(
                    onClick = {
                        followMode = true
                        val last = points.lastOrNull() ?: currentPoint
                        if (last != null) {
                            mapViewRef?.controller?.animateTo(GeoPoint(last.latitude, last.longitude))
                        } else {
                            val locOverlay =
                                mapViewRef?.overlays?.filterIsInstance<MyLocationNewOverlay>()?.firstOrNull()
                            locOverlay?.myLocation?.let {
                                mapViewRef?.controller?.animateTo(it)
                            }
                        }
                    },
                    modifier = Modifier.size(56.dp),
                    shape = CircleShape,
                    containerColor = MaterialTheme.colorScheme.surface,
                ) {
                    Icon(Icons.Default.MyLocation, contentDescription = "Recenter")
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Compass Course-Up / North-Up Toggle (Crucial for Trail Navigation)
                FloatingActionButton(
                    onClick = { isCourseUpMode = !isCourseUpMode },
                    modifier = Modifier.size(56.dp),
                    shape = CircleShape,
                    containerColor = if (isCourseUpMode) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
                ) {
                    Icon(
                        Icons.Default.Explore,
                        contentDescription = "Trail Compass Orientation",
                        tint = if (isCourseUpMode) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Map Layers Modal Switcher
                FloatingActionButton(
                    onClick = { showLayersDialog = true },
                    modifier = Modifier.size(56.dp),
                    shape = CircleShape,
                    containerColor = MaterialTheme.colorScheme.surface,
                ) {
                    Icon(Icons.Default.Layers, contentDescription = "Map Layers")
                }

                if (isTracking) {
                    Spacer(modifier = Modifier.height(12.dp))

                    // Drop Waypoint
                    SmallFloatingActionButton(
                        onClick = { showWaypointDialog = true },
                        modifier = Modifier.size(48.dp),
                        shape = CircleShape,
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                    ) {
                        Icon(Icons.Default.AddLocationAlt, contentDescription = "Add Waypoint")
                    }
                }
            }
        }
    }

    if (showLayersDialog) {
        MapLayersDialog(
            selectedSource = selectedTileSource,
            onSelectSource = { selectedTileSource = it },
            trackColorMode = trackColorMode,
            onSelectColorMode = { trackColorMode = it },
            onOpenOfflineMaps = { showOfflineMapsDialog = true },
            onDismiss = { showLayersDialog = false },
        )
    }

    if (showOfflineMapsDialog) {
        OfflineMapsDialog(
            currentLocation = currentPoint?.let { GeoPoint(it.latitude, it.longitude) },
            onDismiss = { showOfflineMapsDialog = false },
        )
    }

    if (showWaypointDialog) {
        WaypointDialog(
            onDismiss = { showWaypointDialog = false },
            onSave = { name, description, category ->
                service?.addWaypoint(name, description, category)
                showWaypointDialog = false
            },
        )
    }
}

/**
 * Mutable bookkeeping for what is already drawn on the MapView. Deliberately NOT Compose state: it must
 * not trigger recomposition, it only lets the `update` block do incremental work.
 */
private class MapRenderState {
    var myLocation: MyLocationNewOverlay? = null
    var tileSource: MapTileSource? = null
    var orientation: Float = Float.NaN
    var centeredOnce = false
    var lastFollowed: TrackPoint? = null

    var ghostOverlay: Polyline? = null
    var ghostTrackId: Long? = null

    var trackOverlay: Polyline? = null
    var trackRendered = 0
    var trackColorMode: TrackColorMode? = null

    val markers = mutableListOf<Marker>()
    var markersRendered = -1

    /** Keeps the "my location" dot on top of tracks and pins. */
    fun insertIndex(mapView: MapView): Int {
        val dot = myLocation ?: return mapView.overlays.size
        val index = mapView.overlays.indexOf(dot)
        return if (index >= 0) index else mapView.overlays.size
    }
}

private fun tileSourceFor(source: MapTileSource) =
    when (source) {
        MapTileSource.OSM -> TileSourceFactory.MAPNIK
        MapTileSource.TOPO -> TileSourceFactory.OpenTopo
        MapTileSource.DARK ->
            XYTileSource(
                "CartoDB_Dark",
                0,
                20,
                256,
                ".png",
                arrayOf("https://a.basemaps.cartocdn.com/dark_all/"),
            )

        MapTileSource.HOT ->
            XYTileSource(
                "OSM_HOT",
                0,
                20,
                256,
                ".png",
                arrayOf("https://a.tile.openstreetmap.fr/hot/"),
            )
    }

/** Freshest cached fix from any provider, so the map opens on the user instead of at (0, 0). */
@SuppressLint("MissingPermission")
private fun lastKnownLocation(context: Context): Location? {
    val granted =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    if (!granted) return null
    val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
    return listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)
        .mapNotNull { provider -> runCatching { manager.getLastKnownLocation(provider) }.getOrNull() }
        .maxByOrNull { it.time }
}

/**
 * Clean outdoor launchpad with duration slider and activity selection.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StartActivityLaunchpad(onStartWorkout: (targetMinutes: Int, activityType: ActivityType) -> Unit) {
    var selectedActivity by remember { mutableStateOf(ActivityType.RUN) }
    var selectedDurationMinutes by remember { mutableIntStateOf(60) }

    val isCar = selectedActivity == ActivityType.CAR
    val outboundLimit =
        TurnBackEngine.computeOutboundLimit(
            targetDuration = Duration.ofMinutes(selectedDurationMinutes.toLong()),
            beta = if (isCar) 0.0 else 0.12,
            safetyBufferPercent = if (isCar) 0.0 else 15.0,
        )

    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 6.dp),
    ) {
        Text(
            text = "READY FOR AN OUT-AND-BACK",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.5.sp,
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Activity selector chips
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            ActivityType.values().forEach { activity ->
                val icon =
                    when (activity) {
                        ActivityType.RUN -> Icons.Default.DirectionsRun
                        ActivityType.HIKE -> Icons.Default.Hiking
                        ActivityType.CYCLE -> Icons.Default.DirectionsBike
                        ActivityType.WALK -> Icons.Default.DirectionsWalk
                        ActivityType.CAR -> Icons.Default.DirectionsCar
                    }
                FilterChip(
                    selected = selectedActivity == activity,
                    onClick = { selectedActivity = activity },
                    label = { Text(activity.displayName, fontWeight = FontWeight.Bold) },
                    leadingIcon = { Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp)) },
                )
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Duration Slider (10 min to 240 min)
        val durationHours = selectedDurationMinutes / 60
        val durationMins = selectedDurationMinutes % 60
        val durationDisplay =
            if (durationHours > 0) {
                if (durationMins > 0) "${durationHours}h ${durationMins}m" else "${durationHours}h"
            } else {
                "${durationMins}m"
            }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "TOTAL TARGET DURATION",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = durationDisplay,
                fontSize = 16.sp,
                fontWeight = FontWeight.Black,
                color = MaterialTheme.colorScheme.primary,
            )
        }

        Slider(
            value = selectedDurationMinutes.toFloat(),
            onValueChange = { selectedDurationMinutes = ((it / 5).toInt() * 5).coerceIn(10, 240) },
            valueRange = 10f..240f,
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Turn-Around Preview Badge
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
        ) {
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Outbound Window: ~${outboundLimit.toMinutes()} min",
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = if (isCar) "Symmetric 50% split (Car)" else "Fatigue compensated",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Primary Big Start Button
        Button(
            onClick = { onStartWorkout(selectedDurationMinutes, selectedActivity) },
            modifier =
                Modifier
                    .fillMaxWidth()
                    .height(56.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
        ) {
            Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(24.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "START ${selectedActivity.displayName.uppercase()}",
                fontSize = 15.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 0.8.sp,
            )
        }

        Spacer(modifier = Modifier.height(8.dp))
    }
}
