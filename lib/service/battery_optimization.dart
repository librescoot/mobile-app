import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Android's Doze and App Standby exemption, required for an action arriving
/// from another app to start the background service when it isn't already
/// running. A widget tap gets that privilege from the launcher; a broadcast
/// doesn't.
class BatteryOptimization {
  static const MethodChannel _channel = MethodChannel('org.librescoot.mobile.unu/battery_optimization');

  static final Logger _log = Logger('BatteryOptimization');

  /// Only Android has the concept; everywhere else this is silently exempt.
  static bool get isSupported => Platform.isAndroid;

  static Future<bool> isIgnored() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } on PlatformException catch (e) {
      _log.warning('Could not read the battery optimization state', e);
      return false;
    } on MissingPluginException catch (e) {
      _log.warning('Battery optimization channel unavailable here', e);
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
    } on PlatformException catch (e) {
      _log.warning('Could not open the battery optimization settings', e);
    }
  }

  /// Shows the system's own dialog. Returns whether it could be shown, not what
  /// the user chose: the dialog is a separate activity, so re-read [isIgnored]
  /// once the app resumes.
  static Future<bool> request() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;
    } on PlatformException catch (e) {
      _log.warning('Could not show the battery optimization dialog', e);
      return false;
    }
  }
}
