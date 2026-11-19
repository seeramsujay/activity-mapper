package org.opensource.tracker.ui.mesh

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.launch
import org.opensource.tracker.data.mesh.MeshManager
import org.opensource.tracker.data.mesh.MeshSessionConfig
import org.opensource.tracker.data.mesh.MeshUiState
import org.opensource.tracker.data.mesh.PingType
import org.opensource.tracker.data.mesh.Teammate
import org.opensource.tracker.data.settings.AppSettings
import org.opensource.tracker.ui.util.UnitFormat

private val RIDER_COLORS =
    listOf(
        0xFFFF5722.toInt(),
        0xFF3B82F6.toInt(),
        0xFF10B981.toInt(),
        0xFFEAB308.toInt(),
        0xFF8B5CF6.toInt(),
        0xFFEC4899.toInt(),
        0xFF06B6D4.toInt(),
        0xFFEF4444.toInt(),
    )

/**
 * Group tracking sheet: host or join a session, share the invite (link / QR), see teammates,
 * send one-tap pings and drop pins that appear on everyone's map.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GroupSheet(
    mesh: MeshManager,
    state: MeshUiState,
    pendingInvite: MeshSessionConfig?,
    ownLat: Double?,
    ownLng: Double?,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings = remember { AppSettings.getInstance(context) }
    val imperial = remember { settings.useImperialUnits }

    var username by remember { mutableStateOf(settings.meshUsername) }
    var color by remember { mutableStateOf(settings.meshColor) }
    var sessionName by remember { mutableStateOf("") }
    var joinLink by remember { mutableStateOf("") }
    var pinName by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    fun toast(message: String) = Toast.makeText(context, message, Toast.LENGTH_SHORT).show()

    fun saveProfile() {
        settings.meshUsername = username.trim()
        settings.meshColor = color
    }

    fun joinWith(config: MeshSessionConfig) {
        if (busy) return
        saveProfile()
        scope.launch {
            busy = true
            try {
                mesh.join(config, username.trim().ifBlank { "Rider" }, color)
            } catch (e: Exception) {
                toast("Couldn't join: ${e.message ?: "network error"}")
            }
            busy = false
        }
    }

    val scanLauncher =
        rememberLauncherForActivityResult(ScanContract()) { result ->
            val text = result.contents ?: return@rememberLauncherForActivityResult
            val config = MeshSessionConfig.fromUri(text)
            when {
                config == null -> toast("That's not a TurnBack group code")
                state.active ->
                    if (mesh.addPeerFromConfig(config)) {
                        toast("Linked to teammate")
                    } else {
                        toast("That code is for a different session or has no network address yet")
                    }
                else -> joinWith(config)
            }
        }

    fun scan() =
        scanLauncher.launch(
            ScanOptions()
                .setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                .setPrompt("Scan a TurnBack group code")
                .setBeepEnabled(false)
                .setOrientationLocked(false),
        )

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Group tracking", fontSize = 22.sp, fontWeight = FontWeight.Black)
            Text(
                "See your group live on the map, with no account and no server. Everything is end-to-end encrypted " +
                    "and works over the same Wi-Fi / phone hotspot, or across networks via the invite link.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (!state.active) {
                if (pendingInvite != null) {
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Invitation: ${pendingInvite.sessionName}", fontWeight = FontWeight.Bold)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = { joinWith(pendingInvite) }, enabled = !busy) { Text("Join group") }
                                TextButton(onClick = { mesh.offerInvite(null) }) { Text("Decline") }
                            }
                        }
                    }
                }

                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it.take(24) },
                    label = { Text("Your name in the group") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    RIDER_COLORS.forEach { swatch ->
                        Box(
                            modifier =
                                Modifier
                                    .size(if (swatch == color) 34.dp else 28.dp)
                                    .background(Color(swatch), CircleShape)
                                    .clickable { color = swatch },
                        )
                    }
                }

                HorizontalDivider()
                Text("Start a group", fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = sessionName,
                    onValueChange = { sessionName = it.take(40) },
                    label = { Text("Group name (optional)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        saveProfile()
                        scope.launch {
                            busy = true
                            try {
                                mesh.startHost(sessionName, username.trim().ifBlank { "Rider" }, color)
                            } catch (e: Exception) {
                                toast("Couldn't start group: ${e.message ?: "network error"}")
                            }
                            busy = false
                        }
                    },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                ) {
                    Text("Host a group", fontWeight = FontWeight.Bold)
                }

                HorizontalDivider()
                Text("Join a group", fontWeight = FontWeight.Bold)
                OutlinedButton(onClick = { scan() }, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Scan group QR code")
                }
                OutlinedTextField(
                    value = joinLink,
                    onValueChange = { joinLink = it },
                    label = { Text("…or paste an invite link") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                FilledTonalButton(
                    onClick = {
                        val config = MeshSessionConfig.fromUri(joinLink)
                        if (config == null) toast("That doesn't look like a TurnBack invite link") else joinWith(config)
                    },
                    enabled = joinLink.isNotBlank() && !busy,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Join with link")
                }
            } else {
                val config = state.config
                if (config != null) {
                    ActiveSessionHeader(state, config, context) { scan() }
                }

                HorizontalDivider()
                Text("Quick message to the group", fontWeight = FontWeight.Bold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    PingType.entries.forEach { type ->
                        FilledTonalButton(onClick = {
                            mesh.sendPing(type)
                            toast("Sent: ${type.title}")
                        }) {
                            Text("${type.emoji} ${type.title}", fontSize = 13.sp)
                        }
                    }
                }

                HorizontalDivider()
                Text("Riders (${state.activeTeammateCount} online)", fontWeight = FontWeight.Bold)
                if (state.teammates.isEmpty()) {
                    Text(
                        "Nobody else yet. Share the QR code or link, and start recording so they can see you.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                state.teammates.forEach { TeammateRow(it, imperial) }

                HorizontalDivider()
                Text("Shared pins", fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = pinName,
                        onValueChange = { pinName = it.take(32) },
                        label = { Text("Pin name") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    Button(
                        enabled = ownLat != null && ownLng != null,
                        onClick = {
                            if (ownLat != null && ownLng != null) {
                                mesh.addSharedWaypoint(pinName, ownLat, ownLng)
                                pinName = ""
                            }
                        },
                    ) {
                        Text("Drop here")
                    }
                }
                if (ownLat == null) {
                    Text(
                        "Waiting for your GPS position…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                state.sharedWaypoints.forEach { pin ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(12.dp).background(Color(pin.colorValue), CircleShape))
                        Spacer(Modifier.width(8.dp))
                        Text("${pin.name} • ${pin.creatorName}", Modifier.weight(1f))
                        IconButton(onClick = { mesh.removeSharedWaypoint(pin.id) }) {
                            Icon(Icons.Default.Delete, contentDescription = "Remove pin")
                        }
                    }
                }

                HorizontalDivider()
                Text(
                    "Gap alert: warn me when a rider is more than " +
                        UnitFormat.distance(state.gapThresholdMeters / 1000.0, imperial) + " away",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Slider(
                    value = state.gapThresholdMeters.toFloat(),
                    onValueChange = { mesh.setGapThreshold(((it / 50f).toInt() * 50).toDouble()) },
                    valueRange = 100f..2000f,
                )

                OutlinedButton(
                    onClick = { scope.launch { mesh.leave() } },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Leave group", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

@Composable
private fun ActiveSessionHeader(
    state: MeshUiState,
    config: MeshSessionConfig,
    context: Context,
    onScan: () -> Unit,
) {
    val link = config.toUri()
    Card(shape = RoundedCornerShape(16.dp)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(config.sessionName, fontWeight = FontWeight.Black, fontSize = 18.sp)
            Text(
                "You are ${state.username}" + if (config.isHost) " (host)" else "",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                QrCode(content = link, modifier = Modifier.size(220.dp))
            }
            Text(
                if (state.publicEndpoint != null) {
                    "Reachable across networks. Others can join by scanning this."
                } else {
                    "Same Wi-Fi / hotspot works now. Looking for a network address for remote riders…"
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(onClick = {
                    val send =
                        Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, "Join my TurnBack group \"${config.sessionName}\": $link")
                        }
                    context.startActivity(Intent.createChooser(send, "Share group invite"))
                }) {
                    Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Share link")
                }
                OutlinedButton(onClick = {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("TurnBack group link", link))
                    Toast.makeText(context, "Link copied", Toast.LENGTH_SHORT).show()
                }) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Copy")
                }
            }
            OutlinedButton(onClick = onScan, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.QrCodeScanner, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Scan a teammate's code (links networks)")
            }
            Text(
                "Anyone holding this link or QR can join and see the group. Share it only with people you trust.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@Composable
private fun TeammateRow(
    teammate: Teammate,
    imperial: Boolean,
) {
    val now = System.currentTimeMillis()
    val detail =
        when {
            !teammate.isActive(now) -> "offline • last seen ${(now - teammate.lastSeenMs) / 1000}s ago"
            !teammate.hasFix -> "no GPS fix yet"
            else ->
                UnitFormat.distance(teammate.distanceToUserMeters / 1000.0, imperial) + " away • " +
                    UnitFormat.speed(teammate.speedKmh, imperial)
        }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(14.dp).background(Color(teammate.colorValue), CircleShape))
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(teammate.username, fontWeight = FontWeight.Bold)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
