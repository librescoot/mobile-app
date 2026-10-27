import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:unustasis/service/battery_tracker_store.dart';
import 'package:unustasis/ui/screens/battery_tracker_screen.dart';

import '../support/inline_asset_bundle.dart';

void main() {
  final battery = BatteryIdentity(
      serialNumber: 'T-UNU22205090007', source: BatteryIdentitySource.nfc, checkedAt: DateTime.utc(2026, 10, 27));

  Future<void> pump(WidgetTester tester, BatteryTrackerScreen screen) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader: InlineFileTranslationLoader(basePath: 'assets/i18n', forcedLocale: const Locale('en')))
      ],
      home: screen,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('identification is local and browser handoff requires explicit serial verification', (tester) async {
    final opened = <Uri>[];
    var writes = 0;
    final store = BatteryTrackerStore(read: () async => null, write: (_) async => writes++);
    await pump(
        tester,
        BatteryTrackerScreen(
          store: store,
          readBluetooth: () async => [],
          readNfc: () async => battery,
          openRegistration: (uri) async {
            opened.add(uri);
            return true;
          },
        ));
    await tester.tap(find.text('Tap a battery NFC tag'));
    await tester.pumpAndSettle();
    expect(find.text(battery.serialNumber), findsOneWidget);
    expect(writes, 0);
    expect(opened, isEmpty);
    await tester.tap(find.text('Register on rescoot.org'));
    await tester.pumpAndSettle();
    final proceed = find.widgetWithText(FilledButton, 'Continue to rescoot.org');
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tap(find.text('Register on rescoot.org'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    expect(opened.single, batteryRegistrationUri(battery));
    expect(find.text('Complete registration and account confirmation in your browser.'), findsOneWidget);
  });

  testWidgets('local opt-in persists only future checks and forget removes the entry', (tester) async {
    var writes = 0;
    final store = BatteryTrackerStore(read: () async => null, write: (_) async => writes++);
    await pump(tester, BatteryTrackerScreen(store: store, readBluetooth: () async => [battery]));
    await tester.tap(find.text('Read scooter battery serials'));
    await tester.pumpAndSettle();
    expect(store.batteries, isEmpty);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(store.batteries, isEmpty);
    await tester.tap(find.text('Read scooter battery serials'));
    await tester.pumpAndSettle();
    expect(store.batteries.single.serialNumber, battery.serialNumber);
    await tester.tap(find.text('Forget on this phone'));
    await tester.pumpAndSettle();
    expect(store.batteries, isEmpty);
    expect(find.text(battery.serialNumber), findsNothing);
    expect(writes, 3);
  });
}
