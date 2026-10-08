package org.librescoot.companion

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.TimeUnit

class WearableBridgePlugin : FlutterPlugin {
    private lateinit var channel: MethodChannel
    private val owner = UUID.randomUUID().toString()
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "org.librescoot.mobile/companion")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "snapshot" -> {
                    val snapshot = JSONObject(call.arguments as Map<*, *>)
                    PhoneRouter.publish(context, owner, channel, snapshot)
                    result.success(null)
                }
                "detach" -> { PhoneRouter.detach(context, owner); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PhoneRouter.detach(binding.applicationContext, owner)
        channel.setMethodCallHandler(null)
    }
}

internal object PhoneRouter {
    private data class Owner(val channel: MethodChannel, val snapshot: JSONObject)
    private val owners = linkedMapOf<String, Owner>()
    private val main = Handler(Looper.getMainLooper())
    private var busy = false
    private const val STATE = "/companion/v1/state"

    fun publish(context: Context, id: String, channel: MethodChannel, snapshot: JSONObject) {
        owners.remove(id)
        owners[id] = Owner(channel, snapshot)
        publishLatest(context)
    }
    fun detach(context: Context, id: String) {
        owners.remove(id)
        publishLatest(context)
    }
    private fun publishLatest(context: Context) {
        val owner = owners.values.lastOrNull { it.snapshot.optBoolean("connected") }
            ?: owners.values.lastOrNull() ?: return
        val snapshot = owner.snapshot.toString()
        context.getSharedPreferences("companion", 0).edit().putString("snapshot", snapshot).apply()
        Wearable.getDataClient(context).putDataItem(PutDataMapRequest.create(STATE).apply {
            dataMap.putString("json", snapshot)
        }.asPutDataRequest()).addOnFailureListener { /* Phone operation does not depend on a watch. */ }
    }
    fun command(context: Context, request: JSONObject, reply: (String) -> Unit) = main.post {
        val now = System.currentTimeMillis()
        val id = request.optString("id")
        val issued = request.optLong("issuedAt")
        val expires = request.optLong("expiresAt")
        if (request.optInt("version") != 1 || !id.matches(Regex("[a-zA-Z0-9-]{16,64}")) ||
            request.optString("scooterId").length !in 1..128 ||
            request.optString("action") !in listOf("refresh", "lock", "unlock", "openSeat") ||
            expires <= issued || expires - issued > 15000) {
            reply("invalid"); return@post
        }
        if (issued > now + 2000 || expires <= now) { reply("expired"); return@post }
        val prefs = context.getSharedPreferences("companion_requests", 0)
        if (prefs.contains(id)) { reply("duplicate"); return@post }
        val edit = prefs.edit()
        prefs.all.forEach { (key, value) -> if ((value as? Long ?: 0) <= now) edit.remove(key) }
        // Persist before dispatch; process death must not turn retransmission into actuation.
        if (!edit.putLong(id, expires).commit()) { reply("unavailable"); return@post }
        if (busy) { reply("busy"); return@post }
        val owner = owners.values.lastOrNull {
            it.snapshot.optBoolean("connected") &&
                it.snapshot.optString("scooterId") == request.optString("scooterId")
        }
        if (owner == null) { reply("unavailable"); return@post }
        busy = true
        var finished = false
        fun finish(status: String) {
            if (finished) return
            finished = true
            busy = false
            reply(status)
        }
        main.postDelayed({ finish("unknown") }, (expires - now).coerceAtLeast(1))
        owner.channel.invokeMethod("command", request.keys().asSequence().associateWith { request.get(it) },
            object : MethodChannel.Result {
                override fun success(result: Any?) = finish(result as? String ?: "unknown")
                override fun error(code: String, message: String?, details: Any?) = finish("unknown")
                override fun notImplemented() = finish("unavailable")
            })
    }
}

class CompanionListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/companion/v1/command" || event.data.size > 4096) return
        val request = try { JSONObject(String(event.data, Charsets.UTF_8)) } catch (_: Exception) { return }
        fun reply(status: String) {
            val result = JSONObject().put("version", 1).put("id", request.optString("id"))
                .put("scooterId", request.optString("scooterId")).put("status", status)
            Wearable.getMessageClient(this).sendMessage(event.sourceNodeId, "/companion/v1/result",
                result.toString().toByteArray()).addOnFailureListener { }
        }
        val nearby = try {
            Tasks.await(Wearable.getNodeClient(this).connectedNodes, 3, TimeUnit.SECONDS)
                .any { it.id == event.sourceNodeId && it.isNearby }
        } catch (_: Exception) { false }
        // The Data Layer can relay through the internet; that is not local key use.
        if (!nearby) { reply("phoneNotNearby"); return }
        PhoneRouter.command(this, request, ::reply)
    }
}
