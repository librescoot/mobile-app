package org.librescoot.watch

import org.junit.Assert.*
import org.junit.Test

class WatchKeyProtocolTest {
    private val select = byteArrayOf(0, 0xa4.toByte(), 4, 0, 8, 0xf0.toByte(), 0x4c, 0x53, 0x43, 0x4f, 0x4f, 0x54, 1, 0)
    private val challenge = ByteArray(32) { it.toByte() }
    private val command = byteArrayOf(0x80.toByte(), 0x10, 0, 0, 32) + challenge
    @Test fun selectionAndDeactivationGateSigning() {
        var signed = 0
        val protocol = WatchKeyProtocol({ ByteArray(91) }, { signed++; byteArrayOf(1) })
        assertArrayEquals(byteArrayOf(0x69, 0x85.toByte()), protocol.process(command))
        assertEquals(0, signed)
        assertArrayEquals(byteArrayOf(0x90.toByte(), 0), protocol.process(select))
        protocol.process(command)
        assertEquals(1, signed)
        protocol.reset()
        protocol.process(command)
        assertEquals(1, signed)
    }
    @Test fun malformedApdusNeverSign() {
        var signed = 0
        val protocol = WatchKeyProtocol({ ByteArray(91) }, { signed++; byteArrayOf(1) })
        protocol.process(select)
        for (bad in listOf(command.dropLast(1).toByteArray(), command + 0, command.clone().apply { this[4] = 31 }, byteArrayOf())) {
            assertArrayEquals(byteArrayOf(0x6d, 0), protocol.process(bad))
        }
        assertEquals(0, signed)
    }
    @Test fun responseContainsVersionKeySignatureAndStatus() {
        val key = ByteArray(91) { 7 }
        val signature = ByteArray(70) { 9 }
        val protocol = WatchKeyProtocol({ key }, { assertArrayEquals(challenge, it); signature })
        protocol.process(select)
        assertArrayEquals(byteArrayOf(1) + key + signature + byteArrayOf(0x90.toByte(), 0), protocol.process(command))
    }
    @Test fun unavailableKeysFailClosed() {
        val protocol = WatchKeyProtocol({ throw IllegalStateException("locked") }, { error("must not sign") })
        protocol.process(select)
        assertArrayEquals(byteArrayOf(0x69, 0x85.toByte()), protocol.process(command))
    }
}
