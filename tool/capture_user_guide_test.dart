// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:scooter_core/navigation.dart' as scooter;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/home_screen.dart';
import 'package:unustasis/ui/screens/battery_screen.dart';
import 'package:unustasis/ui/screens/ls_keycard_screen.dart';
import 'package:unustasis/ui/sheets/control_sheet.dart';
import 'package:unustasis/ui/screens/settings_screen.dart';
import 'package:unustasis/ui/theme/librescoot_theme.dart';

import '../test/support/inline_asset_bundle.dart';
import '../test/support/persistence_fakes.dart';

class _Ble extends Fake implements FlutterBluePlusMockable {
  @override
  Stream<bool> get isScanning => const Stream.empty();
  @override
  bool get isScanningNow => true;
  @override
  Future<void> stopScan() async {}
}

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(path));
  await loader.load();
}

void main() {
  testWidgets('capture user guide screens in demo mode', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await _loadFont('Inter', 'assets/fonts/Inter-Regular.ttf');
      await _loadFont('Abel', 'assets/fonts/Abel-Regular.ttf');
      await _loadFont('icomoon', 'assets/fonts/icomoon.ttf');
      await _loadFont('KodeMono', 'assets/fonts/KodeMono-Regular.ttf');
      await _loadFont('MaterialIcons', 'fonts/MaterialIcons-Regular.otf');
    });
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences()..bools['osmConsent'] = true;
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (_) async => <String>[],
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (_) async => false,
    );
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    final service = ScooterService(_Ble(), initializeRuntime: false, isInBackgroundService: true)..addDemoData();
    service.savedScooters['12345']!.color = 7;
    service.identity.color = 7;
    service.identity.supportsPhoneKeyManagement = false;
    await service.navigation.saveFavorite(scooter.NavigationDestination(
      location: const LatLng(52.5163, 13.3777),
      name: 'Brandenburger Tor',
    ));
    await service.navigation.saveFavorite(scooter.NavigationDestination(
      location: const LatLng(52.5096, 13.3759),
      name: 'Potsdamer Platz',
    ));
    addTearDown(service.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.light,
        child: RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildLibrescootTheme(Brightness.light),
            localizationsDelegates: [
              FlutterI18nDelegate(
                  translationLoader: InlineFileTranslationLoader(
                basePath: 'assets/i18n',
                fallbackFile: 'de',
                forcedLocale: const Locale('de'),
              ))
            ],
            home: const HomeScreen(forceOpen: true, batteryTrackerEnabled: false),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage('images/scooter/base_7.webp'), boundaryKey.currentContext!);
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump(const Duration(seconds: 1));
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('docs/screenshots').create(recursive: true);
        await File('docs/screenshots/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    expect(find.text('Demo Scooter'), findsOneWidget);
    await capture('start');
    await tester.dragFrom(const Offset(210, 820), const Offset(0, -300));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Brandenburger Tor'), findsOneWidget);
    expect(find.text('Potsdamer Platz'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await capture('navigation');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ControlSheet), findsOneWidget);
    await capture('steuerung');
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('≈69'));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BatteryScreen), findsOneWidget);
    await capture('akkus');
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SettingsScreen), findsOneWidget);
    await capture('einstellungen');
    await tester.tap(find.text('Keycards'));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LsKeycardScreen), findsOneWidget);
    await capture('keycards');
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(find.text('Mobilfunk-APN'), 350,
        scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    await tester.drag(find.byType(SettingsScreen), const Offset(0, 180));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Mobilfunk-APN'), findsOneWidget);
    await capture('mobilfunk-apn');
  });
}
