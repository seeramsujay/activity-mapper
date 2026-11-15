package org.opensource.tracker.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import org.opensource.tracker.service.TrackingService
import org.opensource.tracker.ui.detail.TrackDetailScreen
import org.opensource.tracker.ui.library.LibraryScreen
import org.opensource.tracker.ui.map.MapScreen
import org.opensource.tracker.ui.settings.SettingsScreen

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

    Scaffold(
        bottomBar = {
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
                    onBack = { navController.popBackStack() }
                )
            }
        }
    }
}
