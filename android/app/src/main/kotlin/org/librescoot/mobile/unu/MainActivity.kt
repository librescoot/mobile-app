package org.librescoot.mobile.unu

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import org.librescoot.mobile.unu.tasker.TaskerSettings

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.librescoot.mobile/phone_key")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "existingFingerprint" -> {
                        try {
                            result.success(PhoneKey.existingFingerprint())
                        } catch (e: Exception) {
                            result.error("KEY_ERROR", "Could not read phone key: ${e.message}", null)
                        }
                    }
                    "fingerprint" -> {
                        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION) ||
                            NfcAdapter.getDefaultAdapter(this)?.isEnabled != true) {
                            result.error("NFC_UNAVAILABLE", "Android NFC card emulation is unavailable", null)
                        } else try {
                            result.success(PhoneKey.fingerprint())
                        } catch (e: Exception) {
                            result.error("KEY_ERROR", "Could not initialize phone key: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TASKER_SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBackgroundScan" -> {
                        val enabled = call.argument<Boolean>("enabled")
                        if (enabled == null) {
                            result.error("BAD_ARGUMENT", "Missing background scan state", null)
                        } else {
                            TaskerSettings.setBackgroundScan(this, enabled)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> result.success(BatteryOptimization.isIgnored(this))
                    "requestIgnoreBatteryOptimizations" -> result.success(BatteryOptimization.request(this))
                    "openBatteryOptimizationSettings" -> result.success(BatteryOptimization.openSettings(this))
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val BATTERY_CHANNEL = "org.librescoot.mobile.unu/battery_optimization"
        private const val TASKER_SETTINGS_CHANNEL = "org.librescoot.mobile.unu/tasker_settings"
    }
}

/** Whether the app is exempt from Doze and App Standby, and how to ask for it. */
object BatteryOptimization {

    fun isIgnored(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** Shows the system's dialog. It reports nothing back, so callers re-read [isIgnored]. */
    @SuppressLint("BatteryLife")
    fun request(activity: android.app.Activity): Boolean {
        if (isIgnored(activity)) return true
        return try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${activity.packageName}"),
                )
            )
            true
        } catch (e: Exception) {
            openSettings(activity)
        }
    }

    /** Opens this app's settings page. Android exposes no intent for a per-app battery
     *  screen, so the all-apps list is the fallback. */
    fun openSettings(activity: android.app.Activity): Boolean {
        val destinations = listOf(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${activity.packageName}"),
            ),
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
        )
        for (intent in destinations) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: Exception) {
                continue
            }
        }
        return false
    }
}
