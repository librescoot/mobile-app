package org.librescoot.watch

import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.os.PowerManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

object WatchKey {
    private const val ALIAS = "librescoot-watch-unlock-v1"
    private val domain = "librescoot-phone-unlock-v1\u0000".toByteArray(Charsets.US_ASCII)
    fun available(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION) &&
            NfcAdapter.getDefaultAdapter(context)?.isEnabled == true &&
            (context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isDeviceSecure
    fun enabled(context: Context): Boolean = context.packageManager.getComponentEnabledSetting(
        ComponentName(context, WatchKeyService::class.java)) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
    fun enable(context: Context, enabled: Boolean) {
        if (enabled) { check(available(context)); publicKey() }
        context.packageManager.setComponentEnabledSetting(ComponentName(context, WatchKeyService::class.java),
            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP)
    }
    @Synchronized
    fun publicKey(): ByteArray {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!store.containsAlias(ALIAS)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256).build())
                generateKeyPair()
            }
        }
        return store.getCertificate(ALIAS).publicKey.encoded
    }
    fun fingerprint(): String = MessageDigest.getInstance("SHA-256").digest(publicKey())
        .take(16).joinToString("") { "%02X".format(it.toInt() and 255) }
    fun sign(challenge: ByteArray): ByteArray {
        require(challenge.size == 32)
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return Signature.getInstance("SHA256withECDSA").run {
            initSign(store.getKey(ALIAS, null) as PrivateKey)
            update(domain)
            update(challenge)
            sign()
        }
    }
}

/** Protocol-compatible with the enrolled phone key, with a watch-local private key. */
class WatchKeyService : HostApduService() {
    private val protocol = WatchKeyProtocol(WatchKey::publicKey, WatchKey::sign)
    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!keyguard.isDeviceSecure || keyguard.isDeviceLocked || !power.isInteractive) {
            protocol.reset()
            return byteArrayOf(0x69, 0x85.toByte())
        }
        return protocol.process(commandApdu)
    }
    override fun onDeactivated(reason: Int) { protocol.reset() }
}
