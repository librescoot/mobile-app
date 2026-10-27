import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatteryTrackerStore extends ChangeNotifier {
  BatteryTrackerStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  })  : _read = read ?? (() => SharedPreferencesAsync().getString(_key)),
        _write = write ?? ((value) => SharedPreferencesAsync().setString(_key, value));

  static const _key = 'batteryTracker.v1';
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  bool _enabled = false;
  Map<String, BatteryIdentity> _batteries = {};
  bool get enabled => _enabled;
  List<BatteryIdentity> get batteries => List.unmodifiable(_batteries.values);

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> load() => _serialize(() async {
        final raw = await _read();
        if (raw == null) return;
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          if (data['enabled'] is! bool || data['batteries'] is! List) {
            throw const FormatException('Invalid battery tracker storage');
          }
          final entries = (data['batteries'] as List)
              .map((value) => BatteryIdentity.fromJson(Map<String, dynamic>.from(value as Map)));
          _batteries = {for (final entry in entries) entry.serialNumber: entry};
          _enabled = data['enabled'] as bool;
        } catch (_) {
          _enabled = false;
          _batteries = {};
        }
        if (!_disposed) notifyListeners();
      });

  Future<void> _save(bool enabled, Map<String, BatteryIdentity> batteries) async {
    await _write(jsonEncode({
      'enabled': enabled,
      'batteries': batteries.values.map((entry) => entry.toJson()).toList(),
    }));
    _enabled = enabled;
    _batteries = batteries;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> setEnabled(bool enabled) => _serialize(() => _save(enabled, Map.of(_batteries)));

  Future<void> remember(Iterable<BatteryIdentity> identities) => _serialize(() async {
        if (!_enabled) return;
        await _save(true, {
          ..._batteries,
          for (final identity in identities) identity.serialNumber: identity,
        });
      });

  Future<void> forget(String serial) => _serialize(() async {
        final next = Map.of(_batteries)..remove(serial);
        await _save(_enabled, next);
      });

  Future<void> clear() => _serialize(() => _save(_enabled, {}));
}
