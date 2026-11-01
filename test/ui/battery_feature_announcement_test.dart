import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/service/onboarding_preferences.dart';
import 'package:unustasis/ui/dialogs/battery_feature_announcement.dart';

import '../support/inline_asset_bundle.dart';
import '../support/persistence_fakes.dart';

void main() {
  late MemoryPreferences preferences;
  late SharedPreferencesAsyncPlatform? previous;
  var opened = 0;
  var finished = false;

  setUp(() {
    previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = preferences = MemoryPreferences();
    finished = false;
    opened = 0;
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = previous);

  Future<void> mount(WidgetTester tester,
      {double scale = 1, Size size = const Size(800, 1200), bool enabled = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader: InlineFileTranslationLoader(basePath: 'assets/i18n', forcedLocale: const Locale('en')))
      ],
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () async {
                    finished = false;
                    await showBatteryFeatureAnnouncement(context, enabled: enabled, openTracker: () async {
                      opened++;
                    });
                    finished = true;
                  },
                  child: const Text('Show announcement')))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show announcement'));
    await tester.pumpAndSettle();
  }

  testWidgets('existing-user introduction is shown once without any battery collection or upload', (tester) async {
    await mount(tester);
    expect(find.text('New for your batteries'), findsOneWidget);
    expect(preferences.values, isEmpty);
    expect(preferences.bools, isEmpty);
    expect(opened, 0);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(preferences.ints[batteryFeatureOnboardingVersionKey], currentBatteryFeatureOnboardingVersion);
    expect(preferences.values, isEmpty);
    expect(preferences.bools, isEmpty);
    await tester.tap(find.text('Show announcement'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('adding starts the native flow instead of opening email signup', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Add a battery'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(opened, 1);
    expect(finished, isTrue);
    expect(preferences.values, isEmpty);
    expect(find.textContaining('registered successfully'), findsNothing);
  });

  testWidgets('unavailable email verification is not announced or marked seen', (tester) async {
    await mount(tester, enabled: false);
    expect(find.byType(AlertDialog), findsNothing);
    expect(preferences.ints[batteryFeatureOnboardingVersionKey], isNull);
    expect(opened, 0);
  });

  testWidgets('announcement remains scrollable at narrow width and large text', (tester) async {
    await mount(tester, size: const Size(320, 568), scale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
