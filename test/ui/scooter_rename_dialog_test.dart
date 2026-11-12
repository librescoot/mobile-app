import 'package:flutter/material.dart';
import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/scooter_screen.dart';

import '../support/inline_asset_bundle.dart';
import '../support/persistence_fakes.dart';

class _Ble extends Fake implements FlutterBluePlusMockable {
  @override
  Stream<bool> get isScanning => const Stream.empty();
  @override
  bool get isScanningNow => true;
  @override
  Future<void> stopScan() async {}
}

void main() {
  for (final card in [true, false]) {
    testWidgets('rename scooter using ${card ? 'card' : 'list'} dialog', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final previousPrefs = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previousPrefs);
      FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
      final service = ScooterService(_Ble(), initializeRuntime: false, isInBackgroundService: true)..addDemoData();
      addTearDown(service.dispose);
      final scooter = service.savedScooters['12345']!;
      await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
        value: service,
        child: MaterialApp(
          localizationsDelegates: [
            FlutterI18nDelegate(
              translationLoader: InlineFileTranslationLoader(
                basePath: 'assets/i18n',
                fallbackFile: 'en',
                forcedLocale: const Locale('en'),
              ),
            ),
          ],
          home: Scaffold(
            body: card
                ? SavedScooterCard(
                    savedScooter: scooter,
                    status: ScooterTileStatus.disconnected,
                    selected: true,
                    single: true,
                    forceHover: false,
                    onListChanged: () {})
                : SavedScooterListItem(
                    savedScooter: scooter,
                    status: ScooterTileStatus.disconnected,
                    selected: true,
                    single: true,
                    onListChanged: () {}),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename scooter'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Julian');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(scooter.name, 'Julian');
      expect(tester.takeException(), isNull);
    });
  }
}
