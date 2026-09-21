import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const librescootUrl = 'https://librescoot.org/';
const librescootLogoAsset = 'assets/icons/librescoot-logo.png';

/// Background the logo is drawn on; its wordmark is white, so it needs a dark
/// surface in both themes.
const librescootLogoBackground = Color(0xFF2A2D30);

/// Tells a rider whose scooter still runs the stock firmware what Librescoot
/// adds. Shown at most once per installation, and never to a rider who has
/// already connected a Librescoot scooter.
class LibrescootNotice {
  LibrescootNotice._();

  static const seenKey = 'librescootNoticeSeen';

  /// [isLibrescoot] must be a definitive verdict: null (unknown) never shows
  /// the notice, so a silent, hibernating scooter cannot trigger it.
  static bool shouldShow({
    required bool connected,
    required bool? isLibrescoot,
    required bool systemCanAnswer,
    required bool alreadySeen,
  }) =>
      connected &&
      isLibrescoot == false &&
      systemCanAnswer &&
      !alreadySeen;

  static Future<bool> alreadySeen() async =>
      (await SharedPreferencesAsync().getBool(seenKey)) ?? false;

  static Future<void> markSeen() =>
      SharedPreferencesAsync().setBool(seenKey, true);

  static Future<void> reset() =>
      SharedPreferencesAsync().remove(seenKey);
}

Future<void> showLibrescootNotice(BuildContext context) {
  const features = [
    'librescoot_notice_feature_navigation',
    'librescoot_notice_feature_updates',
    'librescoot_notice_feature_hibernation',
    'librescoot_notice_feature_alarm',
    'librescoot_notice_feature_offline',
    'librescoot_notice_feature_dashboard',
    'librescoot_notice_feature_display',
    'librescoot_notice_feature_keycards',
    'librescoot_notice_feature_lock',
    'librescoot_notice_feature_clock',
    'librescoot_notice_feature_hopon',
    'librescoot_notice_feature_trip',
    'librescoot_notice_feature_extras',
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Center(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: librescootLogoBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Image.asset(
              librescootLogoAsset,
              key: const Key('librescoot-notice-logo'),
              height: 64,
              fit: BoxFit.contain,
              semanticLabel:
                  FlutterI18n.translate(context, 'librescoot_notice_title'),
            ),
          ),
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(FlutterI18n.translate(context, 'librescoot_notice_intro')),
            const SizedBox(height: 8),
            Text(
              FlutterI18n.translate(context, 'librescoot_notice_install'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            for (final feature in features)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(FlutterI18n.translate(context, feature))),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: () => launchUrl(Uri.parse(librescootUrl),
              mode: LaunchMode.externalApplication),
          child: Text(
              FlutterI18n.translate(context, 'librescoot_notice_learn_more')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(FlutterI18n.translate(context, 'librescoot_notice_got_it')),
        ),
      ],
    ),
  );
}