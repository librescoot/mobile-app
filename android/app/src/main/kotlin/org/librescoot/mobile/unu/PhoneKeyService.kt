package org.librescoot.mobile.unu

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/** LibreScoot ISO-DEP credential. Only a locally enrolled public key can unlock. */
class PhoneKeyService : HostApduService() {
    private var selected = false
    private val aid = byteArrayOf(0xF0.toByte(), 0x4C, 0x53, 0x43, 0x4F, 0x4F, 0x54, 0x01)

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        val select = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, aid.size.toByte()) + aid + 0x00.toByte()
        if (commandApdu.contentEquals(select)) {
            selected = true
            return byteArrayOf(0x90.toByte(), 0x00)
        }
        if (!selected) return byteArrayOf(0x69, 0x85.toByte())
        if (commandApdu.size != 37 || commandApdu[0] != 0x80.toByte() ||
            commandApdu[1] != 0x10.toByte() || commandApdu[2] != 0x00.toByte() ||
            commandApdu[3] != 0x00.toByte() || commandApdu[4] != 0x20.toByte()) {
            return byteArrayOf(0x6D, 0x00)
        }
        return try {
            val publicKey = PhoneKey.publicKey()
            val signature = PhoneKey.sign(commandApdu.copyOfRange(5, 37))
            if (publicKey.size != 91 || signature.size > 80) byteArrayOf(0x6F, 0x00)
            else byteArrayOf(0x01) + publicKey + signature + byteArrayOf(0x90.toByte(), 0x00)
        } catch (_: Exception) {
            byteArrayOf(0x69, 0x85.toByte())
        }
    }

    override fun onDeactivated(reason: Int) {
        selected = false
    }
}
