package org.opensource.tracker.ui.map

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
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
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapScreen(
    service: TrackingService?,
    onNavigateToSummary: (Long) -> Unit,
    onNavigateToLibrary: () -> Unit,
    isOled: Boolean,
    onToggleOled: () -> Unit
) {
    val context = LocalContext.current
    var hasLocationPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        )
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        hasLocationPermission = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true
    }

    LaunchedEffect(Unit) {
        if (!hasLocationPermission) {
            permissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                )
            )
        }
    }

    val scaffoldState = rememberBottomSheetScaffoldState()
    var showLayersDialog by remember { mutableStateOf(false) }
    var showWaypointDialog by remember { mutableStateOf(false) }
    var selectedTileSource by remember { mutableStateOf(MapTileSource.OSM) }
    var trackColorMode by remember { mutableStateOf(TrackColorMode.SPEED) }

    val isTracking = service?.isTracking?.collectAsState()?.value ?: false
    val isPaused = service?.isPaused?.collectAsState()?.value ?: false
    val currentPoint = service?.currentPoint?.collectAsState()?.value
    val points = service?.points?.collectAsState()?.value ?: emptyList()
    val waypoints = service?.waypoints?.collectAsState()?.value ?: emptyList()
    val stats = service?.stats?.collectAsState()?.value ?: TelemetryStats()
    val turnBackTriggered = service?.turnBackTriggered?.collectAsState()?.value ?: false
    val outboundRemaining = service?.outboundRemainingSeconds?.collectAsState()?.value ?: 0L

    var mapViewRef by remember { mutableStateOf<MapView?>(null) }

    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        sheetPeekHeight = if (isTracking) 120.dp else 220.dp,
        sheetShape = MaterialTheme.shapes.extraLarge,
        sheetContent = {
            if (isTracking) {
                RecordingBottomSheetContent(
                    currentPoint = currentPoint,
                    stats = stats,
                    points = points,
                    isPaused = isPaused,
                    turnBackTriggered = turnBackTriggered,
                    outboundRemainingSeconds = outboundRemaining,
                    onTogglePause = {
                        if (isPaused) service?.resumeTracking() else service?.pauseTracking()
                    },
                    onAddWaypoint = { showWaypointDialog = true },
                    onToggleOled = onToggleOled,
                    onFinish = {
                        service?.stopAndSave { savedId ->
                            onNavigateToSummary(savedId)
                        }
                    }
                )
            } else {
                StartActivityLaunchpad(
                    onStartWorkout = { targetMinutes, activityType ->
                        service?.startTracking(
                            targetSec = targetMinutes * 60L,
                            beta = 0.12,
                            activityType = activityType
                        )
                    }
                )
            }
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Map Canvas
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
                            MapTileSource.DARK -> XYTileSource(
                                "CartoDB_Dark",
                                0,
                                20,
                                256,
                                ".png",
                                arrayOf("https://a.basemaps.cartocdn.com/dark_all/")
                            )
                            MapTileSource.HOT -> XYTileSource(
                                "OSM_HOT",
                                0,
                                20,
                                256,
                                ".png",
                                arrayOf("https://a.tile.openstreetmap.fr/hot/")
                            )
                        }
                    )

                    mapView.overlays.removeAll { it is Polyline || it is Marker }

                    if (points.isNotEmpty()) {
                        val geoPoints = points.map { GeoPoint(it.latitude, it.longitude) }
                        val polyline = Polyline(mapView).apply {
                            setPoints(geoPoints)
                            outlinePaint.strokeWidth = 14f
                            outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND
                            outlinePaint.strokeJoin = android.graphics.Paint.Join.ROUND
                            outlinePaint.color = when (trackColorMode) {
                                TrackColorMode.SPEED -> android.graphics.Color.parseColor("#06B6D4")
                                TrackColorMode.ELEVATION -> android.graphics.Color.parseColor("#EAB308")
                                TrackColorMode.SOLID -> android.graphics.Color.parseColor("#10B981")
                            }
                        }
                        mapView.overlays.add(polyline)

                        val latest = points.last()
                        mapView.controller.animateTo(GeoPoint(latest.latitude, latest.longitude))
                    }

                    for (w in waypoints) {
                        val marker = Marker(mapView).apply {
                            position = GeoPoint(w.latitude, w.longitude)
                            title = w.name
                            snippet = w.category.displayName
                            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                        }
                        mapView.overlays.add(marker)
                    }

                    mapView.invalidate()
                }
            )

            // Ergonomic Heavy-Glove Floating Action Controls
            Column(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 16.dp, end = 16.dp)
            ) {
                FloatingActionButton(
                    onClick = {
                        val last = points.lastOrNull() ?: currentPoint
                        if (last != null && mapViewRef != null) {
                            mapViewRef?.controller?.animateTo(GeoPoint(last.latitude, last.longitude))
                        }
                    },
                    modifier = Modifier.size(56.dp),
                    shape = CircleShape,
                    containerColor = MaterialTheme.colorScheme.surface
                ) {
                    Icon(Icons.Default.MyLocation, contentDescription = "Recenter")
                }

                Spacer(modifier = Modifier.height(12.dp))

                FloatingActionButton(
                    onClick = { showLayersDialog = true },
                    modifier = Modifier.size(56.dp),
                    shape = CircleShape,
                    containerColor = MaterialTheme.colorScheme.surface
                ) {
                    Icon(Icons.Default.Layers, contentDescription = "Map Layers")
                }

                if (isTracking) {
                    Spacer(modifier = Modifier.height(12.dp))

                    SmallFloatingActionButton(
                        onClick = { showWaypointDialog = true },
                        modifier = Modifier.size(48.dp),
                        shape = CircleShape,
                        containerColor = MaterialTheme.colorScheme.primaryContainer
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
            onSelectSource = {
                selectedTileSource = it
                showLayersDialog = false
            },
            trackColorMode = trackColorMode,
            onSelectColorMode = {
                trackColorMode = it
                showLayersDialog = false
            },
            onDismiss = { showLayersDialog = false }
        )
    }

    if (showWaypointDialog) {
        WaypointDialog(
            onDismiss = { showWaypointDialog = false },
            onSave = { name, desc, category ->
                service?.addWaypoint(name, desc, category)
            }
        )
    }
}

/**
 * Clean, distraction-free outdoor launchpad (inspired by OfflineGPX & rando-gpx).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StartActivityLaunchpad(
    onStartWorkout: (targetMinutes: Int, activityType: ActivityType) -> Unit
) {
    var selectedActivity by remember { mutableStateOf(ActivityType.RUN) }
    var selectedDurationMinutes by remember { mutableIntStateOf(60) }

    val outboundLimit = TurnBackEngine.computeOutboundLimit(
        targetDuration = Duration.ofMinutes(selectedDurationMinutes.toLong()),
        beta = 0.12,
        safetyBufferPercent = 15.0
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 10.dp)
    ) {
        // Drag Pill
        Box(
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .width(44.dp)
                .height(4.dp)
                .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f), RoundedCornerShape(2.dp))
        )

        Spacer(modifier = Modifier.height(14.dp))

        Text(
            text = "READY FOR AN OUT-AND-BACK",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.5.sp
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Activity selector chips
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            ActivityType.values().forEach { activity ->
                val icon = when (activity) {
                    ActivityType.RUN -> Icons.Default.DirectionsRun
                    ActivityType.HIKE -> Icons.Default.Hiking
                    ActivityType.CYCLE -> Icons.Default.DirectionsBike
                    ActivityType.WALK -> Icons.Default.DirectionsWalk
                }
                FilterChip(
                    selected = selectedActivity == activity,
                    onClick = { selectedActivity = activity },
                    label = { Text(activity.displayName, fontWeight = FontWeight.Bold) },
                    leadingIcon = { Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp)) }
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Duration selector chips
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            listOf(30, 45, 60, 90, 120).forEach { mins ->
                val isSelected = selectedDurationMinutes == mins
                SuggestionChip(
                    onClick = { selectedDurationMinutes = mins },
                    label = {
                        Text(
                            "${mins}m",
                            fontWeight = if (isSelected) FontWeight.Black else FontWeight.Bold,
                            color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                        )
                    },
                    modifier = Modifier.weight(1f)
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Turn-Around Preview Badge
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Outbound Window: ~${outboundLimit.toMinutes()} min",
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = "Returns on time",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Primary Big Start Button
        Button(
            onClick = { onStartWorkout(selectedDurationMinutes, selectedActivity) },
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
        ) {
            Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(24.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "START ${selectedActivity.displayName.uppercase()}",
                fontSize = 15.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 0.8.sp
            )
        }

        Spacer(modifier = Modifier.height(8.dp))
    }
}
