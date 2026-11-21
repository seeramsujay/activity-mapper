package org.opensource.tracker

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.opensource.tracker.data.mesh.MeshCrypto
import org.opensource.tracker.data.mesh.MeshManager
import org.opensource.tracker.data.mesh.MeshPing
import org.opensource.tracker.data.mesh.MeshSessionConfig
import org.opensource.tracker.data.mesh.MeshStun
import org.opensource.tracker.data.mesh.PingType
import org.opensource.tracker.data.mesh.SharedWaypoint
import org.opensource.tracker.data.mesh.Teammate
import java.util.Base64

class MeshProtocolTest {
    @Test
    fun `encrypt then decrypt round-trips`() {
        val key = MeshCrypto.generateKey()
        val plain = """{"t":"telem","lat":12.34,"user":"Zoë 🚴"}"""
        assertEquals(plain, MeshCrypto.decrypt(MeshCrypto.encrypt(plain, key), key))
    }

    @Test
    fun `wrong key cannot decrypt`() {
        val encrypted = MeshCrypto.encrypt("secret", MeshCrypto.generateKey())
        assertNull(MeshCrypto.decrypt(encrypted, MeshCrypto.generateKey()))
    }

    @Test
    fun `tampered packet is rejected by the GCM tag`() {
        val key = MeshCrypto.generateKey()
        val bytes = Base64.getUrlDecoder().decode(MeshCrypto.encrypt("hello group", key))
        bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 0x01).toByte()
        assertNull(MeshCrypto.decrypt(Base64.getUrlEncoder().encodeToString(bytes), key))
    }

    @Test
    fun `identical payloads never produce identical ciphertexts`() {
        val key = MeshCrypto.generateKey()
        assertNotEquals(MeshCrypto.encrypt("same", key), MeshCrypto.encrypt("same", key))
    }

    @Test
    fun `wire format is version, 12-byte nonce, ciphertext and 16-byte tag`() {
        val key = MeshCrypto.generateKey()
        val bytes = Base64.getUrlDecoder().decode(MeshCrypto.encrypt("abc", key))
        assertEquals(1.toByte(), bytes[0])
        assertEquals(1 + 12 + 3 + 16, bytes.size)
    }

    @Test
    fun `garbage and short input decrypt to null instead of throwing`() {
        val key = MeshCrypto.generateKey()
        assertNull(MeshCrypto.decrypt("not base64 !!!", key))
        assertNull(MeshCrypto.decrypt("AQID", key))
        assertNull(MeshCrypto.decrypt("", key))
    }

    @Test
    fun `generated key is 256 bits and ids are unique hex`() {
        assertEquals(32, Base64.getUrlDecoder().decode(MeshCrypto.generateKey()).size)
        val a = MeshCrypto.generateId()
        assertEquals(32, a.length)
        assertTrue(a.all { it in "0123456789abcdef" })
        assertNotEquals(a, MeshCrypto.generateId())
    }

    @Test
    fun `invite link round-trips including special characters and public endpoint`() {
        val config =
            MeshSessionConfig(
                sessionId = MeshCrypto.generateId(),
                sessionKey = MeshCrypto.generateKey(),
                sessionName = "Sunday ride & coffee ☕",
                publicIp = "203.0.113.9",
                publicPort = 54321,
            )
        val parsed = MeshSessionConfig.fromUri(config.toUri())
        assertNotNull(parsed)
        assertEquals(config.sessionId, parsed!!.sessionId)
        assertEquals(config.sessionKey, parsed.sessionKey)
        assertEquals(config.sessionName, parsed.sessionName)
        assertEquals("203.0.113.9", parsed.publicIp)
        assertEquals(54321, parsed.publicPort)
        assertFalse(parsed.isHost)
    }

    @Test
    fun `legacy activitymapper scheme is accepted and foreign links are rejected`() {
        val key = MeshCrypto.generateKey()
        assertNotNull(MeshSessionConfig.fromUri("activitymapper://mesh?id=a&key=$key"))
        assertNull(MeshSessionConfig.fromUri("https://example.com/mesh?id=a&key=$key"))
        assertNull(MeshSessionConfig.fromUri("turnback://other?id=a&key=$key"))
        assertNull(MeshSessionConfig.fromUri("turnback://mesh?id=a"))
        assertNull(MeshSessionConfig.fromUri("turnback://mesh?id=&key=$key"))
        assertNull(MeshSessionConfig.fromUri("not a url at all"))
    }

    @Test
    fun `invite with an unusable session key is rejected at parse time`() {
        assertNull(MeshSessionConfig.fromUri("turnback://mesh?id=a&key=b"))
        assertNull(MeshSessionConfig.fromUri("turnback://mesh?id=a&key=!!!notbase64"))
        // valid Base64 but only 16 bytes: not an AES-256 key
        val shortKey = Base64.getUrlEncoder().encodeToString(ByteArray(16))
        assertNull(MeshSessionConfig.fromUri("turnback://mesh?id=a&key=$shortKey"))
    }

    @Test
    fun `key validation accepts exactly 256-bit keys`() {
        assertTrue(MeshCrypto.isValidKey(MeshCrypto.generateKey()))
        assertFalse(MeshCrypto.isValidKey(""))
        assertFalse(MeshCrypto.isValidKey("b"))
        assertFalse(MeshCrypto.isValidKey(Base64.getUrlEncoder().encodeToString(ByteArray(33))))
    }

    @Test
    fun `ping json uses lowercase type and survives a round trip with ARGB colour`() {
        val ping =
            MeshPing(
                id = "p1",
                type = PingType.SOS,
                senderId = "s1",
                senderName = "Sam",
                senderColor = 0xFFFF5722.toInt(),
                timestamp = 1_700_000_000_000L,
                customText = "flat tyre",
            )
        val json = ping.toJson()
        assertEquals("sos", json.getString("type"))
        assertEquals(0xFFFF5722L, json.getLong("color")) // unsigned, as the Flutter build sends it
        assertEquals(ping, MeshPing.fromJson(json))
    }

    @Test
    fun `unknown ping type falls back to regroup`() {
        val json = JSONObject()
        json.put("type", "teleport")
        json.put("id", "x")
        assertEquals(PingType.REGROUP, MeshPing.fromJson(json).type)
    }

    @Test
    fun `shared waypoint json round-trips`() {
        val pin = SharedWaypoint("w1", "Water tap", 51.5, -0.12, "c1", "Alex", 0xFF3B82F6.toInt(), 42L)
        assertEquals(pin, SharedWaypoint.fromJson(pin.toJson()))
    }

    @Test
    fun `stun binding request is well formed`() {
        val request = MeshStun.buildBindingRequest()
        assertEquals(20, request.size)
        assertTrue(MeshStun.isStunPacket(request))
        assertEquals(12, MeshStun.transactionId(request).size)
        assertFalse(MeshStun.isStunPacket(ByteArray(10)))
    }

    /** A complete, valid Binding Success Response (XOR-MAPPED-ADDRESS 203.0.113.9:54321) for [txId]. */
    private fun stunResponse(txId: ByteArray): ByteArray {
        val cookie = intArrayOf(0x21, 0x12, 0xA4, 0x42)
        val ip = intArrayOf(203, 0, 113, 9)
        val xorPort = 54321 xor 0x2112
        val value =
            byteArrayOf(0x00, 0x01, (xorPort shr 8).toByte(), xorPort.toByte()) +
                ByteArray(4) { (ip[it] xor cookie[it]).toByte() }
        val attribute = byteArrayOf(0x00, 0x20, 0x00, 0x08) + value
        val header = byteArrayOf(0x01, 0x01, 0x00, attribute.size.toByte(), 0x21, 0x12, 0xA4.toByte(), 0x42) + txId
        return header + attribute
    }

    @Test
    fun `stun xor-mapped-address response is decoded`() {
        val txId = ByteArray(12) { (it + 1).toByte() }
        val response = stunResponse(txId)

        val endpoint = MeshStun.parseBindingResponse(response, response.size, txId)
        assertEquals("203.0.113.9", endpoint?.ip)
        assertEquals(54321, endpoint?.port)
    }

    @Test
    fun `stun response is only accepted for the matching transaction id`() {
        val txId = ByteArray(12) { 1 }
        val response = stunResponse(txId)
        // Same, fully valid reply: decodes with the right id and is rejected with any other, so this really
        // exercises the transaction check (not just a missing attribute).
        assertNotNull(MeshStun.parseBindingResponse(response, response.size, txId))
        assertNull(MeshStun.parseBindingResponse(response, response.size, ByteArray(12) { 2 }))
    }

    @Test
    fun `endpoint validation accepts only ipv4 literals with a real udp port`() {
        assertTrue(MeshManager.isUsableEndpoint("203.0.113.9", 54321))
        assertTrue(MeshManager.isUsableEndpoint("192.168.43.1", 1))
        assertTrue(MeshManager.isUsableEndpoint("10.0.0.2", 65535))
        assertFalse(MeshManager.isUsableEndpoint("203.0.113.9", 0))
        assertFalse(MeshManager.isUsableEndpoint("203.0.113.9", 65536))
        assertFalse(MeshManager.isUsableEndpoint("203.0.113.9", -5))
        assertFalse(MeshManager.isUsableEndpoint("999.0.0.1", 4000))
        assertFalse(MeshManager.isUsableEndpoint("example.com", 4000))
        assertFalse(MeshManager.isUsableEndpoint("", 4000))
    }

    @Test
    fun `invite with an unusable endpoint stays joinable but drops the endpoint`() {
        val key = MeshCrypto.generateKey()
        val parsed = MeshSessionConfig.fromUri("turnback://mesh?id=a&key=$key&ip=203.0.113.9&port=65536")
        assertNotNull(parsed)
        assertNull(parsed!!.publicIp)
        assertNull(parsed.publicPort)

        val noPort = MeshSessionConfig.fromUri("turnback://mesh?id=a&key=$key&ip=203.0.113.9")
        assertNull(noPort!!.publicIp)
    }

    @Test
    fun `shared pins without real coordinates are rejected`() {
        val ok = JSONObject().put("id", "p1").put("lat", 51.5).put("lng", -0.1)
        assertNotNull(SharedWaypoint.fromJson(ok))

        // explicit (0, 0) is a legitimate place, a missing coordinate is not
        assertNotNull(SharedWaypoint.fromJson(JSONObject().put("id", "p2").put("lat", 0.0).put("lng", 0.0)))
        assertNull(SharedWaypoint.fromJson(JSONObject().put("id", "p3").put("lat", 51.5)))
        assertNull(SharedWaypoint.fromJson(JSONObject().put("id", "p4")))
        assertNull(SharedWaypoint.fromJson(JSONObject().put("id", "p5").put("lat", 91.0).put("lng", 0.0)))
        assertNull(SharedWaypoint.fromJson(JSONObject().put("id", "p6").put("lat", 0.0).put("lng", 181.0)))
        assertNull(SharedWaypoint.fromJson(JSONObject().put("lat", 1.0).put("lng", 1.0)))
    }

    @Test
    fun `teammate activity window and fix detection`() {
        val now = 1_000_000L
        val t = Teammate("p", "Alex", 0, 0.0, 0.0, 0.0, 0.0, lastSeenMs = now - 30_000)
        assertTrue(t.isActive(now))
        assertFalse(t.hasFix)
        assertFalse(t.copy(lastSeenMs = now - 61_000).isActive(now))
        assertTrue(t.copy(lat = 1.0).hasFix)
    }
}
