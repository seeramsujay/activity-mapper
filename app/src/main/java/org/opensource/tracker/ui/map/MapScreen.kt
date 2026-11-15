package org.opensource.tracker.ui.map

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.DashPathEffect
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
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
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.runtime.Composable
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
import org.opensource.tracker.domain.model.ActivityType
import org.opensource.tracker.domain.model.TelemetryStats
import org.opensource.tracker.domain.turnback.TurnBackEngine
import org.opensource.tracker.service.TrackingService
import org.opensource.tracker.ui.components.MapLayersDialog
import org.opensource.tracker.ui.components.MapTileSource
import org.opensource.tracker.ui.components.TrackColorMode
import org.opensource.tracker.ui.components.WaypointDialog
import org.opensource.tracker.ui.record.RecordingBottomSheetContent
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import java.time.Duration
import java.util.Locale

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
    var showWaypointDialog by remember { mutableStateOf(false) }
    var selectedTileSource by remember { mutableStateOf(MapTileSource.OSM) }
    var trackColorMode by remember { mutableStateOf(TrackColorMode.SPEED) }
    var isCourseUpMode by remember { mutableStateOf(false) }
    var isScreenLocked by remember { mutableStateOf(false) }

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

    var mapViewRef by remember { mutableStateOf<MapView?>(null) }

    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        sheetPeekHeight =
            if (isTracking) {
                if (isPaused) 200.dp else 125.dp
            } else {
                240.dp
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
                        service?.stopAndSave { savedId ->
                            onNavigateToSummary(savedId)
                        }
                    },
                )
            } else {
                StartActivityLaunchpad(
                    onStartWorkout = { targetMinutes, activityType ->
                        service?.startTracking(
                            targetSec = targetMinutes * 60L,
                            beta = 0.12,
                            activityType = activityType,
                        )
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
            // 1. Map Canvas
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
                    MapView(ctx).apply {
                        setMultiTouchControls(true)
                        controller.setZoom(16.5)
                        isTilesScaledToDpi = true
                        mapViewRef = this
                    }
                },
                update = { mapView ->
                    mapView.setTileSource(
                        when (selectedTileSource) {
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
                        },
                    )

                    // Dynamic Course-Up vs North-Up orientation for trail navigation
                    if (isCourseUpMode && currentPoint != null && currentPoint.bearingDegrees > 0f) {
                        mapView.setMapOrientation(-currentPoint.bearingDegrees, false)
                    } else {
                        mapView.setMapOrientation(0f, false)
                    }

                    mapView.overlays.removeAll { it is Polyline || it is Marker }

                    // Render Ghost / Reference Track (Past Trail Run)
                    if (referenceTrack != null && referenceTrack.points.isNotEmpty()) {
                        val ghostGeoPoints = referenceTrack.points.map { GeoPoint(it.latitude, it.longitude) }
                        val ghostPolyline =
                            Polyline(mapView).apply {
                                setPoints(ghostGeoPoints)
                                outlinePaint.strokeWidth = 11f
                                outlinePaint.color = android.graphics.Color.parseColor("#8B5CF6")
                                outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND
                                outlinePaint.pathEffect = DashPathEffect(floatArrayOf(24f, 16f), 0f)
                            }
                        mapView.overlays.add(ghostPolyline)
                    }

                    // Render Active Recording Polyline
                    if (points.isNotEmpty()) {
                        val geoPoints = points.map { GeoPoint(it.latitude, it.longitude) }
                        val polyline =
                            Polyline(mapView).apply {
                                setPoints(geoPoints)
                                outlinePaint.strokeWidth = 14f
                                outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND
                                outlinePaint.strokeJoin = android.graphics.Paint.Join.ROUND
                                outlinePaint.color =
                                    when (trackColorMode) {
                                        TrackColorMode.SPEED -> android.graphics.Color.parseColor("#06B6D4")
                                        TrackColorMode.ELEVATION -> android.graphics.Color.parseColor("#EAB308")
                                        TrackColorMode.SOLID -> android.graphics.Color.parseColor("#10B981")
                                    }
                            }
                        mapView.overlays.add(polyline)

                        val latest = points.last()
                        mapView.controller.animateTo(GeoPoint(latest.latitude, latest.longitude))
                    }

                    // Render Waypoint Pins
                    for (w in waypoints) {
                        val marker =
                            Marker(mapView).apply {
                                position = GeoPoint(w.latitude, w.longitude)
                                title = w.name
                                snippet = w.category.displayName
                                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                            }
                        mapView.overlays.add(marker)
                    }

                    mapView.invalidate()
                },
            )

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
                        Icon(Icons.Default.Route, contentDescription = null, tint = Color(0xFF8B5CF6), modifier = Modifier.size(16.dp))
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
                            Icon(Icons.Default.Close, contentDescription = "Clear Ghost", modifier = Modifier.size(14.dp))
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
                        val last = points.lastOrNull() ?: currentPoint
                        if (last != null) {
                            mapViewRef?.controller?.animateTo(GeoPoint(last.latitude, last.longitude))
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

                    // Screen Lock (Wet Screen / Running Vest Pocket Protection)
                    SmallFloatingActionButton(
                        onClick = { isScreenLocked = !isScreenLocked },
                        modifier = Modifier.size(48.dp),
                        shape = CircleShape,
                        containerColor = if (isScreenLocked) Color(0xFFEF4444) else MaterialTheme.colorScheme.surfaceVariant,
                    ) {
                        Icon(
                            imageVector = if (isScreenLocked) Icons.Default.Lock else Icons.Default.LockOpen,
                            contentDescription = "Pocket / Rain Lock",
                            tint = if (isScreenLocked) Color.White else MaterialTheme.colorScheme.onSurface,
                        )
                    }

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

            // 4. Full-Screen Pocket / Rain Lock Overlay (Sweaty Hands & Pocket Mode)
            if (isScreenLocked) {
                Box(
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.85f))
                            .padding(24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(Icons.Default.Lock, contentDescription = null, tint = Color(0xFF10B981), modifier = Modifier.size(48.dp))
                        Spacer(modifier = Modifier.height(12.dp))
                        Text("POCKET & RAIN LOCK ACTIVE", fontWeight = FontWeight.Black, fontSize = 16.sp, color = Color.White)
                        Text("Accidental screen touches blocked", style = MaterialTheme.typography.bodySmall, color = Color.LightGray)

                        Spacer(modifier = Modifier.height(28.dp))

                        // Glanceable giant numbers while running
                        Text(
                            text = String.format(Locale.US, "%.2f km", stats.distanceKm),
                            fontSize = 44.sp,
                            fontWeight = FontWeight.Black,
                            color = Color.White,
                        )
                        Text(
                            text = "PACE ${stats.avgPaceMinKm}/km • TIME ${formatDuration(stats.totalDuration)}",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF06B6D4),
                        )

                        Spacer(modifier = Modifier.height(36.dp))

                        Button(
                            onClick = { isScreenLocked = false },
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                            shape = RoundedCornerShape(16.dp),
                            modifier = Modifier.height(52.dp),
                        ) {
                            Icon(Icons.Default.LockOpen, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("TAP TO UNLOCK SCREEN", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }

    if (showLayersDialog) {
        MapLayersDialog(
            currentTileSource = selectedTileSource,
            currentTrackColorMode = trackColorMode,
            onSelectTileSource = { selectedTileSource = it },
            onSelectTrackColorMode = { trackColorMode = it },
            onDismiss = { showLayersDialog = false },
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
 * Clean, distraction-free outdoor launchpad (inspired by OfflineGPX & rando-gpx).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StartActivityLaunchpad(onStartWorkout: (targetMinutes: Int, activityType: ActivityType) -> Unit) {
    var selectedActivity by remember { mutableStateOf(ActivityType.RUN) }
    var selectedDurationMinutes by remember { mutableIntStateOf(60) }

    val outboundLimit =
        TurnBackEngine.computeOutboundLimit(
            targetDuration = Duration.ofMinutes(selectedDurationMinutes.toLong()),
            beta = 0.12,
            safetyBufferPercent = 15.0,
        )

    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 10.dp),
    ) {
        // Drag Pill
        Box(
            modifier =
                Modifier
                    .align(Alignment.CenterHorizontally)
                    .width(44.dp)
                    .height(4.dp)
                    .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f), RoundedCornerShape(2.dp)),
        )

        Spacer(modifier = Modifier.height(14.dp))

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
                    }
                FilterChip(
                    selected = selectedActivity == activity,
                    onClick = { selectedActivity = activity },
                    label = { Text(activity.displayName, fontWeight = FontWeight.Bold) },
                    leadingIcon = { Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp)) },
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Duration selector chips
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            listOf(30, 45, 60, 90, 120).forEach { mins ->
                val isSelected = selectedDurationMinutes == mins
                SuggestionChip(
                    onClick = { selectedDurationMinutes = mins },
                    label = {
                        Text(
                            "${mins}m",
                            fontWeight = if (isSelected) FontWeight.Black else FontWeight.Bold,
                            color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                        )
                    },
                    modifier = Modifier.weight(1f),
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

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
                    text = "Returns on time",
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

private fun formatDuration(d: Duration): String {
    val h = d.toHours()
    val m = (d.toMinutes() % 60)
    val s = (d.seconds % 60)
    return if (h > 0) {
        String.format("%d:%02d:%02d", h, m, s)
    } else {
        String.format("%02d:%02d", m, s)
    }
}
