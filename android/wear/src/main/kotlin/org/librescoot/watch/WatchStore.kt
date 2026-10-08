package org.librescoot.watch

import android.content.Context
import android.content.ComponentName
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.google.android.gms.wearable.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject

class WatchStore(private val context: Context) {
    val preferences = context.getSharedPreferences("watch_scooters", 0)
    fun targets(): List<JSONObject> {
        val array = JSONArray(preferences.getString("targets", "[]"))
        return (0 until array.length()).map { array.getJSONObject(it) }
    }
    fun selected(): JSONObject? = targets().firstOrNull { it.optString("key") == preferences.getString("selected", null) }
        ?: targets().firstOrNull()
    fun select(key: String) { preferences.edit().putString("selected", key).apply(); updateSurfaces() }
    fun save(snapshot: JSONObject, route: String, node: String = "") {
        if (snapshot.optInt("version") != 1 || snapshot.optString("scooterId").isBlank()) return
        val key = "$route:${snapshot.getString("scooterId") }"
        val copy = JSONObject(snapshot.toString()).put("key", key).put("route", route).put("node", node)
        val items = targets().filter { it.optString("key") != key }.takeLast(19) + copy
        preferences.edit().putString("targets", JSONArray(items).toString()).apply()
        updateSurfaces()
    }
    fun forget(key: String) {
        preferences.edit().putString("targets", JSONArray(targets().filter { it.optString("key") != key }).toString()).apply()
        updateSurfaces()
    }
    private fun updateSurfaces() {
        TileService.getUpdater(context).requestUpdate(ScooterTileService::class.java)
        ComplicationDataSourceUpdateRequester.create(context, ComponentName(context, ScooterComplicationService::class.java)).requestUpdateAll()
    }
}

class WatchDataService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        val store = WatchStore(this)
        events.forEach { event ->
            if (event.type == DataEvent.TYPE_CHANGED && event.dataItem.uri.path == CompanionProtocol.PREFIX + "state") {
                val json = DataMapItem.fromDataItem(event.dataItem).dataMap.getString("json") ?: return@forEach
                try { store.save(JSONObject(json), "phone", event.dataItem.uri.host ?: "") } catch (_: Exception) { }
            }
        }
    }
}

class PhoneRelay(private val context: Context) {
    suspend fun sync() {
        val data = Wearable.getDataClient(context).dataItems.await()
        try {
            data.forEach { item ->
                if (item.uri.path == CompanionProtocol.PREFIX + "state") {
                    val json = DataMapItem.fromDataItem(item).dataMap.getString("json") ?: return@forEach
                    WatchStore(context).save(JSONObject(json), "phone", item.uri.host ?: "")
                }
            }
        } finally { data.release() }
    }
    suspend fun execute(target: JSONObject, action: String): String {
        val nodeId = target.optString("node")
        if (Wearable.getNodeClient(context).connectedNodes.await().none { it.id == nodeId && it.isNearby }) return "phoneNotNearby"
        val request = CompanionProtocol.request(target.getString("scooterId"), action)
        val result = CompletableDeferred<String>()
        val client = Wearable.getMessageClient(context)
        val listener = MessageClient.OnMessageReceivedListener { event ->
            if (event.sourceNodeId != nodeId || event.path != CompanionProtocol.PREFIX + "result") return@OnMessageReceivedListener
            try {
                val response = JSONObject(String(event.data, Charsets.UTF_8))
                if (response.optInt("version") == 1 && response.optString("id") == request.getString("id") &&
                    response.optString("scooterId") == request.getString("scooterId")) {
                    result.complete(response.optString("status", "unknown"))
                }
            } catch (_: Exception) { }
        }
        client.addListener(listener).await()
        try {
            return withTimeout(16000) {
                client.sendMessage(nodeId, CompanionProtocol.PREFIX + "command", request.toString().toByteArray()).await()
                result.await()
            }
        } catch (_: Exception) {
            return "unknown"
        } finally { client.removeListener(listener) }
    }
}
