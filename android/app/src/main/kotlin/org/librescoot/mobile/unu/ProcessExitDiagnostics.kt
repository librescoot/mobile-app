package org.librescoot.mobile.unu

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

object ProcessExitDiagnostics {
    fun register(context: Context, engine: FlutterEngine) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.diagnostics/process_exits")
            .setMethodCallHandler { call, result ->
                if (call.method != "recentExits") {
                    result.notImplemented()
                } else {
                    Thread {
                        try {
                            val exits = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                                manager.getHistoricalProcessExitReasons(context.packageName, 0, 20)
                                    .filter { it.reason in setOf(ApplicationExitInfo.REASON_CRASH, ApplicationExitInfo.REASON_CRASH_NATIVE, ApplicationExitInfo.REASON_ANR) }
                                    .take(3)
                                    .map { info ->
                                        val trace = try {
                                            info.traceInputStream?.use { input ->
                                                val output = ByteArrayOutputStream()
                                                val buffer = ByteArray(4096)
                                                while (output.size() < 1048577) {
                                                    val count = input.read(buffer, 0, minOf(buffer.size, 1048577 - output.size()))
                                                    if (count <= 0) break
                                                    output.write(buffer, 0, count)
                                                }
                                                val bytes = output.toByteArray()
                                                mapOf("encoding" to if (info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) "base64-protobuf" else "utf8",
                                                    "truncated" to (bytes.size > 1048576),
                                                    "data" to if (info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE)
                                                        Base64.encodeToString(bytes.copyOf(minOf(bytes.size, 1048576)), Base64.NO_WRAP)
                                                    else String(bytes, 0, minOf(bytes.size, 1048576), Charsets.UTF_8))
                                            }
                                        } catch (_: Exception) { null }
                                        mapOf("timestamp" to info.timestamp, "reason" to info.reason,
                                            "status" to info.status, "description" to info.description,
                                            "process" to info.processName, "trace" to trace)
                                    }
                            } else emptyList()
                            main.post { result.success(exits) }
                        } catch (error: Exception) {
                            main.post { result.error("EXIT_INFO", error.message, null) }
                        }
                    }.start()
                }
            }
    }
}
