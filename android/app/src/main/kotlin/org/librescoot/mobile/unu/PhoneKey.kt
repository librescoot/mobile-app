package org.librescoot.mobile.unu

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/** The private key never leaves Android Keystore. Reinstalling the app loses the key. */
object PhoneKey {
    private const val ALIAS = "librescoot-phone-unlock-v1"
    private val domain = "librescoot-phone-unlock-v1\u0000".toByteArray(Charsets.US_ASCII)

    @Synchronized
    fun publicKey(): ByteArray {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!store.containsAlias(ALIAS)) {
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
            generator.initialize(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build()
            )
            generator.generateKeyPair()
        }
        return store.getCertificate(ALIAS).publicKey.encoded
    }

    fun fingerprint(): String = fingerprintOf(publicKey())

    fun existingFingerprint(): String? {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return store.getCertificate(ALIAS)?.publicKey?.encoded?.let(::fingerprintOf)
    }

    private fun fingerprintOf(publicKey: ByteArray): String {
        val hash = MessageDigest.getInstance("SHA-256").digest(publicKey)
        return hash.take(16).joinToString("") { "%02X".format(it.toInt() and 0xff) }
    }

    @Synchronized
    fun sign(challenge: ByteArray): ByteArray {
        require(challenge.size == 32)
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = store.getKey(ALIAS, null) ?: error("Phone key not initialized")
        return Signature.getInstance("SHA256withECDSA").run {
            initSign(key as java.security.PrivateKey)
            update(domain)
            update(challenge)
            sign()
        }
    }
}
