import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import '../../service/onboarding_preferences.dart';
import '../../feature_flags.dart';
import '../widgets/battery_tracking_intro.dart';
import '../screens/battery_tracker_screen.dart';

Future<bool> showBatteryFeatureAnnouncement(
  BuildContext context, {
  required bool Function() canShow,
  OnboardingPreferences? preferences,
  Future<void> Function()? openTracker,
  bool enabled = sunshineBatteryRegistrationEnabled,
}) async {
  if (!enabled) return true;
  if (!context.mounted || !canShow()) return false;
  final onboarding = preferences ?? OnboardingPreferences();
  final alreadySeen = await onboarding.hasSeenBatteryFeature();
  if (!context.mounted || !canShow()) return false;
  if (alreadySeen) return true;
  final addBattery = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(FlutterI18n.translate(context, 'battery_tracker_announcement_title')),
      content: SizedBox(width: 380, child: BatteryTrackingIntro(registrationEnabled: enabled)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(FlutterI18n.translate(context, 'battery_tracker_not_now')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(FlutterI18n.translate(context, 'battery_tracker_add')),
        ),
      ],
    ),
  );
  if (addBattery == true && (!context.mounted || !canShow())) return false;
  await onboarding.markBatteryFeatureSeen();
  if (addBattery == true && context.mounted && canShow()) {
    if (openTracker != null) {
      await openTracker();
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => BatteryTrackerScreen(startWithScan: true, registrationEnabled: enabled)));
    }
  }
  return true;
}
