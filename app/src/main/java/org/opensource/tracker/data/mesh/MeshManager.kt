package org.opensource.tracker.data.mesh

import android.content.Context
import android.net.wifi.WifiManager
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import org.opensource.tracker.domain.turnback.TurnBackEngine
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

/** Everything the UI needs to know about the current group session. */
data class MeshUiState(
    val active: Boolean = false,
    val config: MeshSessionConfig? = null,
    val publicEndpoint: StunEndpoint? = null,
    val localPeerId: String = "",
    val username: String = "Rider",
    val colorValue: Int = 0xFFFF5722.toInt(),
    val teammates: List<Teammate> = emptyList(),
    val sharedWaypoints: List<SharedWaypoint> = emptyList(),
    val gapThresholdMeters: Double = 400.0,
) {
    val activeTeammateCount: Int get() = teammates.count { it.isActive() }

    /** Active teammates with a fix who are further away than the gap threshold (and only once we have a fix too). */
    fun droppedTeammates(hasOwnFix: Boolean): List<Teammate> =
        if (!hasOwnFix) {
            emptyList()
        } else {
            teammates.filter { it.isActive() && it.hasFix && it.distanceToUserMeters > gapThresholdMeters }
        }
}

/** One immutable GPS fix, published atomically so a packet never mixes latitude and longitude from different fixes. */
private class LocalFix(
    val lat: Double,
    val lng: Double,
    val speedKmh: Double,
    val altitude: Double,
    val atMs: Long,
)

/**
 * Serverless, end-to-end encrypted peer-to-peer group tracking over a UDP mesh (LAN / hotspot broadcast,
 * plus unicast to known peers and STUN-assisted hole punching for peers on other networks).
 *
 * Wire-compatible with the Flutter build: same packet types (`telem`, `ping`, `wpt_add`, `wpt_del`),
 * same AES-256-GCM envelope ([MeshCrypto]) and same `turnback://mesh` invite links. Telemetry additionally
 * carries a per-sender `seq` (older peers simply omit it and are ordered by their timestamp instead).
 */
class MeshManager(
    context: Context,
) {
    private val appContext = context.applicationContext

    // Network input is untrusted: a bad packet or a socket error must never crash the app process.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + CoroutineExceptionHandler { _, _ -> })
    private val lock = Any()

    /** Serializes start / join / leave so a Leave can never interleave with a half-opened session. */
    private val sessionMutex = Mutex()

    private val _state = MutableStateFlow(MeshUiState())
    val state: StateFlow<MeshUiState> = _state.asStateFlow()

    private val _pings = MutableSharedFlow<MeshPing>(extraBufferCapacity = 8)
    val pings: SharedFlow<MeshPing> = _pings.asSharedFlow()

    /** An invite opened from a link/QR before the user chose to join; the UI confirms it. */
    private val _pendingInvite = MutableStateFlow<MeshSessionConfig?>(null)
    val pendingInvite: StateFlow<MeshSessionConfig?> = _pendingInvite.asStateFlow()

    @Volatile
    private var socket: DatagramSocket? = null
    private var receiveJob: Job? = null
    private var timerJob: Job? = null
    private var discoveryJob: Job? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    private val teammates = mutableMapOf<String, Teammate>()
    private val sharedWaypoints = mutableMapOf<String, SharedWaypoint>()
    private val knownPeerEndpoints = mutableSetOf<String>() // "ip:port"

    // Replay protection (all under [lock]). A captured datagram still authenticates under GCM, so ordering and
    // freshness are enforced on top: telemetry must be newer than the last accepted from that peer, pings are
    // de-duplicated by id, and deleted pins are remembered so a replayed `wpt_add` can't resurrect them.
    private val lastTelemetryOrder = mutableMapOf<String, Long>()
    private val seenPingIds = LinkedHashSet<String>()
    private val deletedPinIds = LinkedHashSet<String>()

    private val telemetrySeq = AtomicLong(0)

    /** Our latest fix for *this* session (cleared on join/leave so an old private location is never sent as live). */
    @Volatile
    private var localFix: LocalFix? = null

    private var stunDeferred: CompletableDeferred<StunEndpoint?>? = null
    private var stunTransactionId: ByteArray? = null

    val isActive: Boolean get() = _state.value.active

    fun offerInvite(config: MeshSessionConfig?) {
        _pendingInvite.value = config
    }

    fun setGapThreshold(meters: Double) {
        synchronized(lock) { publish { it.copy(gapThresholdMeters = meters) } }
    }

    /** Starts hosting a new session; returns the config to share. */
    suspend fun startHost(
        sessionName: String,
        username: String,
        colorValue: Int,
    ): MeshSessionConfig =
        sessionMutex.withLock {
            teardown()
            val config =
                MeshSessionConfig(
                    sessionId = MeshCrypto.generateId(),
                    sessionKey = MeshCrypto.generateKey(),
                    sessionName = sessionName.ifBlank { "Group Ride" },
                    isHost = true,
                )
            open(config, username, colorValue)
            config
        }

    suspend fun join(
        config: MeshSessionConfig,
        username: String,
        colorValue: Int,
    ) {
        // Validate before touching the current session: a bad invite must not drop a working group, nor start a
        // heartbeat that throws on every packet.
        require(MeshCrypto.isValidKey(config.sessionKey)) { "This invite has an invalid session key" }
        sessionMutex.withLock {
            teardown()
            open(config, username, colorValue)
            val ip = config.publicIp
            val port = config.publicPort
            if (ip != null && port != null && isUsableEndpoint(ip, port)) {
                synchronized(lock) { knownPeerEndpoints.add("$ip:$port") }
                punch()
            }
            _pendingInvite.value = null
        }
    }

    suspend fun leave() = sessionMutex.withLock { teardown() }

    /** Installs a session. Callers hold [sessionMutex], so nothing can tear it down half-way. */
    private suspend fun open(
        config: MeshSessionConfig,
        username: String,
        colorValue: Int,
    ) = withContext(Dispatchers.IO) {
        val newSocket = bindSocket()
        acquireMulticastLock()
        synchronized(lock) {
            socket = newSocket
            resetSessionState()
            _state.value =
                MeshUiState(
                    active = true,
                    config = config,
                    localPeerId = MeshCrypto.generateId().substring(0, 8),
                    username = username.ifBlank { "Rider" },
                    colorValue = colorValue,
                    gapThresholdMeters = _state.value.gapThresholdMeters,
                )
        }
        receiveJob = scope.launch { receiveLoop(newSocket) }
        timerJob = scope.launch { heartbeatLoop() }
        // Discovery is bound to this socket (= this session) and cancelled on leave.
        discoveryJob = scope.launch { discoverPublicEndpoint(newSocket) }
    }

    /** Callers hold [sessionMutex]. */
    private suspend fun teardown() =
        withContext(Dispatchers.IO) {
            timerJob?.cancel()
            receiveJob?.cancel()
            discoveryJob?.cancel()
            timerJob = null
            receiveJob = null
            discoveryJob = null
            var old: DatagramSocket? = null
            synchronized(lock) {
                old = socket
                socket = null
                resetSessionState()
                stunDeferred = null
                stunTransactionId = null
                _state.value = MeshUiState(gapThresholdMeters = _state.value.gapThresholdMeters)
            }
            runCatching { old?.close() } // unblocks the blocking receive()
            releaseMulticastLock()
        }

    private fun resetSessionState() {
        teammates.clear()
        sharedWaypoints.clear()
        knownPeerEndpoints.clear()
        lastTelemetryOrder.clear()
        seenPingIds.clear()
        deletedPinIds.clear()
        localFix = null
    }

    /** Scanning a teammate's QR from the same session opens a return path through their NAT. */
    fun addPeerFromConfig(config: MeshSessionConfig): Boolean {
        val current = _state.value.config ?: return false
        if (!_state.value.active || config.sessionId != current.sessionId) return false
        val ip = config.publicIp ?: return false
        val port = config.publicPort ?: return false
        if (!isUsableEndpoint(ip, port)) return false
        synchronized(lock) { knownPeerEndpoints.add("$ip:$port") }
        punch()
        return true
    }

    fun updateLocalPosition(
        lat: Double,
        lng: Double,
        speedKmh: Double,
        altitude: Double,
    ) {
        localFix = LocalFix(lat, lng, speedKmh, altitude, System.currentTimeMillis())
        if (!_state.value.active) return
        synchronized(lock) { recalculateDistances() }
        scope.launch { broadcastTelemetry() }
    }

    fun sendPing(
        type: PingType,
        customText: String? = null,
    ) {
        val s = _state.value
        val config = s.config ?: return
        if (!s.active) return
        val ping =
            MeshPing(
                id = MeshCrypto.generateId().substring(0, 8),
                type = type,
                senderId = s.localPeerId,
                senderName = s.username,
                senderColor = s.colorValue,
                timestamp = System.currentTimeMillis(),
                customText = customText,
            )
        scope.launch {
            send(packet("ping", config).put("ping", ping.toJson()))
        }
    }

    fun addSharedWaypoint(
        name: String,
        lat: Double,
        lng: Double,
    ) {
        val s = _state.value
        val config = s.config ?: return
        if (!s.active) return
        val waypoint =
            SharedWaypoint(
                id = MeshCrypto.generateId().substring(0, 8),
                name = name.ifBlank { "Shared pin" },
                lat = lat,
                lng = lng,
                creatorId = s.localPeerId,
                creatorName = s.username,
                colorValue = s.colorValue,
                timestamp = System.currentTimeMillis(),
            )
        synchronized(lock) {
            sharedWaypoints[waypoint.id] = waypoint
            publishWaypoints()
        }
        scope.launch {
            send(packet("wpt_add", config).put("wpt", waypoint.toJson()))
        }
    }

    fun removeSharedWaypoint(id: String) {
        val config = _state.value.config ?: return
        synchronized(lock) {
            remember(deletedPinIds, id, MAX_TOMBSTONES)
            sharedWaypoints.remove(id)
            publishWaypoints()
        }
        scope.launch {
            send(packet("wpt_del", config).put("wid", id))
        }
    }

    // ---------------------------------------------------------------- networking

    /** Base envelope shared by every packet type. */
    private fun packet(
        type: String,
        config: MeshSessionConfig,
    ): JSONObject {
        val json = JSONObject()
        json.put("v", 1)
        json.put("t", type)
        json.put("sid", config.sessionId)
        return json
    }

    private fun bindSocket(): DatagramSocket {
        fun bind(port: Int) =
            DatagramSocket(null).apply {
                reuseAddress = true
                broadcast = true
                bind(InetSocketAddress(port))
            }
        return try {
            bind(DEFAULT_PORT)
        } catch (_: Exception) {
            bind(0) // port busy: still works for unicast / outbound broadcast
        }
    }

    private fun receiveLoop(sock: DatagramSocket) {
        val buffer = ByteArray(8192)
        while (!sock.isClosed) {
            try {
                val packet = DatagramPacket(buffer, buffer.size)
                sock.receive(packet)
                handleDatagram(sock, packet.data, packet.length, packet.address.hostAddress.orEmpty(), packet.port)
            } catch (_: Exception) {
                if (sock.isClosed) break
            }
        }
    }

    private suspend fun heartbeatLoop() {
        var ticks = 0
        while (scope.isActive) {
            broadcastTelemetry()
            delay(HEARTBEAT_MS)
            ticks++
            if (ticks % 5 == 0) synchronized(lock) { pruneStale() }
        }
    }

    private fun punch() {
        scope.launch {
            repeat(3) {
                broadcastTelemetry()
                delay(80L)
            }
        }
    }

    /**
     * Asks a STUN server for our public endpoint *through [sock]* (so the NAT mapping is the one the mesh uses).
     * Everything is checked against [sock] under the lock: if the session was left or replaced meanwhile, the
     * result is dropped and the new session's pending transaction is left untouched.
     */
    private suspend fun discoverPublicEndpoint(sock: DatagramSocket) {
        for (host in listOf(MeshStun.PRIMARY_SERVER, MeshStun.FALLBACK_SERVER)) {
            if (socket !== sock) return
            val deferred = CompletableDeferred<StunEndpoint?>()
            try {
                val address = InetAddress.getAllByName(host).filterIsInstance<Inet4Address>().firstOrNull() ?: continue
                val request = MeshStun.buildBindingRequest()
                synchronized(lock) {
                    if (socket !== sock) return
                    stunTransactionId = MeshStun.transactionId(request)
                    stunDeferred = deferred
                }
                sock.send(DatagramPacket(request, request.size, address, MeshStun.DEFAULT_PORT))
                val endpoint = withTimeoutOrNull(STUN_TIMEOUT_MS) { deferred.await() }
                if (endpoint != null) {
                    val stillCurrent =
                        synchronized(lock) {
                            if (socket === sock) {
                                publish { s -> s.copy(publicEndpoint = endpoint, config = s.config?.copy(publicIp = endpoint.ip, publicPort = endpoint.port)) }
                                true
                            } else {
                                false
                            }
                        }
                    if (stillCurrent) broadcastTelemetry()
                    return
                }
            } catch (_: Exception) {
                // try the fallback server
            } finally {
                synchronized(lock) {
                    if (stunDeferred === deferred) {
                        stunDeferred = null
                        stunTransactionId = null
                    }
                }
            }
        }
    }

    /**
     * Handles one datagram received on [sock]. Every state change re-checks `socket === sock` under the lock, so a
     * handler that was already running when the user left this group can never write into the next one.
     */
    private fun handleDatagram(
        sock: DatagramSocket,
        data: ByteArray,
        length: Int,
        senderIp: String,
        senderPort: Int,
    ) {
        val deferred = stunDeferred
        val txId = stunTransactionId
        if (deferred != null && txId != null && MeshStun.isStunPacket(data, length)) {
            MeshStun.parseBindingResponse(data, length, txId)?.let { deferred.complete(it) }
            return
        }

        val config = _state.value.config ?: return
        try {
            val plain = MeshCrypto.decrypt(String(data, 0, length, Charsets.UTF_8), config.sessionKey) ?: return
            val json = JSONObject(plain)
            if (json.optString("sid") != config.sessionId) return

            val senderEndpoint = "$senderIp:$senderPort"
            when (json.optString("t", "telem")) {
                "ping" -> {
                    val ping = json.optJSONObject("ping")?.let { MeshPing.fromJson(it) } ?: return
                    val accepted =
                        synchronized(lock) {
                            socket === sock && remember(seenPingIds, ping.id, MAX_REMEMBERED_IDS) && isFresh(ping.timestamp)
                        }
                    if (accepted) {
                        admit(sock, senderEndpoint, json)
                        if (ping.senderId != _state.value.localPeerId) _pings.tryEmit(ping)
                    }
                }

                "wpt_add" -> {
                    val waypoint = json.optJSONObject("wpt")?.let { SharedWaypoint.fromJson(it) } ?: return
                    val accepted =
                        synchronized(lock) {
                            // A deleted pin stays deleted even if an old `wpt_add` is replayed at us.
                            if (socket === sock && waypoint.id !in deletedPinIds) {
                                sharedWaypoints[waypoint.id] = waypoint
                                publishWaypoints()
                                true
                            } else {
                                false
                            }
                        }
                    if (accepted) admit(sock, senderEndpoint, json)
                }

                "wpt_del" -> {
                    val id = json.optString("wid", "")
                    if (id.isNotEmpty()) {
                        val accepted =
                            synchronized(lock) {
                                if (socket === sock) {
                                    remember(deletedPinIds, id, MAX_TOMBSTONES)
                                    sharedWaypoints.remove(id)
                                    publishWaypoints()
                                    true
                                } else {
                                    false
                                }
                            }
                        if (accepted) admit(sock, senderEndpoint, json)
                    }
                }

                else -> handleTelemetry(sock, json, senderEndpoint)
            }
        } catch (_: Exception) {
            // malformed packet from the network: ignore
        }
    }

    /**
     * Registers an authenticated sender as a unicast target. Called only *after* a packet passed its replay checks,
     * so a replayed datagram can't make us start sending to the replayer's address. Returns true for a new endpoint.
     */
    private fun admit(
        sock: DatagramSocket,
        senderEndpoint: String,
        json: JSONObject,
    ): Boolean {
        var isNew = false
        var punchAdvertised = false
        synchronized(lock) {
            if (socket !== sock) return false
            isNew = knownPeerEndpoints.add(senderEndpoint)
            // A peer advertising its public endpoint (e.g. a joiner on mobile data): send to it too, which opens
            // our NAT towards it and makes the tunnel two-way.
            val pip = json.optString("pip", "")
            val pport = json.optInt("pport", -1)
            if (isUsableEndpoint(pip, pport) && "$pip:$pport" != senderEndpoint && knownPeerEndpoints.add("$pip:$pport")) {
                punchAdvertised = true
            }
        }
        if (punchAdvertised) punch()
        return isNew
    }

    private fun handleTelemetry(
        sock: DatagramSocket,
        json: JSONObject,
        senderEndpoint: String,
    ) {
        val peerId = json.optString("id", "")
        if (peerId.isEmpty() || peerId == _state.value.localPeerId) return
        val lat = json.optDouble("lat", 0.0)
        val lng = json.optDouble("lng", 0.0)
        val timestamp = json.optLong("ts", 0L)
        // Ordering uses the sender's sequence number when present (immune to clock jumps); older peers that don't
        // send one are ordered by their timestamp instead. Freshness always uses the timestamp.
        val order = if (json.has("seq")) json.optLong("seq", Long.MIN_VALUE) else timestamp
        var newcomer = false
        synchronized(lock) {
            if (socket !== sock) return
            // Replay protection: a captured packet still authenticates, so require it to be recent AND newer than
            // the last one accepted from this peer. Otherwise an observer could pin a teammate "online" forever.
            if (!isFresh(timestamp) || order <= (lastTelemetryOrder[peerId] ?: Long.MIN_VALUE)) return
            lastTelemetryOrder[peerId] = order

            val existing = teammates[peerId]
            if (existing == null) newcomer = true
            var trail = existing?.trail ?: emptyList()
            if (lat != 0.0 || lng != 0.0) {
                trail = (trail + TrailPoint(lat, lng)).takeLast(Teammate.MAX_TRAIL_POINTS)
            }
            teammates[peerId] =
                Teammate(
                    peerId = peerId,
                    username = json.optString("user", "Rider"),
                    colorValue = json.optLong("color", 0xFF10B981L).toInt(),
                    lat = lat,
                    lng = lng,
                    speedKmh = json.optDouble("spd", 0.0),
                    altitude = json.optDouble("alt", 0.0),
                    lastSeenMs = System.currentTimeMillis(),
                    trail = trail,
                    distanceToUserMeters = distanceFromUser(lat, lng),
                )
            publishTeammates()
        }
        // Only now that the packet is known to be fresh do we remember where it came from.
        val newEndpoint = admit(sock, senderEndpoint, json)

        // Acknowledge a newcomer immediately, and hand it the pin state (pins are otherwise only sent once, at
        // creation, and deletions only once, at deletion).
        if (newcomer || newEndpoint) {
            scope.launch {
                broadcastTelemetry()
                resendPinState()
            }
        }
    }

    /** Re-sends every live pin, and every remembered deletion, so a late joiner or returning peer converges. */
    private suspend fun resendPinState() {
        val config = _state.value.config ?: return
        val (pins, deleted) = synchronized(lock) { sharedWaypoints.values.toList() to deletedPinIds.toList() }
        for (pin in pins) send(packet("wpt_add", config).put("wpt", pin.toJson()))
        for (id in deleted) send(packet("wpt_del", config).put("wid", id))
    }

    /** Within the allowed clock skew (phones are NTP-synced; this only rejects very old or far-future packets). */
    private fun isFresh(timestampMs: Long): Boolean = abs(System.currentTimeMillis() - timestampMs) <= MAX_PACKET_SKEW_MS

    /** Adds [id] to a bounded memory set; returns false if it was already there. */
    private fun remember(
        set: MutableSet<String>,
        id: String,
        capacity: Int,
    ): Boolean {
        val added = set.add(id)
        if (set.size > capacity) set.remove(set.first())
        return added
    }

    private suspend fun broadcastTelemetry() {
        val s = _state.value
        val config = s.config ?: return
        if (!s.active) return
        // Only a fix obtained during this session and still recent goes out as "live". Otherwise we send 0,0 ("no
        // fix yet"), which peers already understand: an old private location must never be presented as current.
        val now = System.currentTimeMillis()
        val fix = localFix?.takeIf { now - it.atMs <= FIX_FRESH_MS }
        val packet = packet("telem", config)
        packet.put("id", s.localPeerId)
        packet.put("user", s.username)
        packet.put("color", s.colorValue.toLong() and 0xFFFFFFFFL)
        packet.put("lat", fix?.lat ?: 0.0)
        packet.put("lng", fix?.lng ?: 0.0)
        packet.put("spd", fix?.speedKmh ?: 0.0)
        packet.put("alt", fix?.altitude ?: 0.0)
        packet.put("ts", now)
        packet.put("seq", telemetrySeq.incrementAndGet())
        s.publicEndpoint?.let { packet.put("pip", it.ip).put("pport", it.port) }
        send(packet)
    }

    /** Encrypts and sends to the subnet broadcast addresses and every known peer endpoint. */
    private suspend fun send(packet: JSONObject) =
        withContext(Dispatchers.IO) {
            val sock = socket ?: return@withContext
            val config = _state.value.config ?: return@withContext
            val bytes = MeshCrypto.encrypt(packet.toString(), config.sessionKey).toByteArray(Charsets.UTF_8)

            fun sendTo(
                address: InetAddress,
                port: Int,
            ) {
                try {
                    sock.send(DatagramPacket(bytes, bytes.size, address, port))
                } catch (_: Exception) {
                    // unreachable network: ignore
                }
            }

            sendTo(InetAddress.getByName("255.255.255.255"), DEFAULT_PORT)
            runCatching {
                NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().filter { it.isUp && !it.isLoopback }.forEach { iface ->
                    iface.interfaceAddresses.mapNotNull { it.broadcast }.forEach { sendTo(it, DEFAULT_PORT) }
                }
            }
            val peers = synchronized(lock) { knownPeerEndpoints.toList() }
            for (endpoint in peers) {
                val parts = endpoint.split(":")
                if (parts.size != 2) continue
                val port = parts[1].toIntOrNull() ?: DEFAULT_PORT
                runCatching { InetAddress.getByName(parts[0]) }.getOrNull()?.let { sendTo(it, port) }
            }
        }

    // ---------------------------------------------------------------- state helpers (call under lock)

    private fun distanceFromUser(
        lat: Double,
        lng: Double,
    ): Double {
        val fix = localFix // read once: lat and lng always come from the same fix
        return if (fix == null || (fix.lat == 0.0 && fix.lng == 0.0) || (lat == 0.0 && lng == 0.0)) {
            0.0
        } else {
            TurnBackEngine.haversineDistanceMeters(fix.lat, fix.lng, lat, lng)
        }
    }

    private fun recalculateDistances() {
        if (teammates.isEmpty()) return
        for ((id, t) in teammates.toMap()) {
            teammates[id] = t.copy(distanceToUserMeters = distanceFromUser(t.lat, t.lng))
        }
        publishTeammates()
    }

    private fun pruneStale() {
        val now = System.currentTimeMillis()
        if (teammates.values.removeAll { now - it.lastSeenMs > Teammate.PRUNE_AFTER_MS }) publishTeammates()
    }

    private fun publishTeammates() = publish { it.copy(teammates = teammates.values.sortedBy { t -> t.username }) }

    private fun publishWaypoints() = publish { it.copy(sharedWaypoints = sharedWaypoints.values.sortedBy { w -> w.timestamp }) }

    private fun publish(transform: (MeshUiState) -> MeshUiState) {
        _state.value = transform(_state.value)
    }

    // ---------------------------------------------------------------- Wi-Fi multicast / broadcast reception

    private fun acquireMulticastLock() {
        // Some devices drop inbound broadcast/multicast UDP while the screen is off unless this is held.
        runCatching {
            val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock =
                wifi?.createMulticastLock("turnback-mesh")?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
    }

    private fun releaseMulticastLock() {
        runCatching { if (multicastLock?.isHeld == true) multicastLock?.release() }
        multicastLock = null
    }

    companion object {
        const val DEFAULT_PORT = 42424
        private const val HEARTBEAT_MS = 3_000L
        private const val STUN_TIMEOUT_MS = 4_000L
        private const val MAX_PACKET_SKEW_MS = 5 * 60_000L
        private const val FIX_FRESH_MS = 90_000L
        private const val MAX_REMEMBERED_IDS = 256
        private const val MAX_TOMBSTONES = 1024

        private val IPV4_LITERAL = Regex("""^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$""")

        /** A concrete peer address: an IPv4 literal (never a hostname, so no DNS lookups) and a real UDP port. */
        internal fun isUsableEndpoint(
            ip: String,
            port: Int,
        ): Boolean {
            if (port !in 1..65535) return false
            val match = IPV4_LITERAL.matchEntire(ip) ?: return false
            return match.groupValues.drop(1).all { it.toInt() in 0..255 }
        }
    }
}
