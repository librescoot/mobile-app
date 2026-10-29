import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:unustasis/ui/screens/battery_tracker_screen.dart';
import 'package:unustasis/ui/theme/librescoot_theme.dart';

import '../support/inline_asset_bundle.dart';
import '../support/persistence_fakes.dart';

void main() {
  final battery = BatteryIdentity(
      serialNumber: 'T-UNU22205090007', source: BatteryIdentitySource.nfc, checkedAt: DateTime.utc(2026, 10, 27));
  late MemoryPreferences preferences;
  late SharedPreferencesAsyncPlatform? previous;

  setUp(() {
    previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = preferences = MemoryPreferences();
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = previous);

  Future<void> pump(
    WidgetTester tester,
    BatteryTrackerScreen screen, {
    Size size = const Size(1000, 1800),
    double textScale = 1,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildLibrescootTheme(brightness),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader: InlineFileTranslationLoader(basePath: 'assets/i18n', forcedLocale: locale)),
      ],
      home: screen,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(finder, 250, scrollable: scrollable);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> read(WidgetTester tester, String source) async {
    final button = find.byKey(const ValueKey('add-battery'));
    await visible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final option = find.byKey(ValueKey('battery-source-$source'));
    await visible(tester, option);
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  testWidgets('joining is primary and serial verification precedes consented sharing', (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
          readBluetooth: () async => [],
          readNfc: () async => battery,
          registrationEnabled: true,
          openBrowser: (uri) async {
            opened.add(uri);
            return true;
          },
        ));
    final join = find.byKey(const ValueKey('join-battery-tracker'));
    expect(tester.getTopLeft(join).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('add-battery'))).dy));
    expect(find.byType(SwitchListTile), findsNothing);
    expect(opened, isEmpty);
    await read(tester, 'nfc');
    expect(find.text(battery.serialNumber), findsOneWidget);
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
    expect(opened, isEmpty);
    final register = find.text('Register with the shared tracker');
    await visible(tester, register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    final proceed = find.byKey(const ValueKey('battery-register-continue'));
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    expect(tester.getTopLeft(find.byKey(const ValueKey('battery-label-verification'))).dy,
        lessThan(tester.getTopLeft(find.textContaining('Continuing opens the tracker')).dy));
    expect(tester.getTopLeft(find.text('Not now')).dy, greaterThan(tester.getTopLeft(proceed).dy));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tap(register);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    expect(opened.single, batteryRegistrationUri(battery));
    expect(opened.single.host, 'sunshine.rescoot.org');
    expect(find.text('Confirm your email and approve battery registration in your browser.'), findsOneWidget);
  });

  testWidgets('serial readings are transient, dismissible and never form a phone inventory', (tester) async {
    await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [battery]));
    await read(tester, 'bluetooth');
    expect(find.text(battery.serialNumber), findsOneWidget);
    await visible(tester, find.byTooltip('Dismiss serial'));
    await tester.tap(find.byTooltip('Dismiss serial'));
    await tester.pumpAndSettle();
    expect(find.text(battery.serialNumber), findsNothing);
    await read(tester, 'bluetooth');
    await tester.pumpWidget(const SizedBox());
    await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [battery]));
    expect(find.text(battery.serialNumber), findsNothing);
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
  });

  testWidgets('working NFC comes before unsupported BLE and only BLE has a firmware marker', (tester) async {
    await pump(tester,
        BatteryTrackerScreen(readBluetooth: () async => [], readNfc: () async => battery, bluetoothSupported: false));
    await visible(tester, find.byKey(const ValueKey('add-battery')));
    await tester.tap(find.byKey(const ValueKey('add-battery')));
    await tester.pumpAndSettle();
    final nfc = find.byKey(const ValueKey('battery-source-nfc'));
    final ble = find.byKey(const ValueKey('battery-source-bluetooth'));
    expect(tester.getTopLeft(nfc).dy, lessThan(tester.getTopLeft(ble).dy));
    expect(tester.widget<ListTile>(ble).enabled, isFalse);
    expect(find.descendant(of: ble, matching: find.text('Librescoot')), findsOneWidget);
    expect(find.descendant(of: nfc, matching: find.text('Librescoot')), findsNothing);
    expect(find.textContaining('1.4'), findsNothing);
  });

  testWidgets('email verification and management never send a scanned serial', (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [battery],
            registrationEnabled: true,
            openBrowser: (uri) async {
              opened.add(uri);
              return true;
            }));
    await read(tester, 'bluetooth');
    await visible(tester, find.byKey(const ValueKey('join-battery-tracker')));
    await tester.tap(find.byKey(const ValueKey('join-battery-tracker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify email / manage registrations'));
    await tester.pumpAndSettle();
    expect(opened, [batteryTrackerJoinUri(), batteryTrackerRegistrationsUri()]);
    expect(opened.every((uri) => uri.host == 'sunshine.rescoot.org' && !uri.hasQuery), isTrue);
  });

  testWidgets('a closed release gate blocks verification and registration until the service is deployed',
      (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [battery],
            registrationEnabled: false,
            openBrowser: (uri) async {
              opened.add(uri);
              return true;
            }));
    await read(tester, 'bluetooth');
    final registration = find
        .ancestor(
            of: find.text('Register with the shared tracker'),
            matching: find.byWidgetPredicate((widget) => widget is FilledButton))
        .first;
    expect(tester.widget<FilledButton>(registration).onPressed, isNull);
    expect(find.text('Verify email / manage registrations'), findsNothing);
    final join = find.byKey(const ValueKey('join-battery-tracker'));
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    expect(opened, isEmpty);
  });

  for (final locale in [const Locale('en'), const Locale('de')]) {
    testWidgets('firmware badge names hash capability ${locale.languageCode}', (tester) async {
      await pump(tester, BatteryTrackerScreen(readBluetooth: () async => []), locale: locale);
      final button = find.byKey(const ValueKey('add-battery'));
      await visible(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((widget) => widget is Tooltip && (widget.message?.contains('(hash=1)') ?? false)),
          findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (widget) => widget is Semantics && (widget.properties.label?.contains('(hash=1)') ?? false)),
          findsOneWidget);
      expect(find.byWidgetPredicate((widget) => widget is Tooltip && (widget.message?.contains('battery=1') ?? false)),
          findsNothing);
    });

    testWidgets('registration preparation fits narrow large text ${locale.languageCode}', (tester) async {
      await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [], readNfc: () async => battery),
          size: const Size(320, 568), textScale: 2, locale: locale, brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
      final button = find.byKey(const ValueKey('add-battery'));
      await visible(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final nfc = find.byKey(const ValueKey('battery-source-nfc'));
      await visible(tester, nfc);
      await tester.tap(nfc);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
