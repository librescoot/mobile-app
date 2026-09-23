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
import 'package:unustasis/ui/screens/navigation_screen.dart';
import 'package:unustasis/ui/widgets/state_circle.dart';

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
  final identity = ScooterIdentity()..supportsAlarmControl = true;
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
  String? currentScooterId = 'A';
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
  bool? tripCounterSupported;
  @override
  TripCounterSnapshot? get cachedTripCounter => null;
  @override
  bool get scanning => false;
  @override
  Stream<HandlebarWarning> get actionWarnings => const Stream.empty();
  int stops = 0;
  Object? stopError;

  @override
  Future<void> disarmAlarm() async {
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

    expect(find.byType(StateCircle), findsNothing, reason: 'the circle stays a dark-mode flourish');
    expect(find.text('Stop alarm'), findsNothing);
    expect(find.text('Armed'), findsNothing, reason: 'the status line stays about the scooter');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sounding alarm pulses the circle and names it in the status line', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.level2Triggered;
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    final circle = tester.widget<StateCircle>(find.byType(StateCircle));
    expect(circle, isNotNull);
    expect(find.text('Alarm sounding'), findsOneWidget, reason: 'the status line says what is happening');
    expect(find.text('Stop alarm'), findsOneWidget, reason: 'the power button becomes the stop control');
    expect(find.text('Unlock'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the circle is showing the alarm, not just decorating', (tester) async {
    final quiet = _Service()..vehicle.alarmStatus = AlarmStatus.armed;
    addTearDown(quiet.dispose);
    await _mountHome(tester, quiet);
    expect(find.byType(StateCircle), findsNothing);

    final alarming = _Service()..vehicle.alarmStatus = AlarmStatus.level1Triggered;
    addTearDown(alarming.dispose);
    await _mountHome(tester, alarming);
    // The circle only appears for the alarm in light mode, so its presence is
    // the alarm state showing through.
    expect(find.byType(StateCircle), findsOneWidget);
    expect(find.text('Warning sounded'), findsOneWidget);
    expect(find.text('Stop alarm'), findsOneWidget);
  });

  testWidgets('an unprobed capability still offers the stop control', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.level2Triggered;
    service.identity.supportsAlarmControl = null;
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    expect(find.text('Stop alarm'), findsOneWidget,
        reason: 'a sounding alarm with an unknown capability is still stoppable');
  });

  testWidgets('a scooter that cannot take alarm commands gets no stop control', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.level2Triggered;
    service.identity.supportsAlarmControl = false;
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    // The state is still reported: the rider should know it is sounding.
    expect(find.text('Alarm sounding'), findsOneWidget);
    expect(find.byType(StateCircle), findsOneWidget);
    // But the button must not offer a command the firmware cannot take.
    expect(find.text('Stop alarm'), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the stop control silences the alarm', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.level2Triggered;
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    await tester.tapAt(tester.getCenter(find.byType(ScooterPowerButton)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(service.stops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the alarm treatment clears once the alarm stops sounding', (tester) async {
    final service = _Service()..vehicle.alarmStatus = AlarmStatus.level2Triggered;
    addTearDown(service.dispose);
    await _mountHome(tester, service);
    expect(find.text('Stop alarm'), findsOneWidget);

    service.vehicle.alarmStatus = AlarmStatus.armed;
    service.changed();
    await tester.pump();
    expect(find.text('Stop alarm'), findsNothing);
    expect(find.byType(StateCircle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation availability does not move the main controls', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    final cue = find.byKey(const ValueKey('home-navigation-cue'));
    expect(tester.widget<Visibility>(cue).visible, isFalse);
    final controlCenter = tester.getCenter(find.byType(ScooterPowerButton));

    service.identity.supportsNavigation = true;
    service.changed();
    await tester.pump();

    expect(tester.widget<Visibility>(cue).visible, isTrue);
    expect(tester.getCenter(find.byType(ScooterPowerButton)), controlCenter);
  });

  testWidgets('navigation swipe is disabled without the capability', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _mountHome(tester, service);

    await tester.fling(find.byType(HomeScreen), const Offset(0, -200), 1000);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NavigationScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed stop reports itself and leaves the control usable', (tester) async {
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

    await tester.tapAt(tester.getCenter(find.byType(ScooterPowerButton)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(service.stops, 1);
    expect(toasts, hasLength(1));
    expect((toasts.single.arguments as Map)['msg'], 'Could not stop the alarm');
    expect(find.text('Stop alarm'), findsOneWidget, reason: 'the rider can try again');
    expect(tester.takeException(), isNull);
  });
}
