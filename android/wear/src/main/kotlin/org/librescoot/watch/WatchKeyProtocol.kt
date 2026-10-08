package org.librescoot.watch

/** ISO-DEP framing is independent of Android's HCE and key-storage APIs. */
class WatchKeyProtocol(private val publicKey: () -> ByteArray, private val sign: (ByteArray) -> ByteArray) {
    private var selected = false
    fun reset() { selected = false }
    fun process(command: ByteArray): ByteArray {
        val select = byteArrayOf(0x00, 0xa4.toByte(), 0x04, 0x00, 0x08,
            0xf0.toByte(), 0x4c, 0x53, 0x43, 0x4f, 0x4f, 0x54, 0x01, 0x00)
        if (command.contentEquals(select)) {
            selected = true
            return byteArrayOf(0x90.toByte(), 0x00)
        }
        if (!selected) return byteArrayOf(0x69, 0x85.toByte())
        if (command.size != 37 || !command.take(5).toByteArray().contentEquals(
                byteArrayOf(0x80.toByte(), 0x10, 0x00, 0x00, 0x20))) return byteArrayOf(0x6d, 0x00)
        return try {
            val key = publicKey()
            val signature = sign(command.copyOfRange(5, 37))
            check(key.size == 91 && signature.size <= 80 && signature.isNotEmpty())
            byteArrayOf(0x01) + key + signature + byteArrayOf(0x90.toByte(), 0x00)
        } catch (_: Exception) { byteArrayOf(0x69, 0x85.toByte()) }
    }
}
