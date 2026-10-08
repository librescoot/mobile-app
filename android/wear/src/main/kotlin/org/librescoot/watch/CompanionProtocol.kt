package org.librescoot.watch

import org.json.JSONObject
import java.util.UUID
import kotlin.math.roundToInt

object CompanionProtocol {
    const val PREFIX = "/companion/v1/"
    fun request(scooterId: String, action: String, now: Long = System.currentTimeMillis()): JSONObject {
        require(scooterId.isNotBlank())
        require(action in listOf("refresh", "lock", "unlock", "openSeat"))
        return JSONObject().put("version", 1).put("id", UUID.randomUUID().toString())
            .put("scooterId", scooterId).put("action", action)
            .put("issuedAt", now).put("expiresAt", now + 15000)
    }
    fun allows(state: String?, action: String): Boolean = when (action) {
        "unlock", "lock" -> state == "stand-by" || state == "parked"
        "openSeat" -> state == "parked"
        "refresh" -> true
        else -> false
    }
    fun confirms(state: String?, seatClosed: Boolean?, action: String): Boolean = when (action) {
        "lock" -> state == "stand-by"
        "unlock" -> state == "parked"
        "openSeat" -> seatClosed == false
        "refresh" -> state != null
        else -> false
    }
    fun wire(action: String): String = when (action) {
        "lock" -> "scooter:state lock"
        "unlock" -> "scooter:state unlock"
        "openSeat" -> "scooter:seatbox open"
        else -> error("Not an actuation")
    }
    fun range(primary: Int?, secondary: Int?): Int? =
        if (primary == null && secondary == null) null
        else (((primary ?: 0) + (secondary ?: 0)) * 0.45).roundToInt()
    fun text(bytes: ByteArray): String = bytes.toString(Charsets.UTF_8).trim('\u0000', ' ', '\n', '\r')
    fun uint32(bytes: ByteArray): Long? = if (bytes.size != 4) null else
        bytes.foldIndexed(0L) { index, result, byte -> result or ((byte.toLong() and 255) shl (8 * index)) }
    fun resultText(status: String): String = when (status) {
        "confirmed" -> "Confirmed by scooter"
        "unknown" -> "Outcome unknown. Check scooter before trying again."
        "unsafeState" -> "Not allowed in this state. Park or wake the scooter first."
        "phoneAuthRequired" -> "Use authentication on your phone."
        "phoneNotNearby" -> "Bring your paired phone nearby."
        "expired" -> "Request expired. Nothing further will be sent."
        "duplicate" -> "Request already handled. Refresh to check the scooter."
        "busy" -> "Another command is running."
        "pairFirst" -> "Pair this watch with the scooter first."
        else -> "Unavailable. Connect your phone or move closer for direct Bluetooth."
    }
}
