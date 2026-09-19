import 'dart:async';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:unustasis/domain/alarm_status.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/ui/screens/home_screen.dart';

class _Connection extends Fake implements SessionConnection {
  @override
  bool isCurrent = true;
  @override
  String id = 'A';
  @override
  int generation = 1;
}

class _Session extends Fake implements ScooterSession {
  @override
  SessionConnection? currentConnection = _Connection();
}

class _Actions extends Fake implements ScooterActions {
  @override
  final _Session session = _Session();
  @override
  void invalidate() {}
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  final _Actions actions = _Actions();
  @override
  final identity = ScooterIdentity();
  @override
  final vehicle = VehicleStatus()
    ..handlebarsLocked = true
    ..seatClosed = true
    ..vehicleState = ScooterVehicleState.standby;
  @override
  ScooterVehicleState? get vehicleState => vehicle.vehicleState;
  @override
  ScooterPowerState? get powerState => ScooterPowerState.running;
  @override
  bool? get handlebarsLocked => vehicle.handlebarsLocked;
  @override
  ScooterState? state = ScooterState.standby;
  @override
  bool connected = true;
  @override
  bool autoUnlock = false;
  @override
  bool keylessPaused = false;
  @override
  DateTime? keylessPendingSince;
  @override
  void setKeylessPaused(bool paused) => keylessPaused = paused;
  @override
  TripCounterSnapshot? tripCounter;
  @override
  TripCounterSnapshot? get cachedTripCounter => null;
  @override
  bool get scanning => false;
  @override
  Stream<HandlebarWarning> get actionWarnings => const Stream.empty();
  int stops = 0;
  Object? stopError;

  @override
  Future<void> stopAlarm() async {
    stops++;
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> lock(
      {bool checkHandlebars = true, bool confirmOpenSeat = false, EventSource source = EventSource.app}) async {}

  @override
  Future<void> unlock({bool checkHandlebars = true, EventSource source = EventSource.app}) async {}

  void changed() => notifyListeners();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mountHome(WidgetTester tester, _Service service) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
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
        home: const HomeScreen(forceOpen: true),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('only the sounding states count as a triggered alarm', () {
    expect(AlarmStatus.level1Triggered.isTriggered, isTrue);
    expect(AlarmStatus.level2Triggered.isTriggered, isTrue);
    for (final quiet in [
      AlarmStatus.disabled,
      AlarmStatus.disarmed,
      AlarmStatus.delayArmed,
      AlarmStatus.armed,
      AlarmStatus.seatboxAccess,
      AlarmStatus.unknown,
    ]) {
      expect(quiet.isTriggered, isFalse, reason: '$quiet is not sounding');
    }
  });

  testWidgets('a quiet alarm leaves the dashboard alone', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.armed;
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    expect(find.byType(AlarmBanner), findsNothing);
    expect(find.byType(AlarmBackdrop), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sounding alarm tints the dashboard and offers the one useful control', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.level2Triggered;
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    expect(find.byType(AlarmBackdrop), findsOneWidget, reason: 'the backdrop tints while it sounds');
    expect(find.byType(AlarmBanner), findsOneWidget);
    expect(find.text('Alarm triggered'), findsOneWidget);
    expect(find.text('Alarm sounding'), findsOneWidget, reason: 'the banner names the alarm state');

    await tester.tap(find.text('Stop alarm'));
    await tester.pump();
    expect(service.stops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopping a level 1 warning works the same way', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.level1Triggered;
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    expect(find.text('Warning sounded'), findsOneWidget);
    await tester.tap(find.text('Stop alarm'));
    await tester.pump();
    expect(service.stops, 1);
  });

  testWidgets('the banner clears once the alarm stops sounding', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.level2Triggered;
    addTearDown(service.dispose);
    await _mountHome(tester, service);
    expect(find.byType(AlarmBanner), findsOneWidget);

    service.vehicle.alarmStatus = AlarmStatus.armed;
    service.changed();
    await tester.pump();
    expect(find.byType(AlarmBanner), findsNothing);
    expect(find.byType(AlarmBackdrop), findsNothing);
  });

  testWidgets('a failed stop reports itself and leaves the banner usable', (tester) async {
    const channel = MethodChannel('PonnamKarthik/fluttertoast');
    final toasts = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'showToast') toasts.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final service = _Service()
      ..vehicle.alarmStatus = AlarmStatus.level2Triggered
      ..stopError = StateError('not connected');
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    await tester.tap(find.text('Stop alarm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.stops, 1);
    expect(toasts, hasLength(1));
    expect((toasts.single.arguments as Map)['msg'], 'Could not stop the alarm');
    expect(find.text('Stop alarm'), findsOneWidget, reason: 'the rider can try again');
    expect(tester.takeException(), isNull);
  });
}
