import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import '../../feature_flags.dart';

class BatteryTrackingIntro extends StatelessWidget {
  const BatteryTrackingIntro({this.registrationEnabled = sunshineBatteryRegistrationEnabled, super.key});

  final bool registrationEnabled;

  @override
  Widget build(BuildContext context) {
    String text(String key) => FlutterI18n.translate(context, 'battery_tracker_$key');
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: Image.asset('images/battery/batt_full.webp', height: 128, excludeFromSemantics: true)),
        const SizedBox(height: 24),
        Text(text('intro_title'), style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(text('intro_body'), style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        for (final item in [
          (Icons.nfc, 'intro_identify'),
          (Icons.group_outlined, 'intro_shared'),
          (Icons.wb_sunny_outlined, registrationEnabled ? 'intro_sunshine' : 'intro_sunshine_pending'),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(item.$1, color: theme.colorScheme.primary),
            title: Text(text(item.$2)),
          ),
      ],
    );
  }
}

class BatteryFirmwareBadge extends StatelessWidget {
  const BatteryFirmwareBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: FlutterI18n.translate(context, 'battery_tracker_firmware_requirement'),
      child: Semantics(
        label: FlutterI18n.translate(context, 'battery_tracker_firmware_requirement'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text('Librescoot', style: Theme.of(context).textTheme.labelSmall),
          ),
        ),
      ),
    );
  }
}
