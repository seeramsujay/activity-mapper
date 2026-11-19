package org.opensource.tracker.data.mesh

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM packet encryption, wire-compatible with the Flutter build:
 * `base64url( version(1) | nonce(12) | ciphertext + 128-bit tag )`.
 *
 * A fresh random nonce is used per packet and the GCM tag authenticates it, so a wrong key or any
 * tampering makes [decrypt] return null.
 */
object MeshCrypto {
    private const val VERSION: Byte = 1
    private const val NONCE_LENGTH = 12
    private const val TAG_BITS = 128
    private const val TAG_BYTES = TAG_BITS / 8
    private val random = SecureRandom()

    /** New 256-bit session key, URL-safe Base64. */
    fun generateKey(): String = Base64.getUrlEncoder().encodeToString(ByteArray(32).also { random.nextBytes(it) })

    /** True only for URL-safe Base64 that decodes to exactly 32 bytes (a usable AES-256 key). */
    fun isValidKey(base64Key: String): Boolean =
        try {
            Base64.getUrlDecoder().decode(base64Key).size == 32
        } catch (_: IllegalArgumentException) {
            false
        }

    /** Random 128-bit hex identifier. */
    fun generateId(): String = ByteArray(16).also { random.nextBytes(it) }.joinToString("") { "%02x".format(it) }

    fun encrypt(
        payload: String,
        base64Key: String,
    ): String {
        val key = decodeKey(base64Key)
        val nonce = ByteArray(NONCE_LENGTH).also { random.nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        val cipherText = cipher.doFinal(payload.toByteArray(Charsets.UTF_8))
        return Base64.getUrlEncoder().encodeToString(byteArrayOf(VERSION) + nonce + cipherText)
    }

    fun decrypt(
        encrypted: String,
        base64Key: String,
    ): String? =
        try {
            val key = decodeKey(base64Key)
            val combined = Base64.getUrlDecoder().decode(encrypted.trim())
            if (combined.size < 1 + NONCE_LENGTH + TAG_BYTES || combined[0] != VERSION) {
                null
            } else {
                val nonce = combined.copyOfRange(1, 1 + NONCE_LENGTH)
                val cipherText = combined.copyOfRange(1 + NONCE_LENGTH, combined.size)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
                String(cipher.doFinal(cipherText), Charsets.UTF_8)
            }
        } catch (_: Exception) {
            null // auth failure (wrong key / tampering), bad Base64, ...
        }

    private fun decodeKey(base64Key: String): ByteArray {
        val key = Base64.getUrlDecoder().decode(base64Key)
        require(key.size == 32) { "Mesh session key must be 256 bits, got ${key.size * 8}" }
        return key
    }
}
