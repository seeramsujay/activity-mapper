package org.opensource.tracker.ui.library

import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import kotlinx.coroutines.launch
import org.opensource.tracker.data.db.AppDatabase
import org.opensource.tracker.data.db.TrackEntity
import org.opensource.tracker.data.gpx.GpxTrackImporter
import org.opensource.tracker.data.settings.AppSettings
import org.opensource.tracker.ui.util.UnitFormat
import java.io.File
import java.text.SimpleDateFormat
import java.time.Duration
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(onTrackClick: (Long) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val db = AppDatabase.getInstance(context)
    val tracks by db.trackDao().getAllTracks().collectAsState(initial = emptyList())

    val importLauncher =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) {
                scope.launch {
                    GpxTrackImporter
                        .import(context, uri)
                        .onSuccess { Toast.makeText(context, "Imported to your library", Toast.LENGTH_SHORT).show() }
                        .onFailure { Toast.makeText(context, it.message ?: "Import failed", Toast.LENGTH_LONG).show() }
                }
            }
        }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Track Library", fontWeight = FontWeight.Black) },
                actions = {
                    IconButton(onClick = { importLauncher.launch(arrayOf("*/*")) }) {
                        Icon(Icons.Default.FileOpen, contentDescription = "Import GPX")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
    ) { padding ->
        if (tracks.isEmpty()) {
            Box(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        imageVector = Icons.Default.Route,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        "No recorded workouts yet",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Start an out-and-back session to log GPS tracks",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            LazyColumn(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(tracks, key = { it.id }) { track ->
                    TrackItemCard(
                        track = track,
                        onClick = { onTrackClick(track.id) },
                        onShareGpx = { shareGpxTrack(context, track) },
                        onDelete = {
                            scope.launch {
                                db.trackDao().deleteTrack(track)
                            }
                        },
                    )
                }
            }
        }
    }
}

private fun shareGpxTrack(
    context: Context,
    track: TrackEntity,
) {
    val gpxPath = track.gpxFilePath
    if (gpxPath.isNullOrBlank()) {
        Toast.makeText(context, "No GPX file available for this activity", Toast.LENGTH_SHORT).show()
        return
    }
    val file = File(gpxPath)
    if (!file.exists()) {
        Toast.makeText(context, "GPX file not found on disk", Toast.LENGTH_SHORT).show()
        return
    }
    val uri =
        FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )
    val shareIntent =
        Intent(Intent.ACTION_SEND).apply {
            type = "application/gpx+xml"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, track.title)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    context.startActivity(Intent.createChooser(shareIntent, "Export GPX Track"))
}

@Composable
private fun TrackItemCard(
    track: TrackEntity,
    onClick: () -> Unit,
    onShareGpx: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(
        modifier =
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)),
    ) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val icon =
                when (track.activityType.uppercase(Locale.ROOT)) {
                    "HIKE" -> Icons.Default.Hiking
                    "CYCLE", "BIKE" -> Icons.Default.DirectionsBike
                    "WALK" -> Icons.Default.DirectionsWalk
                    "CAR" -> Icons.Default.DirectionsCar
                    else -> Icons.Default.DirectionsRun
                }

            Box(
                modifier =
                    Modifier
                        .size(44.dp)
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp),
                )
            }

            Spacer(modifier = Modifier.width(14.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = track.title,
                    fontWeight = FontWeight.ExtraBold,
                    fontSize = 15.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(modifier = Modifier.height(3.dp))
                val dateStr = SimpleDateFormat("MMM d, yyyy • HH:mm", Locale.getDefault()).format(Date(track.startTime))
                Text(dateStr, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)

                Spacer(modifier = Modifier.height(6.dp))

                val imperial = AppSettings.getInstance(LocalContext.current).useImperialUnits
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = UnitFormat.distance(track.distanceKm, imperial),
                        fontWeight = FontWeight.Black,
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = formatDuration(Duration.ofSeconds(track.totalDurationSeconds)),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = UnitFormat.elevation(track.elevationGainMeters, imperial),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF10B981),
                    )
                }
            }

            IconButton(onClick = onShareGpx) {
                Icon(
                    imageVector = Icons.Default.Share,
                    contentDescription = "Export GPX",
                    tint = MaterialTheme.colorScheme.primary,
                )
            }

            IconButton(onClick = onDelete) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                )
            }
        }
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
