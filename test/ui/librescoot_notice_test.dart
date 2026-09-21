import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:unustasis/ui/dialogs/librescoot_notice.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  final values = <String, bool>{};
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async =>
      values[key];
  @override
  Future<void> setBool(
          String key, bool value, SharedPreferencesOptions options) async =>
      values[key] = value;
  @override
  Future<void> clear(ClearPreferencesParameters parameters,
      SharedPreferencesOptions options) async {
    values.removeWhere(
        (key, _) => parameters.filter.allowList?.contains(key) ?? true);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: [
      FlutterI18nDelegate(
        translationLoader: FileTranslationLoader(
          basePath: 'assets/i18n',
          fallbackFile: 'en',
          forcedLocale: const Locale('en'),
        ),
      ),
    ],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showLibrescootNotice(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a definitive stock verdict while the system answers is the only show',
      () {
    bool show({bool connected = true, bool? stock = false, bool awake = true, bool seen = false}) =>
        LibrescootNotice.shouldShow(
          connected: connected,
          isLibrescoot: stock,
          systemCanAnswer: awake,
          alreadySeen: seen,
        );

    expect(show(), isTrue);
    expect(show(stock: null), isFalse, reason: 'unknown is not stock');
    expect(show(stock: true), isFalse);
    expect(show(connected: false), isFalse);
    expect(show(awake: false), isFalse, reason: 'hibernating is not stock');
    expect(show(seen: true), isFalse);
  });

  test('the seen flag round-trips', () async {
    SharedPreferencesAsyncPlatform.instance = _Preferences();
    expect(await LibrescootNotice.alreadySeen(), isFalse);
    await LibrescootNotice.markSeen();
    expect(await LibrescootNotice.alreadySeen(), isTrue);
    await LibrescootNotice.reset();
    expect(await LibrescootNotice.alreadySeen(), isFalse);
  });

  testWidgets('lists what Librescoot adds and offers the website', (tester) async {
    await _open(tester);

    expect(find.byKey(const Key('librescoot-notice-logo')), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(13));
    expect(
        find.textContaining('about 20 minutes'), findsOneWidget);
    expect(find.text("Navigation with offline maps on the scooter's display"),
        findsOneWidget);
    expect(find.text('Built-in alarm'), findsOneWidget);
    expect(find.text('Hop-on for short stops'), findsOneWidget);
    expect(find.textContaining('WireGuard VPN'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Learn more'), findsOneWidget);
    expect(
        tester.getSize(find.widgetWithText(TextButton, 'Learn more')).height,
        tester.getSize(find.widgetWithText(FilledButton, 'Got it')).height);

    await tester.tap(find.widgetWithText(FilledButton, 'Got it'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('librescoot-notice-logo')), findsNothing);
  });
}