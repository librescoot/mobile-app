import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../service/onboarding_preferences.dart';
import '../widgets/battery_tracking_intro.dart';

Future<void> showBatteryFeatureAnnouncement(
  BuildContext context, {
  OnboardingPreferences? preferences,
  Future<bool> Function(Uri)? openBrowser,
}) async {
  final onboarding = preferences ?? OnboardingPreferences();
  if (await onboarding.hasSeenBatteryFeature() || !context.mounted) return;
  final joinTracker = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(FlutterI18n.translate(context, 'battery_tracker_announcement_title')),
      content: const SizedBox(width: 380, child: BatteryTrackingIntro()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(FlutterI18n.translate(context, 'battery_tracker_not_now')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(FlutterI18n.translate(context, 'battery_tracker_join')),
        ),
      ],
    ),
  );
  await onboarding.markBatteryFeatureSeen();
  if (joinTracker == true && context.mounted) {
    final uri = sunshineSignupUri();
    final opened = await (openBrowser?.call(uri) ?? launchUrl(uri, mode: LaunchMode.externalApplication));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FlutterI18n.translate(context, 'battery_tracker_account_open_error'))));
    }
  }
}
