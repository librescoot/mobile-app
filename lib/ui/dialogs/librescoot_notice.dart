import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const librescootUrl = 'https://librescoot.org/';
const librescootDownloadsUrl = 'https://downloads.librescoot.org/';
const librescootLogoAsset = 'assets/icons/librescoot-logo.png';

/// Dark backdrop for the white wordmark.
const librescootLogoBackground = Color(0xFF2A2D30);

/// One-time notice about Librescoot, for a scooter still on stock firmware.
///
/// Shown at most once per installation, and never once a Librescoot scooter has
/// been connected.
class LibrescootNotice {
  LibrescootNotice._();

  static const seenKey = 'librescootNoticeSeen';

  /// Null [isLibrescoot] never shows the notice, so a silent, hibernating
  /// scooter cannot trigger it. A rider with a saved Librescoot scooter is
  /// already a Librescoot rider and is never shown it.
  static bool shouldShow({
    required bool connected,
    required bool? isLibrescoot,
    required bool systemCanAnswer,
    required bool alreadySeen,
    required bool hasLibrescootScooter,
  }) =>
      connected &&
      isLibrescoot == false &&
      systemCanAnswer &&
      !alreadySeen &&
      !hasLibrescootScooter;

  static Future<bool> alreadySeen() async =>
      (await SharedPreferencesAsync().getBool(seenKey)) ?? false;

  static Future<void> markSeen() =>
      SharedPreferencesAsync().setBool(seenKey, true);

  static Future<void> reset() =>
      SharedPreferencesAsync().remove(seenKey);
}

Future<void> showLibrescootNotice(BuildContext context,
        {bool fromStockScooter = false}) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          _LibrescootNoticeDialog(fromStockScooter: fromStockScooter),
    );

class _LibrescootNoticeDialog extends StatefulWidget {
  const _LibrescootNoticeDialog({required this.fromStockScooter});

  /// True only when the notice follows a verdict from the connected scooter,
  /// whose intro can then name the software it runs.
  final bool fromStockScooter;

  @override
  State<_LibrescootNoticeDialog> createState() =>
      _LibrescootNoticeDialogState();
}

class _LibrescootNoticeDialogState extends State<_LibrescootNoticeDialog> {
  static const _features = [
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

  final ScrollController _scroll = ScrollController();
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateScrollHint);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollHint());
  }

  @override
  void dispose() {
    _scroll.removeListener(_updateScrollHint);
    _scroll.dispose();
    super.dispose();
  }

  void _updateScrollHint() {
    if (!_scroll.hasClients) return;
    final more = _scroll.position.extentAfter > 4;
    if (more != _hasMore) setState(() => _hasMore = more);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Container(
        width: double.infinity,
        color: librescootLogoBackground,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 64),
            child: Image.asset(
              librescootLogoAsset,
              key: const Key('librescoot-notice-logo'),
              fit: BoxFit.contain,
              semanticLabel:
                  FlutterI18n.translate(context, 'librescoot_notice_title'),
            ),
          ),
        ),
      ),
      content: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _updateScrollHint();
              return false;
            },
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(FlutterI18n.translate(
                      context,
                      widget.fromStockScooter
                          ? 'librescoot_notice_intro'
                          : 'librescoot_notice_intro_menu')),
                  const SizedBox(height: 12),
                  for (final feature in _features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  FlutterI18n.translate(context, feature))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Divider(height: 24, color: colors.outlineVariant),
                  InkWell(
                    onTap: () => launchUrl(
                        Uri.parse(librescootDownloadsUrl),
                        mode: LaunchMode.externalApplication),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.download_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              FlutterI18n.translate(
                                  context, 'librescoot_notice_install'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.open_in_new_rounded,
                              size: 16, color: colors.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_hasMore)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.surface.withValues(alpha: 0),
                        colors.surface,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_hasMore)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Icon(Icons.keyboard_double_arrow_down,
                    size: 18, color: colors.onSurfaceVariant),
              ),
            ),
        ],
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
    );
  }
}