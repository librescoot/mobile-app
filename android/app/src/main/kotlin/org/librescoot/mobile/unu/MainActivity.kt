package org.librescoot.mobile.unu

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.nfc.NfcAdapter

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.librescoot.mobile/phone_key")
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
    }
}
