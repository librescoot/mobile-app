import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

/// Formats an actual firmware duration without rounding it to a UI preset.
String formatSettingsDuration(BuildContext context, int seconds) {
  if (seconds == 0) return FlutterI18n.translate(context, 'ls_settings_duration_never');
  if (seconds < 0) return '$seconds s';
  var remaining = seconds;
  final parts = <String>[];
  for (final (unit, size) in const [('day', 86400), ('hour', 3600), ('minute', 60), ('second', 1)]) {
    final count = remaining ~/ size;
    remaining %= size;
    if (count == 0) continue;
    parts.add(FlutterI18n.translate(context, 'settings_duration_${unit}_${count == 1 ? 'one' : 'many'}',
        translationParams: {'count': '$count'}));
  }
  return parts.join(' ');
}
