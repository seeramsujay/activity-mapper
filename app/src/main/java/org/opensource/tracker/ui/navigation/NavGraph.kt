package org.opensource.tracker.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import org.opensource.tracker.domain.model.TelemetryStats
import org.opensource.tracker.service.TrackingService
import org.opensource.tracker.ui.detail.TrackDetailScreen
import org.opensource.tracker.ui.library.LibraryScreen
import org.opensource.tracker.ui.map.MapScreen
import org.opensource.tracker.ui.settings.SettingsScreen
import java.time.Duration
import java.util.Locale

sealed class Screen(val route: String, val title: String, val icon: ImageVector) {
    object Map : Screen("map", "Map", Icons.Default.Map)
    object Library : Screen("library", "Library", Icons.Default.Route)
    object Settings : Screen("settings", "Settings", Icons.Default.Settings)
    object Detail : Screen("detail/{trackId}", "Detail", Icons.Default.Route) {
        fun createRoute(trackId: Long) = "detail/$trackId"
    }
}

@Composable
fun TurnBackNavGraph(
    service: TrackingService?,
    isOled: Boolean,
    onToggleOled: () -> Unit,
    navController: NavHostController = rememberNavController()
) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val showBottomBar = currentRoute in listOf(Screen.Map.route, Screen.Library.route, Screen.Settings.route)

    val isTracking = service?.isTracking?.collectAsState()?.value ?: false
    val isPaused = service?.isPaused?.collectAsState()?.value ?: false
    val stats = service?.stats?.collectAsState()?.value ?: TelemetryStats()

    Scaffold(
        bottomBar = {
            Column {
                // Persistent Active Recording Banner when navigating away from the Map screen
                if (isTracking && currentRoute != Screen.Map.route) {
                    ActiveRecordingMiniBar(
                        isPaused = isPaused,
                        stats = stats,
                        onTogglePause = {
                            if (isPaused) service?.resumeTracking() else service?.pauseTracking()
                        },
                        onClick = {
                            navController.navigate(Screen.Map.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    )
                }

                if (showBottomBar) {
                    NavigationBar {
                        listOf(Screen.Map, Screen.Library, Screen.Settings).forEach { screen ->
                            NavigationBarItem(
                                icon = { Icon(screen.icon, contentDescription = screen.title) },
                                label = { Text(screen.title) },
                                selected = currentRoute == screen.route,
                                onClick = {
                                    navController.navigate(screen.route) {
                                        popUpTo(navController.graph.findStartDestination().id) {
                                            saveState = true
                                        }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Map.route,
            modifier = Modifier.padding(padding)
        ) {
            composable(Screen.Map.route) {
                MapScreen(
                    service = service,
                    onNavigateToSummary = { trackId ->
                        navController.navigate(Screen.Detail.createRoute(trackId))
                    },
                    onNavigateToLibrary = {
                        navController.navigate(Screen.Library.route)
                    },
                    isOled = isOled,
                    onToggleOled = onToggleOled
                )
            }
            composable(Screen.Library.route) {
                LibraryScreen(
                    onTrackClick = { trackId ->
                        navController.navigate(Screen.Detail.createRoute(trackId))
                    }
                )
            }
            composable(Screen.Settings.route) {
                SettingsScreen(
                    isOled = isOled,
                    onToggleOled = onToggleOled
                )
            }
            composable(
                route = Screen.Detail.route,
                arguments = listOf(navArgument("trackId") { type = NavType.LongType })
            ) { backStackEntry ->
                val trackId = backStackEntry.arguments?.getLong("trackId") ?: 0L
                TrackDetailScreen(
                    trackId = trackId,
                    service = service,
                    onBack = { navController.popBackStack() },
                    onOverlayOnMap = {
                        navController.navigate(Screen.Map.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                )
            }
        }
    }
}

/**
 * Glanceable floating mini-player bar allowing the runner to view past activities in Library
 * while keeping instant 1-tap control over their active background recording.
 */
@Composable
private fun ActiveRecordingMiniBar(
    isPaused: Boolean,
    stats: TelemetryStats,
    onTogglePause: () -> Unit,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isPaused) Color(0xFFF59E0B).copy(alpha = 0.2f) else MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .background(if (isPaused) Color(0xFFF59E0B) else Color(0xFF10B981), CircleShape)
            )

            Spacer(modifier = Modifier.width(10.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (isPaused) "DRINKS BREAK (PAUSED)" else "ACTIVE RUNNING SESSION",
                    fontWeight = FontWeight.Black,
                    fontSize = 11.sp,
                    color = if (isPaused) Color(0xFFD97706) else MaterialTheme.colorScheme.primary
                )
                Text(
                    text = "${formatDuration(stats.totalDuration)} • ${String.format(Locale.US, "%.2f km", stats.distanceKm)} • ${stats.avgPaceMinKm}/km",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Bold
                )
            }

            // Quick Continue / Pause puck
            FilledIconButton(
                onClick = onTogglePause,
                modifier = Modifier.size(38.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = if (isPaused) Color(0xFF10B981) else MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Icon(
                    imageVector = if (isPaused) Icons.Default.PlayArrow else Icons.Default.Pause,
                    contentDescription = if (isPaused) "Resume" else "Pause",
                    modifier = Modifier.size(20.dp),
                    tint = if (isPaused) Color.White else MaterialTheme.colorScheme.onSurface
                )
            }

            Spacer(modifier = Modifier.width(6.dp))

            Icon(
                imageVector = Icons.AutoMirrored.Default.ArrowForward,
                contentDescription = "Return to Map",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

private fun formatDuration(d: Duration): String {
    val h = d.toHours()
    val m = (d.toMinutes() % 60)
    val s = (d.seconds % 60)
    return if (h > 0) String.format("%d:%02d:%02d", h, m, s)
    else String.format("%02d:%02d", m, s)
}
