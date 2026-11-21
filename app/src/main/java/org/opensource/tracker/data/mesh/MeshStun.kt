package org.opensource.tracker.data.mesh

import java.security.SecureRandom

data class StunEndpoint(
    val ip: String,
    val port: Int,
)

/** Minimal RFC 5389 STUN client pieces: build a Binding Request, parse the Binding Success Response. */
object MeshStun {
    const val PRIMARY_SERVER = "stun.l.google.com"
    const val FALLBACK_SERVER = "stun1.l.google.com"
    const val DEFAULT_PORT = 19302
    private const val MAGIC_COOKIE = 0x2112A442
    private const val BINDING_REQUEST = 0x0001
    private const val BINDING_SUCCESS = 0x0101
    private const val ATTR_MAPPED_ADDRESS = 0x0001
    private const val ATTR_XOR_MAPPED_ADDRESS = 0x0020
    private val random = SecureRandom()

    /** 20-byte Binding Request; bytes 8..19 are the transaction id. */
    fun buildBindingRequest(): ByteArray {
        val buffer = ByteArray(20)
        buffer[0] = (BINDING_REQUEST shr 8).toByte()
        buffer[1] = BINDING_REQUEST.toByte()
        // bytes 2..3: message length 0
        buffer[4] = (MAGIC_COOKIE ushr 24).toByte()
        buffer[5] = (MAGIC_COOKIE ushr 16).toByte()
        buffer[6] = (MAGIC_COOKIE ushr 8).toByte()
        buffer[7] = MAGIC_COOKIE.toByte()
        val txId = ByteArray(12).also { random.nextBytes(it) }
        txId.copyInto(buffer, destinationOffset = 8)
        return buffer
    }

    fun transactionId(request: ByteArray): ByteArray = request.copyOfRange(8, 20)

    fun isStunPacket(
        data: ByteArray,
        length: Int = data.size,
    ): Boolean {
        if (length < 20) return false
        val cookie = u8(data, 4) shl 24 or (u8(data, 5) shl 16) or (u8(data, 6) shl 8) or u8(data, 7)
        return cookie == MAGIC_COOKIE
    }

    fun parseBindingResponse(
        data: ByteArray,
        length: Int,
        transactionId: ByteArray,
    ): StunEndpoint? {
        if (!isStunPacket(data, length)) return null
        if (((u8(data, 0) shl 8) or u8(data, 1)) != BINDING_SUCCESS) return null
        if (!data.copyOfRange(8, 20).contentEquals(transactionId)) return null

        val messageLength = (u8(data, 2) shl 8) or u8(data, 3)
        val end = minOf(length, 20 + messageLength)
        var offset = 20
        while (offset + 4 <= end) {
            val type = (u8(data, offset) shl 8) or u8(data, offset + 1)
            val attrLength = (u8(data, offset + 2) shl 8) or u8(data, offset + 3)
            val valueStart = offset + 4
            if (valueStart + attrLength > end) return null
            val isXor = type == ATTR_XOR_MAPPED_ADDRESS
            if ((isXor || type == ATTR_MAPPED_ADDRESS) && attrLength >= 8 && u8(data, valueStart + 1) == 0x01) {
                var port = (u8(data, valueStart + 2) shl 8) or u8(data, valueStart + 3)
                val ip = IntArray(4) { u8(data, valueStart + 4 + it) }
                if (isXor) {
                    port = port xor (MAGIC_COOKIE ushr 16 and 0xFFFF)
                    ip[0] = ip[0] xor (MAGIC_COOKIE ushr 24 and 0xFF)
                    ip[1] = ip[1] xor (MAGIC_COOKIE ushr 16 and 0xFF)
                    ip[2] = ip[2] xor (MAGIC_COOKIE ushr 8 and 0xFF)
                    ip[3] = ip[3] xor (MAGIC_COOKIE and 0xFF)
                }
                return StunEndpoint(ip.joinToString("."), port)
            }
            // attributes are padded to 4-byte boundaries
            offset = valueStart + ((attrLength + 3) and 3.inv())
        }
        return null
    }

    private fun u8(
        data: ByteArray,
        index: Int,
    ): Int = data[index].toInt() and 0xFF
}
