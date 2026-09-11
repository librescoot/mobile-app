import 'dart:async';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/onboarding_permissions.dart';
import 'package:unustasis/service/onboarding_preferences.dart';
import 'package:unustasis/ui/screens/onboarding_screen.dart';

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool scanning = false;
  @override
  bool connected = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PermissionController implements OnboardingPermissionController {
  _PermissionController(this.summary);
  OnboardingPermissionSummary summary;
  int requests = 0;
  int settingsOpens = 0;

  @override
  Future<OnboardingPermissionSummary> requestPermissions() async {
    requests++;
    return summary;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpens++;
    return true;
  }
}

class _Preferences extends Fake implements SharedPreferencesAsync {
  _Preferences({this.failVersionWrite = false, this.boolWriteGate});

  final values = <String, Object>{};
  final writes = <String>[];
  final bool failVersionWrite;
  final Completer<void>? boolWriteGate;

  @override
  Future<int?> getInt(String key) async => values[key] as int?;
  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;
  @override
  Future<void> setBool(String key, bool value) async {
    await boolWriteGate?.future;
    writes.add('$key=$value');
    values[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    if (failVersionWrite) throw StateError('version write failed');
    writes.add('$key=$value');
    values[key] = value;
  }
}

OnboardingPermissionSummary _summary({
  bool nearby = true,
  bool notifications = false,
  bool location = false,
  bool locationRequired = false,
  bool settings = false,
}) =>
    OnboardingPermissionSummary(
      nearbyDevicesGranted: nearby,
      notificationsGranted: notifications,
      locationGranted: location,
      locationRequiredForScanning: locationRequired,
      canOpenSettings: settings,
    );

Future<void> _mount(
  WidgetTester tester,
  _Service service,
  _PermissionController permissions,
  _Preferences preferences, {
  Size size = const Size(800, 1200),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.light,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          localizationsDelegates: [
            FlutterI18nDelegate(
              translationLoader: FileTranslationLoader(
                basePath: 'assets/i18n',
                fallbackFile: 'en',
                forcedLocale: const Locale('en'),
              ),
            ),
          ],
          home: OnboardingScreen(
            permissionController: permissions,
            onboardingPreferences: OnboardingPreferences(preferences: preferences),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('fresh setup requires nearby access and an explicit online-services choice', (tester) async {
    final service = _Service();
    final permissions = _PermissionController(_summary());
    final preferences = _Preferences();
    addTearDown(service.dispose);
    await _mount(tester, service, permissions, preferences);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Before you connect'), findsOneWidget);
    expect(find.textContaining('Not reviewed yet'), findsNWidgets(3));

    await tester.tap(find.text('REVIEW PERMISSIONS'));
    await tester.pump(const Duration(seconds: 1));
    expect(permissions.requests, 1);
    expect(find.text('CONTINUE'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Online place services'), findsOneWidget);
    expect(find.text('SAVE AND CONTINUE'), findsNothing);
    expect(preferences.writes, isEmpty);
    await tester.tap(find.text('Keep online place services off'));
    await tester.pump();
    await tester.tap(find.text('SAVE AND CONTINUE'));
    await tester.pump(const Duration(seconds: 1));
    expect(preferences.writes, [
      'osmConsent=false',
      '$firstRunOnboardingVersionKey=$currentFirstRunOnboardingVersion',
    ]);
    expect(find.text('Find scooter'), findsOneWidget);
  });

  testWidgets('denied required access offers Settings and cannot advance', (tester) async {
    final service = _Service();
    final permissions = _PermissionController(_summary(locationRequired: true, settings: true));
    final preferences = _Preferences();
    addTearDown(service.dispose);
    await _mount(tester, service, permissions, preferences);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('REVIEW PERMISSIONS'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Required access is off'), findsOneWidget);
    expect(find.text('CONTINUE'), findsNothing);
    await tester.tap(find.text('Open system settings'));
    expect(permissions.settingsOpens, 1);

    permissions.summary = _summary();
    await tester.tap(find.text('REVIEW AGAIN'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('CONTINUE'), findsOneWidget);
  });

  testWidgets('an earlier consent choice is restored before onboarding completes', (tester) async {
    final service = _Service();
    final permissions = _PermissionController(_summary());
    final preferences = _Preferences()..values['osmConsent'] = true;
    addTearDown(service.dispose);
    await _mount(tester, service, permissions, preferences);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('REVIEW PERMISSIONS'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('SAVE AND CONTINUE'), findsOneWidget);
    expect(preferences.writes, isEmpty);
  });

  testWidgets('permission and privacy steps scroll at narrow width and large text', (tester) async {
    final service = _Service();
    final permissions = _PermissionController(_summary());
    final preferences = _Preferences();
    addTearDown(service.dispose);
    await _mount(
      tester,
      service,
      permissions,
      preferences,
      size: const Size(320, 568),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('REVIEW PERMISSIONS'));
    await tester.tap(find.text('REVIEW PERMISSIONS'));
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('CONTINUE'));
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Online place services'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('online choice cannot change while its save is in flight', (tester) async {
    final service = _Service();
    final permissions = _PermissionController(_summary());
    final gate = Completer<void>();
    final preferences = _Preferences(boolWriteGate: gate);
    addTearDown(service.dispose);
    await _mount(tester, service, permissions, preferences);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('REVIEW PERMISSIONS'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Enable online place services'));
    await tester.pump();
    await tester.tap(find.text('SAVE AND CONTINUE'));
    await tester.pump();

    final choices = tester.widgetList<RadioListTile<bool>>(find.byType(RadioListTile<bool>));
    expect(choices.every((choice) => choice.enabled == false), true);
    await tester.tap(find.text('Keep online place services off'), warnIfMissed: false);
    gate.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(preferences.values['osmConsent'], true);
    expect(find.text('Find scooter'), findsOneWidget);
  });

  testWidgets('a failed completion write re-enables the choice controls', (tester) async {
    final service = _Service();
    final permissions = _PermissionController(_summary());
    final preferences = _Preferences(failVersionWrite: true);
    addTearDown(service.dispose);
    await _mount(tester, service, permissions, preferences);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('REVIEW PERMISSIONS'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Keep online place services off'));
    await tester.pump();
    await tester.tap(find.text('SAVE AND CONTINUE'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Your choice could not be saved. Please try again.'), findsOneWidget);
    final choices = tester.widgetList<RadioListTile<bool>>(find.byType(RadioListTile<bool>));
    expect(choices.every((choice) => choice.enabled == true), true);
    expect(await OnboardingPreferences(preferences: preferences).isCurrent(), false);
  });

  testWidgets('current onboarding version skips prompts without overwriting choices', (tester) async {
    final service = _Service();
    final permissions = _PermissionController(_summary());
    final preferences = _Preferences()
      ..values[firstRunOnboardingVersionKey] = currentFirstRunOnboardingVersion
      ..values['osmConsent'] = true;
    addTearDown(service.dispose);
    await _mount(tester, service, permissions, preferences);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Find scooter'), findsOneWidget);
    expect(permissions.requests, 0);
    expect(preferences.writes, isEmpty);
  });

  test('completion marker is never written before the consent choice', () async {
    final preferences = _Preferences(failVersionWrite: true);
    final onboarding = OnboardingPreferences(preferences: preferences);

    await expectLater(
      onboarding.complete(onlineServicesEnabled: false),
      throwsStateError,
    );
    expect(preferences.values['osmConsent'], false);
    expect(preferences.values[firstRunOnboardingVersionKey], isNull);
    expect(await onboarding.isCurrent(), false);
  });
}
