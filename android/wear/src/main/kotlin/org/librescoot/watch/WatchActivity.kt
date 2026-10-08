package org.librescoot.watch

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.format.DateUtils
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.widget.*
import kotlinx.coroutines.*
import org.json.JSONObject

@SuppressLint("MissingPermission")
class WatchActivity : Activity() {
    private val scope = MainScope()
    private lateinit var store: WatchStore
    private lateinit var ble: ScooterBle
    private lateinit var relay: PhoneRelay
    private var busy = false
    private var message = "Choose a scooter or pair this watch."
    private lateinit var column: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = WatchStore(this)
        ble = ScooterBle(this)
        relay = PhoneRelay(this)
        render()
    }
    override fun onResume() {
        super.onResume()
        scope.launch {
            try { withTimeout(4000) { relay.sync() } } catch (_: Exception) { }
            render()
        }
    }
    private fun permissions(): Boolean {
        val required = if (Build.VERSION.SDK_INT >= 31)
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        if (required.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) return true
        requestPermissions(required, 1)
        message = "Allow Bluetooth, then tap again."
        return false
    }
    private fun text(value: String, size: Float = 15f) {
        column.addView(TextView(this).apply {
            text = value; textSize = size; gravity = Gravity.CENTER
            setPadding(0, 5, 0, 5)
        })
    }
    private fun button(label: String, enabled: Boolean = !busy, action: () -> Unit) {
        column.addView(Button(this).apply {
            text = label; isAllCaps = false; isEnabled = enabled
            minHeight = (48 * resources.displayMetrics.density).toInt()
            setOnClickListener { action() }
        }, LinearLayout.LayoutParams(-1, -2))
    }
    private fun render() {
        val padding = (24 * resources.displayMetrics.density).toInt()
        column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
            gravity = Gravity.CENTER_HORIZONTAL
        }
        setContentView(ScrollView(this).apply { addView(column) })
        val target = store.selected()
        text(target?.optString("name") ?: "Librescoot", 20f)
        if (target != null) {
            text(if (target.optString("route") == "direct") "Direct Bluetooth key" else "Via phone")
            text("Last state: ${target.optString("state", "unknown")}")
            fun battery(key: String) = if (target.has(key) && !target.isNull(key)) "${target.optInt(key)}%" else "—"
            text("Batteries: ${battery("battery1")} / ${battery("battery2")}")
            if (target.has("rangeKm") && !target.isNull("rangeKm")) text("≈${target.optInt("rangeKm")} km")
            val updated = target.optLong("updatedAt")
            text(if (updated > 0) "Updated ${DateUtils.getRelativeTimeSpanString(updated)}" else "No recent telemetry", 12f)
        }
        text(message)
        if (target != null) {
            button("Refresh / connect") { execute(target, "refresh") }
            button("Unlock") { confirm("Unlock vehicle?", "This enables the scooter. Keep it stationary.") { execute(target, "unlock") } }
            button("Lock") { confirm("Lock vehicle?", "Only available when parked.") { execute(target, "lock") } }
            button("Open seatbox") { confirm("Open seatbox?", "The scooter must be parked.") { execute(target, "openSeat") } }
            if (!target.isNull("latitude") && target.has("latitude") && !target.isNull("longitude")) {
                button("Parked location") {
                    val uri = Uri.parse("geo:0,0?q=${target.optDouble("latitude")},${target.optDouble("longitude")}")
                    try { startActivity(Intent(Intent.ACTION_VIEW, uri)) } catch (_: Exception) {
                        message = "No maps app installed."; render()
                    }
                }
            }
        }
        button("Choose scooter") {
            val targets = store.targets()
            AlertDialog.Builder(this).setTitle("Choose scooter").setItems(targets.map {
                "${it.optString("name")} · ${it.optString("route")}"
            }.toTypedArray()) { _, index -> store.select(targets[index].getString("key")); message = ""; render() }.show()
        }
        button("Pair direct BLE key") { pair() }
        button(if (WatchKey.enabled(this)) "NFC key settings" else "Set up NFC key") { nfc() }
        if (target != null) button("Remove from watch") {
            confirm("Remove local shortcut?", "This does not revoke its BLE bond. Revoke a lost watch on the scooter. Keep another working key.") {
                store.forget(target.getString("key")); render()
            }
        }
    }
    private fun confirm(title: String, detail: String, action: () -> Unit) {
        AlertDialog.Builder(this).setTitle(title).setMessage(detail)
            .setNegativeButton("Cancel", null).setPositiveButton("Confirm") { _, _ -> action() }.show()
    }
    private fun execute(target: JSONObject, action: String) {
        if (busy) return
        if ((getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isDeviceLocked) return
        if (target.optString("route") == "direct" && !permissions()) { render(); return }
        busy = true; message = "Connecting…"; render()
        scope.launch {
            val result = try {
                if (target.optString("route") == "direct") ble.execute(target.getString("scooterId"), target.optString("name"), action) {
                    store.save(it, "direct")
                } else relay.execute(target, action)
            } catch (_: Exception) { "unavailable" }
            busy = false; message = CompanionProtocol.resultText(result); render()
            if (result == "confirmed") column.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        }
    }
    private fun pair() {
        if (!permissions()) { render(); return }
        confirm("Pair watch with scooter?", "Use an existing key to park the scooter first. Disconnect the phone if it occupies the BLE connection. Enter the scooter's pairing PIN on this watch.") {
            busy = true; message = "Scanning…"; render()
            scope.launch {
                try {
                    val devices = ble.scan()
                    if (devices.isEmpty()) message = "No scooters found. Check Bluetooth and pairing mode."
                    else AlertDialog.Builder(this@WatchActivity).setTitle("Select scooter")
                        .setItems(devices.map { "${it.name ?: "Scooter"}\n${it.address}" }.toTypedArray()) { _, index ->
                            val device = devices[index]
                            busy = true; message = "Pairing — check the system PIN prompt…"; render()
                            scope.launch {
                                val result = ble.execute(device.address, device.name ?: "Scooter", "refresh", pair = true) {
                                    store.save(it, "direct"); store.select("direct:${device.address}")
                                }
                                busy = false; message = CompanionProtocol.resultText(result); render()
                            }
                        }.show()
                } catch (_: Exception) { message = "Scan unavailable. Check Bluetooth permissions." }
                busy = false; render()
            }
        }
    }
    private fun nfc() {
        if (WatchKey.enabled(this)) {
            AlertDialog.Builder(this).setTitle("Experimental NFC key")
                .setMessage("Fingerprint:\n${WatchKey.fingerprint()}\n\nEnroll using the scooter's master-card learn flow. Keep the watch unlocked and screen on. Disabling here does not revoke a lost watch; remove its fingerprint on the scooter.")
                .setPositiveButton("Done", null).setNegativeButton("Disable") { _, _ -> WatchKey.enable(this, false); render() }.show()
        } else if (!WatchKey.available(this)) {
            message = "NFC key needs third-party HCE support, NFC enabled, and a watch PIN. Payment NFC alone is not enough."
            render()
        } else confirm("Enable experimental NFC key?", "Creates a key only on this watch. Enroll it separately on a compatible scooter using its master-card learn flow. Hardware operation is not yet certified.") {
            try { WatchKey.enable(this, true); nfc() } catch (_: Exception) { message = "NFC key unavailable." }
            render()
        }
    }
    override fun onDestroy() {
        scope.cancel()
        ble.close()
        super.onDestroy()
    }
}
