package org.librescoot.watch

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import java.io.File

class CompanionProtocolTest {
    @Test fun matchesCrossPlatformContract() {
        val contract = JSONObject(File(System.getProperty("companionContract")).readText())
        val cases = contract.getJSONArray("stateCases")
        for (index in 0 until cases.length()) {
            val item = cases.getJSONObject(index)
            val state = if (item.isNull("state")) null else item.getString("state")
            val seat = if (item.isNull("seatClosed")) null else item.getBoolean("seatClosed")
            assertEquals(item.getBoolean("allowed"), CompanionProtocol.allows(state, item.getString("action")))
            assertEquals(item.getBoolean("confirmed"), CompanionProtocol.confirms(state, seat, item.getString("action")))
        }
        val commands = contract.getJSONObject("commands")
        commands.keys().forEach { assertEquals(commands.getString(it), CompanionProtocol.wire(it)) }
    }
    @Test fun requestsAreExplicitBoundedAndTargeted() {
        val request = CompanionProtocol.request("scooter-a", "unlock", 100000)
        assertEquals(1, request.getInt("version"))
        assertEquals("scooter-a", request.getString("scooterId"))
        assertEquals(115000, request.getLong("expiresAt"))
        assertNotEquals(request.getString("id"), CompanionProtocol.request("scooter-a", "unlock").getString("id"))
    }
    @Test(expected = IllegalArgumentException::class) fun noToggle() { CompanionProtocol.request("a", "toggle") }
    @Test fun stateGatesAreConservative() {
        for (state in listOf(null, "off", "ready-to-drive", "unknown", "updating", "waiting-seatbox")) {
            assertFalse(CompanionProtocol.allows(state, "unlock"))
            assertFalse(CompanionProtocol.allows(state, "lock"))
            assertFalse(CompanionProtocol.allows(state, "openSeat"))
        }
        assertTrue(CompanionProtocol.allows("stand-by", "unlock"))
        assertTrue(CompanionProtocol.allows("parked", "openSeat"))
    }
    @Test fun confirmationsUseVehicleAndSeatStates() {
        assertTrue(CompanionProtocol.confirms("parked", true, "unlock"))
        assertFalse(CompanionProtocol.confirms("ready-to-drive", true, "unlock"))
        assertFalse(CompanionProtocol.confirms("unlocked", null, "unlock"))
        assertTrue(CompanionProtocol.confirms("parked", false, "openSeat"))
        assertFalse(CompanionProtocol.confirms("parked", null, "openSeat"))
    }
    @Test fun telemetryHandlesUnknownAndZero() {
        assertNull(CompanionProtocol.range(null, null))
        assertEquals(0, CompanionProtocol.range(0, null))
        assertEquals(45, CompanionProtocol.range(100, null))
        assertEquals(90, CompanionProtocol.range(100, 100))
        assertNull(CompanionProtocol.uint32(byteArrayOf(100)))
        assertEquals(100L, CompanionProtocol.uint32(byteArrayOf(100, 0, 0, 0)))
        assertEquals("parked", CompanionProtocol.text("parked\u0000\u0000".toByteArray()))
    }
    @Test fun wireCommandsMatchScooterProtocol() {
        assertEquals("scooter:state unlock", CompanionProtocol.wire("unlock"))
        assertEquals("scooter:state lock", CompanionProtocol.wire("lock"))
        assertEquals("scooter:seatbox open", CompanionProtocol.wire("openSeat"))
    }
}
