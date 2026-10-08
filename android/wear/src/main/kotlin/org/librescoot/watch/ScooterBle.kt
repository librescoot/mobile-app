package org.librescoot.watch

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@SuppressLint("MissingPermission")
class ScooterBle(private val context: Context) {
    private val adapter get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private val main = Handler(Looper.getMainLooper())
    private var link: BluetoothGatt? = null
    private var operation: CancellableContinuation<Unit>? = null
    private var reading: CancellableContinuation<ByteArray>? = null
    private var phase = ""
    private var expected: UUID? = null
    private var writeIssued = false

    companion object {
        fun uuid(short: String): UUID = UUID.fromString("9a59$short-6e67-5d0d-aab9-ad9126b66f91")
    }

    suspend fun scan(): List<BluetoothDevice> {
        check(adapter?.isEnabled == true) { "Turn on Bluetooth" }
        val found = linkedMapOf<String, BluetoothDevice>()
        adapter.bondedDevices.filter { it.name == "unu Scooter" }.forEach { found[it.address] = it }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                main.post {
                    val record = result.scanRecord
                    if (record?.getManufacturerSpecificData(0xe50a) != null ||
                        record?.deviceName == "unu Scooter" ||
                        record?.serviceUuids?.any { it.uuid == uuid("0000") } == true) {
                        found[result.device.address] = result.device
                    }
                }
            }
        }
        val scanner = adapter.bluetoothLeScanner ?: error("Bluetooth unavailable")
        scanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
        try { delay(8000) } finally { scanner.stopScan(callback) }
        return found.values.toList()
    }

    suspend fun execute(id: String, name: String, action: String, pair: Boolean = false,
                        snapshot: (JSONObject) -> Unit): String {
        check(link == null) { "Bluetooth operation already active" }
        writeIssued = false
        val deadline = SystemClock.elapsedRealtime() + if (pair) 60000 else 15000
        try {
            return withTimeout(if (pair) 60000 else 15000) {
                val device = adapter.getRemoteDevice(id)
                if (!pair && device.bondState != BluetoothDevice.BOND_BONDED) return@withTimeout "pairFirst"
                connect(device)
                step("discover") { link!!.discoverServices() }
                check(characteristic("0000", "0001") != null && characteristic("0020", "0021") != null) { "Not a supported scooter" }
                if (pair && device.bondState != BluetoothDevice.BOND_BONDED) {
                    check(device.createBond()) { "Pairing could not start" }
                    while (device.bondState != BluetoothDevice.BOND_BONDED) delay(300)
                }
                suspend fun observe(): Pair<String, Boolean?> {
                    val state = CompanionProtocol.text(read("0020", "0021"))
                    val seat = when (CompanionProtocol.text(read("0020", "0022"))) {
                        "open" -> false
                        "closed" -> true
                        else -> null
                    }
                    return state to seat
                }
                var observed = observe()
                if (!CompanionProtocol.allows(observed.first, action)) return@withTimeout "unsafeState"
                if (!CompanionProtocol.confirms(observed.first, observed.second, action)) {
                    currentCoroutineContext().ensureActive()
                    check(SystemClock.elapsedRealtime() < deadline) { "Request expired" }
                    writeIssued = true
                    write(CompanionProtocol.wire(action))
                    do {
                        observed = observe()
                        if (CompanionProtocol.confirms(observed.first, observed.second, action)) break
                        delay(250)
                    } while (true)
                }
                // Publish confirmation before optional battery reads can exhaust the session budget.
                val data = JSONObject().put("version", 1).put("scooterId", id).put("name", name)
                    .put("state", observed.first).put("seatClosed", observed.second)
                    .put("updatedAt", System.currentTimeMillis()).put("connected", false)
                snapshot(data)
                if (action == "refresh") {
                    suspend fun charge(present: String, soc: String): Int? {
                        if (characteristic("00e0", present) == null || characteristic("00e0", soc) == null) return null
                        if (CompanionProtocol.uint32(read("00e0", present)) != 1L) return null
                        return CompanionProtocol.uint32(read("00e0", soc))?.takeIf { it in 0..100 }?.toInt()
                    }
                    val primary = charge("00e3", "00e9")
                    val secondary = charge("00ef", "00f5")
                    data.put("battery1", primary).put("battery2", secondary)
                        .put("rangeKm", CompanionProtocol.range(primary, secondary))
                    snapshot(data)
                }
                "confirmed"
            }
        } catch (_: Exception) {
            return if (writeIssued) "unknown" else "unavailable"
        } finally { close() }
    }

    private suspend fun connect(device: BluetoothDevice) = suspendCancellableCoroutine<Unit> { continuation ->
        phase = "connect"
        operation = continuation
        link = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        if (link == null) fail("Could not connect")
    }
    private suspend fun step(kind: String, start: () -> Boolean) = suspendCancellableCoroutine<Unit> { continuation ->
        phase = kind
        operation = continuation
        if (!start()) fail("Bluetooth operation rejected")
    }
    private fun characteristic(service: String, id: String) = link?.getService(uuid(service))?.getCharacteristic(uuid(id))
    private suspend fun read(service: String, id: String): ByteArray = suspendCancellableCoroutine { continuation ->
        val characteristic = characteristic(service, id)
        reading = continuation
        expected = characteristic?.uuid
        if (characteristic == null || !link!!.readCharacteristic(characteristic)) fail("Read unavailable")
    }
    @Suppress("DEPRECATION")
    private suspend fun write(command: String) {
        val characteristic = characteristic("0000", "0001") ?: error("Command unavailable")
        check(characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0)
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = command.toByteArray(Charsets.US_ASCII)
        step("write") { link!!.writeCharacteristic(characteristic) }
    }
    private fun completed(kind: String, status: Int) {
        if (phase != kind) return
        if (status != BluetoothGatt.GATT_SUCCESS) { fail("Bluetooth status $status"); return }
        phase = ""
        operation?.let { operation = null; if (it.isActive) it.resume(Unit) }
    }
    private fun readCompleted(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) = main.post {
        if (link !== gatt || characteristic.uuid != expected) return@post
        if (status != BluetoothGatt.GATT_SUCCESS) { fail("Read rejected"); return@post }
        expected = null
        reading?.let { reading = null; if (it.isActive) it.resume(value) }
    }
    private fun fail(message: String) {
        val error = IllegalStateException(message)
        operation?.let { operation = null; if (it.isActive) it.resumeWithException(error) }
        reading?.let { reading = null; if (it.isActive) it.resumeWithException(error) }
    }
    fun close() {
        val previous = link
        link = null
        phase = ""
        expected = null
        fail("Connection ended")
        previous?.disconnect()
        previous?.close()
    }
    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (link !== gatt) return@post
                if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) completed("connect", status)
                else if (newState == BluetoothProfile.STATE_DISCONNECTED || status != BluetoothGatt.GATT_SUCCESS) close()
            }
        }
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            main.post { if (link === gatt) completed("discover", status) }
        }
        override fun onServiceChanged(gatt: BluetoothGatt) { main.post { if (link === gatt) close() } }
        @Deprecated("Android compatibility callback")
        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            @Suppress("DEPRECATION")
            val value = characteristic.value ?: byteArrayOf()
            readCompleted(gatt, characteristic, value, status)
        }
        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            readCompleted(gatt, characteristic, value, status)
        }
        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            main.post { if (link === gatt && characteristic.uuid == uuid("0001")) completed("write", status) }
        }
    }
}
