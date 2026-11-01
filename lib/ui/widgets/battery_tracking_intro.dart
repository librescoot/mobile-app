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
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 104,
            height: 104,
            child: Stack(children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(28)),
                child: Icon(Icons.battery_5_bar, size: 48, color: colors.primary),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: colors.surface, shape: BoxShape.circle, border: Border.all(color: colors.outlineVariant)),
                  child: Icon(Icons.search, size: 24, color: colors.primary),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 28),
        Text(text('intro_title'),
            style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.15)),
        const SizedBox(height: 16),
        Text(text('intro_body'), style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
        if (!registrationEnabled) ...[
          const SizedBox(height: 16),
          Text(text('account_unavailable'), style: theme.textTheme.bodySmall),
        ],
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
