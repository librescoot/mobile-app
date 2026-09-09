import 'dart:async';

import 'package:flutter/material.dart';
import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/ui/dialogs/handlebar_lock_guidance.dart';
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
  int invalidations = 0;
  @override
  void invalidate() => invalidations++;
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  final _Actions actions = _Actions();
  @override
  final identity = ScooterIdentity();
  @override
  final vehicle = VehicleStatus()
    ..handlebarsLocked = false
    ..seatClosed = true
    ..vehicleState = ScooterVehicleState.shuttingDown;
  @override
  ScooterVehicleState? get vehicleState => vehicle.vehicleState;
  @override
  ScooterPowerState? get powerState => ScooterPowerState.running;
  @override
  bool? get handlebarsLocked => vehicle.handlebarsLocked;
  @override
  ScooterState? state = ScooterState.shuttingDown;
  @override
  bool connected = true;
  @override
  bool get scanning => false;
  final warnings = StreamController<HandlebarWarning>.broadcast(sync: true);
  @override
  Stream<HandlebarWarning> get actionWarnings => warnings.stream;
  int commands = 0;
  int emittedWarnings = 0;
  bool disposed = false;
  void warn() {
    emittedWarnings++;
    warnings.add(const HandlebarWarning(
      ActionEvent(scooterId: 'A', generation: 1, kind: EventType.lock, source: EventSource.app),
    ));
  }
  @override
  Future<void> lock(
      {bool checkHandlebars = true, bool confirmOpenSeat = false, EventSource source = EventSource.app}) async {
    commands++;
  }

  @override
  Future<void> unlock({bool checkHandlebars = true, EventSource source = EventSource.app}) async {
    commands++;
  }

  void changed() => notifyListeners();
  @override
  void dispose() {
    disposed = true;
    unawaited(warnings.close());
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _lifecycle(WidgetTester tester, AppLifecycleState state) => tester.binding.handleAppLifecycleStateChanged(state);

void _background(WidgetTester tester) {
  _lifecycle(tester, AppLifecycleState.inactive);
  _lifecycle(tester, AppLifecycleState.hidden);
  _lifecycle(tester, AppLifecycleState.paused);
}

Future<void> _mountHome(WidgetTester tester, _Service service, {AppLifecycleState? initialLifecycle}) async {
  _lifecycle(tester, AppLifecycleState.resumed);
  addTearDown(() => _lifecycle(tester, AppLifecycleState.resumed));
  var initialized = false;
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
    value: service,
    child: EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.light,
        child: MaterialApp(
          localizationsDelegates: [
            FlutterI18nDelegate(
                translationLoader: FileTranslationLoader(
                    basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en'))),
          ],
          home: Builder(builder: (_) {
            if (!initialized) {
              initialized = true;
              if (initialLifecycle != null) _lifecycle(tester, initialLifecycle);
            }
            return const HomeScreen(forceOpen: true);
          }),
        )),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _finish(WidgetTester tester, _Service service) async {
  expect(service.commands, 0);
  expect(service.actions.invalidations, 0);
  expect(service.handlebarsLocked, false);
  expect(service.state, ScooterState.shuttingDown);
  await tester.pumpWidget(const SizedBox());
  if (!service.disposed) service.dispose();
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Home drops delayed warning after background without resurrecting on resume', (tester) async {
    final service = _Service();
    await _mountHome(tester, service);
    // Reproduce the existing awaited five-second warning without native BLE.
    Timer(const Duration(seconds: 5), service.warn);
    _background(tester);
    (tester.binding as AutomatedTestWidgetsFlutterBinding).elapseBlocking(const Duration(seconds: 5));
    await tester.idle(); // Deliver the delayed event, but do not mount an overlay frame.
    expect(service.emittedWarnings, 1);
    expect(find.byType(HandlebarLockGuidance), findsNothing);
    _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(HandlebarLockGuidance), findsNothing);
    await tester.pump(const Duration(seconds: 50));
    expect(find.byType(HandlebarLockGuidance), findsNothing);
    await _finish(tester, service);
  });

  for (final mounted in [false, true]) {
    testWidgets('Home removes ${mounted ? 'mounted' : 'inserted but unmounted'} guidance on departure', (tester) async {
      final service = _Service();
      await _mountHome(tester, service);
      service.warn();
      if (mounted) {
        await tester.pump();
        expect(find.byType(HandlebarLockGuidance), findsOneWidget);
      } else {
        expect(find.byType(HandlebarLockGuidance), findsNothing);
      }
      _background(tester);
      // No overlay frame between insertion and lifecycle departure/resume.
      _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(HandlebarLockGuidance), findsNothing);
      await tester.pump(const Duration(seconds: 50));
      expect(find.byType(HandlebarLockGuidance), findsNothing);
      await _finish(tester, service);
    });
  }

  for (final initial in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
    testWidgets('Home initialized $initial suppresses warning before resume', (tester) async {
      final service = _Service();
      await _mountHome(tester, service, initialLifecycle: initial);
      service.warn();
      _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(HandlebarLockGuidance), findsNothing);
      await _finish(tester, service);
    });
  }

  testWidgets('Home preserves guidance and permits new warnings during transient inactive', (tester) async {
    final service = _Service();
    await _mountHome(tester, service);
    service.warn();
    await tester.pump();
    _lifecycle(tester, AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(HandlebarLockGuidance), findsOneWidget);
    service.warn();
    await tester.pump();
    expect(find.byType(HandlebarLockGuidance), findsOneWidget);
    _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(HandlebarLockGuidance), findsOneWidget);
    await _finish(tester, service);
  });

  for (final end in ['stream closure', 'generation replacement', 'disconnect', 'service disposal', 'Home disposal']) {
    testWidgets('actual Home $end permanently removes guidance without effects', (tester) async {
      final service = _Service();
      await _mountHome(tester, service);
      service.warn();
      await tester.pump();
      expect(find.byType(HandlebarLockGuidance), findsOneWidget);
      expect(find.textContaining('Turn the handlebars fully left'), findsOneWidget);
      switch (end) {
        case 'stream closure':
          await service.warnings.close();
        case 'generation replacement':
          service.actions.session.currentConnection = _Connection()..generation = 2;
          service.changed();
        case 'disconnect':
          service.connected = false;
          service.changed();
        case 'service disposal':
          service.dispose();
          await tester.idle();
        case 'Home disposal':
          await tester.pumpWidget(const SizedBox());
          service.warn(); // The disposed owner no longer subscribes.
      }
      await tester.pump();
      expect(find.byType(HandlebarLockGuidance), findsNothing);
      _background(tester);
      _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      // A replacement session or reconnected transport must not restore the
      // old guidance even while telemetry still says unlocked.
      if (!service.disposed) {
        service.connected = true;
        service.changed();
      }
      await tester.pump(const Duration(seconds: 50));
      expect(find.byType(HandlebarLockGuidance), findsNothing);
      await _finish(tester, service);
    });
  }
}
