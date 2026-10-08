import 'dart:async';
import 'package:flutter/services.dart';

/// One bridge per Flutter engine. Native routing chooses one connected owner.
class WearableBridge {
  WearableBridge(this.execute) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') throw MissingPluginException();
      return execute(Map<String, dynamic>.from(call.arguments as Map));
    });
  }
  static const _channel = MethodChannel('org.librescoot.mobile/companion');
  final Future<String> Function(Map<String, dynamic>) execute;
  bool _disposed = false;
  Timer? _publishTimer;

  void scheduleSnapshot(Map<String, dynamic>? Function() snapshot) {
    if (_disposed) return;
    _publishTimer ??= Timer(const Duration(milliseconds: 500), () {
      _publishTimer = null;
      final value = snapshot();
      if (value != null) unawaited(publish(value));
    });
  }

  Future<void> publish(Map<String, dynamic> snapshot) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('snapshot', snapshot);
    } on MissingPluginException {
      // Desktop and hardware-free Flutter tests have no wearable transport.
    } on PlatformException {
      // A disconnected watch must not affect the phone connection owner.
    }
  }

  void dispose() {
    _disposed = true;
    _publishTimer?.cancel();
    _channel.setMethodCallHandler(null);
    unawaited(_channel.invokeMethod<void>('detach').catchError((Object _) {}));
  }
}
