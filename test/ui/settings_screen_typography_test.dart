import 'dart:async';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/scooter_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/state/vehicle_status.dart';
import 'package:unustasis/ui/screens/settings_screen.dart';
import 'package:unustasis/ui/presentation/settings_duration.dart';
import 'package:unustasis/ui/widgets/header.dart';
import 'package:unustasis/ui/widgets/settings_dropdown_tile.dart';

import 'settings_help_row_theme_test.dart' show renderedStyle, rowTestTheme;

final class _Preferences extends SharedPreferencesAsyncPlatform {
  final values = <String, bool>{};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async => values[key];
  @override
  Future<void> setBool(String key, bool value, SharedPreferencesOptions options) async => values[key] = value;
}

class _Actions implements ScooterActions {
  final reads = <String>[];
  final settingValues = <String, String>{};
  final standbyWrites = <Duration>[];
  final hibernateWrites = <Duration>[];
  Completer<void>? readGate;
  Completer<void>? writeGate;
  @override
  Future<int?> countKeycards() async => 0;
  @override
  Future<String?> getSetting(String key) async {
    reads.add(key);
    await readGate?.future;
    return settingValues[key] ?? '0';
  }

  @override
  Future<void> setAutoStandbyTime(Duration time) async {
    standbyWrites.add(time);
    await writeGate?.future;
  }

  @override
  Future<void> setAutoHibernateTime(Duration time) async {
    hibernateWrites.add(time);
    await writeGate?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingActions extends _Actions {
  @override
  Future<int?> countKeycards() => Future.error(TimeoutException('extended channel'));

  @override
  Future<String?> getSetting(String key) => Future.error(TimeoutException('extended channel'));
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  final identity = ScooterIdentity()..isLibrescoot = true;
  @override
  final vehicle = VehicleStatus();
  @override
  final _Actions actions = _Actions();
  @override
  bool connected = true;
  void setConnection(bool value) {
    connected = value;
    notifyListeners();
  }

  @override
  bool get alarmAvailable => false;
  @override
  bool get otaAvailable => false;
  @override
  bool get autoUnlock => false;
  @override
  int get autoUnlockThreshold => -65;
  @override
  bool openSeatOnUnlock = false;
  @override
  bool hazardLocking = false;
  @override
  void setOpenSeatOnUnlock(bool value) => openSeatOnUnlock = value;
  @override
  void setHazardLocking(bool value) => hazardLocking = value;
  @override
  Future<String?> getCellularApn() async => '';
  @override
  Future<bool?> getBatteryKeepActive() async => false;
  @override
  Future<bool?> getAlarmEnabled() async => false;
  @override
  Future<bool?> getAlarmHonk() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingService extends _Service {
  @override
  final _FailingActions actions = _FailingActions();

  @override
  Future<String?> getCellularApn() => Future.error(TimeoutException('extended channel'));
  @override
  Future<bool?> getBatteryKeepActive() => Future.error(TimeoutException('extended channel'));
  @override
  Future<bool?> getAlarmEnabled() => Future.error(TimeoutException('extended channel'));
  @override
  Future<bool?> getAlarmHonk() => Future.error(TimeoutException('extended channel'));
}

Widget _screen(_Service service, {String locale = 'en', double scale = 1, Brightness brightness = Brightness.light}) =>
    ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.light,
        child: MaterialApp(
          theme: rowTestTheme(brightness),
          localizationsDelegates: [
            FlutterI18nDelegate(
                translationLoader: FileTranslationLoader(
              basePath: 'assets/i18n',
              fallbackFile: 'en',
              forcedLocale: Locale(locale),
            ))
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const SettingsScreen(),
        ),
      ),
    );

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 180, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Finder _timer(int index) => find.byWidgetPredicate((widget) =>
    widget is SettingsDropdownTile<int> &&
    (widget.leading as Icon).icon == (index == 0 ? Icons.hourglass_bottom_rounded : Icons.bedtime_outlined));
Finder _button(Finder row) => find.descendant(of: row, matching: find.byType(DropdownButton<int>));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = _Preferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (call) async => <String>[],
    );
  });

  testWidgets('offline scooter settings remain visible, disabled and never loading', (tester) async {
    final service = _Service()..connected = false;
    addTearDown(service.dispose);
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SettingsScreen));
    for (final key in [
      'ls_keycard_title',
      'ls_settings_auto_lock_title',
      'ls_settings_auto_hibernate_title',
      'ls_scheduled_hibernation_title',
      'ls_settings_battery_keep_active_title',
      'ls_settings_apn_title',
      'ls_settings_ota_title',
      'ls_settings_update_mode_title'
    ]) {
      final title = find.text(FlutterI18n.translate(context, key));
      await _show(tester, title);
      final tile = tester.widget<ListTile>(find.ancestor(of: title, matching: find.byType(ListTile)).first);
      expect(tile.enabled, isFalse, reason: key);
      expect(tile.onTap, isNull, reason: key);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    expect(service.actions.reads, isEmpty);
    expect(service.actions.standbyWrites, isEmpty);
    expect(service.actions.hibernateWrites, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed extended reads settle as unavailable instead of spinning forever', (tester) async {
    final service = _FailingService();
    addTearDown(service.dispose);
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    final unavailable = find.text('Unavailable on this connection');
    await _show(tester, unavailable);
    expect(unavailable, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnect removes in-flight loading and reconnect reads settings again', (tester) async {
    final service = _Service();
    final gate = Completer<void>();
    service.actions.readGate = gate;
    addTearDown(service.dispose);
    await tester.pumpWidget(_screen(service));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(service.actions.reads.length, 2);
    service.setConnection(false);
    await tester.pumpAndSettle();
    final title =
        find.text(FlutterI18n.translate(tester.element(find.byType(SettingsScreen)), 'ls_settings_auto_lock_title'));
    await _show(tester, title);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.ancestor(of: title, matching: find.byType(ListTile)).first).enabled, isFalse);
    service.setConnection(true);
    await tester.pumpAndSettle();
    await _show(tester, _timer(0));
    expect(service.actions.reads.length, 4);
    expect(tester.widget<DropdownButton<int>>(_button(_timer(0))).onChanged, isNotNull);
    expect(service.actions.standbyWrites, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual Settings switch row hierarchy, flat heading spacing and callbacks', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    expect(renderedStyle(tester, 'Auto-unlock').fontSize, 18);
    expect(renderedStyle(tester, 'Auto-unlock').fontWeight, FontWeight.w400);
    expect(renderedStyle(tester, 'Unlock the scooter when your phone is nearby and the app is open.').fontSize, 14);
    final headingBottom = tester.getBottomLeft(find.byType(Header).first).dy;
    final rowTop = tester.getTopLeft(find.byType(SwitchListTile).first).dy;
    expect(rowTop, headingBottom);
    expect(find.byType(Card), findsNothing);
    await tester.tap(find.text('Open seatbox on unlock'));
    await tester.pumpAndSettle();
    expect(service.openSeatOnUnlock, isTrue);
    final row = find.ancestor(of: find.text('Open seatbox on unlock'), matching: find.byType(SwitchListTile));
    expect(tester.widget<SwitchListTile>(row).value, isTrue);
    expect(tester.getSemantics(row).getSemanticsData().label, contains('Open seatbox on unlock'));
    await tester.tap(find.text('Open seatbox on unlock'));
    await tester.pumpAndSettle();
    expect(service.openSeatOnUnlock, isFalse);
    expect(service.actions.reads, [lsKeyAutoStandbySeconds, lsKeyHibernateTimer]);
    final onlineLocation = find.widgetWithText(SwitchListTile, 'Online location services');
    await _show(tester, onlineLocation);
    expect(tester.widget<SwitchListTile>(onlineLocation).value, isFalse);
    expect(find.text('Privacy policy'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening and scrolling Settings tolerates non-preset scooter timers without writing', (tester) async {
    final service = _Service();
    service.actions.settingValues.addAll({lsKeyAutoStandbySeconds: '900', lsKeyHibernateTimer: '432000'});
    addTearDown(service.dispose);
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    for (final index in [0, 1]) {
      await _show(tester, _timer(index));
      expect(tester.takeException(), isNull);
    }
    final hibernation = tester.widget<DropdownButton<int>>(_button(_timer(1)));
    expect(hibernation.value, 432000);
    final custom = hibernation.items!.singleWhere((item) => item.value == 432000);
    expect((custom.child as Text).data, '5 days');
    expect(custom.enabled, isTrue);
    expect(service.actions.standbyWrites, isEmpty);
    expect(service.actions.hibernateWrites, isEmpty);
  });

  testWidgets('custom durations preserve mixed-unit seconds and localize the current value', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SettingsScreen));
    expect(formatSettingsDuration(context, 125), '2 minutes 5 seconds');
    expect(formatSettingsDuration(context, 90061), '1 day 1 hour 1 minute 1 second');
    expect(formatSettingsDuration(context, 0), 'Never');
    await tester.pumpWidget(_screen(service, locale: 'de'));
    await tester.pumpAndSettle();
    expect(formatSettingsDuration(tester.element(find.byType(SettingsScreen)), 432000), '5 Tage');
  });

  testWidgets('actual timers retain options, immediate writes, loading and in-flight disabled states', (tester) async {
    final service = _Service();
    service.actions.readGate = Completer<void>();
    addTearDown(service.dispose);
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_screen(service));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(find.byType(SettingsDropdownTile<int>).first, 200);
    await tester.pump();
    expect(tester.widget<DropdownButton<int>>(_button(_timer(0))).onChanged, isNull);
    service.actions.readGate!.complete();
    await tester.pumpAndSettle();
    for (final index in [0, 1]) {
      final row = _timer(index);
      await _show(tester, row);
      final button = _button(row);
      final dropdown = tester.widget<DropdownButton<int>>(button);
      final values = index == 0 ? [0, 180, 300, 600, 900] : [0, 3600, 86400, 259200, 604800, 1209600];
      expect(dropdown.items!.map((item) => item.value), values);
      expect(dropdown.value, 0);
      expect(tester.getSize(button).width, lessThan(128));
      expect(DropdownButtonHideUnderline.at(tester.element(button)), isTrue);
      service.actions.writeGate = Completer<void>();
      final choice = dropdown.items!.last;
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text((choice.child as Text).data!).last);
      await tester.pump();
      expect(tester.widget<DropdownButton<int>>(button).onChanged, isNull);
      expect(tester.widget<DropdownButton<int>>(button).value, 0);
      expect(index == 0 ? service.actions.standbyWrites : service.actions.hibernateWrites,
          [Duration(seconds: choice.value!)]);
      service.actions.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<int>>(button).value, choice.value);
      expect(tester.widget<DropdownButton<int>>(button).onChanged, isNotNull);
      expect(tester.takeException(), isNull);
    }
  });

  for (final locale in ['en', 'de', 'fr', 'nl', 'pi']) {
    for (final (width, scale, brightness) in [
      (412.0, 1.0, Brightness.light),
      (320.0, 2.0, Brightness.dark),
    ]) {
      testWidgets('actual Settings values/rows $locale $width dp $scale $brightness', (tester) async {
        final service = _Service();
        addTearDown(service.dispose);
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_screen(service, locale: locale, scale: scale, brightness: brightness));
        await tester.pumpAndSettle();
        for (final index in [0, 1]) {
          await _show(tester, _timer(index));
          final button = _button(_timer(index));
          final items = tester.widget<DropdownButton<int>>(button).items!;
          for (final item in items) {
            // Exercise the actual callback and state rebuild for every allowed value.
            tester.widget<DropdownButton<int>>(button).onChanged!(item.value);
            await tester.pumpAndSettle();
            expect(tester.widget<DropdownButton<int>>(button).value, item.value);
            expect(tester.takeException(), isNull);
          }
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text((items.first.child as Text).data!).last);
          await tester.pumpAndSettle();
          expect(tester.widget<DropdownButton<int>>(button).value, 0);
        }
        // Include lower-screen controls (language and theme) in overflow coverage.
        await _show(tester, find.byType(DropdownButtonFormField<Locale>));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
