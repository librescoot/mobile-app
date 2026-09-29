import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/ls_keycard_screen.dart';
import 'package:unustasis/ui/screens/settings_screen.dart';

import '../support/persistence_fakes.dart';

class _Ble extends Fake implements FlutterBluePlusMockable {
  @override
  Stream<bool> get isScanning => const Stream.empty();
  @override
  bool get isScanningNow => true;
  @override
  Future<void> stopScan() async {}
}

Future<void> _mount(WidgetTester tester, ScooterService service) async {
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
    value: service,
    child: EasyDynamicThemeWidget(
      initialThemeMode: ThemeMode.light,
      child: MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
            translationLoader: FileTranslationLoader(
              basePath: 'assets/i18n',
              fallbackFile: 'en',
              forcedLocale: const Locale('en'),
            ),
          ),
        ],
        home: const SettingsScreen(),
      ),
    ),
  ));
  for (var attempt = 0; attempt < 20 && find.byType(SettingsScreen).evaluate().isEmpty; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('demo settings open working keycard management without NFC or persisted demo cards', (tester) async {
    final previousPrefs = SharedPreferencesAsyncPlatform.instance;
    final prefs = MemoryPreferences();
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = prefs;
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
    addTearDown(() {
      SharedPreferencesAsyncPlatform.instance = previousPrefs;
    });
    final service = ScooterService(_Ble(), initializeRuntime: false, isInBackgroundService: true)..addDemoData();
    addTearDown(service.dispose);
    await _mount(tester, service);

    await tester.scrollUntilVisible(find.text('Keycards'), 250);
    await tester.pumpAndSettle();
    expect(find.text('Stored keycards: 2'), findsOneWidget);
    await tester.tap(find.text('Keycards'));
    await tester.pumpAndSettle();
    expect(find.byType(LsKeycardScreen), findsOneWidget);
    expect(await service.actions.listKeycards(), ['D3A00001', 'D3A00002']);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(await service.actions.listKeycards(), ['D3A00001', 'D3A00002', 'D3A00003']);

    final firstCard = find.byType(KeycardCard).first;
    await tester.ensureVisible(firstCard);
    await tester.tap(find.descendant(of: firstCard, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keycard-color-10')));
    await tester.pumpAndSettle();
    expect(prefs.values, isNot(contains('keycard_colors')));

    await tester.tap(find.descendant(of: firstCard, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card icon'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keycard-icon-flame')));
    await tester.pumpAndSettle();
    expect(prefs.values, isNot(contains('keycard_icons')));

    await tester.tap(find.descendant(of: firstCard, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Demo guest');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await service.actions.listKeyAliases())['card:D3A00001'], 'Demo guest');
    expect(prefs.values, isNot(contains('keycard_aliases')));

    await tester.tap(find.descendant(of: firstCard, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await service.actions.listKeycards(), ['D3A00002', 'D3A00003']);

    service.removeDemoData();
    expect(service.store.scooters, isEmpty);
  });
}
